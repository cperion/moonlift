local ui_asdl = require("ui.asdl")
local ui_text_field = require("ui.text_field")
local text_field_view = require("ui.text_field_view")
local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local state_bridge = require("ui.state")

local T = ui_asdl.T

local M = {}

local function copy_table(src)
    local out = {}
    if src ~= nil then
        for k, v in pairs(src) do
            out[k] = v
        end
    end
    return out
end

local function require_id(opts, level)
    local id = opts and opts.id or nil
    return widget.require_id(id, "text widget id")
end

local function id_value(id)
    return ids.key(id)
end

local function host_for_text(host_or_window)
    if host_or_window ~= nil and host_or_window.size ~= nil then
        return host_or_window, host_or_window
    end
    if host_or_window ~= nil and host_or_window.host ~= nil then
        return host_or_window.host, host_or_window
    end
    return host_or_window, host_or_window
end

local function text_key_for(host_or_window, opts)
    if opts ~= nil and opts.text_key ~= nil then return opts.text_key end
    if host_or_window ~= nil then
        if host_or_window.text_key ~= nil then return host_or_window.text_key end
        if host_or_window.text_system_key ~= nil then return host_or_window.text_system_key end
        if host_or_window.session ~= nil then
            return host_or_window.session.text_key or host_or_window.session.text_system_key
        end
    end
    return nil
end

local function set_text_input(host, active)
    if host ~= nil and host.set_text_input ~= nil then
        return host:set_text_input(active)
    end
end

local function state_for_opts(id, opts)
    if opts == nil then return nil end
    local explicit = opts.state or opts.field_state
    if opts.model == nil and opts.interact_model == nil and opts.report == nil
        and opts.selected == nil and opts.selected_ids == nil
        and opts.disabled == nil and opts.disabled_ids == nil
        and opts.active == nil and opts.active_ids == nil then
        return explicit
    end
    local key = id_value(id)
    local bridge_opts = copy_table(opts)
    if type(bridge_opts.selected) == "boolean" then bridge_opts.selected = { [key] = bridge_opts.selected } end
    if type(bridge_opts.disabled) == "boolean" then bridge_opts.disabled = { [key] = bridge_opts.disabled } end
    if type(bridge_opts.active) == "boolean" then bridge_opts.active = { [key] = bridge_opts.active } end
    local derived = state_bridge.for_id(id, opts.model or opts.interact_model, opts.report, bridge_opts)
    if explicit ~= nil then
        return state_bridge.merge(derived, explicit)
    end
    return derived
end

