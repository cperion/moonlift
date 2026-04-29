package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local SurfaceModel = require("moonlift.pvm_surface_model")
local SurfaceBuilder = require("moonlift.pvm_surface_builder")

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

io.write("moonlift pvm_surface_builder ok\n")
