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
M.asdl_model = require("moonlift.asdl_model")
M.asdl_builder = require("moonlift.asdl_builder")
M.asdl_emit = require("moonlift.asdl_emit")
M.asdl_legacy_import = require("moonlift.asdl_legacy_import")
M.asdl_data = require("moonlift.asdl_data")
M.context_define_schema = require("moonlift.context_define_schema")
M.phase_model = require("moonlift.phase_model")
M.phase_builder = require("moonlift.phase_builder")
M.quote = require("moonlift.quote")
M.ast = require("moonlift.ast")
M.back_program = require("moonlift.back_program")
M.back_command_tape = require("moonlift.back_command_tape")
M.back_target_model = require("moonlift.back_target_model")
M.back_inspect = require("moonlift.back_inspect")
M.back_diagnostics = require("moonlift.back_diagnostics")
M.back_object = require("moonlift.back_object")
M.link_target_model = require("moonlift.link_target_model")
M.link_plan_validate = require("moonlift.link_plan_validate")
M.link_command_plan = require("moonlift.link_command_plan")
M.link_execute = require("moonlift.link_execute")
M.vec_inspect = require("moonlift.vec_inspect")
M.std = require("moonlift.std")
M.json = M.std.json
M.builtins = M.std.builtins
M.views = M.std.views
M.buffer_view = M.std.buffer_view
M.host = M.std.host
M.mlua = M.std.mlua
M.lsp = require("moonlift.rpc_stdio_loop")

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
