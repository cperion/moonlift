package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A = require("lalin.schema_projection")
local Gather = require("lalin.bind_residence_gather")
local Decide = require("lalin.bind_residence_decide")
local Machine = require("lalin.bind_machine_binding")

local T = asdl.context()
A(T)
local G = Gather(T)
local D = Decide(T)
local M = Machine(T)
local C = T.LalinCore
local Ty = T.LalinType
local B = T.LalinBind
local Tr = T.LalinTree

local i32 = Ty.TScalar(C.ScalarI32)
local fn_ty = Ty.TFunc({ i32 }, i32)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end
local function binding(id, name, ty, role) return B.Binding(C.Id(id), name, ty, role) end
local function use(binding_node)
    return Tr.StmtExpr(Tr.StmtSurface, Tr.ExprRef(Tr.ExprTyped(binding_node.ty), B.ValueRefBinding(binding_node)))
end
local function has(xs, needle)
    for i = 1, #xs do if xs[i] == needle then return true end end
    return false
end

local bindings = {
    binding("local.value", "local_value", i32, B.BindingRoleLocalValue),
    binding("local.cell", "local_cell", i32, B.BindingRoleLocalCell),
    binding("arg", "arg", i32, B.BindingRoleArg(0)),
    binding("control.entry.acc", "acc", i32, B.BindingRoleEntryBlockParam("control.sum", "loop", 2)),
    binding("control.block.i", "i", i32, B.BindingRoleBlockParam("control.sum", "loop", 1)),
    binding("global.func", "gf", fn_ty, B.BindingRoleGlobalFunc("M", "gf")),
    binding("global.const", "gc", i32, B.BindingRoleGlobalConst("M", "gc")),
    binding("global.static", "gs", i32, B.BindingRoleGlobalStatic("M", "gs")),
    binding("extern", "ex", fn_ty, B.BindingRoleExtern("puts")),
}

local stmts = {
    Tr.StmtLet(Tr.StmtSurface, bindings[1], lit("1")),
    Tr.StmtVar(Tr.StmtSurface, bindings[2], lit("2")),
}
for i = 3, #bindings do stmts[#stmts + 1] = use(bindings[i]) end

local facts = G.facts_of_stmts(stmts)
for i = 1, #bindings do
    assert(has(facts.facts, B.ResidenceFactBinding(bindings[i])))
end
assert(has(facts.facts, B.ResidenceFactMutableCell(bindings[2])))

local plan = D.decide(facts)
assert(has(plan.decisions, B.ResidenceDecision(bindings[1], B.ResidenceValue, B.ResidenceBecauseDefault)))
assert(has(plan.decisions, B.ResidenceDecision(bindings[2], B.ResidenceCell, B.ResidenceBecauseMutableCell)))
for i = 3, #bindings do
    assert(has(plan.decisions, B.ResidenceDecision(bindings[i], B.ResidenceValue, B.ResidenceBecauseDefault)))
end

local machine = M.bind(plan)
for i = 1, #bindings do
    local residence = i == 2 and B.ResidenceCell or B.ResidenceValue
    assert(has(machine.bindings, B.MachineBinding(bindings[i], residence)))
end

print("lalin bind_residence_coverage ok")
