package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Target = require("moonlift.back_target_model")

local T = pvm.context()
Schema(T)

local B = T.MoonBack
local H = T.MoonHost
local api = Target(T)

local model = api.default_native()
assert(pvm.classof(model) == B.BackTargetModel)
assert(model.target == B.BackTargetNative)
assert(#model.facts > 0)

local host = api.host_target(model)
assert(pvm.classof(host) == H.HostTargetModel)
assert(host.pointer_bits == 64)
assert(host.index_bits == 64)

io.write("moonlift schema_back_target_model ok\n")
