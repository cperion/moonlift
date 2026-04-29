package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Gather = require("moonlift.bind_residence_gather")
local Decide = require("moonlift.bind_residence_decide")
local Machine = require("moonlift.bind_machine_binding")

local T = pvm.context()
A.Define(T)
local G = Gather.Define(T)
local D = Decide.Define(T)
local M = Machine.Define(T)
local C = T.MoonCore
local Ty = T.MoonType
local B = T.MoonBind
local Tr = T.MoonTree

local i32 = Ty.TScalar(C.ScalarI32)
local arr4 = Ty.TArray(Ty.ArrayLenConst(4), i32)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end

local scalar = B.Binding(C.Id("scalar"), "scalar", i32, B.BindingClassLocalValue)
local cell = B.Binding(C.Id("cell"), "cell", i32, B.BindingClassLocalCell)
local aggregate = B.Binding(C.Id("aggregate"), "aggregate", arr4, B.BindingClassLocalValue)
local addressed = B.Binding(C.Id("addressed"), "addressed", i32, B.BindingClassLocalValue)

local module = Tr.Module(Tr.ModuleTyped("Demo"), {
    Tr.ItemFunc(Tr.FuncLocal("f", {}, i32, {
        Tr.StmtLet(Tr.StmtTyped, scalar, lit("1")),
        Tr.StmtVar(Tr.StmtTyped, cell, lit("2")),
        Tr.StmtLet(Tr.StmtTyped, aggregate, Tr.ExprArray(Tr.ExprTyped(arr4), i32, { lit("1"), lit("2"), lit("3"), lit("4") })),
        Tr.StmtLet(Tr.StmtTyped, addressed, lit("3")),
        Tr.StmtExpr(Tr.StmtTyped, Tr.ExprAddrOf(Tr.ExprTyped(Ty.TPtr(i32)), Tr.PlaceRef(Tr.PlaceTyped(i32), B.ValueRefBinding(addressed)))),
        Tr.StmtReturnValue(Tr.StmtTyped, Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefBinding(scalar))),
    })),
})

local function has(xs, needle)
    for i = 1, #xs do if xs[i] == needle then return true end end
    return false
end

local facts = G.facts_of_module(module)
assert(has(facts.facts, B.ResidenceFactBinding(scalar)))
assert(has(facts.facts, B.ResidenceFactBinding(cell)))
assert(has(facts.facts, B.ResidenceFactMutableCell(cell)))
assert(has(facts.facts, B.ResidenceFactBinding(aggregate)))
assert(has(facts.facts, B.ResidenceFactNonScalarAbi(aggregate)))
assert(has(facts.facts, B.ResidenceFactAddressTaken(addressed)))

local plan = D.decide(facts)
assert(has(plan.decisions, B.ResidenceDecision(scalar, B.ResidenceValue, B.ResidenceBecauseDefault)))
assert(has(plan.decisions, B.ResidenceDecision(cell, B.ResidenceCell, B.ResidenceBecauseMutableCell)))
assert(has(plan.decisions, B.ResidenceDecision(aggregate, B.ResidenceStack, B.ResidenceBecauseNonScalarAbi)))
assert(has(plan.decisions, B.ResidenceDecision(addressed, B.ResidenceStack, B.ResidenceBecauseAddressTaken)))

local machine = M.bind(plan)
assert(has(machine.bindings, B.MachineBinding(scalar, B.ResidenceValue)))
assert(has(machine.bindings, B.MachineBinding(cell, B.ResidenceCell)))
assert(has(machine.bindings, B.MachineBinding(aggregate, B.ResidenceStack)))
assert(has(machine.bindings, B.MachineBinding(addressed, B.ResidenceStack)))

print("moonlift bind_residence ok")
