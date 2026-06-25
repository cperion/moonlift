package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Tr = T.LalinTree
local Ty = T.LalinType
local Bind = T.LalinBind
local Rules = require("lalin.tree_to_code_rules")(T)

local typed_i32 = Tr.ExprTyped(Ty.TScalar(Core.ScalarI32))
local typed_place_i32 = Tr.PlaceTyped(Ty.TScalar(Core.ScalarI32))
local binding = Bind.Binding(Core.Id("b:x"), "x", Ty.TScalar(Core.ScalarI32), Bind.BindingClassLocalValue)

local function assert_select(relation, node, family, kind)
    local input_name = relation:match("^select_(.-)_lowering$")
    local selection, err = Rules:run(relation, { [input_name] = node }, "selection")
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == kind, "expected " .. family .. " dispatch " .. kind .. ", got " .. tostring(selection.kind))
end

local function assert_expr(expr, kind)
    assert_select("select_expr_lowering", expr, "expr", kind)
end

local function assert_place(place, kind)
    assert_select("select_place_lowering", place, "place", kind)
end

local function assert_stmt(stmt, kind)
    assert_select("select_stmt_lowering", stmt, "stmt", kind)
end

assert_expr(Tr.ExprLit(typed_i32, Core.LitInt("1")), "lit")
assert_expr(Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding)), "ref")
assert_expr(Tr.ExprBinary(typed_i32, Core.BinAdd, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding)), Tr.ExprLit(typed_i32, Core.LitInt("1"))), "binary")
assert_expr(Tr.ExprCall(typed_i32, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding)), {}), "call")
assert_expr(Tr.ExprNull(typed_i32, Ty.TScalar(Core.ScalarI32)), "null")

assert_place(Tr.PlaceRef(typed_place_i32, Bind.ValueRefBinding(binding)), "ref")
assert_place(Tr.PlaceDeref(typed_place_i32, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding))), "deref")

assert_stmt(Tr.StmtLet(Tr.StmtSurface, binding, Tr.ExprLit(typed_i32, Core.LitInt("1"))), "let")
assert_stmt(Tr.StmtExpr(Tr.StmtSurface, Tr.ExprRef(typed_i32, Bind.ValueRefBinding(binding))), "expr")
assert_stmt(Tr.StmtReturnVoid(Tr.StmtSurface), "return_void")

assert_select("select_func_lowering", Tr.FuncLocal("f", {}, Ty.TScalar(Core.ScalarI32), {}), "func", "local")
assert_select("select_func_lowering", Tr.FuncExport("f", {}, Ty.TScalar(Core.ScalarI32), {}), "func", "export")
assert_select("select_item_lowering", Tr.ItemFunc(Tr.FuncLocal("f", {}, Ty.TScalar(Core.ScalarI32), {})), "item", "func")
assert_select("select_item_lowering", Tr.ItemConst(Tr.ConstItem("k", Ty.TScalar(Core.ScalarI32), Tr.ExprLit(typed_i32, Core.LitInt("1")))), "item", "const")
assert_select("select_contract_fact_lowering", Tr.ContractFactBounds(binding, binding), "contract_fact", "bounds")
assert_select("select_contract_fact_lowering", Tr.ContractFactNoAlias(binding), "contract_fact", "noalias")

io.write("lalin tree_to_code_rules ok\n")
