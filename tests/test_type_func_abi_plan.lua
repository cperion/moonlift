package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Abi = require("moonlift.type_func_abi_plan")

local T = pvm.context()
A.Define(T)
local L = Abi.Define(T)
local C = T.MoonCore
local Ty = T.MoonType
local B = T.MoonBind
local Back = T.MoonBack

local i32 = Ty.TScalar(C.ScalarI32)
local view_i32 = Ty.TView(i32)
local void = Ty.TScalar(C.ScalarVoid)

local params = { Ty.Param("dst", view_i32), Ty.Param("n", Ty.TScalar(C.ScalarIndex)), Ty.Param("x", i32) }
local plan = L.plan("f", params, i32)
assert(pvm.classof(plan) == Ty.FuncAbiPlan)
assert(#plan.params == 3)

local dst = plan.params[1]
assert(pvm.classof(dst) == Ty.AbiParamView)
assert(dst.name == "dst")
assert(dst.data == Back.BackValId("arg:f:dst:data"))
assert(dst.len == Back.BackValId("arg:f:dst:len"))
assert(dst.stride == Back.BackValId("arg:f:dst:stride"))
assert(pvm.classof(dst.binding.class) == B.BindingClassArg)
assert(dst.binding.class.index == 0)

local n = plan.params[2]
assert(pvm.classof(n) == Ty.AbiParamScalar)
assert(n.scalar == Back.BackIndex)
assert(n.value == Back.BackValId("arg:f:n"))
assert(n.binding.class.index == 1)

local x = plan.params[3]
assert(pvm.classof(x) == Ty.AbiParamScalar)
assert(x.scalar == Back.BackI32)
assert(x.binding.class.index == 2)
assert(pvm.classof(plan.result) == Ty.AbiResultScalar)
assert(plan.result.scalar == Back.BackI32)

local void_plan = L.plan("g", {}, void)
assert(void_plan.result == Ty.AbiResultVoid)

local view_result_plan = L.plan("make", {}, view_i32)
assert(pvm.classof(view_result_plan.result) == Ty.AbiResultView)
assert(view_result_plan.result.elem == i32)
assert(view_result_plan.result.out == Back.BackValId("arg:make:return:out"))

print("moonlift type_func_abi_plan ok")
