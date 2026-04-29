-- Lua-hosted builder syntax for MoonPhase compiler wiring values.

local pvm = require("moonlift.pvm")
local Model = require("moonlift.phase_model")

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

function M.Define(T)
    Model.Define(T)
    local P = T.MoonPhase
    local W = {}

    local function type_ref(spec)
        if type(spec) == "table" then
            local cls = pvm.classof(spec)
            if cls == P.TypeRef or spec == P.TypeRefAny or cls == P.TypeRefValue then return spec end
        end
        if spec == nil or spec == "any" or spec == "*" then return P.TypeRefAny end
        if type(spec) ~= "string" then error("phase_builder: type ref must be a string or MoonPhase.TypeRef", 3) end
        local module_name, type_name = spec:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
        if module_name ~= nil then return P.TypeRef(module_name, type_name) end
        return P.TypeRefValue(spec)
    end

    local function cache_policy(spec)
        if spec == P.CacheNode or spec == P.CacheNodeArgsFull or spec == P.CacheNodeArgsLast or spec == P.CacheNone then return spec end
        if spec == "node" then return P.CacheNode end
        if spec == "args" or spec == "full" or spec == "node_args_full" then return P.CacheNodeArgsFull end
        if spec == "last" or spec == "node_args_last" then return P.CacheNodeArgsLast end
        if spec == "none" then return P.CacheNone end
        error("phase_builder: unknown cache policy " .. tostring(spec), 3)
    end

    local function result_shape(spec)
        if type(spec) == "table" then
            local cls = pvm.classof(spec)
            if spec == P.ResultOne or spec == P.ResultOptional or spec == P.ResultMany or cls == P.ResultReport then return spec end
        end
        if spec == "one" then return P.ResultOne end
        if spec == "optional" or spec == "maybe" then return P.ResultOptional end
        if spec == "many" or spec == "stream" then return P.ResultMany end
        error("phase_builder: unknown result shape " .. tostring(spec), 3)
    end

    function W.type(spec) return type_ref(spec) end
    function W.cache(spec) return P.PhaseCache(cache_policy(spec)) end
    function W.result(spec) return P.PhaseResult(result_shape(spec)) end
    function W.result_report(report_ty) return P.PhaseResult(P.ResultReport(type_ref(report_ty))) end
    function W.input(spec) return P.PhaseInput(type_ref(spec)) end
    function W.output(spec) return P.PhaseOutput(type_ref(spec)) end

    function W.file(module_name) return P.UnitFile(module_name) end

    function W.uses(names)
        if not is_array(names) then error("phase_builder.uses expects an array table", 2) end
        local uses = {}
        for i = 1, #names do uses[#uses + 1] = P.UnitUse(names[i]) end
        return P.UnitUses(uses)
    end

    function W.exports(names)
        if not is_array(names) then error("phase_builder.exports expects an array table", 2) end
        local exports = {}
        for i = 1, #names do exports[#exports + 1] = P.UnitExport(names[i]) end
        return P.UnitExports(exports)
    end

    function W.phase(name)
        return function(entries)
            if not is_array(entries) then error("phase_builder.phase expects an array table", 2) end
            local input, output, cache, result = nil, nil, P.CacheNode, P.ResultOne
            for i = 1, #entries do
                local item = entries[i]
                local cls = pvm.classof(item)
                if cls == P.PhaseInput then input = item.input
                elseif cls == P.PhaseOutput then output = item.output
                elseif cls == P.PhaseCache then cache = item.cache
                elseif cls == P.PhaseResult then result = item.result
                else error("phase_builder: unexpected phase entry " .. tostring(item), 2) end
            end
            return P.UnitPhase(P.PhaseSpec(name, input or P.TypeRefAny, output or P.TypeRefAny, cache, result))
        end
    end

    function W.unit(name)
        return function(entries)
            if not is_array(entries) then error("phase_builder.unit expects an array table", 2) end
            local file = name
            local uses, phases, exports = {}, {}, {}
            for i = 1, #entries do
                local item = entries[i]
                local cls = pvm.classof(item)
                if cls == P.UnitFile then file = item.module_name
                elseif cls == P.UnitUses then for j = 1, #item.uses do uses[#uses + 1] = item.uses[j] end
                elseif cls == P.UnitExports then for j = 1, #item.exports do exports[#exports + 1] = item.exports[j] end
                elseif cls == P.UnitPhase then phases[#phases + 1] = item.phase
                else error("phase_builder: unexpected unit entry " .. tostring(item), 2) end
            end
            return P.PhaseUnit(name, file, uses, phases, exports)
        end
    end

    function W.package(name)
        return function(entries)
            if not is_array(entries) then error("phase_builder.package expects an array table", 2) end
            local units = {}
            for i = 1, #entries do
                local item = entries[i]
                if pvm.classof(item) ~= P.PhaseUnit then error("phase_builder: expected PhaseUnit", 2) end
                units[#units + 1] = item
            end
            return P.Package(name, units)
        end
    end

    W._T = T
    W._P = P
    return W
end

return M
