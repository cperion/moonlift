package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local ClosureConvert = require("moonlift.closure_convert")
local Typecheck = require("moonlift.tree_typecheck")
local Layout = require("moonlift.sem_layout_resolve")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local C, Ty, B, Sem, Tr, Back = T.MoonCore, T.MoonType, T.MoonBind, T.MoonSem, T.MoonTree, T.MoonBack
local i32 = Ty.TScalar(C.ScalarI32)
local closure_i32 = Ty.TClosure({ i32 }, i32)

local function name_ref(name)
    return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
end

local function int_lit(n)
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(n)))
end

local function call(callee, args)
    return Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(callee), args or {})
end

local function plus(a, b)
    return Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, a, b)
end

local x_plus_1 = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, plus(name_ref("x"), int_lit(1)))
})

local f_binding = B.Binding(C.Id("local:f"), "f", closure_i32, B.BindingClassLocalValue)
local store_func = Tr.FuncExport("closure_store", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, f_binding, x_plus_1),
    Tr.StmtReturnValue(Tr.StmtSurface, call(name_ref("f"), { int_lit(41) })),
})

local apply_func = Tr.FuncLocal("apply_closure", { Ty.Param("f", closure_i32), Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, call(name_ref("f"), { name_ref("x") })),
})

local y_binding = B.Binding(C.Id("local:y"), "y", i32, B.BindingClassLocalValue)
local capture_closure = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, plus(name_ref("x"), name_ref("y")))
})
local pass_func = Tr.FuncExport("closure_pass", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, y_binding, int_lit(1)),
    Tr.StmtReturnValue(Tr.StmtSurface, call(name_ref("apply_closure"), { capture_closure, int_lit(41) })),
})

local make_func = Tr.FuncLocal("make_inc", {}, closure_i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, x_plus_1),
})
local f2_binding = B.Binding(C.Id("local:f2"), "f", closure_i32, B.BindingClassLocalValue)
local return_func = Tr.FuncExport("closure_return", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, f2_binding, call(name_ref("make_inc"), {})),
    Tr.StmtReturnValue(Tr.StmtSurface, call(name_ref("f"), { int_lit(41) })),
})

local module = Tr.Module(Tr.ModuleSurface, {
    Tr.ItemFunc(store_func),
    Tr.ItemFunc(apply_func),
    Tr.ItemFunc(pass_func),
    Tr.ItemFunc(make_func),
    Tr.ItemFunc(return_func),
})

local converted = ClosureConvert.Define(T).module(module)
local checked = Typecheck.Define(T).check_module(converted)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local resolved = Layout.Define(T).module(checked.module)
local program = TreeToBack.Define(T).module(resolved)
local report = Validate.Define(T).validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

local artifact = Jit.Define(T).jit():compile(program)
local store = ffi.cast("int32_t (*)()", artifact:getpointer(Back.BackFuncId("closure_store")))
assert(store() == 42)
local pass = ffi.cast("int32_t (*)()", artifact:getpointer(Back.BackFuncId("closure_pass")))
assert(pass() == 42)
local ret = ffi.cast("int32_t (*)()", artifact:getpointer(Back.BackFuncId("closure_return")))
assert(ret() == 42)
artifact:free()

print("moonlift escaping closure descriptors ok")
