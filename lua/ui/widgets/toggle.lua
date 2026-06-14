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
    kind = "toggle",
    role = "switch",
    indicator_text = nil,
    styles = tw.list {
        tw.flex,
        tw.row,
        tw.items_center,
        tw.gap_x_2,
        tw.px_3,
        tw.py_2,
        tw.rounded_lg,
        tw.border_1,
        tw.bg.slate[900],
        tw.border_color.slate[700],
        tw.fg.slate[200],
        tw.cursor_pointer,
        tw.hover { tw.bg.slate[800] },
        tw.focus { tw.border_color.sky[400] },
        tw.active { tw.bg.slate[950] },
        tw.selected { tw.bg.sky[900], tw.border_color.sky[500], tw.fg.white },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
    indicator_styles = tw.list {
        tw.w_px(18),
        tw.h_px(18),
        tw.rounded_full,
        tw.border_2,
        tw.border_color.slate[500],
        tw.bg.slate[950],
        tw.selected { tw.bg.sky[400], tw.border_color.sky[300] },
    },
    label_styles = tw.list {
        tw.text_sm,
        tw.font_medium,
    },
}

local VARIANT_DEFAULTS = {
    checkbox = {
        kind = "checkbox",
        role = "checkbox",
        indicator_text = "✓",
        indicator_styles = tw.list {
            tw.w_px(18),
            tw.h_px(18),
            tw.rounded_sm,
            tw.border_2,
            tw.border_color.slate[500],
            tw.bg.slate[950],
            tw.flex,
            tw.items_center,
            tw.justify_center,
            tw.text_xs,
            tw.font_bold,
            tw.fg.transparent,
            tw.selected { tw.bg.sky[500], tw.border_color.sky[300], tw.fg.white },
        },
    },
    radio = {
        kind = "radio",
        role = "radio",
        indicator_text = "•",
        indicator_styles = tw.list {
            tw.w_px(18),
            tw.h_px(18),
            tw.rounded_full,
            tw.border_2,
            tw.border_color.slate[500],
            tw.bg.slate[950],
            tw.flex,
            tw.items_center,
            tw.justify_center,
            tw.text_lg,
            tw.font_bold,
            tw.fg.transparent,
            tw.selected { tw.border_color.sky[300], tw.fg.sky[300] },
        },
    },
}

local function copy_table(src)
    local out = {}
    if src ~= nil then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function merged_defaults(variant)
    local out = copy_table(DEFAULTS)
    local extra = VARIANT_DEFAULTS[variant]
    if extra ~= nil then
        for k, v in pairs(extra) do out[k] = v end
    end
    return out
end

local function id_key(id) return ids.key(id) end

local function bool_map_opts(id, opts)
    opts = opts or {}
    local key = id_key(id)
    local out = copy_table(opts)
    if type(out.selected) == "boolean" then out.selected = { [key] = out.selected } end
    if type(out.disabled) == "boolean" then out.disabled = { [key] = out.disabled } end
    if type(out.active) == "boolean" then out.active = { [key] = out.active } end
    return out
end

local function explicit_selected(opts)
    if opts.selected ~= nil then return opts.selected == true end
    if opts.checked ~= nil then return opts.checked == true end
    if opts.value ~= nil and type(opts.value) == "boolean" then return opts.value end
    return false
end

local function state_for(id, opts)
    opts = opts or {}
    local explicit = opts.state
    local selected = explicit_selected(opts)
    local bridge_opts = bool_map_opts(id, opts)
    bridge_opts.selected = bridge_opts.selected or { [id_key(id)] = selected }
    local derived = state_bridge.for_id(id, opts.model or opts.interact_model, opts.report, bridge_opts)
    if explicit ~= nil then return state_bridge.merge(derived, explicit) end
    return derived
end

local function add_style(items, value)
    if value ~= nil and value ~= false then items[#items + 1] = value end
end

local function indicator_node(id, opts, defaults)
    local items = { b.id(id_key(id) .. ":indicator") }
    add_style(items, defaults.indicator_styles)
    add_style(items, opts.indicator_styles)
    local text = opts.indicator_text
    if text == nil then text = defaults.indicator_text end
    if text ~= nil and text ~= false then
        items[#items + 1] = b.text { b.id(id_key(id) .. ":mark"), tostring(text) }
    end
    return b.box(items)
end

local function label_node(id, opts, defaults)
    local label = opts.label
    if label == nil then label = opts.text end
    if label == nil or label == false then return nil end
    return b.text {
        b.id(id_key(id) .. ":label"),
        defaults.label_styles,
        opts.label_styles,
        tostring(label),
    }
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "toggle id")
    local defaults = opts.defaults or merged_defaults(opts.variant)

    local items = { b.id(id_key(id) .. ":box") }
    add_style(items, defaults.styles)
    add_style(items, opts.styles)
    add_style(items, opts.toggle_styles)

    if opts.children ~= nil then
        for i = 1, #opts.children do items[#items + 1] = opts.children[i] end
    else
        items[#items + 1] = indicator_node(id, opts, defaults)
        local label = label_node(id, opts, defaults)
        if label ~= nil then items[#items + 1] = label end
    end

    local child = b.box(items)
    local state = state_for(id, opts)
    if state ~= nil and not state_bridge.is_empty(state) then
        child = b.with_state(state, child)
    end

    local role = opts.disabled and T.Interact.Passive or T.Interact.ActivateTarget
    local node = b.with_input(id, role, child)
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "toggle id")
    local surfaces = {}
    local common = {
        widget_id = id,
        role = opts.role or (opts.defaults and opts.defaults.role) or merged_defaults(opts.variant).role,
        label = opts.label or opts.text,
        value = opts.value,
    }
    widget.add_surface(surfaces, "activate", id, copy_table(common))
    widget.add_surface(surfaces, "focus", id, copy_table(common))
    widget.add_surface(surfaces, "input", id, copy_table(common))
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    if cls == Interact.Activate then
        local info = widget.lookup_surface(surfaces, "activate", ui_event.id)
        if info ~= nil then
            local selected = bundle and bundle.selected == true
            local next_value
            if bundle and bundle.kind == "radio" then
                next_value = bundle.value ~= nil and bundle.value or true
            else
                next_value = not selected
            end
            return widget.value_event(info.widget_id or info.id, next_value, {
                id = info.id,
                selected = next_value == true,
                surface = info,
                source = ui_event,
            })
        end
    end
    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "toggle id")
    local defaults = opts.defaults or merged_defaults(opts.variant)
    local selected = explicit_selected(opts)
    return widget.bundle {
        kind = opts.kind or defaults.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        selected = selected,
        value = opts.value,
        style_slots = {
            root = opts.styles or defaults.styles,
            indicator = opts.indicator_styles or defaults.indicator_styles,
            label = opts.label_styles or defaults.label_styles,
        },
        role = opts.role or defaults.role,
        label = opts.label or opts.text,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }
end

function M.defaults_for(variant)
    return merged_defaults(variant)
end

M.DEFAULTS = DEFAULTS
M.VARIANT_DEFAULTS = VARIANT_DEFAULTS
M.T = T

return M
