package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Lower = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

ffi.cdef[[ typedef struct MoonliftReturnViewI32 { int32_t* data; intptr_t len; intptr_t stride; } MoonliftReturnViewI32; ]]

local T = pvm.context()
A2.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local B = T.Moon2Bind
local Tr = T.Moon2Tree
local B2 = T.Moon2Back
local B2 = T.Moon2Back

local Lowerer = Lower.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)

local i32 = Ty.TScalar(C.ScalarI32)
local index = Ty.TScalar(C.ScalarIndex)
local ptr_i32 = Ty.TPtr(i32)
local view_i32 = Ty.TView(i32)
local data_binding = B.Binding(C.Id("arg:make_view:data"), "data", ptr_i32, B.BindingClassArg(0))
local len_binding = B.Binding(C.Id("arg:make_view:n"), "n", index, B.BindingClassArg(1))
local data_expr = Tr.ExprRef(Tr.ExprTyped(ptr_i32), B.ValueRefBinding(data_binding))
local len_expr = Tr.ExprRef(Tr.ExprTyped(index), B.ValueRefBinding(len_binding))
local view_expr = Tr.ExprView(Tr.ExprTyped(view_i32), Tr.ViewContiguous(data_expr, i32, len_expr))
local func = Tr.FuncExport("make_view", {
    Ty.Param("data", ptr_i32),
    Ty.Param("n", index),
}, view_i32, {
    Tr.StmtReturnValue(Tr.StmtTyped, view_expr),
})
local module = Tr.Module(Tr.ModuleTyped("ViewReturn"), { Tr.ItemFunc(func) })
local program = Lowerer.module(module)
local report = V.validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))
assert(program.cmds[1].params[1] == B2.BackPtr, "view return ABI must take out descriptor pointer first")
assert(program.cmds[1].params[2] == B2.BackPtr)
assert(program.cmds[1].params[3] == B2.BackIndex)
assert(#program.cmds[1].results == 0)
local saw_stride_store = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == B2.CmdStoreInfo and pvm.classof(cmd.ty) == B2.BackShapeScalar and cmd.ty.scalar == B2.BackIndex then saw_stride_store = true end
end
assert(saw_stride_store, "expected descriptor len/stride stores")

local artifact = jit_api.jit():compile(program)
local make_view = ffi.cast("void (*)(MoonliftReturnViewI32*, int32_t*, intptr_t)", artifact:getpointer(B2.BackFuncId("make_view")))
local xs = ffi.new("int32_t[4]", { 3, 4, 5, 6 })
local out = ffi.new("MoonliftReturnViewI32[1]")
make_view(out, xs, 4)
assert(out[0].data == xs)
assert(out[0].len == 4)
assert(out[0].stride == 1)
artifact:free()

print("moonlift host_view_return_abi ok")
