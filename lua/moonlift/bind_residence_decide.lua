local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local B = T.MoonBind

    local mark_fact
    local decide_facts

    function mark_fact(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ResidenceFactBinding) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactAddressTaken) then
            return (function(self, state)
 state.address[self.binding] = true; return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactMutableCell) then
            return (function(self, state)
 state.mutable[self.binding] = true; return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactNonScalarAbi) then
            return (function(self, state)
 state.nonscalar[self.binding] = true; return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactMaterializedTemporary) then
            return (function(self, state)
 state.materialized[self.binding] = true; return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ResidenceFactBackendRequired) then
            return (function(self, state)
 state.backend[self.binding] = true; return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_mark_fact: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
                local g, p, c = mark_fact(fact_set.facts[i], state)
                pvm.drain(g, p, c)
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
            return erased.once(B.ResidencePlan(decisions))
            end)(node, ...)
        else
            error("erased phase moonlift_bind_residence_decide_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        mark_fact = mark_fact,
        decide_facts = decide_facts,
        decide = function(facts) return erased.one(decide_facts(facts)) end,
    }
end

return M
