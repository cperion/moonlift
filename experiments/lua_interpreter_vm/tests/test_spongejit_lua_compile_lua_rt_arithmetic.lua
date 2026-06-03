#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local C = require("lua_compile")
local ExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local ExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")
local Emit = require("lua_compile.moon_cfg_emit")
local ValueModel = require("lua_compile.lua_rt_value_model")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local ObjectModel = require("lua_compile.lua_rt_object_model")
local pvm = require("moonlift.pvm")
local T = require("lua_compile.schema").get()
local Exec, CFG, NF = T.LuaExec, T.MoonCFG, T.LuaNF

ffi.cdef[[
typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
typedef struct { int64_t byte_len; int64_t hash; int64_t numeric_kind; int64_t numeric_i64; double numeric_f64; } LuaRTString;
]]

local function v(tag_name, payload_i64, payload_f64)
  local x = ffi.new("LuaRTValue")
  x.tag = ValueModel.TAG[tag_name]
  x.payload_i64 = payload_i64 or 0
  x.payload_f64 = payload_f64 or 0
  return x
end

local function contains_class(root, target, seen)
  if type(root) ~= "table" then return false end
  seen = seen or {}; if seen[root] then return false end; seen[root] = true
  if pvm.classof(root) == target then return true end
  local cls = pvm.classof(root)
  if cls and cls.__fields then
    for _, f in ipairs(cls.__fields) do if contains_class(root[f.name], target, seen) then return true end end
  elseif not cls then
    for _, x in pairs(root) do if contains_class(x, target, seen) then return true end end
  end
  return false
end

local strings = ffi.new("LuaRTString[128]")
strings[0].byte_len, strings[0].hash, strings[0].numeric_kind, strings[0].numeric_i64, strings[0].numeric_f64 = 2, 100, ObjectModel.STRING_NUMERIC_KIND.DecimalInteger, 10, 10.0
strings[1].byte_len, strings[1].hash, strings[1].numeric_kind, strings[1].numeric_i64, strings[1].numeric_f64 = 3, 101, ObjectModel.STRING_NUMERIC_KIND.DecimalFloat, 0, 2.5
strings[2].byte_len, strings[2].hash, strings[2].numeric_kind, strings[2].numeric_i64, strings[2].numeric_f64 = 3, 102, ObjectModel.STRING_NUMERIC_KIND.NotNumeric, 0, 0.0

local function compile_add(events, projection, name)
  local unit = C.unit_from_events(events, {})
  local exec_kernel, exec_errors = ExecLower.lower(unit.source, unit.evidence)
  assert(exec_kernel, table.concat(exec_errors or {}, "; "))
  assert(contains_class(exec_kernel, Exec.ArithmeticNoMetaExpr), "ADD must lower to explicit LuaExec arithmetic semantics")
  assert(contains_class(exec_kernel, Exec.ArithmeticNumericChoice), "ADD must branch on explicit numeric arithmetic choice")
  local cfg, cfg_errors = ExecToMoon.lower_outcome(exec_kernel, projection)
  assert(cfg, table.concat(cfg_errors or {}, "; "))
  assert(contains_class(cfg, CFG.RuntimeArithmeticNoMeta), "MoonCFG must contain explicit runtime arithmetic expression")
  assert(contains_class(cfg, CFG.RuntimeArithmeticNumericOk), "MoonCFG must contain explicit numeric-ok test")
  assert(contains_class(cfg, CFG.RuntimeArithmeticErrorValue), "MoonCFG must contain explicit arithmetic error value selection")
  local forbidden = { [NF.CallProtocolExit]=true, [NF.CloseProtocolExit]=true, [NF.GenericForProtocolExit]=true, [NF.SetListProtocolExit]=true, [NF.GetVargProtocolExit]=true }
  for cls in pairs(forbidden) do assert(not contains_class(cfg, cls), "arithmetic must not contain protocol exits") end
  local src = Emit.emit(cfg, { name = name })
  assert(not src:match("out_tag") and not src:match("out_event_kind"), "arithmetic must not emit protocol ABI")
  assert(not src:match("lua_add_tvalue") and not src:match("arith_helper") and not src:match("Opcode" .. "Helper"), "arithmetic must be emitted inline, not through opaque helper")
  assert(src:match("arithmetic_error") or src:match("Arithmetic"), "nonnumeric path must remain explicit in emitted CFG")
  local fn = assert(moon.loadstring(src, "=(" .. name .. ")"))()
  return assert(fn:compile()), src
end

local add_window = {
  {op="ADD", pc=1, a=1, b=1, c=2},
  {op="MMBIN", pc=2, a=1, b=2, c="ADD"},
  {op="RETURN1", pc=3, a=1},
}
local add_no_companion = {
  {op="ADD", pc=1, a=1, b=1, c=2},
  {op="RETURN1", pc=2, a=1},
}

