#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()

assert(T.LuaSrc and T.LuaFact and T.LuaRegion and T.LuaFFI and T.LuaGC and T.LuaRT and T.LuaExec and T.CompileContract and T.LalinCFG and T.Stencil and T.LuaCompile)
assert(T.LuaFact.StaticClosureTargetPayload and T.LuaFact.StaticCalleeRegionPayload and T.LuaFact.StaticClosureValuePayload)
assert(T.LuaCompile.SourceEvent and T.LuaCompile.CanonicalPucEvent and T.LuaCompile.DecodedSourceOp and T.LuaCompile.SourceEventBatch)
assert(T.LuaCompile.EvidenceRecord and T.LuaCompile.EvidenceFact and T.LuaCompile.EvidencePayload and T.LuaCompile.EvidenceInput)
assert(T.LuaCompile.ExecProduct and T.LuaCompile.ExecLowerResult and T.LuaCompile.LalinLowerResult and T.LuaCompile.StaticInlineResult)
assert(T.LuaExec.StaticCallProducts and T.LuaExec.StaticCallProductResult and T.LuaExec.StaticClosureProducts and T.LuaExec.StaticClosureProductResult)
assert(not T["Lua" .. "Sem"] and not T["Lua" .. "NF"] and not T["Lua" .. "Contract"] and not T["Lua" .. "Place"])
local function field_names(cls)
  local out = {}
  for _, f in ipairs(cls.__fields or {}) do out[#out + 1] = f.name end
  return table.concat(out, ",")
end

-- Source fidelity remains complete and independent of semantic execution.
assert(field_names(T.LuaSrc.LOADKX) == "pc,a,has_extraarg,extraarg")
assert(field_names(T.LuaSrc.NEWTABLE) == "pc,a,array_hint,hash_hint,uses_extraarg,extraarg")
assert(field_names(T.LuaSrc.MMBINI) == "pc,lhs,rhs,op,operands_flipped")
assert(field_names(T.LuaSrc.TAILCALL) == "pc,base,nargs,hidden_vararg_count,close_upvalues")
assert(field_names(T.LuaSrc.RETURN) == "pc,base,nresults,c,close_upvalues")
assert(field_names(T.LuaSrc.SETLIST) == "pc,table,narray,start,uses_extraarg,extraarg")

-- Complete LuaRT product families.
assert(T.LuaRT.ProtoRef and T.LuaRT.UpvalueIdentity and T.LuaRT.ClosureIdentity)
assert(T.LuaRT.ResultRouteKind and T.LuaRT.ResultDestination and T.LuaRT.ResultBundle and T.LuaRT.FrameEffect)
assert(T.LuaRT.CallRef and T.LuaRT.CallShape and T.LuaRT.CallTarget and T.LuaRT.DirectLuaClosureTarget and T.LuaRT.MetamethodFunctionTarget and T.LuaRT.FFISymbolTarget)
assert(T.LuaRT.ResolvedCallTarget and T.LuaRT.CallArgChannel and T.LuaRT.CallResultChannel and T.LuaRT.CallFrameState)
assert(T.LuaRT.MetatableEpoch and T.LuaRT.MetamethodSlot and T.LuaRT.MetamethodLookupPath and T.LuaRT.MetamethodDispatch)
assert(T.LuaRT.OperationKind and T.LuaRT.OperationOperand and T.LuaRT.CompanionContext and T.LuaRT.LuaOperation)
assert(T.LuaRT.LoopTopology and T.LuaRT.NumericForTopology and T.LuaRT.GenericForTopology)
assert(T.LuaRT.OutcomeCause and T.LuaRT.CloseAction and T.LuaRT.ClosePlan)
assert(field_names(T.LuaRT.ValueSeq) == "kind,values,count,origin")
assert(field_names(T.LuaRT.ArityShape) == "provided,wanted,adjustment,kind")
assert(field_names(T.LuaRT.ResultChannel) == "id,kind,destination,count")
assert(field_names(T.LuaRT.ArityNormalization) == "source,shape,result,effects")
assert(field_names(T.LuaRT.CallShape) == "call,callee,args,wanted_results,tail_mode,yield_policy")
assert(field_names(T.LuaRT.ResolvedCallTarget) == "call,target,identity,callable")
assert(field_names(T.LuaRT.CallFrameState) == "call,layout,args,results,target,state")
assert(not T.LuaRT.ResultChannelKind and not T.LuaRT.UnsupportedReturnChannel and not T.LuaRT.CallFrameResultChannel)
assert(not T.LuaRT.CallTargetKind and not T.LuaRT.MetamethodCallHook and not T.LuaRT.CloseHook)

-- LuaGC/LuaFFI complete architecture products.
assert(T.LuaGC.ProtoObject and T.LuaGC.ThreadObject and T.LuaGC.UpvalueObject)
assert(T.LuaGC.GCProtoObject and T.LuaGC.GCThreadObject and T.LuaGC.GCUpvalueObject)
assert(T.LuaGC.GCEffect and T.LuaGC.GCAllocationEffect and T.LuaGC.GCBarrierEffect and not T.LuaGC.GCHook)
assert(T.LuaFFI.CValueConversion and T.LuaFFI.FFICallShape and T.LuaFFI.FFICallbackEntry and T.LuaFFI.CDataOwnershipTransition)

-- LuaExec semantic regions/module identity; support status is not product identity.
assert(T.LuaExec.Module and T.LuaExec.ModuleDescriptor and T.LuaExec.StaticRegionBinding and T.LuaExec.StaticRegionInvocation)
assert(T.LuaExec.RegionDescriptor and field_names(T.LuaExec.RegionDescriptor) == "id,kind,family,start_pc,end_pc")
assert(not field_names(T.LuaExec.RegionDescriptor):match("executable"))
assert(T.LuaExec.MetamethodDispatchExpr and T.LuaExec.ClosePlanExpr and T.LuaExec.GCEffectExpr and T.LuaExec.LuaOperationExpr)
assert(T.LuaExec.RequiresStaticRegion and T.LuaExec.InvokesStaticRegion and T.LuaExec.RequiresGCEffect and T.LuaExec.RequiresFFICallShape)
assert(T.LuaExec.RequiresClosureIdentity and T.LuaExec.UsesClosureIdentity)
assert(field_names(T.LuaExec.StaticCallProducts) == "call,call_shape,closure,resolved_target,arg_channel,result_channel,result_route,result_normalization,layout,frame_state,call_continuation,invocation,static_binding,static_region,callee_frame,caller_frame,result_base,result_count,arg_count")
assert(field_names(T.LuaExec.StaticClosureProducts) == "pc,slot,proto,closure,resolved_target,static_binding,allocation,handle")
assert(field_names(T.LuaExec.Region) == "id,kind,params,continuations,entry,blocks")
assert(field_names(T.LuaExec.Kernel) == "id,frame,body,contract")
assert(field_names(T.LuaExec.Block) == "id,params,ops,terminator")

-- CompileContract and Stencil typed identities.
assert(T.CompileContract.SemanticAssumption and T.CompileContract.AssumesStaticRegion and T.CompileContract.AssumesMetamethodLookupPath)
assert(T.CompileContract.AssumesClosureIdentity and T.CompileContract.AssumesUpvalueIdentity and T.CompileContract.AssumesGCEffect)
assert(T.CompileContract.AssumesFFICallShape and T.CompileContract.AssumesFFICallbackEntry and T.CompileContract.AssumesCDataOwnership)
assert(T.Stencil.FromStaticRegion and T.Stencil.FromStaticRegionInvocation and T.Stencil.FromClosureIdentity and T.Stencil.FromUpvalueIdentity)
assert(T.Stencil.FromMetamethodLookupPath and T.Stencil.FromLuaOperation and T.Stencil.FromLoopTopology and T.Stencil.FromGCEffect)
assert(T.Stencil.FromFFICallShape and T.Stencil.FromFFICallbackEntry and T.Stencil.FromCDataOwnership)

-- Existing LalinCFG current executable runtime substrate remains present.
assert(T.LalinCFG.RuntimeValueSeqNormalize and T.LalinCFG.RuntimeOutcomeReturnSeq and T.LalinCFG.RuntimeCallTargetCheck)
assert(T.LalinCFG.RuntimeValueSeqStore and T.LalinCFG.RuntimeCallFrameStoreArgs)

-- Model validate_against_schema coverage.
for _, spec in ipairs({
  { "lua_compile.lua_rt_value_model", "LuaRT value model" },
  { "lua_compile.lua_rt_outcome_model", "LuaRT outcome model" },
  { "lua_compile.lua_rt_stack_model", "LuaRT stack model" },
  { "lua_compile.lua_rt_arity_model", "LuaRT arity model" },
  { "lua_compile.lua_rt_call_model", "LuaRT call model" },
  { "lua_compile.lua_rt_metatable_model", "LuaRT metatable model" },
  { "lua_compile.lua_rt_operation_model", "LuaRT operation model" },
  { "lua_compile.lua_rt_close_model", "LuaRT close model" },
  { "lua_compile.lua_rt_gc_alloc_model", "LuaRT GC model" },
  { "lua_compile.lua_rt_closure_upvalue_model", "LuaRT closure/upvalue model" },
  { "lua_compile.lua_rt_loop_model", "LuaRT loop model" },
  { "lua_compile.lua_rt_cdata_model", "LuaRT cdata model" },
  { "lua_compile.lua_exec_region_model", "LuaExec region model" },
  { "lua_compile.lua_exec_static_region_model", "LuaExec static region model" },
}) do
  local model = require(spec[1])
  if model.validate_against_schema then
    local ok, missing = model.validate_against_schema()
    assert(ok, spec[2] .. " missing ASDL constructors: " .. table.concat(missing, ","))
  end
end

-- Structural validation smoke for changed arity/call/region products.
local RT, Exec, GC = T.LuaRT, T.LuaExec, T.LuaGC
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local ExecValidate = require("lua_compile.lua_exec_validate")
local Arity = require("lua_compile.lua_rt_arity_model")
local CallModel = require("lua_compile.lua_rt_call_model")
local StaticRegionModel = require("lua_compile.lua_exec_static_region_model")
local Payload = require("lua_compile.lua_fact_payload_lease")
local Facade = require("lua_compile")
assert(Facade.lua_exec_static_region_model == StaticRegionModel, "static region model must be exported")

local CompileValidate = require("lua_compile.lua_compile_validate")
local event = T.LuaCompile.CanonicalPucEvent("RETURN0", 1, 0, 0, 0, 0, 0, 0, 0, 0, false, 0, false, 0, false, 0, false, 0, false, false, false)
local ok_boundary, boundary_errors = CompileValidate.validate_source_event(event)
assert(ok_boundary, table.concat(boundary_errors, ";"))
ok_boundary, boundary_errors = CompileValidate.validate_source_event_batch(T.LuaCompile.SourceEventBatch({ event }))
assert(ok_boundary, table.concat(boundary_errors, ";"))
ok_boundary, boundary_errors = CompileValidate.validate_evidence_input(T.LuaCompile.EvidenceInput({}, T.LuaRegion.RegionSet({})))
assert(ok_boundary, table.concat(boundary_errors, ";"))
ok_boundary, boundary_errors = CompileValidate.validate_exec_lower_result(T.LuaCompile.ExecLowerReject({ "nope" }))
assert(ok_boundary, table.concat(boundary_errors, ";"))
ok_boundary, boundary_errors = CompileValidate.validate_lalin_lower_result(T.LuaCompile.LalinLowerReject({ "nope" }))
assert(ok_boundary, table.concat(boundary_errors, ";"))
ok_boundary, boundary_errors = CompileValidate.validate_static_inline_result(T.LuaCompile.StaticInlineReject({ "nope" }))
assert(ok_boundary, table.concat(boundary_errors, ";"))

local seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)
local shape = RT.ArityShape(RT.FixedCount(0), RT.FixedCount(0), RT.ExactCount(RT.Count(0)), RT.FixedArity)
local channel = Arity.result_channel("OutcomeReturnChannel", seq, RT.FixedCount(0))
local norm = Arity.normalization(seq, shape, channel)
local ok_norm, norm_errors = LuaRTValidate.arity_normalization(norm)
assert(ok_norm, "ArityNormalization validates: " .. table.concat(norm_errors, ";"))

