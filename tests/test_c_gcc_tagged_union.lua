package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Harness = require("tests.test_c_gcc_harness")

local T = pvm.context(); Schema.Define(T)
local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local B = T.MoonBind

local Typecheck = require("moonlift.tree_typecheck").Define(T)
local ModuleType = require("moonlift.tree_module_type").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToC = require("moonlift.tree_to_c").Define(T)
local CValidate = require("moonlift.c_validate").Define(T)
local CEmit = require("moonlift.c_emit").Define(T)

local i32 = Ty.TScalar(Core.ScalarI32)
local void = Ty.TScalar(Core.ScalarVoid)
local maybe_ty = Ty.TNamed(Ty.TypeRefGlobal("", "Maybe"))
local color_ty = Ty.TNamed(Ty.TypeRefGlobal("", "Color"))

local maybe_decl = Tr.TypeDeclTaggedUnionSugar("Maybe", {
    Ty.VariantDecl("some", i32, {}),
    Ty.VariantDecl("none", void, {}),
})
local color_decl = Tr.TypeDeclEnumSugar("Color", { Core.Name("red"), Core.Name("green") })

local function lit(n) return Tr.ExprLit(Tr.ExprSurface, Core.LitInt(tostring(n))) end
local function ref(name) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name)) end
local function bind(id, name, ty) return B.Binding(Core.Id(id), name, ty, B.BindingClassLocalValue) end

local c_red = bind("local:c_red", "c", color_ty)
local enum_func = Tr.FuncLocal("enum_red", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, c_red, Tr.ExprCtor(Tr.ExprSurface, "Color", "red", {})),
    Tr.StmtSwitch(Tr.StmtSurface, ref("c"), {}, {
        Tr.SwitchVariantStmtArm("red", {}, { Tr.StmtReturnValue(Tr.StmtSurface, lit(7)) }),
    }, { Tr.StmtReturnValue(Tr.StmtSurface, lit(0)) }),
})

local m_stmt = bind("local:m_stmt", "m", maybe_ty)
local stmt_func = Tr.FuncLocal("tag_stmt", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, m_stmt, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(33) })),
    Tr.StmtSwitch(Tr.StmtSurface, ref("m"), {}, {
        Tr.SwitchVariantStmtArm("some", { Tr.VariantBind("x", void) }, { Tr.StmtReturnValue(Tr.StmtSurface, ref("x")) }),
    }, { Tr.StmtReturnValue(Tr.StmtSurface, lit(0)) }),
})

local m_expr = bind("local:m_expr", "m", maybe_ty)
local expr_func = Tr.FuncLocal("tag_expr", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, m_expr, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(44) })),
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprSwitch(Tr.ExprSurface, ref("m"), {}, {
        Tr.SwitchVariantExprArm("some", { Tr.VariantBind("x", void) }, {}, ref("x")),
    }, {}, lit(0))),
})

local m_def = bind("local:m_def", "m", maybe_ty)
local default_func = Tr.FuncLocal("tag_default", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, m_def, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "none", {})),
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprSwitch(Tr.ExprSurface, ref("m"), {}, {
        Tr.SwitchVariantExprArm("some", { Tr.VariantBind("x", void) }, {}, ref("x")),
    }, {}, lit(5))),
})

local module = Tr.Module(Tr.ModuleSurface, {
    Tr.ItemType(maybe_decl), Tr.ItemType(color_decl),
    Tr.ItemFunc(enum_func), Tr.ItemFunc(stmt_func), Tr.ItemFunc(expr_func), Tr.ItemFunc(default_func),
})
local checked = Typecheck.check_module(module)
assert(#checked.issues == 0, "typecheck issues: " .. tostring(#checked.issues))
local layout_env = ModuleType.env(checked.module)
local unit = TreeToC.module(Layout.module(checked.module), { layout_env = layout_env })
local report = CValidate.validate(unit)
assert(#report.issues == 0, "C validation issues: " .. tostring(#report.issues))
local c_src = CEmit.emit(unit) .. [[
int main(void) {
    if (enum_red() != 7) return 101;
    if (tag_stmt() != 33) return 102;
    if (tag_expr() != 44) return 103;
    if (tag_default() != 5) return 104;
    return 0;
}
]]

if Harness.have_cc() then local built = Harness.compile_c(c_src, { cflags = "-std=c99 -Wall -Wextra" }); Harness.run_executable(built.exe_path) end

local bad = Typecheck.check_module(Tr.Module(Tr.ModuleSurface, { Tr.ItemType(maybe_decl), Tr.ItemFunc(Tr.FuncLocal("bad", {}, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprSwitch(Tr.ExprSurface, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "none", {}), {}, {
        Tr.SwitchVariantExprArm("missing", {}, {}, lit(1)),
    }, {}, lit(0))),
})) }))
local saw_unknown = false
for i = 1, #bad.issues do if pvm.classof(bad.issues[i]) == Tr.TypeIssueUnknownVariant then saw_unknown = true end end
assert(saw_unknown, "impossible variant arm should be diagnosed upstream")

io.write("moonlift C gcc tagged union ok\n")
