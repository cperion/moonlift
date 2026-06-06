#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()

assert(T.LuaSrc and T.LuaFact and T.LuaRegion and T.LuaFFI and T.LuaGC and T.LuaRT and T.LuaExec and T.CompileContract and T.MoonCFG and T.Stencil and T.LuaCompile)
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

-- Existing MoonCFG current executable runtime substrate remains present.
assert(T.MoonCFG.RuntimeValueSeqNormalize and T.MoonCFG.RuntimeOutcomeReturnSeq and T.MoonCFG.RuntimeCallTargetCheck)
assert(T.MoonCFG.RuntimeValueSeqStore and T.MoonCFG.RuntimeCallFrameStoreArgs)

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
}) do
  local model = require(spec[1])
  if model.validate_against_schema then
    local ok, missing = model.validate_against_schema()
    assert(ok, spec[2] .. " missing ASDL constructors: " .. table.concat(missing, ","))
  end
end

-- Structural validation smoke for changed arity/call/region products.
local RT, Exec = T.LuaRT, T.LuaExec
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local ExecValidate = require("lua_compile.lua_exec_validate")
local Arity = require("lua_compile.lua_rt_arity_model")
local CallModel = require("lua_compile.lua_rt_call_model")

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
local block = Exec.Block(block_id, {}, { Exec.Let(Exec.Name("norm"), Exec.NormalizeResultsExpr(seq, shape)) }, Exec.Return(RT.ValueSeq(RT.AdjustedSeq, {}, RT.FixedCount(0), RT.FromArityNormalization(norm))))
local region = Exec.Region(Exec.Name("r"), Exec.ReturnRegion, {}, {}, block_id, { block })
local kernel = Exec.Kernel(Exec.Name("k"), frame, region, Exec.Contract({ Exec.RequiresRegionDescriptor(descriptor), Exec.RequiresArityShape(shape), Exec.RequiresResultChannel(channel) }, { Exec.DescribesRegion(descriptor), Exec.NormalizesArity(norm), Exec.ProducesResultChannel(channel) }))
local ok_exec, exec_errors = ExecValidate.kernel(kernel)
assert(ok_exec, "LuaExec kernel validates: " .. table.concat(exec_errors, ";"))

print("ok - SpongeJIT LuaCompile schema")
