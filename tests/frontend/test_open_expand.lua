package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end
local A = require("moonlift.schema_projection")
local Expand = require("moonlift.open_expand")
local Facts = require("moonlift.open_facts")
local Validate = require("moonlift.open_validate")

local T = pvm.context()
A(T)
local E = Expand(T)
local F = Facts(T)
local V = Validate(T)
local C = T.MoonCore
local Ty = T.MoonType
local O = T.MoonOpen
local B = T.MoonBind
local Tr = T.MoonTree

local i32 = Ty.TScalar(C.ScalarI32)
local u64 = Ty.TScalar(C.ScalarU64)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end

local type_slot = O.TypeSlot("T", "T")
local expr_slot = O.ExprSlot("E", "E", i32)
local region_slot = O.RegionSlot("R", "R")
local items_slot = O.ItemsSlot("I", "I")
local module_slot = O.ModuleSlot("M", "M")

local env = O.ExpandEnv({}, {}, O.FillSet({
    O.SlotBinding(O.SlotType(type_slot), O.SlotValueType(u64)),
    O.SlotBinding(O.SlotExpr(expr_slot), O.SlotValueExpr(lit("7"))),
    O.SlotBinding(O.SlotRegion(region_slot), O.SlotValueRegion({
        Tr.StmtExpr(Tr.StmtSurface, lit("1")),
        Tr.StmtExpr(Tr.StmtSurface, lit("2")),
    })),
    O.SlotBinding(O.SlotItems(items_slot), O.SlotValueItems({
        Tr.ItemConst(Tr.ConstItem("a", i32, lit("3"))),
        Tr.ItemConst(Tr.ConstItem("b", i32, lit("4"))),
    })),
    O.SlotBinding(O.SlotModule(module_slot), O.SlotValueModule(Tr.Module(Tr.ModuleTyped("Nested"), {
        Tr.ItemConst(Tr.ConstItem("nested", i32, lit("5"))),
    }))),
}), {}, {}, "")

assert(E.type(Ty.TSlot(type_slot), env) == u64)
assert(E.expr(Tr.ExprSlotValue(Tr.ExprTyped(i32), expr_slot), env) == lit("7"))

local expanded_region = E.stmts({ Tr.StmtUseRegionSlot(Tr.StmtSurface, region_slot) }, env)
assert(#expanded_region == 2)
assert(expanded_region[1] == Tr.StmtExpr(Tr.StmtSurface, lit("1")))
assert(expanded_region[2] == Tr.StmtExpr(Tr.StmtSurface, lit("2")))

local item_region = as_list(E.item_region(Tr.ItemUseItemsSlot(items_slot), env))
assert(#item_region == 2)
assert(item_region[1] == Tr.ItemConst(Tr.ConstItem("a", i32, lit("3"))))
assert(item_region[2] == Tr.ItemConst(Tr.ConstItem("b", i32, lit("4"))))

local module_items = as_list(E.item_region(Tr.ItemUseModuleSlot("use.mod", module_slot, {}), env))
assert(#module_items == 1)
assert(module_items[1] == Tr.ItemConst(Tr.ConstItem("nested", i32, lit("5"))))

local param = O.OpenParam("x", "x", i32)
local binding = B.Binding(C.Id("x"), "x", i32, B.BindingClassOpenParam(param))
local frag = O.ExprFrag(O.NameRefText("frag"), { param }, O.OpenSet({}, {}, {}, {}), Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefBinding(binding)), i32)
local expanded_frag = E.expr(Tr.ExprUseExprFrag(Tr.ExprTyped(i32), "use.frag", O.ExprFragRefName("frag"), { lit("9") }, {}), E.env_with_frags({}, { frag }))
assert(expanded_frag == lit("9"))

local module = Tr.Module(
    Tr.ModuleOpen(O.ModuleNameFixed("Demo"), O.OpenSet({}, {}, {}, { O.SlotExpr(expr_slot) })),
    {
        Tr.ItemFunc(Tr.FuncLocal("f", {}, i32, {
            Tr.StmtExpr(Tr.StmtOpen(O.OpenSet({}, {}, {}, { O.SlotExpr(expr_slot) })), Tr.ExprSlotValue(Tr.ExprOpen(i32, O.OpenSet({}, {}, {}, { O.SlotExpr(expr_slot) })), expr_slot)),
        })),
        Tr.ItemUseItemsSlot(items_slot),
        Tr.ItemUseModuleSlot("module.slot", module_slot, {}),
    }
)

local expanded_module = E.module(module, env)
assert(expanded_module.h == Tr.ModuleTyped("Demo"))
assert(#expanded_module.items == 4)
local func_item = expanded_module.items[1]
assert(pvm.classof(func_item) == Tr.ItemFunc)
assert(func_item.func.body[1].h == Tr.StmtSurface)
assert(func_item.func.body[1].expr == lit("7"))

local report = V.validate(F.facts_of_module(expanded_module))
assert(#report.issues == 0)

print("moonlift open_expand ok")