local caller = RT.FrameRef(RT.Name("caller"))
local callee = RT.FrameRef(RT.Name("callee"))
local call_ref = RT.CallRef(RT.Name("call0"))
local callee_value = RT.StackValue(caller, RT.Slot(0))
local arg_seq = RT.ValueSeq(RT.FixedSeq, { RT.StackValue(caller, RT.Slot(1)) }, RT.FixedCount(1), RT.FromLiteralValues)
local arg_shape = RT.ArityShape(RT.FixedCount(1), RT.FixedCount(1), RT.ExactCount(RT.Count(1)), RT.FixedArity)
local args = RT.CallArgChannel(call_ref, arg_seq, arg_shape)
local result_seq = RT.ValueSeq(RT.CallResultSeq, {}, RT.FixedCount(1), RT.FromCallResult(call_ref))
local result_channel = Arity.result_channel("CallFrameResultChannel", result_seq, RT.FixedCount(1))
local result_norm = Arity.normalization(result_seq, arg_shape, result_channel)
local results = RT.CallResultChannel(call_ref, result_channel, result_norm)
local layout = RT.CallFrameLayout(RT.CallFrameRef(RT.Name("layout0")), caller, callee, RT.Slot(0), RT.Slot(0), RT.FixedCount(1), RT.Slot(1), RT.FixedCount(1), RT.Count(4))
local target = RT.DirectLuaClosureTarget(callee_value, RT.ClosureRef(RT.Name("closure0")))
local identity = RT.LuaClosureTargetIdentity(RT.ClosureRef(RT.Name("closure0")), T.LuaSrc.KRef(0), 7, {})
local resolved = RT.ResolvedCallTarget(call_ref, target, identity, RT.CallableLuaClosure)
local frame_state = RT.CallFrameState(call_ref, layout, args, results, resolved, RT.CallFrameUnprepared)
local ok_frame, frame_errors = LuaRTValidate.call_frame_state(frame_state)
assert(ok_frame, "CallFrameState validates: " .. table.concat(frame_errors, ";"))
local exec_frame_ok, exec_frame_reason = CallModel.is_executable_call_frame_state(frame_state)
assert(exec_frame_ok, tostring(exec_frame_reason))

