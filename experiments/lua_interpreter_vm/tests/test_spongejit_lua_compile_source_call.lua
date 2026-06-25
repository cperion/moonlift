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
local RT, Exec = T.LuaRT, T.LuaExec

pcall(function()
  ffi.cdef[[
    typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
  ]]
end)

local function rn(s) return RT.Name(s) end
local function en(s) return Exec.Name(s) end
local function caller_frame() return RT.FrameRef(rn("frame0")) end
local function callee_frame() return RT.FrameRef(rn("call_1_callee")) end
local function stack_value(frame, slot) return RT.StackValue(frame, RT.Slot(slot)) end

local function callee_region(opts)
  opts = opts or {}
  local callee = callee_frame()
  local entry = Exec.BlockId(en("callee_entry"))
  local vals = { stack_value(callee, 0), stack_value(callee, 1) }
  local seq = RT.ValueSeq(RT.FixedSeq, vals, RT.FixedCount(2), RT.FromLiteralValues)
  local ops = {
    Exec.AssignValue(vals[1], Exec.ConstTValue(RT.IntValue(opts.v0 or 501))),
    Exec.AssignValue(vals[2], Exec.ConstTValue(RT.IntValue(opts.v1 or 502))),
    Exec.AssignSeq(RT.StackWindow(RT.ReturnWindow, callee, RT.Slot(0), RT.FixedCount(2)), seq, RT.ExactCount(RT.Count(2))),
  }
  if opts.nested_emit then ops[#ops + 1] = Exec.EmitRegion(en("callee_region"), {}, {}) end
  local term = Exec.Continue(Exec.ContRef(en(opts.cont or "ret_1")), {})
  if opts.return_term then term = Exec.Return(RT.ValueSeq(RT.FixedSeq, vals, RT.FixedCount(2), RT.FromLiteralValues)) end
  if opts.error_term then term = Exec.Error(RT.ErrorState(RT.RuntimeError, vals[1], RT.Pc(10), RT.TopRef(callee))) end
  if opts.yield_term then term = Exec.Yield(RT.YieldState(RT.Pc(10), RT.TopRef(callee), RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues), RT.ResumeCall)) end
  local conts = {
    Exec.Continuation(en("ret_1"), Exec.ReturnCont, {}),
    Exec.Continuation(en("err_1"), Exec.ErrorCont, {}),
    Exec.Continuation(en("yield_1"), Exec.YieldCont, {}),
  }
  return Exec.Region(en("callee_region"), opts.kind or Exec.ReturnRegion, {}, conts, entry, { Exec.Block(entry, {}, ops, term) })
end

local function resolved_target(kind_name, closure, proto, opts)
  opts = opts or {}
  local call = RT.CallRef(rn("src_call_1"))
  local callee = stack_value(caller_frame(), 0)
  if kind_name == "unknown" then return RT.ResolvedCallTarget(call, RT.UnknownCallTarget(callee), RT.UnknownTargetIdentity, RT.NotCallable) end
  if kind_name == "c" then return RT.ResolvedCallTarget(call, RT.DirectCClosureTarget(callee, closure), RT.CClosureTargetIdentity(closure, 88, {}), RT.CallableCClosure) end
  if kind_name == "ffi" then return RT.ResolvedCallTarget(call, RT.FFISymbolTarget(callee, T.LuaFFI.CSymbolId(7)), RT.FFISymbolTargetIdentity(T.LuaFFI.CSymbolId(7), {}), RT.CallableLightCFunction) end
  if kind_name == "metamethod" then
    local path = RT.MetamethodLookupPath(callee, RT.TM_CALL, {}, RT.MetamethodFoundResult(RT.TempValue(rn("mm_call"))), {})
    return RT.ResolvedCallTarget(call, RT.MetamethodFunctionTarget(callee, path), RT.MetamethodTargetIdentity(path, {}), RT.CallableViaCallMetamethod)
  end
  return RT.ResolvedCallTarget(call, RT.DirectLuaClosureTarget(callee, closure), RT.LuaClosureTargetIdentity(closure, proto, opts.handle or 77, {}), RT.CallableLuaClosure)
end

