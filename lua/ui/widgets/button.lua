local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local state_bridge = require("ui.state")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T

local M = {}

local DEFAULTS = {
    kind = "button",
    role = "button",
    styles = tw.list {
        tw.flex,
        tw.row,
        tw.items_center,
        tw.justify_center,
        tw.gap_x_2,
        tw.px_4,
        tw.py_2,
        tw.rounded_lg,
        tw.border_1,
        tw.bg.slate[800],
        tw.border_color.slate[700],
        tw.fg.white,
        tw.cursor_pointer,
        tw.hover { tw.bg.slate[700], tw.border_color.slate[600] },
        tw.focus { tw.border_color.sky[400] },
        tw.active { tw.bg.slate[900], tw.border_color.sky[500] },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
    label_styles = tw.list {
        tw.text_sm,
        tw.font_semibold,
    },
}

local function copy_table(src)
    local out = {}
    if src ~= nil then
        for k, v in pairs(src) do out[k] = v end
    end
    return out
end

local function id_key(id)
    return ids.key(id)
end

local function state_opts_for(id, opts)
    opts = opts or {}
    local key = id_key(id)
    local out = copy_table(opts)
    if type(out.selected) == "boolean" then out.selected = { [key] = out.selected } end
    if type(out.disabled) == "boolean" then out.disabled = { [key] = out.disabled } end
    if type(out.active) == "boolean" then out.active = { [key] = out.active } end
    return out
end

local function derived_state(id, opts)
    opts = opts or {}
    local explicit = opts.state
    if opts.model == nil and opts.interact_model == nil and opts.report == nil
        and opts.selected == nil and opts.selected_ids == nil
        and opts.disabled == nil and opts.disabled_ids == nil
        and opts.active == nil and opts.active_ids == nil then
        return explicit
    end
    local derived = state_bridge.for_id(id, opts.model or opts.interact_model, opts.report, state_opts_for(id, opts))
    if explicit ~= nil then return state_bridge.merge(derived, explicit) end
    return derived
end

local function merge_style_value(items, value)
    if value ~= nil and value ~= false then
        items[#items + 1] = value
    end
end

local function normalize_children(id, opts, defaults)
    if opts.children ~= nil then return opts.children end
    if opts.child ~= nil then return { opts.child } end
    if opts.node ~= nil then return { opts.node } end

    local label = opts.label
    if label == nil then label = opts.text end
    if label == nil then label = defaults.label or "Button" end

    return {
        b.text {
            b.id(id_key(id) .. ":label"),
            defaults.label_styles,
            opts.label_styles,
            tostring(label),
        },
    }
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "button id")
    local defaults = opts.defaults or DEFAULTS

    local items = {
        b.id(id_key(id) .. ":box"),
    }
    merge_style_value(items, defaults.styles)
    merge_style_value(items, opts.styles)
    merge_style_value(items, opts.button_styles)

    local children = normalize_children(id, opts, defaults)
    for i = 1, #children do
        items[#items + 1] = children[i]
    end

    local child = b.box(items)
    local state = derived_state(id, opts)
    if state ~= nil and not state_bridge.is_empty(state) then
        child = b.with_state(state, child)
    end

    local role = opts.disabled and T.Interact.Passive or T.Interact.ActivateTarget
    local node = b.with_input(id, role, child)

    if opts.validate_ids ~= false then
        ids.assert_auth(node, opts.id_opts)
    end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "button id")
    local surfaces = {}
    local common = {
        widget_id = id,
        role = opts.role or DEFAULTS.role,
        label = opts.label or opts.text,
    }
    widget.add_surface(surfaces, "activate", id, copy_table(common))
    widget.add_surface(surfaces, "focus", id, copy_table(common))
    widget.add_surface(surfaces, "input", id, copy_table(common))
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle)
    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "button id")
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        selected = opts.selected,
        style_slots = {
            root = opts.styles or DEFAULTS.styles,
            label = opts.label_styles or DEFAULTS.label_styles,
        },
        role = opts.role or DEFAULTS.role,
        label = opts.label or opts.text,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }
end

function M.event(id, fields)
    return widget.activate_event(widget.require_id(id, "button id"), fields)
end

M.DEFAULTS = DEFAULTS
M.T = T

return M
