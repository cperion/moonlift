#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Schema = require("lua_compile.schema")
local T = Schema.get()
local RT, GC, FFI, Exec, CC = T.LuaRT, T.LuaGC, T.LuaFFI, T.LuaExec, T.CompileContract
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local ExecValidate = require("lua_compile.lua_exec_validate")
local ContractValidate = require("lua_compile.compile_contract_validate")
local Arity = require("lua_compile.lua_rt_arity_model")
local CallModel = require("lua_compile.lua_rt_call_model")

local function n(s) return RT.Name(s) end
local function en(s) return Exec.Name(s) end
local function fixed_seq(values)
  return RT.ValueSeq(RT.FixedSeq, values or {}, RT.FixedCount(#(values or {})), RT.FromLiteralValues)
end
local function result_channel(id, kind, dest, count)
  return RT.ResultChannel(RT.Name(id), kind, dest, count)
end

local frame = RT.FrameRef(n("frame0"))
local callee_frame = RT.FrameRef(n("callee0"))
local receiver = RT.StackValue(frame, RT.Slot(0))
local key = RT.StackValue(frame, RT.Slot(1))
local fn_value = RT.TempValue(n("mm_fn"))

-- Metatable lookup path and metamethod dispatch are complete structural products.
local mt = RT.TableMetatable(RT.TableRef(n("mt")))
local epoch = RT.MetatableEpoch(mt, 11)
local slot = RT.MetamethodSlot(mt, RT.TM_INDEX, fn_value, 12)
local path = RT.MetamethodLookupPath(receiver, RT.TM_INDEX, {
  RT.CheckReceiverMetatable(receiver, epoch),
  RT.CheckMetamethodSlot(slot),
  RT.InvokeMetamethodCandidate(fn_value),
}, RT.MetamethodFoundResult(fn_value), { T.LuaFact.MetatableEpoch })
local call_ref = RT.CallRef(n("call_index"))
local call_shape = RT.CallShape(call_ref, fn_value, RT.StackWindow(RT.CallWindow, frame, RT.Slot(0), RT.FixedCount(2)), RT.FixedCount(1), RT.NotTailCall, RT.YieldingCall)
local out_channel = result_channel("index_out", RT.ContinuationRoute, RT.ContinuationDestination(n("after_index")), RT.FixedCount(1))
local dispatch = RT.MetamethodDispatch(path, call_shape, out_channel)
local ok, errs = LuaRTValidate.metamethod_dispatch(dispatch)
assert(ok, "metamethod dispatch validates: " .. table.concat(errs, ";"))

-- Closure/upvalue identity captures proto, owner, frame, slot, storage, and epochs.
local proto = RT.ProtoRef(T.LuaSrc.KRef(1))
local closure = RT.ClosureRef(n("closure0"))
local upid = RT.UpvalueIdentity(RT.UpvalueRef(n("uv0")), proto, closure, frame, RT.Slot(2), RT.OpenStackUpvalue, 21, 22)
local cid = RT.ClosureIdentity(closure, proto, { upid }, 23)
ok, errs = LuaRTValidate.upvalue_identity(upid)
assert(ok, "upvalue identity validates: " .. table.concat(errs, ";"))
ok, errs = LuaRTValidate.closure_identity(cid)
assert(ok, "closure identity validates: " .. table.concat(errs, ";"))

-- Generic-for topology is structural call/loop context, not executable support.
local topo = RT.GenericForTopology(RT.Pc(10), RT.Pc(11), RT.Pc(12), RT.Pc(13), RT.Pc(20))
ok, errs = LuaRTValidate.loop_topology(topo)
assert(ok, "generic-for topology validates: " .. table.concat(errs, ";"))

-- Close-on-error plan preserves cause, action order, and pending result bundle.
local empty_seq = fixed_seq({})
local close_channel = result_channel("close_out", RT.ClosePendingRoute, RT.ClosePendingDestination(RT.CloseChain(frame, {})), RT.FixedCount(0))
local bundle = RT.ResultBundle(empty_seq, close_channel)
local err = RT.ErrorState(RT.RuntimeError, receiver, RT.Pc(99), RT.TopRef(frame))
local item = RT.CloseItem(RT.Slot(2), receiver, RT.ClosePending)
local plan = RT.ClosePlan(RT.CloseChain(frame, { item }), RT.MetamethodCause(path), {
  RT.CloseLookupMethod(item, path),
  RT.CloseReplaceWithError(err),
  RT.ClosePropagateOriginal(bundle),
}, bundle)
ok, errs = LuaRTValidate.close_plan(plan)
assert(ok, "close plan validates: " .. table.concat(errs, ";"))

-- GC allocation/finalizer effects and new collectable taxonomy.
local gcname = GC.Name("gc")
local none = GC.NoGCRef
local lists = GC.GCLists(none, none, none, none, none, none, none)
local alloc = GC.Allocator(GC.Name("ctx"), GC.Name("alloc"), GC.Name("realloc"), GC.Name("free"))
local state = GC.GCState(GC.Pause, GC.White0, lists, 0, 0, GC.GCLimits(200, 100, 1024), 1, 2, alloc)
local req = GC.AllocRequest(state, GC.ProtoKind, 64, 8)
local header = GC.GCHeader(GC.GCObjectRef(gcname), none, GC.ProtoKind, GC.White0, 0, 3)
local effect = GC.GCAllocationEffect(req, GC.Allocated(header))
ok, errs = LuaRTValidate.gc_effect(effect)
assert(ok, "GC allocation effect validates: " .. table.concat(errs, ";"))
local proto_obj = GC.ProtoObject(header, proto, "proto-hash")
local gc_ok, gc_errs = require("lua_compile.lua_rt_gc_alloc_model").validate_proto_object(proto_obj)
assert(gc_ok, "proto collectable validates: " .. table.concat(gc_errs, ";"))

-- FFI ABI call/callback/ownership structural products.
local ctype = FFI.ScalarType(FFI.CTypeId(1), FFI.CInt64, FFI.Signed, 8, 8)
local params = FFI.CParamList({ FFI.CParam(FFI.CName("x"), ctype, FFI.CValueParam) }, false)
local ffi_call = FFI.FFICallShape(FFI.CSymbolId(7), FFI.SystemVAMD64, params, ctype, { FFI.LuaToCValue(receiver, ctype), FFI.CToLuaValue(ctype, key) }, call_ref)
ok, errs = LuaRTValidate.ffi_call_shape(ffi_call)
assert(ok, "FFI call shape validates: " .. table.concat(errs, ";"))
local callback = FFI.FFICallbackEntry(FFI.CCallbackId(2), FFI.SystemVAMD64, call_shape, RT.FFICallbackCause(FFI.CCallbackId(2)))
ok, errs = LuaRTValidate.ffi_callback_entry(callback)
assert(ok, "FFI callback entry validates: " .. table.concat(errs, ";"))
local cdata = FFI.CData(ctype, FFI.OwnedHeapStorage("addr", 8), FFI.NoFinalizer, FFI.OwnedOwnership, FFI.CMetatypeId(0))
local ownership = FFI.CDataOwnershipTransition(cdata, FFI.OwnedOwnership, FFI.FinalizerAttachedOwnership, { T.LuaFact.VmAbiEpoch })
ok, errs = LuaRTValidate.cdata_ownership_transition(ownership)
assert(ok, "cdata ownership validates: " .. table.concat(errs, ";"))

-- Static region/module identity products validate structurally.
local desc = Exec.RegionDescriptor(Exec.RegionId(en("callee_region")), Exec.ReturnRegion, Exec.ReturnFamily, RT.Pc(1), RT.Pc(2))
local binding = Exec.StaticRegionBinding(Exec.RegionRef(desc.id), desc, Exec.StaticCalleeBodyRegion)
local cont = Exec.CallContinuationRegion(call_ref, Exec.RegionRef(desc.id), Exec.ContRef(en("ret")), Exec.ContRef(en("err")), Exec.ContRef(en("yield")))
local invocation = Exec.StaticRegionInvocation(en("invoke0"), binding, {}, {}, cont)
ok, errs = ExecValidate.static_region_invocation(invocation)
assert(ok, "static invocation validates: " .. table.concat(errs, ";"))

-- Contract assumptions carry these identities structurally.
local contract = CC.Contract(CC.Transfer({}, {}), {
  CC.RequiresSemanticAssumption(CC.AssumesMetamethodLookupPath(path)),
  CC.RequiresSemanticAssumption(CC.AssumesUpvalueIdentity(upid)),
  CC.RequiresSemanticAssumption(CC.AssumesGCEffect(effect)),
  CC.RequiresSemanticAssumption(CC.AssumesFFICallShape(ffi_call)),
  CC.RequiresSemanticAssumption(CC.AssumesStaticRegionInvocation(invocation)),
}, {}, {})
ok, errs = ContractValidate.validate(contract)
assert(ok, "complete semantic contract validates: " .. table.concat(errs, ";"))

-- Relationship invariants catch mismatched CallRef in call-frame products.
local args = RT.CallArgChannel(call_ref, fixed_seq({ receiver }), RT.ArityShape(RT.FixedCount(1), RT.FixedCount(1), RT.ExactCount(RT.Count(1)), RT.FixedArity))
local wrong_call = RT.CallRef(n("wrong"))
local result_seq = RT.ValueSeq(RT.CallResultSeq, {}, RT.FixedCount(1), RT.FromCallResult(wrong_call))
local result_shape = RT.ArityShape(RT.FixedCount(1), RT.FixedCount(1), RT.ExactCount(RT.Count(1)), RT.FixedArity)
local result_channel = Arity.result_channel("CallFrameResultChannel", result_seq, RT.FixedCount(1))
local results = RT.CallResultChannel(wrong_call, result_channel, Arity.normalization(result_seq, result_shape, result_channel))
local resolved = RT.ResolvedCallTarget(call_ref, RT.DirectLuaClosureTarget(receiver, closure), RT.LuaClosureTargetIdentity(closure, T.LuaSrc.KRef(1), 1, {}), RT.CallableLuaClosure)
local layout = RT.CallFrameLayout(RT.CallFrameRef(n("layout")), frame, callee_frame, RT.Slot(0), RT.Slot(1), RT.FixedCount(1), RT.Slot(2), RT.FixedCount(1), RT.Count(4))
local bad_frame = RT.CallFrameState(call_ref, layout, args, results, resolved, RT.CallFrameUnprepared)
ok, errs = CallModel.validate_call_frame_state(bad_frame)
assert(not ok and table.concat(errs, ";"):match("mismatch"), "mismatched CallRef must fail relationship validation")

print("ok - SpongeJIT LuaCompile full semantic products")
