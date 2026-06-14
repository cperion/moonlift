local menu = require("ui.widgets.menu")

local M = {}

function M.node(opts) return menu.node(menu.select_opts(opts)) end
function M.surfaces(opts) return menu.surfaces(menu.select_opts(opts)) end
function M.route_one(surfaces, ui_event, bundle) return menu.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return menu.bundle(menu.select_opts(opts)) end

M.DEFAULTS = menu.SELECT_DEFAULTS
M.T = menu.T

return M
