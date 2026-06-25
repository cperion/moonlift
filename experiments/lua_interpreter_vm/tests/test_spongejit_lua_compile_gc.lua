#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local GC, RT, FFI, S = T.LuaGC, T.LuaRT, T.LuaFFI, T.Stencil
local Validate = require("lua_compile.lua_gc_validate")

local function assert_ok(ok, errors)
  assert(ok, table.concat(errors or {}, "\n"))
end

local function assert_bad(ok, errors, needle)
  assert(not ok, "expected invalid GC metadata")
  local text = table.concat(errors or {}, "\n")
  assert(text:find(needle, 1, true), "expected error containing " .. needle .. ", got:\n" .. text)
end

local function name(s) return GC.Name(s) end
local function rname(s) return RT.Name(s) end
local function cname(s) return FFI.CName(s) end

-- Core color/kind/phase enums are first-class ASDL constructors.
for _, color in ipairs({ GC.White0, GC.White1, GC.Gray, GC.Black, GC.Fixed, GC.Dead }) do
  assert(GC.GCColor.members[pvm.classof(color)], "bad GCColor")
end
for _, kind in ipairs({ GC.StringKind, GC.TableKind, GC.ClosureKind, GC.ProtoKind, GC.ThreadKind, GC.UserdataKind, GC.CDataKind, GC.UpvalueKind }) do
  assert(GC.GCObjectKind.members[pvm.classof(kind)], "bad GCObjectKind")
end
for _, phase in ipairs({ GC.Pause, GC.Propagate, GC.Atomic, GC.SweepString, GC.SweepObjects, GC.CallFinalizers }) do
  assert(GC.GCPhase.members[pvm.classof(phase)], "bad GCPhase")
end

-- GCHeader / GCState: no hidden global collector state.
local obj_ref = GC.GCObjectRef(name("obj_string"))
local table_obj_ref = GC.GCObjectRef(name("obj_table"))
local closure_obj_ref = GC.GCObjectRef(name("obj_closure"))
local userdata_obj_ref = GC.GCObjectRef(name("obj_userdata"))
local cdata_obj_ref = GC.GCObjectRef(name("obj_cdata"))
local obj = GC.SomeGCRef(obj_ref)
local table_gc_ref = GC.SomeGCRef(table_obj_ref)
local header = GC.GCHeader(obj_ref, GC.NoGCRef, GC.StringKind, GC.White0, 0, 1)
assert_ok(Validate.header(header))
assert_ok(C.validate.lua_gc_header(header))

local lists = GC.GCLists(obj, table_gc_ref, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef)
local limits = GC.GCLimits(1024, 200, 1 * 1024 * 1024)
local allocator = GC.Allocator(name("gc_ctx"), name("gc_alloc"), name("gc_realloc"), name("gc_free"))
local state = GC.GCState(GC.Propagate, GC.White1, lists, 4096, -128, limits, 7, 3, allocator)
assert_ok(Validate.gc_state(state))
assert_ok(C.validate.lua_gc_state(state))

-- LuaRT relationship: TValue/ValueRef can carry an explicit GC reference fact.
local frame_ref = RT.FrameRef(rname("frame0"))
local slot_value = RT.StackValue(frame_ref, RT.Slot(1))
local string_ref = RT.StringRef(rname("hello"))
local lua_string = RT.StringValue(string_ref, RT.ShortString)
local lua_value_ref = GC.LuaValueGCRef(slot_value, GC.GCStringTag, obj)
local lua_tvalue_ref = GC.LuaTValueGCRef(lua_string, GC.GCStringTag, obj)
assert(pvm.classof(lua_value_ref) == GC.LuaValueGCRef)
assert(pvm.classof(lua_tvalue_ref) == GC.LuaTValueGCRef)

-- FFI cdata/finalizer integration products.
local void_t = FFI.ScalarType(FFI.CTypeId(1), FFI.CVoid, FFI.Signless, 0, 0)
local int_t = FFI.ScalarType(FFI.CTypeId(2), FFI.CInt, FFI.Signed, 4, 4)
local void_fn_t = FFI.FunctionType(FFI.CTypeId(3), FFI.PlatformDefaultABI, void_t, FFI.CParamList({}, false))
local libc = FFI.CLib(FFI.CLibId(1), cname("libc"), FFI.DynamicLibrary, "libc.so.6", true)
local finalizer_sym = FFI.CSymbol(FFI.CSymbolId(1), cname("ffi_finalizer"), libc, FFI.FunctionSymbol, void_fn_t, FFI.PlatformDefaultABI, true, "addr:ffi_finalizer")
local ffi_finalizer = FFI.CFunctionFinalizer(FFI.CFinalizerId(1), finalizer_sym)
local ffi_storage = FFI.OwnedHeapStorage("ptr:cdata", 4)
local cdata = FFI.CData(int_t, ffi_storage, ffi_finalizer, FFI.FinalizerAttachedOwnership, FFI.CMetatypeId(0))

