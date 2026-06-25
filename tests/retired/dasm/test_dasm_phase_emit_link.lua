package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local A2 = require("lalin.schema_projection")
local E = require("back.dasm.phases.emit_dynasm")
local L = require("back.dasm.phases.link_encode")
local Mx = require("back.dasm.model")

local T = pvm.context()
A2(T)
Mx.set_context(T)
local D = T.LalinDasm

local payload = E.run({
    D.DFragment(0, {}, string.char(0x90)),
    D.DFragment(1, {}, string.char(0xC3)),
})

assert(pvm.classof(payload) == D.DEmitPlan)
assert(#payload.fragments == 2)

local linked = L.run(payload)
assert(pvm.classof(linked) == D.DEmitPlan)
assert(#linked.fragments == #payload.fragments)

print("dasm phase emit/link: ok")
