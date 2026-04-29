package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local SurfaceModel = require("moonlift.pvm_surface_model")
local SurfaceEmit = require("moonlift.pvm_surface_emit")
local TypeRefSurface = require("moonlift.type_ref_classify_surface")

local T = pvm.context()
SurfaceModel.Define(T)
local S = T.MoonPvmSurface
local Ph = T.MoonPhase

local body = TypeRefSurface.Define(T)
assert(pvm.classof(body) == S.PhaseBody)
assert(body.name == "type_ref_classify")
assert(pvm.classof(body.input) == Ph.TypeRef)
assert(body.input.module_name == "MoonType")
assert(body.input.type_name == "TypeRef")
assert(body.output.type_name == "TypeClass")
assert(body.cache == Ph.CacheNode)
assert(body.result == Ph.ResultOne)
assert(#body.handlers == 4)
assert(body.handlers[1].ctor_name == "TypeRefGlobal")
assert(#body.handlers[1].binds == 2)
assert(body.handlers[1].binds[1].name == "module_name")
assert(body.handlers[1].binds[2].name == "type_name")

local E = SurfaceEmit.Define(T)
local src = E.emit_phase_body(body)
assert(src:find("region type_ref_classify_uncached", 1, true))
assert(src:find("case TypeRefGlobal(module_name, type_name)", 1, true))
assert(src:find("make_MoonType_TypeClass_TypeClassAggregate(ctx, module_name, type_name)", 1, true))
assert(src:find("case TypeRefPath()", 1, true))
assert(src:find("make_MoonType_TypeClass_TypeClassUnknown(ctx)", 1, true))
assert(src:find("emit emit_MoonType_TypeClassId", 1, true))

local module_src = E.emit_phase_module(body)
assert(module_src:find("type type_ref_classifyCacheEntry = struct", 1, true))
assert(module_src:find("key: MoonType_TypeRefId", 1, true))
assert(module_src:find("value: MoonType_TypeClassId", 1, true))
assert(module_src:find("func type_ref_classify_drain_one_uncached", 1, true))
assert(module_src:find("export func type_ref_classify", 1, true))
assert(module_src:find("stats_type_ref_classify_call(ctx)", 1, true))
assert(module_src:find("cache_type_ref_classify_lookup(ctx, subject)", 1, true))
assert(module_src:find("stats_type_ref_classify_hit(ctx)", 1, true))
assert(module_src:find("stats_type_ref_classify_miss(ctx)", 1, true))
assert(module_src:find("cache_type_ref_classify_insert(ctx, subject, value)", 1, true))

io.write("moonlift type_ref_classify_surface ok\n")
