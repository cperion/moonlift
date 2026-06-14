local list = require("ui.widgets.list")

local M = {}

function M.node(opts) return list.node(list.listbox_opts(opts)) end
function M.surfaces(opts) return list.surfaces(list.listbox_opts(opts)) end
function M.route_one(surfaces, ui_event, bundle) return list.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return list.bundle(list.listbox_opts(opts)) end

M.DEFAULTS = list.LISTBOX_DEFAULTS
M.T = list.T

return M
