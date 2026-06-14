local pvm = require("pvm")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local popup = require("ui.widgets.popup")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact

local M = {}

local DEFAULTS = {
    kind = "overlay",
    role = "overlay",
    open = false,
    placement = Interact.PlaceAuto,
    modal = false,
    layer_kind = Interact.LayerOverlay,
    order = 90,
    focus_policy = Interact.FocusPassthrough,
}

local TOOLTIP_DEFAULTS = {
    kind = "tooltip",
    role = "tooltip",
    placement = Interact.PlaceAbove,
    modal = false,
    layer_kind = Interact.LayerTooltip,
    order = 120,
    focus_scope = false,
    styles = tw.list {
        tw.px_2,
        tw.py_1,
        tw.rounded_md,
        tw.bg.slate[900],
        tw.border_1,
        tw.border_color.slate[700],
        tw.fg.slate[100],
        tw.text_xs,
    },
}

local POPOVER_DEFAULTS = {
    kind = "popover",
    role = "popover",
    placement = Interact.PlaceAuto,
    modal = false,
    layer_kind = Interact.LayerPopup,
    order = 110,
    focus_policy = Interact.FocusTrap,
}

local MODAL_DEFAULTS = {
    kind = "modal",
    role = "dialog",
    placement = Interact.PlaceCenter,
    modal = true,
    layer_kind = Interact.LayerModal,
    order = 1000,
    focus_policy = Interact.FocusTrap,
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.gap_y_3,
        tw.min_w_px(320),
        tw.p_4,
        tw.rounded_xl,
        tw.border_1,
        tw.border_color.slate[700],
        tw.bg.slate[950],
        tw.fg.slate[100],
    },
    title_styles = tw.list { tw.text_lg, tw.font_semibold, tw.fg.white },
    body_styles = tw.list { tw.text_sm, tw.fg.slate[300] },
    actions_styles = tw.list { tw.flex, tw.row, tw.justify_end, tw.gap_x_2 },
    close_styles = nil,
}

local function copy_table(src)
    local out = {}
    if src ~= nil then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end

local function merge_defaults(kind)
    local out = copy_table(DEFAULTS)
    local extra
    if kind == "tooltip" then extra = TOOLTIP_DEFAULTS
    elseif kind == "modal" or kind == "dialog" then extra = MODAL_DEFAULTS
    elseif kind == "popover" then extra = POPOVER_DEFAULTS end
    if extra ~= nil then for k, v in pairs(extra) do out[k] = v end end
    return out
end

