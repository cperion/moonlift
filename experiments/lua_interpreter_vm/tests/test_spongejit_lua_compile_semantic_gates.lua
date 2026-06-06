#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local T = Schema.get()
local RT, GC, Exec, FFI = T.LuaRT, T.LuaGC, T.LuaExec, T.LuaFFI
local ExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")
local Emit = require("lua_compile.moon_cfg_emit")

local function assert_reject_contains(errors_or_result, needle, label)
  local text
  if type(errors_or_result) == "table" and errors_or_result.kind == "Reject" then
    text = errors_or_result.diagnostic and errors_or_result.diagnostic.message or ""
  else
    text = table.concat(errors_or_result or {}, ";")
  end
  assert(text:find(needle, 1, true), (label or needle) .. " expected in: " .. text)
end

local function compile_events(events)
  return C.compile_to_moon_kernel(C.unit_from_events(events, {}))
end

-- Source-level dynamic semantics still reject; complete ASDL products do not imply acceptance.
local r = compile_events({ { op = "CALL", pc = 1, a = 0, b = 1, c = 1 }, { op = "RETURN0", pc = 2 } })
assert(r.kind == "Reject", "source CALL must reject")
assert_reject_contains(r, "unsupported_source_semantics:CallRegion", "CALL reject")
r = compile_events({ { op = "TAILCALL", pc = 1, a = 0, b = 1, c = 1 }, { op = "RETURN0", pc = 2 } })
assert(r.kind == "Reject", "source TAILCALL must reject")
assert_reject_contains(r, "unsupported_source_semantics:TailCallRegion", "TAILCALL reject")
for _, op in ipairs({ "CLOSE", "TBC", "NEWTABLE", "CLOSURE", "SETLIST", "TFORPREP", "TFORCALL", "TFORLOOP" }) do
  local ev = { op = op, pc = 1, a = 0, b = 0, c = 0, bx = 0, ax = 0 }
  local rr = compile_events({ ev, { op = "RETURN0", pc = 2 } })
  assert(rr.kind == "Reject", op .. " must reject")
end

local function n(s) return RT.Name(s) end
local function en(s) return Exec.Name(s) end
local frame_ref = RT.FrameRef(n("frame"))
local frame = RT.Frame(frame_ref, RT.StackRef(frame_ref), RT.TopRef(frame_ref), RT.NoVarargs, RT.CloseChain(frame_ref, {}), RT.Pc(1))
local block_id = Exec.BlockId(en("entry"))
local function kernel_with(kind, ops)
  local region = Exec.Region(en("r"), kind, {}, {}, block_id, { Exec.Block(block_id, {}, ops or {}, Exec.Return(RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues))) })
  return Exec.Kernel(en("k"), frame, region, Exec.Contract({}, {}))
end
local function lower_rejects(kernel, needle)
  local cfg, errs = ExecToMoon.lower(kernel, { outcome = true, outcome_projection = "kind" })
  assert(not cfg, "kernel unexpectedly lowered")
  assert_reject_contains(errs, needle)
end

-- Unsupported semantic regions reject before MoonCFG emission.
lower_rejects(kernel_with(Exec.MetatableRegion, {}), "unsupported_semantic_region:MetatableRegion")
lower_rejects(kernel_with(Exec.ClosureRegion, {}), "unsupported_semantic_region:ClosureRegion")
lower_rejects(kernel_with(Exec.UpvalueRegion, {}), "unsupported_semantic_region:UpvalueRegion")
lower_rejects(kernel_with(Exec.NumericForRegion, {}), "unsupported_semantic_region:NumericForRegion")
lower_rejects(kernel_with(Exec.GenericForRegion, {}), "unsupported_semantic_region:GenericForRegion")
lower_rejects(kernel_with(Exec.CloseRegion, {}), "unsupported_semantic_region:CloseRegion")
lower_rejects(kernel_with(Exec.GCAllocRegion, {}), "unsupported_semantic_region:GCAllocRegion")
lower_rejects(kernel_with(Exec.FFIRegion, {}), "unsupported_semantic_region:FFIRegion")

