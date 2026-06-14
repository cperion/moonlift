local pvm = require("pvm")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Auth = T.Auth
local Interact = T.Interact

local M = {}

local DEFAULTS = {
    kind = "popup",
    role = "popup",
    open = false,
    modal = false,
    placement = Interact.PlaceBelow,
    layer_kind = Interact.LayerPopup,
    order = 100,
    focus_policy = Interact.FocusPassthrough,
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.gap_y_1,
        tw.p_2,
        tw.rounded_lg,
        tw.border_1,
        tw.border_color.slate[700],
        tw.bg.slate[950],
        tw.fg.slate[100],
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

local function normalize_id(id, label)
    return widget.require_id(id, label or "popup id")
end

function M.ids(id)
    id = normalize_id(id)
    return {
        root = id,
        layer = child_id(id, "layer"),
        overlay = child_id(id, "overlay"),
        scope = child_id(id, "focus-scope"),
        box = child_id(id, "box"),
    }
end

local function content_node(id, opts)
    if opts.child ~= nil then return opts.child end
    if opts.node ~= nil then return opts.node end
    if opts.children ~= nil then return b.fragment(opts.children) end
    if opts.content ~= nil then
        if type(opts.content) == "string" or type(opts.content) == "number" then
            return b.text { b.id(id_key(child_id(id, "text"))), tostring(opts.content) }
        end
        return opts.content
    end
    return b.empty
end

function M.wrap(id, child, opts)
    opts = opts or {}
    id = normalize_id(id)
    if opts.open == false then return b.empty end

    local ids_ = M.ids(id)
    local box_items = { b.id(id_key(ids_.box)) }
    add_style(box_items, DEFAULTS.styles)
    add_style(box_items, opts.styles)
    add_style(box_items, opts.popup_styles)
    if child ~= nil and child ~= false then box_items[#box_items + 1] = child end
    local node = b.box(box_items)

    local policy = opts.focus_policy or (opts.modal and Interact.FocusTrap or DEFAULTS.focus_policy)
    if opts.focus_scope ~= false then
        node = Auth.FocusScope(ids_.scope, policy, node)
    end

    local anchor_id = opts.anchor_id
    if type(anchor_id) == "string" then anchor_id = ids.id(anchor_id) end
    anchor_id = anchor_id or Core.NoId
    node = Auth.Overlay(ids_.overlay, anchor_id, opts.placement or DEFAULTS.placement, opts.modal == true, node)
    node = Auth.Layer(ids_.layer, opts.layer_kind or (opts.modal and Interact.LayerModal or DEFAULTS.layer_kind), opts.order or DEFAULTS.order, node)
    return node
end

function M.node(opts)
    opts = opts or {}
    local id = normalize_id(opts.id)
    local child = content_node(id, opts)
    local node = M.wrap(id, child, opts)
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = normalize_id(opts.id)
    local ids_ = M.ids(id)
    local surfaces = {}
    widget.add_surface(surfaces, "popup", id, {
        widget_id = id,
        role = opts.role or DEFAULTS.role,
        open = opts.open == true,
        modal = opts.modal == true,
        placement = opts.placement or DEFAULTS.placement,
    })
    widget.add_surface(surfaces, "layer", ids_.layer, { widget_id = id, role = "layer", open = opts.open == true })
    widget.add_surface(surfaces, "overlay", ids_.overlay, { widget_id = id, role = "overlay", open = opts.open == true, modal = opts.modal == true })
    widget.add_surface(surfaces, "focus_scope", ids_.scope, { widget_id = id, role = "focus_scope", open = opts.open == true })
    widget.add_surface(surfaces, "close", id, { widget_id = id, role = "close", open = opts.open == true })
    return surfaces
end

function M.close_event(id, fields)
    return widget.event("close", id, fields)
end

function M.open_event(id, fields)
    return widget.event("open", id, fields)
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    local id = bundle and bundle.id
    if id == nil then
        local popup = surfaces and surfaces.popup
        if popup ~= nil then
            for _, info in pairs(popup) do id = info.widget_id or info.id break end
        end
    end
    if id == nil then return nil end

    if ui_event == Interact.CancelPointer or ui_event == Interact.FocusLost then
        return M.close_event(id, { source = ui_event, reason = ui_event == Interact.FocusLost and "focus_lost" or "cancel" })
    end
    if cls == Interact.KeyPressed and ui_event.key == Interact.KeyEscape then
        return M.close_event(id, { source = ui_event, reason = "escape" })
    end
    return nil
end

function M.bundle(opts)
    opts = opts or {}
    local id = normalize_id(opts.id)
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        open = opts.open == true,
        modal = opts.modal == true,
        placement = opts.placement or DEFAULTS.placement,
        layer_kind = opts.layer_kind or (opts.modal and Interact.LayerModal or DEFAULTS.layer_kind),
        order = opts.order or DEFAULTS.order,
        style_slots = { root = opts.styles or DEFAULTS.styles },
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
