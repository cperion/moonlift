local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local B = T.MoonBind

    local decision_machine_binding
    local plan_machine_bindings

    function decision_machine_binding(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ResidenceDecision) then
            return (function(decision)

            return erased.once(B.MachineBinding(decision.binding, decision.residence))
            end)(node, ...)
        else
            error("erased phase moonlift_bind_decision_machine_binding: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function plan_machine_bindings(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ResidencePlan) then
            return (function(plan)

            local out = {}
            for i = 1, #plan.decisions do
                out[#out + 1] = erased.one(decision_machine_binding(plan.decisions[i]))
            end
            return erased.once(B.MachineBindingSet(out))
            end)(node, ...)
        else
            error("erased phase moonlift_bind_plan_machine_bindings: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        decision_machine_binding = decision_machine_binding,
        plan_machine_bindings = plan_machine_bindings,
        bind = function(plan) return erased.one(plan_machine_bindings(plan)) end,
    }
end

return M
