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

local function name_ref(name)
    return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
end

local closure = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name_ref("x"), Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))))
})

local y_binding = B.Binding(C.Id("local:y"), "y", i32, B.BindingClassLocalValue)
local capture_closure = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name_ref("x"), name_ref("y")))
})

local main = Tr.FuncExport("closure_direct", {}, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(closure), { Tr.ExprLit(Tr.ExprSurface, C.LitInt("41")) }))
})

local capture_main = Tr.FuncExport("closure_capture", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, y_binding, Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))),
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(capture_closure), { Tr.ExprLit(Tr.ExprSurface, C.LitInt("41")) }))
})

local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(main), Tr.ItemFunc(capture_main) })
local converted = ClosureConvert.Define(T).module(module)
assert(#converted.items == 4, "closure conversion should hoist two helpers")

local checked = Typecheck.Define(T).check_module(converted)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local resolved = Layout.Define(T).module(checked.module)
local program = TreeToBack.Define(T).module(resolved)
local report = Validate.Define(T).validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

local artifact = Jit.Define(T).jit():compile(program)
local direct_fn = ffi.cast("int32_t (*)()", artifact:getpointer(Back.BackFuncId("closure_direct")))
assert(direct_fn() == 42)
local capture_fn = ffi.cast("int32_t (*)()", artifact:getpointer(Back.BackFuncId("closure_capture")))
assert(capture_fn() == 42)
artifact:free()

print("moonlift closure conversion ok")
