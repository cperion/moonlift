package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local B = T.MoonBind
local Sem = T.MoonSem

local Typecheck = require("moonlift.tree_typecheck").Define(T)
local ModuleType = require("moonlift.tree_module_type").Define(T)
local Parse = require("moonlift.parse").Define(T)

local i32 = Ty.TScalar(Core.ScalarI32)
local void = Ty.TScalar(Core.ScalarVoid)
local maybe_ty = Ty.TNamed(Ty.TypeRefGlobal("", "Maybe"))
local maybe_decl = Tr.TypeDeclTaggedUnionSugar("Maybe", {
    Ty.VariantDecl("some", i32, {}),
    Ty.VariantDecl("none", void, {}),
})
local enum_decl = Tr.TypeDeclEnumSugar("Color", { Core.Name("red"), Core.Name("green") })

local function lit(n) return Tr.ExprLit(Tr.ExprSurface, Core.LitInt(tostring(n))) end
local function ref(name) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name)) end

local make_some = Tr.FuncLocal("make_some", {}, maybe_ty, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprCtor(Tr.ExprSurface, "Maybe", "some", { lit(7) })),
})
local match_some = Tr.FuncLocal("match_some", { Ty.Param("m", maybe_ty) }, i32, {
    Tr.StmtSwitch(Tr.StmtSurface, ref("m"), {}, {
        Tr.SwitchVariantStmtArm("some", { Tr.VariantBind("x", void) }, { Tr.StmtReturnValue(Tr.StmtSurface, ref("x")) }),
    }, { Tr.StmtReturnValue(Tr.StmtSurface, lit(0)) }),
})
local match_expr = Tr.FuncLocal("match_expr", { Ty.Param("m", maybe_ty) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprSwitch(Tr.ExprSurface, ref("m"), {}, {
        Tr.SwitchVariantExprArm("some", { Tr.VariantBind("x", void) }, {}, ref("x")),
    }, {}, lit(0))),
})

local module = Tr.Module(Tr.ModuleSurface, {
    Tr.ItemType(maybe_decl),
    Tr.ItemType(enum_decl),
    Tr.ItemFunc(make_some),
    Tr.ItemFunc(match_some),
    Tr.ItemFunc(match_expr),
})

local checked = Typecheck.check_module(module)
assert(#checked.issues == 0, "tagged union typecheck issues: " .. tostring(#checked.issues))

local env = ModuleType.env(module)
local maybe_layout, color_layout
for i = 1, #env.layouts do
    local l = env.layouts[i]
    if pvm.classof(l) == Sem.LayoutNamed and l.type_name == "Maybe" then maybe_layout = l end
    if pvm.classof(l) == Sem.LayoutNamed and l.type_name == "Color" then color_layout = l end
end
assert(maybe_layout, "missing tagged-union layout")
assert(color_layout, "missing enum layout")
assert(maybe_layout.fields[1].field_name == "__tag", "tagged union missing __tag")
assert(maybe_layout.fields[2].field_name == "__payload", "tagged union missing __payload")
assert(color_layout.fields[1].field_name == "__tag" and #color_layout.fields == 1, "enum should be tag-only")

local checked_func = checked.module.items[4].func
local switch = checked_func.body[1]
assert(pvm.classof(switch.variant_arms[1].binds[1].ty) == Ty.TScalar and switch.variant_arms[1].binds[1].ty.scalar == Core.ScalarI32, "variant bind should adopt payload type")
local checked_expr_func = checked.module.items[5].func
local expr_switch = checked_expr_func.body[1].value
assert(#expr_switch.variant_arms == 1, "expression switch should retain variant arms")
assert(pvm.classof(expr_switch.variant_arms[1].binds[1].ty) == Ty.TScalar and expr_switch.variant_arms[1].binds[1].ty.scalar == Core.ScalarI32, "expression variant bind should adopt payload type")

local dup = Typecheck.check_module(Tr.Module(Tr.ModuleSurface, { Tr.ItemType(Tr.TypeDeclTaggedUnionSugar("Bad", { Ty.VariantDecl("x", void, {}), Ty.VariantDecl("x", void, {}) })) }))
local saw_dup = false
for i = 1, #dup.issues do if pvm.classof(dup.issues[i]) == Tr.TypeIssueDuplicateVariant then saw_dup = true end end
assert(saw_dup, "duplicate variants should be diagnosed")

local parsed = Parse.parse_module([[
union MaybeParsed some(i32) | none end
func parsed_match(m: MaybeParsed): i32
    return switch m do
        case .some(x) then
            x
        case .none then
            0
        default then
            0 - 1
    end
end
]])
assert(#parsed.issues == 0, "variant switch expression parse issues: " .. tostring(#parsed.issues))
local parsed_switch = parsed.module.items[2].func.body[1].value
assert(#parsed_switch.variant_arms == 2, "parser should populate ExprSwitch.variant_arms")
local parsed_checked = Typecheck.check_module(parsed.module)
assert(#parsed_checked.issues == 0, "parsed variant expr switch typecheck issues: " .. tostring(#parsed_checked.issues))
local parsed_checked_switch = parsed_checked.module.items[2].func.body[1].value
assert(pvm.classof(parsed_checked_switch.variant_arms[1].binds[1].ty) == Ty.TScalar and parsed_checked_switch.variant_arms[1].binds[1].ty.scalar == Core.ScalarI32, "parsed expression variant bind should typecheck")

io.write("moonlift tagged union type/layout ok\n")