-- Finalizer kinds are typed, including Lua, FFI, and userdata finalizers.
local lua_method = RT.TempValue(rname("__gc_method"))
local lua_finalizer = GC.FinalizerRef(name("lua_gc_finalizer"), GC.LuaGCMetamethodFinalizer(lua_method), true)
local ffi_c_finalizer = GC.FinalizerRef(name("ffi_c_finalizer"), GC.FFICFunctionFinalizer(FFI.CSymbolId(1)), true)
local ffi_lua_finalizer = GC.FinalizerRef(name("ffi_lua_finalizer"), GC.FFILuaFinalizer(FFI.CFinalizerId(1)), true)
local userdata_finalizer = GC.FinalizerRef(name("userdata_finalizer"), GC.UserdataFinalizer(lua_method), true)
local no_finalizer = GC.FinalizerRef(name("no_finalizer"), GC.NoFinalizerKind, false)
for _, fin in ipairs({ lua_finalizer, ffi_c_finalizer, ffi_lua_finalizer, userdata_finalizer, no_finalizer }) do
  assert_ok(Validate.finalizer_ref(fin))
end

-- Collectable object sketches: string, table, closure, userdata, cdata.
local tstring = GC.TString(header, string_ref, 5, 12345, "sha256:hello")
local table_header = GC.GCHeader(table_obj_ref, GC.NoGCRef, GC.TableKind, GC.Gray, 0, 2)
local table_ref = RT.TableRef(rname("table0"))
local table_object = GC.TableObject(table_header, table_ref, RT.MixedArrayHash, RT.NoMetatable, 8, 2, 20, 21)
local closure_header = GC.GCHeader(closure_obj_ref, GC.NoGCRef, GC.ClosureKind, GC.Black, 0, 3)
local closure_ref = RT.ClosureRef(rname("closure0"))
local proto_ref = RT.ProtoRef(T.LuaSrc.KRef(1))
local uv0 = RT.UpvalueRef(rname("uv0"))
local uv1 = RT.UpvalueRef(rname("uv1"))
local uv0_id = RT.UpvalueIdentity(uv0, proto_ref, closure_ref, frame_ref, RT.Slot(0), RT.OpenStackUpvalue, 0, 0)
local uv1_id = RT.UpvalueIdentity(uv1, proto_ref, closure_ref, frame_ref, RT.Slot(1), RT.OpenStackUpvalue, 0, 0)
local closure_object = GC.LClosure(closure_header, closure_ref, proto_ref, { uv0_id, uv1_id })
local userdata_header = GC.GCHeader(userdata_obj_ref, GC.NoGCRef, GC.UserdataKind, GC.White1, 0, 4)
local userdata_object = GC.UserdataObject(userdata_header, RT.UserdataRef(rname("userdata0")), RT.UnknownMetatable, 64, userdata_finalizer)
local cdata_header = GC.GCHeader(cdata_obj_ref, GC.NoGCRef, GC.CDataKind, GC.White1, 0, 5)
local cdata_object = GC.CDataObject(cdata_header, cdata, FFI.CTypeId(2), ffi_storage, ffi_c_finalizer)
for _, object in ipairs({ GC.GCStringObject(tstring), GC.GCTableObject(table_object), GC.GCClosureObject(closure_object), GC.GCUserdataObject(userdata_object), GC.GCCDataObject(cdata_object) }) do
  assert(GC.CollectableObject.members[pvm.classof(object)])
end

-- Roots include stack/global/open-upvalue/c-callback/materialized-code surfaces.
local roots = GC.RootSet({
  GC.GCRoot(GC.StackRoot(frame_ref, RT.Slot(1)), obj),
  GC.GCRoot(GC.RegistryRoot, table_gc_ref),
  GC.GCRoot(GC.GlobalTableRoot, table_gc_ref),
  GC.GCRoot(GC.MetatableCacheRoot, table_gc_ref),
  GC.GCRoot(GC.OpenUpvalueRoot(uv0), obj),
  GC.GCRoot(GC.CCallbackRoot(FFI.CCallbackId(1)), GC.SomeGCRef(closure_obj_ref)),
  GC.GCRoot(GC.JitMaterializedCodeRoot(name("template_1")), obj),
})
assert_ok(Validate.root_set(roots))
assert_ok(C.validate.lua_gc_root_set(roots))

