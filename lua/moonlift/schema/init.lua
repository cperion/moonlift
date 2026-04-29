-- Clean Moon* schema modules authored as MoonAsdl data.
--
-- This is intentionally parallel to the current compatibility schema.  The
-- current compiler still consumes Moon2* internally; these modules are the
-- hand-authored destination schema we will port toward layer by layer.

local Builder = require("moonlift.asdl_builder")

local M = {}

function M.schema(T)
    local A = Builder.Define(T)
    return A.schema {
        require("moonlift.schema.core")(A),
    }
end

function M.Define(T)
    local DefineSchema = require("moonlift.context_define_schema")
    return DefineSchema.define(T, M.schema(T))
end

return M
