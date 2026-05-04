local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local B = T.MoonBind

    local decision_machine_binding
    local plan_machine_bindings

    decision_machine_binding = pvm.phase("moonlift_bind_decision_machine_binding", {
        [B.ResidenceDecision] = function(decision)
            return pvm.once(B.MachineBinding(decision.binding, decision.residence))
        end,
    })

    plan_machine_bindings = pvm.phase("moonlift_bind_plan_machine_bindings", {
        [B.ResidencePlan] = function(plan)
            local out = {}
            for i = 1, #plan.decisions do
                out[#out + 1] = pvm.one(decision_machine_binding(plan.decisions[i]))
            end
            return pvm.once(B.MachineBindingSet(out))
        end,
    })

    return {
        decision_machine_binding = decision_machine_binding,
        plan_machine_bindings = plan_machine_bindings,
        bind = function(plan) return pvm.one(plan_machine_bindings(plan)) end,
    }
end

return M