local function fixture(opts)
  opts = opts or {}
  local closure = RT.ClosureRef(rn("source_closure"))
  local proto = T.LuaSrc.KRef(opts.proto or 9)
  local closure_identity = RT.ClosureIdentity(closure, RT.ProtoRef(proto), opts.upvalues or {}, 1)
  local target = opts.target or resolved_target(opts.target_kind or "lua", closure, T.LuaSrc.KRef(opts.target_proto or opts.proto or 9), opts)
  local region = opts.region or callee_region(opts.region_opts)
  local desc = Exec.RegionDescriptor(Exec.RegionId(en(opts.desc_name or "callee_region")), opts.desc_kind or region.kind, Exec.ReturnFamily, RT.Pc(10), RT.Pc(11))
  local binding = Exec.StaticRegionBinding(Exec.RegionRef(desc.id), desc, Exec.StaticCalleeBodyRegion)
  local observations = {}
  if not opts.omit_target_payload then
    observations[#observations + 1] = { slot=0, payload="static_closure_target", pc=1, closure=closure_identity, target=target, deps={"call_target_epoch"} }
  end
  if not opts.omit_region_payload then
    observations[#observations + 1] = { slot=0, payload="static_callee_region", pc=1, closure=closure_identity, binding=binding, region=region, deps={"call_target_epoch"} }
  end
  local events = opts.events or {
    { op="CALL", pc=1, a=0, b=opts.b or 3, c=opts.c or 3 },
    { op="RETURN", pc=2, a=0, b=3, c=0, close=false },
  }
  return C.unit_from_events(events, observations)
end

local function run_cfg(cfg, name)
  local ok, errs = Validate.validate(cfg)
  assert(ok, table.concat(errs, "\n"))
  local src = Emit.emit(cfg, { name = name })
  assert(not src:match("out_tag") and not src:match("out_event_kind") and not src:match("generic_for"), "must not emit protocol/fallback strings")
  assert(not src:match("helper") and not src:match("dispatch"), "must not emit helper/dispatch text")
  local native, quote_errors = Emit.compile(cfg, { name = name })
  assert(native, table.concat(quote_errors or {}, "; "))
  local caller_stack = ffi.new("LuaRTValue[8]")
  local callee_stack = ffi.new("LuaRTValue[8]")
  local top = ffi.new("int64_t[1]", 0)
  caller_stack[0].tag = ValueModel.TAG.LuaClosureTag; caller_stack[0].payload_i64 = 77
  caller_stack[1].tag = ValueModel.TAG.IntegerTag; caller_stack[1].payload_i64 = 101
  caller_stack[2].tag = ValueModel.TAG.IntegerTag; caller_stack[2].payload_i64 = 102
  local out = native(caller_stack, top, callee_stack)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("%-?%d+")) or out end
  native:free()
  return out, caller_stack
end

-- Positive: public source CALL route accepts only typed static closure evidence.
local unit = fixture()
local compiled = C.compile_to_lalin_kernel(unit)
assert(compiled.kind == "Ok", "public source CALL fixture must compile: " .. tostring(compiled.diagnostic and compiled.diagnostic.reason and compiled.diagnostic.reason.kind))
local exec_product, exec_errors = C.lua_src_to_lua_exec_lower.lower(unit.source, unit.evidence)
assert(exec_product and exec_product.kernels and exec_product.regions, table.concat(exec_errors or {}, ";"))
local cfg, cfg_errors = ExecToLalin.lower_module_outcome(exec_product, "lua_exec_core_kernel", "value1_payload_i64")
assert(cfg, table.concat(cfg_errors or {}, ";"))
local out, caller_stack = run_cfg(cfg, "test_source_call_value1")
assert(out == 502, "second static callee result must be returned")
assert(caller_stack[0].payload_i64 == 501 and caller_stack[1].payload_i64 == 502, "ReceiveCallResults must copy callee results to caller slots")

local function reject(opts, needle)
  local r = C.compile_to_lalin_kernel(fixture(opts))
  local parts = {}
  for _, e in ipairs((r.diagnostic and r.diagnostic.errors) or {}) do parts[#parts + 1] = tostring(e) end
  if r.diagnostic and r.diagnostic.message then parts[#parts + 1] = tostring(r.diagnostic.message) end
  if r.diagnostic and r.diagnostic.reason then parts[#parts + 1] = tostring(r.diagnostic.reason.kind or r.diagnostic.reason) end
  local joined = table.concat(parts, ";")
  assert(r.kind == "Reject" and joined:match(needle), "expected reject " .. needle .. ", got " .. tostring(r.kind) .. " " .. joined)
end

reject({ events = { { op="TAILCALL", pc=1, a=0, b=3, c=3 }, { op="RETURN0", pc=2 } } }, "TailCallRegion")
reject({ b = 0 }, "open_arg_count")
reject({ c = 0 }, "open_result_count")
reject({ omit_target_payload = true }, "missing_static_evidence")
reject({ omit_region_payload = true }, "missing_static_evidence")
reject({ events = { { op="CALL", pc=1, a=0, b=3, c=3 }, { op="RETURN", pc=2, a=0, b=3, c=1, close=true } } }, "unsupported_return_close_or_c")
reject({ events = { { op="CALL", pc=1, a=0, b=3, c=3 }, { op="CLOSE", pc=2, a=0 }, { op="RETURN0", pc=3 } } }, "CloseRegion")
reject({ target_kind = "unknown" }, "DirectLuaClosureTarget")
reject({ target_kind = "c" }, "DirectLuaClosureTarget")
reject({ target_kind = "ffi" }, "DirectLuaClosureTarget")
reject({ target_kind = "metamethod" }, "DirectLuaClosureTarget")
reject({ target_proto = 10 }, "proto does not match")
reject({ desc_kind = Exec.MetatableRegion }, "descriptor kind")
reject({ region_opts = { nested_emit = true } }, "nested EmitRegion")
reject({ region_opts = { return_term = true } }, "terminate via Continue")
reject({ region_opts = { error_term = true } }, "terminate via Continue")
reject({ region_opts = { yield_term = true } }, "terminate via Continue")

-- Direct kernel EmitRegion guardrail remains separate from the source CALL route.
local k = exec_product.kernels[1]
local direct_cfg, direct_errors = ExecToLalin.lower_outcome(k, "value1_payload_i64")
assert(not direct_cfg and table.concat(direct_errors or {}, ";"):match("EmitRegion:requires_typed_static_region_lowering"), "direct kernel EmitRegion must reject")

print("ok - SpongeJIT LuaCompile source CALL static slice")
