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

-- Select backend: MOONLIFT_BACKEND env var, default "dynasm"
local function select_backend(T)
    local name = (os.getenv("MOONLIFT_BACKEND") or "dynasm"):lower()
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

    -- 1. Evaluate Lua closures for splice values
    local luamap = {}
    for id, fn in pairs(closures or {}) do
        local ok, val = pcall(fn)
        if not ok then
            error("Moonlift splice eval failed at " .. id .. ": " .. tostring(val), 2)
        end
        luamap[id] = {present = true, value = val}
        adopt_splice_value(self, val)
    end
    local closure_deps = collect_closure_deps(luamap)

    -- 2. Parse island from token window (no source slice)
    local parse_opts = {
        protocol_types = self.protocol_types,
    }
    local parsed = ParseApi.parse_island(self.scan, island_index, parse_opts)
    if #parsed.issues ~= 0 then
        error("Moonlift parse failed: " .. tostring(parsed.issues[1]), 2)
    end

    -- 3. Fill splice slots
    local bindings = {}
    for _, ss in ipairs(parsed.splice_slots) do
        local rec = luamap[ss.splice_id]
        if not rec or not rec.present then
            error("missing splice value for " .. ss.splice_id, 2)
        end
        bindings[#bindings + 1] = Splice.fill(self.session, ss.slot, rec.value, "splice " .. ss.splice_id)
    end

    -- 4. Expand + wrap uniformly
    local base_env = Expand.env_with_frags(self.region_frags, self.expr_frags)
    local env = Expand.env_with_fills(base_env, bindings)

    if parsed.kind == "region" then
        local expanded = Expand.expand_region_frag(parsed.value, env)
        local value = HostValues.region_frag_value(self.session, expanded, {})
        self.region_frags[value.name] = value
        track_deps(value, closure_deps)
        return value

    elseif parsed.kind == "expr" then
        local expanded = Expand.expand_expr_frag(parsed.value, env)
        local value = HostValues.expr_frag_value(self.session, expanded)
        self.expr_frags[value.name] = value
        track_deps(value, closure_deps)
        return value

    elseif parsed.kind == "func" then
        -- Expand by wrapping in internal module
        local Tr = T.MoonTree
        local deps = merge_deps(closure_deps, deps_of(self))
        local raw_mod = internal_module_for_func(T, parsed.value, deps, parsed.value.name)
        local expanded_mod = Expand.expand_module(raw_mod, env)
        -- Extract the expanded function
        local expanded_func
        for i = 1, #expanded_mod.items do
            if pvm.classof(expanded_mod.items[i]) == Tr.ItemFunc then
                expanded_func = expanded_mod.items[i].func
                break
            end
        end
        if not expanded_func then error("func island did not produce a function after expansion", 2) end

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
        -- Expand the decl
        local expanded_decl = Expand.expand_type_decl(td.decl, env)

        -- Register protocol variants
        if td.protocol_variants then
            self.protocol_types[td.name] = td.protocol_variants
        end

        local api = self.session:api()
        local value = api.type_from_asdl(ty, td.name, {
            decl = expanded_decl,
            protocol_variants = td.protocol_variants,
        })
        track_deps(value, merge_deps(closure_deps, { type_decls = { td } }))
        return value

    else
        error("unsupported island kind: " .. tostring(parsed.kind), 2)
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

    -- Scan the document once, authoritatively
    local scan = Parse.scan_document(src)

    local runtime = setmetatable({
        T = T,
        session = session,
        scan = scan,
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
    q("return function(...)")
    q("local __moonlift_runtime = %s", rt)
    q("local moon = setmetatable({ require = function(name) return __moonlift_runtime:require(name) end }, { __index = __moonlift_runtime.session:api() })")

    local island_spans = {}
    local cursor = 1
    for island_index, island in ipairs(scan.islands) do
        -- Emit Lua source between cursor and island start
        local lua_part = src:sub(cursor, island.start - 1)
        if lua_part:match("%S") then
            q(lua_part)
        end

        -- Build closure table for this island's holes
        local entries = {}
        for _, hid in ipairs(island.holes) do
            local expr = scan.splice_map[hid]
            if expr then
                entries[#entries + 1] = string.format("[%q] = function() return (%s) end", hid, expr)
            end
        end

        -- Emit eval_island call by island index, not by source slice
        q(string.format("__moonlift_runtime:eval_island(%d, {%s})",
            island_index, table.concat(entries, ",")))

        cursor = island.stop + 1
    end

    -- Trailing Lua
    local tail = src:sub(cursor)
    if tail:match("%S") then q(tail) end

    q("end")
    local inner, lua_src = q:compile(chunk_name or "=(moonlift.mlua_run)")

    local function fn(...)
        local pop = push_runtime(runtime)
        local function pack(ok, ...)
            return { ok, n = select("#", ...) + 1, ... }
        end
        local results = pack(pcall(inner, ...))
        pop()
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2, results.n)
    end
    return fn, runtime, lua_src
end

function M.loadfile(path, opts)
    local f = assert(io.open(path, "rb"))
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
