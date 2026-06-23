package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local PhaseModel = require("moonlift.phase_model")
local PhaseDsl = require("moonlift.phase_dsl")

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
        abi. cranelift,
        impl. cranelift { symbol = "moon_lower_to_back" },
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
]], "phase_dsl_test.lua"))()

assert(pvm.classof(pkg) == P.Package)
assert(pkg.id.text == "moonlift.compiler")

local formatted = PhaseDsl.format(pkg)
assert(formatted:match("package%. moonlift%.compiler"), "phase formatter should print package head")
assert(formatted:match("\n  world%. tree %[MoonTree%.Module%],"), "phase formatter should use multiline package bodies")
assert(formatted:match("impl%. lua"), "phase formatter should print implementation directive")
assert(not formatted:match("table: 0x"), "phase formatter should not leak raw Lua table addresses")
assert(#pkg.worlds == 5)
assert(#pkg.machines == 3)
assert(#pkg.phases == 3)
assert(#pkg.roots == 1)

local tree = pkg.worlds[1]
assert(tree.id.text == "tree")
assert(pvm.classof(tree.ty) == P.TypeRef)
assert(tree.ty.module_name == "MoonTree")
assert(tree.ty.type_name == "Module")

local machine = pkg.machines[1]
assert(machine.id.text == "moon_typecheck")
assert(machine.input.text == "tree")
assert(machine.output.text == "checked")
assert(machine.diagnostics.text == "diag")
assert(machine.abi == P.MachineAbiStatusReturning)
assert(pvm.classof(machine.impl) == P.ImplLua)
assert(machine.impl.module_name == "moonlift.tree_typecheck")
assert(machine.impl.function_name == "typecheck")
assert(machine.capabilities[1] == "diagnostics")

local phase = pkg.phases[2]
assert(phase.id.text == "tree_to_code")
assert(phase.input.text == "checked")
assert(phase.output.text == "code")
assert(phase.cache == P.CacheNode)
assert(phase.deterministic == true)
assert(phase.machine.text == "moon_tree_to_code")

assert(pkg.roots[1].id.text == "compile")
assert(pkg.roots[1].input.text == "tree")
assert(pkg.roots[1].output.text == "back")

io.write("moonlift phase_dsl ok\n")
