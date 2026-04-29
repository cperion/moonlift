local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local B = T.MoonBind

    local mark_fact
    local decide_facts

    mark_fact = pvm.phase("moon2_bind_residence_mark_fact", {
        [B.ResidenceFactBinding] = function() return pvm.empty() end,
        [B.ResidenceFactAddressTaken] = function(self, state) state.address[self.binding] = true; return pvm.empty() end,
        [B.ResidenceFactMutableCell] = function(self, state) state.mutable[self.binding] = true; return pvm.empty() end,
        [B.ResidenceFactNonScalarAbi] = function(self, state) state.nonscalar[self.binding] = true; return pvm.empty() end,
        [B.ResidenceFactMaterializedTemporary] = function(self, state) state.materialized[self.binding] = true; return pvm.empty() end,
        [B.ResidenceFactBackendRequired] = function(self, state) state.backend[self.binding] = true; return pvm.empty() end,
    }, { args_cache = "none" })

    decide_facts = pvm.phase("moon2_bind_residence_decide_facts", {
        [B.ResidenceFactSet] = function(fact_set)
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
            return pvm.once(B.ResidencePlan(decisions))
        end,
    })

    return {
        mark_fact = mark_fact,
        decide_facts = decide_facts,
        decide = function(facts) return pvm.one(decide_facts(facts)) end,
    }
end

return M
