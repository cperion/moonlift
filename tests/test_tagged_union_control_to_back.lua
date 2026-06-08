package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local B = T.MoonBind
local Back = T.MoonBack

local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local Lower = require("moonlift.tree_to_back").Define(T)
local Validate = require("moonlift.back_validate").Define(T)
local Facts = require("moonlift.tree_control_facts").Define(T)

local i32 = Ty.TScalar(Core.ScalarI32)
local void = Ty.TScalar(Core.ScalarVoid)
local maybe_ty = Ty.TNamed(Ty.TypeRefGlobal("", "Maybe"))
local decl = Tr.TypeDeclTaggedUnionSugar("Maybe", {
    Ty.VariantDecl("some", i32, {}),
    Ty.VariantDecl("none", void, {}),
})

local function lit(n) return Tr.ExprLit(Tr.ExprSurface, Core.LitInt(tostring(n))) end
local function ref(name) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name)) end

local binding = B.Binding(Core.Id("local:m"), "m", maybe_ty, B.BindingClassLocalValue)
local region = Tr.ControlExprRegion("match_region", i32,
    Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {
        Tr.StmtLet(Tr.StmtSurface, binding, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(77) })),
        Tr.StmtSwitch(Tr.StmtSurface, ref("m"), {}, {
            Tr.SwitchVariantStmtArm("some", { Tr.VariantBind("x", void) }, { Tr.StmtYieldValue(Tr.StmtSurface, ref("x")) }),
        }, { Tr.StmtYieldValue(Tr.StmtSurface, lit(0)) }),
    }),
    {})

local func = Tr.FuncLocal("control_match", {}, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprControl(Tr.ExprSurface, region)),
})
local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemType(decl), Tr.ItemFunc(func) })
local checked = Typecheck.check_module(module)
assert(#checked.issues == 0, "typecheck issues: " .. tostring(#checked.issues))

local checked_region = checked.module.items[2].func.body[1].value.region
local facts = Facts.facts(checked_region).facts
local saw_variant_fact = false
for i = 1, #facts do
    if pvm.classof(facts[i]) == Tr.ControlFactVariantSwitch then saw_variant_fact = true end
end
assert(saw_variant_fact, "control facts should include variant switch fact")

local resolved = Layout.module(checked.module)
local program = Lower.module(resolved)
local report = Validate.validate(program)
assert(#report.issues == 0, "back validation issues: " .. tostring(#report.issues))

local saw_switch, saw_bind_load = false, false
for i = 1, #program.cmds do
    local cls = pvm.classof(program.cmds[i])
    if cls == Back.CmdSwitchInt then saw_switch = true end
    if cls == Back.CmdLoadInfo and program.cmds[i].memory.access.text:match("control:variant:bind:x") then saw_bind_load = true end
end
assert(saw_switch, "control variant switch should lower to tag switch")
assert(saw_bind_load, "control variant bind should lower payload load")

io.write("moonlift tagged union control_to_back ok\n")
