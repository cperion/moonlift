-- MoonLift standard library facade.

local M = {}

M.pvm = require("moonlift.pvm")
M.host = require("moonlift.host")
M.mlua = require("moonlift.mlua_run")
M.views = require("moonlift.buffer_view")
M.buffer_view = M.views
M.region_compose = require("moonlift.region_compose")
M.lua_raw = require("moonlift.lua_raw")
M.lua_bridge_model = require("moonlift.lua_bridge_model")

return M
