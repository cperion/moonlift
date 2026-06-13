-- moon_cfg_quote_emit.lua -- quote-first MoonCFG -> Moonlift semantic emitter.
--
-- This module is the primary home for semantic MoonCFG emission.  New lowering
-- must construct Moonlift through moon.* typed quotes/splices (moon.func,
-- moon.stmts, moon.expr, moon.type, moon.params, moon.fields, ...).  The legacy
-- hand-concatenating source renderer lives in moon_cfg_emit_source_compat.lua
-- for compatibility/debug serialization only.

local moon = require("moonlift.host")
local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local CFG, RT = T.MoonCFG, T.LuaRT
local Validate = require("lua_compile.moon_cfg_validate")
local ValueModel = require("lua_compile.lua_rt_value_model")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local StackModel = require("lua_compile.lua_rt_stack_model")
local ObjectModel = require("lua_compile.lua_rt_object_model")
local CDataModel = require("lua_compile.lua_rt_cdata_model")
local CallModel = require("lua_compile.lua_rt_call_model")

local M = {}
local function cls(v) return pvm.classof(v) end
local function n(v) return tonumber(v) or 0 end

local function render_name(name)
  local s = tostring(name and name.text or name or "")
  s = s:gsub("[^%w_]", "_")
  if s == "" then s = "_" end
  if s:match("^%d") then s = "_" .. s end
  return s
end

local function check_kernel(kernel)
  local ok, errors = Validate.validate(kernel)
  if not ok then
    return nil, errors or { "moon_cfg_quote_emit:validation_failed" }
  end
  return true, nil
end

local function unsupported(kernel, why)
  local name = kernel and kernel.id and kernel.id.name and kernel.id.name.text or "kernel"
  return nil, { "moon_cfg_quote_emit:not_yet_migrated:" .. tostring(name) .. (why and (":" .. tostring(why)) or "") }
end

local fresh_id = 0
local function fresh(prefix)
  fresh_id = fresh_id + 1
  return "spongejit_quote_" .. prefix .. tostring(fresh_id)
end

local TY_VALUE = moon.path_named(ValueModel.TYPE_NAME)
local TY_OUTCOME = moon.path_named(OutcomeModel.TYPE_NAME)
local TY_SEQ = moon.path_named(StackModel.SEQ_TYPE_NAME)
local TY_VARARG = moon.path_named(StackModel.VARARG_TYPE_NAME)
local TY_CALL_FRAME = moon.path_named(CallModel.FRAME_TYPE_NAME)
local TY_STRING = moon.path_named(ObjectModel.STRING_TYPE_NAME)
local TY_TABLE = moon.path_named(ObjectModel.TABLE_TYPE_NAME)
local TY_HASH_ENTRY = moon.path_named(ObjectModel.HASH_ENTRY_TYPE_NAME)
local TY_RAW_GET = moon.path_named(ObjectModel.RAW_GET_TYPE_NAME)
local TY_CDATA = moon.path_named(CDataModel.TYPE_NAME)
local TY_VALUE_PTR = moon.ptr(TY_VALUE)
local TY_STRING_PTR = moon.ptr(TY_STRING)
local TY_TABLE_PTR = moon.ptr(TY_TABLE)
local TY_HASH_ENTRY_PTR = moon.ptr(TY_HASH_ENTRY)
local TY_I64_PTR = moon.ptr(moon.i64)

local function type_from_moon_string(s)
  s = tostring(s or "i64")
  if s == "void" then return moon.void
  elseif s == "bool" then return moon.bool
  elseif s == "i8" then return moon.i8
  elseif s == "i16" then return moon.i16
  elseif s == "i32" then return moon.i32
  elseif s == "i64" then return moon.i64
  elseif s == "u8" then return moon.u8
  elseif s == "u16" then return moon.u16
  elseif s == "u32" then return moon.u32
  elseif s == "u64" then return moon.u64
  elseif s == "f32" then return moon.f32
  elseif s == "f64" then return moon.f64
  elseif s == "index" then return moon.index
  elseif s == ValueModel.TYPE_NAME then return TY_VALUE
  elseif s == OutcomeModel.TYPE_NAME then return TY_OUTCOME
  elseif s == StackModel.SEQ_TYPE_NAME then return TY_SEQ
  elseif s == StackModel.VARARG_TYPE_NAME then return TY_VARARG
  elseif s == CallModel.FRAME_TYPE_NAME then return TY_CALL_FRAME
  end
  local inner = s:match("^ptr%((.*)%)$")
  if inner then return moon.ptr(type_from_moon_string(inner)) end
  return moon.path_named(s)
end

local function type_from_ref(ref)
  return type_from_moon_string(ref and ref.moon_type or ref)
end

local function q_name(name, ty)
  assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), "q_name expects an identifier")
  local HT = moon.default_session.T
  local Tr, Bind = HT.MoonTree, HT.MoonBind
  local tv = ty and moon.as_type_value(ty, "q_name type must be a Moonlift type") or nil
  return moon.expr_from_asdl(Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name)), tv, name, { ref_name = name })
end

local function q_i64(v) return moon.int(math.floor(n(v))):as(moon.i64) end
local function q_index(v) return moon.int(math.floor(n(v))):as(moon.index) end
local function q_f64(v) return moon.float(tonumber(v) or 0, moon.f64) end
local function q_bool(v) return moon.bool_lit(v and true or false) end
local function q_null_value_ptr() return moon.expr[[as(ptr(LuaRTValue), as(i64, 0))]] end
local function tag_value(name) return q_i64(ValueModel.tag_value(name)) end
local function seq_kind_value(name) return q_i64(StackModel.seq_kind_value(name)) end
local function vararg_kind_value(name) return q_i64(StackModel.vararg_kind_value(name)) end
local function outcome_kind_value(name) return q_i64(OutcomeModel.outcome_kind_value(name)) end
local function error_kind_value(kind) return q_i64(OutcomeModel.error_kind_value(kind)) end
local function yield_kind_value(kind) return q_i64(OutcomeModel.yield_kind_value(kind)) end

local function nil_value()
  return moon.expr{ tag = tag_value("NilTag") }[[
    LuaRTValue { tag = @{tag}, payload_i64 = 0, payload_f64 = 0.0 }
  ]]
end

local function rt_value(tag, payload_i64, payload_f64)
  return moon.expr{ tag = tag, payload_i64 = payload_i64 or q_i64(0), payload_f64 = payload_f64 or q_f64(0) }[[
    LuaRTValue { tag = @{tag}, payload_i64 = @{payload_i64}, payload_f64 = @{payload_f64} }
  ]]
end

local function seq_value_at(seq, index)
  index = tonumber(index) or 0
  local inline
  if index == 0 then
    inline = moon.expr{seq = seq}[[@{seq}.value0]]
  elseif index == 1 then
    inline = moon.expr{seq = seq}[[@{seq}.value1]]
  else
    local idx = q_i64(index)
    local buffer = moon.expr{seq = seq}[[@{seq}.buffer]]
    local base = moon.expr{seq = seq}[[@{seq}.base]]
    inline = buffer:index((base + idx):as(moon.index))
  end
  if index >= 2 then
    return moon.expr{ idx = q_i64(index), seq = seq, fallback = nil_value(), inline = inline }[[
      block seq_value_at() -> LuaRTValue
        if as(i64, @{idx}) >= @{seq}.count then yield @{fallback} end
        if @{seq}.buffer == as(ptr(LuaRTValue), as(i64, 0)) then yield @{fallback} end
        yield @{inline}
      end
    ]]
  end
  return moon.expr{ idx = q_i64(index), seq = seq, fallback = nil_value(), inline = inline }[[
    block seq_value_at() -> LuaRTValue
      if as(i64, @{idx}) >= @{seq}.count then yield @{fallback} end
      yield @{inline}
    end
  ]]
end

local function buffer_value_at(buffer, base, count, index)
  local idx = q_i64(index)
  local elem = buffer:index((base + idx):as(moon.index))
  return moon.expr{ idx = idx, buffer = buffer, count = count, fallback = nil_value(), elem = elem }[[
    block buffer_value_at() -> LuaRTValue
      if as(i64, @{idx}) >= @{count} then yield @{fallback} end
      if @{buffer} == as(ptr(LuaRTValue), as(i64, 0)) then yield @{fallback} end
      yield @{elem}
    end
  ]]
end


local function string_numeric_kind_value(name) return q_i64(ObjectModel.string_numeric_kind_value(name)) end

local function is_string_expr(v)
  return moon.expr{ v = v, short_tag = tag_value("ShortStringTag"), long_tag = tag_value("LongStringTag") }[[@{v}.tag == @{short_tag} or @{v}.tag == @{long_tag}]]
end

local function numeric_kind_safe(strings, value)
  return moon.expr{ strings = strings, v = value, int_tag = tag_value("IntegerTag"), float_tag = tag_value("FloatTag"), is_string = is_string_expr(value), dec_i = string_numeric_kind_value("DecimalInteger"), dec_f = string_numeric_kind_value("DecimalFloat") }[[
    block rt_num_kind() -> i64
      if @{v}.tag == @{int_tag} then yield as(i64, 1) end
      if @{v}.tag == @{float_tag} then yield as(i64, 2) end
      if @{is_string} then
        if @{v}.payload_i64 >= as(i64, 0) then
          let idx: index = as(index, @{v}.payload_i64)
          if @{strings}[idx].numeric_kind == @{dec_i} then yield as(i64, 1) end
          if @{strings}[idx].numeric_kind == @{dec_f} then yield as(i64, 2) end
        end
      end
      yield as(i64, 0)
    end
  ]]
end

local function numeric_i64_safe(strings, value)
  return moon.expr{ strings = strings, v = value, int_tag = tag_value("IntegerTag"), is_string = is_string_expr(value), dec_i = string_numeric_kind_value("DecimalInteger") }[[
    block rt_num_i64() -> i64
      if @{v}.tag == @{int_tag} then yield @{v}.payload_i64 end
      if @{is_string} then
        if @{v}.payload_i64 >= as(i64, 0) then
          let idx: index = as(index, @{v}.payload_i64)
          if @{strings}[idx].numeric_kind == @{dec_i} then yield @{strings}[idx].numeric_i64 end
        end
      end
      yield as(i64, 0)
    end
  ]]
end

