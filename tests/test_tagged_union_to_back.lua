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
local binding_expr = B.Binding(Core.Id("local:m_expr"), "m", maybe_ty, B.BindingClassLocalValue)

local func = Tr.FuncLocal("match_some", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, binding, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(42) })),
    Tr.StmtSwitch(Tr.StmtSurface, ref("m"), {}, {
        Tr.SwitchVariantStmtArm("some", { Tr.VariantBind("x", void) }, { Tr.StmtReturnValue(Tr.StmtSurface, ref("x")) }),
    }, { Tr.StmtReturnValue(Tr.StmtSurface, lit(0)) }),
})
local func_expr = Tr.FuncLocal("match_expr", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, binding_expr, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(5) })),
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprSwitch(Tr.ExprSurface, ref("m"), {}, {
        Tr.SwitchVariantExprArm("some", { Tr.VariantBind("x", void) }, {}, ref("x")),
    }, {}, lit(0))),
})

local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemType(decl), Tr.ItemFunc(func), Tr.ItemFunc(func_expr) })
local checked = Typecheck.check_module(module)
assert(#checked.issues == 0, "typecheck issues: " .. tostring(#checked.issues))
local resolved = Layout.module(checked.module)
local program = Lower.module(resolved)
local report = Validate.validate(program)
assert(#report.issues == 0, "back validation issues: " .. tostring(#report.issues))

local switch_count, saw_store, saw_expr_bind = 0, false, false
for i = 1, #program.cmds do
    local cls = pvm.classof(program.cmds[i])
    if cls == Back.CmdSwitchInt then switch_count = switch_count + 1 end
    if cls == Back.CmdStoreInfo then saw_store = true end
    if cls == Back.CmdLoadInfo and program.cmds[i].memory.access.text:match("variant:expr:bind:x") then saw_expr_bind = true end
end
assert(switch_count >= 2, "statement and expression variant switches should lower to tag switches")
assert(saw_store, "constructor should store tag/payload")
assert(saw_expr_bind, "variant switch expression should lower payload bind load")

io.write("moonlift tagged union tree_to_back ok\n")
