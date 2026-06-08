-- Canonical data model for PVM bodies that lower to Moonlift surface regions.

local Builder = require("moonlift.asdl_builder")
local AsdlText = require("moonlift.asdl_text")
local PhaseModel = require("moonlift.phase_model")
local DefineSchema = require("moonlift.context_define_schema")

local M = {}

function M.schema(T)
    local A = Builder.Define(T)
    PhaseModel.Define(T)
    local text = AsdlText.load_text("moonlift.schema.pvm_surface", "lua/moonlift/schema/pvm_surface.asdl")
    return AsdlText.parse_schema(T, text)
end

function M.Define(T)
    if T.MoonPvmSurface ~= nil then return T end
    return DefineSchema.define(T, M.schema(T))
end

return M
