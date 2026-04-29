local M = {}

M.SCHEMA = [[
module MoonProject {
    TaskId = (string text) unique
    TaskStatus = TaskTodo | TaskDone | TaskDeferred(string reason) unique
    Task = (MoonProject.TaskId id, string title, MoonProject.TaskStatus status, MoonProject.TaskId* deps) unique
    Project = (MoonProject.Task* tasks) unique
    TaskFact = TaskDeclared(MoonProject.TaskId id) unique
             | TaskCompleted(MoonProject.TaskId id) unique
             | TaskDependsOn(MoonProject.TaskId id, MoonProject.TaskId dep) unique
             | TaskDeferredFact(MoonProject.TaskId id, string reason) unique
             | TaskReady(MoonProject.TaskId id) unique
             | TaskBlocked(MoonProject.TaskId id, MoonProject.TaskId* missing_or_incomplete) unique
    ProjectReport = (MoonProject.TaskFact* facts, MoonProject.TaskId* ready, MoonProject.TaskId* blocked, MoonProject.TaskId* done, MoonProject.TaskId* deferred) unique
}
]]

function M.Define(T)
    T:Define(M.SCHEMA)
    return T
end

return M