-- Barriers and actions are typed obligations, not comments/side tables.
local object_barrier = GC.ObjectToObjectBarrier(table_gc_ref, obj)
local table_barrier = GC.TableSlotBarrier(table_ref, slot_value, obj)
local upvalue_barrier = GC.UpvalueWriteBarrier(uv1, slot_value, obj)
local cdata_barrier = GC.CDataRefBarrier(cdata, obj)
for _, barrier in ipairs({ object_barrier, table_barrier, upvalue_barrier, cdata_barrier }) do
  assert_ok(Validate.barrier_kind(barrier))
  assert_ok(C.validate.lua_gc_barrier_kind(barrier))
end
for _, action in ipairs({ GC.NoBarrierAction, GC.MarkChild(obj), GC.RegrayParent(table_gc_ref), GC.EnqueueGrayAgain(table_gc_ref) }) do
  assert(GC.BarrierAction.members[pvm.classof(action)])
end

-- GC facts for epochs/barrier/finalizer/phase and LuaRT value relationships.
local facts = {
  GC.BarrierClean(table_barrier),
  GC.ObjectEpoch(obj, 5),
  GC.TableEpoch(table_ref, 6),
  GC.ShapeEpoch("shape:table0", 7),
  GC.GCPhaseFact(GC.Propagate),
  GC.NoFinalizerFact(table_gc_ref),
  GC.FinalizerAttachedFact(obj, lua_finalizer),
  GC.LuaValueGCRefFact(lua_value_ref),
  GC.LuaTValueGCRefFact(lua_tvalue_ref),
}
for _, fact in ipairs(facts) do
  assert_ok(Validate.gc_fact(fact))
  assert_ok(C.validate.lua_gc_fact(fact))
end

-- Control/result data for alloc/step/mark/traverse/barrier/finalizer/weak/ephemeron outcomes.
local top_ref = RT.TopRef(frame_ref)
local empty_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)
local error_state = RT.ErrorState(RT.RuntimeError, RT.TempValue(rname("gc_error")), RT.Pc(0), top_ref)
local yield_state = RT.YieldState(RT.Pc(0), top_ref, empty_seq, RT.ResumeClose)
local alloc_request = GC.AllocRequest(state, GC.TableKind, 128, 8)
local alloc_controls = {
  GC.AllocControl(alloc_request, GC.Allocated(table_header)),
  GC.AllocControl(alloc_request, GC.AllocStepRequired(32)),
  GC.AllocControl(alloc_request, GC.AllocOutOfMemory(128)),
  GC.AllocControl(alloc_request, GC.AllocEmergencyCollectRequired),
}
local step_request = GC.StepRequest(state, 4096)
local step_controls = {
  GC.StepControl(step_request, GC.StepProgressed(1024)),
  GC.StepControl(step_request, GC.StepCompletedCycle),
  GC.StepControl(step_request, GC.StepFinalizersPending(1)),
  GC.StepControl(step_request, GC.StepOutOfMemory),
}
local mark_request = GC.MarkRequest(state, obj)
local traverse_request = GC.TraverseRequest(state, table_gc_ref)
local mark_controls = {
  GC.MarkControl(mark_request, GC.MarkSkipped(obj)),
  GC.MarkControl(mark_request, GC.MarkEnqueued(obj)),
  GC.TraverseControl(traverse_request, GC.TraverseChildren(table_gc_ref, { obj })),
  GC.MarkControl(mark_request, GC.MarkError(GC.InvalidObjectRef)),
}
local barrier_controls = {
  GC.BarrierControl(table_barrier, GC.NoBarrierAction, GC.BarrierCleanResult),
  GC.BarrierControl(table_barrier, GC.MarkChild(obj), GC.BarrierChildMarked(obj)),
  GC.BarrierControl(object_barrier, GC.RegrayParent(table_gc_ref), GC.BarrierParentRegrayed(table_gc_ref)),
  GC.BarrierControl(object_barrier, GC.NoBarrierAction, GC.BarrierErrored(GC.InvalidBarrier)),
}
local finalizer_request = GC.FinalizerRequest(state, lua_finalizer, slot_value, error_state)
local finalizer_controls = {
  GC.FinalizerControl(finalizer_request, GC.FinalizerProcessed(GC.FinalizerCompleted)),
  GC.FinalizerControl(finalizer_request, GC.FinalizerProcessed(GC.FinalizerYielded(yield_state))),
  GC.FinalizerControl(finalizer_request, GC.FinalizerProcessed(GC.FinalizerErrored(error_state))),
  GC.FinalizerControl(finalizer_request, GC.FinalizersPending(1)),
  GC.FinalizerControl(finalizer_request, GC.FinalizerProcessError(GC.FinalizerFailure)),
}
local weak_request = GC.WeakProcessRequest(state, table_ref)
local ephemeron_request = GC.EphemeronProcessRequest(state, table_ref)
local weak_controls = {
  GC.WeakProcessControl(weak_request, GC.WeakProcessed(2)),
  GC.WeakProcessControl(weak_request, GC.WeakNeedsAnotherPass),
  GC.WeakProcessControl(weak_request, GC.WeakProcessError(GC.WeakProcessingFailure)),
  GC.EphemeronProcessControl(ephemeron_request, GC.EphemeronProcessed(1)),
  GC.EphemeronProcessControl(ephemeron_request, GC.EphemeronNeedsAnotherPass),
  GC.EphemeronProcessControl(ephemeron_request, GC.EphemeronProcessError(GC.WeakProcessingFailure)),
}
for _, list in ipairs({ alloc_controls, step_controls, mark_controls, barrier_controls, finalizer_controls, weak_controls }) do
  for _, control in ipairs(list) do assert(GC.Control.members[pvm.classof(control)]) end
