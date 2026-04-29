package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Facts = require("moonlift.open_facts")
local Validate = require("moonlift.open_validate")

local T = pvm.context()
A.Define(T)
local F = Facts.Define(T)
local V = Validate.Define(T)
local C = T.MoonCore
local Ty = T.MoonType
local O = T.MoonOpen
local Tr = T.MoonTree

local i32 = Ty.TScalar(C.ScalarI32)
local lit = Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt("1"))

local type_slot = O.TypeSlot("T", "T")
local value_slot = O.ValueSlot("v", "v", i32)
local expr_slot = O.ExprSlot("e", "e", i32)
local place_slot = O.PlaceSlot("p", "p", i32)
local domain_slot = O.DomainSlot("d", "d")
local region_slot = O.RegionSlot("r", "r")
local func_slot = O.FuncSlot("f", "f", Ty.TFunc({}, i32))
local const_slot = O.ConstSlot("c", "c", i32)
local static_slot = O.StaticSlot("s", "s", i32)
local type_decl_slot = O.TypeDeclSlot("td", "td")
local items_slot = O.ItemsSlot("items", "items")
local module_slot = O.ModuleSlot("m", "m")

local import_value = O.ImportValue("imp", "imp", i32)
local import_func = O.ImportGlobalFunc("gf", "Other", "f", Ty.TFunc({}, i32))
local import_const = O.ImportGlobalConst("gc", "Other", "c", i32)
local import_static = O.ImportGlobalStatic("gs", "Other", "s", i32)
local import_extern = O.ImportExtern("ex", "puts", Ty.TFunc({}, i32))

local open = O.OpenSet(
    { import_value, import_func, import_const, import_static, import_extern },
    {},
    {},
    {
        O.SlotType(type_slot),
        O.SlotValue(value_slot),
        O.SlotExpr(expr_slot),
        O.SlotPlace(place_slot),
        O.SlotDomain(domain_slot),
        O.SlotRegion(region_slot),
        O.SlotFunc(func_slot),
        O.SlotConst(const_slot),
        O.SlotStatic(static_slot),
        O.SlotTypeDecl(type_decl_slot),
        O.SlotItems(items_slot),
        O.SlotModule(module_slot),
    }
)

local function has(xs, needle)
    for i = 1, #xs do
        if xs[i] == needle then return true end
    end
    return false
end

local open_facts = F.facts_of_open_set(open)
assert(has(open_facts.facts, O.MetaFactValueImportUse(import_value)))
assert(has(open_facts.facts, O.MetaFactGlobalFunc("Other", "f")))
assert(has(open_facts.facts, O.MetaFactGlobalConst("Other", "c")))
assert(has(open_facts.facts, O.MetaFactGlobalStatic("Other", "s")))
assert(has(open_facts.facts, O.MetaFactExtern("puts")))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotType(type_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotValue(value_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotExpr(expr_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotPlace(place_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotDomain(domain_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotRegion(region_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotFunc(func_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotConst(const_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotStatic(static_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotTypeDecl(type_decl_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotItems(items_slot))))
assert(has(open_facts.facts, O.MetaFactSlot(O.SlotModule(module_slot))))

local report = V.validate(open_facts)
assert(has(report.issues, O.IssueGenericValueImport(import_value)))
assert(has(report.issues, O.IssueUnfilledTypeSlot(type_slot)))
assert(has(report.issues, O.IssueOpenSlot(O.SlotValue(value_slot))))
assert(has(report.issues, O.IssueUnfilledExprSlot(expr_slot)))
assert(has(report.issues, O.IssueUnfilledPlaceSlot(place_slot)))
assert(has(report.issues, O.IssueUnfilledDomainSlot(domain_slot)))
assert(has(report.issues, O.IssueUnfilledRegionSlot(region_slot)))
assert(has(report.issues, O.IssueUnfilledFuncSlot(func_slot)))
assert(has(report.issues, O.IssueUnfilledConstSlot(const_slot)))
assert(has(report.issues, O.IssueUnfilledStaticSlot(static_slot)))
assert(has(report.issues, O.IssueUnfilledTypeDeclSlot(type_decl_slot)))
assert(has(report.issues, O.IssueUnfilledItemsSlot(items_slot)))
assert(has(report.issues, O.IssueUnfilledModuleSlot(module_slot)))

local expr_frag = O.ExprFrag({}, O.OpenSet({}, {}, {}, { O.SlotExpr(expr_slot) }), Tr.ExprSlotValue(Tr.ExprTyped(i32), expr_slot), i32)
local region_frag = O.RegionFrag({}, O.OpenSet({}, {}, {}, { O.SlotRegion(region_slot) }), { Tr.StmtUseRegionSlot(Tr.StmtTyped, region_slot) })
local nested_module = Tr.Module(Tr.ModuleTyped("Nested"), {})
local module = Tr.Module(
    Tr.ModuleOpen(O.ModuleNameOpen, O.OpenSet({}, {}, {}, {})),
    {
        Tr.ItemFunc(Tr.FuncLocal("f", {}, i32, {
            Tr.StmtExpr(Tr.StmtTyped, Tr.ExprUseExprFrag(Tr.ExprTyped(i32), "expr.use", expr_frag, { lit }, {})),
            Tr.StmtUseRegionFrag(Tr.StmtTyped, "region.use", region_frag, { lit }, {}),
        })),
        Tr.ItemUseTypeDeclSlot(type_decl_slot),
        Tr.ItemUseItemsSlot(items_slot),
        Tr.ItemUseModule("module.use", nested_module, {}),
        Tr.ItemUseModuleSlot("module.slot.use", module_slot, {}),
    }
)

local module_facts = F.facts_of_module(module)
assert(has(module_facts.facts, O.MetaFactOpenModuleName))
assert(has(module_facts.facts, O.MetaFactExprFragUse("expr.use")))
assert(has(module_facts.facts, O.MetaFactRegionFragUse("region.use")))
assert(has(module_facts.facts, O.MetaFactModuleUse("module.use")))
assert(has(module_facts.facts, O.MetaFactModuleSlotUse("module.slot.use", module_slot)))
assert(has(module_facts.facts, O.MetaFactSlot(O.SlotExpr(expr_slot))))
assert(has(module_facts.facts, O.MetaFactSlot(O.SlotRegion(region_slot))))
assert(has(module_facts.facts, O.MetaFactSlot(O.SlotTypeDecl(type_decl_slot))))
assert(has(module_facts.facts, O.MetaFactSlot(O.SlotItems(items_slot))))
assert(has(module_facts.facts, O.MetaFactSlot(O.SlotModule(module_slot))))

local module_report = V.validate(module_facts)
assert(has(module_report.issues, O.IssueOpenModuleName))
assert(has(module_report.issues, O.IssueUnexpandedExprFragUse("expr.use")))
assert(has(module_report.issues, O.IssueUnexpandedRegionFragUse("region.use")))
assert(has(module_report.issues, O.IssueUnexpandedModuleUse("module.use")))
assert(has(module_report.issues, O.IssueUnfilledExprSlot(expr_slot)))
assert(has(module_report.issues, O.IssueUnfilledRegionSlot(region_slot)))
assert(has(module_report.issues, O.IssueUnfilledTypeDeclSlot(type_decl_slot)))
assert(has(module_report.issues, O.IssueUnfilledItemsSlot(items_slot)))
assert(has(module_report.issues, O.IssueUnfilledModuleSlot(module_slot)))

print("moonlift open_facts_validate ok")
