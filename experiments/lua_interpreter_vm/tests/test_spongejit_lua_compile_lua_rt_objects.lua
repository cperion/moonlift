#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")
local C = require("lua_compile")
local ExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local ExecToLalin = require("lua_compile.lua_exec_to_lalin_cfg_lower")
local Emit = require("lua_compile.lalin_cfg_emit")
local ValueModel = require("lua_compile.lua_rt_value_model")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local ObjectModel = require("lua_compile.lua_rt_object_model")
local T = require("lua_compile.schema").get()
local RT, Exec = T.LuaRT, T.LuaExec

local function ex_name(s) return Exec.Name(tostring(s)) end
local function rt_name(s) return RT.Name(tostring(s)) end

ffi.cdef(ValueModel.FFI_CDEF .. "\n" .. ObjectModel.FFI_CDEF)

assert(ffi.offsetof("LuaRTTable", "hash") == 16, "LuaRTTable.hash offset must match Lalin TYPE_DECL")
assert(ffi.offsetof("LuaRTTable", "hash_capacity") == 24, "LuaRTTable.hash_capacity offset must match Lalin TYPE_DECL")
assert(ffi.offsetof("LuaRTTable", "hash_count") == 32, "LuaRTTable.hash_count offset must match Lalin TYPE_DECL")
assert(ffi.offsetof("LuaRTTable", "metatable_kind") == 40, "LuaRTTable.metatable_kind offset must match Lalin TYPE_DECL")

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
  local cfg, cfg_errors = ExecToLalin.lower_outcome(exec_kernel, projection)
  assert(cfg, table.concat(cfg_errors or {}, "; "))
  local src = Emit.emit(cfg, { name = name })
  assert(src:match("LuaRTTable") and src:match("LuaRTString") and src:match("LuaRTRawGetResult"), "object substrate declarations must be emitted")
  assert(not src:match("out_tag") and not src:match("out_event_kind"), "must not emit protocol ABI")
  local native, quote_errors = Emit.compile(cfg, { name = name })
  assert(native, table.concat(quote_errors or {}, "; "))
  return native, src
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
tables[0].hash = nil
tables[0].hash_capacity = 0
tables[0].hash_count = 0
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

local hash = ffi.new("LuaRTTableHashEntry[8]")
hash[0].state = ObjectModel.HASH_ENTRY_STATE.Occupied
hash[0].key = key3
hash[0].value = v("IntegerTag", 333)
tables[0].hash = hash
tables[0].hash_capacity = 8
tables[0].hash_count = 1

