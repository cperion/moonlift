package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llb = require("llb")
local region = llb.region

local proto = llb.protocol("RegionTestPull", {
  exits = {
    item = { class = "resumable", payload = { "value" }, next = { "state" } },
    done = { class = "terminal" },
  },
})
local pdesc = llb.describe(proto)
assert(pdesc.tag == "Protocol", "protocol is inspectable")
assert(#pdesc.exits == 2, "protocol records typed exits")

local r = llb.region. scan_test {
  input = { "src" },
  state = { "i" },
  protocol = proto,
  lowerings = { gps = { kind = "plan" } },
  materializers = { array = { kind = "collect-array" } },
}
local rdesc = llb.describe(r)
assert(rdesc.tag == "Region", "region is inspectable")
assert(rdesc.name == "scan_test", "region head captures name")
assert(rdesc.protocol == "RegionTestPull", "region records protocol")
assert(rdesc.lowerings[1].target == "gps", "region records lowerings")
assert(rdesc.materializers[1].name == "array", "region records materializers")

local staged = llb.region. staged_region { "x" } { ok = { "value" }, err = {} } { "body" }
local sdesc = llb.describe(staged)
assert(sdesc.tag == "Region", "staged region head builds a descriptor")
assert(sdesc.protocol == "staged_region.protocol", "staged region creates a protocol from exits")

local plan = llb.gps.plan {
  name = "region-test-plan",
  protocol = proto,
  source = llb.gps.spec.array({ 1, 2, 3 }),
  ops = { llb.gps.op.map(function(v) return v + 1 end) },
}
assert(llb.gps.describe(plan).protocol == "RegionTestPull", "gps plans carry protocol identity")

llb.process. region_probe {} (function(ctx)
  return llb.gps.raw(llb.gps.from.array({
    ctx:event("seen", { value = 1 }),
  }))
end)
local process_desc = llb.describe_process("region_probe")
assert(process_desc.region.protocol == "process", "processes expose process protocol regions")

local g = llb.grammar
local Mini = llb.define "RegionMini" {
  g.role .items { kind = "array", item = "string" },
  g.head .box { g.slot .items [g.items] },
}
assert(Mini.compiled.roles.items.descriptor.protocol_name == "role_items", "array role uses item protocol")

local env = llb.core_family():env()
assert(env.region == llb.region, "LLB family exports bare region head")
local env_region = env.region. env_region { input = { "x" }, protocol = "pull" }
assert(llb.describe(env_region).protocol == "pull", "bare region head works from family env")

local moon = require("moonlift")
local chunk = moon.dsl.loadstring([[
return region. scan { x [i32] } { hit { pos [i32] }, miss } {
  entry. start {} {
    jump. hit { pos = x },
  },
}
]], "region_algebra_moonlift.lua")
local generic_region = chunk()
assert(llb.is(generic_region, "Region"), "bare region head creates a generic LLB region")
local unit = moon.dsl.to_unit("RegionAlgebra", { generic_region })
assert(unit.kind == "unit", "Moonlift projection wraps generic region declaration in a unit")
assert(unit.body[1].kind == "region", "Moonlift consumes generic LLB regions")

io.write("llb region_algebra ok\n")
