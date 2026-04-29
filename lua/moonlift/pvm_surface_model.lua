-- Canonical data model for PVM bodies that lower to Moonlift surface regions.

local Builder = require("moonlift.asdl_builder")
local PhaseModel = require("moonlift.phase_model")
local DefineSchema = require("moonlift.context_define_schema")

local M = {}

function M.schema(T)
    local A = Builder.Define(T)
    PhaseModel.Define(T)
    return A.schema {
        require("moonlift.schema.pvm_surface")(A),
    }
end

function M.Define(T)
    if T.MoonPvmSurface ~= nil then return T end
    return DefineSchema.define(T, M.schema(T))
end

return M
