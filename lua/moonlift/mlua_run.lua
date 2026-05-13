-- moonlift/mlua_run.lua — .mlua runner using scan_document + parse_island.
--
-- A .mlua file is Lua with MoonLift value islands.  scan_document produces
-- the authoritative token stream and island descriptors.  The runtime generates
-- a Lua carrier that calls eval_island by island index.  No source slicing,
-- no regex probes, no module assembly.

local ffi       = require("ffi")
local pvm       = require("moonlift.pvm")
local A         = require("moonlift.asdl")
local Quote     = require("moonlift.quote")
local Session   = require("moonlift.host_session")
local HostValues= require("moonlift.host_values")
local Parse     = require("moonlift.parse")
local SourceMap = require("moonlift.source_map")
local Diag      = require("moonlift.diagnostic")

local M = {}

---------------------------------------------------------------------------
-- Runtime
---------------------------------------------------------------------------

local Runtime = {}; Runtime.__index = Runtime

local FuncValue = {}; FuncValue.__index = FuncValue
local Deps = { __mode = "k" }
local deps_of_value = setmetatable({}, Deps)

local runtime_stack = {}

local function push_runtime(runtime)
    runtime_stack[#runtime_stack + 1] = runtime
    return function()
        assert(runtime_stack[#runtime_stack] == runtime, "moonlift runtime stack imbalance")
        runtime_stack[#runtime_stack] = nil
    end
end

function M.current_runtime() return runtime_stack[#runtime_stack] end
function M._push_runtime(runtime) return push_runtime(runtime) end

local function new_context()
    local T = pvm.context(); A.Define(T); return T
end

---------------------------------------------------------------------------
-- Error diagnostics: phase + source mapping + snippets
---------------------------------------------------------------------------

local function build_line_starts(src)
    return SourceMap.index(src)
end

local function line_col_of_offset(line_index, offset)
    return SourceMap.line_col(line_index, offset)
end

local function render_snippet(_src_ignored, line_index, line_no, ctx)
    return SourceMap.snippet(line_index, line_no, ctx)
end

local function map_generated_line(runtime, lua_line)
    if not runtime or not runtime.carrier_map or not lua_line then return nil end
    return SourceMap.lookup_generated(runtime.carrier_map, lua_line)
end

local function format_report(opts)
    return Diag.new(opts)
end

local function format_phase_exception(runtime, phase, err, extra)
    local diag = Diag.from_error(err, {
        phase = phase,
        file = runtime and runtime.chunk_name,
    })
    if diag.phase and diag.phase ~= phase then
        diag.envelope_phase = phase
    else
        diag.phase = phase
    end

    local mapped = map_generated_line(runtime, diag.generated_line)
    diag.src_line = (extra and extra.src_line) or diag.src_line or (mapped and mapped.src_line)
    diag.src_col = (extra and extra.src_col) or diag.src_col or (mapped and mapped.src_col) or 1
    diag.island_index = (extra and extra.island_index) or diag.island_index or (mapped and mapped.island_index)
    diag.island_kind = (extra and extra.island_kind) or diag.island_kind or (mapped and mapped.island_kind)

    if (not diag.generated_path) and diag.generated_source then
        diag.generated_path = Diag.write_temp_generated(diag.generated_source)
    end

    if runtime and runtime.line_starts and diag.src_line and not diag.snippet then
        diag.snippet = SourceMap.snippet(runtime.line_starts, diag.src_line, 2)
    end

    return diag
end

local function format_parse_issue(runtime, phase, issue, extra)
    local src_line = tonumber(issue and issue.line) or nil
    local src_col = tonumber(issue and issue.col) or 1
    if (not src_line or src_line <= 0) and issue and issue.offset then
        src_line, src_col = line_col_of_offset(runtime.line_starts, tonumber(issue.offset) or 1)
    end

    return Diag.new({
        phase = phase,
        file = runtime and runtime.chunk_name,
        island_index = extra and extra.island_index,
        island_kind = extra and extra.island_kind,
        src_line = src_line,
        src_col = src_col,
        message = issue and issue.message or tostring(issue),
        hint = Diag.detect_hint(issue and issue.message or issue),
        snippet = SourceMap.snippet(runtime.line_starts, src_line, 2),
    })
end

local function island_context(runtime, island_index)
    local island = runtime and runtime.scan and runtime.scan.islands and runtime.scan.islands[island_index]
    if not island then return { island_index = island_index } end
    local line, col = line_col_of_offset(runtime.line_starts, island.start)
    return {
        island_index = island_index,
        island_kind = island.kind,
        src_line = line,
        src_col = col,
    }
end

---------------------------------------------------------------------------
-- C type helpers
---------------------------------------------------------------------------

local scalar_ctype = {
    BackBool = "bool", BackI8 = "int8_t", BackI16 = "int16_t", BackI32 = "int32_t", BackI64 = "int64_t",
    BackU8 = "uint8_t", BackU16 = "uint16_t", BackU32 = "uint32_t", BackU64 = "uint64_t",
    BackF32 = "float", BackF64 = "double", BackPtr = "void *", BackIndex = "intptr_t", BackVoid = "void",
}

local function back_scalar_name(scalar)
    return tostring(scalar):match("%.([%w_]+):") or tostring(scalar):match("(Back[%w_]+)") or tostring(scalar)
end

local function ctype_of_type(T, ty)
    local Ty = T.MoonType
    if pvm.classof(ty) == Ty.TPtr then return "void *" end
    local Back = require("moonlift.type_to_back_scalar").Define(T)
    local r = Back.result(ty)
    if pvm.classof(r) ~= Ty.TypeBackScalarKnown then return "void *" end
    return assert(scalar_ctype[back_scalar_name(r.scalar)], "unsupported C type: " .. tostring(r.scalar))
end

local function c_sig_of(T, func)
    local Ty = T.MoonType
    local args = {}
    local result_is_view = pvm.classof(func.result) == Ty.TView
    if result_is_view then args[#args + 1] = "void *" end
    for i = 1, #func.params do args[#args + 1] = ctype_of_type(T, func.params[i].ty) end
    local ret = result_is_view and "void" or ctype_of_type(T, func.result)
    return ret .. " (*)(" .. table.concat(args, ", ") .. ")"
end

---------------------------------------------------------------------------
-- Dependency tracking
---------------------------------------------------------------------------

local function empty_deps() return { type_decls = {}, region_frags = {}, expr_frags = {} } end

local function merge_deps(a, b)
    local out = { type_decls = {}, region_frags = {}, expr_frags = {} }
    for _, v in ipairs(a.type_decls or {}) do out.type_decls[#out.type_decls + 1] = v end
    for _, v in ipairs(b.type_decls or {}) do out.type_decls[#out.type_decls + 1] = v end
    for _, v in ipairs(a.region_frags or {}) do out.region_frags[#out.region_frags + 1] = v end
    for _, v in ipairs(b.region_frags or {}) do out.region_frags[#out.region_frags + 1] = v end
    for _, v in ipairs(a.expr_frags or {}) do out.expr_frags[#out.expr_frags + 1] = v end
    for _, v in ipairs(b.expr_frags or {}) do out.expr_frags[#out.expr_frags + 1] = v end
    return out
end

local function track_deps(value, deps) deps_of_value[value] = deps end

local function deps_of(value)
    local d = deps_of_value[value]
    if d then return d end
    return empty_deps()
end

local function collect_closure_deps(luamap)
    local deps = empty_deps()
    for _, rec in pairs(luamap or {}) do
        if rec.present then
            deps = merge_deps(deps, deps_of(rec.value))
        end
    end
    return deps
end

---------------------------------------------------------------------------
-- FuncValue
---------------------------------------------------------------------------

local function func_type(T, params, result)
    local tys = {}
    for i = 1, #(params or {}) do tys[i] = params[i].ty end
    return T.MoonType.TFunc(tys, result)
end

local function internal_module_for_func(T, func, deps, name)
    local Tr = T.MoonTree
    local items = {}
    -- Add type deps as ItemType
    for _, td in ipairs(deps.type_decls or {}) do
        items[#items + 1] = Tr.ItemType(td.decl)
    end
    items[#items + 1] = Tr.ItemFunc(func)
    return Tr.Module(Tr.ModuleSurface, items)
end

local CompiledFunction = {}; CompiledFunction.__index = CompiledFunction

-- Select backend: MOONLIFT_BACKEND env var, default "cranelift"
local function select_backend(T)
    local name = (os.getenv("MOONLIFT_BACKEND") or "cranelift"):lower()
    if name == "dynasm" then
        return require("back.dasm.init").Define(T)
    elseif name == "cranelift" then
        return require("moonlift.back_jit").Define(T)
    else
        error("unknown MOONLIFT_BACKEND: " .. tostring(name) .. " (try dynasm or cranelift)", 2)
    end
end

function FuncValue:compile()
    local T = self.T
    local Typecheck = require("moonlift.tree_typecheck").Define(T)
    local Layout = require("moonlift.sem_layout_resolve").Define(T)
    local TreeToBack = require("moonlift.tree_to_back").Define(T)
    local Validate = require("moonlift.back_validate").Define(T)
    local Tr = T.MoonTree

    local deps = deps_of(self) or empty_deps()
    local mod = internal_module_for_func(T, self.func, deps, self.name)

    local checked = Typecheck.check_module(mod)
    if #checked.issues ~= 0 then error("func " .. tostring(self.name) .. " typecheck failed: " .. tostring(checked.issues[1]), 2) end

    -- Extract the function from the checked module
    local checked_func
    for i = 1, #checked.module.items do
        if pvm.classof(checked.module.items[i]) == Tr.ItemFunc then
            checked_func = checked.module.items[i].func
            break
        end
    end
    if not checked_func then error("internal: no func in compiled module", 2) end

    local resolved = Layout.module(checked.module)
    local program = TreeToBack.module(resolved)
    if not program then error("tree_to_back produced nil module", 2) end

    -- Convert BackProgram ASDL to flat cmd table for dynasm
    local flat
    if type(program) == "table" and program.cmds then
        flat = program
    else
        flat = { cmds = {} }
        for i = 1, #program do
            flat.cmds[#flat.cmds + 1] = program[i]
        end
    end

    local J = select_backend(T)
    local artifact = J.jit():compile(flat)
    local c_sig = c_sig_of(T, checked_func)
    local ptr = artifact:getpointer(T.MoonBack.BackFuncId(self.name))

    local wrapped = setmetatable({
        func = checked_func, fn = ffi.cast(c_sig, ptr), c_sig = c_sig,
        artifact = artifact, T = T,
    }, CompiledFunction)
    self._compiled = wrapped
    return wrapped
end

function CompiledFunction:__call(...)
    if not self.artifact then error("compiled Moonlift function called after artifact was freed", 2) end
    return self.fn(...)
end

function CompiledFunction:free()
    if self.artifact then self.artifact:free(); self.artifact = nil end
end

function CompiledFunction:__tostring()
    return "CompiledMoonFunction(" .. tostring(self.func.name) .. ": " .. tostring(self.c_sig) .. ")"
end

---------------------------------------------------------------------------
-- eval_island
---------------------------------------------------------------------------

local function adopt_splice_value(runtime, value)
    if type(value) ~= "table" then return end
    local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
    if kind == "region_frag" and value.frag ~= nil then
        local n = value.name or (value.frag.name and value.frag.name.text)
        if n then runtime.region_frags[n] = value end
    elseif kind == "expr_frag" and value.frag ~= nil then
        local n = value.name or (value.frag.name and value.frag.name.text)
        if n then runtime.expr_frags[n] = value end
    end
end

function Runtime:eval_island(island_index, closures)
    local T = self.T
    local ParseApi = Parse.Define(T)
    local Splice = require("moonlift.host_splice")
    local Expand = require("moonlift.open_expand").Define(T)
    local ctx = island_context(self, island_index)

    local function phase_fail(phase, err)
        error(format_phase_exception(self, phase, err, ctx), 0)
    end

    -- 1. Evaluate Lua closures for splice values
    local luamap = {}
    for id, fn in pairs(closures or {}) do
        local ok, val = pcall(fn)
        if not ok then
            local snippet = render_snippet(self.src, self.line_starts, ctx.src_line, 2)
            error(format_report({
                phase = "splice_eval",
                file = self.chunk_name,
                island_index = ctx.island_index,
                island_kind = ctx.island_kind,
                src_line = ctx.src_line,
                src_col = ctx.src_col,
                message = "splice " .. tostring(id) .. " evaluation failed: " .. tostring(val),
                hint = Diag.detect_hint(val),
                snippet = snippet,
            }), 0)
        end
        luamap[id] = {present = true, value = val}
        adopt_splice_value(self, val)
    end
    local closure_deps = collect_closure_deps(luamap)

    -- 2. Parse island from token window (no source slice)
    local parse_opts = {
        protocol_types = self.protocol_types,
    }
    local ok_parse, parsed_or_err = pcall(ParseApi.parse_island, self.scan, island_index, parse_opts)
    if not ok_parse then phase_fail("parse_island", parsed_or_err) end
    local parsed = parsed_or_err
    if #parsed.issues ~= 0 then
        error(format_parse_issue(self, "parse_island", parsed.issues[1], ctx), 0)
    end

    -- 3. Fill splice slots
    local bindings = {}
    for _, ss in ipairs(parsed.splice_slots) do
        local rec = luamap[ss.splice_id]
        if not rec or not rec.present then
            local snippet = render_snippet(self.src, self.line_starts, ctx.src_line, 2)
            error(format_report({
                phase = "splice_fill",
                file = self.chunk_name,
                island_index = ctx.island_index,
                island_kind = ctx.island_kind,
                src_line = ctx.src_line,
                src_col = ctx.src_col,
                message = "missing splice value for " .. tostring(ss.splice_id),
                snippet = snippet,
            }), 0)
        end
        local ok_fill, binding_or_err = pcall(Splice.fill, self.session, ss.slot, rec.value, "splice " .. ss.splice_id)
        if not ok_fill then phase_fail("splice_fill", binding_or_err) end
        bindings[#bindings + 1] = binding_or_err
    end

    -- 4. Expand + wrap uniformly
    local ok_base_env, base_env_or_err = pcall(Expand.env_with_frags, self.region_frags, self.expr_frags)
    if not ok_base_env then phase_fail("expand_env", base_env_or_err) end
    local ok_env, env_or_err = pcall(Expand.env_with_fills, base_env_or_err, bindings)
    if not ok_env then phase_fail("expand_env", env_or_err) end
    local env = env_or_err

    if parsed.kind == "region" then
        local ok_expand, expanded_or_err = pcall(Expand.expand_region_frag, parsed.value, env)
        if not ok_expand then phase_fail("expand_region", expanded_or_err) end
        local ok_value, value_or_err = pcall(HostValues.region_frag_value, self.session, expanded_or_err, {})
        if not ok_value then phase_fail("wrap_region", value_or_err) end
        self.region_frags[value_or_err.name] = value_or_err
        track_deps(value_or_err, closure_deps)
        return value_or_err

    elseif parsed.kind == "expr" then
        local ok_expand, expanded_or_err = pcall(Expand.expand_expr_frag, parsed.value, env)
        if not ok_expand then phase_fail("expand_expr", expanded_or_err) end
        local ok_value, value_or_err = pcall(HostValues.expr_frag_value, self.session, expanded_or_err)
        if not ok_value then phase_fail("wrap_expr", value_or_err) end
        self.expr_frags[value_or_err.name] = value_or_err
        track_deps(value_or_err, closure_deps)
        return value_or_err

    elseif parsed.kind == "func" then
        -- Expand by wrapping in internal module
        local Tr = T.MoonTree
        local deps = merge_deps(closure_deps, deps_of(self))
        local raw_mod = internal_module_for_func(T, parsed.value, deps, parsed.value.name)
        local ok_mod, expanded_mod_or_err = pcall(Expand.expand_module, raw_mod, env)
        if not ok_mod then phase_fail("expand_func", expanded_mod_or_err) end

        -- Extract the expanded function
        local expanded_func
        for i = 1, #expanded_mod_or_err.items do
            if pvm.classof(expanded_mod_or_err.items[i]) == Tr.ItemFunc then
                expanded_func = expanded_mod_or_err.items[i].func
                break
            end
        end
        if not expanded_func then
            error(format_report({
                phase = "expand_func",
                file = self.chunk_name,
                island_index = ctx.island_index,
                island_kind = ctx.island_kind,
                src_line = ctx.src_line,
                src_col = ctx.src_col,
                message = "func island did not produce a function after expansion",
                snippet = render_snippet(self.src, self.line_starts, ctx.src_line, 2),
            }), 0)
        end

        local value = setmetatable({
            kind = "func", name = expanded_func.name, func = expanded_func,
            T = T, runtime = self,
        }, FuncValue)
        track_deps(value, deps)
        return value

    elseif parsed.kind == "struct" or parsed.kind == "union" then
        -- TypeDeclValue
        local td = parsed.value
        local Ty = T.MoonType
        local ty = Ty.TNamed(Ty.TypeRefPath(T.MoonCore.Path({ T.MoonCore.Name(td.name) })))

        local ok_decl, expanded_decl_or_err = pcall(Expand.expand_type_decl, td.decl, env)
        if not ok_decl then phase_fail("expand_type_decl", expanded_decl_or_err) end

        -- Register protocol variants
        if td.protocol_variants then
            self.protocol_types[td.name] = td.protocol_variants
        end

        local api = self.session:api()
        local ok_value, value_or_err = pcall(api.type_from_asdl, ty, td.name, {
            decl = expanded_decl_or_err,
            protocol_variants = td.protocol_variants,
        })
        if not ok_value then phase_fail("wrap_type_decl", value_or_err) end
        track_deps(value_or_err, merge_deps(closure_deps, { type_decls = { td } }))
        return value_or_err

    else
        error(format_report({
            phase = "eval_island",
            file = self.chunk_name,
            island_index = ctx.island_index,
            island_kind = ctx.island_kind,
            src_line = ctx.src_line,
            src_col = ctx.src_col,
            message = "unsupported island kind: " .. tostring(parsed.kind),
            snippet = render_snippet(self.src, self.line_starts, ctx.src_line, 2),
        }), 0)
    end
end

---------------------------------------------------------------------------
-- Simple require (Lua-first modules)
---------------------------------------------------------------------------

local function module_path_candidates(runtime, name)
    local rel = tostring(name):gsub("%.", "/")
    local patterns = runtime.module_path_patterns or {"mlua/?.mlua", "mlua/?/init.mlua", "?.mlua", "?/init.mlua"}
    local out = {}
    for i = 1, #patterns do out[#out + 1] = (patterns[i]:gsub("%?", rel)) end
    return out
end

function Runtime:require(name)
    self.require_cache = self.require_cache or {}
    if self.require_cache[name] == false then error("circular moon.require for " .. tostring(name), 2) end
    if self.require_cache[name] ~= nil then return self.require_cache[name] end
    for _, path in ipairs(module_path_candidates(self, name)) do
        local f = io.open(path, "rb")
        if f then
            f:close()
            self.require_cache[name] = false
            local ok, loaded_or_err = pcall(function()
                local fn = assert(M.loadfile(path, {runtime = self}))
                return fn()
            end)
            if not ok then self.require_cache[name] = nil; error(loaded_or_err, 2) end
            self.require_cache[name] = loaded_or_err
            return loaded_or_err
        end
    end
    error("moon.require could not find " .. tostring(name), 2)
end

---------------------------------------------------------------------------
-- Loadstring
---------------------------------------------------------------------------

function M.loadstring(src, chunk_name, opts)
    opts = opts or {}
    local parent = opts.runtime
    local T = opts.T or (parent and parent.T) or new_context()
    local session = opts.session or (parent and parent.session)
        or Session.new({prefix = opts.prefix or "mlua", T = T})

    local file_name = chunk_name or "=(moonlift.mlua_run)"
    local line_starts = build_line_starts(src)

    -- Scan the document once, authoritatively.
    local ok_scan, scan_or_err = pcall(Parse.scan_document, src)
    if not ok_scan then
        local pseudo_runtime = {
            src = src,
            line_starts = line_starts,
            chunk_name = file_name,
        }
        error(format_phase_exception(pseudo_runtime, "scan_document", scan_or_err, {}), 0)
    end
    local scan = scan_or_err

    local runtime = setmetatable({
        T = T,
        session = session,
        scan = scan,
        src = src,
        chunk_name = file_name,
        line_starts = line_starts,
        carrier_map = SourceMap.new_carrier_map(1),
        region_frags = opts.region_frags or (parent and parent.region_frags) or {},
        expr_frags = opts.expr_frags or (parent and parent.expr_frags) or {},
        protocol_types = opts.protocol_types or (parent and parent.protocol_types) or {},
        require_cache = opts.require_cache or (parent and parent.require_cache) or {},
        require_stack = opts.require_stack or (parent and parent.require_stack) or {},
        module_path_patterns = opts.module_path_patterns or opts.module_paths
            or (parent and parent.module_path_patterns),
    }, Runtime)

    local q = Quote()
    local rt = q:val(runtime, "runtime")

    local function emit_block(text, map_fn)
        q(text)
        SourceMap.carrier_emit(runtime.carrier_map, text, map_fn)
    end

    local function emit_source_segment(text, src_offset)
        local start_line, start_col = line_col_of_offset(line_starts, src_offset)
        emit_block(text, function(i)
            return {
                src_line = start_line + (i - 1),
                src_col = (i == 1) and start_col or 1,
                origin = "source",
            }
        end)
    end

    emit_block("return function(...)", function() return { origin = "carrier_prelude" } end)
    emit_block(string.format("local __moonlift_runtime = %s", rt), function() return { origin = "carrier_prelude" } end)
    emit_block("local moon = setmetatable({ require = function(name) return __moonlift_runtime:require(name) end }, { __index = __moonlift_runtime.session:api() })", function()
        return { origin = "carrier_prelude" }
    end)

    local cursor = 1
    for island_index, island in ipairs(scan.islands) do
        -- Emit Lua source between cursor and island start.
        local lua_part = src:sub(cursor, island.start - 1)
        if lua_part:match("%S") then
            emit_source_segment(lua_part, cursor)
        end

        -- Build closure table for this island's holes.
        local entries = {}
        for _, hid in ipairs(island.holes) do
            local expr = scan.splice_map[hid]
            if expr then
                entries[#entries + 1] = string.format("[%q] = function() return (%s) end", hid, expr)
            end
        end

        -- Emit eval_island call by island index, not by source slice.
        local island_line, island_col = line_col_of_offset(line_starts, island.start)
        emit_block(string.format("__moonlift_runtime:eval_island(%d, {%s})", island_index, table.concat(entries, ",")), function()
            return {
                src_line = island_line,
                src_col = island_col,
                island_index = island_index,
                island_kind = island.kind,
                origin = "island_dispatch",
            }
        end)

        cursor = island.stop + 1
    end

    -- Trailing Lua.
    local tail = src:sub(cursor)
    if tail:match("%S") then emit_source_segment(tail, cursor) end

    emit_block("end", function() return { origin = "carrier_prelude" } end)

    local ok_compile, inner_or_err, lua_src_or_nil = pcall(function()
        return q:compile(file_name)
    end)
    if not ok_compile then
        error(format_phase_exception(runtime, "compile_carrier", inner_or_err, {}), 0)
    end

    local inner = inner_or_err
    local lua_src = lua_src_or_nil

    local function fn(...)
        local pop = push_runtime(runtime)
        local function pack(ok, ...)
            return { ok, n = select("#", ...) + 1, ... }
        end
        local results = pack(pcall(inner, ...))
        pop()
        if not results[1] then
            error(format_phase_exception(runtime, "run_carrier", results[2], {}), 0)
        end
        return unpack(results, 2, results.n)
    end
    return fn, runtime, lua_src
end

function M.loadfile(path, opts)
    local f, ferr = io.open(path, "rb")
    if not f then
        error(format_report({
            phase = "loadfile",
            file = path,
            message = ferr or ("unable to open file " .. tostring(path)),
        }), 0)
    end
    local src = f:read("*a")
    f:close()
    return M.loadstring(src, path, opts)
end

function M.dofile(path, opts, ...)
    if type(opts) == "table" and (opts.runtime or opts.T or opts.session) then
        return assert(M.loadfile(path, opts))(...)
    end
    if not opts and path:match("%.mlua$") then
        local parent = M.current_runtime()
        if parent then
            return assert(M.loadfile(path, {runtime = parent}))(...)
        end
    end
    local fn = assert(M.loadfile(path))
    return fn(opts, ...)
end

function M.eval(src, chunk_name, ...)
    return assert(M.loadstring(src, chunk_name or "=(moonlift.eval)"))(...)
end

return M
