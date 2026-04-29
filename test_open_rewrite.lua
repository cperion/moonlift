package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Rewrite = require("moonlift.open_rewrite")

local T = pvm.context()
A.Define(T)
local R = Rewrite.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local O = T.Moon2Open
local B = T.Moon2Bind
local Tr = T.Moon2Tree

local i32 = Ty.TScalar(C.ScalarI32)
local i64 = Ty.TScalar(C.ScalarI64)
local ptr_i32 = Ty.TPtr(i32)
local ptr_i64 = Ty.TPtr(i64)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end

local one = lit("1")
local two = lit("2")
local three = lit("3")
local stmt_one = Tr.StmtExpr(Tr.StmtTyped, one)
local stmt_two = Tr.StmtExpr(Tr.StmtTyped, two)
local stmt_three = Tr.StmtExpr(Tr.StmtTyped, three)
local item_a = Tr.ItemConst(Tr.ConstItem("a", i32, one))
local item_b = Tr.ItemConst(Tr.ConstItem("b", i32, two))
local item_c = Tr.ItemConst(Tr.ConstItem("c", i32, three))

local binding_a = B.Binding(C.Id("a"), "a", ptr_i32, B.BindingClassLocalValue)
local binding_b = B.Binding(C.Id("b"), "b", ptr_i64, B.BindingClassLocalValue)
local place_a = Tr.PlaceRef(Tr.PlaceTyped(ptr_i32), B.ValueRefBinding(binding_a))
local place_b = Tr.PlaceRef(Tr.PlaceTyped(ptr_i64), B.ValueRefBinding(binding_b))
local domain_a = Tr.DomainRange(one)
local domain_b = Tr.DomainRange(two)

local set = O.RewriteSet({
    O.RewriteType(i32, i64),
    O.RewriteExpr(one, two),
    O.RewriteBinding(binding_a, binding_b),
    O.RewritePlace(place_a, place_b),
    O.RewriteDomain(domain_a, domain_b),
    O.RewriteStmt(stmt_one, { stmt_two, stmt_three }),
    O.RewriteItem(item_a, { item_b, item_c }),
})

assert(R.type(i32, set) == i64)
assert(R.type(ptr_i32, set) == Ty.TPtr(i64))
assert(R.expr(one, set) == two)
assert(R.expr(Tr.ExprUnary(Tr.ExprTyped(i32), C.UnaryNeg, one), set) == Tr.ExprUnary(Tr.ExprTyped(i32), C.UnaryNeg, two))
assert(R.expr(Tr.ExprCast(Tr.ExprTyped(ptr_i32), C.SurfaceCast, ptr_i32, one), set) == Tr.ExprCast(Tr.ExprTyped(ptr_i32), C.SurfaceCast, ptr_i64, two))
assert(R.expr(Tr.ExprRef(Tr.ExprTyped(ptr_i32), B.ValueRefBinding(binding_a)), set) == Tr.ExprRef(Tr.ExprTyped(ptr_i32), B.ValueRefBinding(binding_b)))
assert(R.rewrite_place and R.type)
assert(pvm.one(R.rewrite_place(place_a, set)) == place_b)
assert(pvm.one(R.rewrite_domain(domain_a, set)) == domain_b)

local stmts = R.stmts({ stmt_one }, set)
assert(#stmts == 2)
assert(stmts[1] == stmt_two)
assert(stmts[2] == stmt_three)

local module = Tr.Module(Tr.ModuleTyped("Demo"), {
    item_a,
    Tr.ItemFunc(Tr.FuncLocal("f", {}, i32, {
        Tr.StmtReturnValue(Tr.StmtTyped, one),
    })),
})
local rewritten = R.module(module, set)
assert(#rewritten.items == 3)
assert(rewritten.items[1] == item_b)
assert(rewritten.items[2] == item_c)
local func_item = rewritten.items[3]
assert(func_item.func.body[1] == Tr.StmtReturnValue(Tr.StmtTyped, two))

print("moonlift open_rewrite ok")
