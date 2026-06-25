#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local Validate = require("lua_compile.lalin_cfg_validate")
local Emit = require("lua_compile.lalin_cfg_emit")
local ValueModel = require("lua_compile.lua_rt_value_model")
local ExecToLalin = require("lua_compile.lua_exec_to_lalin_cfg_lower")
local T = Schema.get()
local RT, Exec, GC = T.LuaRT, T.LuaExec, T.LuaGC

pcall(function()
  ffi.cdef[[
    typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
  ]]
end)

local function rn(s) return RT.Name(s) end
local function en(s) return Exec.Name(s) end
local function caller_frame() return RT.FrameRef(rn("frame0")) end
local function callee_frame(pc) return RT.FrameRef(rn("call_" .. tostring(pc) .. "_callee")) end
local function stack_value(frame, slot) return RT.StackValue(frame, RT.Slot(slot)) end

local function gc_allocation(opts)
  opts = opts or {}
  local lists = GC.GCLists(GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef, GC.NoGCRef)
  local allocator = GC.Allocator(GC.Name("ctx"), GC.Name("alloc"), GC.Name("realloc"), GC.Name("free"))
  local state = GC.GCState(GC.Pause, GC.White0, lists, 0, 0, GC.GCLimits(200, 100, 1024), 1, 2, allocator)
  local req = GC.AllocRequest(state, GC.ClosureKind, 64, 8)
  local header = GC.GCHeader(GC.GCObjectRef(GC.Name("source_closure_gc")), GC.NoGCRef, GC.ClosureKind, GC.White0, 0, 1)
  if opts.oom then return GC.GCAllocationEffect(req, GC.AllocOutOfMemory(64)) end
  return GC.GCAllocationEffect(req, GC.Allocated(header))
end

local function callee_region(pc, opts)
  opts = opts or {}
  local callee = callee_frame(pc)
  local entry = Exec.BlockId(en("callee_entry_" .. tostring(pc)))
  local vals = { stack_value(callee, 0), stack_value(callee, 1) }
  local seq = RT.ValueSeq(RT.FixedSeq, vals, RT.FixedCount(2), RT.FromLiteralValues)
  local ops = {
    Exec.AssignValue(vals[1], Exec.ConstTValue(RT.IntValue(opts.v0 or 701))),
    Exec.AssignValue(vals[2], Exec.ConstTValue(RT.IntValue(opts.v1 or 702))),
    Exec.AssignSeq(RT.StackWindow(RT.ReturnWindow, callee, RT.Slot(0), RT.FixedCount(2)), seq, RT.ExactCount(RT.Count(2))),
  }
  if opts.nested_emit then ops[#ops + 1] = Exec.EmitRegion(en("callee_region_" .. tostring(pc)), {}, {}) end
  local term = Exec.Continue(Exec.ContRef(en(opts.cont or "ret_" .. tostring(pc))), {})
  if opts.return_term then term = Exec.Return(seq) end
  if opts.error_term then term = Exec.Error(RT.ErrorState(RT.RuntimeError, vals[1], RT.Pc(10), RT.TopRef(callee))) end
  if opts.yield_term then term = Exec.Yield(RT.YieldState(RT.Pc(10), RT.TopRef(callee), RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues), RT.ResumeCall)) end
  local conts = {
    Exec.Continuation(en("ret_" .. tostring(pc)), Exec.ReturnCont, {}),
    Exec.Continuation(en("err_" .. tostring(pc)), Exec.ErrorCont, {}),
    Exec.Continuation(en("yield_" .. tostring(pc)), Exec.YieldCont, {}),
  }
  return Exec.Region(en("callee_region_" .. tostring(pc)), opts.kind or Exec.ReturnRegion, {}, conts, entry, { Exec.Block(entry, {}, ops, term) })
end

local function resolved_target(call_pc, closure, proto, opts)
  opts = opts or {}
  local call = RT.CallRef(rn("src_call_" .. tostring(call_pc)))
  local callee = stack_value(caller_frame(), 0)
  local k = opts.target_kind or "lua"
  if k == "unknown" then return RT.ResolvedCallTarget(call, RT.UnknownCallTarget(callee), RT.UnknownTargetIdentity, RT.NotCallable) end
  if k == "c" then return RT.ResolvedCallTarget(call, RT.DirectCClosureTarget(callee, closure), RT.CClosureTargetIdentity(closure, 88, {}), RT.CallableCClosure) end
  if k == "ffi" then return RT.ResolvedCallTarget(call, RT.FFISymbolTarget(callee, T.LuaFFI.CSymbolId(7)), RT.FFISymbolTargetIdentity(T.LuaFFI.CSymbolId(7), {}), RT.CallableLightCFunction) end
  if k == "metamethod" then
    local path = RT.MetamethodLookupPath(callee, RT.TM_CALL, {}, RT.MetamethodFoundResult(RT.TempValue(rn("mm_call"))), {})
    return RT.ResolvedCallTarget(call, RT.MetamethodFunctionTarget(callee, path), RT.MetamethodTargetIdentity(path, {}), RT.CallableViaCallMetamethod)
  end
  return RT.ResolvedCallTarget(call, RT.DirectLuaClosureTarget(callee, closure), RT.LuaClosureTargetIdentity(closure, proto, opts.handle or 77, {}), RT.CallableLuaClosure)
