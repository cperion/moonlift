-- Hosted tagged-union runtime boundary values for PVM surface lowering.
--
-- These are explicit Moonlift declarations for the tag/project/construct
-- operations used by lowered phase regions.  They replace placeholder strings
-- with module-owned extern function values typed from the phase/schema facts.

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

local function is_a(cls, value)
    return type(cls) == "table" and cls.isclassof and cls:isclassof(value) or false
end

local function context_type_value(api, spec)
    if spec == nil then return api.path_named("NativePvmContext") end
    if type(spec) == "table" and type(spec.as_type_value) == "function" then return spec end
    return api.path_named(spec)
end

local function expr_ctor_fields(S, producer, out)
    local cls = pvm.classof(producer)
    if cls == S.ProducerOnce then
        local e = producer.value
        if pvm.classof(e) == S.ExprCtor then out[#out + 1] = e end
    elseif cls == S.ProducerConcat then
        for i = 1, #producer.parts do expr_ctor_fields(S, producer.parts[i], out) end
    elseif cls == S.ProducerLet then
        expr_ctor_fields(S, producer.body, out)
    elseif cls == S.ProducerIf then
        expr_ctor_fields(S, producer.then_body, out)
        expr_ctor_fields(S, producer.else_body, out)
    end
end

function M.add_phase_union_runtime(api, module, body, opts)
    opts = opts or {}
    Model.Define(api.T)
    local Ph, S = api.T.MoonPhase, api.T.MoonPvmSurface
    assert(pvm.classof(body) == S.PhaseBody, "add_phase_union_runtime expects MoonPvmSurface.PhaseBody")

    local ctx_ty = context_type_value(api, opts.context_type)
    local input_id_ty = opts.input_id_type or api.path_named(id_type_name(Ph, body.input))
    local output_id_ty = opts.output_id_type or api.path_named(id_type_name(Ph, body.output))
    local field_ty = opts.field_type or api.index
    local input_name = type_ref_name(Ph, body.input)

    module:extern_func("tag_" .. input_name, {
        api.param("ctx", ctx_ty),
        api.param("subject", input_id_ty),
    }, api.index)

    local seen_accessors = {}
    for i = 1, #body.handlers do
        local h = body.handlers[i]
        for j = 1, #h.binds do
            local b = h.binds[j]
            local fname = "get_" .. input_name .. "_" .. sanitize(h.ctor_name) .. "_" .. sanitize(b.field_name)
            if not seen_accessors[fname] then
                seen_accessors[fname] = true
                module:extern_func(fname, {
                    api.param("ctx", ctx_ty),
                    api.param("subject", input_id_ty),
                }, field_ty)
            end
        end
    end

    local ctors = {}
    for i = 1, #body.handlers do expr_ctor_fields(S, body.handlers[i].body, ctors) end
    if body.default_body ~= nil then expr_ctor_fields(S, body.default_body, ctors) end
    local seen_ctors = {}
    for i = 1, #ctors do
        local c = ctors[i]
        local prefix = c.type_name ~= "" and (sanitize(c.type_name) .. "_") or ""
        local fname = "make_" .. prefix .. sanitize(c.ctor_name)
        if not seen_ctors[fname] then
            seen_ctors[fname] = true
            local params = { api.param("ctx", ctx_ty) }
            for j = 1, #c.fields do params[#params + 1] = api.param(c.fields[j].name, field_ty) end
            module:extern_func(fname, params, output_id_ty)
        end
    end
end

function M.Define(T)
    Model.Define(T)
    return { add_phase_union_runtime = M.add_phase_union_runtime }
end

return M
