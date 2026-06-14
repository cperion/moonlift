local pvm = require("pvm")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact

local M = {}

local DEFAULTS = {
    kind = "split_pane",
    role = "separator",
    orientation = "horizontal",
    ratio = 0.5,
    styles = tw.list { tw.flex, tw.row, tw.gap_x_2, tw.w_full },
    vertical_styles = tw.list { tw.flex, tw.col, tw.gap_y_2, tw.h_full },
    pane_styles = tw.list { tw.flex, tw.col, tw.grow_1 },
    handle_styles = tw.list { tw.w_px(6), tw.rounded_full, tw.bg.slate[800], tw.cursor_grab, tw.hover { tw.bg.slate[700] }, tw.active { tw.cursor_grabbing, tw.bg.sky[700] } },
    vertical_handle_styles = tw.list { tw.h_px(6), tw.rounded_full, tw.bg.slate[800], tw.cursor_grab, tw.hover { tw.bg.slate[700] }, tw.active { tw.cursor_grabbing, tw.bg.sky[700] } },
}

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end
local function add_style(items, value) if value ~= nil and value ~= false then items[#items + 1] = value end end

local function clamp_ratio(r)
    r = tonumber(r) or DEFAULTS.ratio
    if r < 0.05 then return 0.05 elseif r > 0.95 then return 0.95 end
    return r
end

function M.ratio_from_point(report_or_box, id, x, y, opts)
    opts = opts or {}
    local box = report_or_box
    if report_or_box ~= nil and report_or_box.hits ~= nil then
        local key = id_key(id)
        for i = 1, #report_or_box.hits do
            if id_key(report_or_box.hits[i].id) == key then box = report_or_box.hits[i] break end
        end
    end
    if box == nil then return nil end
    if (opts.orientation or DEFAULTS.orientation) == "vertical" then
        return clamp_ratio((y - box.y) / (box.h ~= 0 and box.h or 1))
    end
    return clamp_ratio((x - box.x) / (box.w ~= 0 and box.w or 1))
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "split_pane id")
    local vertical = (opts.orientation or DEFAULTS.orientation) == "vertical"
    local items = { b.id(id_key(child_id(id, "box"))) }
    add_style(items, vertical and DEFAULTS.vertical_styles or DEFAULTS.styles)
    add_style(items, opts.styles)

    local first = { b.id(id_key(child_id(id, "first"))) }
    add_style(first, DEFAULTS.pane_styles)
    add_style(first, opts.first_styles or opts.pane_styles)
    if opts.first ~= nil then first[#first + 1] = opts.first end
    items[#items + 1] = b.box(first)

    local handle_items = { b.id(id_key(child_id(id, "handle-box"))) }
    add_style(handle_items, vertical and DEFAULTS.vertical_handle_styles or DEFAULTS.handle_styles)
    add_style(handle_items, opts.handle_styles)
    items[#items + 1] = b.drag_source(child_id(id, "handle"), b.box(handle_items))

    local second = { b.id(id_key(child_id(id, "second"))) }
    add_style(second, DEFAULTS.pane_styles)
    add_style(second, opts.second_styles or opts.pane_styles)
    if opts.second ~= nil then second[#second + 1] = opts.second end
    items[#items + 1] = b.box(second)

    local node = b.with_input(id, opts.disabled and Interact.Passive or Interact.HitTarget, b.box(items))
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "split_pane id")
    local surfaces = {}
    widget.add_surface(surfaces, "input", id, { widget_id = id, role = opts.role or DEFAULTS.role, orientation = opts.orientation or DEFAULTS.orientation })
    widget.add_surface(surfaces, "drag", child_id(id, "handle"), { widget_id = id, role = "resize_handle", orientation = opts.orientation or DEFAULTS.orientation })
    widget.add_surface(surfaces, "separator", child_id(id, "handle"), { widget_id = id, role = opts.role or DEFAULTS.role, orientation = opts.orientation or DEFAULTS.orientation })
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    if (cls == Interact.DragMoved or cls == Interact.DragDropped) and bundle ~= nil then
        local info = widget.lookup_surface(surfaces, "drag", ui_event.source_id)
        if info ~= nil then
            local ratio = M.ratio_from_point(bundle.report, bundle.id, ui_event.x, ui_event.y, bundle)
            return widget.value_event(bundle.id, ratio or bundle.ratio, { id = info.id, ratio = ratio or bundle.ratio, source = ui_event, input = "pointer" })
        end
    end
    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "split_pane id")
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        value = clamp_ratio(opts.ratio),
        ratio = clamp_ratio(opts.ratio),
        orientation = opts.orientation or DEFAULTS.orientation,
        report = opts.report,
        style_slots = { root = opts.styles or DEFAULTS.styles, pane = opts.pane_styles or DEFAULTS.pane_styles, handle = opts.handle_styles or DEFAULTS.handle_styles },
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
