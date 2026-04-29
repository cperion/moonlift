package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Target = require("moonlift.back_target_model")

local T = pvm.context()
A2.Define(T)
local B = T.MoonBack
local V = T.MoonVec
local H = T.MoonHost
local target_api = Target.Define(T)

local back = target_api.default_native()
assert(pvm.classof(back) == B.BackTargetModel)
assert(back.target == B.BackTargetCraneliftJit)

local saw_i32x4 = false
for i = 1, #back.facts do
    local fact = back.facts[i]
    if pvm.classof(fact) == B.BackTargetSupportsShape and pvm.classof(fact.shape) == B.BackShapeVec and fact.shape.vec.elem == B.BackI32 and fact.shape.vec.lanes == 4 then
        saw_i32x4 = true
    end
end
assert(saw_i32x4, "default target should advertise i32x4")

local host = target_api.host_target(back)
assert(pvm.classof(host) == H.HostTargetModel)
assert(host.pointer_bits == 64)
assert(host.index_bits == 64)
assert(host.endian == H.HostEndianLittle)

local vec = target_api.vec_target(back)
assert(pvm.classof(vec) == V.VecTargetModel)
local saw_vec_shape, saw_vec_add, saw_scalar_tail = false, false, false
for i = 1, #vec.facts do
    local fact = vec.facts[i]
    if pvm.classof(fact) == V.VecTargetSupportsShape and pvm.classof(fact.shape) == V.VecVectorShape and fact.shape.elem == V.VecElemI32 and fact.shape.lanes == 4 then saw_vec_shape = true end
    if pvm.classof(fact) == V.VecTargetSupportsBinOp and pvm.classof(fact.shape) == V.VecVectorShape and fact.shape.elem == V.VecElemI32 and fact.shape.lanes == 4 and fact.op == V.VecAdd then saw_vec_add = true end
    if fact == V.VecTargetPrefersScalarTail then saw_scalar_tail = true end
end
assert(saw_vec_shape, "vec target should derive supported i32x4 shape")
assert(saw_vec_add, "vec target should derive supported vector add")
assert(saw_scalar_tail, "vec target should preserve current scalar-tail policy")

print("moonlift back_target_model ok")
