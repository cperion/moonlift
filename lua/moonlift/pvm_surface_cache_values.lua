-- Hosted Moonlift cache wrapper values for lowerable PVM phases.
--
-- One-result cached phases become ordinary module-owned structs/functions built
-- through the host API.  No source strings are generated.

local pvm = require("moonlift.pvm")
local Model = require("moonlift.pvm_surface_model")

local M = {}

local function sanitize(name)
    return tostring(name):gsub("[^%w_]", "_")
end

local function type_ref_name(Ph, ref)
    local cls = pvm.classof(ref)
    if ref == Ph.TypeRefAny then return "Value" end
    if cls == Ph.TypeRefValue then return ref.name end
    if cls == Ph.TypeRef then return ref.module_name .. "_" .. ref.type_name end
    return "Value"
end

local function id_type_name(Ph, ref)
    return type_ref_name(Ph, ref) .. "Id"
end

local function call_expr(api, func_name, args, result_ty, hint)
    local T = api.T
    local B, Sem, Tr = T.MoonBind, T.MoonSem, T.MoonTree
    local exprs = {}
    for i = 1, #args do exprs[i] = api.as_moon2_expr(args[i], "call arg expects expression") end
    local callee = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(func_name))
    local expr = Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(callee), exprs)
    return api.expr_from_asdl(expr, result_ty, hint or (func_name .. "(...)"))
end

local function context_type_value(api, spec)
    if spec == nil then return api.path_named("NativePvmContext") end
    if type(spec) == "table" and type(spec.as_type_value) == "function" then return spec end
    return api.path_named(spec)
end

function M.add_one_result_cache(api, module, body, opts)
    opts = opts or {}
    Model.Define(api.T)
    local Ph, S = api.T.MoonPhase, api.T.MoonPvmSurface
    assert(pvm.classof(body) == S.PhaseBody, "add_one_result_cache expects MoonPvmSurface.PhaseBody")
    assert(body.result == Ph.ResultOne, "add_one_result_cache expects ResultOne")

    local phase = sanitize(body.name)
    local ctx_ty = context_type_value(api, opts.context_type)
    local key_ty = opts.input_id_type or api.path_named(id_type_name(Ph, body.input))
    local value_ty = opts.output_id_type or api.path_named(id_type_name(Ph, body.output))
    local cache_state_ty = api.path_named(opts.cache_state_type or "CacheState")

    local hit_ty = module:struct(phase .. "CacheHit", {
        api.field("valid", api.bool),
        api.field("value", value_ty),
    })
    module:struct(phase .. "CacheEntry", {
        api.field("key", key_ty),
        api.field("value", value_ty),
        api.field("state", cache_state_ty),
    })
    module:struct(phase .. "Cache", {
        api.field("entries", api.ptr(api.path_named(phase .. "CacheEntry"))),
        api.field("len", api.index),
        api.field("capacity", api.index),
    })

    return module:export_func(phase, {
        api.param("ctx", ctx_ty),
        api.param("subject", key_ty),
    }, value_ty, function(fn)
        local ctx = fn:param("ctx")
        local subject = fn:param("subject")
        fn:expr(call_expr(api, "stats_" .. phase .. "_call", { ctx }, api.void))
        local hit = fn:let("hit", hit_ty, call_expr(api, "cache_" .. phase .. "_lookup", { ctx, subject }, hit_ty))
        fn:if_(hit:field("valid", api.bool), function(t)
            t:expr(call_expr(api, "stats_" .. phase .. "_hit", { ctx }, api.void))
            t:return_(hit:field("value", value_ty))
        end)
        fn:expr(call_expr(api, "stats_" .. phase .. "_miss", { ctx }, api.void))
        local value = fn:let("value", value_ty, call_expr(api, phase .. "_drain_one_uncached", { ctx, subject }, value_ty))
        fn:expr(call_expr(api, "cache_" .. phase .. "_insert", { ctx, subject, value }, api.void))
        fn:return_(value)
    end)
end

function M.Define(T)
    Model.Define(T)
    return { add_one_result_cache = M.add_one_result_cache }
end

return M
