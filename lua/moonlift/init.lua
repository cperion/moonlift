-- Public Moonlift Lua facade.
--
-- The PVM/ASDL implementation is internal to the moonlift package and exposed
-- through this namespace.  Prefer `require("moonlift.pvm")` or this facade over
-- root-level compatibility shims.

local M = {}

M.pvm = require("moonlift.pvm")
M.triplet = require("moonlift.triplet")
M.asdl_context = require("moonlift.asdl_context")
M.asdl_lexer = require("moonlift.asdl_lexer")
M.asdl_parser = require("moonlift.asdl_parser")
M.quote = require("moonlift.quote")
M.std = require("moonlift.std")
M.json = M.std.json
M.builtins = M.std.builtins
M.views = M.std.views
M.buffer_view = M.std.buffer_view
M.host = M.std.host
M.mlua = M.std.mlua

function M.context(opts)
    return M.pvm.context(opts)
end

function M.Define(T)
    return require("moonlift.asdl").Define(T)
end

function M.host_quote()
    return M.mlua
end

return M
