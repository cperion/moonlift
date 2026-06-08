#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local Emit = require("lua_compile.moon_cfg_emit")
local Validate = require("lua_compile.moon_cfg_validate")
local ExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local ExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")
local ValueModel = require("lua_compile.lua_rt_value_model")
local T = Schema.get()
local RT, CFG, CC = T.LuaRT, T.MoonCFG, T.CompileContract

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
  assert(not src:match("out_tag") and not src:match("out_event_kind") and not src:match("generic_for"), "must not emit protocol/fallback strings")
  local fn = assert(moon.loadstring(src, "=(" .. fname .. ")"))()
  local native = assert(fn:compile())
  local out = native(...)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("^-?%d+")) or out end
  native:free()
  return out, src
end

local function run_quote(k, fname, ...)
  local ok, errs = Validate.validate(k)
  assert(ok, table.concat(errs, "\n"))
  local native, compiled_or_errors = Emit.compile(k, { name = fname })
  assert(native, table.concat(compiled_or_errors or {}, "; "))
  local out = native(...)
  if type(out) == "cdata" then out = tonumber(out) or tonumber(tostring(out):match("^-?%d+")) or out end
  native:free()
  return out
end

local function box_i64(n) return CFG.RuntimeBoxI64(i64(n)) end

local function normalize_projection(adjustment, projection)
  local ops = {
    CFG.Let(temp("v0"), box_i64(10)),
    CFG.Let(temp("v1"), box_i64(20)),
    CFG.Let(temp("seq"), CFG.RuntimeValueSeqFixed(i64(2), { place("v0"), place("v1") })),
  }
  local wanted = 2
  if adjustment.kind == "FillNilTo" or adjustment.kind == "TruncateTo" or adjustment.kind == "ExactCount" then wanted = adjustment.count.n or adjustment.count.value or adjustment.count.count or 0 end
  local shape = RT.ArityShape(RT.FixedCount(2), RT.FixedCount(wanted), adjustment, RT.FixedArity)
  ops[#ops + 1] = CFG.Let(temp("norm"), CFG.RuntimeValueSeqNormalize(place("seq"), shape))
  if projection == "count" then
    ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimeValueSeqCount(place("norm")))
  elseif projection == "value2_tag" then
    ops[#ops + 1] = CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(place("norm"), 2))
    ops[#ops + 1] = CFG.Let(temp("out"), CFG.RuntimeTag(place("elem")))
  end
  return kernel("arity_normalize", {}, ops, "i64")
end

assert(run(normalize_projection(RT.TruncateTo(RT.Count(1)), "count"), "test_arity_truncate_count") == 1)
assert(run(normalize_projection(RT.FillNilTo(RT.Count(3)), "count"), "test_arity_fill_count") == 3)
assert(run(normalize_projection(RT.FillNilTo(RT.Count(3)), "value2_tag"), "test_arity_fill_value2_nil") == ValueModel.TAG.NilTag)
assert(run_quote(normalize_projection(RT.TruncateTo(RT.Count(1)), "count"), "quote_arity_truncate_count") == 1)
assert(run_quote(normalize_projection(RT.FillNilTo(RT.Count(3)), "value2_tag"), "quote_arity_fill_value2_nil") == ValueModel.TAG.NilTag)

local function stack_seq_projection(index)
  local params = { param("stack", "ptr(LuaRTValue)") }
  local ops = {
    CFG.Let(temp("seq"), CFG.RuntimeValueSeqFromStack(param_value("stack"), i64(0), i64(4))),
    CFG.Let(temp("elem"), CFG.RuntimeValueSeqValue(place("seq"), index)),
    CFG.Let(temp("out"), CFG.RuntimePayloadI64(place("elem"))),
  }
  return kernel("stack_seq_projection", params, ops, "i64")
end

local stack = ffi.new("LuaRTValue[4]")
for i = 0, 3 do stack[i].tag = ValueModel.TAG.IntegerTag; stack[i].payload_i64 = (i + 1) * 11 end
assert(run(stack_seq_projection(2), "test_stack_seq_value2", stack) == 33)
assert(run(stack_seq_projection(3), "test_stack_seq_value3", stack) == 44)
assert(run_quote(stack_seq_projection(2), "quote_stack_seq_value2", stack) == 33)

local function seq_store_kernel()
  local params = { param("src", "ptr(LuaRTValue)"), param("dst", "ptr(LuaRTValue)") }
  local ops = {
    CFG.Let(temp("seq"), CFG.RuntimeValueSeqFromStack(param_value("src"), i64(0), i64(3))),
    CFG.RuntimeValueSeqStore(param_value("dst"), i64(0), place("seq")),
    CFG.Let(temp("elem"), CFG.RuntimeStackLoad(param_value("dst"), i64(2))),
    CFG.Let(temp("out"), CFG.RuntimePayloadI64(place("elem"))),
  }
  return kernel("seq_store", params, ops, "i64")
end
local dst = ffi.new("LuaRTValue[3]")
assert(run(seq_store_kernel(), "test_seq_store_three_values", stack, dst) == 33)
assert(dst[2].payload_i64 == 33, "RuntimeValueSeqStore must copy value2 into destination stack")
local quote_dst = ffi.new("LuaRTValue[8]")
assert(run_quote(seq_store_kernel(), "quote_seq_store_three_values", stack, quote_dst) == 33)
assert(quote_dst[2].payload_i64 == 33, "quote RuntimeValueSeqStore must copy value2 into destination stack")

local function type_test_kernel()
  local ops = {
    CFG.Let(temp("v"), CFG.RuntimeBoxI64(i64(99))),
    CFG.Let(temp("out"), CFG.RuntimeTypeTest(place("v"), RT.IsInteger)),
  }
  return kernel("type_test_integer", {}, ops, "bool")
end
assert(run_quote(type_test_kernel(), "quote_type_test_integer") == true)

local function lower_outcome(events, projection)
  local unit = C.unit_from_events(events, {})
  local exec_kernel, exec_errors = ExecLower.lower(unit.source, unit.evidence)
  assert(exec_kernel, "LuaExec lower rejected fixture: " .. table.concat(exec_errors or {}, "; "))
  local cfg, cfg_errors = ExecToMoon.lower_outcome(exec_kernel, projection)
  assert(cfg, "LuaExec->MoonCFG rejected fixture: " .. table.concat(cfg_errors or {}, "; "))
  return cfg
end

local vargs = ffi.new("LuaRTValue[3]")
for i = 0, 2 do vargs[i].tag = ValueModel.TAG.IntegerTag; vargs[i].payload_i64 = 70 + i end
local stack2 = ffi.new("LuaRTValue[8]")
local top2 = ffi.new("int64_t[1]", 0)
local vararg_events = { {op="VARARG", pc=1, a=1, b=0, c=4, k=false}, {op="RETURN", pc=2, a=1, b=4, c=0, k=false} }
assert(run(lower_outcome(vararg_events, "count"), "test_vararg_fixed_count3", stack2, top2, vargs, 3) == 3)
assert(run(lower_outcome(vararg_events, "value2_payload_i64"), "test_vararg_fixed_value2", stack2, top2, vargs, 3) == 72)

local return3_events = { {op="RETURN", pc=1, a=1, b=4, c=0, k=false} }
local stack3 = ffi.new("LuaRTValue[5]")
local top3 = ffi.new("int64_t[1]", 4)
local slot_values = {}
for i = 1, 3 do
  stack3[i].tag = ValueModel.TAG.IntegerTag; stack3[i].payload_i64 = i * 11
  slot_values[i] = ffi.new("LuaRTValue"); slot_values[i].tag = ValueModel.TAG.IntegerTag; slot_values[i].payload_i64 = i * 11
end
assert(run(lower_outcome(return3_events, "count"), "test_return3_count", stack3, top3, slot_values[1], slot_values[2], slot_values[3]) == 3)
assert(run(lower_outcome(return3_events, "value2_payload_i64"), "test_return3_value2", stack3, top3, slot_values[1], slot_values[2], slot_values[3]) == 33)
assert(run(lower_outcome(return3_events, "value3_tag"), "test_return3_oob_nil", stack3, top3, slot_values[1], slot_values[2], slot_values[3]) == ValueModel.TAG.NilTag)

print("ok - SpongeJIT LuaRT arity/value-sequence execution")
