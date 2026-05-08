-- MoonLift standard library facade.

local M = {}

M.pvm = require("moonlift.pvm")
M.host = require("moonlift.host")
M.mlua = require("moonlift.mlua_run")
M.views = require("moonlift.buffer_view")
M.buffer_view = M.views
M.region_compose = require("moonlift.region_compose")
M.parser_compose = require("moonlift.parser_compose")

return M
