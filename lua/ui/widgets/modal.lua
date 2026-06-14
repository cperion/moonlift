local overlay = require("ui.widgets.overlay")

local M = {}
function M.node(opts) return overlay.node(overlay.modal_opts(opts)) end
function M.surfaces(opts) return overlay.surfaces(overlay.modal_opts(opts)) end
function M.route_one(surfaces, ui_event, bundle) return overlay.route_one(surfaces, ui_event, bundle) end
function M.bundle(opts) return overlay.bundle(overlay.modal_opts(opts)) end
M.DEFAULTS = overlay.MODAL_DEFAULTS
M.T = overlay.T
return M
