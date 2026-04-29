-- Experimental schema-as-data entry point for the current Moonlift schema.
--
-- The existing compiler implementation still uses the legacy Moon2* module names.
-- This module routes that same schema through MoonAsdl.Schema values first, then
-- through the compatibility text emitter.  It is the migration bridge for
-- proving Moonlift can run on schema-as-data before the schema is hand-cleaned
-- and renamed to Moon* modules.

local Legacy = require("moonlift.asdl")
local Import = require("moonlift.asdl_legacy_import")
local DefineSchema = require("moonlift.context_define_schema")

local M = {}

function M.schema(T)
    return Import.import(T, Legacy.SCHEMA)
end

function M.Define(T)
    local schema = M.schema(T)
    DefineSchema.define(T, schema)
    return T
end

return M
