-- Canonical compiler phase/wiring model, authored with table-builder syntax.

local Model = require("moonlift.asdl_model")
local Builder = require("moonlift.asdl_builder")
local DefineSchema = require("moonlift.context_define_schema")

local M = {}

function M.schema(T)
    Model.Define(T)
    local A = Builder.Define(T)
    return A.schema {
        A.module "MoonPhase" {
            A.product "Package" {
                A.field "name" "string",
                A.field "units" (A.many "MoonPhase.PhaseUnit"),
                A.unique,
            },
            A.product "PhaseUnit" {
                A.field "name" "string",
                A.field "file" "string",
                A.field "uses" (A.many "MoonPhase.UnitUse"),
                A.field "phases" (A.many "MoonPhase.PhaseSpec"),
                A.field "exports" (A.many "MoonPhase.UnitExport"),
                A.unique,
            },
            A.product "UnitUse" {
                A.field "name" "string",
                A.unique,
            },
            A.product "UnitExport" {
                A.field "name" "string",
                A.unique,
            },
            A.sum "TypeRef" {
                A.variant "TypeRef" {
                    A.field "module_name" "string",
                    A.field "type_name" "string",
                    A.variant_unique,
                },
                A.variant "TypeRefAny",
                A.variant "TypeRefValue" {
                    A.field "name" "string",
                    A.variant_unique,
                },
            },
            A.sum "CachePolicy" {
                A.variant "CacheNode",
                A.variant "CacheNodeArgsFull",
                A.variant "CacheNodeArgsLast",
                A.variant "CacheNone",
            },
            A.sum "ResultShape" {
                A.variant "ResultOne",
                A.variant "ResultOptional",
                A.variant "ResultMany",
                A.variant "ResultReport" {
                    A.field "report_ty" "MoonPhase.TypeRef",
                    A.variant_unique,
                },
            },
            A.product "PhaseSpec" {
                A.field "name" "string",
                A.field "input" "MoonPhase.TypeRef",
                A.field "output" "MoonPhase.TypeRef",
                A.field "cache" "MoonPhase.CachePolicy",
                A.field "result" "MoonPhase.ResultShape",
                A.unique,
            },
            -- UnitPart / PhasePart are structural decompositions used by the builder API.
            A.sum "UnitPart" {
                A.variant "UnitFile" {
                    A.field "module_name" "string",
                    A.variant_unique,
                },
                A.variant "UnitUses" {
                    A.field "uses" (A.many "MoonPhase.UnitUse"),
                    A.variant_unique,
                },
                A.variant "UnitExports" {
                    A.field "exports" (A.many "MoonPhase.UnitExport"),
                    A.variant_unique,
                },
                A.variant "UnitPhase" {
                    A.field "phase" "MoonPhase.PhaseSpec",
                    A.variant_unique,
                },
            },
            A.sum "PhasePart" {
                A.variant "PhaseInput" {
                    A.field "input" "MoonPhase.TypeRef",
                    A.variant_unique,
                },
                A.variant "PhaseOutput" {
                    A.field "output" "MoonPhase.TypeRef",
                    A.variant_unique,
                },
                A.variant "PhaseCache" {
                    A.field "cache" "MoonPhase.CachePolicy",
                    A.variant_unique,
                },
                A.variant "PhaseResult" {
                    A.field "result" "MoonPhase.ResultShape",
                    A.variant_unique,
                },
            },
        },
    }
end

function M.Define(T)
    if T.MoonPhase ~= nil then return T end
    return DefineSchema.define(T, M.schema(T))
end

return M
