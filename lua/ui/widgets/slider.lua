local pvm = require("pvm")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local state_bridge = require("ui.state")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact

local M = {}

local DEFAULTS = {
    kind = "slider",
    role = "slider",
    orientation = "horizontal",
    min = 0,
    max = 1,
    step = nil,
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.gap_y_1,
        tw.cursor_pointer,
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
    label_styles = tw.list { tw.text_sm, tw.font_medium, tw.fg.slate[200] },
    value_styles = tw.list { tw.text_xs, tw.fg.slate[400] },
    track_styles = tw.list {
        tw.w_full,
        tw.h_px(8),
        tw.rounded_full,
        tw.bg.slate[800],
        tw.border_1,
        tw.border_color.slate[700],
        tw.hover { tw.border_color.slate[500] },
        tw.focus { tw.border_color.sky[400] },
        tw.active { tw.border_color.sky[500] },
    },
    fill_styles = tw.list {
        tw.h_px(6),
        tw.rounded_full,
        tw.bg.sky[500],
    },
    thumb_styles = tw.list {
        tw.w_px(16),
        tw.h_px(16),
        tw.rounded_full,
        tw.bg.slate[100],
        tw.border_2,
        tw.border_color.sky[500],
        tw.cursor_grab,
        tw.active { tw.cursor_grabbing, tw.bg.white },
    },
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

local function number_or(v, fallback)
    v = tonumber(v)
    if v == nil then return fallback end
    return v
end

function M.clamp(value, opts)
    opts = opts or {}
    local min = number_or(opts.min, DEFAULTS.min)
    local max = number_or(opts.max, DEFAULTS.max)
    if max < min then min, max = max, min end
    value = number_or(value, min)
    if value < min then value = min elseif value > max then value = max end
    local step = tonumber(opts.step or DEFAULTS.step)
    if step ~= nil and step > 0 then
        value = min + math.floor(((value - min) / step) + 0.5) * step
        if value < min then value = min elseif value > max then value = max end
    end
    return value
end

function M.normalized(value, opts)
    opts = opts or {}
    local min = number_or(opts.min, DEFAULTS.min)
    local max = number_or(opts.max, DEFAULTS.max)
    if max == min then return 0 end
    local v = (M.clamp(value, opts) - min) / (max - min)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

function M.value_from_normalized(t, opts)
    opts = opts or {}
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local min = number_or(opts.min, DEFAULTS.min)
    local max = number_or(opts.max, DEFAULTS.max)
    return M.clamp(min + (max - min) * t, opts)
end

local function find_hit(report, id)
    if report == nil or report.hits == nil then return nil end
    local key = id_key(id)
    for i = 1, #report.hits do
        local hit = report.hits[i]
        if id_key(hit.id) == key then return hit end
    end
    return nil
end

function M.value_from_point(report_or_box, id, x, y, opts)
    opts = opts or {}
    local box = report_or_box
    if report_or_box ~= nil and report_or_box.hits ~= nil then
        box = find_hit(report_or_box, id)
    end
    if box == nil then return nil end
    local orientation = opts.orientation or DEFAULTS.orientation
    local t
    if orientation == "vertical" then
        local h = box.h ~= 0 and box.h or 1
        t = 1 - ((y - box.y) / h)
    else
        local w = box.w ~= 0 and box.w or 1
        t = (x - box.x) / w
    end
    return M.value_from_normalized(t, opts), t, box
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

local function track_node(id, opts, defaults)
    local track_id = child_id(id, "track")
    local fill_id = child_id(id, "fill")
    local thumb_id = child_id(id, "thumb")
    local fill_px = math.max(1, math.floor((opts.fill_px or 96) * M.normalized(opts.value, opts)))

    local fill_items = { b.id(id_key(fill_id)), tw.w_px(fill_px) }
    add_style(fill_items, defaults.fill_styles)
    add_style(fill_items, opts.fill_styles)

    local thumb_items = { b.id(id_key(thumb_id)) }
    add_style(thumb_items, defaults.thumb_styles)
    add_style(thumb_items, opts.thumb_styles)

    local track_items = { b.id(id_key(track_id)), tw.flex, tw.row, tw.items_center }
    add_style(track_items, defaults.track_styles)
    add_style(track_items, opts.track_styles)
    track_items[#track_items + 1] = b.box(fill_items)
    track_items[#track_items + 1] = b.box(thumb_items)

    return b.drag_source(child_id(id, "drag"), b.box(track_items))
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "slider id")
    local defaults = opts.defaults or DEFAULTS
    opts.value = M.clamp(opts.value, opts)

    local items = { b.id(id_key(id) .. ":box") }
    add_style(items, defaults.styles)
    add_style(items, opts.styles)

    if opts.label ~= nil and opts.label ~= false then
        items[#items + 1] = b.text { b.id(id_key(id) .. ":label"), defaults.label_styles, opts.label_styles, tostring(opts.label) }
    end

    items[#items + 1] = track_node(id, opts, defaults)

    if opts.show_value == true then
        items[#items + 1] = b.text { b.id(id_key(id) .. ":value"), defaults.value_styles, opts.value_styles, fmt_value(opts.value, opts) }
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
    local id = widget.require_id(opts.id, "slider id")
    local surfaces = {}
    local common = {
        widget_id = id,
        role = opts.role or DEFAULTS.role,
        label = opts.label,
        min = opts.min or DEFAULTS.min,
        max = opts.max or DEFAULTS.max,
        step = opts.step,
        orientation = opts.orientation or DEFAULTS.orientation,
    }
    widget.add_surface(surfaces, "activate", id, copy_table(common))
    widget.add_surface(surfaces, "focus", id, copy_table(common))
    widget.add_surface(surfaces, "input", id, copy_table(common))
    widget.add_surface(surfaces, "drag", child_id(id, "drag"), copy_table(common))
    return surfaces
end

function M.increment(value, dir, opts)
    opts = opts or {}
    local min = number_or(opts.min, DEFAULTS.min)
    local max = number_or(opts.max, DEFAULTS.max)
    local step = tonumber(opts.step) or ((max - min) / 100)
    if step == 0 then step = 1 end
    return M.clamp(number_or(value, min) + step * (dir or 1), opts)
end

local function keyboard_delta(key)
    if key == Interact.KeyRight or key == Interact.KeyUp then return 1 end
    if key == Interact.KeyLeft or key == Interact.KeyDown then return -1 end
    if key == Interact.KeyPageUp then return 10 end
    if key == Interact.KeyPageDown then return -10 end
    if key == Interact.KeyHome then return "min" end
    if key == Interact.KeyEnd then return "max" end
    return nil
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    local id = bundle and bundle.id or nil

    if cls == Interact.KeyPressed and bundle ~= nil and bundle.focused == true then
        local delta = keyboard_delta(ui_event.key)
        if delta ~= nil then
            local value
            if delta == "min" then value = M.clamp(bundle.min or DEFAULTS.min, bundle)
            elseif delta == "max" then value = M.clamp(bundle.max or DEFAULTS.max, bundle)
            else value = M.increment(bundle.value, delta, bundle) end
            return widget.value_event(bundle.id, value, { id = bundle.id, source = ui_event, input = "keyboard" })
        end
    elseif cls == Interact.DragMoved or cls == Interact.DragDropped then
        local info = widget.lookup_surface(surfaces, "drag", ui_event.source_id)
        if info ~= nil and bundle ~= nil then
            local report = bundle.report
            local value = M.value_from_point(report, bundle.id, ui_event.x, ui_event.y, bundle)
            if value ~= nil then
                return widget.value_event(info.widget_id or bundle.id, value, { id = info.id, source = ui_event, input = "pointer" })
            end
        end
    elseif cls == Interact.Activate and id ~= nil then
        local info = widget.lookup_surface(surfaces, "activate", ui_event.id)
        if info ~= nil then
            return widget.activate_event(info.widget_id or info.id, { id = info.id, source = ui_event })
        end
    end

    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "slider id")
    local value = M.clamp(opts.value, opts)
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
        orientation = opts.orientation or DEFAULTS.orientation,
        report = opts.report,
        focused = opts.focused,
        throttle_ms = opts.throttle_ms or 0,
        redraw = opts.redraw or "on_change",
        style_slots = {
            root = opts.styles or DEFAULTS.styles,
            label = opts.label_styles or DEFAULTS.label_styles,
            track = opts.track_styles or DEFAULTS.track_styles,
            fill = opts.fill_styles or DEFAULTS.fill_styles,
            thumb = opts.thumb_styles or DEFAULTS.thumb_styles,
            value = opts.value_styles or DEFAULTS.value_styles,
        },
        role = opts.role or DEFAULTS.role,
        label = opts.label,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }

    function bundle:value_from_point(report, x, y)
        return M.value_from_point(report, self.id, x, y, self)
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
