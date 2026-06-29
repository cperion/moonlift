package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context()
Schema(T)
require("lalin.tree_to_code")(T)

local Core = T.LalinCore
local Tr = T.LalinTree
local Ty = T.LalinType
local Bind = T.LalinBind

local typed_i32 = Tr.ExprTyped(Ty.TScalar(Core.ScalarI32))
local typed_place_i32 = Tr.PlaceTyped(Ty.TScalar(Core.ScalarI32))
local binding = Bind.Binding(Core.Id("b:x"), "x", Ty.TScalar(Core.ScalarI32), Bind.BindingClassLocalValue)

local function assert_method(node, name)
    assert(type(node[name]) == "function", "missing method " .. name)
end

assert_method(Tr.ExprLit(typed_i32, Core.LitInt("1")), "lower_tree_expr_to_code")
assert_method(Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding)), "lower_tree_expr_to_code")
assert_method(Tr.ExprBinary(typed_i32, Core.BinAdd, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding)), Tr.ExprLit(typed_i32, Core.LitInt("1"))), "lower_tree_expr_to_code")
assert_method(Tr.ExprCall(typed_i32, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding)), {}), "lower_tree_expr_to_code")
assert_method(Tr.ExprNull(typed_i32, Ty.TScalar(Core.ScalarI32)), "lower_tree_expr_to_code")

assert_method(Tr.PlaceRef(typed_place_i32, Bind.ValueRefBinding(binding)), "lower_tree_place_to_code")
assert_method(Tr.PlaceDeref(typed_place_i32, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding))), "lower_tree_place_to_code")

assert_method(Tr.StmtLet(Tr.StmtSurface, binding, Tr.ExprLit(typed_i32, Core.LitInt("1"))), "lower_tree_stmt_to_code")
assert_method(Tr.StmtExpr(Tr.StmtSurface, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding))), "lower_tree_stmt_to_code")
assert_method(Tr.StmtReturnVoid(Tr.StmtSurface), "lower_tree_stmt_to_code")

assert_method(Tr.FuncLocal("f", {}, Ty.TScalar(Core.ScalarI32), {}), "lower_tree_func_parts_to_code")
assert_method(Tr.FuncExport("f", {}, Ty.TScalar(Core.ScalarI32), {}), "lower_tree_func_parts_to_code")
assert_method(Tr.ItemFunc(Tr.FuncLocal("f", {}, Ty.TScalar(Core.ScalarI32), {})), "lower_tree_item_to_code")
assert_method(Tr.ItemConst(Tr.ConstItem("k", Ty.TScalar(Core.ScalarI32), Tr.ExprLit(typed_i32, Core.LitInt("1")))), "lower_tree_item_to_code")
assert_method(Tr.ContractFactBounds(binding, binding), "lower_tree_contract_fact_to_code")
assert_method(Tr.ContractFactNoAlias(binding), "lower_tree_contract_fact_to_code")

local ok = pcall(require, "lalin.tree_to_code_rules")
assert(not ok, "tree_to_code_rules must not exist")

io.write("lalin tree_to_code methods ok\n")
