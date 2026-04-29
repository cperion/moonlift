package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local SurfaceModel = require("moonlift.pvm_surface_model")
local TypeRefSurface = require("moonlift.type_ref_classify_surface")
local RegionLower = require("moonlift.pvm_surface_region_values")

local T = moon.T
SurfaceModel.Define(T)
local Tr, O = T.MoonTree, T.MoonOpen

local body = TypeRefSurface.Define(T)

local out_ty = moon.path_named("MoonType_TypeClassId")
local emit_frag = moon.region_frag("emit_MoonType_TypeClassId", {
    moon.param("value", out_ty),
}, {
    resume = moon.cont({}),
}, function(r)
    r:entry("start", {}, function(start)
        start:jump(r.resume, {})
    end)
end)

local phase_frag = RegionLower.lower_phase_body(moon, body, { emit_frag = emit_frag })
assert(type(phase_frag) == "table" and getmetatable(phase_frag) == moon.RegionFragValue)
assert(phase_frag.name == "type_ref_classify_uncached")
assert(#phase_frag.frag.params == 2)
assert(#phase_frag.frag.open.slots == 1)
assert(pvm.classof(phase_frag.frag.entry.body[1]) == Tr.StmtSwitch)
local switch = phase_frag.frag.entry.body[1]
assert(#switch.arms == 4)
assert(#switch.arms[1].body == 1)
assert(pvm.classof(switch.arms[1].body[1]) == Tr.StmtUseRegionFrag)
assert(pvm.classof(switch.arms[1].body[1].fills[1].value) == O.SlotValueContSlot)

io.write("moonlift pvm_surface_region_values ok\n")