local function numeric_f64_safe(strings, value)
  return moon.expr{ strings = strings, v = value, int_tag = tag_value("IntegerTag"), float_tag = tag_value("FloatTag"), is_string = is_string_expr(value), dec_i = string_numeric_kind_value("DecimalInteger"), dec_f = string_numeric_kind_value("DecimalFloat") }[[
    block rt_num_f64() -> f64
      if @{v}.tag == @{int_tag} then yield as(f64, @{v}.payload_i64) end
      if @{v}.tag == @{float_tag} then yield @{v}.payload_f64 end
      if @{is_string} then
        if @{v}.payload_i64 >= as(i64, 0) then
          let idx: index = as(index, @{v}.payload_i64)
          if @{strings}[idx].numeric_kind == @{dec_i} then yield as(f64, @{strings}[idx].numeric_i64) end
          if @{strings}[idx].numeric_kind == @{dec_f} then yield @{strings}[idx].numeric_f64 end
        end
      end
      yield 0.0
    end
  ]]
end

local function arithmetic_numeric_ok(op, strings, left, right)
  if not op or op.kind ~= "ArithAdd" then return nil, "unsupported_arithmetic_op:" .. tostring(op and op.kind) end
  local lk, rk = numeric_kind_safe(strings, left), numeric_kind_safe(strings, right)
  return moon.expr{ lk = lk, rk = rk }[[@{lk} ~= as(i64, 0) and @{rk} ~= as(i64, 0)]]
end

local function arithmetic_error_value(op, _strings, left, right)
  if not op or op.kind ~= "ArithAdd" then return nil, "unsupported_arithmetic_op:" .. tostring(op and op.kind) end
  local left_prim = moon.expr{ l = left, int_tag = tag_value("IntegerTag"), float_tag = tag_value("FloatTag") }[[@{l}.tag == @{int_tag} or @{l}.tag == @{float_tag}]]
  return moon.expr{ lp = left_prim, l = left, r = right }[[
    LuaRTValue { tag = select(@{lp}, @{r}.tag, @{l}.tag), payload_i64 = select(@{lp}, @{r}.payload_i64, @{l}.payload_i64), payload_f64 = select(@{lp}, @{r}.payload_f64, @{l}.payload_f64) }
  ]]
end

local function arithmetic_no_meta(op, strings, left, right)
  if not op or op.kind ~= "ArithAdd" then return nil, "unsupported_arithmetic_op:" .. tostring(op and op.kind) end
  local lk, rk = numeric_kind_safe(strings, left), numeric_kind_safe(strings, right)
  local both_int = moon.expr{ lk = lk, rk = rk }[[@{lk} == as(i64, 1) and @{rk} == as(i64, 1)]]
  local numeric = moon.expr{ lk = lk, rk = rk }[[@{lk} ~= as(i64, 0) and @{rk} ~= as(i64, 0)]]
  local int_sum = numeric_i64_safe(strings, left) + numeric_i64_safe(strings, right)
  local float_sum = numeric_f64_safe(strings, left) + numeric_f64_safe(strings, right)
  return moon.expr{ both_int = both_int, numeric = numeric, int_tag = tag_value("IntegerTag"), float_tag = tag_value("FloatTag"), nil_tag = tag_value("NilTag"), int_sum = int_sum, float_sum = float_sum }[[
    LuaRTValue { tag = select(@{both_int}, @{int_tag}, select(@{numeric}, @{float_tag}, @{nil_tag})), payload_i64 = select(@{both_int}, @{int_sum}, as(i64, 0)), payload_f64 = select((@{numeric} and not @{both_int}), @{float_sum}, 0.0) }
  ]]
end


local value_to_expr
local set_lua_value
local index_place_of
local function metatable_kind_value(name) return q_i64(ObjectModel.metatable_kind_value(name)) end
local function hash_state_value(name) return q_i64(ObjectModel.hash_entry_state_value(name)) end
local function gc_color_value(name) return q_i64(ObjectModel.gc_color_value(name)) end
local function gc_generation_value(name) return q_i64(ObjectModel.gc_generation_value(name)) end

local function is_tag_expr(v, tag_name)
  return moon.expr{ v = v, tag = tag_value(tag_name) }[[@{v}.tag == @{tag}]]
end

local function is_hash_key_expr(v)
  return moon.expr{ v = v, int_tag = tag_value("IntegerTag"), short_tag = tag_value("ShortStringTag"), long_tag = tag_value("LongStringTag") }[[
    @{v}.tag == @{int_tag} or @{v}.tag == @{short_tag} or @{v}.tag == @{long_tag}
  ]]
end

local function collectable_expr(v)
  local tags = { "ShortStringTag", "LongStringTag", "TableTag", "LuaClosureTag", "CClosureTag", "UserdataTag", "ThreadTag", "CDataTag" }
  local cond = q_bool(false)
  for _, t in ipairs(tags) do cond = moon.expr{ prev = cond, v = v, tag = tag_value(t) }[[@{prev} or @{v}.tag == @{tag}]] end
  return cond
end

local function hash_key_equal_expr(entry_key, key)
  return moon.expr{ e = entry_key, k = key, int_tag = tag_value("IntegerTag"), short_tag = tag_value("ShortStringTag"), long_tag = tag_value("LongStringTag") }[[
    (@{e}.tag == @{int_tag} and @{k}.tag == @{int_tag} and @{e}.payload_i64 == @{k}.payload_i64) or
    ((@{e}.tag == @{short_tag} or @{e}.tag == @{long_tag}) and (@{k}.tag == @{short_tag} or @{k}.tag == @{long_tag}) and @{e}.payload_i64 == @{k}.payload_i64)
  ]]
end

local function raw_get_initial()
  return moon.expr{ absent_tag = tag_value("AbsentKeyTag"), absent_payload = q_i64(ValueModel.payload_for_nil_kind(RT.AbsentKeySentinel)) }[[
    LuaRTRawGetResult { hit = false, value = LuaRTValue { tag = @{absent_tag}, payload_i64 = @{absent_payload}, payload_f64 = 0.0 } }
  ]]
end

local function emit_raw_get_let(builder, env, dst, expr_node)
  local tables, tablev, key = value_to_expr(expr_node.tables, env), value_to_expr(expr_node.table_value, env), value_to_expr(expr_node.key, env)
  local dst_ref = builder:var(dst, TY_RAW_GET, raw_get_initial())
  env[dst] = dst_ref
  local done = builder:var(dst .. "_done", moon.bool, q_bool(false))
  builder:if_(moon.expr{ tv = tablev, tag = tag_value("TableTag") }[[@{tv}.tag == @{tag} and @{tv}.payload_i64 >= as(i64, 0)]], function(b)
    local tidx = b:let(dst .. "_table_index", moon.index, tablev:field("payload_i64", moon.i64):as(moon.index))
    local tbl = tables:index(tidx)
    b:if_(tbl:field("metatable_kind", moon.i64):eq(metatable_kind_value("NoMetatable")), function(nb)
      nb:if_(moon.expr{ k = key, int_tag = tag_value("IntegerTag"), tbl = tbl }[[@{k}.tag == @{int_tag} and @{k}.payload_i64 >= as(i64, 1) and @{k}.payload_i64 <= @{tbl}.array_len and @{tbl}.array ~= as(ptr(LuaRTValue), as(i64, 0))]], function(ab)
        ab:set(dst_ref:place():field("hit", moon.bool), q_bool(true))
        set_lua_value(ab, dst_ref:place():field("value", TY_VALUE), tbl:field("array", TY_VALUE_PTR):index((key:field("payload_i64", moon.i64) - q_i64(1)):as(moon.index)))
        ab:set(done:place(), q_bool(true))
      end)
      nb:if_(moon.expr{ done = done, k = key, tbl = tbl, is_hash = is_hash_key_expr(key), limit = q_i64(ObjectModel.HASH_PROBE_LIMIT) }[[not @{done} and @{is_hash} and @{tbl}.hash_capacity > as(i64, 0) and @{tbl}.hash_capacity <= @{limit} and @{tbl}.hash ~= as(ptr(LuaRTTableHashEntry), as(i64, 0))]], function(hb)
        local hash = hb:let(dst .. "_hash", TY_HASH_ENTRY_PTR, tbl:field("hash", TY_HASH_ENTRY_PTR))
        for i = 0, ObjectModel.HASH_PROBE_LIMIT - 1 do
          hb:if_(moon.expr{ done = done, tbl = tbl, i = q_i64(i) }[[not @{done} and @{i} < @{tbl}.hash_capacity]], function(pb)
            local entry = hash:index(q_index(i))
            pb:if_(moon.expr{ e = entry, occupied = hash_state_value("Occupied"), eq = hash_key_equal_expr(entry:field("key", TY_VALUE), key) }[[@{e}.state == @{occupied} and @{eq}]], function(eb)
              eb:set(dst_ref:place():field("hit", moon.bool), q_bool(true))
              set_lua_value(eb, dst_ref:place():field("value", TY_VALUE), entry:field("value", TY_VALUE))
              eb:set(done:place(), q_bool(true))
            end)
          end)
        end
      end)
      nb:if_(moon.expr{ done = done }[[not @{done}]], function(mb)
        mb:set(dst_ref:place():field("hit", moon.bool), q_bool(true))
        set_lua_value(mb, dst_ref:place():field("value", TY_VALUE), nil_value())
      end)
    end)
  end)
  return true
end

local function emit_raw_set_can_write_let(builder, env, dst, expr_node)
  local tables, tablev, key = value_to_expr(expr_node.tables, env), value_to_expr(expr_node.table_value, env), value_to_expr(expr_node.key, env)
  local out = builder:var(dst, moon.bool, q_bool(false)); env[dst] = out
  builder:if_(moon.expr{ tv = tablev, tag = tag_value("TableTag") }[[@{tv}.tag == @{tag} and @{tv}.payload_i64 >= as(i64, 0)]], function(b)
    local tidx = b:let(dst .. "_table_index", moon.index, tablev:field("payload_i64", moon.i64):as(moon.index))
    local tbl = tables:index(tidx)
    b:if_(tbl:field("metatable_kind", moon.i64):eq(metatable_kind_value("NoMetatable")), function(nb)
      nb:if_(moon.expr{ k = key, int_tag = tag_value("IntegerTag"), tbl = tbl }[[@{k}.tag == @{int_tag} and @{k}.payload_i64 >= as(i64, 1) and @{k}.payload_i64 <= @{tbl}.array_len and @{tbl}.array ~= as(ptr(LuaRTValue), as(i64, 0))]], function(ab) ab:set(out:place(), q_bool(true)) end)
      nb:if_(moon.expr{ out = out, k = key, tbl = tbl, is_hash = is_hash_key_expr(key), limit = q_i64(ObjectModel.HASH_PROBE_LIMIT) }[[not @{out} and @{is_hash} and @{tbl}.hash_capacity > as(i64, 0) and @{tbl}.hash_capacity <= @{limit} and @{tbl}.hash ~= as(ptr(LuaRTTableHashEntry), as(i64, 0))]], function(hb)
        local hash = hb:let(dst .. "_hash", TY_HASH_ENTRY_PTR, tbl:field("hash", TY_HASH_ENTRY_PTR))
        for i = 0, ObjectModel.HASH_PROBE_LIMIT - 1 do
          hb:if_(moon.expr{ out = out, tbl = tbl, i = q_i64(i) }[[not @{out} and @{i} < @{tbl}.hash_capacity]], function(pb)
            local entry = hash:index(q_index(i))
            pb:if_(moon.expr{ e = entry, empty = hash_state_value("Empty"), tomb = hash_state_value("Tombstone"), occupied = hash_state_value("Occupied"), eq = hash_key_equal_expr(entry:field("key", TY_VALUE), key) }[[
              @{e}.state == @{empty} or @{e}.state == @{tomb} or (@{e}.state == @{occupied} and @{eq})
            ]], function(eb) eb:set(out:place(), q_bool(true)) end)
          end)
        end
      end)
    end)
  end)
  return true
