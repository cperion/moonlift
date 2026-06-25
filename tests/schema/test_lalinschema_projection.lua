package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local S = require("lalin.schema.dsl")
local Phase = require("lalin.phase_model")
local Project = require("lalin.project_asdl")

local T = pvm.context()
Phase(T)
Project(T)

local Ph = T.LalinPhase
local P = T.LalinProject

local world = Ph.World(Ph.WorldId("tree"), Ph.TypeRef("LalinTree", "Module"))
assert(world.id.text == "tree")
assert(world.ty.type_name == "Module")

local machine = Ph.Machine(
    Ph.MachineId("typecheck"),
    Ph.WorldId("tree"),
    Ph.WorldId("checked"),
    Ph.WorldId("diag"),
    Ph.MachineAbiStatusReturning,
    Ph.ImplLua("lalin.tree_typecheck", "typecheck"),
    { "diagnostics" }
)
assert(machine.input.text == "tree")
assert(machine.impl.function_name == "typecheck")

local phase = Ph.Phase(Ph.PhaseId("typecheck"), Ph.WorldId("tree"), Ph.WorldId("checked"), Ph.WorldId("diag"), Ph.CacheIdentity, true, Ph.MachineId("typecheck"))
assert(phase.machine.text == "typecheck")

local root = Ph.Root(Ph.RootId("compile"), Ph.WorldId("tree"), Ph.WorldId("checked"))
assert(root.id.text == "compile")
assert(root.output.text == "checked")

local step = Ph.PlanStep(1, Ph.PhaseId("typecheck"), Ph.MachineId("typecheck"), Ph.WorldId("tree"), Ph.WorldId("checked"), Ph.WorldId("diag"), Ph.CacheIdentity, true, Ph.MachineAbiStatusReturning, Ph.ImplLua("lalin.tree_typecheck", "typecheck"), { "diagnostics" })
local plan = Ph.Plan(Ph.RootId("compile"), Ph.WorldId("tree"), Ph.WorldId("checked"), { step })
assert(plan.steps[1].phase.text == "typecheck")

local id = P.TaskId("schema")
local task = P.Task(id, "schema projection", P.TaskDone, {})
assert(task.id == id)
assert(P.TaskStatus:isclassof(P.TaskDone))

local schema = Project.schema(pvm.context())
assert(schema.modules[1].name == "LalinProject")

local text = S.file_text(require("lalin.schema.project"), { width = 100, indent = 2 })
assert(text:match("schema%. LalinProject"))
assert(text:match("product%. Task"))

io.write("lalin lalinschema projection ok\n")
