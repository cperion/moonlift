package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

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
local C = T.Moon2Core
local Ty = T.Moon2Type
local B = T.Moon2Bind
local O = T.Moon2Open
local Tr = T.Moon2Tree

local i32 = Ty.TScalar(C.ScalarI32)
local fn_ty = Ty.TFunc({ i32 }, i32)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end
local function binding(id, name, ty, class) return B.Binding(C.Id(id), name, ty, class) end
local function use(binding_node)
    return Tr.StmtExpr(Tr.StmtTyped, Tr.ExprRef(Tr.ExprTyped(binding_node.ty), B.ValueRefBinding(binding_node)))
end
local function has(xs, needle)
    for i = 1, #xs do if xs[i] == needle then return true end end
    return false
end

local open_param = O.OpenParam("P", "p", i32)
local import_value = O.ImportValue("iv", "iv", i32)
local import_func = O.ImportGlobalFunc("if", "Imported", "f", fn_ty)
local func_slot = O.FuncSlot("fs", "fs", fn_ty)
local const_slot = O.ConstSlot("cs", "cs", i32)
local static_slot = O.StaticSlot("ss", "ss", i32)
local value_slot = O.ValueSlot("vs", "vs", i32)

local bindings = {
    binding("local.value", "local_value", i32, B.BindingClassLocalValue),
    binding("local.cell", "local_cell", i32, B.BindingClassLocalCell),
    binding("arg", "arg", i32, B.BindingClassArg(0)),
    binding("control.entry.acc", "acc", i32, B.BindingClassEntryBlockParam("control.sum", "loop", 2)),
    binding("control.block.i", "i", i32, B.BindingClassBlockParam("control.sum", "loop", 1)),
    binding("global.func", "gf", fn_ty, B.BindingClassGlobalFunc("M", "gf")),
    binding("global.const", "gc", i32, B.BindingClassGlobalConst("M", "gc")),
    binding("global.static", "gs", i32, B.BindingClassGlobalStatic("M", "gs")),
    binding("extern", "ex", fn_ty, B.BindingClassExtern("puts")),
    binding("open.param", "p", i32, B.BindingClassOpenParam(open_param)),
    binding("import.value", "iv", i32, B.BindingClassImport(import_value)),
    binding("import.func", "if", fn_ty, B.BindingClassImport(import_func)),
    binding("func.sym", "fsym", fn_ty, B.BindingClassFuncSym(C.FuncSym("fk", "fsym"))),
    binding("extern.sym", "esym", fn_ty, B.BindingClassExternSym(C.ExternSym("ek", "esym", "c_esym"))),
    binding("const.sym", "csym", i32, B.BindingClassConstSym(C.ConstSym("ck", "csym"))),
    binding("static.sym", "ssym", i32, B.BindingClassStaticSym(C.StaticSym("sk", "ssym"))),
    binding("func.slot", "fslot", fn_ty, B.BindingClassFuncSlot(func_slot)),
    binding("const.slot", "cslot", i32, B.BindingClassConstSlot(const_slot)),
    binding("static.slot", "sslot", i32, B.BindingClassStaticSlot(static_slot)),
    binding("value.slot", "vslot", i32, B.BindingClassValueSlot(value_slot)),
}

local stmts = {
    Tr.StmtLet(Tr.StmtTyped, bindings[1], lit("1")),
    Tr.StmtVar(Tr.StmtTyped, bindings[2], lit("2")),
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

print("moonlift bind_residence_coverage ok")
