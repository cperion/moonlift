#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Schema = require("lua_compile.schema")
local Validate = require("lua_compile.lalin_cfg_validate")
local Emit = require("lua_compile.lalin_cfg_emit")
local ExecValidate = require("lua_compile.lua_exec_validate")
local ExecToLalin = require("lua_compile.lua_exec_to_lalin_cfg_lower")
local Arity = require("lua_compile.lua_rt_arity_model")
local ValueModel = require("lua_compile.lua_rt_value_model")
local T = Schema.get()
local RT, Exec = T.LuaRT, T.LuaExec

pcall(function()
  ffi.cdef[[
    typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
  ]]
end)

local function run(k, fname, ...)
  local ok, errs = Validate.validate(k)
  assert(ok, table.concat(errs, "\n"))
  local src = Emit.emit(k, { name = fname })
  assert(not src:match("out_tag") and not src:match("out_event_kind") and not src:match("generic_for"), "must not emit protocol/fallback strings")
  assert(not src:match("helper") and not src:match("dispatch"), "must not emit helper/dispatch text")
  local native, quote_errors = Emit.compile(k, { name = fname })
  assert(native, table.concat(quote_errors or {}, "; "))
  local out = native(...)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("^-?%d+")) or out end
  native:free()
  return out, src
end

local function n(s) return RT.Name(s) end
local function en(s) return Exec.Name(s) end
local function frame_ref(s) return RT.FrameRef(n(s)) end
local function stack_value(frame, slot) return RT.StackValue(frame, RT.Slot(slot)) end
local function fixed_seq_from_window(frame, base, count, kind)
  local w = RT.StackWindow(kind or RT.CallWindow, frame, RT.Slot(base), RT.FixedCount(count))
  return RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(count), RT.FromStackWindow(w))
end
local function i64_tv(v) return RT.IntValue(v) end
local function exact_shape(nv) return RT.ArityShape(RT.FixedCount(nv), RT.FixedCount(nv), RT.ExactCount(RT.Count(nv)), RT.FixedArity) end

local caller = frame_ref("caller")
local callee = frame_ref("callee")
local call_ref = RT.CallRef(n("call_static"))
local callee_value = stack_value(caller, 0)
local closure = RT.ClosureRef(n("closure_static"))
local target = RT.DirectLuaClosureTarget(callee_value, closure)
local identity = RT.LuaClosureTargetIdentity(closure, T.LuaSrc.KRef(0), 77, {})
local resolved = RT.ResolvedCallTarget(call_ref, target, identity, RT.CallableLuaClosure)
local arg_seq = fixed_seq_from_window(caller, 1, 3, RT.CallWindow)
local args = RT.CallArgChannel(call_ref, arg_seq, exact_shape(3))
local result_seq = RT.ValueSeq(RT.CallResultSeq, {}, RT.FixedCount(3), RT.FromCallResult(call_ref))
local result_channel = Arity.result_channel("CallFrameResultChannel", result_seq, RT.FixedCount(3))
local result_norm = Arity.normalization(result_seq, exact_shape(3), result_channel)
local results = RT.CallResultChannel(call_ref, result_channel, result_norm)
local layout = RT.CallFrameLayout(RT.CallFrameRef(n("layout_static")), caller, callee, RT.Slot(0), RT.Slot(0), RT.FixedCount(3), RT.Slot(4), RT.FixedCount(3), RT.Count(8))
local frame_state = RT.CallFrameState(call_ref, layout, args, results, resolved, RT.CallFrameUnprepared)
local frame = RT.Frame(caller, RT.StackRef(caller), RT.TopRef(caller), RT.NoVarargs, RT.CloseChain(caller, {}), RT.Pc(1))

local function params()
  return {
    Exec.Param(en("caller_stack"), Exec.LalinType("ptr(LuaRTValue)")),
    Exec.Param(en("callee_stack"), Exec.LalinType("ptr(LuaRTValue)")),
  }
end