end

local function fixture(opts)
  opts = opts or {}
  local call_pc = opts.call_pc or 2
  local closure = RT.ClosureRef(rn("source_closure"))
  local closure_proto = T.LuaSrc.KRef(opts.proto or 9)
  local target_proto = T.LuaSrc.KRef(opts.target_proto or opts.proto or 9)
  local upvalues = opts.upvalues or {}
  local closure_identity = RT.ClosureIdentity(closure, RT.ProtoRef(closure_proto), upvalues, 1)
  local target = opts.target or resolved_target(call_pc, closure, target_proto, opts)
  local region = opts.region or callee_region(call_pc, opts.region_opts)
  local desc = Exec.RegionDescriptor(Exec.RegionId(en(opts.desc_name or region.id.text)), opts.desc_kind or region.kind, Exec.ReturnFamily, RT.Pc(10), RT.Pc(11))
  local binding = Exec.StaticRegionBinding(Exec.RegionRef(desc.id), desc, Exec.StaticCalleeBodyRegion)
  local observations = {}
  if not opts.omit_closure_payload then
    observations[#observations + 1] = { slot=0, payload="static_closure_value", pc=1, closure=closure_identity, target=target, binding=binding, allocation=opts.allocation or gc_allocation(opts), deps={"call_target_epoch", "gc_barrier_protocol"} }
  end
  if not opts.omit_call_payloads then
    local call_target = opts.call_target or target
    observations[#observations + 1] = { slot=0, payload="static_closure_target", pc=call_pc, closure=closure_identity, target=call_target, deps={"call_target_epoch"} }
    observations[#observations + 1] = { slot=0, payload="static_callee_region", pc=call_pc, closure=closure_identity, binding=binding, region=region, deps={"call_target_epoch"} }
  end
  local events = opts.events or {
    { op="CLOSURE", pc=1, a=0, bx=opts.op_proto or opts.proto or 9 },
    { op="CALL", pc=call_pc, a=0, b=opts.b or 3, c=opts.c or 3 },
    { op="RETURN", pc=call_pc + 1, a=0, b=3, c=0, close=false },
  }
  return C.unit_from_events(events, observations), { closure_identity = closure_identity, target = target, binding = binding, region = region }
end

local function run_cfg(cfg, name, ...)
  local ok, errs = Validate.validate(cfg)
  assert(ok, table.concat(errs, "\n"))
  local src = Emit.emit(cfg, { name = name })
  assert(not src:match("out_tag") and not src:match("out_event_kind") and not src:match("generic_for"), "must not emit protocol/fallback strings")
  assert(not src:match("helper") and not src:match("dispatch"), "must not emit helper/dispatch text")
  local native, quote_errors = Emit.compile(cfg, { name = name })
  assert(native, table.concat(quote_errors or {}, "; "))
  local out = native(...)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("%-?%d+")) or out end
  native:free()
  return out, src
end

-- Positive: CLOSURE alone boxes a LuaClosureTag with the typed closure handle.
local closure_only = fixture({ events = {
  { op="CLOSURE", pc=1, a=0, bx=9 },
  { op="RETURN1", pc=2, a=0 },
}, omit_call_payloads = true })
local exec_product, exec_errors = C.lua_src_to_lua_exec_lower.lower(closure_only.source, closure_only.evidence)
assert(exec_product, table.concat(exec_errors or {}, ";"))
local cfg_payload, cfg_errors = ExecToLalin.lower_outcome(exec_product, "value0_payload_i64")
assert(cfg_payload, table.concat(cfg_errors or {}, ";"))
assert(run_cfg(cfg_payload, "test_source_closure_payload") == 77, "CLOSURE must box contracted closure handle")
local cfg_tag = assert(ExecToLalin.lower_outcome(exec_product, "value0_tag"))
assert(run_cfg(cfg_tag, "test_source_closure_tag") == ValueModel.TAG.LuaClosureTag, "CLOSURE must box LuaClosureTag")

-- Positive: source CLOSURE produces the closure consumed by strict source CALL.
local unit = fixture()
local compiled = C.compile_to_lalin_kernel(unit)
assert(compiled.kind == "Ok", "public CLOSURE->CALL fixture must compile")
local module_product = assert(C.lua_src_to_lua_exec_lower.lower(unit.source, unit.evidence))
assert(module_product.kernels and module_product.regions, "CLOSURE->CALL must lower to LuaExec.Module")
local cfg, errors = ExecToLalin.lower_module_outcome(module_product, "lua_exec_core_kernel", "value1_payload_i64")
assert(cfg, table.concat(errors or {}, ";"))
local caller_stack = ffi.new("LuaRTValue[8]")
local callee_stack = ffi.new("LuaRTValue[8]")
local top = ffi.new("int64_t[1]", 0)
caller_stack[1].tag = ValueModel.TAG.IntegerTag; caller_stack[1].payload_i64 = 101
caller_stack[2].tag = ValueModel.TAG.IntegerTag; caller_stack[2].payload_i64 = 102
local out = run_cfg(cfg, "test_source_closure_call", caller_stack, top, callee_stack)
assert(out == 702, "CLOSURE->CALL must return second static callee result")
assert(caller_stack[0].payload_i64 == 701 and caller_stack[1].payload_i64 == 702, "ReceiveCallResults must copy static callee results")
local direct_cfg, direct_errors = ExecToLalin.lower_outcome(module_product.kernels[1], "value1_payload_i64")
assert(not direct_cfg and table.concat(direct_errors or {}, ";"):match("EmitRegion:requires_typed_static_region_lowering"), "direct kernel EmitRegion must remain rejected")

local function reject(opts, needle)
  local unit = fixture(opts)
  local r = C.compile_to_lalin_kernel(unit)
  local parts = {}
  for _, e in ipairs((r.diagnostic and r.diagnostic.errors) or {}) do parts[#parts + 1] = tostring(e) end
  if r.diagnostic and r.diagnostic.message then parts[#parts + 1] = tostring(r.diagnostic.message) end
  if r.diagnostic and r.diagnostic.reason then parts[#parts + 1] = tostring(r.diagnostic.reason.kind or r.diagnostic.reason) end
  local joined = table.concat(parts, ";")
  assert(r.kind == "Reject" and joined:match(needle), "expected reject " .. needle .. ", got " .. tostring(r.kind) .. " " .. joined)
end

reject({ omit_closure_payload = true }, "source_closure_missing_static_evidence")
reject({ op_proto = 10 }, "proto does not match")
reject({ target_proto = 10 }, "proto does not match")
reject({ handle = -1 }, "invalid closure handle")
reject({ upvalues = { RT.UpvalueIdentity(RT.UpvalueRef(rn("up0")), RT.ProtoRef(T.LuaSrc.KRef(9)), RT.ClosureRef(rn("source_closure")), caller_frame(), RT.Slot(1), RT.OpenStackUpvalue, 0, 0) } }, "upvalues")
reject({ target_kind = "unknown" }, "DirectLuaClosureTarget")
reject({ target_kind = "c" }, "DirectLuaClosureTarget")
reject({ target_kind = "ffi" }, "DirectLuaClosureTarget")
reject({ target_kind = "metamethod" }, "DirectLuaClosureTarget")
reject({ allocation = gc_allocation({ oom = true }) }, "Allocated")
reject({ desc_kind = Exec.MetatableRegion }, "descriptor kind")
reject({ b = 0 }, "open_arg_count")
reject({ c = 0 }, "open_result_count")
reject({ events = { { op="CLOSURE", pc=1, a=0, bx=9 }, { op="TAILCALL", pc=2, a=0, b=3, c=3 }, { op="RETURN0", pc=3 } } }, "TailCallRegion")
reject({ region_opts = { nested_emit = true } }, "nested EmitRegion")
reject({ region_opts = { return_term = true } }, "terminate via Continue")
reject({ region_opts = { error_term = true } }, "terminate via Continue")
reject({ region_opts = { yield_term = true } }, "terminate via Continue")

-- Same-block CLOSURE/CALL evidence must agree on closure/proto/handle/static binding.
local bad_call_target = resolved_target(2, RT.ClosureRef(rn("source_closure")), T.LuaSrc.KRef(9), { handle = 88 })
reject({ call_target = bad_call_target }, "closure_handle_mismatch")

print("ok - SpongeJIT LuaCompile source CLOSURE static slice")
