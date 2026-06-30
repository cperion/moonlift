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

    local decision_machine_binding
    local plan_machine_bindings

    function decision_machine_binding(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ResidenceDecision) then
            return (function(decision)

            return single(B.MachineBinding(decision.binding, decision.residence))
            end)(node, ...)
        else
            error("phase lalin_bind_decision_machine_binding: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function plan_machine_bindings(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ResidencePlan) then
            return (function(plan)

            local out = {}
            for i = 1, #plan.decisions do
                out[#out + 1] = only(decision_machine_binding(plan.decisions[i]))
            end
            return single(B.MachineBindingSet(out))
            end)(node, ...)
        else
            error("phase lalin_bind_plan_machine_bindings: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        decision_machine_binding = decision_machine_binding,
        plan_machine_bindings = plan_machine_bindings,
        bind = function(plan) return only(plan_machine_bindings(plan)) end,
    }
end

return bind_context