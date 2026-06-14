local panel = require("ui.widgets.panel")
local tw = require("ui.tw")

local M = {}

local DEFAULTS = {
    kind = "toolbar",
    role = "toolbar",
    styles = tw.list {
        tw.flex,
        tw.row,
        tw.items_center,
        tw.gap_x_2,
        tw.p_2,
        tw.rounded_lg,
        tw.border_1,
        tw.border_color.slate[800],
        tw.bg.slate[950],
    },
}

local function with_toolbar(opts)
    opts = opts or {}
    local out = {}
    for k, v in pairs(opts) do out[k] = v end
    out.kind = out.kind or DEFAULTS.kind
    out.role = out.role or DEFAULTS.role
    out.styles = out.styles or DEFAULTS.styles
    return out
end

function M.node(opts) return panel.node(with_toolbar(opts)) end
function M.surfaces(opts) return panel.surfaces(with_toolbar(opts)) end
function M.route_one(surfaces, ui_event, bundle) return panel.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return panel.bundle(with_toolbar(opts)) end

M.DEFAULTS = DEFAULTS
M.T = panel.T
return M
