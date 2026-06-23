package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.schema_projection")
local dasm_init = require("back.dasm")

local T = pvm.context()
A2(T)
local api = dasm_init(T)
local jit = api.jit()

assert(jit:watch_rules(true) == true)
assert(jit:watch_rules(false) == false)
assert(jit:reload_rules() == true)

print("dasm lisle watch/reload: ok")
