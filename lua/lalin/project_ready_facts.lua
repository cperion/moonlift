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

    local task_base_facts
    local project_base_facts
    local project_ready_facts

    function task_base_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, P.Task) then
            return (function(task)

            local facts = { P.TaskDeclared(task.id) }
            if task.status == P.TaskDone then facts[#facts + 1] = P.TaskCompleted(task.id) end
            if schema.classof(task.status) == P.TaskDeferred then facts[#facts + 1] = P.TaskDeferredFact(task.id, task.status.reason) end
            for i = 1, #task.deps do facts[#facts + 1] = P.TaskDependsOn(task.id, task.deps[i]) end
            return flat_map(function(fact) return single(fact) end, facts)
            end)(node, ...)
        else
            error("phase lalin_project_task_base_facts: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function project_base_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, P.Project) then
            return (function(project)

            return flat_map(task_base_facts, project.tasks)
            end)(node, ...)
        else
            error("phase lalin_project_base_facts: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function project_ready_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, P.Project) then
            return (function(project)

            local declared = {}
            local done = {}
            local deferred = {}
            for i = 1, #project.tasks do
                local task = project.tasks[i]
                declared[task.id] = true
                if task.status == P.TaskDone then done[task.id] = true end
                if schema.classof(task.status) == P.TaskDeferred then deferred[task.id] = true end
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
            return flat_map(function(fact) return single(fact) end, facts)
            end)(node, ...)
        else
            error("phase lalin_project_ready_facts: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        task_base_facts = task_base_facts,
        project_base_facts = project_base_facts,
        project_ready_facts = project_ready_facts,
        facts = function(project)
            local g1, p1, c1 = project_base_facts(project)
            local g2, p2, c2 = project_ready_facts(project)
            return concat2(g1, g2)
        end,
    }
end

return bind_context