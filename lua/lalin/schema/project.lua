local S = require("lalin.schema.dsl")
S.use()

return schema. LalinProject {
  product. TaskId { interned, text [str], },
  sum. TaskStatus { TaskTodo, TaskDone, TaskDeferred { variant_unique, reason [str], }, },
  product. Task {
    interned,
    field. id [LalinProject.TaskId],
    title [str],
    status [LalinProject.TaskStatus],
    deps [many [LalinProject.TaskId]],
  },
  product. Project { interned, tasks [many [LalinProject.Task]], },
  sum. TaskFact {
    TaskDeclared { variant_unique, field. id [LalinProject.TaskId], },
    TaskCompleted { variant_unique, field. id [LalinProject.TaskId], },
    TaskDependsOn {
      variant_unique,
      field. id [LalinProject.TaskId],
      dep [LalinProject.TaskId],
    },
    TaskDeferredFact { variant_unique, field. id [LalinProject.TaskId], reason [str], },
    TaskReady { variant_unique, field. id [LalinProject.TaskId], },
    TaskBlocked {
      variant_unique,
      field. id [LalinProject.TaskId],
      missing_or_incomplete [many [LalinProject.TaskId]],
    },
  },
  product. ProjectReport {
    interned,
    facts [many [LalinProject.TaskFact]],
    ready [many [LalinProject.TaskId]],
    blocked [many [LalinProject.TaskId]],
    done [many [LalinProject.TaskId]],
    deferred [many [LalinProject.TaskId]],
  },
}
