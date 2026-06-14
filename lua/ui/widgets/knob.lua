local b = require("ui.build")
local tw = require("ui.tw")
local paint = require("ui.paint")
local widget = require("ui.widget")
local ids = require("ui.id")
local state_bridge = require("ui.state")
local slider = require("ui.widgets.slider")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T

local M = {}

local DEFAULTS = {
    kind = "knob",
    role = "knob",
    size = 64,
    min = 0,
    max = 1,
    step = nil,
    start_angle = math.rad(135),
    end_angle = math.rad(405),
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.items_center,
        tw.gap_y_1,
        tw.cursor_grab,
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
        tw.active { tw.cursor_grabbing },
    },
    label_styles = tw.list { tw.text_xs, tw.font_medium, tw.fg.slate[300] },
    value_styles = tw.list { tw.text_xs, tw.fg.slate[400] },
    paint_styles = nil,
    track_rgba8 = 0x334155ff,
    arc_rgba8 = 0x38bdf8ff,
    fill_rgba8 = 0x0f172aff,
    border_rgba8 = 0x64748bff,
    tick_rgba8 = 0xf8fafcff,
}

local function copy_table(src)
    local out = {}
    if src ~= nil then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end

local function add_style(items, value)
    if value ~= nil and value ~= false then items[#items + 1] = value end
end

local function bool_map_opts(id, opts)
    opts = opts or {}
    local key = id_key(id)
    local out = copy_table(opts)
    if type(out.selected) == "boolean" then out.selected = { [key] = out.selected } end
    if type(out.disabled) == "boolean" then out.disabled = { [key] = out.disabled } end
    if type(out.active) == "boolean" then out.active = { [key] = out.active } end
    return out
end

local function state_for(id, opts)
    opts = opts or {}
    local explicit = opts.state
    if opts.model == nil and opts.interact_model == nil and opts.report == nil
        and opts.selected == nil and opts.selected_ids == nil
        and opts.disabled == nil and opts.disabled_ids == nil
        and opts.active == nil and opts.active_ids == nil then
        return explicit
    end
    local derived = state_bridge.for_id(id, opts.model or opts.interact_model, opts.report, bool_map_opts(id, opts))
    if explicit ~= nil then return state_bridge.merge(derived, explicit) end
    return derived
end

local function fmt_value(value, opts)
    if opts.format_value ~= nil then return opts.format_value(value, opts) end
    local precision = opts.precision
    if precision == nil then precision = (opts.step ~= nil and opts.step < 1) and 2 or 0 end
    return string.format("%." .. tostring(precision) .. "f", value)
end

local function knob_program(value, opts)
    local size = opts.size or DEFAULTS.size
    local cx = size / 2
    local cy = size / 2
    local r = math.max(4, (size / 2) - 5)
    local start_angle = opts.start_angle or DEFAULTS.start_angle
    local end_angle = opts.end_angle or DEFAULTS.end_angle
    local t = slider.normalized(value, opts)
    local angle = start_angle + (end_angle - start_angle) * t
    local tick_r1 = r * 0.45
    local tick_r2 = r * 0.82
    local tx1 = cx + math.cos(angle) * tick_r1
    local ty1 = cy + math.sin(angle) * tick_r1
    local tx2 = cx + math.cos(angle) * tick_r2
    local ty2 = cy + math.sin(angle) * tick_r2

    return paint.list {
        paint.circle(cx, cy, r, paint.fill(opts.fill_rgba8 or DEFAULTS.fill_rgba8), paint.stroke(opts.border_rgba8 or DEFAULTS.border_rgba8, 2)),
        paint.arc(cx, cy, r - 2, start_angle, end_angle, 48, paint.stroke(opts.track_rgba8 or DEFAULTS.track_rgba8, 4)),
        paint.arc(cx, cy, r - 2, start_angle, angle, 32, paint.stroke(opts.arc_rgba8 or DEFAULTS.arc_rgba8, 4)),
        paint.line(tx1, ty1, tx2, ty2, paint.stroke(opts.tick_rgba8 or DEFAULTS.tick_rgba8, 3)),
    }
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "knob id")
    local value = slider.clamp(opts.value, opts)
    local size = opts.size or DEFAULTS.size

    local items = { b.id(id_key(id) .. ":box") }
    add_style(items, DEFAULTS.styles)
    add_style(items, opts.styles)

    if opts.label ~= nil and opts.label ~= false then
        items[#items + 1] = b.text { b.id(id_key(id) .. ":label"), DEFAULTS.label_styles, opts.label_styles, tostring(opts.label) }
    end

    local paint_items = { b.id(id_key(id) .. ":paint"), tw.w_px(size), tw.h_px(size) }
    add_style(paint_items, DEFAULTS.paint_styles)
    add_style(paint_items, opts.paint_styles)
    paint_items[#paint_items + 1] = knob_program(value, opts)
    items[#items + 1] = b.drag_source(child_id(id, "drag"), b.paint(paint_items))

    if opts.show_value == true then
        items[#items + 1] = b.text { b.id(id_key(id) .. ":value"), DEFAULTS.value_styles, opts.value_styles, fmt_value(value, opts) }
    end

    local child = b.box(items)
    local state = state_for(id, opts)
    if state ~= nil and not state_bridge.is_empty(state) then child = b.with_state(state, child) end

    local role = opts.disabled and T.Interact.Passive or T.Interact.ActivateTarget
    local node = b.with_input(id, role, child)
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "knob id")
    local surfaces = {}
    local common = {
        widget_id = id,
        role = opts.role or DEFAULTS.role,
        label = opts.label,
        min = opts.min or DEFAULTS.min,
        max = opts.max or DEFAULTS.max,
        step = opts.step,
        orientation = "vertical",
    }
    widget.add_surface(surfaces, "activate", id, copy_table(common))
    widget.add_surface(surfaces, "focus", id, copy_table(common))
    widget.add_surface(surfaces, "input", id, copy_table(common))
    widget.add_surface(surfaces, "drag", child_id(id, "drag"), copy_table(common))
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle)
    return slider.route_one(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "knob id")
    local value = slider.clamp(opts.value, opts)
    local bundle = widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        selected = opts.selected,
        value = value,
        min = opts.min or DEFAULTS.min,
        max = opts.max or DEFAULTS.max,
        step = opts.step,
        orientation = "vertical",
        report = opts.report,
        focused = opts.focused,
        throttle_ms = opts.throttle_ms or 16,
        redraw = opts.redraw or "on_change",
        style_slots = {
            root = opts.styles or DEFAULTS.styles,
            label = opts.label_styles or DEFAULTS.label_styles,
            value = opts.value_styles or DEFAULTS.value_styles,
            paint = opts.paint_styles or DEFAULTS.paint_styles,
        },
        role = opts.role or DEFAULTS.role,
        label = opts.label,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }

    function bundle:value_from_point(report, x, y)
        return slider.value_from_point(report, self.id, x, y, self)
    end

    function bundle:with_report(report)
        self.report = report
        return self
    end

    return bundle
end

M.DEFAULTS = DEFAULTS
M.T = T

return M
