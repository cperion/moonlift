-- Project tracking schema, authored with table-builder syntax.

local Model = require("moonlift.asdl_model")
local Builder = require("moonlift.asdl_builder")
local DefineSchema = require("moonlift.context_define_schema")

local M = {}

function M.schema(T)
    Model.Define(T)
    local A = Builder.Define(T)
    return A.schema {
        A.module "MoonProject" {
            A.product "TaskId" {
                A.field "text" "string",
                A.unique,
            },
            A.sum "TaskStatus" {
                A.variant "TaskTodo",
                A.variant "TaskDone",
                A.variant "TaskDeferred" {
                    A.field "reason" "string",
                    A.variant_unique,
                },
            },
            A.product "Task" {
                A.field "id" "MoonProject.TaskId",
                A.field "title" "string",
                A.field "status" "MoonProject.TaskStatus",
                A.field "deps" (A.many "MoonProject.TaskId"),
                A.unique,
            },
            A.product "Project" {
                A.field "tasks" (A.many "MoonProject.Task"),
                A.unique,
            },
            A.sum "TaskFact" {
                A.variant "TaskDeclared" {
                    A.field "id" "MoonProject.TaskId",
                    A.variant_unique,
                },
                A.variant "TaskCompleted" {
                    A.field "id" "MoonProject.TaskId",
                    A.variant_unique,
                },
                A.variant "TaskDependsOn" {
                    A.field "id" "MoonProject.TaskId",
                    A.field "dep" "MoonProject.TaskId",
                    A.variant_unique,
                },
                A.variant "TaskDeferredFact" {
                    A.field "id" "MoonProject.TaskId",
                    A.field "reason" "string",
                    A.variant_unique,
                },
                A.variant "TaskReady" {
                    A.field "id" "MoonProject.TaskId",
                    A.variant_unique,
                },
                A.variant "TaskBlocked" {
                    A.field "id" "MoonProject.TaskId",
                    A.field "missing_or_incomplete" (A.many "MoonProject.TaskId"),
                    A.variant_unique,
                },
            },
            A.product "ProjectReport" {
                A.field "facts" (A.many "MoonProject.TaskFact"),
                A.field "ready" (A.many "MoonProject.TaskId"),
                A.field "blocked" (A.many "MoonProject.TaskId"),
                A.field "done" (A.many "MoonProject.TaskId"),
                A.field "deferred" (A.many "MoonProject.TaskId"),
                A.unique,
            },
        },
    }
end

function M.Define(T)
    return DefineSchema.define(T, M.schema(T))
end

return M
