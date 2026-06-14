local b = require("ui.build")
local tw = require("ui.tw")
local property_row = require("ui.widgets.property_row")
local widget = require("ui.widget")

local M = {}

local DEFAULTS = {
    kind = "form_field",
    role = "group",
    message_styles = tw.list { tw.text_xs, tw.fg.slate[500] },
    error_styles = tw.list { tw.text_xs, tw.fg.red[400] },
}

local function with_form_field(opts)
    opts = opts or {}
    local out = {}
    for k, v in pairs(opts) do out[k] = v end
    out.kind = out.kind or DEFAULTS.kind
    out.role = out.role or DEFAULTS.role
    if opts.message ~= nil or opts.error ~= nil then
        local id = widget.require_id(opts.id, "form_field id")
        local child = opts.control or opts.child
        local children = {}
        if child ~= nil then children[#children + 1] = child end
        local msg = opts.error or opts.message
        children[#children + 1] = b.text {
            b.id(widget.key(widget.child_id(id, opts.error and "error" or "message"))),
            opts.error and (opts.error_styles or DEFAULTS.error_styles) or (opts.message_styles or DEFAULTS.message_styles),
            tostring(msg),
        }
        out.control = b.box { b.id(widget.key(widget.child_id(id, "field-control"))), tw.flex, tw.col, tw.gap_y_1, unpack(children) }
    end
    return out
end

function M.node(opts) return property_row.node(with_form_field(opts)) end
function M.surfaces(opts) return property_row.surfaces(with_form_field(opts)) end
function M.route_one(surfaces, ui_event, bundle) return property_row.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts)
    local bundle = property_row.bundle(with_form_field(opts))
    bundle.kind = (opts and opts.kind) or DEFAULTS.kind
    return bundle
end

M.DEFAULTS = DEFAULTS
M.T = property_row.T
return M