local function callee_region(kind, opts)
  opts = opts or {}
  local entry = Exec.BlockId(en("callee_entry"))
  local conts = {
    Exec.Continuation(en("ret"), Exec.ReturnCont, {}),
    Exec.Continuation(en("err"), Exec.ErrorCont, {}),
    Exec.Continuation(en("yield"), Exec.YieldCont, {}),
  }
  local vals = { stack_value(callee, 4), stack_value(callee, 5), stack_value(callee, 6) }
  local seq01 = RT.ValueSeq(RT.FixedSeq, { vals[1], vals[2] }, RT.FixedCount(2), RT.FromLiteralValues)
  local seq2 = RT.ValueSeq(RT.FixedSeq, { vals[3] }, RT.FixedCount(1), RT.FromLiteralValues)
  local return_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(3), RT.FromStackWindow(RT.StackWindow(RT.ReturnWindow, callee, RT.Slot(4), RT.FixedCount(3))))
  local ops = {
    Exec.AssignValue(vals[1], Exec.ConstTValue(i64_tv(401))),
    Exec.AssignValue(vals[2], Exec.ConstTValue(i64_tv(402))),
    Exec.AssignValue(vals[3], Exec.ConstTValue(i64_tv(403))),
    Exec.AssignSeq(RT.StackWindow(RT.ReturnWindow, callee, RT.Slot(4), RT.FixedCount(2)), seq01, RT.ExactCount(RT.Count(2))),
    Exec.AssignSeq(RT.StackWindow(RT.ReturnWindow, callee, RT.Slot(6), RT.FixedCount(1)), seq2, RT.ExactCount(RT.Count(1))),
  }
  if opts.nested_emit then ops[#ops + 1] = Exec.EmitRegion(en("callee_region"), {}, {}) end
  local term = Exec.Continue(Exec.ContRef(en(opts.cont or "ret")), {})
  if opts.return_term then term = Exec.Return(return_seq) end
  local block = Exec.Block(entry, {}, ops, term)
  return Exec.Region(en("callee_region"), kind or Exec.ReturnRegion, {}, conts, entry, { block })
end

local function static_contract(static_region, opts)
  opts = opts or {}
  local desc_name = opts.desc_name or static_region.id.text
  local desc_kind = opts.desc_kind or static_region.kind
  local desc = Exec.RegionDescriptor(Exec.RegionId(en(desc_name)), desc_kind, Exec.ReturnFamily, RT.Pc(10), RT.Pc(11))
  local binding = Exec.StaticRegionBinding(Exec.RegionRef(desc.id), desc, Exec.StaticCalleeBodyRegion)
  local call_cont = Exec.CallContinuationRegion(call_ref, Exec.RegionRef(desc.id), Exec.ContRef(en("ret")), Exec.ContRef(en("err")), Exec.ContRef(en("yield")))
  local conts = { Exec.ContBinding(Exec.ContRef(en("ret")), Exec.BlockRef(Exec.BlockId(en("after_emit"))), {}) }
  local invocation = Exec.StaticRegionInvocation(en("invoke_callee"), binding, {}, conts, call_cont)
  local obligations = {
    Exec.RequiresResolvedCallTarget(resolved),
    Exec.RequiresCallFrameLayout(layout),
    Exec.RequiresCallArgChannel(args),
    Exec.RequiresCallResultChannel(results),
    Exec.RequiresStaticRegion(binding),
    Exec.RequiresStaticRegionInvocation(invocation),
    Exec.RequiresCallContinuationRegion(call_cont),
  }
  local guarantees = {
    Exec.ResolvesCallTarget(resolved),
    Exec.PreparesCallFrame(frame_state),
    Exec.ProducesCallResults(results),
    Exec.ProvidesStaticRegion(binding),
    Exec.InvokesStaticRegion(invocation),
    Exec.BindsCallContinuationRegion(call_cont),
  }
  return Exec.Contract(obligations, guarantees)
end

local function kernel_with_emit(contract)
  local entry = Exec.BlockId(en("entry"))
  local after = Exec.BlockId(en("after_emit"))
  local ret_window = RT.StackWindow(RT.ReturnWindow, caller, RT.Slot(4), RT.FixedCount(3))
  local ret_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(3), RT.FromStackWindow(ret_window))
  local emit_conts = { Exec.ContBinding(Exec.ContRef(en("ret")), Exec.BlockRef(after), {}) }
  local entry_block = Exec.Block(entry, {}, {
    Exec.PrepareCallFrame(frame_state),
    Exec.EmitRegion(en("callee_region"), {}, emit_conts),
  }, Exec.Unreachable)
  local after_block = Exec.Block(after, {}, { Exec.ReceiveCallResults(frame_state) }, Exec.Return(ret_seq))
  local region = Exec.Region(en("kernel_body"), Exec.CallRegion, params(), {}, entry, { entry_block, after_block })
  return Exec.Kernel(en("kernel"), frame, region, contract)