-- Unsupported complete-product expressions reject with typed diagnostics in otherwise supported regions.
local receiver = RT.StackValue(frame_ref, RT.Slot(0))
local mt = RT.TableMetatable(RT.TableRef(n("mt")))
local path = RT.MetamethodLookupPath(receiver, RT.TM_INDEX, { RT.CheckReceiverMetatable(receiver, RT.MetatableEpoch(mt, 1)) }, RT.MetamethodMissingResult, { T.LuaFact.MetatableEpoch })
local call_ref = RT.CallRef(n("call"))
local ch = RT.ResultChannel(n("out"), RT.OutcomeReturnRoute, RT.OutcomeDestination, RT.FixedCount(0))
local dispatch = RT.MetamethodDispatch(path, RT.CallShape(call_ref, receiver, RT.StackWindow(RT.CallWindow, frame_ref, RT.Slot(0), RT.FixedCount(0)), RT.FixedCount(0), RT.NotTailCall, RT.YieldingCall), ch)
lower_rejects(kernel_with(Exec.ReturnRegion, { Exec.Let(en("mm"), Exec.MetamethodDispatchExpr(dispatch)) }), "unsupported_semantic_expr:MetamethodDispatchExpr")

local empty_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)
local bundle = RT.ResultBundle(empty_seq, ch)
local plan = RT.ClosePlan(RT.CloseChain(frame_ref, {}), RT.DirectReturnCause, { RT.ClosePropagateOriginal(bundle) }, bundle)
lower_rejects(kernel_with(Exec.ReturnRegion, { Exec.Let(en("close"), Exec.ClosePlanExpr(plan)) }), "unsupported_semantic_expr:ClosePlanExpr")

local none = GC.NoGCRef
local lists = GC.GCLists(none, none, none, none, none, none, none)
local state = GC.GCState(GC.Pause, GC.White0, lists, 0, 0, GC.GCLimits(1, 1, 1), 0, 0, GC.Allocator(GC.Name("ctx"), GC.Name("a"), GC.Name("r"), GC.Name("f")))
local req = GC.AllocRequest(state, GC.CDataKind, 8, 8)
local effect = GC.GCAllocationEffect(req, GC.AllocOutOfMemory(8))
lower_rejects(kernel_with(Exec.ReturnRegion, { Exec.Let(en("gc"), Exec.GCEffectExpr(effect)) }), "unsupported_semantic_expr:GCEffectExpr")

local desc = Exec.RegionDescriptor(Exec.RegionId(en("target")), Exec.ReturnRegion, Exec.ReturnFamily, RT.Pc(1), RT.Pc(1))
local binding = Exec.StaticRegionBinding(Exec.RegionRef(desc.id), desc, Exec.StaticCalleeBodyRegion)
local cont = Exec.CallContinuationRegion(call_ref, Exec.RegionRef(desc.id), Exec.ContRef(en("ret")), Exec.ContRef(en("err")), Exec.ContRef(en("yield")))
local inv = Exec.StaticRegionInvocation(en("inv"), binding, {}, {}, cont)
lower_rejects(kernel_with(Exec.ReturnRegion, { Exec.Let(en("inv"), Exec.StaticRegionInvocationExpr(inv)) }), "unsupported_semantic_expr:StaticRegion")
lower_rejects(kernel_with(Exec.ReturnRegion, { Exec.EmitRegion(en("target"), {}, {}) }), "unsupported_lua_exec_op:EmitRegion:requires_typed_static_region_lowering")

-- Successful current slice still emits no forbidden helper/protocol strings.
local ok_result = compile_events({ { op = "LOADI", pc = 1, a = 1, value = 7 }, { op = "RETURN1", pc = 2, a = 1 } })
assert(ok_result.kind == "Ok")
local src = Emit.emit(ok_result.product.kernel)
for _, forbidden in ipairs({ "out" .. "_tag", "out" .. "_event_kind", "generic" .. "_for", "set" .. "list", "Opcode" .. "Helper", "Protocol" .. "Exit" }) do
  assert(not src:find(forbidden, 1, true), "emitted source contains forbidden string " .. forbidden)
end

print("ok - SpongeJIT LuaCompile semantic gates")