end

local function table_barrier_needed_expr(tables, tablev, value)
  return moon.expr{ tables = tables, tv = tablev, v = value, table_tag = tag_value("TableTag"), black = gc_color_value("Black"), old = gc_generation_value("Old"), collect = collectable_expr(value) }[[
    block rt_table_barrier_needed() -> bool
      if @{tv}.tag == @{table_tag} then
        if @{tv}.payload_i64 >= as(i64, 0) then
          let idx: index = as(index, @{tv}.payload_i64)
          if @{tables}[idx].gc_color == @{black} then
            if @{tables}[idx].gc_generation == @{old} then
              if @{collect} then yield true end
            end
          end
        end
      end
      yield false
    end
  ]]
end

local function table_array_len_expr(tables, tablev)
  return moon.expr{ tables = tables, tv = tablev, table_tag = tag_value("TableTag") }[[
    block rt_table_array_len() -> i64
      if @{tv}.tag == @{table_tag} then
        if @{tv}.payload_i64 >= as(i64, 0) then yield @{tables}[as(index, @{tv}.payload_i64)].array_len end
      end
      yield as(i64, 0)
    end
  ]]
end

local function string_len_expr(strings, value)
  return moon.expr{ strings = strings, v = value, is_str = is_string_expr(value) }[[
    block rt_string_len() -> i64
      if @{is_str} then
        if @{v}.payload_i64 < as(i64, 0) then yield as(i64, 0) - @{v}.payload_i64 end
        let idx: index = as(index, @{v}.payload_i64)
        yield @{strings}[idx].byte_len
      end
      yield as(i64, 0)
    end
  ]]
end

local function len_no_meta_ok_expr(strings, tables, value)
  return moon.expr{ tables = tables, v = value, table_tag = tag_value("TableTag"), is_str = is_string_expr(value), no_meta = metatable_kind_value("NoMetatable") }[[
    block rt_len_no_meta_ok() -> bool
      if @{is_str} then yield true end
      if @{v}.tag == @{table_tag} then
        if @{v}.payload_i64 >= as(i64, 0) then
          let idx: index = as(index, @{v}.payload_i64)
          if @{tables}[idx].metatable_kind == @{no_meta} then yield true end
        end
      end
      yield false
    end
  ]]
end

local function len_no_meta_expr(strings, tables, value)
  return moon.expr{ strings = strings, tables = tables, v = value, table_tag = tag_value("TableTag"), is_str = is_string_expr(value), no_meta = metatable_kind_value("NoMetatable"), int_tag = tag_value("IntegerTag") }[[
    block rt_len_no_meta() -> i64
      if @{is_str} then yield @{strings}[as(index, @{v}.payload_i64)].byte_len end
      if @{v}.tag == @{table_tag} then
        if @{v}.payload_i64 >= as(i64, 0) then
          let idx: index = as(index, @{v}.payload_i64)
          if @{tables}[idx].metatable_kind == @{no_meta} then yield @{tables}[idx].array_len end
        end
      end
      yield as(i64, 0)
    end
  ]]
end

local function concat2_expr(strings, left, right)
  return moon.expr{ strings = strings, l = left, r = right, is_l = is_string_expr(left), is_r = is_string_expr(right), tag = tag_value("LongStringTag"), nil_tag = tag_value("NilTag") }[[
    block rt_concat2() -> LuaRTValue
      if @{is_l} and @{is_r} then
        let llen: i64 = @{strings}[as(index, @{l}.payload_i64)].byte_len
        let rlen: i64 = @{strings}[as(index, @{r}.payload_i64)].byte_len
        yield LuaRTValue { tag = @{tag}, payload_i64 = as(i64, 0) - (llen + rlen), payload_f64 = 0.0 }
      end
      yield LuaRTValue { tag = @{nil_tag}, payload_i64 = 0, payload_f64 = 0.0 }
    end
  ]]
end

value_to_expr = function(v, env)
  env = env or {}
  local c = cls(v)
  if c == CFG.PlaceValue then
    local pcls = cls(v.place)
    local key = nil
    if pcls == CFG.Temp then key = render_name(v.place.name)
    elseif pcls == CFG.FrameTop then key = "frame_top"
    elseif pcls == CFG.ExecCtx then key = "exec_ctx"
    elseif pcls == CFG.StackSlot then key = "stack_" .. tostring(math.floor(n(v.place.index)))
    elseif pcls == CFG.VarargSlot then key = "vararg_" .. tostring(math.floor(n(v.place.index)))
    end
    if key and env[key] then return env[key] end
    if key then return q_name(key) end
  elseif c == CFG.ParamValue then
    local key = render_name(v.name)
    return env[key] or q_name(key)
  elseif c == CFG.ConstValue then
    local k = cls(v.const)
    if k == CFG.I64Const then return q_i64(v.const.value)
    elseif k == CFG.F64Const then return q_f64(v.const.value)
    elseif k == CFG.BoolConst then return q_bool(v.const.value)
    elseif k == CFG.StringConst then return moon.string_lit(v.const.value or "") end
  elseif c == CFG.UnitValue then
    return moon.nil_lit()
  end
  error("moon_cfg_quote_emit unsupported MoonCFG.Value: " .. tostring(v and v.kind), 2)
end

local function value_to_index_expr(v, env)
  if cls(v) == CFG.ConstValue and cls(v.const) == CFG.I64Const then return q_index(v.const.value) end
  return value_to_expr(v, env):as(moon.index)
end

local function fixed_count_spec_value(count_spec)
  local c = count_spec and count_spec.count
  if type(c) == "number" then return tonumber(c) or 0 end
  return tonumber(c and (c.value or c.count or c.n) or 0) or 0
end

local function slot_index(slot)
  return tonumber(slot and slot.index or 0) or 0
end

local function adjustment_target_count(adjustment)
  local ak = adjustment and adjustment.kind
  if ak == "ExactCount" or ak == "FillNilTo" or ak == "TruncateTo" then
    return tonumber(adjustment.count and adjustment.count.value or 0) or 0
  end
  return nil
end

local function quote_seq(kind_name, count, value0, value1, buffer, base)
  return moon.expr{
    kind = seq_kind_value(kind_name), count = count, value0 = value0 or nil_value(),
    value1 = value1 or nil_value(), buffer = buffer or q_null_value_ptr(), base = base or q_i64(0)
  }[[
    LuaRTValueSeq { kind = @{kind}, count = @{count}, value0 = @{value0}, value1 = @{value1}, buffer = @{buffer}, base = @{base} }
  ]]
end

local function outcome_value(values, index, env)
  local v = (values or {})[index]
  return v and value_to_expr(v, env) or nil_value()
end

local value_to_place

