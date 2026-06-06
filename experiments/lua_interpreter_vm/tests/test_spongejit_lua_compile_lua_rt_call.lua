#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local Schema = require("lua_compile.schema")
local Validate = require("lua_compile.moon_cfg_validate")
local Emit = require("lua_compile.moon_cfg_emit")
local ExecValidate = require("lua_compile.lua_exec_validate")
local ExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")
local CallModel = require("lua_compile.lua_rt_call_model")
local ArityModel = require("lua_compile.lua_rt_arity_model")
local ValueModel = require("lua_compile.lua_rt_value_model")
local T = Schema.get()
local RT, Exec, CFG, CC = T.LuaRT, T.LuaExec, T.MoonCFG, T.CompileContract

pcall(function()
  ffi.cdef[[
    typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
  ]]
end)

local function cname(s) return CFG.Name(s) end
local function cty(s) return CFG.TypeRef(s) end
local function temp(s) return CFG.Temp(cname(s)) end
local function place(s) return CFG.PlaceValue(temp(s)) end
local function param_value(s) return CFG.ParamValue(cname(s)) end
local function i64(n) return CFG.ConstValue(CFG.I64Const(n)) end
local function cfg_param(s, ty) return CFG.Param(cname(s), cty(ty), CFG.ValueParam) end
local function empty_contract() return CC.Contract(CC.Transfer({}, {}), {}, {}, {}) end

local function moon_kernel(id, params, ops, ret_ty)
  local block = CFG.Block(CFG.BlockId(cname("entry")), {}, ops, CFG.Return({ place("out") }))
  local region = CFG.Region(CFG.RegionId(cname(id .. "_body")), params or {}, {}, CFG.BlockId(cname("entry")), { block })
  return CFG.Kernel(CFG.KernelId(cname(id)), CFG.InlineSpan, params or {}, { cty(ret_ty or "i64") }, region, empty_contract())
end

local function run(k, fname, ...)
  local ok, errs = Validate.validate(k)
  assert(ok, table.concat(errs, "\n"))
  local src = Emit.emit(k, { name = fname })
  assert(not src:match("out_tag") and not src:match("out_event_kind") and not src:match("generic_for"), "must not emit protocol/fallback strings")
  assert(not src:match("helper") and not src:match("dispatch"), "must not emit helper/dispatch text")
  local fn = assert(moon.loadstring(src, "=(" .. fname .. ")"))()
  local native = assert(fn:compile())
  local out = native(...)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("^-?%d+")) or out end
  native:free()
  return out, src
end

local function frame_ref(s) return RT.FrameRef(RT.Name(s)) end
local function stack_value(frame, slot) return RT.StackValue(frame, RT.Slot(slot)) end
local function fixed_seq_from_window(frame, base, count, kind)
  local w = RT.StackWindow(kind or RT.CallWindow, frame, RT.Slot(base), RT.FixedCount(count))
  return RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(count), RT.FromStackWindow(w))
end
local function arg_shape(n) return RT.ArityShape(RT.FixedCount(n), RT.FixedCount(n), RT.ExactCount(RT.Count(n)), RT.FixedArity) end
local function result_shape(n) return RT.ArityShape(RT.FixedCount(n), RT.FixedCount(n), RT.ExactCount(RT.Count(n)), RT.FixedArity) end

local caller = frame_ref("caller")
local callee = frame_ref("callee")
local call_ref = RT.CallRef(RT.Name("call0"))
local callee_value = stack_value(caller, 0)
local closure = RT.ClosureRef(RT.Name("closure0"))
local target = RT.DirectLuaClosureTarget(callee_value, closure)
local identity = RT.LuaClosureTargetIdentity(closure, T.LuaSrc.KRef(0), 77, {})
local resolved = RT.ResolvedCallTarget(call_ref, target, identity, RT.CallableLuaClosure)
local arg_seq = fixed_seq_from_window(caller, 1, 3, RT.CallWindow)
local args = RT.CallArgChannel(call_ref, arg_seq, arg_shape(3))
local result_seq = RT.ValueSeq(RT.CallResultSeq, {}, RT.FixedCount(3), RT.FromCallResult(call_ref))
local result_channel = ArityModel.result_channel("CallFrameResultChannel", result_seq, RT.FixedCount(3))
local result_norm = ArityModel.normalization(result_seq, result_shape(3), result_channel)
local results = RT.CallResultChannel(call_ref, result_channel, result_norm)
local layout = RT.CallFrameLayout(RT.CallFrameRef(RT.Name("layout0")), caller, callee, RT.Slot(0), RT.Slot(0), RT.FixedCount(3), RT.Slot(4), RT.FixedCount(3), RT.Count(8))
local frame_state = RT.CallFrameState(call_ref, layout, args, results, resolved, RT.CallFrameUnprepared)
local ok_frame, frame_reason = CallModel.is_executable_call_frame_state(frame_state)
assert(ok_frame, tostring(frame_reason))

