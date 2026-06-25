#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local Emit = require("lua_compile.lalin_cfg_emit")
local Validate = require("lua_compile.lalin_cfg_validate")
local ExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local ExecToLalin = require("lua_compile.lua_exec_to_lalin_cfg_lower")
local ValueModel = require("lua_compile.lua_rt_value_model")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local StackModel = require("lua_compile.lua_rt_stack_model")
local T = Schema.get()
local RT, Exec, CFG, CC = T.LuaRT, T.LuaExec, T.LalinCFG, T.CompileContract

pcall(function()
  ffi.cdef[[
    typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
  ]]
end)

local function name(s) return CFG.Name(s) end
local function ty(s) return CFG.TypeRef(s) end
local function temp(s) return CFG.Temp(name(s)) end
local function place(s) return CFG.PlaceValue(temp(s)) end
local function param_value(s) return CFG.ParamValue(name(s)) end
local function i64(n) return CFG.ConstValue(CFG.I64Const(n)) end
local function param(s, t) return CFG.Param(name(s), ty(t), CFG.ValueParam) end
local function contract0() return CC.Contract(CC.Transfer({}, {}), {}, {}, {}) end

local function kernel(id, params, ops, ret)
  local block = CFG.Block(CFG.BlockId(name("entry")), {}, ops, CFG.Return({ place("out") }))
  local region = CFG.Region(CFG.RegionId(name(id .. "_body")), params or {}, {}, CFG.BlockId(name("entry")), { block })
  return CFG.Kernel(CFG.KernelId(name(id)), CFG.InlineSpan, params or {}, { ty(ret or "i64") }, region, contract0())
end

local function run(k, fname, ...)
  local ok, errs = Validate.validate(k)
  assert(ok, table.concat(errs, "\n"))
  local src = Emit.emit(k, { name = fname })
  assert(src:match("LuaRTValueSeq") and src:match("LuaRTVarargSource") and src:match("LuaRTStack"), "stack/sequence declarations must be emitted")
  assert(not src:match("out_tag") and not src:match("out_event_kind"), "must not emit protocol ABI")
  local native, quote_errors = Emit.compile(k, { name = fname })
  assert(native, table.concat(quote_errors or {}, "; "))
  local out = native(...)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("^-?%d+")) or out end
  native:free()
  return out, src
end

local function box_i64(n) return CFG.RuntimeBoxI64(i64(n)) end
local function seq_fixed_projection(adjustment, projection)
  local ops = {
    CFG.Let(temp("v0"), box_i64(10)),
    CFG.Let(temp("v1"), box_i64(20)),
    CFG.Let(temp("seq"), CFG.RuntimeValueSeqFixed(i64(2), { place("v0"), place("v1") })),
  }
  local seq_place = place("seq")
  if adjustment then
    ops[#ops + 1] = CFG.Let(temp("adj"), CFG.RuntimeValueSeqAdjust(seq_place, adjustment))
    seq_place = place("adj")
  end
  if projection == "count" then
    ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimeValueSeqCount(seq_place))
  elseif projection == "value0_payload" then
    ops[#ops + 1] = CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(seq_place, 0))
    ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimePayloadI64(place("elem")))
  elseif projection == "value1_tag" then
    ops[#ops + 1] = CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(seq_place, 1))
    ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimeTag(place("elem")))
  elseif projection == "value1_payload" then
    ops[#ops + 1] = CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(seq_place, 1))
    ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimePayloadI64(place("elem")))
  end
  return kernel("seq_fixed", {}, ops, "i64")
end

assert(run(seq_fixed_projection(nil, "count"), "test_seq_fixed_count") == 2)
assert(run(seq_fixed_projection(RT.ExactCount(RT.Count(1)), "count"), "test_seq_exact_count") == 1)
assert(run(seq_fixed_projection(RT.TruncateTo(RT.Count(1)), "count"), "test_seq_truncate_count") == 1)
assert(run(seq_fixed_projection(RT.TruncateTo(RT.Count(1)), "value0_payload"), "test_seq_truncate_value0") == 10)
assert(run(seq_fixed_projection(RT.FillNilTo(RT.Count(3)), "count"), "test_seq_fill_nil_count") == 3)
assert(run(seq_fixed_projection(RT.FillNilTo(RT.Count(3)), "value1_payload"), "test_seq_fill_existing_value1") == 20)

local function one_value_fill_nil_projection()
  local ops = {
    CFG.Let(temp("v0"), box_i64(33)),
    CFG.Let(temp("seq"), CFG.RuntimeValueSeqFixed(i64(1), { place("v0") })),
    CFG.Let(temp("adj"), CFG.RuntimeValueSeqAdjust(place("seq"), RT.FillNilTo(RT.Count(2)))),
    CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(place("adj"), 1)),
    CFG.Let(temp("out"), CFG.RuntimeTag(place("elem"))),
  }
  return kernel("seq_fill_nil", {}, ops, "i64")
end
assert(run(one_value_fill_nil_projection(), "test_seq_fill_nil_tag") == ValueModel.TAG.NilTag)

