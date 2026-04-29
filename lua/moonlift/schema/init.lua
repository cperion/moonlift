-- Full clean Moon* schema authored as MoonAsdl builder data.
-- This is the destination schema namespace for Moonlift.

local Builder = require("moonlift.asdl_builder")

local M = {}

function M.schema(T)
    local A = Builder.Define(T)
    return A.schema {
        require("moonlift.schema.core")(A),
        require("moonlift.schema.back")(A),
        require("moonlift.schema.link")(A),
        require("moonlift.schema.type")(A),
        require("moonlift.schema.open")(A),
        require("moonlift.schema.bind")(A),
        require("moonlift.schema.sem")(A),
        require("moonlift.schema.tree")(A),
        require("moonlift.schema.parse")(A),
        require("moonlift.schema.vec")(A),
        require("moonlift.schema.host")(A),
        require("moonlift.schema.source")(A),
        require("moonlift.schema.mlua")(A),
        require("moonlift.schema.editor")(A),
        require("moonlift.schema.lsp")(A),
        require("moonlift.schema.rpc")(A),
    }
end

function M.Define(T)
    local DefineSchema = require("moonlift.context_define_schema")
    return DefineSchema.define(T, M.schema(T))
end

return M
