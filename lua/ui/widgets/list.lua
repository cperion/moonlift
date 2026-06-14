local pvm = require("pvm")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local state_bridge = require("ui.state")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact
local Style = T.Style

local M = {}

local DEFAULTS = {
    kind = "list",
    role = "list",
    orientation = "vertical",
    activatable = false,
    focusable = true,
    wrap_navigation = true,
    scroll = false,
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.gap_y_1,
        tw.fg.slate[200],
    },
    row_styles = tw.list {
        tw.flex,
        tw.row,
        tw.items_center,
        tw.gap_x_2,
        tw.px_3,
        tw.py_2,
        tw.rounded_md,
        tw.cursor_default,
        tw.hover { tw.bg.slate[800] },
        tw.focus { tw.border_1, tw.border_color.sky[400] },
        tw.selected { tw.bg.sky[900], tw.fg.white },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
    label_styles = tw.list { tw.text_sm, tw.font_medium },
}

local LISTBOX_DEFAULTS = {
    kind = "listbox",
    role = "listbox",
    activatable = true,
    focusable = true,
    selectable = true,
    row_styles = tw.list {
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

local TABS_DEFAULTS = {
    kind = "tabs",
    role = "tabs",
    orientation = "horizontal",
    activatable = true,
    focusable = true,
    selectable = true,
    styles = tw.list {
        tw.flex,
        tw.row,
        tw.gap_x_1,
        tw.border_1,
        tw.border_color.slate[800],
        tw.rounded_lg,
        tw.p_1,
        tw.bg.slate[950],
    },
    row_styles = tw.list {
        tw.flex,
        tw.row,
        tw.items_center,
        tw.justify_center,
        tw.px_3,
        tw.py_2,
        tw.rounded_md,
        tw.cursor_pointer,
        tw.hover { tw.bg.slate[800] },
        tw.focus { tw.border_1, tw.border_color.sky[400] },
        tw.active { tw.bg.slate[950] },
        tw.selected { tw.bg.sky[600], tw.fg.white },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
}

local function copy_table(src)
    local out = {}
    if src ~= nil then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function merged_defaults(variant)
    local out = copy_table(DEFAULTS)
    local extra = variant == "tabs" and TABS_DEFAULTS or (variant == "listbox" and LISTBOX_DEFAULTS or nil)
    if extra ~= nil then for k, v in pairs(extra) do out[k] = v end end
    return out
end

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end

local function add_style(items, value)
    if value ~= nil and value ~= false then items[#items + 1] = value end
end

local function key_string(key)
    if key == nil then return "nil" end
    return tostring(key)
end

local function key_of(item, index, opts)
    if opts.key_of ~= nil then return opts.key_of(item, index) end
    if type(item) == "table" then
        if item.key ~= nil then return item.key end
        if item.id ~= nil then return item.id end
        if item.value ~= nil then return item.value end
    end
    return index
end

local function label_of(item, index, opts)
    if opts.label_of ~= nil then return opts.label_of(item, index) end
    if type(item) == "table" then
        if item.label ~= nil then return item.label end
        if item.text ~= nil then return item.text end
        if item.name ~= nil then return item.name end
        if item.value ~= nil then return item.value end
    end
    return item
end

local function same_key(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

local function selected_key(opts)
    if opts.selected_key ~= nil then return opts.selected_key end
    if opts.value ~= nil then return opts.value end
    if opts.selected ~= nil and type(opts.selected) ~= "boolean" then return opts.selected end
    return nil
end

local function flag_for_item(spec, item, ctx)
    if spec == nil then return false end
    if type(spec) == "boolean" then return spec == true end
    if type(spec) == "function" then return spec(item, ctx) == true end
    if type(spec) == "table" then
        if spec[ctx.key] ~= nil then return spec[ctx.key] == true end
        local ks = key_string(ctx.key)
        if spec[ks] ~= nil then return spec[ks] == true end
        return false
    end
    return same_key(spec, ctx.key)
end

local function row_id(parent_id, key)
    return child_id(parent_id, "item:" .. key_string(key))
end

local function scroll_id(parent_id)
    return child_id(parent_id, "scroll")
end

local function row_box_id(parent_id, key)
    return child_id(parent_id, "item:" .. key_string(key) .. ":box")
end

local function item_infos(opts, defaults)
    local id = widget.require_id(opts.id, "list id")
    local items = opts.items or {}
    local selected = selected_key(opts)
    local out = {}
    for i = 1, #items do
        local item = items[i]
        local key = key_of(item, i, opts)
        local rid = row_id(id, key)
        local ctx = {
            id = rid,
            widget_id = id,
            item = item,
            key = key,
            index = i,
            first = i == 1,
            last = i == #items,
            selected = selected ~= nil and same_key(key, selected),
            disabled = false,
            role = defaults.role,
        }
        ctx.disabled = flag_for_item(opts.disabled_items or opts.disabled_keys or opts.disabled_item, item, ctx)
            or (type(item) == "table" and item.disabled == true)
        out[#out + 1] = ctx
    end
    return out
end

local function state_for_row(info, opts)
    opts = opts or {}
    local key = id_key(info.id)
    local bridge_opts = copy_table(opts)
    bridge_opts.selected = { [key] = info.selected == true }
    bridge_opts.disabled = { [key] = info.disabled == true }
    local explicit = opts.row_state
    if type(explicit) == "function" then explicit = explicit(info) end
    local derived = state_bridge.for_id(info.id, opts.model or opts.interact_model, opts.report, bridge_opts)
    if explicit ~= nil then return state_bridge.merge(derived, explicit) end
    return derived
end

local function default_row_node(info, opts, defaults)
    local items = { b.id(id_key(row_box_id(opts.id, info.key))) }
    add_style(items, defaults.row_styles)
    add_style(items, opts.row_styles)
    add_style(items, opts.item_styles)
    local label = label_of(info.item, info.index, opts)
    items[#items + 1] = b.text {
        b.id(id_key(child_id(info.id, "label"))),
        defaults.label_styles,
        opts.label_styles,
        tostring(label == nil and "" or label),
    }
    return b.box(items)
end

local function build_row(info, opts, defaults)
    local node
    if opts.row ~= nil then
        node = opts.row(info.item, info)
    elseif opts.render_item ~= nil then
        node = opts.render_item(info.item, info)
    else
        node = default_row_node(info, opts, defaults)
    end
    if node == nil or node == false then return nil end

    local state = state_for_row(info, opts)
    if state ~= nil and not state_bridge.is_empty(state) then node = b.with_state(state, node) end

    local focusable = opts.focusable
    if focusable == nil then focusable = defaults.focusable ~= false end
    local activatable = opts.activatable
    if activatable == nil then activatable = defaults.activatable == true end

    if info.disabled then
        return b.with_input(info.id, Interact.Passive, node)
    elseif activatable then
        return b.with_input(info.id, Interact.ActivateTarget, node)
    elseif focusable then
        return b.with_input(info.id, Interact.FocusTarget, node)
    end
    return node
end

local function build_contents(opts, defaults, infos)
    local children = {}
    if opts.before_all ~= nil then
        local node = opts.before_all(infos)
        if node ~= nil and node ~= false then children[#children + 1] = node end
    end
    for i = 1, #infos do
        local info = infos[i]
        if opts.before_item ~= nil then
            local node = opts.before_item(info.item, info)
            if node ~= nil and node ~= false then children[#children + 1] = node end
        end
        local row = build_row(info, opts, defaults)
        if row ~= nil and row ~= false then children[#children + 1] = row end
        if opts.after_item ~= nil then
            local node = opts.after_item(info.item, info)
            if node ~= nil and node ~= false then children[#children + 1] = node end
        end
    end
    if opts.after_all ~= nil then
        local node = opts.after_all(infos)
        if node ~= nil and node ~= false then children[#children + 1] = node end
    end
    return children
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "list id")
    local defaults = opts.defaults or merged_defaults(opts.variant or opts.kind)
    local infos = item_infos(opts, defaults)

    local items = { b.id(id_key(child_id(id, "box"))) }
    add_style(items, defaults.styles)
    add_style(items, opts.styles)
    if (opts.orientation or defaults.orientation) == "horizontal" then
        items[#items + 1] = tw.row
    else
        items[#items + 1] = tw.col
    end

    local children = build_contents(opts, defaults, infos)
    for i = 1, #children do items[#items + 1] = children[i] end

    local content = b.box(items)
    if opts.scroll == true or opts.scroll_axis ~= nil then
        local axis = opts.scroll_axis or ((opts.orientation or defaults.orientation) == "horizontal" and Style.ScrollX or Style.ScrollY)
        content = b.scroll(scroll_id(id), axis, { content })
    end

    local role = opts.disabled and Interact.Passive or Interact.HitTarget
    local node = b.with_input(id, role, content)
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "list id")
    local defaults = opts.defaults or merged_defaults(opts.variant or opts.kind)
    local infos = item_infos(opts, defaults)
    local surfaces = {}
    widget.add_surface(surfaces, "input", id, { widget_id = id, role = defaults.role, label = opts.label })
    widget.add_surface(surfaces, "list", id, { widget_id = id, role = defaults.role, label = opts.label })
    if opts.scroll == true or opts.scroll_axis ~= nil then
        widget.add_surface(surfaces, "scroll", scroll_id(id), { widget_id = id, role = "scroll", label = opts.label })
    end
    for i = 1, #infos do
        local info = copy_table(infos[i])
        info.widget_id = id
        info.role = opts.item_role or (defaults.kind == "tabs" and "tab" or "option")
        widget.add_surface(surfaces, "items", info.id, info)
        if not info.disabled then
            widget.add_surface(surfaces, "focus", info.id, copy_table(info))
            if opts.activatable ~= false and (defaults.activatable == true or opts.activatable == true) then
                widget.add_surface(surfaces, "activate", info.id, copy_table(info))
            end
        end
    end
    return surfaces
end

local function find_info_by_id(bundle, id)
    local key = id_key(id)
    if key == nil or bundle == nil then return nil end
    local infos = bundle.item_infos or {}
    for i = 1, #infos do
        if id_key(infos[i].id) == key then return infos[i], i end
    end
    return nil
end

local function find_info_by_key(bundle, key)
    if key == nil or bundle == nil then return nil end
    local infos = bundle.item_infos or {}
    for i = 1, #infos do
        if same_key(infos[i].key, key) then return infos[i], i end
    end
    return nil
end

local function enabled_indices(bundle)
    local out = {}
    local infos = bundle and bundle.item_infos or {}
    for i = 1, #infos do
        if not infos[i].disabled then out[#out + 1] = i end
    end
    return out
end

local function current_index(bundle)
    local focus_info, focus_i = find_info_by_id(bundle, bundle and bundle.focus_id)
    if focus_info ~= nil then return focus_i end
    local selected_info, selected_i = find_info_by_key(bundle, bundle and bundle.selected_key)
    if selected_info ~= nil then return selected_i end
    return nil
end

local function next_enabled_info(bundle, delta)
    local enabled = enabled_indices(bundle)
    if #enabled == 0 then return nil end
    local cur = current_index(bundle)
    local pos = nil
    if cur ~= nil then
        for i = 1, #enabled do if enabled[i] == cur then pos = i break end end
    end
    if delta == "first" then pos = 1
    elseif delta == "last" then pos = #enabled
    elseif pos == nil then pos = delta and delta < 0 and #enabled or 1
    else
        pos = pos + delta
        if bundle.wrap_navigation ~= false then
            if pos < 1 then pos = #enabled end
            if pos > #enabled then pos = 1 end
        else
            if pos < 1 then pos = 1 end
            if pos > #enabled then pos = #enabled end
        end
    end
    return bundle.item_infos[enabled[pos]]
end

local function navigation_delta(key, orientation)
    if key == Interact.KeyHome then return "first" end
    if key == Interact.KeyEnd then return "last" end
    if orientation == "horizontal" then
        if key == Interact.KeyLeft then return -1 end
        if key == Interact.KeyRight then return 1 end
    else
        if key == Interact.KeyUp then return -1 end
        if key == Interact.KeyDown then return 1 end
        if key == Interact.KeyPageUp then return -10 end
        if key == Interact.KeyPageDown then return 10 end
    end
    return nil
end

local function item_event(kind, bundle, info, source, extra)
    extra = extra or {}
    extra.id = info.id
    extra.key = info.key
    extra.item = info.item
    extra.index = info.index
    extra.selected = info.selected == true
    extra.disabled = info.disabled == true
    extra.source = source
    return widget.event(kind, bundle.id, extra)
end

function M.route_one(surfaces, ui_event, bundle)
    local cls = pvm.classof(ui_event)
    if bundle == nil then return widget.route_interact_event(surfaces, ui_event, bundle) end

    if cls == Interact.Activate then
        local info = widget.lookup_surface(surfaces, "items", ui_event.id)
        if info ~= nil and not info.disabled then
            return item_event("select", bundle, info, ui_event, { value = info.key })
        end
    elseif cls == Interact.SetFocus then
        local info = widget.lookup_surface(surfaces, "items", ui_event.id)
        if info ~= nil and not info.disabled then
            return item_event(widget.EventFocus, bundle, info, ui_event, { focused = true })
        end
    elseif cls == Interact.KeyPressed then
        local delta = navigation_delta(ui_event.key, bundle.orientation)
        if delta ~= nil then
            local info = next_enabled_info(bundle, delta)
            if info ~= nil then
                return item_event("navigate", bundle, info, ui_event, { focus_id = info.id, value = info.key })
            end
        elseif ui_event.key == Interact.KeyReturn or ui_event.key == Interact.KeySpace then
            local info = find_info_by_id(bundle, bundle.focus_id) or find_info_by_key(bundle, bundle.selected_key)
            if info ~= nil and not info.disabled then
                return item_event("select", bundle, info, ui_event, { value = info.key, input = "keyboard" })
            end
        end
    elseif cls == Interact.ScrollBy then
        local info = widget.lookup_surface(surfaces, "scroll", ui_event.id)
        if info ~= nil then
            return widget.event(widget.EventScroll, bundle.id, { id = info.id, dx = ui_event.dx, dy = ui_event.dy, source = ui_event })
        end
    end

    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "list id")
    local defaults = opts.defaults or merged_defaults(opts.variant or opts.kind)
    local infos = item_infos(opts, defaults)
    local selected = selected_key(opts)
    local bundle = widget.bundle {
        kind = opts.kind or defaults.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        selected = selected ~= nil,
        value = selected,
        selected_key = selected,
        focus_id = opts.focus_id or (opts.interact_model and opts.interact_model.focus_id) or (opts.model and opts.model.focus_id),
        item_infos = infos,
        items = opts.items or {},
        orientation = opts.orientation or defaults.orientation,
        wrap_navigation = opts.wrap_navigation ~= nil and opts.wrap_navigation or defaults.wrap_navigation,
        scroll = opts.scroll == true or opts.scroll_axis ~= nil,
        scroll_id = scroll_id(id),
        style_slots = {
            root = opts.styles or defaults.styles,
            item = opts.row_styles or opts.item_styles or defaults.row_styles,
            label = opts.label_styles or defaults.label_styles,
        },
        role = opts.role or defaults.role,
        label = opts.label,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }

    function bundle:info_for_id(item_id)
        return find_info_by_id(self, item_id)
    end

    function bundle:info_for_key(key)
        return find_info_by_key(self, key)
    end

    function bundle:next_enabled(delta)
        return next_enabled_info(self, delta)
    end

    return bundle
end

function M.listbox_opts(opts)
    opts = opts or {}
    local out = copy_table(opts)
    out.kind = out.kind or "listbox"
    out.variant = out.variant or "listbox"
    out.activatable = out.activatable ~= false
    out.focusable = out.focusable ~= false
    return out
end

function M.tabs_opts(opts)
    opts = opts or {}
    local out = copy_table(opts)
    out.kind = out.kind or "tabs"
    out.variant = out.variant or "tabs"
    out.orientation = out.orientation or "horizontal"
    out.activatable = out.activatable ~= false
    out.focusable = out.focusable ~= false
    return out
end

M.listbox = {
    node = function(opts) return M.node(M.listbox_opts(opts)) end,
    surfaces = function(opts) return M.surfaces(M.listbox_opts(opts)) end,
    route_one = M.route_one,
    bundle = function(opts) return M.bundle(M.listbox_opts(opts)) end,
}

M.tabs = {
    node = function(opts) return M.node(M.tabs_opts(opts)) end,
    surfaces = function(opts) return M.surfaces(M.tabs_opts(opts)) end,
    route_one = M.route_one,
    bundle = function(opts) return M.bundle(M.tabs_opts(opts)) end,
}

M.DEFAULTS = DEFAULTS
M.LISTBOX_DEFAULTS = LISTBOX_DEFAULTS
M.TABS_DEFAULTS = TABS_DEFAULTS
M.T = T

return M
