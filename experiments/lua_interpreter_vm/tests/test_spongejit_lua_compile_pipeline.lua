#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local LuaExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local LuaExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")

local unit = C.unit_from_events({ {op="LOADI",pc=1,a=1,b=9}, {op="RETURN1",pc=2,a=1} }, {})
local pvm = require("moonlift.pvm")
local T = require("lua_compile.schema").get()
local exec = LuaExecLower.lower(unit.source, unit.evidence)
assert(exec and pvm.classof(exec) == T.LuaExec.Kernel, "LuaExec lowering must own public MoonKernel fixture")
local mk = C.compile_to_moon_kernel(unit)
assert(mk.kind == "Ok" and mk.product.kind == "MoonKernel")
assert(pvm.classof(mk.product.kernel) == T.MoonCFG.Kernel)
assert(pvm.classof(mk.product.kernel.contract) == T.CompileContract.Contract)
assert(mk.product.kernel.id.name.text == "lua_exec_core_kernel", "MoonKernel success must route through LuaExec")
assert(mk.product.kernel["normal" .. "_form"] == nil, "MoonCFG kernel must not carry retired executable payloads")
local mk2 = C.compile_to_moon_kernel(unit)
assert(mk2.product.kernel == mk.product.kernel, "MoonKernel compile must return the same interned product for the same unit")
assert(LuaExecLower.lower(unit.source, unit.evidence) == exec)
local cfg = LuaExecToMoon.lower(exec)
assert(LuaExecToMoon.lower(exec) == cfg)
local outcome_cfg = LuaExecToMoon.lower(exec, { outcome = true, outcome_projection = "kind" })
assert(LuaExecToMoon.lower(exec, { outcome = true, outcome_projection = "kind" }) == outcome_cfg)

-- LuaCompile file manifest.  MoonCFG semantic execution is quote-first
-- (`moon_cfg_quote_emit.lua` via `moon_cfg_emit.compile/build/run`); the
-- hand-concatenating `moon_cfg_emit_source_compat.lua` renderer is retained for
-- compatibility/debug serialization through `moon_cfg_emit.emit` and foundry
-- source artifacts only.
local planned = {
"builders.lua", "compile_contract_key.lua", "compile_contract_validate.lua", "diagnostics.lua", "errors.lua", "init.lua", "lua_compile_foundry.lua", "lua_compile_to_moon_kernel.lua", "lua_compile_unit.lua", "lua_compile_validate.lua", "lua_exec_region_model.lua", "lua_exec_static_region_inline.lua", "lua_exec_static_region_model.lua", "lua_exec_to_moon_cfg_lower.lua", "lua_exec_validate.lua", "lua_fact_closure.lua", "lua_fact_contradiction.lua", "lua_fact_from_foundry_bundle.lua", "lua_fact_from_runtime_observe.lua", "lua_fact_payload_lease.lua", "lua_fact_validate.lua", "lua_ffi_validate.lua", "lua_gc_validate.lua", "lua_region_validate.lua", "lua_rt_arity_model.lua", "lua_rt_call_model.lua", "lua_rt_cdata_model.lua", "lua_rt_close_model.lua", "lua_rt_closure_upvalue_model.lua", "lua_rt_gc_alloc_model.lua", "lua_rt_loop_model.lua", "lua_rt_metatable_model.lua", "lua_rt_operation_model.lua", "lua_rt_object_model.lua", "lua_rt_outcome_model.lua", "lua_rt_stack_model.lua", "lua_rt_validate.lua", "lua_rt_value_model.lua", "lua_src_call_static_model.lua", "lua_src_closure_static_model.lua", "lua_src_from_puc_decode.lua", "lua_src_slot_alias.lua", "lua_src_to_lua_exec_lower.lua", "lua_src_to_lua_region_recognize.lua", "lua_src_validate.lua", "lua_src_window_collect.lua", "moon_cfg_abi.lua", "moon_cfg_emit.lua", "moon_cfg_emit_source_compat.lua", "moon_cfg_key.lua", "moon_cfg_quote_emit.lua", "moon_cfg_validate.lua", "schema.lua", "stencil_bank.lua", "stencil_bundle.lua", "stencil_foundry.lua", "stencil_key.lua", "stencil_manifest.lua", "stencil_materialization_plan.lua", "stencil_materialize.lua", "stencil_object_extract.lua", "stencil_validate.lua", "validate.lua" }
local seen = {}
for _, f in ipairs(planned) do seen[f] = true end
local p = io.popen("find experiments/lua_interpreter_vm/spongejit/lua_compile -maxdepth 1 -type f -printf '%f\\n' | sort")
local count = 0
for f in p:lines() do
  count = count + 1
  assert(seen[f], "unplanned LuaCompile file remains: " .. f)
  seen[f] = nil
  assert(not f:match("lua" .. "_sem"), "retired file remains: " .. f)
  assert(not f:match("lua" .. "_nf"), "retired file remains: " .. f)
  assert(not f:match("lua" .. "_contract"), "retired file remains: " .. f)
  assert(not f:match("lua" .. "_place"), "retired file remains: " .. f)
  assert(not f:match("normal" .. "_form"), "retired file remains: " .. f)
  assert(not f:match("moon" .. "_cfg_closed"), "retired file remains: " .. f)
  local forbidden_versioned_name = "ssa" .. "2"
  assert(not f:match(forbidden_versioned_name), "versioned rewrite name forbidden")
end
p:close()
for f in pairs(seen) do error("planned LuaCompile file missing: " .. f) end
assert(count == #planned)
print("ok - SpongeJIT LuaCompile pipeline")
