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
local T = require("lua_compile.schema").get()
local RT, Exec = T.LuaRT, T.LuaExec

local function ex_name(s) return Exec.Name(tostring(s)) end
local function rt_name(s) return RT.Name(tostring(s)) end

ffi.cdef[[
typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
typedef struct { int64_t byte_len; int64_t hash; int64_t numeric_kind; int64_t numeric_i64; double numeric_f64; } LuaRTString;
typedef struct { LuaRTValue *array; int64_t array_len; int64_t metatable_kind; int64_t index_table; int64_t newindex_table; int64_t gc_color; int64_t gc_generation; int64_t gc_epoch; int64_t barrier_epoch; int64_t barrier_count; int64_t barrier_last_child_tag; int64_t barrier_last_child_payload; } LuaRTTable;
]]

local function v(tag_name, payload)
  local x = ffi.new("LuaRTValue")
  x.tag = ValueModel.TAG[tag_name]
  x.payload_i64 = payload or 0
  x.payload_f64 = 0
  return x
end

local function compile_outcome(events, projection, name)
  local unit = C.unit_from_events(events, {})
  local exec_kernel, exec_errors = ExecLower.lower(unit.source, unit.evidence)
  assert(exec_kernel, table.concat(exec_errors or {}, "; "))
  local cfg, cfg_errors = ExecToMoon.lower_outcome(exec_kernel, projection)
  assert(cfg, table.concat(cfg_errors or {}, "; "))
  local src = Emit.emit(cfg, { name = name })
  assert(src:match("LuaRTTable") and src:match("LuaRTString") and src:match("LuaRTRawGetResult"), "object substrate declarations must be emitted")
  assert(not src:match("out_tag") and not src:match("out_event_kind"), "must not emit protocol ABI")
  local fn = assert(moon.loadstring(src, "=(" .. name .. ")"))()
  return assert(fn:compile()), src
end

local strings = ffi.new("LuaRTString[4]")
strings[0].byte_len, strings[0].hash = 3, 101
strings[1].byte_len, strings[1].hash = 5, 202

local array = ffi.new("LuaRTValue[4]")
array[0] = v("IntegerTag", 77)
array[1] = v("ShortStringTag", 0)
local tables = ffi.new("LuaRTTable[2]")
tables[0].array = array
tables[0].array_len = 2
tables[0].metatable_kind = ObjectModel.METATABLE_KIND.NoMetatable
tables[0].index_table = 0
tables[0].newindex_table = 0

local table0 = v("TableTag", 0)
local key1 = v("IntegerTag", 1)
local key2 = v("IntegerTag", 2)
local key3 = v("IntegerTag", 3)
local nilkey = v("NilTag", 0)
local intval = v("IntegerTag", 1234)
local str0 = v("ShortStringTag", 0)
local str1 = v("ShortStringTag", 1)

local get_hit = compile_outcome({ {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_gettable_raw_hit")
assert(tonumber(get_hit(tables, strings, table0, key1)) == 77)
get_hit:free()

local get_miss_tag, get_miss_src = compile_outcome({ {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} }, "value0_tag", "test_rt_gettable_raw_miss_nil_tag")
assert(get_miss_src:match(tostring(ValueModel.TAG.AbsentKeyTag)) or get_miss_src:match("AbsentKey"), "raw miss must materialize an internal absent-key sentinel before nil conversion")
assert(tonumber(get_miss_tag(tables, strings, table0, key3)) == ValueModel.TAG.NilTag)
get_miss_tag:free()

local set_kind = compile_outcome({ {op="SETTABLE", pc=1, a=2, b=3, c=1, k=false} }, "kind", "test_rt_settable_raw_set_kind")
assert(tonumber(set_kind(tables, strings, table0, key2, intval)) == OutcomeModel.OUTCOME_KIND.NormalReturnOutcome)
set_kind:free()
assert(tonumber(array[1].payload_i64) == 1234)

local set_err_kind = compile_outcome({ {op="SETTABLE", pc=1, a=2, b=3, c=1, k=false} }, "error_kind", "test_rt_settable_nil_key_error")
assert(tonumber(set_err_kind(tables, strings, table0, nilkey, intval)) == OutcomeModel.ERROR_KIND.TableIndexNilError)
set_err_kind:free()

local len_string = compile_outcome({ {op="LEN", pc=1, a=1, b=2}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_len_string")
assert(tonumber(len_string(tables, strings, str1)) == 5)
len_string:free()

local len_table = compile_outcome({ {op="LEN", pc=1, a=1, b=2}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_len_table")
assert(tonumber(len_table(tables, strings, table0)) == 2)
len_table:free()

local concat_payload = compile_outcome({ {op="CONCAT", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_concat_payload")
assert(tonumber(concat_payload(tables, strings, str0, str1)) == -8)
concat_payload:free()

-- Function-valued metamethod branches must be explicit region/call IR, and
-- remain non-executable until the call subsystem can lower them. This is a
-- validator/lowering invariant, not rejection-as-feature coverage.
local frame_ref = RT.FrameRef(rt_name("frame0"))
local frame = RT.Frame(frame_ref, RT.StackRef(frame_ref), RT.TopRef(frame_ref), RT.NoVarargs, RT.CloseChain(frame_ref, {}), RT.Pc(1))
local meta_call = Exec.EmitRegion(ex_name("__index_metamethod_call"), {}, {})
local b = Exec.Block(Exec.BlockId(ex_name("entry")), {}, { meta_call }, Exec.Return(RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)))
local r = Exec.Region(ex_name("metamethod_body"), Exec.TableGetRegion, {}, {}, Exec.BlockId(ex_name("entry")), { b })
local k = Exec.Kernel(ex_name("metamethod_kernel"), frame, r, Exec.Contract({}, {}))
local rejected = select(1, ExecToMoon.lower_outcome(k, "kind")) == nil
assert(rejected, "unresolved function-valued metamethod call region must not lower to executable MoonCFG")

print("ok - SpongeJIT LuaRT object/table/string substrate")
