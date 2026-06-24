package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llb = require("llb")
local gps = llb.gps

local env = llb.core_family():env().env
assert(rawget(env, "gps") == nil, "LLB family env should expose GPS through llb.gps, not as a bare family binding")
assert(llb.gps == gps, "LLB gps API is available through llb.gps")

local mapped = gps.from.array({ 1, 2, 3 })
    :map(function(v) return v * 2 end)
    :filter(function(v) return v > 2 end)
    :to_array()
assert(#mapped == 2 and mapped[1] == 4 and mapped[2] == 6, "gps map/filter should preserve values")

local calls = 0
local filtered = gps.from.array({ 1, 2, 3, 4 })
    :filter_map(function(v)
        calls = calls + 1
        if v % 2 == 0 then return v, v * 10 end
        return nil
    end)
    :to_array()
assert(calls == 4, "filter_map callback must run once per source item")
assert(#filtered == 2 and filtered[1] == 2 and filtered[2] == 4, "collect_array keeps first filter_map payload value")

local drained = {}
local drain_result = gps.drain(function(v) drained[#drained + 1] = v end, gps.from.array({ "a", "b" }))
assert(drain_result == nil, "gps.drain returns nil after full consumption")
assert(#drained == 2 and drained[1] == "a" and drained[2] == "b", "gps.drain should consume every item")

local plan_array = gps.run(gps.plan {
    source = gps.spec.array({ 3, 4, 5 }),
    ops = {
        gps.op.drop(1),
        gps.op.map(function(v) return v + 1 end),
        gps.op.take(2),
    },
    materializer = gps.materializer.array(),
})
assert(#plan_array == 2 and plan_array[1] == 5 and plan_array[2] == 6, "gps plan array materializer should run")

local any = gps.spec.any({ 7, 8 })
local any_array = gps.collect.array(any)
assert(#any_array == 2 and any_array[1] == 7 and any_array[2] == 8, "any_spec should preserve raw gps triple")

local seen = {}
local materialized_result = gps.run(gps.plan {
    source = gps.spec.array({ "x", "y" }),
    materializer = gps.materializer.drain(function(v) seen[#seen + 1] = v end),
})
assert(materialized_result == nil, "drain materializer should return nil")
assert(#seen == 2 and seen[1] == "x" and seen[2] == "y", "drain materializer should consume gps")

io.write("llb gps ok\n")
