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
    kind = "panel",
    role = "group",
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.gap_y_2,
        tw.p_3,
        tw.rounded_lg,
        tw.border_1,
        tw.border_color.slate[800],
        tw.bg.slate[950],
        tw.fg.slate[100],
    },
    title_styles = tw.list { tw.text_sm, tw.font_semibold, tw.fg.white },
    body_styles = nil,
}

local function copy_table(src)
    local out = {}
    if src ~= nil then for k, v in pairs(src) do out[k] = v end end
    return out
end

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end
local function add_style(items, value) if value ~= nil and value ~= false then items[#items + 1] = value end end

local function state_for(id, opts)
    opts = opts or {}
    local explicit = opts.state
    if opts.model == nil and opts.interact_model == nil and opts.report == nil and opts.selected == nil and opts.disabled == nil and opts.active == nil then return explicit end
    local bridge_opts = copy_table(opts)
    local key = id_key(id)
    if type(bridge_opts.selected) == "boolean" then bridge_opts.selected = { [key] = bridge_opts.selected } end
    if type(bridge_opts.disabled) == "boolean" then bridge_opts.disabled = { [key] = bridge_opts.disabled } end
    if type(bridge_opts.active) == "boolean" then bridge_opts.active = { [key] = bridge_opts.active } end
    local derived = state_bridge.for_id(id, opts.model or opts.interact_model, opts.report, bridge_opts)
    if explicit ~= nil then return state_bridge.merge(derived, explicit) end
    return derived
end

local function append_children(items, opts, defaults)
    if opts.title ~= nil and opts.title ~= false then
        items[#items + 1] = b.text { b.id(id_key(child_id(opts.id, "title"))), defaults.title_styles, opts.title_styles, tostring(opts.title) }
    end
    if opts.children ~= nil then
        for i = 1, #opts.children do items[#items + 1] = opts.children[i] end
    elseif opts.child ~= nil then
        items[#items + 1] = opts.child
    elseif opts.body ~= nil then
        if type(opts.body) == "string" or type(opts.body) == "number" then
            items[#items + 1] = b.text { b.id(id_key(child_id(opts.id, "body"))), defaults.body_styles, opts.body_styles, tostring(opts.body) }
        else
            items[#items + 1] = opts.body
        end
    end
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "panel id")
    local defaults = opts.defaults or DEFAULTS
    local items = { b.id(id_key(child_id(id, "box"))) }
    add_style(items, defaults.styles)
    add_style(items, opts.styles)
    append_children(items, opts, defaults)
    local child = b.box(items)
    local state = state_for(id, opts)
    if state ~= nil and not state_bridge.is_empty(state) then child = b.with_state(state, child) end
    local node = b.with_input(id, opts.disabled and Interact.Passive or Interact.HitTarget, child)
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "panel id")
    local surfaces = {}
    widget.add_surface(surfaces, "input", id, { widget_id = id, role = opts.role or DEFAULTS.role, label = opts.label or opts.title })
    widget.add_surface(surfaces, "panel", id, { widget_id = id, role = opts.role or DEFAULTS.role, label = opts.label or opts.title })
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle)
    return widget.route_interact_event(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "panel id")
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        selected = opts.selected,
        style_slots = { root = opts.styles or DEFAULTS.styles, title = opts.title_styles or DEFAULTS.title_styles, body = opts.body_styles or DEFAULTS.body_styles },
        role = opts.role or DEFAULTS.role,
        label = opts.label or opts.title,
        description = opts.description,
        metadata = opts.metadata,
        route_one = M.route_one,
        validate = opts.validate_bundle == true,
    }
end

M.DEFAULTS = DEFAULTS
M.T = T
return M
