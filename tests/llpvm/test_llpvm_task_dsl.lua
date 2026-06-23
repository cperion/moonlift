package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ll = require("llpvm")
local pvm = require("pvm")

local env = {}
require("moonlift").use { scope = "env", target = env, global = false, searcher = false }
ll.use { scope = "env", target = env, global = false, searcher = false }

local chunk = assert(loadstring([[
return task. compile {
    input [i32],
    output [i32],
    event. progress [i32],
    event. diagnostic [i32],
}
]], "llpvm_task_dsl_test.lua"))
setfenv(chunk, env)

local spec = chunk()
assert(getmetatable(spec) == ll.TaskSpec)

local asdl = spec:asdl()
assert(pvm.classof(asdl) == ll.T.LlPvm.TaskSpec)
assert(asdl.name.value == "compile")
assert(#asdl.events == 2)
assert(asdl.events[1].name.value == "progress")

local run = ll.task_run("compile", "done", {
    ll.task_event(1, "progress", "typecheck"),
}, {
    ll.task_step(1, "typecheck", "hosted_typecheck", "done"),
})
assert(pvm.classof(run) == ll.T.LlPvm.TaskRun)
assert(run.task.value == "compile")
assert(run.events[1].kind == "progress")
assert(run.steps[1].phase == "typecheck")

io.write("llpvm task_dsl ok\n")