end

-- Stencil metadata has typed GC patch-hole sources; this is materialization data only.
local gc_holes = {
  S.PatchHole(S.Name("gc_state_ptr"), S.GCStatePtrPatch, 0, 8, S.Abs64, S.FromGCState(name("gc_state"))),
  S.PatchHole(S.Name("gc_alloc_fn"), S.GCAllocatorFnPatch, 8, 8, S.Abs64, S.FromGCAllocator(name("allocator"), name("alloc_fn"))),
  S.PatchHole(S.Name("gc_table_epoch_offset"), S.GCObjectLayoutOffsetPatch, 16, 4, S.I32, S.FromGCObjectLayout(GC.TableKind, name("table_epoch"))),
  S.PatchHole(S.Name("gc_barrier_entry"), S.GCBarrierEntryAddrPatch, 24, 8, S.Abs64, S.FromGCBarrierEntry(table_barrier)),
  S.PatchHole(S.Name("gc_finalizer_queue"), S.GCFinalizerQueuePtrPatch, 32, 8, S.Abs64, S.FromGCFinalizerQueue(name("gc_state"))),
  S.PatchHole(S.Name("gc_epoch_addr"), S.GCEpochAddressPatch, 40, 8, S.Abs64, S.FromGCEpoch(GC.TableEpoch(table_ref, 6))),
  S.PatchHole(S.Name("gc_epoch_expected"), S.GCEpochExpectedPatch, 48, 8, S.I64, S.FromGCEpoch(GC.ObjectEpoch(obj, 5))),
}
for _, hole in ipairs(gc_holes) do
  assert(S.PatchKind.members[pvm.classof(hole.kind)])
  assert(S.PatchSource.members[pvm.classof(hole.source)])
end

-- Invalid tests are malformed GC metadata checks only.
local bad_header = GC.GCHeader(obj_ref, GC.NoGCRef, GC.StringKind, GC.White0, -1, 0)
local ok, errors = Validate.header(bad_header)
assert_bad(ok, errors, "flags")

local bad_state = GC.GCState(GC.Pause, GC.White0, lists, -1, 0, limits, 0, 0, allocator)
ok, errors = Validate.gc_state(bad_state)
assert_bad(ok, errors, "total_bytes")

local bad_root_set = GC.RootSet({ GC.GCRoot(GC.GlobalTableRoot, GC.NoGCRef) })
ok, errors = Validate.root_set(bad_root_set)
assert_bad(ok, errors, "must not be NoGCRef")

local bad_barrier = GC.ObjectToObjectBarrier(GC.NoGCRef, obj)
ok, errors = Validate.barrier_kind(bad_barrier)
assert_bad(ok, errors, "parent")

local bad_finalizer = GC.FinalizerRef(name("bad_finalizer"), GC.NoFinalizerKind, true)
ok, errors = Validate.finalizer_ref(bad_finalizer)
assert_bad(ok, errors, "NoFinalizerKind")

local bad_fact = GC.ObjectEpoch(GC.NoGCRef, -1)
ok, errors = Validate.gc_fact(bad_fact)
assert_bad(ok, errors, "object_epoch")

print("ok - SpongeJIT LuaCompile GC semantic ASDL foundation")
