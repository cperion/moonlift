local b = require("ui.build")
local tw = require("ui.tw")
local paint = require("ui.paint")
local widget = require("ui.widget")
local ids = require("ui.id")
local slider = require("ui.widgets.slider")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T

local M = {}

local DEFAULTS = {
    kind = "meter",
    role = "meter",
    min = 0,
    max = 1,
    value = 0,
    peak = nil,
    hold = nil,
    width = 160,
    height = 14,
    orientation = "horizontal",
    redraw = "timed",
    animation_ms = 80,
    styles = tw.list { tw.flex, tw.col, tw.gap_y_1 },
    label_styles = tw.list { tw.text_xs, tw.font_medium, tw.fg.slate[300] },
    value_styles = tw.list { tw.text_xs, tw.fg.slate[400] },
    paint_styles = nil,
    bg_rgba8 = 0x0f172aff,
    border_rgba8 = 0x334155ff,
    fill_rgba8 = 0x22c55eff,
    warn_rgba8 = 0xf59e0bff,
    clip_rgba8 = 0xef4444ff,
    peak_rgba8 = 0xf8fafcff,
    hold_rgba8 = 0x38bdf8ff,
    warn_at = 0.75,
    clip_at = 0.93,
}

local function copy_table(src)
    local out = {}
    if src ~= nil then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function id_key(id) return ids.key(id) end

local function add_style(items, value)
    if value ~= nil and value ~= false then items[#items + 1] = value end
end

local function rect(x, y, w, h, fill, stroke)
    return paint.polygon({ x, y, x + w, y, x + w, y + h, x, y + h }, fill, stroke)
end

local function value_color(t, opts)
    if opts.color_for_value ~= nil then return opts.color_for_value(t, opts) end
    if t >= (opts.clip_at or DEFAULTS.clip_at) then return opts.clip_rgba8 or DEFAULTS.clip_rgba8 end
    if t >= (opts.warn_at or DEFAULTS.warn_at) then return opts.warn_rgba8 or DEFAULTS.warn_rgba8 end
    return opts.fill_rgba8 or DEFAULTS.fill_rgba8
end

function M.normalized(value, opts)
    return slider.normalized(value, opts)
end

function M.program(opts)
    opts = opts or {}
    local w = opts.width or DEFAULTS.width
    local h = opts.height or DEFAULTS.height
    local t = M.normalized(opts.value or DEFAULTS.value, opts)
    local peak_t = opts.peak ~= nil and M.normalized(opts.peak, opts) or nil
    local hold_t = opts.hold ~= nil and M.normalized(opts.hold, opts) or nil
    local vertical = opts.orientation == "vertical"
    local programs = {}

    programs[#programs + 1] = rect(0, 0, w, h, paint.fill(opts.bg_rgba8 or DEFAULTS.bg_rgba8), paint.stroke(opts.border_rgba8 or DEFAULTS.border_rgba8, 1))

    if vertical then
        local fill_h = math.max(0, h * t)
        programs[#programs + 1] = rect(1, h - fill_h, math.max(0, w - 2), fill_h, paint.fill(value_color(t, opts)), nil)
        if peak_t ~= nil then
            local y = h - h * peak_t
            programs[#programs + 1] = paint.line(1, y, w - 1, y, paint.stroke(opts.peak_rgba8 or DEFAULTS.peak_rgba8, 2))
        end
        if hold_t ~= nil then
            local y = h - h * hold_t
            programs[#programs + 1] = paint.line(1, y, w - 1, y, paint.stroke(opts.hold_rgba8 or DEFAULTS.hold_rgba8, 1))
        end
    else
        local fill_w = math.max(0, w * t)
        programs[#programs + 1] = rect(1, 1, fill_w, math.max(0, h - 2), paint.fill(value_color(t, opts)), nil)
        if peak_t ~= nil then
            local x = w * peak_t
            programs[#programs + 1] = paint.line(x, 1, x, h - 1, paint.stroke(opts.peak_rgba8 or DEFAULTS.peak_rgba8, 2))
        end
        if hold_t ~= nil then
            local x = w * hold_t
            programs[#programs + 1] = paint.line(x, 1, x, h - 1, paint.stroke(opts.hold_rgba8 or DEFAULTS.hold_rgba8, 1))
        end
    end

    return paint.list(programs)
end

local function fmt_value(value, opts)
    if opts.format_value ~= nil then return opts.format_value(value, opts) end
    local precision = opts.precision or 2
    return string.format("%." .. tostring(precision) .. "f", value or 0)
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "meter id")
    local value = slider.clamp(opts.value or DEFAULTS.value, opts)
    local w = opts.width or DEFAULTS.width
    local h = opts.height or DEFAULTS.height

    local items = { b.id(id_key(id) .. ":box") }
    add_style(items, DEFAULTS.styles)
    add_style(items, opts.styles)

    if opts.label ~= nil and opts.label ~= false then
        items[#items + 1] = b.text { b.id(id_key(id) .. ":label"), DEFAULTS.label_styles, opts.label_styles, tostring(opts.label) }
    end

    local paint_items = { b.id(id_key(id) .. ":paint"), tw.w_px(w), tw.h_px(h) }
    add_style(paint_items, DEFAULTS.paint_styles)
    add_style(paint_items, opts.paint_styles)
    local paint_opts = copy_table(opts)
    paint_opts.value = value
    paint_items[#paint_items + 1] = M.program(paint_opts)
    items[#items + 1] = b.paint(paint_items)

    if opts.show_value == true then
        items[#items + 1] = b.text { b.id(id_key(id) .. ":value"), DEFAULTS.value_styles, opts.value_styles, fmt_value(value, opts) }
    end

    local node = b.box(items)
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "meter id")
    local surfaces = {}
    widget.add_surface(surfaces, "display", id, {
        widget_id = id,
        role = opts.role or DEFAULTS.role,
        label = opts.label,
        min = opts.min or DEFAULTS.min,
        max = opts.max or DEFAULTS.max,
        value = opts.value or DEFAULTS.value,
        peak = opts.peak,
        hold = opts.hold,
    })
    return surfaces
end

function M.route_one()
    return nil
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "meter id")
    local value = slider.clamp(opts.value or DEFAULTS.value, opts)
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        value = value,
        min = opts.min or DEFAULTS.min,
        max = opts.max or DEFAULTS.max,
        peak = opts.peak,
        hold = opts.hold,
        redraw = opts.redraw or DEFAULTS.redraw,
        animation_ms = opts.animation_ms or DEFAULTS.animation_ms,
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
end

M.DEFAULTS = DEFAULTS
M.T = T

return M
