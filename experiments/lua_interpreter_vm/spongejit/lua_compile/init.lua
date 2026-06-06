-- lua_compile/init.lua -- public facade for the SpongeJIT LuaCompile rewrite.

local M = {}

M.schema = require("lua_compile.schema")
M.builders = require("lua_compile.builders")
M.validate = require("lua_compile.validate")
M.diagnostics = require("lua_compile.diagnostics")
M.errors = require("lua_compile.errors")

M.lua_compile_unit = require("lua_compile.lua_compile_unit")
M.lua_compile_to_moon_kernel = require("lua_compile.lua_compile_to_moon_kernel")
M.lua_compile_validate = require("lua_compile.lua_compile_validate")
M.moon_cfg_abi = require("lua_compile.moon_cfg_abi")
M.moon_cfg_validate = require("lua_compile.moon_cfg_validate")
M.moon_cfg_emit = require("lua_compile.moon_cfg_emit")
M.lua_rt_value_model = require("lua_compile.lua_rt_value_model")
M.lua_rt_outcome_model = require("lua_compile.lua_rt_outcome_model")
M.lua_rt_stack_model = require("lua_compile.lua_rt_stack_model")
M.lua_rt_object_model = require("lua_compile.lua_rt_object_model")
M.lua_rt_cdata_model = require("lua_compile.lua_rt_cdata_model")
M.lua_rt_arity_model = require("lua_compile.lua_rt_arity_model")
M.lua_rt_call_model = require("lua_compile.lua_rt_call_model")
M.lua_rt_metatable_model = require("lua_compile.lua_rt_metatable_model")
M.lua_rt_operation_model = require("lua_compile.lua_rt_operation_model")
M.lua_rt_close_model = require("lua_compile.lua_rt_close_model")
M.lua_rt_gc_alloc_model = require("lua_compile.lua_rt_gc_alloc_model")
M.lua_rt_closure_upvalue_model = require("lua_compile.lua_rt_closure_upvalue_model")
M.lua_rt_loop_model = require("lua_compile.lua_rt_loop_model")
M.lua_exec_region_model = require("lua_compile.lua_exec_region_model")
M.lua_src_to_lua_exec_lower = require("lua_compile.lua_src_to_lua_exec_lower")
M.lua_exec_to_moon_cfg_lower = require("lua_compile.lua_exec_to_moon_cfg_lower")
M.compile_contract_key = require("lua_compile.compile_contract_key")
M.compile_contract_validate = require("lua_compile.compile_contract_validate")
M.lua_ffi_validate = require("lua_compile.lua_ffi_validate")
M.lua_gc_validate = require("lua_compile.lua_gc_validate")
M.lua_rt_validate = require("lua_compile.lua_rt_validate")
M.lua_exec_validate = require("lua_compile.lua_exec_validate")
M.stencil_key = require("lua_compile.stencil_key")
M.stencil_validate = require("lua_compile.stencil_validate")
M.stencil_materialization_plan = require("lua_compile.stencil_materialization_plan")
M.stencil_materialize = require("lua_compile.stencil_materialize")
M.stencil_bank = require("lua_compile.stencil_bank")
M.stencil_bundle = require("lua_compile.stencil_bundle")
M.stencil_manifest = require("lua_compile.stencil_manifest")
M.stencil_foundry = require("lua_compile.stencil_foundry")
M.stencil_object_extract = require("lua_compile.stencil_object_extract")

function M.unit_from_events(events, observations)
  return M.lua_compile_unit.from_events(events, observations)
end

function M.compile_to_moon_kernel(unit)
  return M.lua_compile_to_moon_kernel.compile(unit)
end

return M
