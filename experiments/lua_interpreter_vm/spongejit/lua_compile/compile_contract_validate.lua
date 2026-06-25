-- compile_contract_validate.lua -- executable contract structural validation.

local pvm = require("lalin.pvm")
local Schema = require("lua_compile.schema")
local T = Schema.get()
local CallModel = require("lua_compile.lua_rt_call_model")
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local StaticRegionModel = require("lua_compile.lua_exec_static_region_model")

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end
local function is(v, cls) return pvm.classof(v) == cls end
local function member(v, family)
  return family and family.members and family.members[pvm.classof(v)]
end

local function validate_deps(errors, deps, path)
  for i, d in ipairs(deps or {}) do
    if not member(d, T.LuaFact.Dependency) then add(errors, path .. ".deps[" .. i .. "] must be LuaFact.Dependency") end
  end
end

local function validate_fact_use(errors, f, path)
  if not is(f, T.CompileContract.FactUse) then
    add(errors, path .. " must be CompileContract.FactUse")
    return
  end
  if not member(f.role, T.CompileContract.FactRole) then add(errors, path .. ".role must be CompileContract.FactRole") end
  if not member(f.subject, T.LuaFact.Subject) then add(errors, path .. ".subject must be LuaFact.Subject") end
  if not member(f.predicate, T.LuaFact.Predicate) then add(errors, path .. ".predicate must be LuaFact.Predicate") end
  if type(f.value_key) ~= "string" then add(errors, path .. ".value_key must be string") end
  validate_deps(errors, f.deps, path)
end

local function validate_payload_use(errors, p, path)
  if not is(p, T.CompileContract.PayloadUse) then
    add(errors, path .. " must be CompileContract.PayloadUse")
    return
  end
  if not member(p.payload, T.LuaFact.PayloadLease) then add(errors, path .. ".payload must be LuaFact.PayloadLease") end
end

local function validate_region_descriptor(errors, d, path)
  if not is(d, T.LuaExec.RegionDescriptor) then
    add(errors, path .. " must be LuaExec.RegionDescriptor")
    return
  end
  if not is(d.id, T.LuaExec.RegionId) then add(errors, path .. ".id must be LuaExec.RegionId") end
  if not member(d.kind, T.LuaExec.RegionKind) then add(errors, path .. ".kind must be LuaExec.RegionKind") end
  if not member(d.family, T.LuaExec.OpcodeFamily) then add(errors, path .. ".family must be LuaExec.OpcodeFamily") end
  if not is(d.start_pc, T.LuaRT.Pc) then add(errors, path .. ".start_pc must be LuaRT.Pc") end
  if not is(d.end_pc, T.LuaRT.Pc) then add(errors, path .. ".end_pc must be LuaRT.Pc") end
end