local function open_stack_kernel(projection)
  local params = { param("stack", "ptr(LuaRTValue)"), param("top_ptr", "ptr(i64)") }
  local ops = {
    CFG.Let(temp("top"), CFG.RuntimeTopLoad(param_value("top_ptr"))),
    CFG.Let(temp("count"), CFG.RuntimeOpenCountFromTop(place("top"), i64(1))),
    CFG.Let(temp("seq"), CFG.RuntimeValueSeqFromStack(param_value("stack"), i64(1), place("count"))),
  }
  if projection == "count" then ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimeValueSeqCount(place("seq")))
  elseif projection == "tag0" then ops[#ops + 1] = CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(place("seq"), 0)); ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimeTag(place("elem")))
  elseif projection == "payload1" then ops[#ops + 1] = CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(place("seq"), 1)); ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimePayloadI64(place("elem"))) end
  return kernel("open_stack", params, ops, "i64")
end
local stack = ffi.new("LuaRTValue[4]")
stack[1].tag = ValueModel.TAG.IntegerTag; stack[1].payload_i64 = 101
stack[2].tag = ValueModel.TAG.IntegerTag; stack[2].payload_i64 = 202
local top_ptr = ffi.new("int64_t[1]", 3)
assert(run(open_stack_kernel("count"), "test_open_stack_count", stack, top_ptr) == 2)
assert(run(open_stack_kernel("tag0"), "test_open_stack_tag0", stack, top_ptr) == ValueModel.TAG.IntegerTag)
assert(run(open_stack_kernel("payload1"), "test_open_stack_payload1", stack, top_ptr) == 202)

local function lower_outcome(events, evidence, projection)
  local unit = C.unit_from_events(events, evidence or {})
  local exec_kernel, exec_errors = ExecLower.lower(unit.source, unit.evidence)
  assert(exec_kernel, "LuaExec stack lowering rejected fixture: " .. table.concat(exec_errors or {}, "; "))
  local cfg, cfg_errors = ExecToLalin.lower_outcome(exec_kernel, projection)
  assert(cfg, "LuaExec stack outcome rejected fixture: " .. table.concat(cfg_errors or {}, "; "))
  return cfg
end

local vargs = ffi.new("LuaRTValue[3]")
vargs[0].tag = ValueModel.TAG.IntegerTag; vargs[0].payload_i64 = 7
vargs[1].tag = ValueModel.TAG.IntegerTag; vargs[1].payload_i64 = 8
vargs[2].tag = ValueModel.TAG.IntegerTag; vargs[2].payload_i64 = 9
local stack2 = ffi.new("LuaRTValue[6]")
local top2 = ffi.new("int64_t[1]", 0)
local fixed_events = { {op="VARARG", pc=1, a=1, b=0, c=3, k=false}, {op="RETURN", pc=2, a=1, b=3, c=0, k=false} }
assert(run(lower_outcome(fixed_events, {}, "count"), "test_vararg_fixed_count", stack2, top2, vargs, 3) == 2)
-- Value projection/copy coverage for fixed varargs lives in
-- test_spongejit_lua_compile_lua_rt_arity.lua; this legacy substrate test keeps
-- the fixed-count smoke check.

local stack3 = ffi.new("LuaRTValue[6]")
local top3 = ffi.new("int64_t[1]", 0)
local open_events = { {op="VARARG", pc=1, a=1, b=0, c=0, k=false}, {op="RETURN", pc=2, a=1, b=0, c=0, k=false} }
assert(run(lower_outcome(open_events, {}, "count"), "test_vararg_open_count", stack3, top3, vargs, 3) == 3)
assert(top3[0] == 4, "open VARARG must update top to base + vararg_count")
-- Open value projection/copy coverage is exercised by the arity test.

local getvarg_events = { {op="LOADI", pc=1, a=3, b=2}, {op="GETVARG", pc=2, a=1, b=0, c=3}, {op="RETURN1", pc=3, a=1} }
assert(run(lower_outcome(getvarg_events, {}, "value0_payload_i64"), "test_getvarg_integer_key", vargs, 3) == 8)
assert(run(lower_outcome(getvarg_events, {}, "value0_tag"), "test_getvarg_integer_key_tag", vargs, 3) == ValueModel.TAG.IntegerTag)

local function vararg_get_manual_kernel()
  local params = { param("vargs", "ptr(LuaRTValue)"), param("count", "i64"), param("key", "LuaRTValue") }
  local ops = {
    CFG.Let(temp("src"), CFG.RuntimeVarargSource(param_value("vargs"), param_value("count"), i64(0))),
    CFG.Let(temp("got"), CFG.RuntimeVarargGet(place("src"), param_value("key"))),
    CFG.Let(temp("out"), CFG.RuntimeTag(place("got"))),
  }
  return kernel("vararg_get_manual", params, ops, "i64")
end
local bad_string_key = ffi.new("LuaRTValue")
bad_string_key.tag = ValueModel.TAG.ShortStringTag; bad_string_key.payload_i64 = -1000000
assert(run(vararg_get_manual_kernel(), "test_getvarg_non_integer_key_safe_nil", vargs, 3, bad_string_key) == ValueModel.TAG.NilTag)
local bad_oob_key = ffi.new("LuaRTValue")
bad_oob_key.tag = ValueModel.TAG.IntegerTag; bad_oob_key.payload_i64 = 99
assert(run(vararg_get_manual_kernel(), "test_getvarg_out_of_range_key_safe_nil", vargs, 3, bad_oob_key) == ValueModel.TAG.NilTag)

local stack_model_ok, stack_model_missing = StackModel.validate_against_schema()
assert(stack_model_ok, "LuaRT stack model missing schema constructors: " .. table.concat(stack_model_missing, ","))

print("ok - SpongeJIT LuaRT stack/window/top/sequence/vararg substrate")
