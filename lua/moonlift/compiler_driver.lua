-- Public Moonlift compiler driver.
--
-- This is the public orchestration boundary: module AST -> compiler package ->
-- plan -> execute. The hosted frontend pipeline is just the implementation of
-- the current compiler machine, not the public entrypoint.

local pvm = require("moonlift.pvm")
local CompilerPackage = require("moonlift.compiler_package")
local PhasePlan = require("moonlift.phase_plan")
local PhaseExecute = require("moonlift.phase_execute")

local M = {}

function M.lower_module(module, opts)
    opts = opts or {}
    local T = opts.context
    if T == nil then
        local cls = pvm.classof(module)
        T = cls and rawget(cls, "__context")
    end
    T = T or pvm.context()

    local package = CompilerPackage.Define(T)
    local planned = PhasePlan.assert_plan(package, opts.root or "compile")
    local executor = opts.executor or PhaseExecute.registry()
    local exec_opts = {}
    for k, v in pairs(opts) do exec_opts[k] = v end
    exec_opts.context = T
    local report = executor:run(planned.plan, module, exec_opts)
    if not report.ok then
        local messages = {}
        for i = 1, #report.diagnostics do
            local d = report.diagnostics[i]
            messages[#messages + 1] = tostring(d.code) .. ": " .. tostring(d.message)
        end
        error(table.concat(messages, "\n"), 2)
    end
    return report.output
end

function M.compile_jit(module, opts)
    opts = opts or {}
    local run_opts = {}
    for k, v in pairs(opts) do run_opts[k] = v end
    run_opts.root = "jit"
    local descriptor = M.lower_module(module, run_opts)
    local T = opts.context
    if T == nil then
        local cls = pvm.classof(module)
        T = cls and rawget(cls, "__context")
    end
    T = T or pvm.context()
    return require("moonlift.native_runtime").Define(T).wrap(descriptor)
end

return M
