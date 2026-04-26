package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Switch = require("moonlift.sem_switch_decide")
local Call = require("moonlift.sem_call_decide")

local T = pvm.context()
A.Define(T)
local S = Switch.Define(T)
local CallD = Call.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local O = T.Moon2Open
local B = T.Moon2Bind
local Sem = T.Moon2Sem
local Tr = T.Moon2Tree

local i32 = Ty.TScalar(C.ScalarI32)
local fn_ty = Ty.TFunc({ i32 }, i32)
local closure_ty = Ty.TClosure({ i32 }, i32)
local key1 = Sem.SwitchKeyRaw("1")
local key2 = Sem.SwitchKeyConst(Sem.ConstInt(i32, "2"))
local expr_key = Sem.SwitchKeyExpr(Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt("3")))

assert(S.keys({ key1, key2 }) == Sem.SwitchDecisionConstKeys({ key1, key2 }))
assert(S.keys({ expr_key }) == Sem.SwitchDecisionExprKeys({ expr_key }))
assert(S.keys({ key1, expr_key }) == Sem.SwitchDecisionCompareFallback({ key1, expr_key }, "mixed const and expression switch keys"))

local switch_stmt = Tr.StmtSwitch(Tr.StmtTyped, Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt("0")), {
    Tr.SwitchStmtArm(key1, {}),
    Tr.SwitchStmtArm(key2, {}),
}, {})
assert(S.stmt(switch_stmt) == Sem.SwitchDecisionConstKeys({ key1, key2 }))

local direct_binding = B.Binding(C.Id("f"), "f", fn_ty, B.BindingClassGlobalFunc("Demo", "f"))
local direct_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(direct_binding))
assert(CallD.decide(direct_expr, fn_ty) == Sem.CallDirect("Demo", "f", fn_ty))

local extern_binding = B.Binding(C.Id("puts"), "puts", fn_ty, B.BindingClassExtern("puts"))
local extern_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(extern_binding))
assert(CallD.decide(extern_expr, fn_ty) == Sem.CallExtern("puts", fn_ty))

local import_binding = B.Binding(C.Id("imp"), "imp", fn_ty, B.BindingClassImport(O.ImportGlobalFunc("imp", "Other", "g", fn_ty)))
local import_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(import_binding))
assert(CallD.decide(import_expr, fn_ty) == Sem.CallDirect("Other", "g", fn_ty))

local local_binding = B.Binding(C.Id("fp"), "fp", fn_ty, B.BindingClassLocalValue)
local local_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(local_binding))
assert(CallD.decide(local_expr, fn_ty) == Sem.CallIndirect(local_expr, fn_ty))

local closure_expr = Tr.ExprRef(Tr.ExprTyped(closure_ty), B.ValueRefBinding(B.Binding(C.Id("cl"), "cl", closure_ty, B.BindingClassLocalValue)))
assert(CallD.decide(closure_expr, closure_ty) == Sem.CallClosure(closure_expr, closure_ty))

local unresolved = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefName("late"))
assert(CallD.decide(unresolved, fn_ty) == Sem.CallUnresolved(unresolved))

print("moonlift sem_switch_call ok")