local function add_style(items, value)
    if value ~= nil and value ~= false then items[#items + 1] = value end
end

local function content_from_opts(id, opts, defaults)
    if opts.child ~= nil then return opts.child end
    if opts.node ~= nil then return opts.node end
    if opts.children ~= nil then return b.fragment(opts.children) end

    if defaults.kind == "modal" or defaults.kind == "dialog" or opts.kind == "modal" or opts.kind == "dialog" then
        local items = { b.id(id_key(child_id(id, "content"))) }
        add_style(items, defaults.styles)
        add_style(items, opts.styles)
        if opts.title ~= nil and opts.title ~= false then
            items[#items + 1] = b.text { b.id(id_key(child_id(id, "title"))), defaults.title_styles, opts.title_styles, tostring(opts.title) }
        end
        if opts.body ~= nil and opts.body ~= false then
            if type(opts.body) == "string" or type(opts.body) == "number" then
                items[#items + 1] = b.text { b.id(id_key(child_id(id, "body"))), defaults.body_styles, opts.body_styles, tostring(opts.body) }
            else
                items[#items + 1] = opts.body
            end
        elseif opts.content ~= nil then
            if type(opts.content) == "string" or type(opts.content) == "number" then
                items[#items + 1] = b.text { b.id(id_key(child_id(id, "body"))), defaults.body_styles, opts.body_styles, tostring(opts.content) }
            else
                items[#items + 1] = opts.content
            end
        end
        if opts.actions ~= nil then
            local action_items = { b.id(id_key(child_id(id, "actions"))) }
            add_style(action_items, defaults.actions_styles)
            add_style(action_items, opts.actions_styles)
            for i = 1, #opts.actions do action_items[#action_items + 1] = opts.actions[i] end
            items[#items + 1] = b.box(action_items)
        end
        if opts.close_label ~= nil and opts.close_label ~= false then
            local close_id = child_id(id, "close")
            local close_items = { b.id(id_key(child_id(id, "close:box"))) }
            add_style(close_items, opts.close_styles or defaults.close_styles)
            close_items[#close_items + 1] = b.text { b.id(id_key(child_id(id, "close:label"))), tostring(opts.close_label or "Close") }
            items[#items + 1] = b.with_input(close_id, Interact.ActivateTarget, b.box(close_items))
        end
        return b.box(items)
    end

    if opts.content ~= nil then
        if type(opts.content) == "string" or type(opts.content) == "number" then
            return b.text { b.id(id_key(child_id(id, "text"))), tostring(opts.content) }
        end
        return opts.content
    end
    return b.empty
end

local function popup_opts(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "overlay id")
    local defaults = opts.defaults or merge_defaults(opts.variant or opts.kind)
    local out = copy_table(opts)
    out.kind = opts.kind or defaults.kind
    out.role = opts.role or defaults.role
    out.open = opts.open == true
    out.modal = opts.modal ~= nil and opts.modal or defaults.modal
    out.placement = opts.placement or defaults.placement
    out.layer_kind = opts.layer_kind or defaults.layer_kind
    out.order = opts.order or defaults.order
    out.focus_policy = opts.focus_policy or defaults.focus_policy
    out.focus_scope = opts.focus_scope ~= nil and opts.focus_scope or defaults.focus_scope
    out.styles = opts.popup_styles or opts.styles or defaults.styles
    out.child = content_from_opts(id, opts, defaults)
    return out, defaults
end

function M.node(opts)
    local out = popup_opts(opts)
    return popup.node(out)
end

function M.surfaces(opts)
    local out = popup_opts(opts)
    local surfaces = popup.surfaces(out)
    local id = widget.require_id(out.id, "overlay id")
    if out.kind == "modal" or out.kind == "dialog" then
        widget.add_surface(surfaces, "modal", id, { widget_id = id, role = out.role, open = out.open, modal = true })
        if out.close_label ~= nil and out.close_label ~= false then
            widget.add_surface(surfaces, "activate", child_id(id, "close"), { widget_id = id, role = "close", open = out.open })
        end
    elseif out.kind == "tooltip" then
        widget.add_surface(surfaces, "tooltip", id, { widget_id = id, role = out.role, open = out.open, anchor_id = out.anchor_id })
    else
        widget.add_surface(surfaces, "popover", id, { widget_id = id, role = out.role, open = out.open, modal = out.modal })
    end
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    if bundle ~= nil and cls == Interact.Activate then
        local close = widget.lookup_surface(surfaces, "activate", ui_event.id)
        if close ~= nil and close.role == "close" then
            return widget.event("close", bundle.id, { id = close.id, reason = "button", source = ui_event })
        end
    end
    if bundle ~= nil and (bundle.kind == "modal" or bundle.kind == "dialog" or bundle.kind == "popover") then
        local ev = popup.route_one(surfaces, ui_event, bundle)
        if ev ~= nil then return ev end
    end
    return nil
end

function M.bundle(opts)
    opts = opts or {}
    local out, defaults = popup_opts(opts)
    local id = widget.require_id(out.id, "overlay id")
    return widget.bundle {
        kind = out.kind,
        id = id,
        node = M.node(out),
        surfaces = M.surfaces(out),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        open = out.open,
        modal = out.modal,
        placement = out.placement,
        layer_kind = out.layer_kind,
        order = out.order,
        style_slots = {
            root = out.styles,
            title = opts.title_styles or defaults.title_styles,
            body = opts.body_styles or defaults.body_styles,
            actions = opts.actions_styles or defaults.actions_styles,
        },
        role = out.role,
        label = opts.label or opts.title,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }
end

function M.tooltip_opts(opts)
    opts = opts or {}
    local out = copy_table(opts)
    out.kind = out.kind or "tooltip"
    out.variant = out.variant or "tooltip"
    out.open = out.open ~= false
    return out
end

function M.popover_opts(opts)
    opts = opts or {}
    local out = copy_table(opts)
    out.kind = out.kind or "popover"
    out.variant = out.variant or "popover"
    return out
end

function M.modal_opts(opts)
    opts = opts or {}
    local out = copy_table(opts)
    out.kind = out.kind or "modal"
    out.variant = out.variant or "modal"
    out.modal = true
    return out
end

M.tooltip = {
    node = function(opts) return M.node(M.tooltip_opts(opts)) end,
    surfaces = function(opts) return M.surfaces(M.tooltip_opts(opts)) end,
    route_one = M.route_one,
    bundle = function(opts) return M.bundle(M.tooltip_opts(opts)) end,
}

M.popover = {
    node = function(opts) return M.node(M.popover_opts(opts)) end,
    surfaces = function(opts) return M.surfaces(M.popover_opts(opts)) end,
    route_one = M.route_one,
    bundle = function(opts) return M.bundle(M.popover_opts(opts)) end,
}

M.modal = {
    node = function(opts) return M.node(M.modal_opts(opts)) end,
    surfaces = function(opts) return M.surfaces(M.modal_opts(opts)) end,
    route_one = M.route_one,
    bundle = function(opts) return M.bundle(M.modal_opts(opts)) end,
}

M.dialog = M.modal
M.DEFAULTS = DEFAULTS
M.TOOLTIP_DEFAULTS = TOOLTIP_DEFAULTS
M.POPOVER_DEFAULTS = POPOVER_DEFAULTS
M.MODAL_DEFAULTS = MODAL_DEFAULTS
M.T = T

return M
