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
    local P = T.LalinProject
    local Facts = require("lalin.project_ready_facts")(T)

    local project_report

    function project_report(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, P.Project) then
            return (function(project)

            local facts = Facts.facts(project)
            local ready = {}
            local blocked = {}
            local done = {}
            local deferred = {}
            local seen_ready = {}
            local seen_blocked = {}
            local seen_done = {}
            local seen_deferred = {}
            for i = 1, #facts do
                local fact = facts[i]
                local cls = schema.classof(fact)
                if cls == P.TaskReady and not seen_ready[fact.id] then
                    seen_ready[fact.id] = true
                    ready[#ready + 1] = fact.id
                elseif cls == P.TaskBlocked and not seen_blocked[fact.id] then
                    seen_blocked[fact.id] = true
                    blocked[#blocked + 1] = fact.id
                elseif cls == P.TaskCompleted and not seen_done[fact.id] then
                    seen_done[fact.id] = true
                    done[#done + 1] = fact.id
                elseif cls == P.TaskDeferredFact and not seen_deferred[fact.id] then
                    seen_deferred[fact.id] = true
                    deferred[#deferred + 1] = fact.id
                end
            end
            return single(P.ProjectReport(facts, ready, blocked, done, deferred))
            end)(node, ...)
        else
            error("phase lalin_project_report: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        project_report = project_report,
        report = function(project) return only(project_report(project)) end,
    }
end

return bind_context