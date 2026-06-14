local slider = require("ui.widgets.slider")

local M = {}

local function with_fader(opts)
    opts = opts or {}
    local out = {}
    for k, v in pairs(opts) do out[k] = v end
    out.kind = out.kind or "fader"
    out.orientation = out.orientation or "vertical"
    return out
end

function M.node(opts) return slider.node(with_fader(opts)) end
function M.surfaces(opts) return slider.surfaces(with_fader(opts)) end
function M.route_one(surfaces, ui_event, bundle) return slider.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return slider.bundle(with_fader(opts)) end

M.DEFAULTS = slider.DEFAULTS
M.T = slider.T

return M
