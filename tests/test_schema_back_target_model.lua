package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Target = require("moonlift.back_target_model")

local T = pvm.context()
Schema.Define(T)

local B = T.MoonBack
local V = T.MoonVec
local H = T.MoonHost
local api = Target.Define(T)

local model = api.default_native()
assert(pvm.classof(model) == B.BackTargetModel)
assert(model.target == B.BackTargetCraneliftJit)
assert(#model.facts > 0)

local host = api.host_target(model)
assert(pvm.classof(host) == H.HostTargetModel)
assert(host.pointer_bits == 64)
assert(host.index_bits == 64)

local vec = api.vec_target(model)
assert(pvm.classof(vec) == V.VecTargetModel)
assert(vec.target == V.VecTargetCraneliftJit)
assert(#vec.facts > 0)

io.write("moonlift schema_back_target_model ok\n")
