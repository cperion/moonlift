-- Lower MoonPvmSurface phase bodies to hosted Moonlift region values.
--
-- This is the metaprogrammed PVM-on-Moonlift path: no source strings are
-- generated here.  The output is a Moonlift RegionFragValue / MoonTree ASDL
-- graph built through the existing hosted region/jump/emit API.

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

local Lower = {}
Lower.__index = Lower

function Lower:type_value_for_ref(ref)
    if ref == self.body.input and self.input_id_ty ~= nil then return self.input_id_ty end
    if ref == self.body.output and self.output_id_ty ~= nil then return self.output_id_ty end
    return self.api.path_named(id_type_name(self.Ph, ref))
end

function Lower:expr(env, e, result_ty)
    local S = self.S
    local cls = pvm.classof(e)
    if e == S.ExprSubject then return env.subject end
    if cls == S.ExprLocal then
        local v = env[e.name]
        assert(v ~= nil, "unknown PVM surface local: " .. tostring(e.name))
        return v
    end
    if cls == S.ExprName then
        local v = env[e.name]
        if v ~= nil then return v end
        return call_expr(self.api, e.name, {}, result_ty or self.api.path_named("Value"), e.name)
    end
    if cls == S.ExprLiteralInt then return self.api.int(tonumber(e.text) or e.text) end
    if cls == S.ExprLiteralBool then return self.api.bool_lit(e.value) end
    if cls == S.ExprField then
        local base = self:expr(env, e.base)
        return base:field(e.field_name, result_ty or self.api.path_named("Value"))
    end
    if cls == S.ExprCall then
        local args = {}
        for i = 1, #e.args do args[i] = self:expr(env, e.args[i]) end
        return call_expr(self.api, e.func_name, args, result_ty or self.api.path_named("Value"))
    end
    if cls == S.ExprCtor then
        local args = { env.ctx }
        for i = 1, #e.fields do args[#args + 1] = self:expr(env, e.fields[i].value) end
        local prefix = e.type_name ~= "" and (sanitize(e.type_name) .. "_") or ""
        local ty = self.api.path_named((e.type_name ~= "" and sanitize(e.type_name) or type_ref_name(self.Ph, self.body.output)) .. "Id")
        return call_expr(self.api, "make_" .. prefix .. sanitize(e.ctor_name), args, ty)
    end
    error("unsupported MoonPvmSurface.Expr " .. tostring(cls and cls.kind or e), 2)
end

function Lower:producer(region, block, env, producer, done_target)
    local S = self.S
    local cls = pvm.classof(producer)
    if producer == S.ProducerEmpty then
        block:jump(done_target, {})
    elseif cls == S.ProducerOnce then
        local value = self:expr(env, producer.value, self:type_value_for_ref(self.body.output))
        block:emit(self.emit_frag, { value }, { resume = done_target })
    elseif cls == S.ProducerCallPhase then
        local frag = assert(self.phase_frags[producer.phase_name], "no region fragment registered for phase " .. tostring(producer.phase_name))
        local args = { env.ctx, self:expr(env, producer.subject) }
        for i = 1, #producer.args do args[#args + 1] = self:expr(env, producer.args[i]) end
        block:emit(frag, args, { done = done_target })
    elseif cls == S.ProducerConcat then
        self:concat(region, block, env, producer.parts, 1, done_target)
    elseif cls == S.ProducerChildren then
        error("ProducerChildren needs range iteration lowering; add it as hosted block/jump values, not text", 2)
    elseif cls == S.ProducerLet then
        local value = self:expr(env, producer.value)
        local local_env = {}
        for k, v in pairs(env) do local_env[k] = v end
        local_env[producer.name] = value
        self:producer(region, block, local_env, producer.body, done_target)
    elseif cls == S.ProducerIf then
        local cond = self:expr(env, producer.cond, self.api.bool)
        block:if_(cond, function(t)
            self:producer(region, t, env, producer.then_body, done_target)
        end, function(e)
            self:producer(region, e, env, producer.else_body, done_target)
        end)
    else
        error("unsupported MoonPvmSurface.Producer " .. tostring(cls and cls.kind or producer), 2)
    end
end

function Lower:concat(region, block, env, parts, index, done_target)
    if index > #parts then
        block:jump(done_target, {})
        return
    end
    if index == #parts then
        self:producer(region, block, env, parts[index], done_target)
        return
    end
    local after = region:block("after_concat_" .. tostring(index), {}, function(after_block)
        self:concat(region, after_block, env, parts, index + 1, done_target)
    end)
    self:producer(region, block, env, parts[index], after)
end

function Lower:tag_expr(env)
    return call_expr(self.api, "tag_" .. type_ref_name(self.Ph, self.body.input), { env.ctx, env.subject }, self.api.index)
end

function Lower:bind_handler_fields(env, handler)
    local out = {}
    for k, v in pairs(env) do out[k] = v end
    local input_name = type_ref_name(self.Ph, self.body.input)
    for i = 1, #handler.binds do
        local b = handler.binds[i]
        out[b.name] = call_expr(self.api, "get_" .. input_name .. "_" .. sanitize(handler.ctor_name) .. "_" .. sanitize(b.field_name), { env.ctx, env.subject }, self.field_ty or self.api.path_named("Value"))
    end
    return out
end

local function context_type_value(api, spec)
    if spec == nil then return api.path_named("NativePvmContext") end
    if type(spec) == "table" and type(spec.as_type_value) == "function" then return spec end
    return api.path_named(spec)
end

function M.lower_phase_body(api, body, opts)
    opts = opts or {}
    Model.Define(api.T)
    local Ph, S = api.T.MoonPhase, api.T.MoonPvmSurface
    assert(pvm.classof(body) == S.PhaseBody, "lower_phase_body expects MoonPvmSurface.PhaseBody")
    local emit_frag = assert(opts.emit_frag, "lower_phase_body expects opts.emit_frag RegionFragValue")
    local self = setmetatable({ api = api, Ph = Ph, S = S, body = body, emit_frag = emit_frag, phase_frags = opts.phase_frags or {}, field_ty = opts.field_type, input_id_ty = opts.input_id_type, output_id_ty = opts.output_id_type }, Lower)
    local ctx_ty = context_type_value(api, opts.context_type)
    local subject_ty = self:type_value_for_ref(body.input)
    return api.region_frag(sanitize(body.name) .. "_uncached", {
        api.param("ctx", ctx_ty),
        api.param("subject", subject_ty),
    }, {
        done = api.cont({}),
    }, function(region)
        region:entry("start", {}, function(start)
            local env = { ctx = region.ctx, subject = region.subject }
            local arms = {}
            for i = 1, #body.handlers do
                local handler = body.handlers[i]
                arms[#arms + 1] = {
                    key = tostring(i - 1),
                    body = function(arm)
                        self:producer(region, arm, self:bind_handler_fields(env, handler), handler.body, region.done)
                    end,
                }
            end
            start:switch_(self:tag_expr(env), arms, function(default)
                if body.default_body ~= nil then
                    self:producer(region, default, env, body.default_body, region.done)
                else
                    default:jump(region.done, {})
                end
            end)
        end)
    end)
end

function M.Define(T)
    Model.Define(T)
    return {
        lower_phase_body = M.lower_phase_body,
    }
end

return M
