-- LalinPhase compiler-package validation.
--
-- The phase package is the declarative graph that connects named worlds,
-- machines, phases, and roots. This module validates that graph as a first
-- class process so tooling can consume the same event gps as batch callers.

local llb = require("llb")
local pvm = require("lalin.pvm")

local M = {}

local function classof(v) return pvm.classof(v) end

local function class_name(v)
    local cls = classof(v)
    if type(cls) ~= "table" then return nil end
    return tostring(cls):match("^Class%((.+)%)$")
end

local function is_class(v, name)
    return class_name(v) == "LalinPhase." .. name
end

local function id_text(id)
    if type(id) == "table" and type(id.text) == "string" then return id.text end
    if type(id) == "string" then return id end
    return tostring(id)
end

local function maybe_id_text(id)
    if id == nil then return nil end
    return id_text(id)
end

local function same_id(a, b)
    return maybe_id_text(a) == maybe_id_text(b)
end

local function impl_kind(impl)
    local cls = classof(impl)
    if type(cls) ~= "table" then return "unknown" end
    if cls.kind == "ImplLalin" then return "lalin" end
    if cls.kind == "ImplLua" then return "lua" end
    if cls.kind == "ImplC" then return "c" end
    if cls.kind == "ImplExternal" then return "external" end
    return "unknown"
end

local function empty_string(v)
    return type(v) ~= "string" or v == ""
end

local function report_new(package)
    return {
        ok = true,
        package = package,
        diagnostics = {},
        worlds = {},
        machines = {},
        phases = {},
        roots = {},
    }
end

