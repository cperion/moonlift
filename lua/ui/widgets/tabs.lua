local list = require("ui.widgets.list")

local M = {}

function M.node(opts) return list.node(list.tabs_opts(opts)) end
function M.surfaces(opts) return list.surfaces(list.tabs_opts(opts)) end
function M.route_one(surfaces, ui_event, bundle) return list.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return list.bundle(list.tabs_opts(opts)) end

M.DEFAULTS = list.TABS_DEFAULTS
M.T = list.T

return M
