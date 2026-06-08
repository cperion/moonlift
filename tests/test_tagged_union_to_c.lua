package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local B = T.MoonBind

local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToC = require("moonlift.tree_to_c").Define(T)
local ModuleType = require("moonlift.tree_module_type").Define(T)
local CValidate = require("moonlift.c_validate").Define(T)
local CEmit = require("moonlift.c_emit").Define(T)

local i32 = Ty.TScalar(Core.ScalarI32)
local void = Ty.TScalar(Core.ScalarVoid)
local maybe_ty = Ty.TNamed(Ty.TypeRefGlobal("", "Maybe"))
local decl = Tr.TypeDeclTaggedUnionSugar("Maybe", {
    Ty.VariantDecl("some", i32, {}),
    Ty.VariantDecl("none", void, {}),
})

local function lit(n) return Tr.ExprLit(Tr.ExprSurface, Core.LitInt(tostring(n))) end
local function ref(name) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name)) end

local bind_stmt = B.Binding(Core.Id("local:m_stmt"), "m", maybe_ty, B.BindingClassLocalValue)
local bind_expr = B.Binding(Core.Id("local:m_expr"), "m", maybe_ty, B.BindingClassLocalValue)

local func_stmt = Tr.FuncLocal("match_stmt", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, bind_stmt, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(33) })),
    Tr.StmtSwitch(Tr.StmtSurface, ref("m"), {}, {
        Tr.SwitchVariantStmtArm("some", { Tr.VariantBind("x", void) }, { Tr.StmtReturnValue(Tr.StmtSurface, ref("x")) }),
    }, { Tr.StmtReturnValue(Tr.StmtSurface, lit(0)) }),
})

local func_expr = Tr.FuncLocal("match_expr", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, bind_expr, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(44) })),
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprSwitch(Tr.ExprSurface, ref("m"), {}, {
        Tr.SwitchVariantExprArm("some", { Tr.VariantBind("x", void) }, {}, ref("x")),
    }, {}, lit(0))),
})

local bind_ctl = B.Binding(Core.Id("local:m_ctl"), "m", maybe_ty, B.BindingClassLocalValue)
local ctl_region = Tr.ControlExprRegion("match_ctl", i32, Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {
    Tr.StmtLet(Tr.StmtSurface, bind_ctl, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(55) })),
    Tr.StmtSwitch(Tr.StmtSurface, ref("m"), {}, {
        Tr.SwitchVariantStmtArm("some", { Tr.VariantBind("x", void) }, { Tr.StmtYieldValue(Tr.StmtSurface, ref("x")) }),
    }, { Tr.StmtYieldValue(Tr.StmtSurface, lit(0)) }),
}), {})
local func_control = Tr.FuncLocal("match_control", {}, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprControl(Tr.ExprSurface, ctl_region)),
})

local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemType(decl), Tr.ItemFunc(func_stmt), Tr.ItemFunc(func_expr), Tr.ItemFunc(func_control) })
local checked = Typecheck.check_module(module)
assert(#checked.issues == 0, "typecheck issues: " .. tostring(#checked.issues))
local layout_env = ModuleType.env(checked.module)
local resolved = Layout.module(checked.module)
local unit = TreeToC.module(resolved, { layout_env = layout_env })
local report = CValidate.validate(unit)
assert(#report.issues == 0, "C validation issues: " .. tostring(#report.issues))

local c_src = CEmit.emit(unit)
assert(c_src:match("__tag"), "tagged union C should contain __tag field")
assert(c_src:match("__payload"), "tagged union C should contain __payload field")
assert(c_src:match("switch %(ml_variant_tag"), "variant switch should lower through tag switch")

local function exec_ok(cmd)
    local a = os.execute(cmd)
    return a == true or a == 0
end
if exec_ok("command -v cc >/dev/null 2>&1") then
    local path = os.tmpname() .. ".c"
    local f = assert(io.open(path, "wb")); f:write(c_src); f:close()
    local ok = exec_ok("cc -std=c99 -fsyntax-only " .. path)
    os.remove(path)
    assert(ok, "emitted tagged-union C failed cc -std=c99 -fsyntax-only")
end

io.write("moonlift tagged union tree_to_c ok\n")
