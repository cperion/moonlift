local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact

local M = {}

local DEFAULTS = {
    kind = "property_row",
    role = "group",
    styles = tw.list { tw.flex, tw.row, tw.items_center, tw.justify_between, tw.gap_x_3, tw.py_1 },
    label_box_styles = tw.list { tw.flex, tw.col, tw.gap_y_1 },
    label_styles = tw.list { tw.text_sm, tw.font_medium, tw.fg.slate[200] },
    description_styles = tw.list { tw.text_xs, tw.fg.slate[500] },
    control_styles = tw.list { tw.flex, tw.row, tw.items_center, tw.justify_end },
}

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end
local function add_style(items, value) if value ~= nil and value ~= false then items[#items + 1] = value end end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "property_row id")
    local items = { b.id(id_key(child_id(id, "box"))) }
    add_style(items, DEFAULTS.styles)
    add_style(items, opts.styles)

    local labels = { b.id(id_key(child_id(id, "label-box"))) }
    add_style(labels, DEFAULTS.label_box_styles)
    add_style(labels, opts.label_box_styles)
    labels[#labels + 1] = b.text { b.id(id_key(child_id(id, "label"))), DEFAULTS.label_styles, opts.label_styles, tostring(opts.label or opts.name or "") }
    if opts.description ~= nil and opts.description ~= false then
        labels[#labels + 1] = b.text { b.id(id_key(child_id(id, "description"))), DEFAULTS.description_styles, opts.description_styles, tostring(opts.description) }
    end
    items[#items + 1] = b.box(labels)

    local controls = { b.id(id_key(child_id(id, "control"))) }
    add_style(controls, DEFAULTS.control_styles)
    add_style(controls, opts.control_styles)
    if opts.control ~= nil then controls[#controls + 1] = opts.control
    elseif opts.child ~= nil then controls[#controls + 1] = opts.child
    elseif opts.children ~= nil then for i = 1, #opts.children do controls[#controls + 1] = opts.children[i] end end
    items[#items + 1] = b.box(controls)

    local node = b.with_input(id, opts.disabled and Interact.Passive or Interact.HitTarget, b.box(items))
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "property_row id")
    local surfaces = {}
    widget.add_surface(surfaces, "input", id, { widget_id = id, role = opts.role or DEFAULTS.role, label = opts.label or opts.name })
    widget.add_surface(surfaces, "property", id, { widget_id = id, role = opts.role or DEFAULTS.role, label = opts.label or opts.name })
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle) return widget.route_interact_event(surfaces, ui_event, bundle) end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "property_row id")
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        style_slots = { root = opts.styles or DEFAULTS.styles, label = opts.label_styles or DEFAULTS.label_styles, description = opts.description_styles or DEFAULTS.description_styles, control = opts.control_styles or DEFAULTS.control_styles },
        role = opts.role or DEFAULTS.role,
        label = opts.label or opts.name,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }
end

M.DEFAULTS = DEFAULTS
M.T = T
return M