end

local function module_with(callee, contract)
  return Exec.Module({ callee }, { kernel_with_emit(contract) })
end

local good_callee = callee_region(Exec.ReturnRegion)
local good_contract = static_contract(good_callee)
local good_module = module_with(good_callee, good_contract)
local ok_module, module_errors = ExecValidate.module(good_module)
assert(ok_module, table.concat(module_errors, ";"))
local cfg, cfg_errors = ExecToLalin.lower_module_outcome(good_module, "kernel", "value2_payload_i64")
assert(cfg, table.concat(cfg_errors or {}, ";"))
local caller_stack = ffi.new("LuaRTValue[8]")
local callee_stack = ffi.new("LuaRTValue[8]")
for i = 1, 3 do caller_stack[i].tag = ValueModel.TAG.IntegerTag; caller_stack[i].payload_i64 = 100 + i end
assert(run(cfg, "test_static_invoke_value2", caller_stack, callee_stack) == 403)
assert(caller_stack[6].payload_i64 == 403, "static callee result must flow through ReceiveCallResults")

local direct_cfg, direct_errors = ExecToLalin.lower_outcome(kernel_with_emit(good_contract), "value2_payload_i64")
assert(not direct_cfg and table.concat(direct_errors or {}, ";"):match("EmitRegion:requires_typed_static_region_lowering"), "direct kernel EmitRegion must still reject")

local function lower_module_rejects(module, needle)
  local out, errs = ExecToLalin.lower_module_outcome(module, "kernel", "value2_payload_i64")
  local joined = table.concat(errs or {}, ";")
  assert(not out and joined:match(needle), "expected rejection matching " .. needle .. ", got: " .. joined)
end

local call_only_contract = Exec.Contract({
  Exec.RequiresResolvedCallTarget(resolved), Exec.RequiresCallFrameLayout(layout), Exec.RequiresCallArgChannel(args), Exec.RequiresCallResultChannel(results),
}, { Exec.ResolvesCallTarget(resolved), Exec.PreparesCallFrame(frame_state), Exec.ProducesCallResults(results) })
lower_module_rejects(module_with(good_callee, call_only_contract), "missing_static_region_invocation_contract")
lower_module_rejects(Exec.Module({}, { kernel_with_emit(good_contract) }), "target not in module")
lower_module_rejects(module_with(good_callee, static_contract(good_callee, { desc_kind = Exec.MetatableRegion })), "descriptor kind mismatch")
lower_module_rejects(module_with(callee_region(Exec.ReturnRegion, { nested_emit = true }), static_contract(good_callee)), "nested EmitRegion")
lower_module_rejects(module_with(callee_region(Exec.ReturnRegion, { return_term = true }), static_contract(good_callee)), "not Return")
lower_module_rejects(module_with(callee_region(Exec.MetatableRegion), static_contract(callee_region(Exec.MetatableRegion))), "unsupported_static_target_region")
lower_module_rejects(module_with(callee_region(Exec.ReturnRegion, { cont = "err" }), static_contract(good_callee)), "bound return continuation")

local unknown = RT.ResolvedCallTarget(call_ref, RT.UnknownCallTarget(callee_value), RT.UnknownTargetIdentity, RT.NotCallable)
local unknown_frame = RT.CallFrameState(call_ref, layout, args, results, unknown, RT.CallFrameUnprepared)
local unknown_contract = Exec.Contract({
  Exec.RequiresResolvedCallTarget(unknown), Exec.RequiresCallFrameLayout(layout), Exec.RequiresCallArgChannel(args), Exec.RequiresCallResultChannel(results),
  good_contract.obligations[5], good_contract.obligations[6], good_contract.obligations[7],
}, { Exec.PreparesCallFrame(unknown_frame), Exec.ProducesCallResults(results), good_contract.guarantees[4], good_contract.guarantees[5], good_contract.guarantees[6] })
lower_module_rejects(module_with(good_callee, unknown_contract), "unsupported_target_kind")

print("ok - SpongeJIT LuaExec static region invocation")