local function quote_runtime_expr(e, env)
  env = env or {}
  local c = cls(e)
  if c == CFG.ValueExpr then return value_to_expr(e.value, env)
  elseif c == CFG.RuntimeBoxNil then return rt_value(tag_value(ValueModel.tag_name_for_nil_kind(e.kind)), q_i64(ValueModel.payload_for_nil_kind(e.kind)), q_f64(0))
  elseif c == CFG.RuntimeBoxBool then
    local b = value_to_expr(e.value, env)
    return moon.expr{ b = b, true_tag = tag_value("TrueTag"), false_tag = tag_value("FalseTag") }[[
      LuaRTValue { tag = select(@{b}, @{true_tag}, @{false_tag}), payload_i64 = select(@{b}, as(i64, 1), as(i64, 0)), payload_f64 = 0.0 }
    ]]
  elseif c == CFG.RuntimeBoxI64 then return rt_value(tag_value("IntegerTag"), value_to_expr(e.value, env), q_f64(0))
  elseif c == CFG.RuntimeBoxF64 then return rt_value(tag_value("FloatTag"), q_i64(0), value_to_expr(e.value, env))
  elseif c == CFG.RuntimeBoxRef then return rt_value(tag_value(e.tag and e.tag.kind or "NilTag"), value_to_expr(e.handle, env), q_f64(0))
  elseif c == CFG.RuntimeTag then return moon.expr{ v = value_to_expr(e.value, env) }[[@{v}.tag]]
  elseif c == CFG.RuntimePayloadI64 then return moon.expr{ v = value_to_expr(e.value, env) }[[@{v}.payload_i64]]
  elseif c == CFG.RuntimePayloadF64 then return moon.expr{ v = value_to_expr(e.value, env) }[[@{v}.payload_f64]]
  elseif c == CFG.RuntimeStackLoad then return value_to_expr(e.stack, env):index(value_to_index_expr(e.index, env))
  elseif c == CFG.Primitive then
    local args = e.args or {}
    local a = args[1] and value_to_expr(args[1], env) or q_i64(0)
    local b = args[2] and value_to_expr(args[2], env) or q_i64(0)
    local k = e.op and e.op.kind
    if k == "AddI64" then return a + b
    elseif k == "SubI64" then return a - b
    elseif k == "MulI64" then return a * b
    elseif k == "IDivI64" then return a / b
    elseif k == "ModI64" then return a % b
    elseif k == "DivF64" then return a / b
    elseif k == "Eq" then return a:eq(b)
    elseif k == "Lt" then return a:lt(b)
    elseif k == "Le" then return a:le(b)
    elseif k == "Not" then return moon.expr{ a = a }[[not @{a}]]
    elseif k == "Truthy" then return a end
    return nil, "unsupported_primitive:" .. tostring(k)
  elseif c == CFG.Convert then
    return value_to_expr(e.value, env):as(type_from_ref(e.type))
  elseif c == CFG.Load then
    return value_to_expr(CFG.PlaceValue(e.place), env)
  elseif c == CFG.AddressOf then
    local p, perr = value_to_place(e.place, env)
    if not p then return nil, perr end
    return moon.addr_of(p)
  elseif c == CFG.RuntimeTruthiness then
    local v = value_to_expr(e.value, env)
    return moon.expr{ v = v, nil_tag = tag_value("NilTag"), empty_tag = tag_value("EmptySlotTag"), absent_tag = tag_value("AbsentKeyTag"), no_table_tag = tag_value("NoTableTag"), false_tag = tag_value("FalseTag") }[[
      not (@{v}.tag == @{nil_tag} or @{v}.tag == @{empty_tag} or @{v}.tag == @{absent_tag} or @{v}.tag == @{no_table_tag} or @{v}.tag == @{false_tag})
    ]]
  elseif c == CFG.RuntimeTypeTest then
    local tags = ValueModel.tags_for_type_test(e.test)
    if not tags then return nil, "unsupported_type_test:" .. tostring(e.test and e.test.kind) end
    local v = value_to_expr(e.value, env)
    local cond = q_bool(false)
    for _, tag in ipairs(tags) do
      cond = moon.expr{ prev = cond, v = v, tag = tag_value(tag) }[[@{prev} or @{v}.tag == @{tag}]]
    end
    return cond
  elseif c == CFG.RuntimeOutcomeReturn then
    return moon.expr{ kind = outcome_kind_value("NormalReturnOutcome"), count = value_to_expr(e.count, env), v0 = outcome_value(e.values, 1, env), v1 = outcome_value(e.values, 2, env), nilv = nil_value(), nullp = q_null_value_ptr() }[[
      LuaRTOutcome { kind = @{kind}, count = @{count}, value0 = @{v0}, value1 = @{v1}, error_kind = 0, error_value = @{nilv}, saved_pc = 0, saved_top = 0, yield_kind = 0, value_buffer = @{nullp}, value_base = 0 }
    ]]
  elseif c == CFG.RuntimeOutcomeReturnSeq then
    local seq = value_to_expr(e.seq, env)
    return moon.expr{ kind = outcome_kind_value("NormalReturnOutcome"), seq = seq, v0 = moon.expr{seq=seq}[[@{seq}.value0]], v1 = moon.expr{seq=seq}[[@{seq}.value1]], nilv = nil_value() }[[
      LuaRTOutcome { kind = @{kind}, count = @{seq}.count, value0 = @{v0}, value1 = @{v1}, error_kind = 0, error_value = @{nilv}, saved_pc = 0, saved_top = 0, yield_kind = 0, value_buffer = @{seq}.buffer, value_base = @{seq}.base }
    ]]
  elseif c == CFG.RuntimeOutcomeError then
    return moon.expr{ kind = outcome_kind_value("LuaErrorOutcome"), ek = error_kind_value(e.kind), errv = value_to_expr(e.error_value, env), pc = value_to_expr(e.saved_pc, env), top = value_to_expr(e.saved_top, env), nilv = nil_value(), nullp = q_null_value_ptr() }[[
      LuaRTOutcome { kind = @{kind}, count = 0, value0 = @{nilv}, value1 = @{nilv}, error_kind = @{ek}, error_value = @{errv}, saved_pc = @{pc}, saved_top = @{top}, yield_kind = 0, value_buffer = @{nullp}, value_base = 0 }
    ]]
  elseif c == CFG.RuntimeOutcomeYield or c == CFG.RuntimeOutcomeYieldSeq then
    local count = c == CFG.RuntimeOutcomeYield and value_to_expr(e.count, env) or moon.expr{seq=value_to_expr(e.seq, env)}[[@{seq}.count]]
    local v0 = c == CFG.RuntimeOutcomeYield and outcome_value(e.values, 1, env) or seq_value_at(value_to_expr(e.seq, env), 0)
    local v1 = c == CFG.RuntimeOutcomeYield and outcome_value(e.values, 2, env) or seq_value_at(value_to_expr(e.seq, env), 1)
    local buffer = c == CFG.RuntimeOutcomeYield and q_null_value_ptr() or moon.expr{seq=value_to_expr(e.seq, env)}[[@{seq}.buffer]]
    local base = c == CFG.RuntimeOutcomeYield and q_i64(0) or moon.expr{seq=value_to_expr(e.seq, env)}[[@{seq}.base]]
    return moon.expr{ kind = outcome_kind_value("LuaYieldOutcome"), yk = yield_kind_value(e.resume_point), count = count, v0 = v0, v1 = v1, pc = value_to_expr(e.saved_pc, env), top = value_to_expr(e.saved_top, env), nilv = nil_value(), buffer = buffer, base = base }[[
      LuaRTOutcome { kind = @{kind}, count = @{count}, value0 = @{v0}, value1 = @{v1}, error_kind = 0, error_value = @{nilv}, saved_pc = @{pc}, saved_top = @{top}, yield_kind = @{yk}, value_buffer = @{buffer}, value_base = @{base} }
    ]]
  elseif c == CFG.RuntimeTopLoad then return moon.expr{ p = value_to_expr(e.top_ptr, env) }[=[@{p}[as(index, 0)]]=]
  elseif c == CFG.RuntimeOpenCountFromTop then return value_to_expr(e.top, env) - value_to_expr(e.base, env)
  elseif c == CFG.RuntimeValueSeqFixed then return quote_seq("FixedSeq", value_to_expr(e.count, env), outcome_value(e.values, 1, env), outcome_value(e.values, 2, env), q_null_value_ptr(), q_i64(0))
  elseif c == CFG.RuntimeValueSeqFromStack then
    local stack, base, count = value_to_expr(e.stack, env), value_to_expr(e.base, env), value_to_expr(e.count, env)
    local b0 = cls(e.base) == CFG.ConstValue and cls(e.base.const) == CFG.I64Const and q_index(e.base.const.value) or base:as(moon.index)
    local b1 = cls(e.base) == CFG.ConstValue and cls(e.base.const) == CFG.I64Const and q_index(e.base.const.value + 1) or (base + q_i64(1)):as(moon.index)
    return quote_seq("OpenSeq", count, stack:index(b0), stack:index(b1), stack, base)
  elseif c == CFG.RuntimeValueSeqFromVarargs then
    local src, count = value_to_expr(e.varargs, env), value_to_expr(e.count, env)
    local values = moon.expr{ src = src }[[@{src}.values]]
    return quote_seq("VarargSeq", count, values:index(q_index(0)), values:index(q_index(1)), values, q_i64(0))
  elseif c == CFG.RuntimeValueSeqAdjust or c == CFG.RuntimeValueSeqNormalize then
    local seq = value_to_expr(e.seq, env)
    local adjustment = c == CFG.RuntimeValueSeqNormalize and e.shape and e.shape.adjustment or e.adjustment
    local target = adjustment_target_count(adjustment)
    local count = target ~= nil and q_i64(target) or moon.expr{ seq = seq }[[@{seq}.count]]
    return quote_seq("AdjustedSeq", count, moon.expr{seq=seq}[[@{seq}.value0]], moon.expr{seq=seq}[[@{seq}.value1]], moon.expr{seq=seq}[[@{seq}.buffer]], moon.expr{seq=seq}[[@{seq}.base]])
  elseif c == CFG.RuntimeValueSeqCount then return moon.expr{ seq = value_to_expr(e.seq, env) }[[@{seq}.count]]
  elseif c == CFG.RuntimeValueSeqValue then return seq_value_at(value_to_expr(e.seq, env), e.index)
  elseif c == CFG.RuntimeValueSeqBuffer then return moon.expr{ seq = value_to_expr(e.seq, env) }[[@{seq}.buffer]]
  elseif c == CFG.RuntimeValueSeqBase then return moon.expr{ seq = value_to_expr(e.seq, env) }[[@{seq}.base]]
  elseif c == CFG.RuntimeVarargSource then
    return moon.expr{ kind = vararg_kind_value("HiddenFrameVarargs"), values = value_to_expr(e.values, env), count = value_to_expr(e.count, env), table_handle = value_to_expr(e.table_handle, env) }[[
      LuaRTVarargSource { kind = @{kind}, values = @{values}, count = @{count}, table_handle = @{table_handle} }
    ]]
  elseif c == CFG.RuntimeVarargCount then return moon.expr{ src = value_to_expr(e.source, env) }[[@{src}.count]]
  elseif c == CFG.RuntimeClassifyCallee then
    local callee = value_to_expr(e.callee, env)
    local callee_tag = callee:field("tag", moon.i64)
    return callee_tag:eq(tag_value("LuaClosureTag")):select(q_i64(1),
      callee_tag:eq(tag_value("CClosureTag")):select(q_i64(2),
        callee_tag:eq(tag_value("LightCFunctionTag")):select(q_i64(3), q_i64(0))))
  elseif c == CFG.RuntimeCallTargetCheck then
    local callee = value_to_expr(e.callee, env)
    local identity = e.target and e.target.identity
    if cls(identity) == RT.LuaClosureTargetIdentity then
      return moon.expr{ tag = callee:field("tag", moon.i64), payload = callee:field("payload_i64", moon.i64), lua_tag = tag_value("LuaClosureTag"), handle = q_i64(identity.closure_handle) }[[
        @{tag} == @{lua_tag} and @{payload} == @{handle}
      ]]
    end
    return q_bool(false)
  elseif c == CFG.RuntimeVarargGet then
    local src, key = value_to_expr(e.source, env), value_to_expr(e.key, env)
    return moon.expr{ src = src, key = key, nilv = nil_value(), int_tag = tag_value("IntegerTag") }[[
      block rt_vararg_get() -> LuaRTValue
        if @{key}.tag == @{int_tag} then
          if @{key}.payload_i64 >= as(i64, 1) then
            if @{key}.payload_i64 <= @{src}.count then
              yield @{src}.values[as(index, @{key}.payload_i64 - as(i64, 1))]
            end
          end
        end
        yield @{nilv}
      end
    ]]
  elseif c == CFG.RuntimeOutcomeKind then return moon.expr{ out = value_to_expr(e.outcome, env) }[[@{out}.kind]]
  elseif c == CFG.RuntimeOutcomeCount then return moon.expr{ out = value_to_expr(e.outcome, env) }[[@{out}.count]]
  elseif c == CFG.RuntimeOutcomeValueTag then
    return moon.expr{ v = (tonumber(e.index or 0) == 0 and moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value0]] or tonumber(e.index or 0) == 1 and moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value1]] or buffer_value_at(moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value_buffer]], moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value_base]], moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.count]], tonumber(e.index or 0))) }[[@{v}.tag]]
  elseif c == CFG.RuntimeOutcomeValuePayloadI64 then
    return moon.expr{ v = (tonumber(e.index or 0) == 0 and moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value0]] or tonumber(e.index or 0) == 1 and moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value1]] or buffer_value_at(moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value_buffer]], moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value_base]], moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.count]], tonumber(e.index or 0))) }[[@{v}.payload_i64]]
  elseif c == CFG.RuntimeOutcomeValuePayloadF64 then
    return moon.expr{ v = (tonumber(e.index or 0) == 0 and moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value0]] or tonumber(e.index or 0) == 1 and moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value1]] or buffer_value_at(moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value_buffer]], moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.value_base]], moon.expr{out=value_to_expr(e.outcome, env)}[[@{out}.count]], tonumber(e.index or 0))) }[[@{v}.payload_f64]]
  elseif c == CFG.RuntimeOutcomeErrorKind then return moon.expr{ out = value_to_expr(e.outcome, env) }[[@{out}.error_kind]]
  elseif c == CFG.RuntimeOutcomeErrorValueTag then return moon.expr{ out = value_to_expr(e.outcome, env) }[[@{out}.error_value.tag]]
  elseif c == CFG.RuntimeOutcomeErrorValuePayloadI64 then return moon.expr{ out = value_to_expr(e.outcome, env) }[[@{out}.error_value.payload_i64]]
  elseif c == CFG.RuntimeOutcomeSavedPc then return moon.expr{ out = value_to_expr(e.outcome, env) }[[@{out}.saved_pc]]
  elseif c == CFG.RuntimeOutcomeYieldKind then return moon.expr{ out = value_to_expr(e.outcome, env) }[[@{out}.yield_kind]]
  elseif c == CFG.RuntimeCallFramePrepare then
    return moon.expr{ caller = value_to_expr(e.caller_stack, env), callee = value_to_expr(e.callee_stack, env), arg_base = q_i64(slot_index(e.layout and e.layout.arg_base)), arg_count = q_i64(fixed_count_spec_value(e.layout and e.layout.arg_count)), result_base = q_i64(slot_index(e.layout and e.layout.result_base)), result_count = q_i64(fixed_count_spec_value(e.layout and e.layout.result_count)) }[[
      LuaRTCallFrame { caller_stack = @{caller}, callee_stack = @{callee}, arg_base = @{arg_base}, arg_count = @{arg_count}, result_base = @{result_base}, result_count = @{result_count}, target_ok = true }
    ]]
  elseif c == CFG.RuntimeCallFrameResultSeq then
    local stack = value_to_expr(e.callee_stack, env)
    local base = q_i64(slot_index(e.layout and e.layout.result_base))
    local count = q_i64(fixed_count_spec_value(e.layout and e.layout.result_count))
    return quote_seq("CallResultSeq", count, stack:index(q_index(slot_index(e.layout and e.layout.result_base))), stack:index(q_index(slot_index(e.layout and e.layout.result_base) + 1)), stack, base)
  elseif c == CFG.RuntimeArithmeticNumericOk then
    return arithmetic_numeric_ok(e.op, value_to_expr(e.strings, env), value_to_expr(e.left, env), value_to_expr(e.right, env))
  elseif c == CFG.RuntimeArithmeticNoMeta then
    return arithmetic_no_meta(e.op, value_to_expr(e.strings, env), value_to_expr(e.left, env), value_to_expr(e.right, env))
  elseif c == CFG.RuntimeArithmeticErrorValue then
    return arithmetic_error_value(e.op, value_to_expr(e.strings, env), value_to_expr(e.left, env), value_to_expr(e.right, env))
  elseif c == CFG.RuntimeTableRawGet then
    return raw_get_initial()
  elseif c == CFG.RuntimeRawGetHit then
    return value_to_expr(e.rawget, env):field("hit", moon.bool)
  elseif c == CFG.RuntimeRawGetValue then
    return value_to_expr(e.rawget, env):field("value", TY_VALUE)
  elseif c == CFG.RuntimeRawGetValueOrNil then
    local rg = value_to_expr(e.rawget, env)
    return rg:field("hit", moon.bool):select(rg:field("value", TY_VALUE), nil_value())
  elseif c == CFG.RuntimeTableRawSetCanWrite then
    return q_bool(false)
  elseif c == CFG.RuntimeTableWriteBarrierNeeded then
    return table_barrier_needed_expr(value_to_expr(e.tables, env), value_to_expr(e.table_value, env), value_to_expr(e.value, env))
  elseif c == CFG.RuntimeTableArrayLen then
    return table_array_len_expr(value_to_expr(e.tables, env), value_to_expr(e.table_value, env))
  elseif c == CFG.RuntimeStringLen then
    return string_len_expr(value_to_expr(e.strings, env), value_to_expr(e.value, env))
  elseif c == CFG.RuntimeLenNoMeta then
    return len_no_meta_expr(value_to_expr(e.strings, env), value_to_expr(e.tables, env), value_to_expr(e.value, env))
  elseif c == CFG.RuntimeLenNoMetaOk then
    return len_no_meta_ok_expr(value_to_expr(e.strings, env), value_to_expr(e.tables, env), value_to_expr(e.value, env))
  elseif c == CFG.RuntimeStringConcat2 then
    return concat2_expr(value_to_expr(e.strings, env), value_to_expr(e.left, env), value_to_expr(e.right, env))
  elseif c == CFG.RuntimeStringToNumberOk or c == CFG.RuntimeStringToNumber or c == CFG.RuntimeCDataAccessOk or c == CFG.RuntimeCDataLoadScalar then
    return nil, "unsupported_runtime_expr:" .. tostring(e and e.kind)
  end
  return nil, "unsupported_runtime_expr:" .. tostring(e and e.kind)
