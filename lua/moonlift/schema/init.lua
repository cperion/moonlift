-- Full clean Moon* schema authored as compact ASDL text.
--
-- The .asdl files in this directory are the source of truth.  A few C-schema
-- modules still live under lua/moonlift/c/ as Lua-builder modules because they
-- are outside this schema directory migration.

local Builder = require("moonlift.asdl_builder")
local AsdlText = require("moonlift.asdl_text")

local M = {}

local SCHEMA_ASDL_MODULES = {
    "core",
    "back",
    "dasm",
    "link",
    "type",
    "open",
    "bind",
    "sem",
    "tree",
    "code",
    "parse",
    "vec",
    "host",
    "source",
    "mlua",
    "editor",
    "lsp",
    "rpc",
}

local function append_all(dst, src)
    for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
end

local function schema_asdl_path(name)
    return "lua/moonlift/schema/" .. name .. ".asdl"
end

function M.schema(T)
    local A = Builder.Define(T)
    local modules = {}

    for _, name in ipairs(SCHEMA_ASDL_MODULES) do
        local modname = "moonlift.schema." .. name
        local text = AsdlText.load_text(modname, schema_asdl_path(name))
        local schema = AsdlText.parse_schema(T, text)
        append_all(modules, schema.modules)
    end

    -- C frontend/backend schema modules live under lua/moonlift/c/ and are not
    -- part of the lua/moonlift/schema/*.asdl source directory yet.
    modules[#modules + 1] = require("moonlift.c.c_type")(A)
    modules[#modules + 1] = require("moonlift.c.c_ast")(A)

    return T.MoonAsdl.Schema(modules)
end

function M.Define(T)
    local DefineSchema = require("moonlift.context_define_schema")
    return DefineSchema.define(T, M.schema(T))
end

return M
