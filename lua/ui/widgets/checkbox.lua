local toggle = require("ui.widgets.toggle")

local M = {}

local function with_variant(opts)
    opts = opts or {}
    local out = {}
    for k, v in pairs(opts) do out[k] = v end
    out.variant = "checkbox"
    out.kind = out.kind or "checkbox"
    return out
end

function M.node(opts)
    return toggle.node(with_variant(opts))
end

function M.surfaces(opts)
    return toggle.surfaces(with_variant(opts))
end

function M.route_one(surfaces, ui_event, bundle)
    return toggle.route_one(surfaces, ui_event, bundle)
end

function M.bundle(opts)
    return toggle.bundle(with_variant(opts))
end

M.DEFAULTS = toggle.defaults_for("checkbox")
M.T = toggle.T

return M
