package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Const = require("moonlift.sem_const_eval")

local T = pvm.context()
A.Define(T)
local E = Const.Define(T)
local C = T.MoonCore
local Ty = T.MoonType
local B = T.MoonBind
local Sem = T.MoonSem
local Tr = T.MoonTree

local i32 = Ty.TScalar(C.ScalarI32)
local bool = Ty.TScalar(C.ScalarBool)
local function int(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end
local function boolean(v) return Tr.ExprLit(Tr.ExprTyped(bool), C.LitBool(v)) end

assert(E.value(int("42")) == Sem.ConstInt(i32, "42"))
assert(E.value(Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, int("2"), int("3"))) == Sem.ConstInt(i32, "5"))
assert(E.value(Tr.ExprBinary(Tr.ExprTyped(i32), C.BinMul, int("6"), int("7"))) == Sem.ConstInt(i32, "42"))
assert(E.value(Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpLt, int("1"), int("2"))) == Sem.ConstBool(true))
assert(E.value(Tr.ExprLogic(Tr.ExprTyped(bool), C.LogicAnd, boolean(true), boolean(false))) == Sem.ConstBool(false))
assert(E.value(Tr.ExprSelect(Tr.ExprTyped(i32), boolean(false), int("1"), int("9"))) == Sem.ConstInt(i32, "9"))

local x = B.Binding(C.Id("x"), "x", i32, B.BindingClassLocalValue)
local block = Tr.ExprBlock(Tr.ExprTyped(i32), {
    Tr.StmtLet(Tr.StmtTyped, x, int("10")),
}, Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefBinding(x)), int("5")))
assert(E.value(block) == Sem.ConstInt(i32, "15"))

local agg_ty = Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))
local agg = Tr.ExprAgg(Tr.ExprTyped(agg_ty), agg_ty, {
    Tr.FieldInit("left", int("1")),
    Tr.FieldInit("right", int("2")),
})
assert(E.value(Tr.ExprField(Tr.ExprTyped(i32), agg, Sem.FieldByName("right", i32))) == Sem.ConstInt(i32, "2"))

local global_binding = B.Binding(C.Id("global"), "global", i32, B.BindingClassGlobalConst("Demo", "answer"))
local const_env = B.ConstEnv({ B.ConstEntry("Demo", "answer", i32, int("99")) })
assert(E.value(Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefBinding(global_binding)), const_env) == Sem.ConstInt(i32, "99"))

local result = E.stmts({
    Tr.StmtLet(Tr.StmtTyped, x, int("4")),
    Tr.StmtReturnValue(Tr.StmtTyped, Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefBinding(x)), int("6"))),
})
assert(result == Sem.ConstStmtReturnValue(Sem.ConstLocalEnv({ Sem.ConstLocalEntry(x, Sem.ConstInt(i32, "4")) }), Sem.ConstInt(i32, "10")))

print("moonlift sem_const_eval ok")
