-- Canonical LalinSchema package loader.
--
-- Runtime schema source is Lua/LalinSchema data under lua/lalin/schema/*.lua.
-- Compact .asdl text is not an active source path.

local Dsl = require("lalin.schema.dsl")

local M = {}

local SCHEMA_MODULES = {
    "core",
    "back",
    "c",
    "luajit",
    "luatrace",
    "c_ast",
    "dasm",
    "link",
    "type",
    "open",
    "bind",
    "sem",
    "tree",
    "code",
    "graph",
    "flow",
    "value",
    "mem",
    "effect",
    "kernel",
    "stencil",
    "exec",
    "schedule",
    "lower",
    "compiler",
    "parse",
    "host",
    "source",
    "mlua",
    "editor",
    "lsp",
    "rpc",
}

local function append(dst, src)
    for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
end

local function load_schema_module(name)
    local mod = require("lalin.schema." .. name)
    if not Dsl.is_schema_value(mod, "Module") then
        error("lalin.schema: module lalin.schema." .. name .. " did not return a LalinSchema module", 2)
    end
    return mod
end

function M.modules_for_test()
    local copy = {}
    for i, name in ipairs(SCHEMA_MODULES) do copy[i] = name end
    return copy
end

function M.schema_modules_for_test()
    return M.modules_for_test()
end

function M.load_modules(names)
    names = names or SCHEMA_MODULES
    local out = {}
    for _, name in ipairs(names) do out[#out + 1] = load_schema_module(name) end
    return out
end

function M.schema(T)
    return Dsl.to_asdl_schema(T, M.load_modules())
end

local function bind_context(T)
    return Dsl.define(T, M.load_modules())
end

M.dsl = Dsl
M.use = Dsl.use
M.define = Dsl.define
M.to_asdl_schema = Dsl.to_asdl_schema

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
