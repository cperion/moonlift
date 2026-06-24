local M = require("llisle.dsl")
local engine = require("llisle.engine")

M.engine = engine
M.compile = engine.compile
M.run = engine.run

return M
