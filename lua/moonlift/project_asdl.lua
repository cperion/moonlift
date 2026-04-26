local M = {}

M.SCHEMA = [[
module Moon2Project {
    TaskId = (string text) unique
    TaskStatus = TaskTodo | TaskDone | TaskDeferred(string reason) unique
    Task = (Moon2Project.TaskId id, string title, Moon2Project.TaskStatus status, Moon2Project.TaskId* deps) unique
    Project = (Moon2Project.Task* tasks) unique
    TaskFact = TaskDeclared(Moon2Project.TaskId id) unique
             | TaskCompleted(Moon2Project.TaskId id) unique
             | TaskDependsOn(Moon2Project.TaskId id, Moon2Project.TaskId dep) unique
             | TaskDeferredFact(Moon2Project.TaskId id, string reason) unique
             | TaskReady(Moon2Project.TaskId id) unique
             | TaskBlocked(Moon2Project.TaskId id, Moon2Project.TaskId* missing_or_incomplete) unique
    ProjectReport = (Moon2Project.TaskFact* facts, Moon2Project.TaskId* ready, Moon2Project.TaskId* blocked, Moon2Project.TaskId* done, Moon2Project.TaskId* deferred) unique
}
]]

function M.Define(T)
    T:Define(M.SCHEMA)
    return T
end

return M
