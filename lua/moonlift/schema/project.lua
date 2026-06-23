local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonProject {
  product. TaskId { interned, text [str], },
  sum. TaskStatus { TaskTodo, TaskDone, TaskDeferred { variant_unique, reason [str], }, },
  product. Task {
    interned,
    field. id [MoonProject.TaskId],
    title [str],
    status [MoonProject.TaskStatus],
    deps [many [MoonProject.TaskId]],
  },
  product. Project { interned, tasks [many [MoonProject.Task]], },
  sum. TaskFact {
    TaskDeclared { variant_unique, field. id [MoonProject.TaskId], },
    TaskCompleted { variant_unique, field. id [MoonProject.TaskId], },
    TaskDependsOn {
      variant_unique,
      field. id [MoonProject.TaskId],
      dep [MoonProject.TaskId],
    },
    TaskDeferredFact { variant_unique, field. id [MoonProject.TaskId], reason [str], },
    TaskReady { variant_unique, field. id [MoonProject.TaskId], },
    TaskBlocked {
      variant_unique,
      field. id [MoonProject.TaskId],
      missing_or_incomplete [many [MoonProject.TaskId]],
    },
  },
  product. ProjectReport {
    interned,
    facts [many [MoonProject.TaskFact]],
    ready [many [MoonProject.TaskId]],
    blocked [many [MoonProject.TaskId]],
    done [many [MoonProject.TaskId]],
    deferred [many [MoonProject.TaskId]],
  },
}