local function validate_semantic_assumption(errors, a, path)
  if not member(a, T.CompileContract.SemanticAssumption) then
    add(errors, path .. " must be CompileContract.SemanticAssumption")
    return
  end
  local cls = pvm.classof(a)
  if cls == T.CompileContract.AssumesCallTarget then
    if not is(a.target, T.LuaRT.CallTarget) then add(errors, path .. ".target must be LuaRT.CallTarget") end
  elseif cls == T.CompileContract.AssumesArityShape then
    if not is(a.shape, T.LuaRT.ArityShape) then add(errors, path .. ".shape must be LuaRT.ArityShape") end
  elseif cls == T.CompileContract.AssumesMetatable then
    if not member(a.value, T.LuaRT.ValueRef) then add(errors, path .. ".value must be LuaRT.ValueRef") end
    if not member(a.metatable, T.LuaRT.MetatableRef) then add(errors, path .. ".metatable must be LuaRT.MetatableRef") end
  elseif cls == T.CompileContract.AssumesNoMetamethod then
    local ok, errs = LuaRTValidate.metamethod_lookup_path(a.path)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".path " .. e) end end
  elseif cls == T.CompileContract.AssumesMetatableEpoch then
    if not is(a.epoch, T.LuaRT.MetatableEpoch) then add(errors, path .. ".epoch must be LuaRT.MetatableEpoch") end
  elseif cls == T.CompileContract.AssumesMetamethodLookupPath then
    local ok, errs = LuaRTValidate.metamethod_lookup_path(a.path)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".path " .. e) end end
  elseif cls == T.CompileContract.AssumesGCEffect then
    local ok, errs = LuaRTValidate.gc_effect(a.effect)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".effect " .. e) end end
  elseif cls == T.CompileContract.AssumesRegionDescriptor then
    validate_region_descriptor(errors, a.descriptor, path .. ".descriptor")
  elseif cls == T.CompileContract.AssumesResultChannel then
    if not is(a.channel, T.LuaRT.ResultChannel) then add(errors, path .. ".channel must be LuaRT.ResultChannel") end
  elseif cls == T.CompileContract.AssumesResolvedCallTarget then
    local ok, errs = CallModel.validate_resolved_call_target(a.target)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".target " .. e) end end
  elseif cls == T.CompileContract.AssumesCallFrameLayout then
    local ok, errs = CallModel.validate_call_frame_layout(a.layout)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".layout " .. e) end end
  elseif cls == T.CompileContract.AssumesCallArgChannel then
    local ok, errs = CallModel.validate_call_arg_channel(a.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".channel " .. e) end end
  elseif cls == T.CompileContract.AssumesCallResultChannel then
    local ok, errs = CallModel.validate_call_result_channel(a.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".channel " .. e) end end
  elseif cls == T.CompileContract.AssumesCallTargetIdentity then
    local ok, errs = CallModel.validate_call_target_identity(a.identity)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".identity " .. e) end end
  elseif cls == T.CompileContract.AssumesFFILayout then
    if not is(a.type_id, T.LuaFFI.CTypeId) then add(errors, path .. ".type_id must be LuaFFI.CTypeId") end
    if type(a.layout_hash) ~= "string" or a.layout_hash == "" then add(errors, path .. ".layout_hash must be non-empty string") end
  elseif cls == T.CompileContract.AssumesResultRoute then
    local ok, errs = LuaRTValidate.result_channel(a.channel)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".channel " .. e) end end
  elseif cls == T.CompileContract.AssumesFrameEffect then
    local ok, errs = LuaRTValidate.frame_effect(a.effect)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".effect " .. e) end end
  elseif cls == T.CompileContract.AssumesClosureIdentity then
    local ok, errs = LuaRTValidate.closure_identity(a.identity)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".identity " .. e) end end
  elseif cls == T.CompileContract.AssumesUpvalueIdentity then
    local ok, errs = LuaRTValidate.upvalue_identity(a.identity)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".identity " .. e) end end
  elseif cls == T.CompileContract.AssumesStaticRegion then
    local ok, errs = StaticRegionModel.validate_static_region_binding(a.binding)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".binding " .. e) end end
  elseif cls == T.CompileContract.AssumesStaticRegionInvocation then
    local ok, errs = StaticRegionModel.validate_static_region_invocation(a.invocation)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".invocation " .. e) end end
  elseif cls == T.CompileContract.AssumesCallContinuationRegion then
    local ok, errs = StaticRegionModel.validate_call_continuation_region(a.region)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".region " .. e) end end
  elseif cls == T.CompileContract.AssumesModuleDescriptor then
    if not is(a.descriptor, T.LuaExec.ModuleDescriptor) then add(errors, path .. ".descriptor must be LuaExec.ModuleDescriptor") end
  elseif cls == T.CompileContract.AssumesLuaOperation then
    local ok, errs = LuaRTValidate.lua_operation(a.operation)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".operation " .. e) end end
  elseif cls == T.CompileContract.AssumesCompanionContext then
    if not member(a.companion, T.LuaRT.CompanionContext) then add(errors, path .. ".companion must be LuaRT.CompanionContext") end
  elseif cls == T.CompileContract.AssumesLoopTopology then
    local ok, errs = LuaRTValidate.loop_topology(a.topology)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".topology " .. e) end end
  elseif cls == T.CompileContract.AssumesClosePlan then
    local ok, errs = LuaRTValidate.close_plan(a.plan)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".plan " .. e) end end
  elseif cls == T.CompileContract.AssumesOutcomeCause then
    local ok, errs = LuaRTValidate.outcome_cause(a.cause)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".cause " .. e) end end
  elseif cls == T.CompileContract.AssumesGCObjectEpoch then
    if not member(a.fact, T.LuaGC.GCFact) then add(errors, path .. ".fact must be LuaGC.GCFact") end
  elseif cls == T.CompileContract.AssumesFinalizer then
    if not is(a.finalizer, T.LuaGC.FinalizerRef) then add(errors, path .. ".finalizer must be LuaGC.FinalizerRef") end
  elseif cls == T.CompileContract.AssumesFFICallShape then
    local ok, errs = LuaRTValidate.ffi_call_shape(a.call)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".call " .. e) end end
  elseif cls == T.CompileContract.AssumesFFICallbackEntry then
    local ok, errs = LuaRTValidate.ffi_callback_entry(a.callback)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".callback " .. e) end end
  elseif cls == T.CompileContract.AssumesCDataOwnership then
    local ok, errs = LuaRTValidate.cdata_ownership_transition(a.transition)
    if not ok then for _, e in ipairs(errs) do add(errors, path .. ".transition " .. e) end end
  end