end

function M.quote_runtime_expr(expr, env)
  return quote_runtime_expr(expr, env or {})
end

local declare_runtime_abi

local function infer_expr_type(e)
  local c = cls(e)
  if c == CFG.Primitive then
    local k = e.op and e.op.kind
    if k == "DivF64" then return moon.f64 end
    if k == "Eq" or k == "Lt" or k == "Le" or k == "Not" or k == "Truthy" then return moon.bool end
    return moon.i64
  elseif c == CFG.RuntimeBoxNil or c == CFG.RuntimeBoxBool or c == CFG.RuntimeBoxI64 or c == CFG.RuntimeBoxF64 or c == CFG.RuntimeBoxRef or c == CFG.RuntimeStackLoad or c == CFG.RuntimeVarargGet or c == CFG.RuntimeValueSeqValue or c == CFG.RuntimeArithmeticNoMeta or c == CFG.RuntimeArithmeticErrorValue or c == CFG.RuntimeRawGetValue or c == CFG.RuntimeRawGetValueOrNil or c == CFG.RuntimeStringConcat2 then return TY_VALUE
  elseif c == CFG.RuntimeOutcomeReturn or c == CFG.RuntimeOutcomeReturnSeq or c == CFG.RuntimeOutcomeError or c == CFG.RuntimeOutcomeYield or c == CFG.RuntimeOutcomeYieldSeq then return TY_OUTCOME
  elseif c == CFG.RuntimeValueSeqFixed or c == CFG.RuntimeValueSeqFromStack or c == CFG.RuntimeValueSeqFromVarargs or c == CFG.RuntimeValueSeqAdjust or c == CFG.RuntimeValueSeqNormalize or c == CFG.RuntimeCallFrameResultSeq then return TY_SEQ
  elseif c == CFG.RuntimeCallFramePrepare then return TY_CALL_FRAME
  elseif c == CFG.RuntimeTableRawGet then return TY_RAW_GET
  elseif c == CFG.RuntimeVarargSource then return TY_VARARG
  elseif c == CFG.RuntimeValueSeqBuffer then return TY_VALUE_PTR
  elseif c == CFG.RuntimeTag or c == CFG.RuntimePayloadI64 or c == CFG.RuntimeTopLoad or c == CFG.RuntimeOpenCountFromTop or c == CFG.RuntimeValueSeqCount or c == CFG.RuntimeValueSeqBase or c == CFG.RuntimeVarargCount or c == CFG.RuntimeClassifyCallee or c == CFG.RuntimeOutcomeKind or c == CFG.RuntimeOutcomeCount or c == CFG.RuntimeOutcomeValueTag or c == CFG.RuntimeOutcomeValuePayloadI64 or c == CFG.RuntimeOutcomeErrorKind or c == CFG.RuntimeOutcomeErrorValueTag or c == CFG.RuntimeOutcomeErrorValuePayloadI64 or c == CFG.RuntimeOutcomeSavedPc or c == CFG.RuntimeOutcomeYieldKind or c == CFG.RuntimeTableArrayLen or c == CFG.RuntimeStringLen or c == CFG.RuntimeLenNoMeta then return moon.i64
  elseif c == CFG.RuntimePayloadF64 or c == CFG.RuntimeOutcomeValuePayloadF64 then return moon.f64
  elseif c == CFG.RuntimeTruthiness or c == CFG.RuntimeTypeTest or c == CFG.RuntimeCallTargetCheck or c == CFG.RuntimeArithmeticNumericOk or c == CFG.RuntimeRawGetHit or c == CFG.RuntimeTableRawSetCanWrite or c == CFG.RuntimeTableWriteBarrierNeeded or c == CFG.RuntimeLenNoMetaOk then return moon.bool
  elseif c == CFG.ValueExpr then
    local v = e.value
    if cls(v) == CFG.ConstValue then
      local ck = cls(v.const)
      if ck == CFG.F64Const then return moon.f64 elseif ck == CFG.BoolConst then return moon.bool else return moon.i64 end
    end
  elseif c == CFG.Convert then return type_from_ref(e.type) end
  return moon.i64
end

local function place_key(place)
  local pc = cls(place)
  if pc == CFG.Temp then return render_name(place.name)
  elseif pc == CFG.FrameTop then return "frame_top"
  elseif pc == CFG.ExecCtx then return "exec_ctx"
  elseif pc == CFG.StackSlot then return "stack_" .. tostring(math.floor(n(place.index)))
  elseif pc == CFG.VarargSlot then return "vararg_" .. tostring(math.floor(n(place.index)))
  end
  return nil
