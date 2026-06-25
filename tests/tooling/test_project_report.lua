package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local A = require("lalin.project_asdl")
local Facts = require("lalin.project_ready_facts")
local Report = require("lalin.project_report")

local T = pvm.context()
A(T)
local F = Facts(T)
local R = Report(T)
local P = T.LalinProject

local function id(text) return P.TaskId(text) end
local function has(xs, needle)
    for i = 1, #xs do if xs[i] == needle then return true end end
    return false
end

local schema = id("schema")
local back = id("back")
local tree = id("tree")
local parser = id("parser")
local docs = id("docs")
local future = id("future")
local missing = id("missing")

local project = P.Project({
    P.Task(schema, "define schema", P.TaskDone, {}),
    P.Task(back, "finish backend", P.TaskTodo, { schema }),
    P.Task(tree, "finish tree", P.TaskTodo, { back }),
    P.Task(parser, "write parser", P.TaskTodo, { tree, missing }),
    P.Task(docs, "sync docs", P.TaskDeferred("waiting for final architecture"), { schema }),
    P.Task(future, "future polish", P.TaskTodo, { docs }),
})

local facts = F.facts(project)
assert(has(facts, P.TaskDeclared(schema)))
assert(has(facts, P.TaskCompleted(schema)))
assert(has(facts, P.TaskDependsOn(back, schema)))
assert(has(facts, P.TaskReady(back)))
assert(has(facts, P.TaskBlocked(tree, { back })))
assert(has(facts, P.TaskBlocked(parser, { tree, missing })))
assert(has(facts, P.TaskDeferredFact(docs, "waiting for final architecture")))
assert(has(facts, P.TaskBlocked(future, { docs })))

local report = R.report(project)
assert(has(report.ready, back))
assert(has(report.blocked, tree))
assert(has(report.blocked, parser))
assert(has(report.blocked, future))
assert(has(report.done, schema))
assert(has(report.deferred, docs))
assert(#report.ready == 1)
assert(#report.done == 1)
assert(#report.deferred == 1)

print("lalin project_report ok")
