local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    local B = T.LalinBind

    local mark_fact
    local decide_facts

    function mark_fact(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ResidenceFactBinding) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactAddressTaken) then
            return (function(self, state)
 state.address[self.binding] = true; return {}
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactMutableCell) then
            return (function(self, state)
 state.mutable[self.binding] = true; return {}
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactNonScalarAbi) then
            return (function(self, state)
 state.nonscalar[self.binding] = true; return {}
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactMaterializedTemporary) then
            return (function(self, state)
 state.materialized[self.binding] = true; return {}
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactBackendRequired) then
            return (function(self, state)
 state.backend[self.binding] = true; return {}
            end)(node, ...)
        else
            error("phase lalin_bind_residence_mark_fact: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function decide_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ResidenceFactSet) then
            return (function(fact_set)

            local state = {
                bindings = {}, seen = {}, address = {}, mutable = {}, nonscalar = {}, materialized = {}, backend = {},
            }
            for i = 1, #fact_set.facts do
                mark_fact(fact_set.facts[i], state)
                local binding = fact_set.facts[i].binding
                if binding and not state.seen[binding] then
                    state.seen[binding] = true
                    state.bindings[#state.bindings + 1] = binding
                end
            end
            local decisions = {}
            for i = 1, #state.bindings do
                local binding = state.bindings[i]
                if state.mutable[binding] then
                    decisions[#decisions + 1] = B.ResidenceDecision(binding, B.ResidenceCell, B.ResidenceBecauseMutableCell)
                elseif state.address[binding] then
                    decisions[#decisions + 1] = B.ResidenceDecision(binding, B.ResidenceStack, B.ResidenceBecauseAddressTaken)
                elseif state.nonscalar[binding] then
                    decisions[#decisions + 1] = B.ResidenceDecision(binding, B.ResidenceStack, B.ResidenceBecauseNonScalarAbi)
                elseif state.materialized[binding] then
                    decisions[#decisions + 1] = B.ResidenceDecision(binding, B.ResidenceStack, B.ResidenceBecauseMaterializedTemporary)
                elseif state.backend[binding] then
                    decisions[#decisions + 1] = B.ResidenceDecision(binding, B.ResidenceStack, B.ResidenceBecauseBackendRequired)
                else
                    decisions[#decisions + 1] = B.ResidenceDecision(binding, B.ResidenceValue, B.ResidenceBecauseDefault)
                end
            end
            return single(B.ResidencePlan(decisions))
            end)(node, ...)
        else
            error("phase lalin_bind_residence_decide_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        mark_fact = mark_fact,
        decide_facts = decide_facts,
        decide = function(facts) return only(decide_facts(facts)) end,
    }
end

return bind_context