local function classify_kernel()
  local params = { cfg_param("callee", "LuaRTValue") }
  return moon_kernel("classify", params, {
    CFG.Let(temp("out"), CFG.RuntimeClassifyCallee(param_value("callee"))),
  }, "i64")
end

local v = ffi.new("LuaRTValue")
v.tag = ValueModel.TAG.LuaClosureTag; v.payload_i64 = 77
assert(run(classify_kernel(), "test_call_classify_lua_closure", v) == 1)
v.tag = ValueModel.TAG.IntegerTag; v.payload_i64 = 12
assert(run(classify_kernel(), "test_call_classify_integer", v) == 0)

local function target_check_kernel(target_to_check)
  local params = { cfg_param("callee", "LuaRTValue") }
  return moon_kernel("target_check", params, {
    CFG.Let(temp("ok"), CFG.RuntimeCallTargetCheck(param_value("callee"), target_to_check)),
    CFG.Let(temp("out"), CFG.ValueExpr(CFG.ConstValue(CFG.I64Const(0)))),
    CFG.Let(temp("out"), CFG.Primitive(CFG.AddI64, { i64(0), i64(0) })),
  }, "i64")
end

local function target_check_bool_kernel(target_to_check)
  local params = { cfg_param("callee", "LuaRTValue") }
  local block = CFG.Block(CFG.BlockId(cname("entry")), {}, {
    CFG.Let(temp("ok"), CFG.RuntimeCallTargetCheck(param_value("callee"), target_to_check)),
  }, CFG.Return({ place("ok") }))
  local region = CFG.Region(CFG.RegionId(cname("target_check_body")), params, {}, CFG.BlockId(cname("entry")), { block })
  return CFG.Kernel(CFG.KernelId(cname("target_check")), CFG.InlineSpan, params, { cty("bool") }, region, empty_contract())
end

v.tag = ValueModel.TAG.LuaClosureTag; v.payload_i64 = 77
assert(run(target_check_bool_kernel(resolved), "test_call_target_match", v) == true)
v.payload_i64 = 78
assert(run(target_check_bool_kernel(resolved), "test_call_target_mismatch", v) == false)
local unknown_resolved = RT.ResolvedCallTarget(call_ref, RT.UnknownCallTarget(callee_value), RT.UnknownTargetIdentity, RT.NotCallable)
assert(run(target_check_bool_kernel(unknown_resolved), "test_call_target_unknown_false", v) == false)

local function arg_store_kernel()
  local params = { cfg_param("caller_stack", "ptr(LuaRTValue)"), cfg_param("callee_stack", "ptr(LuaRTValue)") }
  return moon_kernel("arg_store", params, {
    CFG.Let(temp("seq"), CFG.RuntimeValueSeqFromStack(param_value("caller_stack"), i64(1), i64(3))),
    CFG.RuntimeCallFrameStoreArgs(param_value("callee_stack"), layout, place("seq")),
    CFG.Let(temp("elem"), CFG.RuntimeStackLoad(param_value("callee_stack"), i64(2))),
    CFG.Let(temp("out"), CFG.RuntimePayloadI64(place("elem"))),
  }, "i64")
end

local caller_stack = ffi.new("LuaRTValue[8]")
local callee_stack = ffi.new("LuaRTValue[8]")
for i = 1, 3 do caller_stack[i].tag = ValueModel.TAG.IntegerTag; caller_stack[i].payload_i64 = 100 + i end
assert(run(arg_store_kernel(), "test_call_arg_store_value2", caller_stack, callee_stack) == 103)
assert(callee_stack[2].payload_i64 == 103)

local function result_seq_kernel()
  local params = { cfg_param("callee_stack", "ptr(LuaRTValue)") }
  return moon_kernel("result_seq", params, {
    CFG.Let(temp("seq"), CFG.RuntimeCallFrameResultSeq(param_value("callee_stack"), layout, results)),
    CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(place("seq"), 2)),
    CFG.Let(temp("out"), CFG.RuntimePayloadI64(place("elem"))),
  }, "i64")
