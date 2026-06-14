local slider = require("ui.widgets.slider")
local tw = require("ui.tw")

local M = {}

local DEFAULTS = {
    styles = tw.list {
        tw.flex,
        tw.row,
        tw.items_center,
        tw.gap_x_2,
        tw.px_2,
        tw.py_1,
        tw.rounded,
        tw.bg.slate[900],
        tw.border_1,
        tw.border_color.slate[700],
        tw.cursor_grab,
        tw.active { tw.cursor_grabbing, tw.border_color.sky[500] },
        tw.disabled { tw.opacity_50, tw.cursor_not_allowed },
    },
}

local function with_value_drag(opts)
    opts = opts or {}
    local out = {}
    for k, v in pairs(opts) do out[k] = v end
    out.kind = out.kind or "value_drag"
    out.show_value = out.show_value ~= false
    out.styles = out.styles or DEFAULTS.styles
    out.throttle_ms = out.throttle_ms or 16
    return out
end

function M.node(opts) return slider.node(with_value_drag(opts)) end
function M.surfaces(opts) return slider.surfaces(with_value_drag(opts)) end
function M.route_one(surfaces, ui_event, bundle) return slider.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return slider.bundle(with_value_drag(opts)) end

M.DEFAULTS = DEFAULTS
M.T = slider.T

return M
