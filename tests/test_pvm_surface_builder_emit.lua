package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local AsdlBuilder = require("moonlift.asdl_builder")
local SurfaceModel = require("moonlift.pvm_surface_model")
local SurfaceBuilder = require("moonlift.pvm_surface_builder")
local SurfaceEmit = require("moonlift.pvm_surface_emit")
local SchemaEmit = require("moonlift.pvm_surface_schema_emit")
local CleanAsdl = require("moonlift.asdl")
local Parse = require("moonlift.parse")

local T = pvm.context()
SurfaceModel.Define(T)
local P = SurfaceBuilder.Define(T)
local S = T.MoonPvmSurface
local Ph = T.MoonPhase

local body = P.phase "type_classify" {
    P.input "MoonType.Type",
    P.output "MoonType.TypeClass",
    P.cache "node",
    P.result "one",

    P.on "TScalar" {
        P.bind "scalar",
        P.once(P.ctor("MoonType_TypeClass", "TypeClassScalar") {
            scalar = P.local_("scalar"),
        }),
    },

    P.on "TPtr" {
        P.bind "elem",
        P.once(P.ctor("MoonType_TypeClass", "TypeClassPointer") {
            elem = P.local_("elem"),
        }),
    },

    P.default {
        P.once(P.ctor("MoonType_TypeClass", "TypeClassUnknown") {}),
    },
}

assert(pvm.classof(body) == S.PhaseBody)
assert(body.name == "type_classify")
assert(pvm.classof(body.input) == Ph.TypeRef)
assert(body.input.module_name == "MoonType")
assert(body.output.type_name == "TypeClass")
assert(body.cache == Ph.CacheNode)
assert(body.result == Ph.ResultOne)
assert(#body.handlers == 2)
assert(body.handlers[1].ctor_name == "TScalar")
assert(body.handlers[1].binds[1].name == "scalar")
assert(pvm.classof(body.handlers[1].body) == S.ProducerOnce)

local phase_src = SurfaceEmit.Define(T).emit_phase_body(body)
assert(phase_src:find("region type_classify_uncached", 1, true))
assert(phase_src:find("ambient emit fragment: emit_MoonType_TypeClassId", 1, true))
assert(phase_src:find("match subject_value", 1, true))
assert(phase_src:find("case TScalar(scalar)", 1, true))
assert(phase_src:find("emit emit_MoonType_TypeClassId", 1, true))
assert(phase_src:find("resume = done", 1, true))

local A = AsdlBuilder.Define(T)
local schema = A.schema {
    A.module "Demo" {
        A.product "Id" {
            A.field "text" "string",
            A.unique,
        },
        A.sum "Type" {
            A.variant "TScalar" {
                A.field "scalar" "Demo.Id",
                A.variant_unique,
            },
            A.variant "TPtr" {
                A.field "elem" "Demo.Type",
                A.variant_unique,
            },
            A.variant "TPair" {
                A.field "lhs" "Demo.Type",
                A.field "rhs" "Demo.Type",
                A.variant_unique,
            },
        },
    },
}

local schema_src = SchemaEmit.Define(T).emit(schema)
assert(schema_src:find("type Demo_Id = struct", 1, true))
assert(schema_src:find("text: StringId", 1, true))
assert(schema_src:find("type Demo_Type =", 1, true))
assert(schema_src:find("TScalar(Demo_IdId)", 1, true))
assert(schema_src:find("TPtr(Demo_TypeId)", 1, true))
assert(schema_src:find("type Demo_Type_TPairPayload = struct", 1, true))
assert(schema_src:find("lhs: Demo_TypeId", 1, true))
assert(schema_src:find("TPair(Demo_Type_TPairPayload)", 1, true))
assert(not schema_src:find("tag:", 1, true), "tagged unions must not be lowered to fake tag structs")

local T2 = pvm.context()
CleanAsdl.Define(T2)
local parsed_schema_surface = Parse.Define(T2).parse_module(schema_src)
assert(#parsed_schema_surface.issues == 0, parsed_schema_surface.issues[1] and parsed_schema_surface.issues[1].message)

io.write("moonlift pvm_surface_builder_emit ok\n")
