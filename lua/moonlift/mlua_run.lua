-- moonlift/mlua_run.lua — .mlua runner using frontend_pipeline + ThrowingCollector.
--
-- A .mlua file is Lua that uses the moonlift API to compile Moonlift source.
-- This module provides loadstring/loadfile/dofile/eval that:
--   1. Create a fresh PVM context
--   2. Call frontend_pipeline.parse_and_lower() with a ThrowingCollector
--   3. JIT-compile the resulting BackProgram via back_jit.lua
--   4. Return a callable Lua function
--
-- All compilation errors go through the ThrowingCollector → explainers → E0xxx format.
-- No island pipeline, no phase_fail, no E9999 hardcoding.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local M = {}

-------------------------------------------------------------------------------
-- C type helpers
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- CompiledFunction: callable wrapper around a JIT artifact
-------------------------------------------------------------------------------

local CompiledFunction = {}
CompiledFunction.__index = CompiledFunction

function CompiledFunction:__call(...)
    if not self.artifact then
        error("compiled Moonlift function called after artifact was freed", 2)
    end
    return self.fn(...)
end

function CompiledFunction:free()
    if self.artifact then
        self.artifact:free()
        self.artifact = nil
    end
end

-------------------------------------------------------------------------------
-- Compilation
-------------------------------------------------------------------------------

local function compile(src, chunk_name, opts)
    opts = opts or {}
    local T = pvm.context()
    A.Define(T)
    local Pipeline = require("moonlift.frontend_pipeline").Define(T)
    local J = require("moonlift.back_jit").Define(T)
    local Tr = T.MoonTree
    local Back = T.MoonBack

    -- Create ThrowingCollector — errors throw with rich E0xxx formatted output
    local Errors = require("moonlift.error")
    local analysis_ctx = { source_text = src, uri = chunk_name or "?" }
    local collector = Errors.ThrowingCollector(
        Errors.SpanResolvers.RESOLVERS,
        analysis_ctx,
        Errors.Catalog,
        Errors.Terminal.render
    )

    -- Parse and lower through the frontend pipeline
    local result = Pipeline.parse_and_lower(src, {
        site = "loadstring",
        collector = collector,
        analysis_ctx = analysis_ctx,
    })

    -- JIT-compile the BackProgram
    local program = result.program
    local jit = J.jit()
    local artifact = jit:compile(program)

    -- Find the function in the compiled module
    local checked_module = result.checked.module
    local checked_func
    for i = 1, #checked_module.items do
        if pvm.classof(checked_module.items[i]) == Tr.ItemFunc then
            checked_func = checked_module.items[i].func
            break
        end
    end
    if not checked_func then
        error("internal: no function found in compiled module", 2)
    end

    -- Resolve C signature and function pointer
    local csig = c_sig_of(T, checked_func)
    local ptr = artifact:getpointer(Back.BackFuncId(checked_func.name))

    return setmetatable({
        func = checked_func,
        fn = ffi.cast(csig, ptr),
        c_sig = csig,
        artifact = artifact,
        T = T,
    }, CompiledFunction)
end

-------------------------------------------------------------------------------
-- .mlua Lua-carrier transform
-------------------------------------------------------------------------------

local function long_bracket(s)
    local eq = ""
    while s:find("]" .. eq .. "]", 1, true) do eq = eq .. "=" end
    return "[" .. eq .. "[" .. s .. "]" .. eq .. "]"
end

local function quote_lua_string(s)
    return string.format("%q", s)
end

