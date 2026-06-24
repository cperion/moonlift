-- MoonPhase execution planning.
--
-- A package declares a graph of reusable phase capabilities. A root declares a
-- named requested transformation from one world to another. The planner selects
-- exactly one simple path through the phase graph and expands it into machine
-- call steps.

local llb = require("llb")
local pvm = require("moonlift.pvm")
local PhaseModel = require("moonlift.phase_model")
local PhaseValidate = require("moonlift.phase_validate")

local M = {}

local function id_text(id)
    if type(id) == "table" and type(id.text) == "string" then return id.text end
    if type(id) == "string" then return id end
    return tostring(id)
end

local function maybe_id_text(id)
    if id == nil then return nil end
    return id_text(id)
end

local function phase_namespace(package)
    local cls = pvm.classof(package)
    local ctx = cls and rawget(cls, "__context")
    if ctx and ctx.MoonPhase and ctx.MoonPhase.Plan then return ctx.MoonPhase end
    local T = pvm.context()
    PhaseModel(T)
    return T.MoonPhase
end

local function report_new(package)
    return { ok = true, package = package, root = nil, input = nil, output = nil, steps = {}, diagnostics = {} }
end

local function add_diagnostic(ctx, report, code, message, subject)
    local d = { severity = "error", code = code, message = message, subject = subject }
    report.ok = false
    report.diagnostics[#report.diagnostics + 1] = d
    ctx:diagnostic(d)
    return d
end

local function copy_validation_diagnostics(ctx, report, validation)
    for i = 1, #validation.diagnostics do
        local d = validation.diagnostics[i]
        add_diagnostic(ctx, report, d.code, d.message, d.subject)
    end
end

local function build_maps(package)
    local machines, phases_by_input = {}, {}
    for i = 1, #package.machines do
        local machine = package.machines[i]
        machines[id_text(machine.id)] = machine
    end
    for i = 1, #package.phases do
        local phase = package.phases[i]
        local input = id_text(phase.input)
        phases_by_input[input] = phases_by_input[input] or {}
        phases_by_input[input][#phases_by_input[input] + 1] = phase
    end
    return machines, phases_by_input
end

local function root_matches(root, spec)
    if spec == nil then return true end
    if type(spec) == "string" then return id_text(root.id) == spec end
    if type(spec) == "table" and spec.id ~= nil then return id_text(root.id) == id_text(spec.id) end
    if type(spec) == "table" and spec.text ~= nil then return id_text(root.id) == id_text(spec) end
    return root == spec
end

local function select_root(ctx, report, package, root_spec)
    local matches = {}
    for i = 1, #package.roots do
        local root = package.roots[i]
        if root_matches(root, root_spec) then matches[#matches + 1] = root end
    end
    if #matches == 1 then return matches[1] end
    if #matches == 0 then
        add_diagnostic(ctx, report, root_spec == nil and "E_NO_ROOT" or "E_UNKNOWN_ROOT", root_spec == nil and "package has no root" or "package has no root matching requested root", root_spec or package)
        return nil
    end
    add_diagnostic(ctx, report, "E_AMBIGUOUS_ROOT", "requested root matches multiple roots", root_spec or package)
    return nil
end

local function find_paths(phases_by_input, input, output)
    local paths = {}
    local function dfs(world, path, seen_phase)
        if world == output then
            local copy = {}
            for i = 1, #path do copy[i] = path[i] end
            paths[#paths + 1] = copy
            return
        end
        local candidates = phases_by_input[world] or {}
        for i = 1, #candidates do
            local phase = candidates[i]
            local pid = id_text(phase.id)
            if not seen_phase[pid] then
                seen_phase[pid] = true
                path[#path + 1] = phase
                dfs(id_text(phase.output), path, seen_phase)
                path[#path] = nil
                seen_phase[pid] = nil
            end
        end
    end
    dfs(input, {}, {})
    return paths
end

local function step_record(index, phase, machine)
    return {
        index = index,
        phase = phase,
        machine = machine,
        phase_id = id_text(phase.id),
        machine_id = id_text(machine.id),
        input = id_text(phase.input),
        output = id_text(phase.output),
        diagnostics = maybe_id_text(phase.diagnostics),
        cache = phase.cache,
        deterministic = phase.deterministic,
        abi = machine.abi,
        impl = machine.impl,
        capabilities = machine.capabilities,
    }
end

local function step_node(P, index, phase, machine)
    return P.PlanStep(
        index,
        phase.id,
        machine.id,
        phase.input,
        phase.output,
        phase.diagnostics,
        phase.cache,
        phase.deterministic,
        machine.abi,
        machine.impl,
        machine.capabilities
    )
end

local function path_names(path)
    local out = {}
    for i = 1, #path do out[#out + 1] = id_text(path[i].id) end
    return table.concat(out, " -> ")
end

local function plan_package(ctx, package, root_spec)
    local report = report_new(package)
    ctx:event("plan_start", { package = package and package.id and package.id.text or nil })

    local validation = PhaseValidate.validate(package)
    if not validation.ok then
        copy_validation_diagnostics(ctx, report, validation)
        ctx:event("plan_done", { ok = report.ok, diagnostics = report.diagnostics, steps = report.steps })
        return report
    end

    local machines, phases_by_input = build_maps(package)
    local root = select_root(ctx, report, package, root_spec)
    if root == nil then
        ctx:event("plan_done", { ok = report.ok, diagnostics = report.diagnostics, steps = report.steps })
        return report
    end

    report.root = root
    report.input = id_text(root.input)
    report.output = id_text(root.output)
    ctx:event("root", { id = id_text(root.id), input = report.input, output = report.output, root = root })

    local paths = find_paths(phases_by_input, report.input, report.output)
    if #paths == 0 then
        add_diagnostic(ctx, report, "E_NO_PHASE_PATH", "root '" .. id_text(root.id) .. "' has no phase path from '" .. report.input .. "' to '" .. report.output .. "'", root)
    elseif #paths > 1 then
        local names = {}
        for i = 1, #paths do names[#names + 1] = path_names(paths[i]) end
        add_diagnostic(ctx, report, "E_AMBIGUOUS_PHASE_PATH", "root '" .. id_text(root.id) .. "' has multiple phase paths: " .. table.concat(names, " | "), root)
    else
        local P = phase_namespace(package)
        local steps = {}
        local path = paths[1]
        for i = 1, #path do
            local phase = path[i]
            local machine = machines[id_text(phase.machine)]
            steps[#steps + 1] = step_node(P, i, phase, machine)
            local step = step_record(i, phase, machine)
            report.steps[#report.steps + 1] = step
            ctx:event("step", step)
        end
        report.plan = P.Plan(root.id, root.input, root.output, steps)
    end

    ctx:event("plan_done", { ok = report.ok, diagnostics = report.diagnostics, steps = report.steps, plan = report.plan, input = report.input, output = report.output })
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

local function materialized_event_stream(ctx, fn)
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

M.process = llb.process.phase_plan {
    stream = function(ctx, package, root_spec)
        return materialized_event_stream(ctx, function(event_ctx)
            return plan_package(event_ctx, package, root_spec)
        end)
    end,
}

function M.plan(package, root_spec)
    local handle = M.process:start(package, root_spec)
    for _ in handle:events() do end
    return handle:result()
end

function M.assert_plan(package, root_spec)
    local report = M.plan(package, root_spec)
    if not report.ok then
        local messages = {}
        for i = 1, #report.diagnostics do
            local d = report.diagnostics[i]
            messages[#messages + 1] = tostring(d.code) .. ": " .. tostring(d.message)
        end
        error(table.concat(messages, "\n"), 2)
    end
    return report
end

function M.plan_all(package)
    local out = {}
    for i = 1, #package.roots do out[#out + 1] = M.plan(package, package.roots[i]) end
    return out
end

return M
