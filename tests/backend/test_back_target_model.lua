package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.schema_projection")
local Target = require("moonlift.back_target_model")

local T = pvm.context()
A2(T)
local B = T.MoonBack
local H = T.MoonHost
local target_api = Target(T)

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
assert(saw_i32x4, "default target should advertise i32x4 as a Back shape")

local host = target_api.host_target(back)
assert(pvm.classof(host) == H.HostTargetModel)
assert(host.pointer_bits == 64)
assert(host.index_bits == 64)
assert(host.endian == H.HostEndianLittle)

print("moonlift back_target_model ok")