end
for i = 0, 2 do callee_stack[4 + i].tag = ValueModel.TAG.IntegerTag; callee_stack[4 + i].payload_i64 = 200 + i end
assert(run(result_seq_kernel(), "test_call_result_seq_value2", callee_stack) == 202)

local function manual_call_exec_kernel(contract)
  local ret_window = RT.StackWindow(RT.ReturnWindow, caller, RT.Slot(4), RT.FixedCount(3))
  local ret_seq = RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(3), RT.FromStackWindow(ret_window))
  local block_id = Exec.BlockId(Exec.Name("entry"))
  local params = {
    Exec.Param(Exec.Name("caller_stack"), Exec.MoonType("ptr(LuaRTValue)")),
    Exec.Param(Exec.Name("callee_stack"), Exec.MoonType("ptr(LuaRTValue)")),
  }
  local block = Exec.Block(block_id, {}, { Exec.PrepareCallFrame(frame_state), Exec.ReceiveCallResults(frame_state) }, Exec.Return(ret_seq))
  local region = Exec.Region(Exec.Name("manual_call_region"), Exec.CallRegion, params, {}, block_id, { block })
  return Exec.Kernel(Exec.Name("manual_call_kernel"), RT.Frame(caller, RT.StackRef(caller), RT.TopRef(caller), RT.NoVarargs, RT.CloseChain(caller, {}), RT.Pc(1)), region, contract)
end

local good_contract = Exec.Contract({
  Exec.RequiresResolvedCallTarget(resolved),
  Exec.RequiresCallFrameLayout(layout),
  Exec.RequiresCallArgChannel(args),
  Exec.RequiresCallResultChannel(results),
}, {
  Exec.ResolvesCallTarget(resolved),
  Exec.PreparesCallFrame(frame_state),
  Exec.ProducesCallResults(results),
})
local exec_kernel = manual_call_exec_kernel(good_contract)
local ok_exec, exec_errors = ExecValidate.kernel(exec_kernel)
assert(ok_exec, table.concat(exec_errors, ";"))
local cfg, cfg_errors = ExecToMoon.lower_outcome(exec_kernel, "value2_payload_i64")
assert(cfg, table.concat(cfg_errors or {}, ";"))
local ok_cfg, cfg_validate_errors = Validate.validate(cfg)
assert(ok_cfg, table.concat(cfg_validate_errors, ";"))
for i = 0, 2 do callee_stack[4 + i].tag = ValueModel.TAG.IntegerTag; callee_stack[4 + i].payload_i64 = 300 + i end
assert(run(cfg, "test_manual_call_region_value2", caller_stack, callee_stack) == 302)
assert(caller_stack[6].payload_i64 == 302, "ReceiveCallResults must copy third callee result to caller result base")

local missing_cfg, missing_errors = ExecToMoon.lower_outcome(manual_call_exec_kernel(Exec.Contract({}, {})), "value2_payload_i64")
assert(not missing_cfg and table.concat(missing_errors or {}, ";"):match("missing_call_contract"), "under-contracted CallRegion must reject")
local unknown_frame = RT.CallFrameState(call_ref, layout, args, results, unknown_resolved, RT.CallFrameUnprepared)
local unknown_contract = Exec.Contract({ Exec.RequiresResolvedCallTarget(unknown_resolved), Exec.RequiresCallFrameLayout(layout), Exec.RequiresCallArgChannel(args), Exec.RequiresCallResultChannel(results) }, { Exec.PreparesCallFrame(unknown_frame), Exec.ProducesCallResults(results) })
local bad_cfg, bad_errors = ExecToMoon.lower_outcome(manual_call_exec_kernel(unknown_contract), "value2_payload_i64")
assert(not bad_cfg and table.concat(bad_errors or {}, ";"):match("unsupported_target_kind"), "unknown target must reject")
local dynamic_layout = RT.CallFrameLayout(RT.CallFrameRef(RT.Name("dynamic_layout")), caller, callee, RT.Slot(0), RT.Slot(0), RT.UnknownCount("args"), RT.Slot(4), RT.FixedCount(3), RT.Count(8))
local dynamic_frame = RT.CallFrameState(call_ref, dynamic_layout, args, results, resolved, RT.CallFrameUnprepared)
assert(not CallModel.is_executable_call_frame_state(dynamic_frame), "dynamic arity call frame must not be executable")

print("ok - SpongeJIT LuaRT call-frame substrate")
