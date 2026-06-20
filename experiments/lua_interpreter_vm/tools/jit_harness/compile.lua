-- compile.lua
-- Compiles Lua source into the Moonlift Lua VM bytecode bundle used by the harness.
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.4

local M = {}
local util = require("tools.jit_harness.util")
local bit = require("bit")

local compiler_state = nil

local function install_experiment_package_path(repo_root)
    repo_root = repo_root or util.find_repo_root(".")
    if repo_root then
        local prefix = repo_root .. "/?.lua;" .. repo_root .. "/?/init.lua;" .. repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;"
        if not package.path:find(repo_root .. "/%?%.lua", 1, true) then
            package.path = prefix .. package.path
        end
    end
end

local function reverse_opcodes(const)
    local rev = {}
    if const and const.Op then
        for name, id in pairs(const.Op) do rev[id] = name end
    end
    return rev
end

local function decode_word(word, opcode_names)
    word = tonumber(word) or 0
    local op = bit.band(word, 127)
    local bx = bit.band(bit.rshift(word, 15), 131071)
    return {
        pc = 0, -- caller patches
        opcode = op,
        op = opcode_names[op] or tostring(op),
        name = opcode_names[op] or tostring(op),
        word = word,
        encoding = word,
        format = "packed",
        a = bit.band(bit.rshift(word, 7), 255),
        b = bit.band(bit.rshift(word, 16), 255),
        c = bit.band(bit.rshift(word, 24), 255),
        k = bit.band(bit.rshift(word, 15), 1),
        bx = bx,
        sbx = bx - 65535,
        ax = bit.rshift(word, 7),
    }
end
M.decode_word = decode_word

local function init_real_compiler(config)
    if compiler_state ~= nil then return compiler_state end
    config = config or {}
    local repo_root = config.repo_root or util.find_repo_root(".")
    if repo_root then repo_root = util.abspath(repo_root) end
    install_experiment_package_path(repo_root)

    local lfs_ok, lfs = pcall(require, "lfs")
    local old_cwd = lfs_ok and lfs.currentdir and lfs.currentdir() or nil
    if not old_cwd then
        local p = io.popen("pwd", "r")
        old_cwd = p and p:read("*l") or nil
        if p then p:close() end
    end
    local ffi_for_chdir = nil
    if not (lfs_ok and lfs.chdir) then
        local ok_ffi, ffi = pcall(require, "ffi")
        if ok_ffi then
            pcall(ffi.cdef, "int chdir(const char *path);")
            ffi_for_chdir = ffi
        end
    end
    if repo_root then
        -- moonlift.back_jit/back_object probe ./target/... relative to cwd.
        if lfs_ok and lfs.chdir then lfs.chdir(repo_root)
        elseif ffi_for_chdir then ffi_for_chdir.C.chdir(repo_root) end
    end

    local ok, state_or_err = pcall(function()
        local ffi = require("ffi")
        local moon = require("moonlift")
        local vm = require("experiments.lua_interpreter_vm.src.init")

        require("experiments.lua_interpreter_vm.tools.vm_ffi_schema").apply(ffi)

        local compile_region = vm.regions_compiler.compile_lua_source_into
        local wrapper = moon.func { compile_lua_source_into = compile_region } [[
compile_text_for_jit_harness(cu: ptr(CompileUnit), b: ptr(FuncBuilder), p: ptr(Proto), bytes: ptr(u8), n: index, code: ptr(Instr), code_cap: index, locals: ptr(CompileLocal), locals_cap: index, workspace: ptr(u8), workspace_cap: index): i32
    return region: i32
    entry start()
        emit @{compile_lua_source_into}(cu, b, p, bytes, n, code, code_cap, locals, locals_cap, workspace, workspace_cap;
            ok = ok,
            syntax_error = syntax_bad,
            semantic_error = semantic_bad,
            limit_error = limit_bad,
            oom = oom_bad)
    end
    block ok(proto: ptr(Proto)) yield as(i32, proto.code_len) end
    block syntax_bad(err: CompileError) yield 0 - err.code end
    block semantic_bad(err: CompileError) yield -100 - err.code end
    block limit_bad(err: CompileError) yield -200 - err.code end
    block oom_bad() yield -999 end
    end
end
]]

        return {
            ffi = ffi,
            vm = vm,
            compiled = assert(wrapper:compile()),
            opcode_names = reverse_opcodes(vm.const),
        }
    end)

    if old_cwd then
        if lfs_ok and lfs.chdir then lfs.chdir(old_cwd)
        elseif ffi_for_chdir then ffi_for_chdir.C.chdir(old_cwd) end
    end

    if ok then
        compiler_state = state_or_err
    else
        compiler_state = { unavailable = true, error = tostring(state_or_err), opcode_names = {} }
    end
    return compiler_state
end

function M.compiler_available(config)
    local st = init_real_compiler(config)
    return not st.unavailable, st.error
end

