package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local PhaseModel = require("moonlift.phase_model")
local PhaseDsl = require("moonlift.phase_dsl")
local Plan = require("moonlift.phase_plan")
local Execute = require("moonlift.phase_execute")

local T = pvm.context()
PhaseModel.Define(T)
PhaseDsl.Define(T)

local pkg = assert(PhaseDsl.loadstring([[
return package "demo.compiler" {
    world. source [Demo.Source],
    world. checked [Demo.Checked],
    world. back [Demo.Back],

    machine. check {
        from. source,
        to. checked,
        abi. pure,
        impl. lua { module = "demo.compiler", func = "check" },
    },

    machine. lower {
        from. checked,
        to. back,
        abi. pure,
        impl. lua { module = "demo.compiler", func = "lower" },
    },

    phase. check {
        from. source,
        to. checked,
        cache. identity,
        deterministic(true),
        machine. check,
    },

    phase. lower {
        from. checked,
        to. back,
        cache. full,
        deterministic(true),
        machine. lower,
    },

    root. compile {
        from. source,
        to. back,
    },
}
]], "phase_execute_test.lua"))()

local planned = Plan.assert_plan(pkg, "compile")
local executor = Execute.registry()
executor:register_lua("demo.compiler", "check", function(input)
    return { checked = input.source + 1 }
end)
executor:register_lua("demo.compiler", "lower", function(input)
    return { code = input.checked * 2 }
end)

local report = executor:run(planned.plan, { source = 20 })
assert(report.ok)
assert(report.output.code == 42)
assert(#report.steps == 2)
assert(report.run.status == "done")
assert(report.run.task.value == "compile")
assert(#report.run.events == 6)
assert(#report.run.steps == 2)

local seen = {}
local handle = executor:process(planned.plan, { source = 1 })
for ev in handle:events() do seen[ev.kind] = (seen[ev.kind] or 0) + 1 end
assert(handle:result().output.code == 4)
assert(seen.execute_start == 1)
assert(seen.step_start == 2)
assert(seen.step_done == 2)
assert(seen.execute_done == 1)

local unbound = Execute.registry():run(planned.plan, { source = 1 })
assert(not unbound.ok)
assert(unbound.diagnostics[1].code == "E_MACHINE_UNBOUND")
assert(unbound.run.status == "failed")
assert(unbound.run.steps[1].status == "failed")

io.write("moonlift phase_execute ok\n")