local ii_payload = compile_add(add_window, "value0_payload_i64", "test_rt_add_i64_i64_payload")
assert(tonumber(ii_payload(strings, v("IntegerTag", 20), v("IntegerTag", 22))) == 42)
ii_payload:free()
local ii_tag = compile_add(add_window, "value0_tag", "test_rt_add_i64_i64_tag")
assert(tonumber(ii_tag(strings, v("IntegerTag", 1), v("IntegerTag", 2))) == ValueModel.TAG.IntegerTag)
ii_tag:free()

local if_tag = compile_add(add_window, "value0_tag", "test_rt_add_i64_f64_tag")
assert(tonumber(if_tag(strings, v("IntegerTag", 2), v("FloatTag", 0, 3.5))) == ValueModel.TAG.FloatTag)
if_tag:free()
local if_payload = compile_add(add_window, "value0_payload_f64", "test_rt_add_i64_f64_payload")
assert(math.abs(tonumber(if_payload(strings, v("IntegerTag", 2), v("FloatTag", 0, 3.5))) - 5.5) < 0.00001)
if_payload:free()

local fi_payload = compile_add(add_window, "value0_payload_f64", "test_rt_add_f64_i64_payload")
assert(math.abs(tonumber(fi_payload(strings, v("FloatTag", 0, 1.25), v("IntegerTag", 4))) - 5.25) < 0.00001)
fi_payload:free()
local ff_payload = compile_add(add_window, "value0_payload_f64", "test_rt_add_f64_f64_payload")
assert(math.abs(tonumber(ff_payload(strings, v("FloatTag", 0, 1.25), v("FloatTag", 0, 2.5))) - 3.75) < 0.00001)
ff_payload:free()

local si_tag = compile_add(add_window, "value0_tag", "test_rt_add_string_i64_tag")
assert(tonumber(si_tag(strings, v("ShortStringTag", 0), v("IntegerTag", 5))) == ValueModel.TAG.IntegerTag)
si_tag:free()
local si_payload = compile_add(add_window, "value0_payload_i64", "test_rt_add_string_i64_payload")
assert(tonumber(si_payload(strings, v("ShortStringTag", 0), v("IntegerTag", 5))) == 15)
si_payload:free()
local sf_tag = compile_add(add_window, "value0_tag", "test_rt_add_string_float_tag")
assert(tonumber(sf_tag(strings, v("ShortStringTag", 1), v("IntegerTag", 1))) == ValueModel.TAG.FloatTag)
sf_tag:free()
local sf_payload = compile_add(add_window, "value0_payload_f64", "test_rt_add_string_float_payload")
assert(math.abs(tonumber(sf_payload(strings, v("ShortStringTag", 1), v("IntegerTag", 1))) - 3.5) < 0.00001)
sf_payload:free()

local err_kind = compile_add(add_window, "error_kind", "test_rt_add_nonnumeric_error_kind")
assert(tonumber(err_kind(strings, v("NilTag", 0), v("IntegerTag", 4))) == OutcomeModel.ERROR_KIND.ArithmeticError)
err_kind:free()
local err_value_tag = compile_add(add_window, "error_value_tag", "test_rt_add_nonnumeric_error_value_tag")
assert(tonumber(err_value_tag(strings, v("FalseTag", 0), v("IntegerTag", 4))) == ValueModel.TAG.FalseTag)
err_value_tag:free()
local err_value_right_tag = compile_add(add_window, "error_value_tag", "test_rt_add_nonnumeric_right_error_value_tag")
assert(tonumber(err_value_right_tag(strings, v("IntegerTag", 4), v("ShortStringTag", 2))) == ValueModel.TAG.ShortStringTag)
err_value_right_tag:free()

-- The completion fixture form without an explicit companion still compiles as
-- the current no-metamethod arithmetic slice: numeric success plus typed error
-- path. Full metamethod/call semantics remain rejected until CallRegion lowers.
local no_companion_kind = compile_add(add_no_companion, "kind", "test_rt_add_no_companion_kind")
assert(tonumber(no_companion_kind(strings, v("IntegerTag", 5), v("IntegerTag", 6))) == OutcomeModel.OUTCOME_KIND.NormalReturnOutcome)
no_companion_kind:free()

local bad_unit = C.unit_from_events({ {op="MMBIN", pc=1, a=1, b=2, c="ADD"}, {op="RETURN0", pc=2} }, {})
local bad_exec, bad_errors = ExecLower.lower(bad_unit.source, bad_unit.evidence)
assert(not bad_exec, "standalone MMBIN must not compile as success")
assert(table.concat(bad_errors or {}, "; "):match("unsupported_instruction:MMBIN"), table.concat(bad_errors or {}, "; "))

print("ok - SpongeJIT LuaRT arithmetic semantics")