local function compile_with_real_compiler(source, name, config)
    local st = init_real_compiler(config)
    if st.unavailable then return nil, st.error end
    local ffi = st.ffi
    config = config or {}
    local code_cap = config.code_cap or 8192
    local locals_cap = config.locals_cap or 1024
    local workspace_cap = config.workspace_cap or (1024 * 1024)

    local cu = ffi.new("CompileUnit[1]")
    local b = ffi.new("FuncBuilder[1]")
    local p = ffi.new("Proto[1]")
    local code = ffi.new("Instr[?]", code_cap)
    local locals = ffi.new("CompileLocal[?]", locals_cap)
    local workspace = ffi.new("uint8_t[?]", workspace_cap)
    local bytes = ffi.new("uint8_t[?]", #source)
    ffi.copy(bytes, source, #source)

    local n = st.compiled(cu, b, p, bytes, #source, code, code_cap, locals, locals_cap, workspace, workspace_cap)
    if n < 0 then
        return nil, string.format("compile failed (%d)", n)
    end

    local instrs = {}
    for i = 0, n - 1 do
        local word = tonumber(code[i].word)
        local instr = decode_word(word, st.opcode_names)
        instr.pc = i
        instrs[#instrs + 1] = instr
    end

    return {
        id = util.stable_hash(name .. "\0" .. source),
        index = 1,
        code = instrs,
        code_len = #instrs,
        max_stack = tonumber(p[0].maxstack) or 0,
        num_params = tonumber(p[0].numparams) or 0,
        flag = tonumber(p[0].flag) or 0,
        constants_len = tonumber(p[0].constants_len) or 0,
        child_proto_count = tonumber(p[0].children_len) or 0,
        _workspace = workspace,
    }
end

local fallback_keywords = {
    ["return"] = "RETURN1", ["if"] = "TEST", ["then"] = "JMP", ["while"] = "JMP",
    ["for"] = "FORPREP", ["function"] = "CLOSURE", ["local"] = "MOVE",
}

local function compile_with_fallback(source, name)
    -- Conservative lexical fallback used only when the Moonlift VM compiler cannot be loaded.
    -- It preserves reproducible corpus/profiling behavior instead of pretending this is VM semantics.
    local code = {}
    local i = 1
    while i <= #source do
        local s, e, tok = source:find("([%a_][%w_]*)", i)
        local os_, oe, opchars = source:find("([%+%-%*/%%=<>~]+)", i)
        if s and (not os_ or s <= os_) then
            local op = fallback_keywords[tok]
            if op then code[#code + 1] = { pc = #code, op = op, name = op, opcode = op, word = 0, format = "fallback" } end
            i = e + 1
        elseif os_ then
            local op
            if opchars:find("+", 1, true) then op = "ADD"
            elseif opchars:find("-", 1, true) then op = "SUB"
            elseif opchars:find("*", 1, true) then op = "MUL"
            elseif opchars:find("/", 1, true) then op = "DIV"
            elseif opchars:find("=", 1, true) then op = "EQ"
            elseif opchars:find("<", 1, true) then op = "LT"
            elseif opchars:find(">", 1, true) then op = "LE" end
            if op then code[#code + 1] = { pc = #code, op = op, name = op, opcode = op, word = 0, format = "fallback" } end
            i = oe + 1
        else
            break
        end
    end
    if #code == 0 then code[1] = { pc = 0, op = "RETURN0", name = "RETURN0", opcode = "RETURN0", word = 0, format = "fallback" } end
    return {
        id = util.stable_hash("fallback\0" .. name .. "\0" .. source),
        index = 1,
        code = code,
        code_len = #code,
        fallback = true,
    }
end

function M.compile_lua_unit(unit, config)
    config = config or {}
    local path = unit.path or unit.file_path
    local source = unit.source
    if not source and path then
        local data, err = util.read_file(path)
        if not data then return nil, { stage = "COMPILE", reason = "IO_ERROR", detail = err, path = path } end
        source = data
    end
    if not source then return nil, { stage = "COMPILE", reason = "NO_SOURCE", detail = "unit has no source", path = path } end
    local name = unit.name or path or unit.id or "<string>"

    local proto, err
    if config.force_fallback then
        -- Explicit harness-only escape hatch. The VM source frontier never uses
        -- this token fallback, and default harness compilation now reports real
        -- source compiler failure instead of fabricating bytecode products.
        proto = compile_with_fallback(source, name)
    else
        proto, err = compile_with_real_compiler(source, name, config)
    end
    if not proto then
        return nil, { stage = "COMPILE", reason = "COMPILE_ERROR", detail = err, path = path }
    end

    return {
        bundle_id = util.stable_hash("bundle\0" .. name .. "\0" .. source),
        source_unit = unit.id or unit.file_id or name,
        path = path,
        root_proto = proto.id,
        protos = { proto },
        constants = {},
        compiler = proto.fallback and "fallback-token" or "moonlift-lua-vm",
        compiler_config_hash = util.stable_hash(util.to_json(config)),
    }
end

function M.compile_file(path, config)
    local data, err = util.read_file(path)
    if not data then return nil, { stage = "COMPILE", reason = "IO_ERROR", detail = err, path = path } end
    return M.compile_lua_unit({ path = path, name = util.basename(path), source = data }, config)
end

function M.dump_proto_bundle(bundle, path)
    return util.write_json(path, bundle)
end

function M.read_proto_bundle(path)
    -- JSON decoding is intentionally not implemented in the harness core yet.
    -- Return the raw persisted artifact so callers can archive/replay externally.
    local data, err = util.read_file(path)
    if not data then return nil, err end
    return { path = path, raw = data }
end

function M.compile_units(units, config)
    local db = { bundles = {}, rejects = {}, total = #(units or {}), compiled = 0, failed = 0, fallback_compiled = 0 }
    for _, unit in ipairs(units or {}) do
        local bundle, reject = M.compile_lua_unit(unit, config)
        if bundle then
            db.compiled = db.compiled + 1
            if bundle.compiler == "fallback-token" then db.fallback_compiled = db.fallback_compiled + 1 end
            db.bundles[#db.bundles + 1] = bundle
        else
            db.failed = db.failed + 1
            db.rejects[#db.rejects + 1] = reject
        end
    end
    return db
end

return M
