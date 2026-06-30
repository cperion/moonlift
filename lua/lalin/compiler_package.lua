-- Canonical Lalin compiler package.
--
-- This is the data-level entrypoint for the hosted compiler pipeline. The
-- package describes the compiler as LalinPhase worlds, machines, phases, and
-- roots; execution is handled by lalin.phase_plan + lalin.phase_execute.

local CompilerModel = require("lalin.compiler_model")
local PhaseDsl = require("lalin.phase_dsl")
local PhasePlan = require("lalin.phase_plan")

local M = {}

local SOURCE = [[
return package "lalin.compiler" {
    world. tree [LalinTree.Module],
    world. checked [LalinTree.TypeModuleResult],
    world. c_code [LalinCompiler.CodeResult],
    world. c [LalinC.CBackendUnit],
    world. diag [LalinDiag.Report],

    machine. hosted_typecheck {
        from. tree,
        to. checked,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "lalin.compiler_machines", func = "typecheck_module" },
        capabilities { "diagnostics", "source_index", "surface_resolve", "closure_convert" },
    },

    machine. hosted_checked_to_c_code {
        from. checked,
        to. c_code,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "lalin.compiler_machines", func = "checked_to_c_code" },
        capabilities { "diagnostics", "source_index", "layout", "tree_to_code" },
    },

    machine. hosted_c_code_to_c {
        from. c_code,
        to. c,
        diagnostics. diag,
        abi. process,
        impl. lua { module = "lalin.compiler_machines", func = "code_to_c" },
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
        to. c,
    },

    root. emit_c {
        from. tree,
        to. c,
    },

}
]]

local function bind_context(T)
    assert(T ~= nil, "lalin.compiler_package(T) expects a caller-owned schema context")
    CompilerModel(T)
    PhaseDsl(T)
    local chunk = assert(PhaseDsl.loadstring(SOURCE, "lalin.compiler_package.lua"))
    return chunk(), T
end

function M.package(T)
    return bind_context(T)
end

function M.plan(T, root)
    local pkg = bind_context(T)
    return PhasePlan.assert_plan(pkg, root or "compile")
end

M.source = SOURCE

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
