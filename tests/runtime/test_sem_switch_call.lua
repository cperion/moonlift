package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local A = require("lalin.schema_projection")
local Switch = require("lalin.sem_switch_decide")
local Call = require("lalin.sem_call_decide")

local T = pvm.context()
A(T)
local S = Switch(T)
local CallD = Call(T)
local C = T.LalinCore
local Ty = T.LalinType
local O = T.LalinOpen
local B = T.LalinBind
local Sem = T.LalinSem
local Tr = T.LalinTree

local i32 = Ty.TScalar(C.ScalarI32)
local fn_ty = Ty.TFunc({ i32 }, i32)
local closure_ty = Ty.TClosure({ i32 }, i32)
local key1 = "1"
local key2 = "2"
local expr_key = ""

local function assert_keys_equal(a, b)
    assert(a.kind == b.kind)
    if a.reason then assert(a.reason == b.reason) end
end

assert_keys_equal(S.keys({ key1, key2 }), { kind = "const_keys", keys = { key1, key2 } })
assert_keys_equal(S.keys({ expr_key }), { kind = "expr_keys", keys = { expr_key } })
assert_keys_equal(S.keys({ key1, expr_key }), { kind = "compare_fallback", keys = { key1, expr_key }, reason = "mixed const and expression switch keys" })

local direct_binding = B.Binding(C.Id("f"), "f", fn_ty, B.BindingClassGlobalFunc("Demo", "f"))
local direct_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(direct_binding))
local function assert_call_equal(a, b)
    assert(a.kind == b.kind)
    for _, k in ipairs({"callee", "closure", "fn_ty", "module_name", "item_name", "symbol"}) do
        if a[k] ~= nil then assert(a[k] == b[k]) end
    end
end

local r1 = CallD.decide(direct_expr, fn_ty)
assert_call_equal(r1, { kind = "direct", module_name = "Demo", item_name = "f", fn_ty = fn_ty })

local extern_binding = B.Binding(C.Id("puts"), "puts", fn_ty, B.BindingClassExtern("puts"))
local extern_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(extern_binding))
local r2 = CallD.decide(extern_expr, fn_ty)
assert_call_equal(r2, { kind = "extern", symbol = "puts", fn_ty = fn_ty })

local import_binding = B.Binding(C.Id("imp"), "imp", fn_ty, B.BindingClassImport(O.ImportGlobalFunc("imp", "Other", "g", fn_ty)))
local import_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(import_binding))
local r3 = CallD.decide(import_expr, fn_ty)
assert_call_equal(r3, { kind = "direct", module_name = "Other", item_name = "g", fn_ty = fn_ty })

local local_binding = B.Binding(C.Id("fp"), "fp", fn_ty, B.BindingClassLocalValue)
local local_expr = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefBinding(local_binding))
local r4 = CallD.decide(local_expr, fn_ty)
assert_call_equal(r4, { kind = "indirect", callee = local_expr, fn_ty = fn_ty })

local closure_expr = Tr.ExprRef(Tr.ExprTyped(closure_ty), B.ValueRefBinding(B.Binding(C.Id("cl"), "cl", closure_ty, B.BindingClassLocalValue)))
local r5 = CallD.decide(closure_expr, closure_ty)
assert_call_equal(r5, { kind = "closure", closure = closure_expr, fn_ty = closure_ty })

local unresolved = Tr.ExprRef(Tr.ExprTyped(fn_ty), B.ValueRefName("late"))
local r6 = CallD.decide(unresolved, fn_ty)
assert_call_equal(r6, { kind = "unresolved", callee = unresolved })

print("lalin sem_switch_call ok")
