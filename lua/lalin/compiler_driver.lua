-- Public Lalin compiler driver.
--
-- This is the public orchestration boundary: module AST -> compiler package ->
-- plan -> execute. The hosted frontend pipeline is just the implementation of
-- the current compiler machine, not the public entrypoint.

local asdl = require("lalin.asdl")
local CompilerPackage = require("lalin.compiler_package")
local PhasePlan = require("lalin.phase_plan")
local PhaseExecute = require("lalin.phase_execute")

local M = {}

function M.lower_module(module, opts)
    opts = opts or {}
    local T = opts.context
    if T == nil then
        local cls = asdl.classof(module)
        T = cls and asdl.context_of(cls)
    end
    T = T or asdl.context()

    local package = CompilerPackage(T)
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

return M
