package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Tr = T.LalinTree
local Ty = T.LalinType
local Bind = T.LalinBind
local Open = T.LalinOpen
local Rules = require("lalin.tree_typecheck_rules")(T)

local i32 = Ty.TScalar(Core.ScalarI32)
local binding = Bind.Binding(Core.Id("b:x"), "x", i32, Bind.BindingClassLocalValue)
local expr = Tr.ExprLit(Tr.ExprSurface, Core.LitInt("1"))

local function assert_select(relation, node, family, kind)
    local input_name = ({
        select_stmt_typecheck = "stmt",
        select_expr_typecheck = "expr",
        select_view_typecheck = "view",
        select_index_base_typecheck = "index_base",
        select_place_typecheck = "place",
        select_control_stmt_region_typecheck = "control_stmt_region",
        select_control_expr_region_typecheck = "control_expr_region",
        select_func_typecheck = "func",
        select_item_typecheck = "item",
        select_module_typecheck = "module",
    })[relation]
    local selection, err = Rules:run(relation, { [input_name] = node }, "selection")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == kind, "expected " .. family .. " typecheck dispatch " .. kind .. ", got " .. tostring(selection.kind))
end

local function assert_expr(expr_node, kind)
    assert_select("select_expr_typecheck", expr_node, "expr", kind)
end

local function assert_stmt(stmt, kind)
    assert_select("select_stmt_typecheck", stmt, "stmt", kind)
end

assert_expr(expr, "lit")
assert_expr(Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefBinding(binding)), "ref")
assert_expr(Tr.ExprBinary(Tr.ExprSurface, Core.BinAdd, expr, expr), "binary")
assert_expr(Tr.ExprCall(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefBinding(binding)), {}), "call")
assert_expr(Tr.ExprNull(Tr.ExprSurface, Ty.TPtr(i32)), "null")

assert_stmt(Tr.StmtLet(Tr.StmtSurface, binding, expr), "let")
assert_stmt(Tr.StmtVar(Tr.StmtSurface, binding, expr), "var")
assert_stmt(Tr.StmtExpr(Tr.StmtSurface, expr), "expr")
assert_stmt(Tr.StmtReturnVoid(Tr.StmtSurface), "return_void")
assert_stmt(Tr.StmtTrap(Tr.StmtSurface), "trap")

assert_select("select_view_typecheck", Tr.ViewFromExpr(expr, i32), "view", "from_expr")
assert_select("select_view_typecheck", Tr.ViewContiguous(expr, i32, expr), "view", "contiguous")
assert_select("select_index_base_typecheck", Tr.IndexBaseExpr(expr), "index_base", "expr")
assert_select("select_place_typecheck", Tr.PlaceRef(Tr.PlaceSurface, Bind.ValueRefBinding(binding)), "place", "ref")
assert_select("select_place_typecheck", Tr.PlaceDeref(Tr.PlaceSurface, expr), "place", "deref")
assert_select("select_control_stmt_region_typecheck", Tr.ControlStmtRegion("r", Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, {}), {}), "control_stmt_region", "stmt_region")
assert_select("select_control_expr_region_typecheck", Tr.ControlExprRegion("r", i32, Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, {}), {}), "control_expr_region", "expr_region")
assert_select("select_func_typecheck", Tr.FuncLocal("f", {}, i32, {}), "func", "local")
assert_select("select_func_typecheck", Tr.FuncOpen(Core.FuncSym("f", "f"), Core.VisibilityLocal, {}, Open.OpenSet({}, {}, {}, {}), i32, {}), "func", "open")
assert_select("select_item_typecheck", Tr.ItemFunc(Tr.FuncLocal("f", {}, i32, {})), "item", "func")
assert_select("select_item_typecheck", Tr.ItemUseItemsSlot(Open.ItemsSlot("items", "items")), "item", "use_items_slot")
assert_select("select_module_typecheck", Tr.Module(Tr.ModuleSurface, {}), "module", "module")

io.write("lalin tree_typecheck_rules ok\n")
