local b = require("ui.build")
local tw = require("ui.tw")
local widget = require("ui.widget")
local ids = require("ui.id")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Style = T.Style
local Interact = T.Interact

local M = {}

local DEFAULTS = {
    kind = "scroll_panel",
    role = "scroll_panel",
    axis = Style.ScrollY,
    styles = tw.list {
        tw.flex,
        tw.col,
        tw.gap_y_2,
        tw.p_2,
        tw.rounded_lg,
        tw.border_1,
        tw.border_color.slate[800],
        tw.bg.slate[950],
        tw.overflow_y_auto,
    },
    content_styles = tw.list { tw.flex, tw.col, tw.gap_y_2 },
}

local function id_key(id) return ids.key(id) end
local function child_id(id, suffix) return widget.child_id(id, suffix) end
local function add_style(items, value) if value ~= nil and value ~= false then items[#items + 1] = value end end

local function axis_from_opts(opts)
    if opts.axis ~= nil then return opts.axis end
    if opts.scroll_x and opts.scroll_y then return Style.ScrollBoth end
    if opts.scroll_x then return Style.ScrollX end
    return DEFAULTS.axis
end

function M.node(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "scroll_panel id")
    local content_items = { b.id(id_key(child_id(id, "content"))) }
    add_style(content_items, DEFAULTS.content_styles)
    add_style(content_items, opts.content_styles)
    if opts.children ~= nil then for i = 1, #opts.children do content_items[#content_items + 1] = opts.children[i] end
    elseif opts.child ~= nil then content_items[#content_items + 1] = opts.child end

    local scroll = b.scroll(child_id(id, "scroll"), axis_from_opts(opts), { b.box(content_items) })
    local shell = { b.id(id_key(child_id(id, "box"))) }
    add_style(shell, DEFAULTS.styles)
    add_style(shell, opts.styles)
    shell[#shell + 1] = scroll
    local node = b.with_input(id, opts.disabled and Interact.Passive or Interact.HitTarget, b.box(shell))
    if opts.validate_ids ~= false then ids.assert_auth(node, opts.id_opts) end
    return node
end

function M.surfaces(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "scroll_panel id")
    local surfaces = {}
    widget.add_surface(surfaces, "input", id, { widget_id = id, role = opts.role or DEFAULTS.role, label = opts.label })
    widget.add_surface(surfaces, "scroll", child_id(id, "scroll"), { widget_id = id, role = "scroll", axis = axis_from_opts(opts), label = opts.label })
    return surfaces
end

function M.route_one(surfaces, ui_event, bundle) return widget.route_interact_event(surfaces, ui_event, bundle) end

function M.bundle(opts)
    opts = opts or {}
    local id = widget.require_id(opts.id, "scroll_panel id")
    return widget.bundle {
        kind = opts.kind or DEFAULTS.kind,
        id = id,
        node = M.node(opts),
        surfaces = M.surfaces(opts),
        model = opts.model,
        events = opts.events,
        disabled = opts.disabled,
        axis = axis_from_opts(opts),
        scroll_id = child_id(id, "scroll"),
        style_slots = { root = opts.styles or DEFAULTS.styles, content = opts.content_styles or DEFAULTS.content_styles },
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
