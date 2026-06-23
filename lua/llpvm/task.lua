-- LLPVM task declarations and run records.

local llb = require("llb")
local asdl = require("llpvm.asdl")

local M = {}

local T = asdl.T.LlPvm

local function text(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    if type(v) == "table" then
        if type(v.message) == "string" then return v.message end
        if type(v.code) == "string" then return v.code end
        if type(v.kind) == "string" then return v.kind end
    end
    return tostring(v)
end

function M.event(seq, kind, payload)
    return T.TaskRunEvent(seq or 0, tostring(kind or "event"), text(payload))
end

function M.step(index, phase, machine, status)
    return T.TaskStepRun(index or 0, tostring(phase or ""), tostring(machine or ""), tostring(status or "done"))
end

function M.run(name, status, events, steps)
    return T.TaskRun(T.Symbol(tostring(name or "task")), tostring(status or "done"), events or {}, steps or {})
end

function M.record_handle(name, handle, steps)
    local events = {}
    for ev in handle:events() do
        events[#events + 1] = M.event(ev.seq or #events + 1, ev.kind, ev.message or ev.code or ev)
    end
    return handle:result(), M.run(name, handle:failed() and "failed" or "done", events, steps or {})
end

function M.describe_run(run)
    return {
        task = run.task and run.task.value,
        status = run.status,
        events = #(run.events or {}),
        steps = #(run.steps or {}),
    }
end

function M.from_llb_handle(handle, name)
    local result, run = M.record_handle(name or (handle.task and handle.task.name) or "task", handle)
    return { output = result, run = run }
end

M.T = asdl.T
M.B = asdl.B.LlPvm
M.llb_process = llb.process

return M
