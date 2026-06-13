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

local function name_anonymous_island(kind, text, name_hint)
    if not name_hint or name_hint == "" then return text end
    if kind == "func" and text:match("^%s*func%s*%(") then
        return (text:gsub("^(%s*func)%s*", "%1 " .. name_hint, 1))
    end
    if kind == "region" and text:match("^%s*region%s*[%(%-%>]") then
        return (text:gsub("^(%s*region)%s*", "%1 " .. name_hint, 1))
    end
    if kind == "expr" and text:match("^%s*expr%s*%(") then
        return (text:gsub("^(%s*expr)%s*", "%1 " .. name_hint, 1))
    end
    if kind == "struct" and (
        text:match("^%s*struct%s*\n") or text:match("^%s*struct%s*\r\n") or
        text:match("^%s*struct%s+[A-Za-z_][A-Za-z0-9_]*%s*:")
    ) then
        return (text:gsub("^(%s*struct)%s*", "%1 " .. name_hint .. " ", 1))
    end
    if kind == "union" and (
        text:match("^%s*union%s*\n") or text:match("^%s*union%s*\r\n") or
        text:match("^%s*union%s+[A-Za-z_][A-Za-z0-9_]*%s*[%(%|]") or
        text:match("^%s*union%s+[A-Za-z_][A-Za-z0-9_]*%s+end")
    ) then
        return (text:gsub("^(%s*union)%s*", "%1 " .. name_hint .. " ", 1))
    end
    return text
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
    -- dotted identifier chain. More complex expressions can still use the
    -- explicit header[[body]] form. The final region `end` belongs to the
    -- shorthand syntax and is stripped before the header is called.
    local ref, body = text:match("^%s*region%s+([^\r\n]+)\r\n(.*)$")
    if not ref then ref, body = text:match("^%s*region%s+([^\r\n]+)\n(.*)$") end
    if not ref then return nil end
    ref = ref:gsub("%s+$", "")
    local valid_ref = true
    if ref:match("^%.") or ref:match("%.$") or ref:match("%.%.") then valid_ref = false end
    if valid_ref then
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
    if valid_ref then
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
    extern = "extern",
}

local function transform_mlua(src)
    local Parse = require("moonlift.parse")
    local scan = Parse.scan_document(src)
    if #scan.islands == 0 then
        return "local moon = require('moonlift')\n" .. src
    end
    local out = { "local moon = require('moonlift')\n" }
    local cursor = 1
    for _, island in ipairs(scan.islands) do
        out[#out + 1] = src:sub(cursor, island.start - 1)
        local island_src = src:sub(island.start, island.stop)
        local bindings = binding_table_for_island(scan, island)
        local impl_ref, impl_body
        if island.kind == "region" then
            impl_ref, impl_body = split_region_impl_island(island_src)
        elseif island.kind == "func" then
            impl_ref, impl_body = split_func_impl_island(island_src)
        end
        if impl_ref then
            if bindings ~= "" then
                out[#out + 1] = impl_ref .. bindings .. long_bracket(impl_body)
            else
                out[#out + 1] = impl_ref .. long_bracket(impl_body)
            end
        else
            island_src = name_anonymous_island(island.kind, island_src, island.name_hint)
            local api_name = assert(api_name_for_kind[island.kind], "unsupported .mlua island kind: " .. tostring(island.kind))
            if bindings ~= "" then
                out[#out + 1] = "moon." .. api_name .. bindings .. long_bracket(island_src)
            else
                out[#out + 1] = "moon." .. api_name .. long_bracket(island_src)
            end
        end
        cursor = island.stop + 1
    end
    out[#out + 1] = src:sub(cursor)
    return table.concat(out)
end

local function load_mlua_chunk(src, chunk_name)
    local transformed = transform_mlua(src)
    local loader, err = loadstring(transformed, chunk_name or "=(mlua)")
    if not loader then
        error("loadstring: " .. tostring(err), 3)
    end
    return loader, transformed
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function M.loadstring(src, chunk_name, opts)
    local loader = load_mlua_chunk(src, chunk_name)
    return loader
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

function M.current_runtime()
    return nil  -- no runtime state in this simplified path
end

return M
