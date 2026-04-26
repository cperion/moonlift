local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local P = T.Moon2Project
    local Facts = require("moonlift.project_ready_facts").Define(T)

    local project_report

    project_report = pvm.phase("moon2_project_report", {
        [P.Project] = function(project)
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
                local cls = pvm.classof(fact)
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
            return pvm.once(P.ProjectReport(facts, ready, blocked, done, deferred))
        end,
    })

    return {
        project_report = project_report,
        report = function(project) return pvm.one(project_report(project)) end,
    }
end

return M
