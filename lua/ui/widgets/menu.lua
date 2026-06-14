local pvm = require("pvm")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local button = require("ui.widgets.button")
local list = require("ui.widgets.list")
local popup = require("ui.widgets.popup")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact

local M = {}

local DEFAULTS = {
    kind = "menu",
    role = "menu",
    open = false,
    placement = Interact.PlaceBelow,
    modal = false,
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.gap_y_1,
        tw.min_w_px(160),
        tw.p_1,
    },
    item_styles = tw.list {
        tw.flex,
        tw.row,
        tw.items_center,
        tw.gap_x_2,
        tw.px_3,
        tw.py_2,
        tw.rounded_md,
        tw.cursor_pointer,
        tw.hover { tw.bg.slate[800] },
        tw.focus { tw.border_1, tw.border_color.sky[400] },
        tw.active { tw.bg.slate[950] },
        tw.selected { tw.bg.sky[900], tw.fg.white },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
}

local SELECT_DEFAULTS = {
    kind = "select",
    role = "combobox",
    open = false,
    placement = Interact.PlaceBelow,
    modal = false,
}

local function copy_table(src)
    local out = {}
    if src ~= nil then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end

local function merge_surfaces(dst, src)
    for group, map in pairs(src or {}) do
        for _, info in pairs(map) do
            widget.add_surface(dst, group, info.id, copy_table(info))
        end
    end
    return dst
end

local function selected_key(opts)
    if opts.selected_key ~= nil then return opts.selected_key end
    if opts.value ~= nil then return opts.value end
    return nil
end

local function label_for_key(items, key)
    if key == nil then return nil end
    for i = 1, #(items or {}) do
        local item = items[i]
        local item_key = item
        local label = item
        if type(item) == "table" then
            item_key = item.key or item.id or item.value or i
            label = item.label or item.text or item.name or item.value or item_key
        end
        if tostring(item_key) == tostring(key) then return label end
    end
    return nil
end

local function menu_ids(id)
    return {
        root = id,
        trigger = child_id(id, "trigger"),
        list = child_id(id, "list"),
        popup = child_id(id, "popup"),
        box = child_id(id, "box"),
    }
end

local function trigger_node(id, opts, defaults)
    local ids_ = menu_ids(id)
    if opts.trigger_node ~= nil then
        return b.with_input(ids_.trigger, opts.disabled and Interact.Passive or Interact.ActivateTarget, opts.trigger_node)
    end
    local label = opts.label or opts.text
    if label == nil and (opts.kind == "select" or opts.variant == "select") then
        label = label_for_key(opts.items, selected_key(opts)) or opts.placeholder or "Select"
    end
    label = label or "Menu"
    return button.node {
        id = ids_.trigger,
        label = tostring(label),
        disabled = opts.disabled,
        model = opts.model,
        interact_model = opts.interact_model,
        report = opts.report,
        styles = opts.trigger_styles,
        validate_ids = false,
    }
end

local function list_opts(id, opts, defaults)
    local ids_ = menu_ids(id)
    return {
        id = ids_.list,
        kind = "menu_list",
        variant = "listbox",
        role = "menu",
        items = opts.items or {},
        key_of = opts.key_of,
        label_of = opts.label_of,
        row = opts.row or opts.render_item,
        selected_key = selected_key(opts),
        disabled_items = opts.disabled_items or opts.disabled_keys or opts.disabled_item,
        focus_id = opts.focus_id or (opts.interact_model and opts.interact_model.focus_id),
        model = opts.model,
        interact_model = opts.interact_model,
        report = opts.report,
        orientation = opts.orientation or "vertical",
        activatable = true,
        focusable = true,
        scroll = opts.scroll == true,
        scroll_axis = opts.scroll_axis,
        styles = opts.menu_styles or defaults.styles,
        row_styles = opts.item_styles or defaults.item_styles,
        label_styles = opts.item_label_styles,
        validate_ids = false,
    }
end

local function popup_content(id, opts, defaults)
    local ids_ = menu_ids(id)
    if opts.content ~= nil then return opts.content end
    return list.node(list_opts(id, opts, defaults))
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "menu id")
    local defaults = opts.defaults or ((opts.kind == "select" or opts.variant == "select") and SELECT_DEFAULTS or DEFAULTS)
    local ids_ = menu_ids(id)
    local children = { trigger_node(id, opts, defaults) }
    if opts.open == true then
        children[#children + 1] = popup.node {
            id = ids_.popup,
            open = true,
            modal = opts.modal == true,
            placement = opts.placement or defaults.placement,
            anchor_id = ids_.trigger,
            child = popup_content(id, opts, defaults),
            styles = opts.popup_styles,
            focus_policy = opts.focus_policy or Interact.FocusTrap,
            validate_ids = false,
        }
    end
    local node = b.fragment(children)
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "menu id")
    local defaults = opts.defaults or ((opts.kind == "select" or opts.variant == "select") and SELECT_DEFAULTS or DEFAULTS)
    local ids_ = menu_ids(id)
    local surfaces = {}
    widget.add_surface(surfaces, "menu", id, { widget_id = id, role = opts.role or defaults.role, open = opts.open == true, label = opts.label })
    widget.add_surface(surfaces, "activate", ids_.trigger, { widget_id = id, role = "trigger", open = opts.open == true, label = opts.label })
    widget.add_surface(surfaces, "focus", ids_.trigger, { widget_id = id, role = "trigger", open = opts.open == true, label = opts.label })
    widget.add_surface(surfaces, "input", ids_.trigger, { widget_id = id, role = "trigger", open = opts.open == true, label = opts.label })
    merge_surfaces(surfaces, list.surfaces(list_opts(id, opts, defaults)))
    merge_surfaces(surfaces, popup.surfaces { id = ids_.popup, open = opts.open == true, modal = opts.modal == true, placement = opts.placement or defaults.placement })
    return surfaces
