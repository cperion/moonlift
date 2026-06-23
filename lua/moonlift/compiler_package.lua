-- Canonical Moonlift compiler package.
--
-- This is the data-level entrypoint for the hosted compiler pipeline. The
-- package describes the compiler as MoonPhase worlds, machines, phases, and
-- roots; execution is handled by moonlift.phase_plan + moonlift.phase_execute.

local pvm = require("moonlift.pvm")
local CompilerModel = require("moonlift.compiler_model")
local PhaseDsl = require("moonlift.phase_dsl")
local PhasePlan = require("moonlift.phase_plan")

local M = {}

local SOURCE = [[
return package "moonlift.compiler" {
    world. tree [MoonTree.Module],
    world. checked [MoonTree.TypeModuleResult],
    world. back_code [MoonCompiler.CodeResult],
    world. c_code [MoonCompiler.CodeResult],
    world. back [MoonBack.Program],
    world. flatline [MoonCompiler.FlatlineImage],
    world. native [MoonCompiler.NativeArtifact],
    world. object [MoonCompiler.ObjectArtifact],
    world. c [MoonC.CBackendUnit],
    world. diag [MoonDiag.Report],

    machine. hosted_typecheck {
        from. tree,
        to. checked,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "typecheck_module" },
        capabilities { "diagnostics", "source_index", "open_expand", "closure_convert" },
    },

    machine. hosted_checked_to_back_code {
        from. checked,
        to. back_code,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "checked_to_back_code" },
        capabilities { "diagnostics", "source_index", "layout", "tree_to_code" },
    },

    machine. hosted_back_code_to_back {
        from. back_code,
        to. back,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "code_to_back" },
        capabilities { "diagnostics", "code_facts", "cranelift_back" },
    },

    machine. hosted_back_to_flatline {
        from. back,
        to. flatline,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "back_to_flatline" },
        capabilities { "diagnostics", "flatline_encode", "cranelift_abi" },
    },

    machine. hosted_flatline_to_native {
        from. flatline,
        to. native,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "flatline_to_native" },
        capabilities { "diagnostics", "native_runtime", "cranelift_jit" },
    },

    machine. hosted_flatline_to_object {
        from. flatline,
        to. object,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "flatline_to_object" },
        capabilities { "diagnostics", "object_emit", "cranelift_object" },
    },

    machine. hosted_checked_to_c_code {
        from. checked,
        to. c_code,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "checked_to_c_code" },
        capabilities { "diagnostics", "source_index", "layout", "tree_to_code" },
    },

    machine. hosted_c_code_to_c {
        from. c_code,
        to. c,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "moonlift.compiler_machines", func = "code_to_c" },
        capabilities { "diagnostics", "code_facts", "c_backend" },
    },

    phase. typecheck {
        from. tree,
        to. checked,
        diagnostics. diag,
        cache. full,
        deterministic(true),
        machine. hosted_typecheck,
    },

    phase. checked_to_back_code {
        from. checked,
        to. back_code,
        diagnostics. diag,
        cache. full,
        deterministic(true),
        machine. hosted_checked_to_back_code,
    },

    phase. back_code_to_back {
        from. back_code,
        to. back,
        diagnostics. diag,
        cache. full,
        deterministic(true),
        machine. hosted_back_code_to_back,
    },

    phase. back_to_flatline {
        from. back,
        to. flatline,
        diagnostics. diag,
        cache. full,
        deterministic(true),
        machine. hosted_back_to_flatline,
    },

    phase. flatline_to_native {
        from. flatline,
        to. native,
        diagnostics. diag,
        cache. none,
        deterministic(false),
        machine. hosted_flatline_to_native,
    },

    phase. flatline_to_object {
        from. flatline,
        to. object,
        diagnostics. diag,
        cache. none,
        deterministic(false),
        machine. hosted_flatline_to_object,
    },

    phase. checked_to_c_code {
        from. checked,
        to. c_code,
        diagnostics. diag,
        cache. full,
        deterministic(true),
        machine. hosted_checked_to_c_code,
    },

    phase. c_code_to_c {
        from. c_code,
        to. c,
        diagnostics. diag,
        cache. full,
        deterministic(true),
        machine. hosted_c_code_to_c,
    },

    root. compile {
        from. tree,
        to. flatline,
    },

    root. emit_c {
        from. tree,
        to. c,
    },

    root. jit {
        from. tree,
        to. native,
    },

    root. emit_object {
        from. tree,
        to. object,
    },
}
]]

function M.Define(T)
    T = T or pvm.context()
    CompilerModel.Define(T)
    PhaseDsl.Define(T)
    local chunk = assert(PhaseDsl.loadstring(SOURCE, "moonlift.compiler_package.lua"))
    return chunk(), T
end

function M.package(T)
    return M.Define(T)
end

function M.plan(T, root)
    local pkg = M.Define(T)
    return PhasePlan.assert_plan(pkg, root or "compile")
end

M.source = SOURCE

return M
