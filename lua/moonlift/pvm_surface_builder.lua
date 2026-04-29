-- Lua-hosted builder syntax for lowerable PVM-on-Moonlift phase bodies.
--
-- Builder calls are syntax only.  The result is canonical MoonPvmSurface ASDL
-- data consumed by the surface emitter.

local pvm = require("moonlift.pvm")
local Model = require("moonlift.pvm_surface_model")
local PhaseModel = require("moonlift.phase_model")

local M = {}

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then return false end
        if k > n then n = k end
    end
    return n == #t
end

local function sorted_keys(t)
    local keys = {}
    for k, _ in pairs(t) do
        if type(k) ~= "number" and tostring(k):sub(1, 1) ~= "_" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function is_a(cls, value)
    return type(cls) == "table" and cls.isclassof and cls:isclassof(value) or false
end

function M.Define(T)
    PhaseModel.Define(T)
    Model.Define(T)
    local Ph = T.MoonPhase
    local S = T.MoonPvmSurface
    local B = {}

    local function type_ref(spec)
        if type(spec) == "table" then
            local cls = pvm.classof(spec)
            if cls == Ph.TypeRef or spec == Ph.TypeRefAny or cls == Ph.TypeRefValue then return spec end
        end
        if spec == nil or spec == "any" or spec == "*" then return Ph.TypeRefAny end
        if type(spec) ~= "string" then error("pvm_surface_builder: type ref must be a string or MoonPhase.TypeRef", 3) end
        local module_name, type_name = spec:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
        if module_name ~= nil then return Ph.TypeRef(module_name, type_name) end
        return Ph.TypeRefValue(spec)
    end

    local function cache_policy(spec)
        if spec == Ph.CacheNode or spec == Ph.CacheNodeArgsFull or spec == Ph.CacheNodeArgsLast or spec == Ph.CacheNone then return spec end
        if spec == nil or spec == "node" then return Ph.CacheNode end
        if spec == "args" or spec == "full" or spec == "node_args_full" then return Ph.CacheNodeArgsFull end
        if spec == "last" or spec == "node_args_last" then return Ph.CacheNodeArgsLast end
        if spec == "none" then return Ph.CacheNone end
        error("pvm_surface_builder: unknown cache policy " .. tostring(spec), 3)
    end

    local function result_shape(spec)
        if type(spec) == "table" then
            local cls = pvm.classof(spec)
            if spec == Ph.ResultOne or spec == Ph.ResultOptional or spec == Ph.ResultMany or cls == Ph.ResultReport then return spec end
        end
        if spec == nil or spec == "one" then return Ph.ResultOne end
        if spec == "optional" or spec == "maybe" then return Ph.ResultOptional end
        if spec == "many" or spec == "stream" then return Ph.ResultMany end
        error("pvm_surface_builder: unknown result shape " .. tostring(spec), 3)
    end

    local function expr(v)
        if is_a(S.Expr, v) then return v end
        if type(v) == "number" then return S.ExprLiteralInt(tostring(v)) end
        if type(v) == "boolean" then return S.ExprLiteralBool(v) end
        if type(v) == "string" then return S.ExprName(v) end
        error("pvm_surface_builder: expected expression", 3)
    end

    local function producer(v)
        if is_a(S.Producer, v) then return v end
        error("pvm_surface_builder: expected producer", 3)
    end

    function B.input(spec) return { _moon_pvm_surface_part = "input", value = type_ref(spec) } end
    function B.output(spec) return { _moon_pvm_surface_part = "output", value = type_ref(spec) } end
    function B.cache(spec) return { _moon_pvm_surface_part = "cache", value = cache_policy(spec) } end
    function B.result(spec) return { _moon_pvm_surface_part = "result", value = result_shape(spec) } end

    B.subject = S.ExprSubject
    function B.local_(name) return S.ExprLocal(name) end
    function B.name(name) return S.ExprName(name) end
    function B.int(value) return S.ExprLiteralInt(tostring(value)) end
    function B.bool(value) return S.ExprLiteralBool(value and true or false) end

    function B.field(base, field_name)
        if field_name == nil then return S.ExprField(S.ExprSubject, base) end
        return S.ExprField(expr(base), field_name)
    end

    function B.arg(name, value) return S.NamedExpr(name, expr(value)) end

    function B.ctor(type_name, ctor_name)
        if ctor_name == nil then
            ctor_name = type_name
            type_name = ""
        end
        return function(fields)
            fields = fields or {}
            local out = {}
            if is_array(fields) then
                for i = 1, #fields do
                    local item = fields[i]
                    if pvm.classof(item) ~= S.NamedExpr then error("pvm_surface_builder.ctor array entries must be named args", 2) end
                    out[#out + 1] = item
                end
            else
                local keys = sorted_keys(fields)
                for i = 1, #keys do
                    local k = keys[i]
                    out[#out + 1] = S.NamedExpr(k, expr(fields[k]))
                end
            end
            return S.ExprCtor(type_name, ctor_name, out)
        end
    end

    function B.call(func_name)
        return function(args)
            args = args or {}
            if not is_array(args) then error("pvm_surface_builder.call expects an array table", 2) end
            local out = {}
            for i = 1, #args do out[i] = expr(args[i]) end
            return S.ExprCall(func_name, out)
        end
    end

    B.empty = S.ProducerEmpty
    function B.once(value) return S.ProducerOnce(expr(value)) end
    function B.concat(parts)
        if not is_array(parts) then error("pvm_surface_builder.concat expects an array table", 2) end
        local out = {}
        for i = 1, #parts do out[i] = producer(parts[i]) end
        return S.ProducerConcat(out)
    end
    function B.call_phase(phase_name, subject, args)
        args = args or {}
        if not is_array(args) then error("pvm_surface_builder.call_phase args must be an array table", 2) end
        local out = {}
        for i = 1, #args do out[i] = expr(args[i]) end
        return S.ProducerCallPhase(phase_name, expr(subject), out)
    end
    function B.children(phase_name, range) return S.ProducerChildren(phase_name, expr(range)) end
    function B.let_(name, value, body) return S.ProducerLet(name, expr(value), producer(body)) end
    function B.if_(cond, then_body, else_body) return S.ProducerIf(expr(cond), producer(then_body), producer(else_body)) end

    function B.bind(name, field_name) return S.Bind(name, field_name or name) end

    function B.on(ctor_name)
        return function(entries)
            if not is_array(entries) then error("pvm_surface_builder.on expects an array table", 2) end
            local binds, body = {}, nil
            for i = 1, #entries do
                local item = entries[i]
                local cls = pvm.classof(item)
                if cls == S.Bind then binds[#binds + 1] = item
                elseif is_a(S.Producer, item) then
                    if body ~= nil then error("pvm_surface_builder.on accepts one producer body", 2) end
                    body = item
                else
                    error("pvm_surface_builder.on unexpected entry", 2)
                end
            end
            return { _moon_pvm_surface_part = "handler", value = S.Handler(ctor_name, binds, body or S.ProducerEmpty) }
        end
    end

    function B.default(entries)
        if not is_array(entries) then error("pvm_surface_builder.default expects an array table", 2) end
        local body = nil
        for i = 1, #entries do
            local item = entries[i]
            if not is_a(S.Producer, item) then error("pvm_surface_builder.default expects producer entries", 2) end
            if body ~= nil then error("pvm_surface_builder.default accepts one producer body", 2) end
            body = item
        end
        return { _moon_pvm_surface_part = "default", value = body or S.ProducerEmpty }
    end

    function B.phase(name)
        return function(entries)
            if not is_array(entries) then error("pvm_surface_builder.phase expects an array table", 2) end
            local input, output = Ph.TypeRefAny, Ph.TypeRefAny
            local cache, result = Ph.CacheNode, Ph.ResultOne
            local handlers, default_body = {}, nil
            for i = 1, #entries do
                local item = entries[i]
                local part = type(item) == "table" and item._moon_pvm_surface_part
                if part == "input" then input = item.value
                elseif part == "output" then output = item.value
                elseif part == "cache" then cache = item.value
                elseif part == "result" then result = item.value
                elseif part == "handler" then handlers[#handlers + 1] = item.value
                elseif part == "default" then default_body = item.value
                else error("pvm_surface_builder.phase unexpected entry", 2) end
            end
            return S.PhaseBody(name, input, output, cache, result, handlers, default_body)
        end
    end

    B._T = T
    B._P = S
    return B
end

return M