end

local function validate_obligation(errors, o, path)
  if not member(o, T.CompileContract.Obligation) then
    add(errors, path .. " must be CompileContract.Obligation")
    return
  end
  local cls = pvm.classof(o)
  if cls == T.CompileContract.RequiresFact then validate_fact_use(errors, o.fact, path .. ".fact")
  elseif cls == T.CompileContract.RequiresPayload then validate_payload_use(errors, o.payload, path .. ".payload")
  elseif cls == T.CompileContract.RequiresRuntimeGuard then
    if not member(o.guard, T.LuaRT.Guard) then add(errors, path .. ".guard must be LuaRT.Guard") end
  elseif cls == T.CompileContract.RequiresExecObligation then
    if not member(o.obligation, T.LuaExec.Obligation) then add(errors, path .. ".obligation must be LuaExec.Obligation") end
  elseif cls == T.CompileContract.RequiresCompanion then
    if not is(o.pc, T.LuaRT.Pc) then add(errors, path .. ".pc must be LuaRT.Pc") end
    if not member(o.kind, T.LuaRT.CompanionKind) then add(errors, path .. ".kind must be LuaRT.CompanionKind") end
  elseif cls == T.CompileContract.RequiresResolvedRegion then
    if not is(o.region, T.LuaExec.Name) then add(errors, path .. ".region must be LuaExec.Name") end
  elseif cls == T.CompileContract.RequiresContinuation then
    if not is(o.continuation, T.LuaExec.ContRef) then add(errors, path .. ".continuation must be LuaExec.ContRef") end
  elseif cls == T.CompileContract.RequiresSemanticAssumption then
    validate_semantic_assumption(errors, o.assumption, path .. ".assumption")
  end
end

local function validate_guarantee(errors, g, path)
  if not member(g, T.CompileContract.Guarantee) then
    add(errors, path .. " must be CompileContract.Guarantee")
    return
  end
  local cls = pvm.classof(g)
  if cls == T.CompileContract.GuaranteesFact then validate_fact_use(errors, g.fact, path .. ".fact")
  elseif cls == T.CompileContract.GuaranteesExec then
    if not member(g.guarantee, T.LuaExec.Guarantee) then add(errors, path .. ".guarantee must be LuaExec.Guarantee") end
  elseif cls == T.CompileContract.ProducesRuntimeValue then
    if not member(g.value, T.LuaRT.ValueRef) then add(errors, path .. ".value must be LuaRT.ValueRef") end
  elseif cls == T.CompileContract.PreservesRuntimeFrame then
    if not is(g.frame, T.LuaRT.FrameRef) then add(errors, path .. ".frame must be LuaRT.FrameRef") end
  elseif cls == T.CompileContract.UpdatesRuntimeTop then
    if not is(g.top, T.LuaRT.TopRef) then add(errors, path .. ".top must be LuaRT.TopRef") end
  elseif cls == T.CompileContract.GuaranteesSemanticAssumption then
    validate_semantic_assumption(errors, g.assumption, path .. ".assumption")
  end
end

function M.validate(contract)
  local errors = {}
  if not is(contract, T.CompileContract.Contract) then
    return false, { "expected CompileContract.Contract" }
  end
  if not is(contract.transfer, T.CompileContract.Transfer) then add(errors, "contract transfer must be CompileContract.Transfer") end
  for i, f in ipairs((contract.transfer and contract.transfer.facts) or {}) do
    validate_fact_use(errors, f, "transfer.facts[" .. i .. "]")
  end
  for i, p in ipairs((contract.transfer and contract.transfer.payloads) or {}) do
    validate_payload_use(errors, p, "transfer.payloads[" .. i .. "]")
  end
  for i, o in ipairs(contract.obligations or {}) do validate_obligation(errors, o, "obligations[" .. i .. "]") end
  for i, g in ipairs(contract.guarantees or {}) do validate_guarantee(errors, g, "guarantees[" .. i .. "]") end
  validate_deps(errors, contract.dependencies, "contract")
  return #errors == 0, errors
end

return M
