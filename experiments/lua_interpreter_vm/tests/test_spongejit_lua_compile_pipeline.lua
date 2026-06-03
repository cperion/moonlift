#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local SemLower = require("lua_compile.lua_src_to_lua_sem_lower")
local NFNormalize = require("lua_compile.lua_sem_to_lua_nf_normalize")
local ContractDerive = require("lua_compile.lua_nf_to_lua_contract_derive")
local MoonLower = require("lua_compile.lua_nf_to_moon_cfg_lower")

local unit = C.unit_from_events({ {op="LOADI",pc=1,a=1,b=9}, {op="RETURN1",pc=2,a=1} }, {})
local nf = C.compile_to_normal_form(unit)
assert(nf.kind == "Ok" and nf.product.kind == "NormalForm")
local mk = C.compile_to_moon_kernel(unit)
assert(mk.kind == "Ok" and mk.product.kind == "MoonKernel")
local pvm = require("moonlift.pvm")
local T = require("lua_compile.schema").get()
assert(pvm.classof(mk.product.kernel) == T.MoonCFG.Kernel)
assert(pvm.classof(mk.product.kernel.contract) == T.LuaContract.Contract)
assert(mk.product.kernel.normal_form == nil, "MoonCFG kernel must not carry executable LuaNF.Program")
local nf_hits_before = C.lua_compile_to_normal_form.phase:stats().hits
assert(C.compile_to_normal_form(unit).product == nf.product, "normal-form compilation must remain available during LuaExec migration")
assert(C.lua_compile_to_normal_form.phase:stats().hits > nf_hits_before, "normal-form compilation must be a real cached PVM phase")
local moon_hits = C.lua_compile_to_moon_kernel.phase:stats().hits
local mk2 = C.compile_to_moon_kernel(unit)
assert(mk2.product.kernel == mk.product.kernel, "MoonKernel phase should return interned identical product")
assert(C.lua_compile_to_moon_kernel.phase:stats().hits > moon_hits, "MoonKernel compilation must hit the PVM phase cache")
local sem = SemLower.lower(unit.source, unit.evidence)
local sem_hits = SemLower.phase:stats().hits
assert(SemLower.lower(unit.source, unit.evidence) == sem and SemLower.phase:stats().hits > sem_hits, "LuaSrc->LuaSem must be a cached PVM phase")
local nf_again = NFNormalize.normalize(sem.program)
local nf_hits = NFNormalize.phase:stats().hits
assert(NFNormalize.normalize(sem.program) == nf_again and NFNormalize.phase:stats().hits > nf_hits, "LuaSem->LuaNF must be a cached PVM phase")
local contract_again = ContractDerive.derive(nf_again)
local contract_hits = ContractDerive.phase:stats().hits
assert(ContractDerive.derive(nf_again) == contract_again and ContractDerive.phase:stats().hits > contract_hits, "LuaNF->LuaContract must be a cached PVM phase")
local kernel_again = MoonLower.lower(nf_again, contract_again)
local lower_hits = MoonLower.phase:stats().hits
assert(MoonLower.lower(nf_again, contract_again) == kernel_again and MoonLower.phase:stats().hits > lower_hits, "LuaNF+LuaContract->MoonCFG must be a cached PVM phase")
local planned = {
"builders.lua", "diagnostics.lua", "errors.lua", "init.lua", "lua_compile_foundry.lua", "lua_compile_to_moon_kernel.lua", "lua_compile_to_normal_form.lua", "lua_compile_unit.lua", "lua_compile_validate.lua", "lua_contract_dependency.lua", "lua_contract_fact_use.lua", "lua_contract_key.lua", "lua_contract_projection.lua", "lua_contract_validate.lua", "lua_exec_to_moon_cfg_lower.lua", "lua_exec_validate.lua", "lua_fact_closure.lua", "lua_fact_contradiction.lua", "lua_fact_from_foundry_bundle.lua", "lua_fact_from_runtime_observe.lua", "lua_fact_payload_lease.lua", "lua_fact_validate.lua", "lua_ffi_validate.lua", "lua_gc_validate.lua", "lua_nf_expr_canonicalize.lua", "lua_nf_guard_reduce.lua", "lua_nf_key.lua", "lua_nf_projection_reduce.lua", "lua_nf_to_lua_contract_derive.lua", "lua_nf_to_lua_place_plan.lua", "lua_nf_to_moon_cfg_lower.lua", "lua_nf_validate.lua", "lua_nf_write_reduce.lua", "lua_place_projection_plan.lua", "lua_place_validate.lua", "lua_region_validate.lua", "lua_rt_cdata_model.lua", "lua_rt_object_model.lua", "lua_rt_validate.lua", "lua_rt_outcome_model.lua", "lua_rt_stack_model.lua", "lua_rt_value_model.lua", "lua_sem_env.lua", "lua_sem_guard.lua", "lua_sem_reject.lua", "lua_sem_to_lua_nf_normalize.lua", "lua_sem_validate.lua", "lua_sem_write.lua", "lua_src_from_puc_decode.lua", "lua_src_slot_alias.lua", "lua_src_to_lua_exec_lower.lua", "lua_src_to_lua_region_recognize.lua", "lua_src_to_lua_sem_lower.lua", "lua_src_to_moon_cfg_closed.lua", "lua_src_validate.lua", "lua_src_window_collect.lua", "moon_cfg_abi.lua", "moon_cfg_emit.lua", "moon_cfg_key.lua", "moon_cfg_validate.lua", "schema.lua", "stencil_bank.lua", "stencil_bundle.lua", "stencil_foundry.lua", "stencil_key.lua", "stencil_manifest.lua", "stencil_materialization_plan.lua", "stencil_materialize.lua", "stencil_object_extract.lua", "stencil_validate.lua", "validate.lua" }
local seen = {}
for _, f in ipairs(planned) do seen[f] = true end
local p = io.popen("find experiments/lua_interpreter_vm/spongejit/lua_compile -maxdepth 1 -type f -printf '%f\\n' | sort")
local count = 0
for f in p:lines() do
  count = count + 1
  assert(seen[f], "unplanned LuaCompile file remains: " .. f)
  seen[f] = nil
  local forbidden_versioned_name = "ssa" .. "2"
  assert(not f:match(forbidden_versioned_name), "versioned rewrite name forbidden")
end
p:close()
for f in pairs(seen) do error("planned LuaCompile file missing: " .. f) end
assert(count == #planned)
print("ok - SpongeJIT LuaCompile pipeline")