local function binding_table_for_island(scan, island)
    local entries, seen = {}, {}
    for _, id in ipairs(island.holes or {}) do
        local expr = scan.splice_map[id] or id
        if not seen[expr] then
            seen[expr] = true
            entries[#entries + 1] = "[" .. quote_lua_string(expr) .. "] = (" .. expr .. ")"
        end
    end
    if #entries == 0 then return "" end
    return "{" .. table.concat(entries, ", ") .. "}"
end

local function table_literal_inner(lit)
    if not lit or lit == "" then return nil end
    return lit:sub(2, -2)
end

local function merge_binding_literals(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local inner = table_literal_inner(select(i, ...))
        if inner and inner ~= "" then parts[#parts + 1] = inner end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function source_line_col(src, offset_1)
    local line, col = 1, 1
    for i = 1, math.max(1, offset_1) - 1 do
        if src:byte(i) == 10 then
            line = line + 1
            col = 1
        else
            col = col + 1
        end
    end
    return line, col
end

local function origin_bindings_for_island(src, island, chunk_name, host_type_aliases_literal)
    local line, col = source_line_col(src, island.start)
    local opts_parts = {}
    if island.name_hint then opts_parts[#opts_parts + 1] = "name_hint = " .. quote_lua_string(island.name_hint) end
    if host_type_aliases_literal and host_type_aliases_literal ~= "" then
        opts_parts[#opts_parts + 1] = "host_type_aliases = " .. host_type_aliases_literal
    end
    local opts = table.concat(opts_parts, ", ")
    return "{"
        .. "[\"__moonlift_source_origin\"] = {"
        .. "__moonlift_source = __moonlift_mlua_source, "
        .. "start_offset = " .. tostring((island.start or 1) - 1) .. ", "
        .. "start_line = " .. tostring(line) .. ", "
        .. "start_col = " .. tostring(col)
        .. "}, "
        .. "[\"__moonlift_parse_opts\"] = {" .. opts .. "}"
        .. "}"
end

local function split_region_impl_island(text)
    -- Pure .mlua shorthand for implementing a region header from Lua scope:
    --
    --     local impl = region Header.or_header
    --     entry start()
    --         ...
    --     end
    --     end
    --
    -- This is intentionally conservative: the reference is a Lua identifier or
    -- identifier chain. More complex expressions can still use the
    -- explicit header[[body]] form. The final region `end` belongs to the
    -- shorthand syntax and is stripped before the header is called.
    local ref, body = text:match("^%s*region%s+([^\r\n]+)\r\n(.*)$")
    if not ref then ref, body = text:match("^%s*region%s+([^\r\n]+)\n(.*)$") end
    if not ref then return nil end
    ref = ref:gsub("%s+$", "")
    local valid_ref = true
    if ref:match("^%.") or ref:match("%.$") or ref:match("%.%.") then valid_ref = false end
    if ref:match("^@{.*}$") then
        ref = ref:match("^@{(.*)}$")
        if not ref or ref == "" then valid_ref = false end
    elseif valid_ref then
        for part in ref:gmatch("[^%.]+") do
            if not part:match("^[_%a][_%w]*$") then valid_ref = false; break end
        end
    end
    if not valid_ref then return nil end
    if not body:match("^%s*entry%f[^%w_]") and not body:match("^%s*block%f[^%w_]") then return nil end
    local trimmed = body:gsub("%s+$", "")
    local s = trimmed:find("end%s*$")
    if not s then return nil end
    return ref, trimmed:sub(1, s - 1):gsub("%s+$", "")
end

local function split_func_impl_island(text)
    -- Pure .mlua shorthand for implementing a function header from Lua scope:
    --
    --     local impl = func Header.or_header
    --         return 0
    --     end
    --
    -- This mirrors region header implementation sugar. The final function
    -- `end` belongs to the shorthand syntax and is stripped before the header
    -- is called.
    local ref, body = text:match("^%s*func%s+([^\r\n]+)\r\n(.*)$")
    if not ref then ref, body = text:match("^%s*func%s+([^\r\n]+)\n(.*)$") end
    if not ref then return nil end
    ref = ref:gsub("%s+$", "")
    local valid_ref = true
    if ref:match("^%.") or ref:match("%.$") or ref:match("%.%.") then valid_ref = false end
    if ref:match("^@{.*}$") then
        ref = ref:match("^@{(.*)}$")
        if not ref or ref == "" then valid_ref = false end
    elseif valid_ref then
        for part in ref:gmatch("[^%.]+") do
            if not part:match("^[_%a][_%w]*$") then valid_ref = false; break end
        end
    end
    if not valid_ref then return nil end
    local trimmed = body:gsub("%s+$", "")
    local s = trimmed:find("end%s*$")
    if not s then return nil end
    return ref, trimmed:sub(1, s - 1):gsub("%s+$", "")
end

local api_name_for_kind = {
    func = "func",
    region = "region",
    expr = "expr_frag",
    struct = "struct",
    union = "union",
    handle = "handle",
    extern = "extern",
}

local function transform_mlua(src, chunk_name)
    local Parse = require("moonlift.parse")
    local moon = require("moonlift")
    local scan = Parse.scan_document(src)
    if #scan.islands == 0 then
        return "local moon = require('moonlift')\n" .. src
    end
    local out = {
        "local moon = require('moonlift')\n",
        "local __moonlift_mlua_source = { uri = " .. quote_lua_string(chunk_name or "=(mlua)")
            .. ", source_text = " .. long_bracket(src) .. " }\n",
    }
    local cursor = 1
    -- All declared names -> Lua value expressions.
    local vars = {}
    local host_type_aliases = {}
    for _, island in ipairs(scan.islands) do
        if (island.kind == "struct" or island.kind == "union" or island.kind == "handle")
            and island.lhs_path and island.name_hint then
            host_type_aliases[island.lhs_path] = island.name_hint
        end
    end
    local function host_type_aliases_literal()
        local entries = {}
        for path, local_name in pairs(host_type_aliases) do
            entries[#entries + 1] = "[" .. quote_lua_string(path) .. "] = " .. quote_lua_string(local_name)
        end
        table.sort(entries)
        return "{" .. table.concat(entries, ", ") .. "}"
    end
    local host_type_aliases_src = host_type_aliases_literal()
    local function demanded_root_bindings(island_src)
        local roots = {}
        for root in island_src:gmatch("([_%a][_%w]*)%s*%.") do
            roots[root] = root
        end
        for root in island_src:gmatch("%f[%w_]([%u_][%u%d_]*)%f[^%w_]") do
            roots[root] = root
        end
        return roots
    end
    -- Build bindings table literal from current declarations plus roots
    -- demanded by this island.  Deep paths are resolved lazily by chain.lua.
    local function all_var_bindings(island_src)
        local merged = {}
        for k, v in pairs(vars) do merged[k] = v end
        for k, v in pairs(demanded_root_bindings(island_src or "")) do merged[k] = v end
        if next(merged) == nil then return "{_=1}" end  -- sentinel to force binder path
        local entries = {}
        for k, v in pairs(merged) do
            entries[#entries + 1] = "[" .. string.format("%q", k) .. "] = (" .. v .. ")"
        end
        return "{" .. table.concat(entries, ", ") .. "}"
    end
    for _, island in ipairs(scan.islands) do
        out[#out + 1] = src:sub(cursor, island.start - 1)
        local island_src = src:sub(island.start, island.stop)
        local hint = island.name_hint
        local lhs = island.lhs_path
        local has_assign = lhs and lhs ~= ""
        local api_name = api_name_for_kind[island.kind]
        local hole_bindings = binding_table_for_island(scan, island)
        -- Merge hole bindings with var bindings.
        local bindings = all_var_bindings(island_src)
        if hole_bindings ~= "" then
            bindings = merge_binding_literals(hole_bindings, bindings)
        end
        bindings = merge_binding_literals(bindings, origin_bindings_for_island(src, island, chunk_name, host_type_aliases_src))
        local impl_ref, impl_body
        if island.kind == "region" then
            impl_ref, impl_body = split_region_impl_island(island_src)
        elseif island.kind == "func" then
            impl_ref, impl_body = split_func_impl_island(island_src)
        end
        if impl_ref then
            out[#out + 1] = impl_ref .. bindings .. long_bracket(impl_body)
        else
            assert(api_name, "unsupported .mlua island kind: " .. tostring(island.kind))
            if has_assign then
                out[#out + 1] = "moon." .. api_name .. bindings .. long_bracket(island_src)
            elseif hint then
                out[#out + 1] = hint .. " = moon." .. api_name .. bindings .. long_bracket(island_src)
            else
                out[#out + 1] = "moon." .. api_name .. bindings .. long_bracket(island_src)
            end
        end
        -- Track this declaration.
        if hint then
            local var = has_assign and lhs or hint
            vars[hint] = var
            if has_assign and lhs ~= hint then
                vars[lhs] = var
            end
        end
        cursor = island.stop + 1
    end
    out[#out + 1] = src:sub(cursor)
    return table.concat(out)
end

local function load_mlua_chunk(src, chunk_name)
    local transformed = transform_mlua(src, chunk_name)
    local loader, err = loadstring(transformed, chunk_name or "=(mlua)")
    if not loader then
        error("loadstring: " .. tostring(err), 3)
    end
    return loader, transformed
end

local module_table_mt = {}
module_table_mt.__index = module_table_mt

local function is_packable_value(v)
    if type(v) ~= "table" then return false end
    local kind = rawget(v, "kind")
    return kind == "func" or kind == "extern_func"
        or kind == "region_frag" or kind == "expr_frag"
        or kind == "struct" or kind == "union"
end

function module_table_mt:to_bundle(opts)
    local moon = require("moonlift")
    local name = (opts and opts.module_name) or rawget(self, "__moonlift_module_name") or "mlua_module"
    local bundle = moon.bundle(tostring(name):gsub("[^_%w]", "_"))
    local dep_names = moon._mlua_cache_order or {}
    for i = 1, #dep_names do
        local dep = moon._mlua_cache[dep_names[i]]
        if type(dep) == "table" then
            local dep_keys = {}
            for k, v in pairs(dep) do
                if type(k) == "string" and is_packable_value(v) then dep_keys[#dep_keys + 1] = k end
            end
            table.sort(dep_keys)
            for j = 1, #dep_keys do bundle:pack(dep[dep_keys[j]]) end
        end
    end
    local keys = {}
    for k, v in pairs(self) do
        if type(k) == "string" and is_packable_value(v) then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for i = 1, #keys do bundle:pack(self[keys[i]]) end
    return bundle
end

function module_table_mt:compile(opts)
    return self:to_bundle(opts):compile(opts)
end

function module_table_mt:emit_c_artifact(opts)
    return self:to_bundle(opts):emit_c_artifact(opts)
end

function module_table_mt:c_artifact(path_or_opts)
    local opts = type(path_or_opts) == "table" and path_or_opts or nil
    return self:to_bundle(opts):c_artifact(path_or_opts)
end

function module_table_mt:compile_c(opts)
    return self:to_bundle(opts):compile_c(opts)
end

local function wrap_result(value, chunk_name)
    if type(value) ~= "table" or is_packable_value(value) or getmetatable(value) ~= nil then return value end
    local saw_packable = false
    for _, v in pairs(value) do
        if is_packable_value(v) then saw_packable = true; break end
    end
    if not saw_packable then return value end
    rawset(value, "__moonlift_module_name", chunk_name or "mlua_module")
    return setmetatable(value, module_table_mt)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function M.loadstring(src, chunk_name, opts)
    local loader = load_mlua_chunk(src, chunk_name)
    local function pack_results(...)
        return { n = select("#", ...), ... }
    end
    return function(...)
        local results = pack_results(loader(...))
        for i = 1, results.n do results[i] = wrap_result(results[i], chunk_name) end
        return unpack(results, 1, results.n)
    end
end

function M.loadfile(path, opts)
    local f, err = io.open(path, "rb")
    if not f then error("loadfile: " .. tostring(err), 2) end
    local src = f:read("*a")
    f:close()
    return M.loadstring(src, path, opts)
end

function M.dofile(path, opts, ...)
    local fn = M.loadfile(path, opts)
    return fn(...)
end

function M.eval(src, chunk_name, ...)
    local fn = M.loadstring(src, chunk_name or "=(eval)")
    return fn(...)
end

return M
