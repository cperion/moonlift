local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local P = T.MoonProject

    local task_base_facts
    local project_base_facts
    local project_ready_facts

    local function pack(g, p, c) return { g, p, c } end

    task_base_facts = pvm.phase("moon2_project_task_base_facts", {
        [P.Task] = function(task)
            local facts = { P.TaskDeclared(task.id) }
            if task.status == P.TaskDone then facts[#facts + 1] = P.TaskCompleted(task.id) end
            if pvm.classof(task.status) == P.TaskDeferred then facts[#facts + 1] = P.TaskDeferredFact(task.id, task.status.reason) end
            for i = 1, #task.deps do facts[#facts + 1] = P.TaskDependsOn(task.id, task.deps[i]) end
            return pvm.children(function(fact) return pvm.once(fact) end, facts)
        end,
    })

    project_base_facts = pvm.phase("moon2_project_base_facts", {
        [P.Project] = function(project)
            return pvm.children(task_base_facts, project.tasks)
        end,
    })

    project_ready_facts = pvm.phase("moon2_project_ready_facts", {
        [P.Project] = function(project)
            local declared = {}
            local done = {}
            local deferred = {}
            for i = 1, #project.tasks do
                local task = project.tasks[i]
                declared[task.id] = true
                if task.status == P.TaskDone then done[task.id] = true end
                if pvm.classof(task.status) == P.TaskDeferred then deferred[task.id] = true end
            end
            local facts = {}
            for i = 1, #project.tasks do
                local task = project.tasks[i]
                if task.status ~= P.TaskDone and not deferred[task.id] then
                    local blockers = {}
                    for j = 1, #task.deps do
                        local dep = task.deps[j]
                        if not declared[dep] or not done[dep] then blockers[#blockers + 1] = dep end
                    end
                    if #blockers == 0 then
                        facts[#facts + 1] = P.TaskReady(task.id)
                    else
                        facts[#facts + 1] = P.TaskBlocked(task.id, blockers)
                    end
                end
            end
            return pvm.children(function(fact) return pvm.once(fact) end, facts)
        end,
    })

    return {
        task_base_facts = task_base_facts,
        project_base_facts = project_base_facts,
        project_ready_facts = project_ready_facts,
        facts = function(project)
            local g1, p1, c1 = project_base_facts(project)
            local g2, p2, c2 = project_ready_facts(project)
            return pvm.drain(pvm.concat2(g1, p1, c1, g2, p2, c2))
        end,
    }
end

return M
