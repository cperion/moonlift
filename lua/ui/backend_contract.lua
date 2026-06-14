local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact

local M = {}

M._VERSION = "ui-backend-contract-1"

local RAW_CLASSES = {
    [Interact.PointerMoved] = true,
    [Interact.PointerPressed] = true,
    [Interact.PointerReleased] = true,
    [Interact.PointerCancelled] = true,
    [Interact.WheelMoved] = true,
    [Interact.KeyPressed] = true,
    [Interact.KeyReleased] = true,
    [Interact.TextInput] = true,
    [Interact.TextEditing] = true,
    [Interact.FocusMove] = true,
    [Interact.FocusLost] = true,
    [Interact.FocusNext] = true,
    [Interact.FocusPrev] = true,
    [Interact.ActivateFocus] = true,
    [Interact.CancelPointer] = true,
}

local INPUT_EVENT_TYPES = {
    mouse_moved = true,
    mouse_pressed = true,
    mouse_released = true,
    mouse_wheel = true,
    key_down = true,
    key_up = true,
    text_input = true,
    text_editing = true,
    focus_lost = true,
}

local function append(dst, value)
    dst[#dst + 1] = value
end

local function copy_array(src)
    local out = {}
    if src ~= nil then
        for i = 1, #src do out[i] = src[i] end
    end
    return out
end

local function path_value(root, path)
    local cur = root
    for part in string.gmatch(path, "[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
        if cur == nil then return nil end
    end
    return cur
end

local function callable(obj, name)
    return type(obj) == "table" and type(obj[name]) == "function"
end

local function has_any_method(obj, names)
    for i = 1, #names do
        if callable(obj, names[i]) then return true, names[i] end
    end
    return false, nil
end

local function require_any_method(obj, names, label, errors)
    local ok, found = has_any_method(obj, names)
    if ok then return found end
    append(errors, label .. " must provide method " .. table.concat(names, " or "))
    return nil
end

local function require_function(obj, name, label, errors)
    if type(obj) == "table" and type(obj[name]) == "function" then return true end
    append(errors, label .. " must provide function " .. name)
    return false
end

local function boolish(v)
    return v == true or type(v) == "string"
end

local function truthy_capability(caps, path)
    local v = path_value(caps, path)
    return v == true or type(v) == "string", v
end

local function add_required_capability_errors(caps, paths, errors)
    for i = 1, #paths do
        local path = paths[i]
        local ok, value = truthy_capability(caps, path)
        if not ok then
            append(errors, "capability " .. path .. " must be declared truthy, got " .. tostring(value))
        end
    end
end

function M.capability(caps, path)
    return path_value(caps, path)
end

function M.has_capability(caps, path)
    return truthy_capability(caps, path)
end

function M.required_sdl3_capabilities()
    return {
        "runtime.boxes",
        "runtime.rounded_boxes",
        "runtime.capsules",
        "runtime.clipping",
        "runtime.transforms",
        "runtime.scrolling",
        "runtime.cursors",
        "paint.line",
        "paint.polyline",
        "paint.polygon_fill",
        "paint.circle_fill",
        "paint.arc",
        "paint.bezier",
        "paint.mesh",
        "paint.image",
        "paint.stroke_width",
        "text.measure",
        "text.draw",
        "text.hit_test",
        "text.ranges",
        "text.ime",
        "text.clipboard",
        "host.windows",
        "host.events",
        "host.text_input_rect",
        "host.clipboard",
        "host.timers",
    }
end

function M.capabilities_template()
    return {
        runtime = {
            boxes = false,
            rounded_boxes = false,
            capsules = false,
            clipping = false,
            transforms = false,
            scrolling = false,
            layers = false,
            cursors = false,
            density = false,
        },
        paint = {
            line = false,
            polyline = false,
            polygon_fill = false,
            circle_fill = false,
            arc = false,
            bezier = false,
            mesh = false,
            image = false,
            stroke_width = false,
        },
        text = {
            measure = false,
            draw = false,
            hit_test = false,
            ranges = false,
            ime = false,
            clipboard = false,
            shaping = false,
        },
        host = {
            windows = false,
            multi_window = false,
            events = false,
            text_input_rect = false,
            clipboard = false,
            timers = false,
            hidpi = false,
        },
    }
end

function M.validate_capabilities(caps, opts)
    opts = opts or {}
    local errors = {}
    local warnings = {}

    if caps == nil then
        if opts.require_capabilities then
            append(errors, "capabilities table is required")
        else
            append(warnings, "capabilities table is missing")
        end
        return #errors == 0, errors, warnings
    end

    if type(caps) ~= "table" then
        append(errors, "capabilities must be a table")
        return false, errors, warnings
    end

    for _, section in ipairs({ "runtime", "paint", "text", "host" }) do
        if caps[section] ~= nil and type(caps[section]) ~= "table" then
            append(errors, "capabilities." .. section .. " must be a table when present")
        elseif caps[section] == nil then
            append(warnings, "capabilities." .. section .. " is missing")
        end
    end

    local required = opts.required_capabilities
    if required == "sdl3" then required = M.required_sdl3_capabilities() end
    if type(required) == "table" then
        add_required_capability_errors(caps, required, errors)
    end

    return #errors == 0, errors, warnings
end

function M.assert_capabilities(caps, opts)
    local ok, errors = M.validate_capabilities(caps, opts)
    if not ok then error("ui.backend_contract capabilities failed: " .. table.concat(errors, "; "), 2) end
    return true
end

function M.is_raw(value)
    local cls = pvm.classof(value)
    return RAW_CLASSES[cls] == true
end

function M.validate_runtime_driver(driver, opts)
    opts = opts or {}
    local errors = {}
    local report = { methods = {}, capabilities = type(driver) == "table" and driver.capabilities or nil }

    if type(driver) ~= "table" then
        append(errors, "runtime driver must be a table")
        return false, errors, report
    end

    report.methods.draw_box = require_any_method(driver, { "draw_box", "draw_rect" }, "runtime driver", errors)
    report.methods.draw_text = require_any_method(driver, { "draw_text" }, "runtime driver", errors)
    report.methods.draw_paint = require_any_method(driver, { "draw_paint" }, "runtime driver", errors)
    report.methods.push_clip_rect = require_any_method(driver, { "push_clip_rect", "push_clip" }, "runtime driver", errors)
    report.methods.pop_clip_rect = require_any_method(driver, { "pop_clip_rect", "pop_clip" }, "runtime driver", errors)

    local cursor_method = select(2, has_any_method(driver, { "set_cursor_kind", "set_cursor" }))
    report.methods.cursor = cursor_method
    if opts.require_cursor and cursor_method == nil then
        append(errors, "runtime driver must provide set_cursor_kind or set_cursor")
    end

    local layer_method = select(2, has_any_method(driver, { "push_layer" }))
    local pop_layer_method = select(2, has_any_method(driver, { "pop_layer" }))
    report.methods.push_layer = layer_method
    report.methods.pop_layer = pop_layer_method
    if opts.require_native_layers and (layer_method == nil or pop_layer_method == nil) then
        append(errors, "runtime driver native layers require push_layer and pop_layer")
    end

    if opts.require_capabilities then
        local ok, cap_errors = M.validate_capabilities(report.capabilities, {
            require_capabilities = true,
            required_capabilities = opts.required_capabilities,
        })
        if not ok then
            for i = 1, #cap_errors do append(errors, "runtime driver " .. cap_errors[i]) end
        end
    end

    return #errors == 0, errors, report
end

function M.assert_runtime_driver(driver, opts)
    local ok, errors, report = M.validate_runtime_driver(driver, opts)
    if not ok then error("ui.backend_contract runtime driver failed: " .. table.concat(errors, "; "), 2) end
    return report
end

function M.validate_runtime_module(runtime_module, opts)
    opts = opts or {}
    local errors = {}
    local report = { capabilities = type(runtime_module) == "table" and runtime_module.capabilities or nil }

    if type(runtime_module) ~= "table" then
        append(errors, "runtime module must be a table")
        return false, errors, report
    end

    require_function(runtime_module, "new", "runtime module", errors)
    if opts.require_capabilities or runtime_module.capabilities ~= nil then
        local ok, cap_errors = M.validate_capabilities(runtime_module.capabilities, {
            require_capabilities = opts.require_capabilities,
            required_capabilities = opts.required_capabilities,
        })
        if not ok then
            for i = 1, #cap_errors do append(errors, "runtime module " .. cap_errors[i]) end
        end
    end

    return #errors == 0, errors, report
end

function M.assert_runtime_module(runtime_module, opts)
    local ok, errors, report = M.validate_runtime_module(runtime_module, opts)
    if not ok then error("ui.backend_contract runtime module failed: " .. table.concat(errors, "; "), 2) end
    return report
end

function M.validate_text_system(system, opts)
    opts = opts or {}
    local errors = {}
    local report = { methods = {}, capabilities = type(system) == "table" and system.capabilities or nil }

    if type(system) ~= "table" then
        append(errors, "text system must be a table")
        return false, errors, report
    end

    report.methods.measure = require_any_method(system, { "measure" }, "text system", errors)
    report.methods.hit_test = require_any_method(system, { "hit_test" }, "text system", errors)
    report.methods.range_query = require_any_method(system, { "range_query" }, "text system", errors)
    report.methods.close = select(2, has_any_method(system, { "close" }))

    if opts.require_close and report.methods.close == nil then
        append(errors, "text system must provide close")
    end

    return #errors == 0, errors, report
end

function M.assert_text_system(system, opts)
    local ok, errors, report = M.validate_text_system(system, opts)
    if not ok then error("ui.backend_contract text system failed: " .. table.concat(errors, "; "), 2) end
    return report
end

function M.validate_text_module(text_module, opts)
    opts = opts or {}
    local errors = {}
    local report = { capabilities = type(text_module) == "table" and text_module.capabilities or nil }

    if type(text_module) ~= "table" then
        append(errors, "text module must be a table")
        return false, errors, report
    end

    require_function(text_module, "new", "text module", errors)
    if opts.require_capabilities or text_module.capabilities ~= nil then
        local ok, cap_errors = M.validate_capabilities(text_module.capabilities, {
            require_capabilities = opts.require_capabilities,
            required_capabilities = opts.required_capabilities,
        })
        if not ok then
            for i = 1, #cap_errors do append(errors, "text module " .. cap_errors[i]) end
        end
    end

    return #errors == 0, errors, report
end

function M.assert_text_module(text_module, opts)
    local ok, errors, report = M.validate_text_module(text_module, opts)
    if not ok then error("ui.backend_contract text module failed: " .. table.concat(errors, "; "), 2) end
    return report
end

function M.validate_host_object(host, opts)
    opts = opts or {}
    local errors = {}
    local report = { methods = {}, capabilities = type(host) == "table" and host.capabilities or nil }

    if type(host) ~= "table" then
        append(errors, "host object must be a table")
        return false, errors, report
    end

    for _, name in ipairs({ "begin_frame", "present", "close", "now_ms", "size" }) do
        if require_function(host, name, "host object", errors) then report.methods[name] = name end
    end

    for _, name in ipairs({ "pixel_size", "set_clipboard_text", "get_clipboard_text", "set_text_input", "set_text_input_rect", "new_runtime_driver", "poll_events", "filter_events" }) do
        if callable(host, name) then report.methods[name] = name end
    end

    if opts.require_clipboard and (not callable(host, "set_clipboard_text") or not callable(host, "get_clipboard_text")) then
        append(errors, "host object clipboard requires set_clipboard_text and get_clipboard_text")
    end
    if opts.require_text_input_rect and not callable(host, "set_text_input_rect") then
        append(errors, "host object must provide set_text_input_rect")
    end
    if opts.require_density and not callable(host, "pixel_size") then
        append(errors, "host object density/HiDPI checks require pixel_size")
    end

    return #errors == 0, errors, report
end

function M.assert_host_object(host, opts)
    local ok, errors, report = M.validate_host_object(host, opts)
    if not ok then error("ui.backend_contract host object failed: " .. table.concat(errors, "; "), 2) end
    return report
end

function M.validate_host_module(host_module, opts)
    opts = opts or {}
    local errors = {}
    local report = { capabilities = type(host_module) == "table" and host_module.capabilities or nil }

    if type(host_module) ~= "table" then
        append(errors, "host module must be a table")
        return false, errors, report
    end

    for _, name in ipairs({ "new", "poll_events", "filter_events", "partition_events" }) do
        require_function(host_module, name, "host module", errors)
    end

    return #errors == 0, errors, report
end

function M.assert_host_module(host_module, opts)
    local ok, errors, report = M.validate_host_module(host_module, opts)
    if not ok then error("ui.backend_contract host module failed: " .. table.concat(errors, "; "), 2) end
    return report
end

function M.validate_host_event(ev, opts)
    opts = opts or {}
    local errors = {}

    if type(ev) ~= "table" then
        return false, { "host event must be a table" }
    end
    if type(ev.type) ~= "string" then
        append(errors, "host event must have string type")
    end

    if INPUT_EVENT_TYPES[ev.type] and opts.require_raw ~= false then
        local has_raw = ev.raw ~= nil and M.is_raw(ev.raw)
        local has_raws = false
        if type(ev.raws) == "table" then
            has_raws = #ev.raws > 0
            for i = 1, #ev.raws do
                if not M.is_raw(ev.raws[i]) then
                    append(errors, "host event raws[" .. i .. "] is not an Interact.Raw value")
                end
            end
        end
        if not has_raw and not has_raws then
            append(errors, "input host event " .. tostring(ev.type) .. " must expose typed raw or raws")
        end
    end

    return #errors == 0, errors
end

function M.assert_host_event(ev, opts)
    local ok, errors = M.validate_host_event(ev, opts)
    if not ok then error("ui.backend_contract host event failed: " .. table.concat(errors, "; "), 2) end
    return true
end

function M.validate_event_batch(events, opts)
    local errors = {}
    if type(events) ~= "table" then
        return false, { "event batch must be a table" }
    end
    for i = 1, #events do
        local ok, ev_errors = M.validate_host_event(events[i], opts)
        if not ok then
            for j = 1, #ev_errors do
                append(errors, "events[" .. i .. "]: " .. ev_errors[j])
            end
        end
    end
    return #errors == 0, errors
end

function M.validate_backend_package(backend, opts)
    opts = opts or {}
    local errors = {}
    local warnings = {}
    local report = {}

    if type(backend) ~= "table" then
        return false, { "backend package must be a table" }, warnings, report
    end

    if type(backend.name) ~= "string" then append(errors, "backend package must have string name") end
    if backend.host == nil then append(errors, "backend package must expose host module") end
    if backend.runtime == nil then append(errors, "backend package must expose runtime module") end
    if backend.text == nil then append(errors, "backend package must expose text module") end

    for _, name in ipairs({ "new_host", "poll_events", "filter_events", "partition_events", "new_text_system" }) do
        require_function(backend, name, "backend package", errors)
    end

    if backend.host ~= nil then
        local ok, sub_errors, sub_report = M.validate_host_module(backend.host, opts.host or {})
        report.host = sub_report
        if not ok then for i = 1, #sub_errors do append(errors, "host: " .. sub_errors[i]) end end
    end
    if backend.runtime ~= nil then
        local ok, sub_errors, sub_report = M.validate_runtime_module(backend.runtime, opts.runtime or {})
        report.runtime = sub_report
        if not ok then for i = 1, #sub_errors do append(errors, "runtime: " .. sub_errors[i]) end end
    end
    if backend.text ~= nil then
        local ok, sub_errors, sub_report = M.validate_text_module(backend.text, opts.text or {})
        report.text = sub_report
        if not ok then for i = 1, #sub_errors do append(errors, "text: " .. sub_errors[i]) end end
    end

    local cap_opts = {
        require_capabilities = opts.require_capabilities,
        required_capabilities = opts.required_capabilities,
    }
    if opts.required_capabilities == nil and opts.product == "sdl3" then
        cap_opts.required_capabilities = "sdl3"
    end
    if backend.capabilities ~= nil or opts.require_capabilities or cap_opts.required_capabilities ~= nil then
        local ok, cap_errors, cap_warnings = M.validate_capabilities(backend.capabilities, cap_opts)
        if not ok then for i = 1, #cap_errors do append(errors, cap_errors[i]) end end
        for i = 1, #cap_warnings do append(warnings, cap_warnings[i]) end
        report.capabilities = backend.capabilities
    end

    return #errors == 0, errors, warnings, report
end

function M.assert_backend_package(backend, opts)
    local ok, errors, warnings, report = M.validate_backend_package(backend, opts)
    if not ok then error("ui.backend_contract backend package failed: " .. table.concat(errors, "; "), 2) end
    return report, warnings
end

function M.new_trace_driver(opts)
    opts = opts or {}
    local calls = {}
    local self = { calls = calls, capabilities = opts.capabilities or M.capabilities_template() }

    local function record(name, ...)
        calls[#calls + 1] = { name = name, args = { ... } }
    end

    function self:draw_box(...) record("draw_box", ...) end
    function self:draw_rect(...) record("draw_rect", ...) end
    function self:draw_text(...) record("draw_text", ...) end
    function self:draw_paint(...) record("draw_paint", ...) end
    function self:push_clip_rect(...) record("push_clip_rect", ...) end
    function self:pop_clip_rect(...) record("pop_clip_rect", ...) end
    function self:push_clip(...) record("push_clip", ...) end
    function self:pop_clip(...) record("pop_clip", ...) end
    function self:set_cursor_kind(...) record("set_cursor_kind", ...) end
    function self:set_cursor(...) record("set_cursor", ...) end
    function self:push_layer(...) record("push_layer", ...) end
    function self:pop_layer(...) record("pop_layer", ...) end
    function self:reset() record("reset") end
    function self:close() record("close") end

    return self
end

function M.validate_trace_balance(calls)
    local errors = {}
    local clip_depth = 0
    local layer_depth = 0
    calls = calls or {}

    for i = 1, #calls do
        local name = calls[i].name
        if name == "push_clip" or name == "push_clip_rect" then
            clip_depth = clip_depth + 1
        elseif name == "pop_clip" or name == "pop_clip_rect" then
            clip_depth = clip_depth - 1
            if clip_depth < 0 then append(errors, "clip pop underflow at call " .. i); clip_depth = 0 end
        elseif name == "push_layer" then
            layer_depth = layer_depth + 1
        elseif name == "pop_layer" then
            layer_depth = layer_depth - 1
            if layer_depth < 0 then append(errors, "layer pop underflow at call " .. i); layer_depth = 0 end
        end
    end

    if clip_depth ~= 0 then append(errors, "clip stack is unbalanced by " .. clip_depth) end
    if layer_depth ~= 0 then append(errors, "layer stack is unbalanced by " .. layer_depth) end
    return #errors == 0, errors
end

function M.assert_trace_balance(calls)
    local ok, errors = M.validate_trace_balance(calls)
    if not ok then error("ui.backend_contract trace failed: " .. table.concat(errors, "; "), 2) end
    return true
end

function M.density_report(host)
    if type(host) ~= "table" or type(host.size) ~= "function" then
        return { supported = false, reason = "host has no size()" }
    end
    local logical_w, logical_h = host:size()
    local pixel_w, pixel_h = logical_w, logical_h
    local supported = false
    if type(host.pixel_size) == "function" then
        pixel_w, pixel_h = host:pixel_size()
        supported = true
    end
    local sx = logical_w and logical_w ~= 0 and pixel_w / logical_w or 1
    local sy = logical_h and logical_h ~= 0 and pixel_h / logical_h or 1
    return {
        supported = supported,
        logical_w = logical_w,
        logical_h = logical_h,
        pixel_w = pixel_w,
        pixel_h = pixel_h,
        scale_x = sx,
        scale_y = sy,
    }
end

function M.describe_errors(errors)
    return table.concat(copy_array(errors), "\n")
end

return M
