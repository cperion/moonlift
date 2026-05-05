-- Public Moonlift Lua facade.
--
-- The PVM/ASDL implementation is internal to the moonlift package and exposed
-- through this namespace. Prefer `require("moonlift.pvm")` or this facade.

local M = {}

M.pvm = require("moonlift.pvm")
M.triplet = require("moonlift.triplet")
M.asdl_context = require("moonlift.asdl_context")
M.asdl_lexer = require("moonlift.asdl_lexer")
M.asdl_parser = require("moonlift.asdl_parser")
M.asdl_model = require("moonlift.asdl_model")
M.asdl_builder = require("moonlift.asdl_builder")
M.schema = require("moonlift.schema")
M.context_define_schema = require("moonlift.context_define_schema")
M.phase_model = require("moonlift.phase_model")
M.phase_builder = require("moonlift.phase_builder")
M.pvm_surface_model = require("moonlift.pvm_surface_model")
M.pvm_surface_builder = require("moonlift.pvm_surface_builder")
M.pvm_surface_region_values = require("moonlift.pvm_surface_region_values")
M.pvm_surface_schema_values = require("moonlift.pvm_surface_schema_values")
M.pvm_surface_cache_values = require("moonlift.pvm_surface_cache_values")
M.pvm_surface_union_values = require("moonlift.pvm_surface_union_values")
M.type_ref_classify_surface = require("moonlift.type_ref_classify_surface")
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
M.region_compose = require("moonlift.region_compose")
M.parser_compose = require("moonlift.parser_compose")
M.std = require("moonlift.std")
M.json = M.std.json
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

return M