local function merge_style_value(items, value)
    if value ~= nil and value ~= false then
        items[#items + 1] = value
    end
end

function M.find_hit_box(report, id)
    if report == nil or report.hits == nil then return nil end
    for i = 1, #report.hits do
        local hit = report.hits[i]
        if hit.id == id then return hit end
    end
    return nil
end

function M.build_shell(opts, defaults)
    opts = opts or {}
    defaults = defaults or {}

    local id = require_id(opts, 3)
    local id_string = id_value(id)
    local gap_y = opts.gap_y or defaults.gap_y or 8
    local min_h = opts.min_h or defaults.min_h

    local field_box_items = {
        b.id(id_string .. ":field"),
        tw.w_full,
    }
    if min_h ~= nil then
        field_box_items[#field_box_items + 1] = tw.min_h_px(min_h)
    end
    merge_style_value(field_box_items, defaults.field_styles)
    merge_style_value(field_box_items, opts.field_styles)

    local wrapper_items = {
        tw.flow,
        tw.gap_y(gap_y),
    }
    merge_style_value(wrapper_items, defaults.styles)
    merge_style_value(wrapper_items, opts.styles)

    if opts.label ~= nil and opts.label ~= "" then
        wrapper_items[#wrapper_items + 1] = b.text {
            b.id(id_string .. ":label"),
            defaults.label_styles,
            opts.label_styles,
            opts.label,
        }
    end

    local field_node = opts.field_node
    if field_node == nil then
        field_node = b.with_input(id, T.Interact.EditTarget, b.box(field_box_items))
    end

    local derived_state = state_for_opts(id, opts)
    if derived_state ~= nil and not state_bridge.is_empty(derived_state) then
        field_node = b.with_state(derived_state, field_node)
    end

    wrapper_items[#wrapper_items + 1] = field_node

    local node = b.box(wrapper_items)
    if opts.validate_ids ~= false then
        ids.assert_auth(node, opts.id_opts)
    end
    return node
end

function M.surfaces(opts, defaults)
    opts = opts or {}
    local id = require_id(opts, 3)
    local surfaces = {}
    local common = {
        widget_id = id,
        role = opts.role or defaults and defaults.role or "textbox",
        label = opts.label,
        text_key = opts.text_key,
    }
    widget.add_surface(surfaces, "edit", id, copy_table(common))
    widget.add_surface(surfaces, "text", id, copy_table(common))
    widget.add_surface(surfaces, "focus", id, copy_table(common))
    widget.add_surface(surfaces, "input", id, copy_table(common))
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle)
    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts, defaults, kind)
    opts = opts or {}
    defaults = defaults or {}
    local id = require_id(opts, 3)
    local node = M.build_shell(opts, defaults)
    local surfaces = M.surfaces(opts, defaults)
    return widget.bundle {
        kind = kind or defaults.kind or "text_input",
        id = id,
        node = node,
        surfaces = surfaces,
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        selected = opts.selected,
        style_slots = {
            root = opts.styles or defaults.styles,
            label = opts.label_styles or defaults.label_styles,
            field = opts.field_styles or defaults.field_styles,
        },
        role = opts.role or defaults.role or "textbox",
        label = opts.label,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }
end

local function default_placeholder_style(placeholder, base, opts)
    return T.Layout.TextStyle(
        base.font_id,
        base.font_size,
        base.font_weight,
        opts.placeholder_rgba8 or 0x94a3b8ff,
        base.align,
        base.leading,
        base.tracking,
        placeholder
    )
end

local function placeholder_active(field, opts)
    local placeholder = opts.placeholder
    return placeholder ~= nil and placeholder ~= ""
       and ui_text_field.text(field) == ""
       and field.composition_text == ""
end

local function overlay_opts_for_hit(hit, opts)
    local out = copy_table(opts)
    out.x = hit.x
    out.y = hit.y
    out.w = hit.w
    out.h = hit.h
    return out
end

local function draw_placeholder(host, field, hit, opts, resolved)
    if not placeholder_active(field, opts) then return end

    local overlay_opts = overlay_opts_for_hit(hit, opts)
    local base_style = resolved.text_style or (overlay_opts.text_style and overlay_opts.text_style(field, overlay_opts))
    if base_style == nil then return end

    local placeholder = opts.placeholder
    local style
    if opts.placeholder_style ~= nil then
        style = opts.placeholder_style(placeholder, base_style, field, overlay_opts)
    else
        style = default_placeholder_style(placeholder, base_style, overlay_opts)
    end

    local placeholder_field = ui_text_field.state(placeholder, 0, 0, {
        focused = false,
    })

    local placeholder_opts = copy_table(overlay_opts)
    placeholder_opts.text_style = function()
        return style
    end
    placeholder_opts.show_caret = false
    placeholder_opts.apply_text_input_rect = false
    placeholder_opts.bg_rgba8 = nil
    placeholder_opts.border_rgba8 = nil
    placeholder_opts.focus_border_rgba8 = nil
    placeholder_opts.selection_opacity = 0
    placeholder_opts.selection_rgba8 = 0x00000000
    placeholder_opts.composition_rgba8 = 0x00000000
    placeholder_opts.composition_underline_rgba8 = 0x00000000

    local placeholder_resolved = text_field_view.resolve(host, placeholder_field, placeholder_opts)
    text_field_view.draw(host, placeholder_field, placeholder_resolved, placeholder_opts)
end

function M.draw_overlay(host, report, field, opts)
    opts = opts or {}
    local id = require_id(opts, 3)
    local hit = M.find_hit_box(report, id)
    if hit == nil then return nil end

    local draw_host, owner = host_for_text(host)
    local overlay_opts = overlay_opts_for_hit(hit, opts)
    overlay_opts.text_key = text_key_for(owner, overlay_opts)
    if overlay_opts.apply_text_input_rect == nil then
        overlay_opts.apply_text_input_rect = field.focused == true
    end

    if opts.manage_text_input ~= false then
        if field.focused then
            set_text_input(draw_host, true)
        elseif opts.stop_text_input_on_blur == true then
            set_text_input(draw_host, false)
        end
    end

    local resolved = text_field_view.resolve(draw_host, field, overlay_opts)
    draw_placeholder(draw_host, field, hit, overlay_opts, resolved)
    text_field_view.draw(draw_host, field, resolved, overlay_opts)

    return {
        id = id,
        hit = hit,
        resolved = resolved,
        placeholder = placeholder_active(field, overlay_opts),
        text_key = overlay_opts.text_key,
        text_input_active = field.focused == true,
        text_input_rect = field.focused and ui_text_field.input_rect(resolved.layout, field, resolved.content_x, resolved.content_y, overlay_opts.caret_w or 1) or nil,
    }
end

function M.contains(result, x, y)
    if result == nil or result.resolved == nil then return false end
    return text_field_view.contains(result.resolved, x, y)
end

function M.local_point(result, x, y)
    if result == nil or result.resolved == nil then return nil, nil end
    return text_field_view.local_point(result.resolved, x, y)
end

M.T = T

return M
