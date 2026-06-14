local meter = require("ui.widgets.meter")

local M = {}

local function with_progress(opts)
    opts = opts or {}
    local out = {}
    for k, v in pairs(opts) do out[k] = v end
    out.kind = out.kind or "progress"
    out.role = out.role or "progressbar"
    out.peak = nil
    out.hold = nil
    out.redraw = out.redraw or "on_change"
    return out
end

function M.normalized(value, opts) return meter.normalized(value, opts) end
function M.program(opts) return meter.program(with_progress(opts)) end
function M.node(opts) return meter.node(with_progress(opts)) end
function M.surfaces(opts) return meter.surfaces(with_progress(opts)) end
function M.route_one(surfaces, ui_event, bundle) return meter.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return meter.bundle(with_progress(opts)) end

M.DEFAULTS = meter.DEFAULTS
M.T = meter.T

return M
