package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local PhaseModel = require("moonlift.phase_model")
local PhaseDsl = require("moonlift.phase_dsl")
local Plan = require("moonlift.phase_plan")

local T = pvm.context()
PhaseModel(T)
PhaseDsl(T)
local P = T.MoonPhase

local pkg = assert(PhaseDsl.loadstring([[
return package "moonlift.compiler" {
    world. tree [MoonTree.Module],
    world. checked [MoonTree.TypecheckResult],
    world. code [MoonCode.CodeModule],
    world. back [MoonBack.Program],
    world. diag [MoonDiag.Report],

    machine. moon_typecheck {
        from. tree,
        to. checked,
        diagnostics. diag,
        abi. status_returning,
        impl. lua { module = "moonlift.tree_typecheck", func = "typecheck" },
        capabilities { "diagnostics", "source_index" },
    },

    machine. moon_tree_to_code {
        from. checked,
        to. code,
        diagnostics. diag,
        abi. process,
        impl. moonlift { module = "moonlift.tree_to_code", func = "lower" },
    },

    machine. moon_lower_to_back {
        from. code,
        to. back,
        diagnostics. diag,
        abi. c,
        impl. c { symbol = "moon_lower_to_back" },
    },

    phase. typecheck {
        from. tree,
        to. checked,
        diagnostics. diag,
        cache. identity,
        deterministic(true),
        machine. moon_typecheck,
    },

    phase. tree_to_code {
        from. checked,
        to. code,
        diagnostics. diag,
        cache. node,
        deterministic(true),
        machine. moon_tree_to_code,
    },

    phase. lower_to_back {
        from. code,
        to. back,
        diagnostics. diag,
        cache. full,
        deterministic(true),
        machine. moon_lower_to_back,
    },

    root. compile {
        from. tree,
        to. back,
    },
}
]], "phase_plan_test.lua"))()

local report = Plan.plan(pkg, "compile")
assert(report.ok)
assert(pvm.classof(report.plan) == P.Plan)
assert(#report.plan.steps == 3)
assert(report.plan.steps[1].phase.text == "typecheck")
assert(report.input == "tree")
assert(report.output == "back")
assert(#report.steps == 3)
assert(report.steps[1].phase_id == "typecheck")
assert(report.steps[1].machine_id == "moon_typecheck")
assert(report.steps[1].input == "tree")
assert(report.steps[1].output == "checked")
assert(report.steps[1].diagnostics == "diag")
assert(report.steps[2].phase_id == "tree_to_code")
assert(report.steps[2].machine_id == "moon_tree_to_code")
assert(report.steps[3].phase_id == "lower_to_back")
assert(report.steps[3].machine_id == "moon_lower_to_back")

local seen = {}
local handle = Plan.process:start(pkg, "compile")
for ev in handle:events() do seen[ev.kind] = (seen[ev.kind] or 0) + 1 end
assert(handle:result().ok)
assert(seen.plan_start == 1)
assert(seen.root == 1)
assert(seen.step == 3)
assert(seen.plan_done == 1)

local function has_code(plan, code)
    for i = 1, #plan.diagnostics do
        if plan.diagnostics[i].code == code then return true end
    end
    return false
end

local ambiguous = P.Package(
    P.PackageId("bad.ambiguous"),
    {
        P.World(P.WorldId("a"), P.TypeRefValue("A")),
        P.World(P.WorldId("b"), P.TypeRefValue("B")),
        P.World(P.WorldId("c"), P.TypeRefValue("C")),
        P.World(P.WorldId("d"), P.TypeRefValue("D")),
    },
    {
        P.Machine(P.MachineId("m1"), P.WorldId("a"), P.WorldId("b"), nil, P.MachineAbiPure, P.ImplLua("mod", "m1"), {}),
        P.Machine(P.MachineId("m2"), P.WorldId("b"), P.WorldId("d"), nil, P.MachineAbiPure, P.ImplLua("mod", "m2"), {}),
        P.Machine(P.MachineId("m3"), P.WorldId("a"), P.WorldId("c"), nil, P.MachineAbiPure, P.ImplLua("mod", "m3"), {}),
        P.Machine(P.MachineId("m4"), P.WorldId("c"), P.WorldId("d"), nil, P.MachineAbiPure, P.ImplLua("mod", "m4"), {}),
    },
    {
        P.Phase(P.PhaseId("p1"), P.WorldId("a"), P.WorldId("b"), nil, P.CacheIdentity, true, P.MachineId("m1")),
        P.Phase(P.PhaseId("p2"), P.WorldId("b"), P.WorldId("d"), nil, P.CacheIdentity, true, P.MachineId("m2")),
        P.Phase(P.PhaseId("p3"), P.WorldId("a"), P.WorldId("c"), nil, P.CacheIdentity, true, P.MachineId("m3")),
        P.Phase(P.PhaseId("p4"), P.WorldId("c"), P.WorldId("d"), nil, P.CacheIdentity, true, P.MachineId("m4")),
    },
    { P.Root(P.RootId("compile"), P.WorldId("a"), P.WorldId("d")) }
)
local ambiguous_report = Plan.plan(ambiguous, "compile")
assert(not ambiguous_report.ok)
assert(has_code(ambiguous_report, "E_AMBIGUOUS_PHASE_PATH"))

local no_path = P.Package(
    P.PackageId("bad.no_path"),
    { P.World(P.WorldId("a"), P.TypeRefValue("A")), P.World(P.WorldId("b"), P.TypeRefValue("B")) },
    {},
    {},
    { P.Root(P.RootId("compile"), P.WorldId("a"), P.WorldId("b")) }
)
local no_path_report = Plan.plan(no_path, "compile")
assert(not no_path_report.ok)
assert(has_code(no_path_report, "E_NO_PHASE_PATH"))

local unknown_root = Plan.plan(pkg, "missing")
assert(not unknown_root.ok)
assert(has_code(unknown_root, "E_UNKNOWN_ROOT"))

io.write("moonlift phase_plan ok\n")