local get_hash_hit = compile_outcome({ {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_gettable_hash_hit")
assert(tonumber(get_hash_hit(tables, strings, table0, key3)) == 333)
get_hash_hit:free()

local meta_table = v("TableTag", 1)
tables[1].array = array
tables[1].array_len = 99
tables[1].hash = nil
tables[1].hash_capacity = 0
tables[1].hash_count = 0
local get_meta_kind = compile_outcome({ {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} }, "kind", "test_rt_gettable_metatable_not_raw_success")
tables[1].metatable_kind = ObjectModel.METATABLE_KIND.IndexFunction
assert(tonumber(get_meta_kind(tables, strings, meta_table, key1)) == OutcomeModel.OUTCOME_KIND.LuaErrorOutcome)
get_meta_kind:free()

local set_meta_kind = compile_outcome({ {op="SETTABLE", pc=1, a=2, b=3, c=1, k=false} }, "kind", "test_rt_settable_metatable_not_raw_success")
tables[1].metatable_kind = ObjectModel.METATABLE_KIND.NewIndexFunction
assert(tonumber(set_meta_kind(tables, strings, meta_table, key1, intval)) == OutcomeModel.OUTCOME_KIND.LuaErrorOutcome)
set_meta_kind:free()

tables[1].metatable_kind = ObjectModel.METATABLE_KIND.NoMetatable

local set_hash_kind = compile_outcome({ {op="SETTABLE", pc=1, a=2, b=3, c=1, k=false} }, "kind", "test_rt_settable_hash_update_kind")
assert(tonumber(set_hash_kind(tables, strings, table0, key3, intval)) == OutcomeModel.OUTCOME_KIND.NormalReturnOutcome)
set_hash_kind:free()
assert(tonumber(hash[0].value.payload_i64) == 1234)
assert(tonumber(tables[0].hash_count) == 1)

local len_string = compile_outcome({ {op="LEN", pc=1, a=1, b=2}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_len_string")
assert(tonumber(len_string(tables, strings, str1)) == 5)
len_string:free()

local len_table = compile_outcome({ {op="LEN", pc=1, a=1, b=2}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_len_table")
assert(tonumber(len_table(tables, strings, table0)) == 2)
-- Table LEN must not evaluate a string-bank access while deciding the table path.
assert(tonumber(len_table(tables, ffi.cast("LuaRTString *", nil), table0)) == 2)
len_table:free()

local len_string_safe = compile_outcome({ {op="LEN", pc=1, a=1, b=2}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_len_string_no_table_touch")
-- String LEN must not evaluate a table-bank access while deciding the string path.
assert(tonumber(len_string_safe(ffi.cast("LuaRTTable *", nil), strings, str1)) == 5)
len_string_safe:free()

tables[1].metatable_kind = ObjectModel.METATABLE_KIND.LenFunction
local len_meta = compile_outcome({ {op="LEN", pc=1, a=1, b=2}, {op="RETURN1", pc=2, a=1} }, "kind", "test_rt_len_table_metatable_errors")
assert(tonumber(len_meta(tables, strings, meta_table)) == OutcomeModel.OUTCOME_KIND.LuaErrorOutcome, "table LEN with metatable must produce a typed error, not sentinel normal success")
len_meta:free()

local concat_payload = compile_outcome({ {op="CONCAT", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} }, "value0_payload_i64", "test_rt_concat_payload")
assert(tonumber(concat_payload(tables, strings, str0, str1)) == -8)
concat_payload:free()

local concat_bad_kind = compile_outcome({ {op="CONCAT", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} }, "kind", "test_rt_concat_nonstring_errors_no_string_touch")
assert(tonumber(concat_bad_kind(tables, ffi.cast("LuaRTString *", nil), intval, v("IntegerTag", 2))) == OutcomeModel.OUTCOME_KIND.LuaErrorOutcome, "unsupported CONCAT must produce a typed error, not nil normal success")
concat_bad_kind:free()

-- Function-valued metamethod branches must be explicit region/call IR, and
-- remain non-executable until the call subsystem can lower them. This is a
-- validator/lowering invariant, not rejection-as-feature coverage.
local frame_ref = RT.FrameRef(rt_name("frame0"))
local frame = RT.Frame(frame_ref, RT.StackRef(frame_ref), RT.TopRef(frame_ref), RT.NoVarargs, RT.CloseChain(frame_ref, {}), RT.Pc(1))
local meta_call = Exec.EmitRegion(ex_name("__index_metamethod_call"), {}, {})
local b = Exec.Block(Exec.BlockId(ex_name("entry")), {}, { meta_call }, Exec.Return(RT.ValueSeq(RT.FixedSeq, {}, RT.FixedCount(0), RT.FromLiteralValues)))
local r = Exec.Region(ex_name("metamethod_body"), Exec.TableGetRegion, {}, {}, Exec.BlockId(ex_name("entry")), { b })
local k = Exec.Kernel(ex_name("metamethod_kernel"), frame, r, Exec.Contract({}, {}))
local rejected = select(1, ExecToLalin.lower_outcome(k, "kind")) == nil
assert(rejected, "unresolved function-valued metamethod call region must not lower to executable LalinCFG")

print("ok - SpongeJIT LuaRT object/table/string substrate")
