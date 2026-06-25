-- LalinPhase plan execution shell.
--
-- This is the runtime boundary for planned compiler packages. The executor is
-- deliberately explicit: Lua/Lalin/C/external implementations all
-- resolve through a registry key, with Lua/Lalin allowed to fall back to
-- require(module)[function] for hosted compiler code.

local llb = require("llb")
local pvm = require("lalin.pvm")
local LlTask = require("llpvm.task")

local M = {}

local Executor = {}
Executor.__index = Executor

local function id_text(id)
    if type(id) == "table" and type(id.text) == "string" then return id.text end
    if type(id) == "string" then return id end
    return tostring(id)
end

local function class_kind(v)
    local cls = pvm.classof(v)
    return type(cls) == "table" and cls.kind or nil
end

local function impl_key(impl)
    local kind = class_kind(impl)
    if kind == "ImplLua" then return "lua", impl.module_name .. ":" .. impl.function_name end
    if kind == "ImplLalin" then return "lalin", impl.module_name .. ":" .. impl.function_name end
    if kind == "ImplC" then return "c", impl.symbol end
    if kind == "ImplExternal" then return "external", impl.capability end
    return "unknown", tostring(impl)
end

local function call_result(a, b)
    if type(a) == "table" and rawget(a, "output") ~= nil then return a.output, a.diagnostics end
    return a, b
end

function M.registry(opts)
    return setmetatable({ bindings = {}, opts = opts or {} }, Executor)
end

function Executor:register(kind, key, fn)
    if type(fn) ~= "function" then error("phase_execute: binding must be a function", 2) end
    self.bindings[tostring(kind) .. ":" .. tostring(key)] = fn
    return self
end

function Executor:register_lua(module_name, function_name, fn)
    return self:register("lua", tostring(module_name) .. ":" .. tostring(function_name), fn)
end

function Executor:register_lalin(module_name, function_name, fn)
    return self:register("lalin", tostring(module_name) .. ":" .. tostring(function_name), fn)
end

function Executor:register_c(symbol, fn)
    return self:register("c", symbol, fn)
end

function Executor:register_external(capability, fn)
    return self:register("external", capability, fn)
end

function Executor:resolve(impl)
    local kind, key = impl_key(impl)
    local registered = self.bindings[kind .. ":" .. key]
    if registered then return registered, kind, key end

    if kind == "lua" or kind == "lalin" then
        local module_name, function_name = key:match("^(.*):([^:]*)$")
        local ok, module = pcall(require, module_name)
        if ok then
            local fn = module[function_name]
            if type(fn) == "function" then return fn, kind, key end
            if type(module) == "function" and (function_name == "call" or function_name == "run") then return module, kind, key end
        end
    end

    return nil, kind, key
end

local function execute_plan(ctx, executor, plan, input, opts)
    opts = opts or {}
    executor = executor or M.registry()
    local report = {
        ok = true,
        plan = plan,
        input = input,
        output = nil,
        diagnostics = {},
        steps = {},
        run = nil,
    }
    local run_events = {}
    local run_steps = {}

    local function emit(kind, payload)
        run_events[#run_events + 1] = LlTask.event(#run_events + 1, kind, payload)
        return ctx:event(kind, payload)
    end

    emit("execute_start", { plan = plan, root = plan and plan.root and id_text(plan.root) or nil })

    local current = input
    for i = 1, #(plan.steps or {}) do
        local step = plan.steps[i]
        local phase_name = id_text(step.phase)
        local fn, kind, key = executor:resolve(step.impl)
        emit("step_start", { index = i, phase = phase_name, machine = id_text(step.machine), impl_kind = kind, impl_key = key, input = current, step = step })
        if not fn then
            local d = { severity = "error", code = "E_MACHINE_UNBOUND", message = "no binding for " .. tostring(kind) .. " implementation '" .. tostring(key) .. "'", step = step }
            report.ok = false
            report.diagnostics[#report.diagnostics + 1] = d
            run_steps[#run_steps + 1] = LlTask.step(i, phase_name, id_text(step.machine), "failed")
            ctx:diagnostic(d)
            break
        end
        local ok, a, b = pcall(fn, current, step, { executor = executor, plan = plan, opts = opts })
        if not ok then
            local d = { severity = "error", code = "E_MACHINE_FAILED", message = tostring(a), step = step }
            report.ok = false
            report.diagnostics[#report.diagnostics + 1] = d
            run_steps[#run_steps + 1] = LlTask.step(i, phase_name, id_text(step.machine), "failed")
            ctx:diagnostic(d)
            break
        end
        local output, diagnostics = call_result(a, b)
        if diagnostics then report.diagnostics[#report.diagnostics + 1] = diagnostics end
        local step_report = { step = step, input = current, output = output }
        current = output
        report.steps[#report.steps + 1] = step_report
        run_steps[#run_steps + 1] = LlTask.step(i, phase_name, id_text(step.machine), "done")
        emit("step_done", { index = i, phase = phase_name, output = output, diagnostics = diagnostics, step = step })
    end

    report.output = current
    emit("execute_done", { ok = report.ok, output = report.output, diagnostics = report.diagnostics })
    report.run = LlTask.run(plan and plan.root and id_text(plan.root) or "phase_execute", report.ok and "done" or "failed", run_events, run_steps)
    return report
end

local function collecting_context(ctx, events)
    return setmetatable({}, {
        __index = function(_, key)
            if key == "event" then
                return function(_, kind, payload)
                    local ev = ctx:make_event(kind, payload)
                    events[#events + 1] = ev
                    return ev
                end
            end
            if key == "diagnostic" then
                return function(_, spec)
                    local ev = ctx:diagnostic_event(spec)
                    events[#events + 1] = ev
                    return ev
                end
            end
            return function(_, payload)
                local ev = ctx:make_event(key, payload)
                events[#events + 1] = ev
                return ev
            end
        end,
    })
end

local function materialized_event_region(ctx, fn)
    local function gen(param, state)
        if state == nil then
            local events = {}
            local report = param.fn(collecting_context(param.ctx, events))
            events[#events + 1] = param.ctx:make_event("result", { result = report })
            state = { events = events, index = 1 }
        end
        local ev = state.events[state.index]
        if ev == nil then return nil end
        state.index = state.index + 1
        return state, ev
    end
    return gen, { ctx = ctx, fn = fn }, nil
end

local function phase_execute_process_body(ctx, executor, plan, input, opts)
        return materialized_event_region(ctx, function(event_ctx)
            return execute_plan(event_ctx, executor, plan, input, opts)
        end)
end

M.process = llb.process.phase_execute { "executor", "plan", "input", "opts" } (phase_execute_process_body)

function Executor:run(plan, input, opts)
    local handle = M.process:start(self, plan, input, opts)
    for _ in handle:events() do end
    return handle:result()
end

function Executor:process(plan, input, opts)
    return M.process:start(self, plan, input, opts)
end

function M.execute(plan, input, executor, opts)
    return (executor or M.registry()):run(plan, input, opts)
end

return M