end

local function find_item(bundle, item_id)
    if bundle == nil then return nil end
    return list.listbox.bundle and bundle:info_for_id(item_id) or nil
end

local function menu_event(kind, bundle, fields)
    return widget.event(kind, bundle.id, fields)
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    if bundle == nil then return widget.route_interact_event(surfaces, ui_event, bundle) end
    local ids_ = menu_ids(bundle.id)

    if cls == Interact.Activate then
        if id_key(ui_event.id) == id_key(ids_.trigger) then
            return menu_event(bundle.open and "close" or "open", bundle, { id = ids_.trigger, open = not bundle.open, source = ui_event })
        end
        local info = widget.lookup_surface(surfaces, "items", ui_event.id)
        if info ~= nil and not info.disabled then
            if bundle.kind == "select" then
                return widget.value_event(bundle.id, info.key, { id = info.id, key = info.key, item = info.item, index = info.index, close = true, source = ui_event })
            end
            return menu_event("select", bundle, { id = info.id, key = info.key, value = info.key, item = info.item, index = info.index, close = true, source = ui_event })
        end
    elseif cls == Interact.KeyPressed then
        if ui_event.key == Interact.KeyEscape then
            if bundle.open then return menu_event("close", bundle, { reason = "escape", source = ui_event }) end
        elseif not bundle.open and (ui_event.key == Interact.KeyDown or ui_event.key == Interact.KeyUp or ui_event.key == Interact.KeyReturn or ui_event.key == Interact.KeySpace) then
            return menu_event("open", bundle, { open = true, source = ui_event })
        end
        local ev = list.route_one(surfaces, ui_event, bundle)
        if ev ~= nil then return ev end
    elseif ui_event == Interact.CancelPointer or ui_event == Interact.FocusLost then
        if bundle.open then return menu_event("close", bundle, { reason = ui_event == Interact.FocusLost and "focus_lost" or "cancel", source = ui_event }) end
    end

    local popup_ev = popup.route_one(surfaces, ui_event, bundle)
    if popup_ev ~= nil and bundle.open then return popup_ev end
    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "menu id")
    local defaults = opts.defaults or ((opts.kind == "select" or opts.variant == "select") and SELECT_DEFAULTS or DEFAULTS)
    local lb = list.bundle(list_opts(id, opts, defaults))
    local bundle = widget.bundle {
        kind = opts.kind or defaults.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        selected = selected_key(opts) ~= nil,
        value = selected_key(opts),
        selected_key = selected_key(opts),
        open = opts.open == true,
        item_infos = lb.item_infos,
        items = opts.items or {},
        focus_id = opts.focus_id or (opts.interact_model and opts.interact_model.focus_id) or (opts.model and opts.model.focus_id),
        orientation = opts.orientation or "vertical",
        wrap_navigation = opts.wrap_navigation ~= nil and opts.wrap_navigation or true,
        popup_id = menu_ids(id).popup,
        trigger_id = menu_ids(id).trigger,
        list_id = menu_ids(id).list,
        style_slots = {
            trigger = opts.trigger_styles,
            popup = opts.popup_styles,
            menu = opts.menu_styles or defaults.styles,
            item = opts.item_styles or defaults.item_styles,
        },
        role = opts.role or defaults.role,
        label = opts.label,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }

    function bundle:info_for_id(item_id)
        return lb:info_for_id(item_id)
    end

    function bundle:info_for_key(key)
        return lb:info_for_key(key)
    end

    function bundle:next_enabled(delta)
        return lb:next_enabled(delta)
    end

    return bundle
end

function M.select_opts(opts)
    opts = opts or {}
    local out = copy_table(opts)
    out.kind = out.kind or "select"
    out.variant = out.variant or "select"
    return out
end

M.select = {
    node = function(opts) return M.node(M.select_opts(opts)) end,
    surfaces = function(opts) return M.surfaces(M.select_opts(opts)) end,
    route_one = M.route_one,
    bundle = function(opts) return M.bundle(M.select_opts(opts)) end,
}

M.DEFAULTS = DEFAULTS
M.SELECT_DEFAULTS = SELECT_DEFAULTS
M.T = T

return M
