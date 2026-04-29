package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Expand = require("moonlift.open_expand")
local Facts = require("moonlift.open_facts")
local Validate = require("moonlift.open_validate")

local T = pvm.context()
A.Define(T)
local E = Expand.Define(T)
local F = Facts.Define(T)
local V = Validate.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local O = T.Moon2Open
local B = T.Moon2Bind
local Tr = T.Moon2Tree

local i32 = Ty.TScalar(C.ScalarI32)
local u64 = Ty.TScalar(C.ScalarU64)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end

local type_slot = O.TypeSlot("T", "T")
local expr_slot = O.ExprSlot("E", "E", i32)
local region_slot = O.RegionSlot("R", "R")
local items_slot = O.ItemsSlot("I", "I")
local module_slot = O.ModuleSlot("M", "M")

local env = O.ExpandEnv(O.FillSet({
    O.SlotBinding(O.SlotType(type_slot), O.SlotValueType(u64)),
    O.SlotBinding(O.SlotExpr(expr_slot), O.SlotValueExpr(lit("7"))),
    O.SlotBinding(O.SlotRegion(region_slot), O.SlotValueRegion({
        Tr.StmtExpr(Tr.StmtTyped, lit("1")),
        Tr.StmtExpr(Tr.StmtTyped, lit("2")),
    })),
    O.SlotBinding(O.SlotItems(items_slot), O.SlotValueItems({
        Tr.ItemConst(Tr.ConstItem("a", i32, lit("3"))),
        Tr.ItemConst(Tr.ConstItem("b", i32, lit("4"))),
    })),
    O.SlotBinding(O.SlotModule(module_slot), O.SlotValueModule(Tr.Module(Tr.ModuleTyped("Nested"), {
        Tr.ItemConst(Tr.ConstItem("nested", i32, lit("5"))),
    }))),
}), {}, "")

assert(E.type(Ty.TSlot(type_slot), env) == u64)
assert(E.expr(Tr.ExprSlotValue(Tr.ExprTyped(i32), expr_slot), env) == lit("7"))

local expanded_region = E.stmts({ Tr.StmtUseRegionSlot(Tr.StmtTyped, region_slot) }, env)
assert(#expanded_region == 2)
assert(expanded_region[1] == Tr.StmtExpr(Tr.StmtTyped, lit("1")))
assert(expanded_region[2] == Tr.StmtExpr(Tr.StmtTyped, lit("2")))

local item_stream = pvm.drain(E.item_stream(Tr.ItemUseItemsSlot(items_slot), env))
assert(#item_stream == 2)
assert(item_stream[1] == Tr.ItemConst(Tr.ConstItem("a", i32, lit("3"))))
assert(item_stream[2] == Tr.ItemConst(Tr.ConstItem("b", i32, lit("4"))))

local module_items = pvm.drain(E.item_stream(Tr.ItemUseModuleSlot("use.mod", module_slot, {}), env))
assert(#module_items == 1)
assert(module_items[1] == Tr.ItemConst(Tr.ConstItem("nested", i32, lit("5"))))

local param = O.OpenParam("x", "x", i32)
local binding = B.Binding(C.Id("x"), "x", i32, B.BindingClassOpenParam(param))
local frag = O.ExprFrag({ param }, O.OpenSet({}, {}, {}, {}), Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefBinding(binding)), i32)
local expanded_frag = E.expr(Tr.ExprUseExprFrag(Tr.ExprTyped(i32), "frag", frag, { lit("9") }, {}), E.empty_env())
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
assert(func_item.func.body[1].h == Tr.StmtTyped)
assert(func_item.func.body[1].expr == lit("7"))

local report = V.validate(F.facts_of_module(expanded_module))
assert(#report.issues == 0)

print("moonlift open_expand ok")