end

value_to_place = function(v, env)
  local vc = cls(v)
  local place = vc == CFG.PlaceValue and v.place or v
  local key = place_key(place)
  if key and env[key] and env[key].place then return env[key]:place() end
  if key then return q_name(key):place() end
  return nil, "unsupported_place:" .. tostring(place and place.kind)
end

set_lua_value = function(builder, dst_place, src_expr)
  builder:set(dst_place:field("tag", moon.i64), moon.expr{ v = src_expr }[[@{v}.tag]])
  builder:set(dst_place:field("payload_i64", moon.i64), moon.expr{ v = src_expr }[[@{v}.payload_i64]])
  builder:set(dst_place:field("payload_f64", moon.f64), moon.expr{ v = src_expr }[[@{v}.payload_f64]])
end

local function emit_seq_value_let(builder, env, dst, expr_node)
  local seq = value_to_expr(expr_node.seq, env)
  local idxn = tonumber(expr_node.index or 0) or 0
  local dst_ref = builder:var(dst, TY_VALUE, nil_value())
  env[dst] = dst_ref
  local dst_place = dst_ref:place()
  local idx = q_i64(idxn)
  builder:if_(moon.expr{ idx = idx, seq = seq }[[@{idx} < @{seq}.count]], function(b)
    if idxn == 0 then
      set_lua_value(b, dst_place, moon.expr{ seq = seq }[[@{seq}.value0]])
    elseif idxn == 1 then
      set_lua_value(b, dst_place, moon.expr{ seq = seq }[[@{seq}.value1]])
    else
      local buffer = moon.expr{ seq = seq }[[@{seq}.buffer]]
      local base = moon.expr{ seq = seq }[[@{seq}.base]]
      b:if_(moon.expr{ buffer = buffer }[[@{buffer} ~= as(ptr(LuaRTValue), as(i64, 0))]], function(bb)
        set_lua_value(bb, dst_place, buffer:index((base + idx):as(moon.index)))
      end)
    end
  end)
  return true
end

local function vararg_source_initial()
  return moon.expr{ kind = vararg_kind_value("HiddenFrameVarargs"), nullp = q_null_value_ptr() }[[
    LuaRTVarargSource { kind = @{kind}, values = @{nullp}, count = 0, table_handle = 0 }
  ]]
end

local function emit_vararg_source_let(_builder, env, dst, expr_node)
  -- LuaRTVarargSource is immutable in current quote paths; keep it as a typed
  -- expression to avoid Moonlift aggregate local initializer lowering limits.
  env[dst] = quote_runtime_expr(expr_node, env)
  return true
end

local function emit_vararg_get_let(builder, env, dst, expr_node)
  local src, key = value_to_expr(expr_node.source, env), value_to_expr(expr_node.key, env)
  local dst_ref = builder:var(dst, TY_VALUE, nil_value())
  env[dst] = dst_ref
  builder:if_(moon.expr{ key = key, int_tag = tag_value("IntegerTag") }[[@{key}.tag == @{int_tag}]], function(ib)
    ib:if_(moon.expr{ key = key }[[@{key}.payload_i64 >= as(i64, 1)]], function(lb)
      lb:if_(moon.expr{ key = key, src = src }[[@{key}.payload_i64 <= @{src}.count]], function(cb)
        set_lua_value(cb, dst_ref:place(), src:field("values", TY_VALUE_PTR):index((key:field("payload_i64", moon.i64) - q_i64(1)):as(moon.index)))
      end)
    end)
  end)
  return true
end

local function emit_let(builder, env, op)
  local dst = assert(place_key(op.dst), "Let destination must be a named MoonCFG place")
  if cls(op.expr) == CFG.RuntimeValueSeqValue then return emit_seq_value_let(builder, env, dst, op.expr) end
  if cls(op.expr) == CFG.RuntimeVarargSource then return emit_vararg_source_let(builder, env, dst, op.expr) end
  if cls(op.expr) == CFG.RuntimeVarargGet then return emit_vararg_get_let(builder, env, dst, op.expr) end
  if cls(op.expr) == CFG.RuntimeTableRawGet then return emit_raw_get_let(builder, env, dst, op.expr) end
  if cls(op.expr) == CFG.RuntimeTableRawSetCanWrite then return emit_raw_set_can_write_let(builder, env, dst, op.expr) end
  local expr, err = quote_runtime_expr(op.expr, env)
  if not expr then return nil, err end
  local ty = infer_expr_type(op.expr)
  if ty == TY_VALUE or ty == TY_OUTCOME or ty == TY_SEQ or ty == TY_VARARG or ty == TY_CALL_FRAME then
    env[dst] = builder:var(dst, ty, expr)
  else
    env[dst] = builder:let(dst, ty, expr)
  end
  return true
end

local function seq_expr_at(seq, index)
  index = tonumber(index) or 0
  if index == 0 then return moon.expr{ seq = seq }[[@{seq}.value0]] end
  if index == 1 then return moon.expr{ seq = seq }[[@{seq}.value1]] end
  local idx = q_i64(index)
  local buffer = moon.expr{ seq = seq }[[@{seq}.buffer]]
  local base = moon.expr{ seq = seq }[[@{seq}.base]]
  return buffer:index((base + idx):as(moon.index))
end

local MAX_SEQ_STORE_UNROLL = 8
local function emit_seq_store(builder, stack, base, seq, start_index, max_count, base_const)
  start_index = start_index or 0
  max_count = max_count or MAX_SEQ_STORE_UNROLL
  for i = start_index, max_count - 1 do
    local idx = q_i64(i)
    builder:if_(moon.expr{ seq = seq, idx = idx }[[@{seq}.count >= (@{idx} + as(i64, 1))]], function(b)
      local index = base_const ~= nil and q_index(base_const + i) or (base + idx):as(moon.index)
      local dst = index_place_of(stack, index, TY_VALUE)
      set_lua_value(b, dst, seq_expr_at(seq, i))
    end)
  end
end

local function emit_op(builder, env, op)
  local c = cls(op)
  if c == CFG.Let then return emit_let(builder, env, op)
  elseif c == CFG.Assign or c == CFG.Store then
    local dst, derr = value_to_place(op.dst, env)
    if not dst then return nil, derr end
    builder:set(dst, value_to_expr(op.src, env))
    return true
  elseif c == CFG.RuntimeStackStore then
    local stack, value = value_to_expr(op.stack, env), value_to_expr(op.value, env)
    set_lua_value(builder, stack:index_place(value_to_index_expr(op.index, env)), value)
    return true
  elseif c == CFG.RuntimeValueSeqStore then
    local base_const = cls(op.base) == CFG.ConstValue and cls(op.base.const) == CFG.I64Const and tonumber(op.base.const.value) or nil
    emit_seq_store(builder, value_to_expr(op.stack, env), value_to_expr(op.base, env), value_to_expr(op.seq, env), 0, MAX_SEQ_STORE_UNROLL, base_const)
    return true
  elseif c == CFG.RuntimeCallFrameStoreArgs then
    local base_slot = slot_index(op.layout and op.layout.arg_base)
    emit_seq_store(builder, value_to_expr(op.callee_stack, env), q_i64(base_slot), value_to_expr(op.args, env), 0, MAX_SEQ_STORE_UNROLL, base_slot)
    return true
  elseif c == CFG.RuntimeTopStore then
    builder:set(value_to_expr(op.top_ptr, env):index_place(q_index(0)), value_to_expr(op.top, env))
    return true
  elseif c == CFG.RuntimeTableRawSet then
    local tables, tablev, key, value = value_to_expr(op.tables, env), value_to_expr(op.table_value, env), value_to_expr(op.key, env), value_to_expr(op.value, env)
    builder:if_(moon.expr{ tv = tablev, tag = tag_value("TableTag") }[[@{tv}.tag == @{tag} and @{tv}.payload_i64 >= as(i64, 0)]], function(b)
      local tidx = b:let("raw_set_table_index", moon.index, tablev:field("payload_i64", moon.i64):as(moon.index))
      local tbl = tables:index(tidx)
      local tbl_place = index_place_of(tables, tidx, TY_TABLE)
      local array_slot = b:var("raw_set_array_slot", moon.bool, q_bool(false))
      b:if_(moon.expr{ k = key, int_tag = tag_value("IntegerTag"), tbl = tbl }[[@{k}.tag == @{int_tag} and @{k}.payload_i64 >= as(i64, 1) and @{k}.payload_i64 <= @{tbl}.array_len]], function(ab)
        ab:set(array_slot:place(), q_bool(true))
        ab:if_(moon.expr{ tbl = tbl }[[@{tbl}.array ~= as(ptr(LuaRTValue), as(i64, 0))]], function(sb)
          set_lua_value(sb, index_place_of(tbl:field("array", TY_VALUE_PTR), (key:field("payload_i64", moon.i64) - q_i64(1)):as(moon.index), TY_VALUE), value)
        end)
      end)
      b:if_(moon.expr{ array_slot = array_slot, is_hash = is_hash_key_expr(key), tbl = tbl, limit = q_i64(ObjectModel.HASH_PROBE_LIMIT) }[[not @{array_slot} and @{is_hash} and @{tbl}.hash_capacity > as(i64, 0) and @{tbl}.hash_capacity <= @{limit} and @{tbl}.hash ~= as(ptr(LuaRTTableHashEntry), as(i64, 0))]], function(hb)
        local hash = hb:let("raw_set_hash", TY_HASH_ENTRY_PTR, tbl:field("hash", TY_HASH_ENTRY_PTR))
        local done = hb:var("raw_set_hash_done", moon.bool, q_bool(false))
        for i = 0, ObjectModel.HASH_PROBE_LIMIT - 1 do
          hb:if_(moon.expr{ done = done, tbl = tbl, i = q_i64(i) }[[not @{done} and @{i} < @{tbl}.hash_capacity]], function(ub)
            local entry = hash:index(q_index(i))
            local entry_place = index_place_of(hash, q_index(i), TY_HASH_ENTRY)
            ub:if_(moon.expr{ e = entry, occupied = hash_state_value("Occupied"), eq = hash_key_equal_expr(entry:field("key", TY_VALUE), key) }[[@{e}.state == @{occupied} and @{eq}]], function(eb)
              set_lua_value(eb, entry_place:field("value", TY_VALUE), value)
              eb:set(done:place(), q_bool(true))
            end)
          end)
        end
        for i = 0, ObjectModel.HASH_PROBE_LIMIT - 1 do
          hb:if_(moon.expr{ done = done, tbl = tbl, i = q_i64(i) }[[not @{done} and @{i} < @{tbl}.hash_capacity]], function(ib)
            local entry = hash:index(q_index(i))
            local entry_place = index_place_of(hash, q_index(i), TY_HASH_ENTRY)
            ib:if_(moon.expr{ e = entry, empty = hash_state_value("Empty"), tomb = hash_state_value("Tombstone") }[[@{e}.state == @{empty} or @{e}.state == @{tomb}]], function(eb)
              eb:set(entry_place:field("state", moon.i64), hash_state_value("Occupied"))
              set_lua_value(eb, entry_place:field("key", TY_VALUE), key)
              set_lua_value(eb, entry_place:field("value", TY_VALUE), value)
              eb:set(tbl_place:field("hash_count", moon.i64), tbl:field("hash_count", moon.i64) + q_i64(1))
              eb:set(done:place(), q_bool(true))
            end)
          end)
        end
      end)
    end)
    return true
  elseif c == CFG.RuntimeTableWriteBarrier then
    local tables, tablev, value = value_to_expr(op.tables, env), value_to_expr(op.table_value, env), value_to_expr(op.value, env)
    builder:if_(table_barrier_needed_expr(tables, tablev, value), function(b)
      b:if_(moon.expr{ tv = tablev, tag = tag_value("TableTag") }[[@{tv}.tag == @{tag} and @{tv}.payload_i64 >= as(i64, 0)]], function(tb)
        local idx = tb:let("barrier_table_index", moon.index, tablev:field("payload_i64", moon.i64):as(moon.index))
        local tbl = tables:index(idx)
        local tbl_place = index_place_of(tables, idx, TY_TABLE)
        tb:set(tbl_place:field("barrier_count", moon.i64), tbl:field("barrier_count", moon.i64) + q_i64(1))
        tb:set(tbl_place:field("barrier_epoch", moon.i64), tbl:field("gc_epoch", moon.i64))
        tb:set(tbl_place:field("barrier_last_child_tag", moon.i64), value:field("tag", moon.i64))
        tb:set(tbl_place:field("barrier_last_child_payload", moon.i64), value:field("payload_i64", moon.i64))
      end)
    end)
    return true
  elseif c == CFG.Assert then
    -- Current migrated tests use validated kernels where assertions are guards
    -- already discharged by input construction. Dynamic guard exits remain for a
    -- later quote-control migration.
    return nil, "unsupported_op:Assert"
  end
  return nil, "unsupported_op:" .. tostring(op and op.kind)
