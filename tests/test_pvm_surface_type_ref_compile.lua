package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local SurfaceModel = require("moonlift.pvm_surface_model")
local TypeRefSurface = require("moonlift.type_ref_classify_surface")
local UnionRuntime = require("moonlift.pvm_surface_union_values")
local RegionLower = require("moonlift.pvm_surface_region_values")
local CacheValues = require("moonlift.pvm_surface_cache_values")
local OpenFacts = require("moonlift.open_facts")
local OpenValidate = require("moonlift.open_validate")
local OpenExpand = require("moonlift.open_expand")
local Typecheck = require("moonlift.tree_typecheck")
local SemLayout = require("moonlift.sem_layout_resolve")
local TreeToBack = require("moonlift.tree_to_back")
local BackValidate = require("moonlift.back_validate")

local T = moon.T
SurfaceModel.Define(T)
local Tr = T.MoonTree
local OF = OpenFacts.Define(T)
local OV = OpenValidate.Define(T)
local OE = OpenExpand.Define(T)
local TC = Typecheck.Define(T)
local Layout = SemLayout.Define(T)
local Lower = TreeToBack.Define(T)
local BV = BackValidate.Define(T)

local body = TypeRefSurface.Define(T)
local M = moon.module("NativePvmTypeRefCompileTest")
local ctx_ty = moon.rawptr
local type_ref_id = M:struct("MoonType_TypeRefId", { moon.field("index", moon.index) }).type
local type_class_id = M:struct("MoonType_TypeClassId", { moon.field("index", moon.index) }).type
M:struct("CacheState", { moon.field("value", moon.index) })

UnionRuntime.add_phase_union_runtime(moon, M, body, {
    context_type = ctx_ty,
    field_type = moon.index,
    input_id_type = type_ref_id,
    output_id_type = type_class_id,
})

local emit_frag = moon.region_frag("emit_MoonType_TypeClassId", {
    moon.param("value", type_class_id),
}, {
    resume = moon.cont({}),
}, function(r)
    r:entry("start", {}, function(start)
        start:jump(r.resume, {})
    end)
end)

local phase_frag = RegionLower.lower_phase_body(moon, body, {
    context_type = ctx_ty,
    field_type = moon.index,
    input_id_type = type_ref_id,
    output_id_type = type_class_id,
    emit_frag = emit_frag,
})

M:extern_func("default_type_class_id", { moon.param("ctx", ctx_ty) }, type_class_id)
M:func("type_ref_classify_drain_one_uncached", {
    moon.param("ctx", ctx_ty),
    moon.param("subject", type_ref_id),
}, type_class_id, function(fn)
    local ctx = fn:param("ctx")
    local subject = fn:param("subject")
    fn:return_region(type_class_id, function(r)
        local done = r:block("done", {}, function(done)
            done:yield_(moon.call("default_type_class_id", { ctx }, type_class_id))
        end)
        r:entry("start", {}, function(start)
            start:emit(phase_frag, { ctx, subject }, { done = done })
        end)
    end)
end)

M:extern_func("stats_type_ref_classify_call", { moon.param("ctx", ctx_ty) }, moon.void)
M:extern_func("stats_type_ref_classify_hit", { moon.param("ctx", ctx_ty) }, moon.void)
M:extern_func("stats_type_ref_classify_miss", { moon.param("ctx", ctx_ty) }, moon.void)
M:extern_func("cache_type_ref_classify_lookup", {
    moon.param("ctx", ctx_ty),
    moon.param("subject", type_ref_id),
}, moon.named("NativePvmTypeRefCompileTest", "type_ref_classifyCacheHit"))
M:extern_func("cache_type_ref_classify_insert", {
    moon.param("ctx", ctx_ty),
    moon.param("subject", type_ref_id),
    moon.param("value", type_class_id),
}, moon.void)
CacheValues.add_one_result_cache(moon, M, body, {
    context_type = ctx_ty,
    input_id_type = type_ref_id,
    output_id_type = type_class_id,
})

local module = M:to_asdl()
local saw_phase_emit = false
for i = 1, #module.items do
    local item = module.items[i]
    if pvm.classof(item) == Tr.ItemFunc and item.func.name == "type_ref_classify_drain_one_uncached" then
        saw_phase_emit = true
    end
end
assert(saw_phase_emit)

local expanded = OE.module(module)
local open_report = OV.validate(OF.facts_of_module(expanded))
assert(#open_report.issues == 0, tostring(open_report.issues[1]))
local checked = TC.check_module(expanded)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local resolved = Layout.module(checked.module, M:layout_env())
local program = Lower.module(resolved)
local report = BV.validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

io.write("moonlift pvm_surface_type_ref_compile ok\n")