local frame = RT.Frame(caller, RT.StackRef(caller), RT.TopRef(caller), RT.NoVarargs, RT.CloseChain(caller, {}), RT.Pc(1))
local block_id = Exec.BlockId(Exec.Name("entry"))
local descriptor = Exec.RegionDescriptor(Exec.RegionId(Exec.Name("r")), Exec.ReturnRegion, Exec.ReturnFamily, RT.Pc(1), RT.Pc(1))
local binding = Exec.StaticRegionBinding(Exec.RegionRef(descriptor.id), descriptor, Exec.StaticCalleeBodyRegion)
local call_cont = Exec.CallContinuationRegion(call_ref, Exec.RegionRef(descriptor.id), Exec.ContRef(Exec.Name("ret")), Exec.ContRef(Exec.Name("err")), Exec.ContRef(Exec.Name("yield")))
local invocation = Exec.StaticRegionInvocation(Exec.Name("invoke_r"), binding, {}, { Exec.ContBinding(Exec.ContRef(Exec.Name("ret")), Exec.BlockRef(block_id), {}) }, call_cont)
local ok_static, static_errors = StaticRegionModel.validate_static_region_invocation(invocation)
assert(ok_static, "StaticRegionInvocation validates: " .. table.concat(static_errors, ";"))
local closure_identity = RT.ClosureIdentity(RT.ClosureRef(RT.Name("closure0")), RT.ProtoRef(T.LuaSrc.KRef(0)), {}, 1)
local static_closure_payload = Payload.static_closure_target(T.LuaFact.SrcSlot(T.LuaSrc.Slot(0)), T.LuaSrc.Pc(1), closure_identity, resolved, {})
local static_region_payload = Payload.static_callee_region(T.LuaFact.SrcSlot(T.LuaSrc.Slot(0)), T.LuaSrc.Pc(1), closure_identity, binding, Exec.Region(Exec.Name("r"), Exec.ReturnRegion, {}, {}, block_id, {}), {})
local gc_lists = GC.GCLists(GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef)
local allocator = GC.Allocator(GC.Name("ctx"), GC.Name("alloc"), GC.Name("realloc"), GC.Name("free"))
local gc_state = GC.GCState(GC.Pause, GC.White0, gc_lists, 0, 0, GC.GCLimits(200, 100, 1024), 1, 2, allocator)
local alloc_req = GC.AllocRequest(gc_state, GC.ClosureKind, 64, 8)
local alloc_header = GC.GCHeader(GC.GCObjectRef(GC.Name("closure_gc")), GC.NoGCRef, GC.ClosureKind, GC.White0, 0, 1)
local allocation = GC.GCAllocationEffect(alloc_req, GC.Allocated(alloc_header))
local static_value_payload = Payload.static_closure_value(T.LuaFact.SrcSlot(T.LuaSrc.Slot(0)), T.LuaSrc.Pc(1), closure_identity, resolved, binding, allocation, {})
local ok_payload, payload_errors = Payload.validate(static_closure_payload)
assert(ok_payload, "StaticClosureTargetPayload validates: " .. table.concat(payload_errors, ";"))
ok_payload, payload_errors = Payload.validate(static_region_payload)
assert(ok_payload, "StaticCalleeRegionPayload validates: " .. table.concat(payload_errors, ";"))
ok_payload, payload_errors = Payload.validate(static_value_payload)
assert(ok_payload, "StaticClosureValuePayload validates: " .. table.concat(payload_errors, ";"))
local observed_value = require("lua_compile.lua_fact_from_runtime_observe").payload({ slot=0, payload="static_closure_value", pc=1, closure=closure_identity, target=resolved, binding=binding, allocation=allocation })
assert(observed_value and observed_value.kind == "StaticClosureValuePayload", "runtime observe imports StaticClosureValuePayload")
local block = Exec.Block(block_id, {}, { Exec.Let(Exec.Name("norm"), Exec.NormalizeResultsExpr(seq, shape)) }, Exec.Return(RT.ValueSeq(RT.AdjustedSeq, {}, RT.FixedCount(0), RT.FromArityNormalization(norm))))
local region = Exec.Region(Exec.Name("r"), Exec.ReturnRegion, {}, {}, block_id, { block })
local kernel = Exec.Kernel(Exec.Name("k"), frame, region, Exec.Contract({ Exec.RequiresRegionDescriptor(descriptor), Exec.RequiresArityShape(shape), Exec.RequiresResultChannel(channel) }, { Exec.DescribesRegion(descriptor), Exec.NormalizesArity(norm), Exec.ProducesResultChannel(channel) }))
local ok_exec, exec_errors = ExecValidate.kernel(kernel)
assert(ok_exec, "LuaExec kernel validates: " .. table.concat(exec_errors, ";"))

print("ok - SpongeJIT LuaCompile schema")