end


local function param_type(p) return type_from_ref(p and p.type) end
local function return_type(kernel)
  local returns = kernel.returns or {}
  if #returns == 0 then return moon.void end
  if #returns > 1 then return nil, "multi_return_not_migrated" end
  return type_from_ref(returns[1]), nil
end

local function default_value_for_type(ty)
  local ts = tostring(ty and (ty.source_hint or ty) or "")
  if ty == moon.void then return nil end
  if ty == moon.bool then return q_bool(false) end
  if ty == moon.f64 or ts == "f64" then return q_f64(0) end
  if ts == ValueModel.TYPE_NAME or ts:match(ValueModel.TYPE_NAME) then return nil_value() end
  if ts == OutcomeModel.TYPE_NAME or ts:match(OutcomeModel.TYPE_NAME) then
    return moon.expr{ kind = outcome_kind_value("NormalReturnOutcome"), nilv = nil_value(), nullp = q_null_value_ptr() }[[
      LuaRTOutcome { kind = @{kind}, count = 0, value0 = @{nilv}, value1 = @{nilv}, error_kind = 0, error_value = @{nilv}, saved_pc = 0, saved_top = 0, yield_kind = 0, value_buffer = @{nullp}, value_base = 0 }
    ]]
  end
  return q_i64(0)
end

local function copy_env(env)
  local out = {}
  for k, v in pairs(env or {}) do out[k] = v end
  return out
end

local function tree_api()
  local S = moon.default_session.T
  return S.MoonCore, S.MoonBind, S.MoonTree
end

local function as_expr(v, site) return moon.as_moonlift_expr(v, site or "quote expr") end
local function as_place(v, site) return moon.as_moonlift_place(v, site or "quote place") end
local function as_type_asdl(ty, site) return moon.as_type_value(ty, site or "quote type").ty end

index_place_of = function(base_expr, index_expr, elem_ty)
  local S = moon.default_session.T
  local Tr, Ty, Core = S.MoonTree, S.MoonType, S.MoonCore
  local place = Tr.PlaceIndex(Tr.PlaceSurface, Tr.IndexBaseExpr(as_expr(base_expr, "index base"), Ty.TScalar(Core.ScalarVoid)), as_expr(index_expr, "index expr"))
  return moon.place_from_asdl(place, elem_ty, "quote_index_place")
end

local function make_local_binding(name, ty, mutable, ordinal)
  local C, Bind = tree_api()
  local class = mutable and Bind.BindingClassLocalCell or Bind.BindingClassLocalValue
  return Bind.Binding(C.Id("quote:local:" .. tostring(name) .. ":" .. tostring(ordinal or 0)), name, as_type_asdl(ty, name), class)
end

local function expr_ref_for_binding(binding, ty, name)
  return moon.expr_ref(binding, ty, name)
end

