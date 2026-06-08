package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local Open = T.MoonOpen
local Pipeline = require("moonlift.frontend_pipeline").Define(T)

local i32 = Ty.TScalar(Core.ScalarI32)
local void = Ty.TScalar(Core.ScalarVoid)

local function class_counts(root)
    local counts, seen = {}, {}
    local function walk(node)
        if type(node) ~= "table" or seen[node] then return end
        seen[node] = true
        local cls = pvm.classof(node)
        if cls then
            if cls.kind ~= nil then counts[cls.kind] = (counts[cls.kind] or 0) + 1 end
            local fields = cls.__fields or {}
            for i = 1, #fields do walk(node[fields[i].name]) end
        else
            for _, value in pairs(node) do walk(value) end
        end
    end
    walk(root)
    return counts
end

local function assert_absent(counts, kind)
    assert((counts[kind] or 0) == 0, kind .. " reached the C phase boundary")
end

local function assert_present(counts, kind)
    assert((counts[kind] or 0) > 0, kind .. " was not observed in resolved form")
end

local resolved_case = Pipeline.parse_and_lower_c([[
struct Pair
    x: i32
end

func get_x(p: ptr(Pair)): i32
    return (*p).x
end

func set_x(p: ptr(Pair), v: i32): i32
    (*p).x = v
    return (*p).x
end

func cast_u8(p: ptr(u8)): i32
    return as(i32, p[0])
end
]], { site = "test_c_backend_phase_boundaries:resolved" })

local counts = class_counts(resolved_case.resolved)
assert_absent(counts, "ExprDot")
assert_absent(counts, "PlaceDot")
assert_absent(counts, "ExprCast")
assert_absent(counts, "SurfaceCast")
assert_present(counts, "ExprField")
assert_present(counts, "PlaceField")
assert_present(counts, "ExprMachineCast")

local function lit(n)
    return Tr.ExprLit(Tr.ExprSurface, Core.LitInt(tostring(n)))
end

local function local_func(name, result, body)
    return Tr.ItemFunc(Tr.FuncLocal(name, {}, result, body))
end

local function module_with(items)
    return Tr.Module(Tr.ModuleSurface, items)
end

local function must_fail_before_tree_to_c(label, module, pattern)
    local ok, err = pcall(function()
        Pipeline.lower_module_to_c(module, { site = label })
    end)
    assert(not ok, label .. " unexpectedly reached C lowering successfully")
    err = tostring(err)
    assert(not err:match("lua/moonlift/tree_to_c%.lua"), label .. " failed inside tree_to_c instead of an earlier phase/boundary: " .. err)
    if pattern then assert(err:match(pattern), label .. " error did not match " .. pattern .. ": " .. err) end
end

local closure_expr = Tr.ExprClosure(Tr.ExprSurface, {}, i32, { Tr.StmtReturnValue(Tr.StmtSurface, lit(1)) })
local closure_case = Pipeline.lower_module_to_c(module_with({
    local_func("closure_boundary", void, { Tr.StmtExpr(Tr.StmtSurface, closure_expr), Tr.StmtReturnVoid(Tr.StmtSurface) }),
}), { site = "test_c_backend_phase_boundaries:closure" })
assert_absent(class_counts(closure_case.resolved), "ExprClosure")

must_fail_before_tree_to_c("test_c_backend_phase_boundaries:FuncOpen", module_with({
    Tr.ItemFunc(Tr.FuncOpen(Core.FuncSym("open_f", "open_f"), Core.VisibilityLocal, {}, Open.OpenSet({}, {}, {}, {}), i32, { Tr.StmtReturnValue(Tr.StmtSurface, lit(0)) })),
}), "phase boundary")

must_fail_before_tree_to_c("test_c_backend_phase_boundaries:ExternFuncOpen", module_with({
    Tr.ItemExtern(Tr.ExternFuncOpen(Core.ExternSym("open_e", "open_e", "open_e"), {}, i32)),
}), "phase boundary")

must_fail_before_tree_to_c("test_c_backend_phase_boundaries:ItemImport", module_with({
    Tr.ItemImport(Tr.ImportItem(Core.Path({ Core.Name("not_resolved") }))),
}), "phase boundary")

must_fail_before_tree_to_c("test_c_backend_phase_boundaries:ItemUseItemsSlot", module_with({
    Tr.ItemUseItemsSlot(Open.ItemsSlot("items", "items")),
}), "unfilled items slot")

must_fail_before_tree_to_c("test_c_backend_phase_boundaries:ExprSlotValue", module_with({
    local_func("expr_slot", i32, { Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprSlotValue(Tr.ExprSurface, Open.ExprSlot("expr", "expr", i32))) }),
}), "unfilled expression slot")

must_fail_before_tree_to_c("test_c_backend_phase_boundaries:ExprUseExprFrag", module_with({
    local_func("expr_frag", i32, { Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprUseExprFrag(Tr.ExprSurface, "frag_use", Open.ExprFragRefName("missing_frag"), {}, {})) }),
}), "unexpanded expression fragment use")

must_fail_before_tree_to_c("test_c_backend_phase_boundaries:StmtUseRegionFrag", module_with({
    local_func("region_frag", void, { Tr.StmtUseRegionFrag(Tr.StmtSurface, "region_use", Open.RegionFragRefName("missing_region"), {}, {}, {}), Tr.StmtReturnVoid(Tr.StmtSurface) }),
}), "unexpanded region fragment use")

io.write("moonlift C backend phase boundaries ok\n")
