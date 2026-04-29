package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local PhaseModel = require("moonlift.phase_model")
local PhaseBuilder = require("moonlift.phase_builder")

local T = pvm.context()
PhaseModel.Define(T)
local W = PhaseBuilder.Define(T)
local P = T.MoonPhase

local package = W.package "moonlift.compiler" {
    W.unit "type.classify" {
        W.file "moonlift.type_classify",
        W.phase "type.classify" {
            W.input "MoonType.Type",
            W.output "MoonType.TypeClass",
            W.cache "node",
            W.result "one",
        },
        W.exports { "classify", "classify_type" },
    },

    W.unit "tree.to_back" {
        W.file "moonlift.tree_to_back",
        W.uses { "type.classify" },
        W.phase "tree.module_to_back" {
            W.input "MoonTree.Module",
            W.output "MoonBack.Program",
            W.cache "last",
            W.result "one",
        },
        W.exports { "module", "module_to_back" },
    },
}

assert(pvm.classof(package) == P.Package)
assert(package.name == "moonlift.compiler")
assert(#package.units == 2)
assert(package.units[1].file == "moonlift.type_classify")
assert(package.units[2].uses[1].name == "type.classify")
local phase = package.units[2].phases[1]
assert(phase.name == "tree.module_to_back")
assert(pvm.classof(phase.input) == P.TypeRef)
assert(phase.input.module_name == "MoonTree")
assert(phase.output.type_name == "Program")
assert(phase.cache == P.CacheNodeArgsLast)
assert(phase.result == P.ResultOne)

io.write("moonlift phase_builder ok\n")