local function add_diagnostic(ctx, report, code, message, subject)
    local d = {
        severity = "error",
        code = code,
        message = message,
        subject = subject,
    }
    report.ok = false
    report.diagnostics[#report.diagnostics + 1] = d
    ctx:diagnostic(d)
    return d
end

local function add_unique(ctx, report, map, list, kind, id, value)
    local name = id_text(id)
    if map[name] ~= nil then
        add_diagnostic(ctx, report, "E_DUPLICATE_" .. kind:upper(), "duplicate " .. kind .. " id '" .. name .. "'", value)
    else
        map[name] = value
        list[#list + 1] = value
    end
    return name
end

local function require_world(ctx, report, worlds, id, owner_kind, owner_name, field)
    local name = id_text(id)
    if worlds[name] == nil then
        add_diagnostic(ctx, report, "E_UNKNOWN_WORLD", owner_kind .. " '" .. owner_name .. "' references unknown " .. field .. " world '" .. name .. "'", id)
        return nil
    end
    return worlds[name]
end

local function require_machine(ctx, report, machines, id, owner_kind, owner_name)
    local name = id_text(id)
    if machines[name] == nil then
        add_diagnostic(ctx, report, "E_UNKNOWN_MACHINE", owner_kind .. " '" .. owner_name .. "' references unknown machine '" .. name .. "'", id)
        return nil
    end
    return machines[name]
end

local function validate_impl(ctx, report, machine)
    local impl = machine.impl
    local kind = impl_kind(impl)
    local name = id_text(machine.id)
    if kind == "unknown" then
        add_diagnostic(ctx, report, "E_BAD_IMPL", "machine '" .. name .. "' has invalid implementation binding", impl)
        return
    end

    if kind == "lalin" or kind == "lua" then
        if empty_string(impl.module_name) then
            add_diagnostic(ctx, report, "E_BAD_IMPL", "machine '" .. name .. "' " .. kind .. " implementation requires module_name", impl)
        end
        if empty_string(impl.function_name) then
            add_diagnostic(ctx, report, "E_BAD_IMPL", "machine '" .. name .. "' " .. kind .. " implementation requires function_name", impl)
        end
    elseif kind == "c" then
        if empty_string(impl.symbol) then
            add_diagnostic(ctx, report, "E_BAD_IMPL", "machine '" .. name .. "' " .. kind .. " implementation requires symbol", impl)
        end
    elseif kind == "external" then
        if empty_string(impl.capability) then
            add_diagnostic(ctx, report, "E_BAD_IMPL", "machine '" .. name .. "' external implementation requires capability", impl)
        end
    end
end

local function validate_package(ctx, package)
    local report = report_new(package)

    ctx:event("validate_start", { package = package and package.id and package.id.text or nil })

    if not is_class(package, "Package") then
        add_diagnostic(ctx, report, "E_BAD_PACKAGE", "phase validation expects LalinPhase.Package", package)
        ctx:event("validate_done", { ok = report.ok, diagnostics = report.diagnostics })
        return report
    end

    local world_map, machine_map, phase_map, root_map = {}, {}, {}, {}

    for i = 1, #package.worlds do
        local world = package.worlds[i]
        if not is_class(world, "World") then
            add_diagnostic(ctx, report, "E_BAD_WORLD", "package world entry " .. i .. " is not LalinPhase.World", world)
        else
            local name = add_unique(ctx, report, world_map, report.worlds, "world", world.id, world)
            ctx:event("world", { id = name, world = world })
        end
    end

    for i = 1, #package.machines do
        local machine = package.machines[i]
        if not is_class(machine, "Machine") then
            add_diagnostic(ctx, report, "E_BAD_MACHINE", "package machine entry " .. i .. " is not LalinPhase.Machine", machine)
        else
            local name = add_unique(ctx, report, machine_map, report.machines, "machine", machine.id, machine)
            ctx:event("machine", { id = name, machine = machine })
        end
    end

    for i = 1, #package.phases do
        local phase = package.phases[i]
        if not is_class(phase, "Phase") then
            add_diagnostic(ctx, report, "E_BAD_PHASE", "package phase entry " .. i .. " is not LalinPhase.Phase", phase)
        else
            local name = add_unique(ctx, report, phase_map, report.phases, "phase", phase.id, phase)
            ctx:event("phase", { id = name, phase = phase })
        end
    end

    for i = 1, #package.roots do
        local root = package.roots[i]
        if not is_class(root, "Root") then
            add_diagnostic(ctx, report, "E_BAD_ROOT", "package root entry " .. i .. " is not LalinPhase.Root", root)
        else
            local name = add_unique(ctx, report, root_map, report.roots, "root", root.id, root)
            ctx:event("root", { id = name, input = id_text(root.input), output = id_text(root.output), root = root })
        end
    end

    for _, machine in ipairs(report.machines) do
        local name = id_text(machine.id)
        require_world(ctx, report, world_map, machine.input, "machine", name, "input")
        require_world(ctx, report, world_map, machine.output, "machine", name, "output")
        if machine.diagnostics ~= nil then
            require_world(ctx, report, world_map, machine.diagnostics, "machine", name, "diagnostic")
        end
        validate_impl(ctx, report, machine)
    end

    for _, phase in ipairs(report.phases) do
        local name = id_text(phase.id)
        require_world(ctx, report, world_map, phase.input, "phase", name, "input")
        require_world(ctx, report, world_map, phase.output, "phase", name, "output")
        if phase.diagnostics ~= nil then
            require_world(ctx, report, world_map, phase.diagnostics, "phase", name, "diagnostic")
        end

        local machine = require_machine(ctx, report, machine_map, phase.machine, "phase", name)
        if machine ~= nil then
            if not same_id(phase.input, machine.input) then
                add_diagnostic(ctx, report, "E_PHASE_MACHINE_INPUT_MISMATCH", "phase '" .. name .. "' input world does not match machine '" .. id_text(machine.id) .. "'", phase)
            end
            if not same_id(phase.output, machine.output) then
                add_diagnostic(ctx, report, "E_PHASE_MACHINE_OUTPUT_MISMATCH", "phase '" .. name .. "' output world does not match machine '" .. id_text(machine.id) .. "'", phase)
            end
            if not same_id(phase.diagnostics, machine.diagnostics) then
                add_diagnostic(ctx, report, "E_PHASE_MACHINE_DIAGNOSTICS_MISMATCH", "phase '" .. name .. "' diagnostic world does not match machine '" .. id_text(machine.id) .. "'", phase)
            end
        end
    end

    for _, root in ipairs(report.roots) do
        local name = id_text(root.id)
        require_world(ctx, report, world_map, root.input, "root", name, "input")
        require_world(ctx, report, world_map, root.output, "root", name, "output")
    end

    ctx:event("validate_done", { ok = report.ok, diagnostics = report.diagnostics })
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

local function phase_validate_process_body(ctx, package)
        return materialized_event_region(ctx, function(event_ctx)
            return validate_package(event_ctx, package)
        end)
end

M.process = llb.process.phase_validate { "package" } (phase_validate_process_body)

function M.validate(package)
    local handle = M.process:start(package)
    for _ in handle:events() do end
    return handle:result()
end

function M.assert_valid(package)
    local report = M.validate(package)
    if not report.ok then
        local messages = {}
        for i = 1, #report.diagnostics do
            local d = report.diagnostics[i]
            messages[#messages + 1] = tostring(d.code) .. ": " .. tostring(d.message)
        end
        error(table.concat(messages, "\n"), 2)
    end
    return package, report
end

return M
