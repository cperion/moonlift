-- Hosted machine implementations for lalin.compiler_package.

local asdl = require("lalin.asdl")

local M = {}

local function context_of(node)
    local cls = asdl.classof(node)
    local ctx = cls and asdl.context_of(cls)
    if ctx then return ctx end
    error("lalin.compiler_machines: input value does not carry a schema context", 3)
end

local function process_result_or_error(handle, label)
    local result = handle:result()
    if result ~= nil then return result end
    local diagnostics = handle.diagnostics and handle.diagnostics.items or {}
    local messages = {}
    for i = 1, #diagnostics do
        messages[#messages + 1] = tostring(diagnostics[i].code) .. ": " .. tostring(diagnostics[i].message)
    end
    error(label .. (#messages > 0 and (": " .. table.concat(messages, "\n")) or ""), 3)
end

function M.typecheck_module(module, _step, call)
    local T = (call and call.opts and call.opts.context) or context_of(module)
    local opts = {}
    if call and call.opts then
        for k, v in pairs(call.opts) do opts[k] = v end
    end
    opts.context = nil
    local Pipeline = require("lalin.frontend_pipeline")(T)
    local handle = Pipeline.typecheck_module_process:start(module, opts)
    for _ in handle:events() do end
    return process_result_or_error(handle, "lalin compiler machine typecheck_module failed")
end

function M.checked_to_c_code(checked, _step, call)
    local T = (call and call.opts and call.opts.context) or context_of(checked)
    local opts = {}
    if call and call.opts then
        for k, v in pairs(call.opts) do opts[k] = v end
    end
    opts.root = "emit_c"
    opts.context = nil
    local Pipeline = require("lalin.frontend_pipeline")(T)
    local handle = Pipeline.checked_to_code_process:start(checked, opts)
    for _ in handle:events() do end
    return process_result_or_error(handle, "lalin compiler machine checked_to_c_code failed")
end

function M.code_to_c(code_result, _step, call)
    local T = (call and call.opts and call.opts.context) or context_of(code_result)
    local opts = {}
    if call and call.opts then
        for k, v in pairs(call.opts) do opts[k] = v end
    end
    opts.context = nil
    local Pipeline = require("lalin.frontend_pipeline")(T)
    local handle = Pipeline.code_to_c_process:start(code_result, opts)
    for _ in handle:events() do end
    local result = process_result_or_error(handle, "lalin compiler machine code_to_c failed")
    if result.c_report and result.c_report.issues and #result.c_report.issues ~= 0 then
        local messages = {}
        for i = 1, #result.c_report.issues do messages[#messages + 1] = tostring(result.c_report.issues[i]) end
        error("lalin compiler machine code_to_c validation failed: " .. table.concat(messages, "\n"), 2)
    end
    return result.c_unit
end

return M