local function make_stmt_builder(env)
  local builder = { body = {}, env = env or {} }
  function builder:emit(stmt) self.body[#self.body + 1] = stmt; return stmt end
  function builder:let(name, ty, init)
    local _C, _Bind, Tr = tree_api()
    local binding = make_local_binding(name, ty, false, #self.body + 1)
    self:emit(Tr.StmtLet(Tr.StmtSurface, binding, as_expr(init, "let init")))
    local ref = expr_ref_for_binding(binding, ty, name)
    self.env[name] = ref
    return ref
  end
  function builder:var(name, ty, init)
    local _C, _Bind, Tr = tree_api()
    local binding = make_local_binding(name, ty, true, #self.body + 1)
    self:emit(Tr.StmtVar(Tr.StmtSurface, binding, as_expr(init, "var init")))
    local ref = expr_ref_for_binding(binding, ty, name)
    self.env[name] = ref
    return ref
  end
  function builder:set(place, value)
    local _C, _Bind, Tr = tree_api()
    return self:emit(Tr.StmtSet(Tr.StmtSurface, as_place(place, "set place"), as_expr(value, "set value")))
  end
  function builder:if_(cond, then_fn, else_fn)
    local _C, _Bind, Tr = tree_api()
    local tb = make_stmt_builder(copy_env(self.env)); then_fn(tb)
    local eb_body = {}
    if else_fn then local eb = make_stmt_builder(copy_env(self.env)); else_fn(eb); eb_body = eb.body end
    return self:emit(Tr.StmtIf(Tr.StmtSurface, as_expr(cond, "if cond"), tb.body, eb_body))
  end
  return builder
end

local function jump_arg_map(args, env)
  local out = {}
  for _, a in ipairs(args or {}) do out[render_name(a.name)] = value_to_expr(a.value, env) end
  return out
end

local function block_label(ref_or_id)
  local id = ref_or_id and ref_or_id.id or ref_or_id
  return render_name(id and id.name)
end

local function quote_choice(choice, env)
  local c = cls(choice)
  if c == CFG.BoolChoice then return value_to_expr(choice.value, env)
  elseif c == CFG.NilChoice then
    local v = value_to_expr(choice.value, env)
    return moon.expr{ v = v, nil_tag = tag_value("NilTag") }[[@{v}.tag == @{nil_tag}]]
  elseif c == CFG.TypeChoice then
    local expr, err = quote_runtime_expr(CFG.RuntimeTypeTest(choice.value, choice.test), env)
    return expr, err
  elseif c == CFG.NumericChoice then
    local l, r = value_to_expr(choice.left, env), value_to_expr(choice.right, env)
    local k = choice.test and choice.test.kind
    if k == "NumEq" then return l:eq(r)
    elseif k == "NumLt" then return l:lt(r)
    elseif k == "NumLe" then return l:le(r)
    elseif k == "NumGt" then return r:lt(l)
    elseif k == "NumGe" then return r:le(l)
    elseif k == "NumNonZero" then return moon.expr{ l = l }[[@{l} ~= as(i64, 0)]] end
    return nil, "unsupported_numeric_choice:" .. tostring(k)
  elseif c == CFG.EqualityChoice then
    return value_to_expr(choice.left, env):eq(value_to_expr(choice.right, env))
  elseif c == CFG.GuardChoice then
    return q_bool(true)
  elseif c == CFG.MetamethodPresentChoice then
    return nil, "unsupported_choice:MetamethodPresentChoice"
  end
  return nil, "unsupported_choice:" .. tostring(choice and choice.kind)
end

local function jump_args_asdl(args, env)
  local _C, _Bind, Tr = tree_api()
  local out = {}
  for _, a in ipairs(args or {}) do out[#out + 1] = Tr.JumpArg(render_name(a.name), as_expr(value_to_expr(a.value, env), "jump arg")) end
  return out
end

local function append_yield_or_return(builder, expr, as_region)
  local _C, _Bind, Tr = tree_api()
  if as_region then
    if expr == nil then builder:emit(Tr.StmtYieldVoid(Tr.StmtSurface)) else builder:emit(Tr.StmtYieldValue(Tr.StmtSurface, as_expr(expr, "yield value"))) end
  else
    if expr == nil then builder:emit(Tr.StmtReturnVoid(Tr.StmtSurface)) else builder:emit(Tr.StmtReturnValue(Tr.StmtSurface, as_expr(expr, "return value"))) end
  end
end

local function append_terminator(builder, env, term, ret_ty, as_region)
  local _C, _Bind, Tr = tree_api()
  local c = cls(term)
  if c == CFG.Return then
    local values = term.values or {}
    if ret_ty == moon.void and #values == 0 then append_yield_or_return(builder, nil, as_region); return true end
    if #values == 0 then append_yield_or_return(builder, default_value_for_type(ret_ty), as_region); return true end
    if #values > 1 then return nil, "multi_value_return" end
    append_yield_or_return(builder, value_to_expr(values[1], env), as_region); return true
  elseif c == CFG.Jump then
    builder:emit(Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(block_label(term.target)), jump_args_asdl(term.args, env)))
    return true
  elseif c == CFG.Branch or c == CFG.BranchArgs then
    local cond, err = quote_choice(term.choice, env); if not cond then return nil, err end
    local true_args = c == CFG.BranchArgs and term.true_args or {}
    local false_args = c == CFG.BranchArgs and term.false_args or {}
    builder:if_(cond, function(tb)
      append_terminator(tb, env, CFG.Jump(term.if_true, true_args or {}), ret_ty, as_region)
    end, function(fb)
      append_terminator(fb, env, CFG.Jump(term.if_false, false_args or {}), ret_ty, as_region)
    end)
    return true
  elseif c == CFG.Unreachable then
    append_yield_or_return(builder, ret_ty == moon.void and nil or default_value_for_type(ret_ty), as_region)
    return true
  end
  return nil, "unsupported_terminator:" .. tostring(term and term.kind)
end

local function make_param_env(params)
  local env = {}
  for _, p in ipairs(params or {}) do
    local name = render_name(p.name)
    env[name] = q_name(name, param_type(p))
  end
  return env
end

local function build_region_block(block, is_entry, region_params, base_env, ret_ty)
  local env = copy_env(base_env)
  local params = {}
  if is_entry then
    for _, p in ipairs(region_params or {}) do
      local name, ty = render_name(p.name), param_type(p)
      params[#params + 1] = { name = name, type = ty, init = base_env[name] or q_name(name, ty) }
      env[name] = q_name(name, ty)
    end
    params = moon.entry_params(params)
  else
    local Tr = moon.default_session.T.MoonTree
    for _, p in ipairs(block.params or {}) do
      local name, ty = render_name(p.name), param_type(p)
      params[#params + 1] = Tr.BlockParam(name, moon.as_type_value(ty, "block param type").ty)
      env[name] = q_name(name, ty)
    end
  end
  local b = make_stmt_builder(env)
  for _, op in ipairs(block.ops or {}) do
    local done, err = emit_op(b, env, op)
    if not done then return nil, err end
  end
  local ok, terr = append_terminator(b, env, block.terminator, ret_ty, true)
  if not ok then return nil, terr end
  local Tr = moon.default_session.T.MoonTree
  local label = Tr.BlockLabel(block_label(block.id))
  if is_entry then return Tr.EntryControlBlock(label, params, b.body) end
  return Tr.ControlBlock(label, params, b.body)
end

local function index_region_blocks(region)
  local entry_key = region.entry and render_name(region.entry.name)
  local entry, others = nil, {}
  for _, block in ipairs(region.blocks or {}) do
    local key = block_label(block.id)
    if key == entry_key then entry = block else others[#others + 1] = block end
  end
  return entry, others
end

local function build_control_expr(kernel, ret_ty, base_env)
  local region = kernel.body
  local entry, others = index_region_blocks(region)
  if not entry then return nil, "missing_entry_block" end
  local entry_block, err = build_region_block(entry, true, region.params or {}, base_env, ret_ty)
  if not entry_block then return nil, err end
  local blocks = {}
  for _, block in ipairs(others) do
    local cb, cerr = build_region_block(block, false, nil, base_env, ret_ty)
    if not cb then return nil, cerr end
    blocks[#blocks + 1] = cb
  end
  local Tr = moon.default_session.T.MoonTree
  if ret_ty == moon.void then
    return Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(render_name(region.id and region.id.name), entry_block, blocks)), nil, "stmt"
  end
  local ty = moon.as_type_value(ret_ty, "control expr result type").ty
  return moon.expr_from_asdl(Tr.ExprControl(Tr.ExprSurface, Tr.ControlExprRegion(render_name(region.id and region.id.name), ty, entry_block, blocks)), ret_ty, "quote_control_region"), nil, "expr"
end

local function build_func_in_bundle(bundle, kernel, opts)
  local ok, errors = check_kernel(kernel)
  if not ok then return nil, errors end
  local ret_ty, ret_err = return_type(kernel)
  if not ret_ty then return unsupported(kernel, ret_err) end
  local fname = render_name(opts.name or (kernel.id and kernel.id.name) or "spongejit_quote_kernel")
  local params = {}
  for i, p in ipairs(kernel.params or {}) do params[i] = { render_name(p.name), param_type(p) } end
  -- Local implementation note: generated CFG block binders are assembled with
  -- Moonlift's typed AST helpers because quote syntax cannot ergonomically splice
  -- arbitrary entry/block parameter binder lists.  All expression and runtime
  -- fragments remain moon.* typed quote/splice values.
  local func = bundle:export_func(fname, moon.params(params), ret_ty, function(builder)
    local base_env = {}
    for _, p in ipairs(kernel.params or {}) do
      local pname = render_name(p.name)
      base_env[pname] = builder:param(pname)
    end
    local blocks = kernel.body and kernel.body.blocks or {}
    if #blocks == 1 and cls(blocks[1].terminator) == CFG.Return and #(blocks[1].params or {}) == 0 then
      local env = copy_env(base_env)
      for _, op in ipairs(blocks[1].ops or {}) do
        local done, err = emit_op(builder, env, op)
        if not done then error("moon_cfg_quote_emit:not_yet_migrated:" .. tostring(err), 2) end
      end
      local values = blocks[1].terminator.values or {}
      if #values == 0 then return nil end
      if #values > 1 then error("moon_cfg_quote_emit:not_yet_migrated:multi_value_return", 2) end
      return value_to_expr(values[1], env)
    end
    local ctrl, cerr, mode = build_control_expr(kernel, ret_ty, base_env)
    if not ctrl then error("moon_cfg_quote_emit:not_yet_migrated:" .. tostring(cerr), 2) end
    if mode == "stmt" then builder:emit(ctrl); return nil end
    return ctrl
  end)
  return func, nil
end

function M.build_func(kernel, opts)
  opts = opts or {}
  local name = render_name(opts.name or (kernel.id and kernel.id.name) or "spongejit_quote_kernel")
  local bundle = moon.module(name .. "_func_bundle")
  declare_runtime_abi(bundle)
  return build_func_in_bundle(bundle, kernel, opts)
end

function declare_runtime_abi(bundle)
  -- Runtime ABI declarations are semantic quote products.  Keep these layouts
  -- in sync with the compatibility TYPE_DECL strings, but construct them here
  -- with moon.fields typed quotes so the quote emitter owns the semantic path.
  bundle:struct(ValueModel.TYPE_NAME, moon.fields[[
    tag: i64;
    payload_i64: i64;
    payload_f64: f64
  ]])
  bundle:struct(OutcomeModel.TYPE_NAME, moon.fields[[
    kind: i64;
    count: i64;
    value0: LuaRTValue;
    value1: LuaRTValue;
    error_kind: i64;
    error_value: LuaRTValue;
    saved_pc: i64;
    saved_top: i64;
    yield_kind: i64;
    value_buffer: ptr(LuaRTValue);
    value_base: i64
  ]])
  bundle:struct(StackModel.STACK_TYPE_NAME, moon.fields[[
    values: ptr(LuaRTValue);
    base: i64;
    top: i64
  ]])
  bundle:struct(StackModel.WINDOW_TYPE_NAME, moon.fields[[
    values: ptr(LuaRTValue);
    base: i64;
    count: i64
  ]])
  bundle:struct(StackModel.SEQ_TYPE_NAME, moon.fields[[
    kind: i64;
    count: i64;
    value0: LuaRTValue;
    value1: LuaRTValue;
    buffer: ptr(LuaRTValue);
    base: i64
  ]])
  bundle:struct(StackModel.VARARG_TYPE_NAME, moon.fields[[
    kind: i64;
    values: ptr(LuaRTValue);
    count: i64;
    table_handle: i64
  ]])
  bundle:struct(CallModel.FRAME_TYPE_NAME, moon.fields[[
    caller_stack: ptr(LuaRTValue);
    callee_stack: ptr(LuaRTValue);
    arg_base: i64;
    arg_count: i64;
    result_base: i64;
    result_count: i64;
    target_ok: bool
  ]])
  bundle:struct(ObjectModel.STRING_TYPE_NAME, moon.fields[[
    byte_len: i64;
    hash: i64;
    numeric_kind: i64;
    numeric_i64: i64;
    numeric_f64: f64
  ]])
  bundle:struct(ObjectModel.HASH_ENTRY_TYPE_NAME, moon.fields[[
    state: i64;
    key: LuaRTValue;
    value: LuaRTValue
  ]])
  bundle:struct(ObjectModel.TABLE_TYPE_NAME, moon.fields[[
    array: ptr(LuaRTValue);
    array_len: i64;
    hash: ptr(LuaRTTableHashEntry);
    hash_capacity: i64;
    hash_count: i64;
    metatable_kind: i64;
    index_table: i64;
    newindex_table: i64;
    gc_color: i64;
    gc_generation: i64;
    gc_epoch: i64;
    barrier_epoch: i64;
    barrier_count: i64;
    barrier_last_child_tag: i64;
    barrier_last_child_payload: i64
  ]])
  bundle:struct(ObjectModel.RAW_GET_TYPE_NAME, moon.fields[[
    hit: bool;
    value: LuaRTValue
  ]])
  bundle:struct(CDataModel.TYPE_NAME, moon.fields[[
    data_i32: ptr(i32);
    data_i64: ptr(i64);
    data_f64: ptr(f64);
    size_bytes: i64;
    type_id: i64;
    ownership_kind: i64;
    finalizer_kind: i64;
    metatype: i64
  ]])
  return bundle
end

function M.declare_runtime_abi(bundle)
  return declare_runtime_abi(bundle)
end

function M.build_bundle(kernel, opts)
  opts = opts or {}
  local ok, errors = check_kernel(kernel)
  if not ok then return nil, errors end
  local name = render_name(opts.name or (kernel.id and kernel.id.name) or "spongejit_quote_kernel")
  local bundle = moon.module(name .. "_bundle")
  declare_runtime_abi(bundle)
  local ok_build, func, ferr = pcall(build_func_in_bundle, bundle, kernel, opts)
  if not ok_build then return nil, { tostring(func) } end
  if not func then return nil, ferr end
  return bundle, nil
end

function M.build(kernel, opts)
  return M.build_bundle(kernel, opts or {})
end

function M.compile(kernel, opts)
  opts = opts or {}
  local bundle, errors = M.build_bundle(kernel, opts)
  if not bundle then return nil, errors end
  local compiled = bundle:compile(opts.compile_opts or {})
  local name = render_name(opts.name or (kernel.id and kernel.id.name) or "spongejit_quote_kernel")
  return assert(compiled:get(name)), compiled
end

function M.run(kernel, opts, ...)
  local fn, compiled_or_errors = M.compile(kernel, opts or {})
  if not fn then return nil, compiled_or_errors end
  return fn(...)
end

return M
