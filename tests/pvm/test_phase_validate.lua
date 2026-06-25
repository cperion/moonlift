package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local PhaseModel = require("lalin.phase_model")
local PhaseDsl = require("lalin.phase_dsl")
local Validate = require("lalin.phase_validate")

local T = pvm.context()
PhaseModel(T)
PhaseDsl(T)
local P = T.LalinPhase

local function package_from_source(src)
    return assert(PhaseDsl.loadstring(src, "phase_validate_test.lua"))()
end

local function sample_package()
    return package_from_source([[
return package "lalin.compiler" {
    world. tree [LalinTree.Module],
    world. checked [LalinTree.TypecheckResult],
    world. diag [LalinDiag.Report],

    machine. lalin_typecheck {
        from. tree,
        to. checked,
        diagnostics. diag,
        abi. status_returning,
        impl. lua { module = "lalin.tree_typecheck", func = "typecheck" },
        capabilities { "diagnostics" },
    },

    phase. typecheck {
        from. tree,
        to. checked,
        diagnostics. diag,
        cache. identity,
        deterministic(true),
        machine. lalin_typecheck,
    },

    root. compile {
        from. tree,
        to. checked,
    },
}
]])
end

local function has_code(report, code)
    for i = 1, #report.diagnostics do
        if report.diagnostics[i].code == code then return true end
    end
    return false
end

local ok_pkg = sample_package()
local ok_report = Validate.validate(ok_pkg)
assert(ok_report.ok)
assert(#ok_report.worlds == 3)
assert(#ok_report.machines == 1)
assert(#ok_report.phases == 1)
assert(#ok_report.roots == 1)

local seen = {}
local handle = Validate.process:start(ok_pkg)
for ev in handle:events() do seen[ev.kind] = true end
assert(handle:result().ok)
assert(seen.validate_start)
assert(seen.world)
assert(seen.machine)
assert(seen.phase)
assert(seen.root)
assert(seen.validate_done)

local duplicate_world = P.Package(
    P.PackageId("bad.duplicate"),
    { P.World(P.WorldId("tree"), P.TypeRefValue("Tree")), P.World(P.WorldId("tree"), P.TypeRefValue("Other")) },
    {},
    {},
    {}
)
local duplicate_report = Validate.validate(duplicate_world)
assert(not duplicate_report.ok)
assert(has_code(duplicate_report, "E_DUPLICATE_WORLD"))

local missing_world = P.Package(
    P.PackageId("bad.world"),
    { P.World(P.WorldId("tree"), P.TypeRefValue("Tree")) },
    { P.Machine(P.MachineId("m"), P.WorldId("missing"), P.WorldId("tree"), nil, P.MachineAbiPure, P.ImplLua("mod", "run"), {}) },
    {},
    {}
)
local missing_world_report = Validate.validate(missing_world)
assert(not missing_world_report.ok)
assert(has_code(missing_world_report, "E_UNKNOWN_WORLD"))

local missing_machine = P.Package(
    P.PackageId("bad.machine"),
    { P.World(P.WorldId("tree"), P.TypeRefValue("Tree")), P.World(P.WorldId("checked"), P.TypeRefValue("Checked")) },
    {},
    { P.Phase(P.PhaseId("typecheck"), P.WorldId("tree"), P.WorldId("checked"), nil, P.CacheIdentity, true, P.MachineId("missing")) },
    {}
)
local missing_machine_report = Validate.validate(missing_machine)
assert(not missing_machine_report.ok)
assert(has_code(missing_machine_report, "E_UNKNOWN_MACHINE"))

local mismatch = P.Package(
    P.PackageId("bad.mismatch"),
    {
        P.World(P.WorldId("tree"), P.TypeRefValue("Tree")),
        P.World(P.WorldId("checked"), P.TypeRefValue("Checked")),
        P.World(P.WorldId("code"), P.TypeRefValue("Code")),
    },
    { P.Machine(P.MachineId("m"), P.WorldId("tree"), P.WorldId("checked"), nil, P.MachineAbiPure, P.ImplLua("mod", "run"), {}) },
    { P.Phase(P.PhaseId("typecheck"), P.WorldId("code"), P.WorldId("checked"), nil, P.CacheIdentity, true, P.MachineId("m")) },
    { P.Root(P.RootId("compile"), P.WorldId("tree"), P.WorldId("checked")) }
)
local mismatch_report = Validate.validate(mismatch)
assert(not mismatch_report.ok)
assert(has_code(mismatch_report, "E_PHASE_MACHINE_INPUT_MISMATCH"))

local bad_impl = P.Package(
    P.PackageId("bad.impl"),
    { P.World(P.WorldId("tree"), P.TypeRefValue("Tree")) },
    { P.Machine(P.MachineId("m"), P.WorldId("tree"), P.WorldId("tree"), nil, P.MachineAbiPure, P.ImplLua("", ""), {}) },
    {},
    {}
)
local bad_impl_report = Validate.validate(bad_impl)
assert(not bad_impl_report.ok)
assert(has_code(bad_impl_report, "E_BAD_IMPL"))

local ok, err = pcall(function()
    return package_from_source([[
return package "bad.dsl" {
    world. tree [LalinTree.Module],
    phase. typecheck {
        from. tree,
        to. tree,
        machine. missing,
    },
    root. compile {
        from. tree,
        to. tree,
    },
}
]])
end)
assert(not ok)
assert(tostring(err):match("E_UNKNOWN_MACHINE"))

local string_ok, string_err = pcall(function()
    return package_from_source([[
return package "bad.string_type_ref" {
    world. tree ["LalinTree.Module"],
}
]])
end)
assert(not string_ok)
assert(tostring(string_err):match("E_BAD_SLOT"))

io.write("lalin phase_validate ok\n")
