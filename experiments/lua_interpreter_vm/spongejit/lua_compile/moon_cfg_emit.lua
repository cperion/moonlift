-- moon_cfg_emit.lua -- mechanical MoonCFG -> Moonlift source renderer.
--
-- This renderer prints MoonCFG only.  It must not inspect LuaSrc/LuaNF to
-- choose semantics and must not synthesize out_tag/protocol continuations.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local CFG = T.MoonCFG
local Validate = require("lua_compile.moon_cfg_validate")
local ValueModel = require("lua_compile.lua_rt_value_model")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local StackModel = require("lua_compile.lua_rt_stack_model")
local ObjectModel = require("lua_compile.lua_rt_object_model")
local CDataModel = require("lua_compile.lua_rt_cdata_model")

local M = {}

local function class(v) return pvm.classof(v) end
local function n(v) return tonumber(v) or 0 end
local function int_lit(v) return tostring(math.floor(n(v))) end
local function i64_lit(v) return "as(i64, " .. int_lit(v) .. ")" end
local function f64_lit(v)
  local s = tostring(tonumber(v) or 0)
  if not s:find("[%.eE]") then s = s .. ".0" end
  return s
end
local function par(s) return "(" .. s .. ")" end

local RESERVED = {
  ["and"] = true, ["as"] = true, ["block"] = true, ["cont"] = true,
  ["else"] = true, ["emit"] = true, ["end"] = true, ["entry"] = true,
  ["extern"] = true, ["expr"] = true, ["false"] = true, ["func"] = true,
  ["if"] = true, ["in"] = true, ["jump"] = true, ["let"] = true,
  ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
  ["region"] = true, ["return"] = true, ["select"] = true,
  ["struct"] = true, ["switch"] = true, ["then"] = true, ["true"] = true,
  ["union"] = true, ["var"] = true, ["yield"] = true,
}

local function render_name(name)
  local s = tostring(name and name.text or name or "")
  s = s:gsub("[^%w_]", "_")
  if s == "" then s = "_" end
  if s:match("^%d") then s = "_" .. s end
  if RESERVED[s] then s = s .. "_" end
  return s
end

local function render_type(ty)
  return tostring(ty and ty.moon_type or ty or "void")
end

local function render_param(p)
  return render_name(p.name) .. ": " .. render_type(p.type)
end

local function render_const(c)
  local cls = class(c)
  if cls == CFG.I64Const then return i64_lit(c.value)
  elseif cls == CFG.F64Const then return f64_lit(c.value)
  elseif cls == CFG.BoolConst then return c.value == true and "true" or "false"
  elseif cls == CFG.StringConst then return string.format("%q", c.value or "") end
  error("unsupported MoonCFG.Const reached emission: " .. tostring(c and c.kind))
end

local function render_place(place)
  local cls = class(place)
  if cls == CFG.Temp then return render_name(place.name)
  elseif cls == CFG.StackSlot then return "stack_" .. int_lit(place.index)
  elseif cls == CFG.ConstSlot then return "const_" .. int_lit(place.index)
  elseif cls == CFG.UpvalueSlot then return "upvalue_" .. int_lit(place.index)
  elseif cls == CFG.VarargSlot then return "vararg_" .. int_lit(place.index)
  elseif cls == CFG.FrameTop then return "frame_top"
  elseif cls == CFG.ExecCtx then return "exec_ctx" end
  error("unsupported MoonCFG.Place reached emission: " .. tostring(place and place.kind))
end

local render_value
local function render_values(args)
  local out = {}
  for _, a in ipairs(args or {}) do out[#out + 1] = render_value(a) end
  return out
end

function render_value(v)
  local cls = class(v)
  if cls == CFG.PlaceValue then return render_place(v.place)
  elseif cls == CFG.ConstValue then return render_const(v.const)
  elseif cls == CFG.ParamValue then return render_name(v.name)
  elseif cls == CFG.UnitValue then return "nil" end
  error("unsupported MoonCFG.Value reached emission: " .. tostring(v and v.kind))
end

local function join_binary(xs, op, empty)
  if #xs == 0 then return empty end
  local s = xs[1]
  for i = 2, #xs do s = par(s .. " " .. op .. " " .. xs[i]) end
  return s
end

local function tag_lit(tag_name)
  return i64_lit(ValueModel.tag_value(tag_name))
end

local function seq_kind_lit(kind_name)
  return i64_lit(StackModel.seq_kind_value(kind_name))
end

local function vararg_kind_lit(kind_name)
  return i64_lit(StackModel.vararg_kind_value(kind_name))
end

local function outcome_kind_lit(kind_name)
  return i64_lit(OutcomeModel.outcome_kind_value(kind_name))
end

local function error_kind_lit(kind)
  return i64_lit(OutcomeModel.error_kind_value(kind))
end

local function yield_kind_lit(resume_point)
  return i64_lit(OutcomeModel.yield_kind_value(resume_point))
end

local function render_tag_compare(value_expr, tag_name)
  return par(value_expr .. ".tag == " .. tag_lit(tag_name))
end

local function render_tag_any(value_expr, tag_names)
  local parts = {}
  for _, tag_name in ipairs(tag_names or {}) do parts[#parts + 1] = render_tag_compare(value_expr, tag_name) end
  return join_binary(parts, "or", "false")
end

local function render_primitive(op, args)
  local k = op and op.kind
  local xs = render_values(args)
  if k == "AddI64" then return join_binary(xs, "+", i64_lit(0))
  elseif k == "SubI64" then return #xs == 1 and par(i64_lit(0) .. " - " .. xs[1]) or join_binary(xs, "-", i64_lit(0))
  elseif k == "MulI64" then return join_binary(xs, "*", i64_lit(1))
  elseif k == "IDivI64" then return join_binary(xs, "/", i64_lit(0))
  elseif k == "ModI64" then return join_binary(xs, "%", i64_lit(0))
  elseif k == "DivF64" then return join_binary(xs, "/", f64_lit(0))
  elseif k == "Eq" then return par((xs[1] or "false") .. " == " .. (xs[2] or "false"))
  elseif k == "Lt" then return par((xs[1] or "false") .. " < " .. (xs[2] or "false"))
  elseif k == "Le" then return par((xs[1] or "false") .. " <= " .. (xs[2] or "false"))
  elseif k == "Not" then return par("not " .. (xs[1] or "false"))
  elseif k == "Truthy" then return xs[1] or "false" end
  error("unsupported MoonCFG.PrimOp reached emission: " .. tostring(k))
end

local function render_nil_kind_payload(kind)
  return i64_lit(ValueModel.payload_for_nil_kind(kind))
end

local function render_box(tag_name, payload_i64, payload_f64)
  return ValueModel.TYPE_NAME .. "{ tag = " .. tag_lit(tag_name)
      .. ", payload_i64 = " .. (payload_i64 or i64_lit(0))
      .. ", payload_f64 = " .. (payload_f64 or f64_lit(0)) .. " }"
end

local function tag_name_from_runtime_tag(tag)
  return tag and tag.kind
end

local function render_nil_value()
  return render_box("NilTag", i64_lit(0), f64_lit(0))
end

local function lua_value_ptr_null()
  return "as(ptr(" .. ValueModel.TYPE_NAME .. "), " .. i64_lit(0) .. ")"
end

local function raw_get_absent_value()
  return render_box("AbsentKeyTag", i64_lit(ValueModel.payload_for_nil_kind(B.T.LuaRT.AbsentKeySentinel)), f64_lit(0))
end

local function render_string_len(strings, value)
  return "select(" .. value .. ".payload_i64 < " .. i64_lit(0) .. ", " .. par(i64_lit(0) .. " - " .. value .. ".payload_i64") .. ", " .. strings .. "[as(index, " .. value .. ".payload_i64)].byte_len)"
end

local function numeric_kind_lit(kind_name)
  return i64_lit(ObjectModel.string_numeric_kind_value(kind_name))
end

local function render_is_string(value)
  return render_tag_any(value, { "ShortStringTag", "LongStringTag" })
end

local function render_string_numeric_kind(strings, value)
  return strings .. "[as(index, " .. value .. ".payload_i64)].numeric_kind"
end

local function render_string_to_number_ok(strings, value)
  return par(render_is_string(value) .. " and " .. value .. ".payload_i64 >= " .. i64_lit(0) .. " and " .. render_string_numeric_kind(strings, value) .. " ~= " .. numeric_kind_lit("NotNumeric"))
end

local function render_string_integral(strings, value)
  return par(render_string_to_number_ok(strings, value) .. " and " .. render_string_numeric_kind(strings, value) .. " == " .. numeric_kind_lit("DecimalInteger"))
end

local function render_string_to_number(strings, value)
  local kind = render_string_numeric_kind(strings, value)
  local is_int = par(kind .. " == " .. numeric_kind_lit("DecimalInteger"))
  local is_float = par(kind .. " == " .. numeric_kind_lit("DecimalFloat"))
  local i_payload = strings .. "[as(index, " .. value .. ".payload_i64)].numeric_i64"
  local f_payload = strings .. "[as(index, " .. value .. ".payload_i64)].numeric_f64"
  return ValueModel.TYPE_NAME .. "{ tag = select(" .. is_int .. ", " .. tag_lit("IntegerTag") .. ", select(" .. is_float .. ", " .. tag_lit("FloatTag") .. ", " .. tag_lit("NilTag") .. ")), payload_i64 = select(" .. is_int .. ", " .. i_payload .. ", " .. i64_lit(0) .. "), payload_f64 = select(" .. is_float .. ", " .. f_payload .. ", " .. f64_lit(0) .. ") }"
end

local function render_number_or_string_ok(strings, value)
  return par(render_tag_any(value, { "IntegerTag", "FloatTag" }) .. " or " .. render_string_to_number_ok(strings, value))
end

local function render_effective_integral(strings, value)
  return par(render_tag_compare(value, "IntegerTag") .. " or " .. render_string_integral(strings, value))
end

local function render_effective_i64(strings, value)
  return "select(" .. render_tag_compare(value, "IntegerTag") .. ", " .. value .. ".payload_i64, " .. strings .. "[as(index, " .. value .. ".payload_i64)].numeric_i64)"
end

local function render_effective_f64(strings, value)
  local string_kind = render_string_numeric_kind(strings, value)
  local string_f64 = "select(" .. string_kind .. " == " .. numeric_kind_lit("DecimalInteger") .. ", as(f64, " .. strings .. "[as(index, " .. value .. ".payload_i64)].numeric_i64), " .. strings .. "[as(index, " .. value .. ".payload_i64)].numeric_f64)"
  return "select(" .. render_tag_compare(value, "IntegerTag") .. ", as(f64, " .. value .. ".payload_i64), select(" .. render_tag_compare(value, "FloatTag") .. ", " .. value .. ".payload_f64, " .. string_f64 .. "))"
end

local function render_arithmetic_numeric_ok(op, strings, left, right)
  local k = op and op.kind
  if k ~= "ArithAdd" then return "false" end
  return par(render_number_or_string_ok(strings, left) .. " and " .. render_number_or_string_ok(strings, right))
end

local function render_arithmetic_error_value(op, strings, left, right)
  local k = op and op.kind
  if k ~= "ArithAdd" then return left end
  return "select(" .. render_number_or_string_ok(strings, left) .. ", " .. right .. ", " .. left .. ")"
end

local function render_arithmetic_no_meta(op, strings, left, right)
  local k = op and op.kind
  if k ~= "ArithAdd" then return render_box("NilTag", i64_lit(0), f64_lit(0)) end
  local both_int = par(render_effective_integral(strings, left) .. " and " .. render_effective_integral(strings, right))
  local numeric = render_arithmetic_numeric_ok(op, strings, left, right)
  local int_sum = par(render_effective_i64(strings, left) .. " + " .. render_effective_i64(strings, right))
  local float_sum = par(render_effective_f64(strings, left) .. " + " .. render_effective_f64(strings, right))
  return ValueModel.TYPE_NAME .. "{ tag = select(" .. both_int .. ", " .. tag_lit("IntegerTag") .. ", select(" .. numeric .. ", " .. tag_lit("FloatTag") .. ", " .. tag_lit("NilTag") .. ")), payload_i64 = select(" .. both_int .. ", " .. int_sum .. ", " .. i64_lit(0) .. "), payload_f64 = select(" .. par(numeric .. " and not " .. both_int) .. ", " .. float_sum .. ", " .. f64_lit(0) .. ") }"
end

local function cdata_type_id_lit(type_id)
  return i64_lit(type_id and type_id.id or 0)
end

local function render_cdata_record(cdata_bank, cdata_value)
  return cdata_bank .. "[as(index, " .. cdata_value .. ".payload_i64)]"
end

local function cdata_scalar_info(scalar)
  local info = CDataModel.scalar_info(scalar)
  if not info then error("unsupported cdata scalar kind reached emission: " .. tostring(scalar and scalar.kind)) end
  return info
end

local function render_cdata_access_ok(cdata_bank, cdata_value, scalar, type_id, offset_bytes, width_bytes)
  local info = cdata_scalar_info(scalar)
  local off = tonumber(offset_bytes) or 0
  local width = tonumber(width_bytes) or 0
  local cd = render_cdata_record(cdata_bank, cdata_value)
  local scalar_ok = width == info.width
  local aligned = info.align <= 1 or (off % info.align) == 0
  return par(cdata_value .. ".tag == " .. tag_lit("CDataTag")
      .. " and " .. cdata_value .. ".payload_i64 >= " .. i64_lit(0)
      .. " and " .. cd .. ".type_id == " .. cdata_type_id_lit(type_id)
      .. " and " .. (scalar_ok and "true" or "false")
      .. " and " .. (aligned and "true" or "false")
      .. " and " .. i64_lit(off) .. " >= " .. i64_lit(0)
      .. " and " .. i64_lit(off + width) .. " <= " .. cd .. ".size_bytes")
end

local function render_cdata_scalar_load(cdata_bank, cdata_value, scalar, type_id, offset_bytes, width_bytes)
  local info = cdata_scalar_info(scalar)
  local off = tonumber(offset_bytes) or 0
  local cd = render_cdata_record(cdata_bank, cdata_value)
  local ok = render_cdata_access_ok(cdata_bank, cdata_value, scalar, type_id, offset_bytes, width_bytes)
  if info.moon_type == "i32" then
    local load = cd .. ".data_i32[as(index, " .. i64_lit(off / 4) .. ")]"
    return "select(" .. ok .. ", " .. render_box("IntegerTag", "as(i64, " .. load .. ")", f64_lit(0)) .. ", " .. render_nil_value() .. ")"
  elseif info.moon_type == "i64" then
    local load = cd .. ".data_i64[as(index, " .. i64_lit(off / 8) .. ")]"
    return "select(" .. ok .. ", " .. render_box("IntegerTag", load, f64_lit(0)) .. ", " .. render_nil_value() .. ")"
  elseif info.moon_type == "f64" then
    local load = cd .. ".data_f64[as(index, " .. i64_lit(off / 8) .. ")]"
    return "select(" .. ok .. ", " .. render_box("FloatTag", i64_lit(0), load) .. ", " .. render_nil_value() .. ")"
  end
  error("unsupported cdata scalar type reached emission: " .. tostring(info.moon_type))
end

local function render_table_array_len(tables, value)
  return tables .. "[as(index, " .. value .. ".payload_i64)].array_len"
end

local function hash_state_lit(name)
  return i64_lit(ObjectModel.hash_entry_state_value(name))
end

local function render_is_hash_key(value)
  return par(render_tag_compare(value, "IntegerTag") .. " or " .. render_is_string(value))
end

local function render_hash_entry(tables, tablev, index)
  local tbl = tables .. "[as(index, " .. tablev .. ".payload_i64)]"
  return tbl .. ".hash[as(index, " .. i64_lit(index) .. ")]"
end

local function render_hash_valid(tables, tablev)
  local tbl = tables .. "[as(index, " .. tablev .. ".payload_i64)]"
  return par(tablev .. ".tag == " .. tag_lit("TableTag")
      .. " and " .. tbl .. ".hash_capacity > " .. i64_lit(0)
      .. " and " .. tbl .. ".hash_capacity <= " .. i64_lit(ObjectModel.HASH_PROBE_LIMIT)
      .. " and " .. render_is_hash_key("__KEY__"))
end

local function render_hash_key_equal(entry_key, key)
  local both_int = par(entry_key .. ".tag == " .. tag_lit("IntegerTag") .. " and " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " and " .. entry_key .. ".payload_i64 == " .. key .. ".payload_i64")
  local both_string = par(render_is_string(entry_key) .. " and " .. render_is_string(key) .. " and " .. entry_key .. ".payload_i64 == " .. key .. ".payload_i64")
  return par(both_int .. " or " .. both_string)
end

local function render_hash_match(entry, key)
  return par(entry .. ".state == " .. hash_state_lit("Occupied") .. " and " .. render_hash_key_equal(entry .. ".key", key))
end

local function render_hash_insertable(entry)
  return par(entry .. ".state == " .. hash_state_lit("Empty") .. " or " .. entry .. ".state == " .. hash_state_lit("Tombstone"))
end

local function render_collectable_value(value)
  return render_tag_any(value, { "ShortStringTag", "LongStringTag", "TableTag", "LuaClosureTag", "CClosureTag", "UserdataTag", "ThreadTag", "CDataTag" })
end

local function render_table_barrier_needed(tables, tablev, value)
  local tbl = tables .. "[as(index, " .. tablev .. ".payload_i64)]"
  return par(tablev .. ".tag == " .. tag_lit("TableTag")
      .. " and " .. tbl .. ".gc_color == " .. i64_lit(ObjectModel.gc_color_value("Black"))
      .. " and " .. tbl .. ".gc_generation == " .. i64_lit(ObjectModel.gc_generation_value("Old"))
      .. " and " .. render_collectable_value(value))
end

local function render_raw_get(tables, tablev, key)
  local tbl = tables .. "[as(index, " .. tablev .. ".payload_i64)]"
  local array_hit = par(tablev .. ".tag == " .. tag_lit("TableTag") .. " and " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " and " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " and " .. key .. ".payload_i64 <= " .. tbl .. ".array_len")
  local array_val = tbl .. ".array[as(index, " .. key .. ".payload_i64 - " .. i64_lit(1) .. ")]"
  local hash_valid = par((render_hash_valid(tables, tablev):gsub("__KEY__", key)))
  local hash_hit_parts = {}
  local value_expr = raw_get_absent_value()
  for i = ObjectModel.HASH_PROBE_LIMIT - 1, 0, -1 do
    local e = render_hash_entry(tables, tablev, i)
    local in_cap = par(hash_valid .. " and " .. tbl .. ".hash_capacity > " .. i64_lit(i))
    local hit = par(in_cap .. " and " .. render_hash_match(e, key))
    hash_hit_parts[#hash_hit_parts + 1] = hit
    value_expr = "select(" .. hit .. ", " .. e .. ".value, " .. value_expr .. ")"
  end
  local hash_hit = join_binary(hash_hit_parts, "or", "false")
  local hit = par(array_hit .. " or " .. hash_hit)
  local val = "select(" .. array_hit .. ", " .. array_val .. ", " .. value_expr .. ")"
  return ObjectModel.RAW_GET_TYPE_NAME .. "{ hit = " .. hit .. ", value = " .. val .. " }"
end

local function render_table_raw_set_can_write(tables, tablev, key)
  local tbl = tables .. "[as(index, " .. tablev .. ".payload_i64)]"
  local array_hit = par(tablev .. ".tag == " .. tag_lit("TableTag") .. " and " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " and " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " and " .. key .. ".payload_i64 <= " .. tbl .. ".array_len")
  local hash_valid = par((render_hash_valid(tables, tablev):gsub("__KEY__", key)))
  local slots = {}
  for i = 0, ObjectModel.HASH_PROBE_LIMIT - 1 do
    local e = render_hash_entry(tables, tablev, i)
    local in_cap = par(hash_valid .. " and " .. tbl .. ".hash_capacity > " .. i64_lit(i))
    slots[#slots + 1] = par(in_cap .. " and " .. par(render_hash_match(e, key) .. " or " .. render_hash_insertable(e)))
  end
  return par(array_hit .. " or " .. join_binary(slots, "or", "false"))
end

local function seq_field(seq_expr, index)
  return (tonumber(index) or 0) == 1 and seq_expr .. ".value1" or seq_expr .. ".value0"
end

local function seq_value_at(seq_expr, index)
  index = tonumber(index) or 0
  if index == 0 or index == 1 then return seq_field(seq_expr, index) end
  return seq_expr .. ".buffer[as(index, " .. seq_expr .. ".base + " .. i64_lit(index) .. ")]"
end

local function render_seq(kind_name, count, value0, value1, buffer, base)
  return StackModel.SEQ_TYPE_NAME .. "{ kind = " .. seq_kind_lit(kind_name)
      .. ", count = " .. count
      .. ", value0 = " .. (value0 or render_nil_value())
      .. ", value1 = " .. (value1 or render_nil_value())
      .. ", buffer = " .. (buffer or lua_value_ptr_null())
      .. ", base = " .. (base or i64_lit(0)) .. " }"
end

local function render_outcome_value(values, idx)
  local v = (values or {})[idx]
  if v then return render_value(v) end
  return render_nil_value()
end

local function render_outcome_index(outcome_expr, index, field)
  local value_field = (tonumber(index) or 0) == 1 and "value1" or "value0"
  return outcome_expr .. "." .. value_field .. "." .. field
end

local function render_expr(e)
  local cls = class(e)
  if cls == CFG.ValueExpr then return render_value(e.value)
  elseif cls == CFG.Primitive then return render_primitive(e.op, e.args or {})
  elseif cls == CFG.Load then return render_place(e.place)
  elseif cls == CFG.AddressOf then return "&" .. render_place(e.place)
  elseif cls == CFG.Convert then return "as(" .. render_type(e.type) .. ", " .. render_value(e.value) .. ")"
  elseif cls == CFG.RuntimeBoxNil then return render_box(ValueModel.tag_name_for_nil_kind(e.kind), render_nil_kind_payload(e.kind), f64_lit(0))
  elseif cls == CFG.RuntimeBoxBool then
    local b = render_value(e.value)
    return ValueModel.TYPE_NAME .. "{ tag = select(" .. b .. ", " .. tag_lit("TrueTag") .. ", " .. tag_lit("FalseTag") .. "), payload_i64 = select(" .. b .. ", " .. i64_lit(1) .. ", " .. i64_lit(0) .. "), payload_f64 = " .. f64_lit(0) .. " }"
  elseif cls == CFG.RuntimeBoxI64 then return render_box("IntegerTag", render_value(e.value), f64_lit(0))
  elseif cls == CFG.RuntimeBoxF64 then return render_box("FloatTag", i64_lit(0), render_value(e.value))
  elseif cls == CFG.RuntimeBoxRef then return render_box(tag_name_from_runtime_tag(e.tag), render_value(e.handle), f64_lit(0))
  elseif cls == CFG.RuntimeTag then return render_value(e.value) .. ".tag"
  elseif cls == CFG.RuntimePayloadI64 then return render_value(e.value) .. ".payload_i64"
  elseif cls == CFG.RuntimePayloadF64 then return render_value(e.value) .. ".payload_f64"
  elseif cls == CFG.RuntimeTruthiness then
    local v = render_value(e.value)
    return par("not " .. par(render_tag_any(v, { "NilTag", "EmptySlotTag", "AbsentKeyTag", "NoTableTag", "FalseTag" })))
  elseif cls == CFG.RuntimeTypeTest then
    local tags = ValueModel.tags_for_type_test(e.test)
    if not tags then error("unsupported LuaRT.TypeTest reached emission: " .. tostring(e.test and e.test.kind)) end
    return render_tag_any(render_value(e.value), tags)
  elseif cls == CFG.RuntimeOutcomeReturn then
    return OutcomeModel.TYPE_NAME .. "{ kind = " .. outcome_kind_lit("NormalReturnOutcome")
        .. ", count = " .. render_value(e.count)
        .. ", value0 = " .. render_outcome_value(e.values, 1)
        .. ", value1 = " .. render_outcome_value(e.values, 2)
        .. ", value_buffer = " .. render_value(e.value_buffer)
        .. ", error_kind = " .. i64_lit(0)
        .. ", error_value = " .. render_nil_value()
        .. ", saved_pc = " .. i64_lit(0)
        .. ", saved_top = " .. i64_lit(0)
        .. ", yield_kind = " .. i64_lit(0) .. " }"
  elseif cls == CFG.RuntimeOutcomeError then
    return OutcomeModel.TYPE_NAME .. "{ kind = " .. outcome_kind_lit("LuaErrorOutcome")
        .. ", count = " .. i64_lit(0)
        .. ", value0 = " .. render_nil_value()
        .. ", value1 = " .. render_nil_value()
        .. ", value_buffer = " .. i64_lit(0)
        .. ", error_kind = " .. error_kind_lit(e.kind)
        .. ", error_value = " .. render_value(e.error_value)
        .. ", saved_pc = " .. render_value(e.saved_pc)
        .. ", saved_top = " .. render_value(e.saved_top)
        .. ", yield_kind = " .. i64_lit(0) .. " }"
  elseif cls == CFG.RuntimeOutcomeYield then
    return OutcomeModel.TYPE_NAME .. "{ kind = " .. outcome_kind_lit("LuaYieldOutcome")
        .. ", count = " .. render_value(e.count)
        .. ", value0 = " .. render_outcome_value(e.values, 1)
        .. ", value1 = " .. render_outcome_value(e.values, 2)
        .. ", value_buffer = " .. i64_lit(0)
        .. ", error_kind = " .. i64_lit(0)
        .. ", error_value = " .. render_nil_value()
        .. ", saved_pc = " .. render_value(e.saved_pc)
        .. ", saved_top = " .. render_value(e.saved_top)
        .. ", yield_kind = " .. yield_kind_lit(e.resume_point) .. " }"
  elseif cls == CFG.RuntimeStackLoad then return render_value(e.stack) .. "[as(index, " .. render_value(e.index) .. ")]"
  elseif cls == CFG.RuntimeTopLoad then return render_value(e.top_ptr) .. "[as(index, 0)]"
  elseif cls == CFG.RuntimeOpenCountFromTop then return par(render_value(e.top) .. " - " .. render_value(e.base))
  elseif cls == CFG.RuntimeValueSeqFixed then
    return render_seq("FixedSeq", render_value(e.count), render_outcome_value(e.values, 1), render_outcome_value(e.values, 2), lua_value_ptr_null(), i64_lit(0))
  elseif cls == CFG.RuntimeValueSeqFromStack then
    local stack, base, count = render_value(e.stack), render_value(e.base), render_value(e.count)
    return render_seq("OpenSeq", count,
      stack .. "[as(index, " .. base .. ")]",
      stack .. "[as(index, " .. base .. " + " .. i64_lit(1) .. ")]",
      stack, base)
  elseif cls == CFG.RuntimeValueSeqFromVarargs then
    local src, count = render_value(e.varargs), render_value(e.count)
    return render_seq("VarargSeq", count,
      src .. ".values[as(index, 0)]",
      src .. ".values[as(index, 1)]",
      src .. ".values", i64_lit(0))
  elseif cls == CFG.RuntimeValueSeqAdjust then
    local seq = render_value(e.seq)
    local ak = e.adjustment and e.adjustment.kind
    local count = seq .. ".count"
    if ak == "ExactCount" or ak == "FillNilTo" or ak == "TruncateTo" then count = i64_lit(e.adjustment.count and e.adjustment.count.value or e.adjustment.count and e.adjustment.count.count or 0) end
    if ak ~= "ExactCount" and ak ~= "FillNilTo" and ak ~= "TruncateTo" and ak ~= "OpenResult" and ak ~= "PropagateOpenTail" then error("unsupported LuaRT.ResultAdjustment reached emission: " .. tostring(ak)) end
    local v0 = ak == "FillNilTo" and "select(" .. seq .. ".count >= " .. i64_lit(1) .. ", " .. seq .. ".value0, " .. render_nil_value() .. ")" or seq .. ".value0"
    local v1 = ak == "FillNilTo" and "select(" .. seq .. ".count >= " .. i64_lit(2) .. ", " .. seq .. ".value1, " .. render_nil_value() .. ")" or seq .. ".value1"
    return render_seq("AdjustedSeq", count, v0, v1, seq .. ".buffer", seq .. ".base")
  elseif cls == CFG.RuntimeValueSeqCount then return render_value(e.seq) .. ".count"
  elseif cls == CFG.RuntimeValueSeqValue then return seq_value_at(render_value(e.seq), e.index)
  elseif cls == CFG.RuntimeVarargSource then
    return StackModel.VARARG_TYPE_NAME .. "{ kind = " .. vararg_kind_lit("HiddenFrameVarargs")
        .. ", values = " .. render_value(e.values)
        .. ", count = " .. render_value(e.count)
        .. ", table_handle = " .. render_value(e.table_handle) .. " }"
  elseif cls == CFG.RuntimeVarargCount then return render_value(e.source) .. ".count"
  elseif cls == CFG.RuntimeVarargGet then
    local src, key = render_value(e.source), render_value(e.key)
    local in_range = par(key .. ".tag == " .. tag_lit("IntegerTag") .. " and " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " and " .. key .. ".payload_i64 <= " .. src .. ".count")
    return "select(" .. in_range .. ", " .. src .. ".values[as(index, " .. key .. ".payload_i64 - " .. i64_lit(1) .. ")], " .. render_nil_value() .. ")"
  elseif cls == CFG.RuntimeTableRawGet then return render_raw_get(render_value(e.tables), render_value(e.table_value), render_value(e.key))
  elseif cls == CFG.RuntimeRawGetHit then return render_value(e.rawget) .. ".hit"
  elseif cls == CFG.RuntimeRawGetValue then return render_value(e.rawget) .. ".value"
  elseif cls == CFG.RuntimeRawGetValueOrNil then return "select(" .. render_value(e.rawget) .. ".hit, " .. render_value(e.rawget) .. ".value, " .. render_nil_value() .. ")"
  elseif cls == CFG.RuntimeTableRawSetCanWrite then return render_table_raw_set_can_write(render_value(e.tables), render_value(e.table_value), render_value(e.key))
  elseif cls == CFG.RuntimeTableWriteBarrierNeeded then return render_table_barrier_needed(render_value(e.tables), render_value(e.table_value), render_value(e.value))
  elseif cls == CFG.RuntimeTableArrayLen then return render_table_array_len(render_value(e.tables), render_value(e.table_value))
  elseif cls == CFG.RuntimeStringLen then return render_string_len(render_value(e.strings), render_value(e.value))
  elseif cls == CFG.RuntimeLenNoMeta then
    local v, strings, tables = render_value(e.value), render_value(e.strings), render_value(e.tables)
    local is_string = render_tag_any(v, { "ShortStringTag", "LongStringTag" })
    local is_table = render_tag_compare(v, "TableTag")
    return "select(" .. is_string .. ", " .. render_string_len(strings, v) .. ", select(" .. is_table .. ", " .. render_table_array_len(tables, v) .. ", " .. i64_lit(0) .. "))"
  elseif cls == CFG.RuntimeStringConcat2 then
    local left, right, strings = render_value(e.left), render_value(e.right), render_value(e.strings)
    local len = par(render_string_len(strings, left) .. " + " .. render_string_len(strings, right))
    return render_box("ShortStringTag", par(i64_lit(0) .. " - " .. len), f64_lit(0))
  elseif cls == CFG.RuntimeArithmeticNumericOk then return render_arithmetic_numeric_ok(e.op, render_value(e.strings), render_value(e.left), render_value(e.right))
  elseif cls == CFG.RuntimeArithmeticNoMeta then return render_arithmetic_no_meta(e.op, render_value(e.strings), render_value(e.left), render_value(e.right))
  elseif cls == CFG.RuntimeArithmeticErrorValue then return render_arithmetic_error_value(e.op, render_value(e.strings), render_value(e.left), render_value(e.right))
  elseif cls == CFG.RuntimeCDataAccessOk then return render_cdata_access_ok(render_value(e.cdata_bank), render_value(e.cdata_value), e.scalar, e.type_id, e.offset_bytes, e.width_bytes)
  elseif cls == CFG.RuntimeCDataLoadScalar then return render_cdata_scalar_load(render_value(e.cdata_bank), render_value(e.cdata_value), e.scalar, e.type_id, e.offset_bytes, e.width_bytes)
  elseif cls == CFG.RuntimeOutcomeKind then return render_value(e.outcome) .. ".kind"
  elseif cls == CFG.RuntimeOutcomeCount then return render_value(e.outcome) .. ".count"
  elseif cls == CFG.RuntimeOutcomeValueTag then return render_outcome_index(render_value(e.outcome), e.index, "tag")
  elseif cls == CFG.RuntimeOutcomeValuePayloadI64 then return render_outcome_index(render_value(e.outcome), e.index, "payload_i64")
  elseif cls == CFG.RuntimeOutcomeValuePayloadF64 then return render_outcome_index(render_value(e.outcome), e.index, "payload_f64")
  elseif cls == CFG.RuntimeOutcomeErrorKind then return render_value(e.outcome) .. ".error_kind"
  elseif cls == CFG.RuntimeOutcomeErrorValueTag then return render_value(e.outcome) .. ".error_value.tag"
  elseif cls == CFG.RuntimeOutcomeErrorValuePayloadI64 then return render_value(e.outcome) .. ".error_value.payload_i64"
  elseif cls == CFG.RuntimeOutcomeSavedPc then return render_value(e.outcome) .. ".saved_pc"
  elseif cls == CFG.RuntimeOutcomeYieldKind then return render_value(e.outcome) .. ".yield_kind"
  end
  error("unsupported MoonCFG.Expr reached emission: " .. tostring(e and e.kind))
end

local function render_choice(choice)
  local cls = class(choice)
  if cls == CFG.BoolChoice then return render_value(choice.value) end
  if cls == CFG.NumericChoice then
    local left = render_value(choice.left)
    local right = render_value(choice.right)
    local k = choice.test and choice.test.kind
    if k == "NumEq" then return par(left .. " == " .. right)
    elseif k == "NumLt" then return par(left .. " < " .. right)
    elseif k == "NumLe" then return par(left .. " <= " .. right)
    elseif k == "NumGt" then return par(left .. " > " .. right)
    elseif k == "NumGe" then return par(left .. " >= " .. right)
    elseif k == "NumNonZero" then return par(left .. " ~= " .. i64_lit(0)) end
  end
  error("unsupported MoonCFG.Choice reached emission: " .. tostring(choice and choice.kind))
end

local function infer_expr_type(e)
  local cls = class(e)
  if cls == CFG.Primitive then
    local k = e.op and e.op.kind
    if k == "DivF64" then return "f64" end
    if k == "Eq" or k == "Lt" or k == "Le" or k == "Not" or k == "Truthy" then return "bool" end
    return "i64"
  elseif cls == CFG.RuntimeBoxNil or cls == CFG.RuntimeBoxBool or cls == CFG.RuntimeBoxI64 or cls == CFG.RuntimeBoxF64 or cls == CFG.RuntimeBoxRef or cls == CFG.RuntimeStackLoad or cls == CFG.RuntimeVarargGet or cls == CFG.RuntimeValueSeqValue or cls == CFG.RuntimeRawGetValue or cls == CFG.RuntimeRawGetValueOrNil or cls == CFG.RuntimeStringConcat2 or cls == CFG.RuntimeArithmeticNoMeta or cls == CFG.RuntimeArithmeticErrorValue then return ValueModel.TYPE_NAME
  elseif cls == CFG.RuntimeOutcomeReturn or cls == CFG.RuntimeOutcomeError or cls == CFG.RuntimeOutcomeYield then return OutcomeModel.TYPE_NAME
  elseif cls == CFG.RuntimeValueSeqFixed or cls == CFG.RuntimeValueSeqFromStack or cls == CFG.RuntimeValueSeqFromVarargs or cls == CFG.RuntimeValueSeqAdjust then return StackModel.SEQ_TYPE_NAME
  elseif cls == CFG.RuntimeTableRawGet then return ObjectModel.RAW_GET_TYPE_NAME
  elseif cls == CFG.RuntimeVarargSource then return StackModel.VARARG_TYPE_NAME
  elseif cls == CFG.RuntimeTag or cls == CFG.RuntimePayloadI64 or cls == CFG.RuntimeTopLoad or cls == CFG.RuntimeOpenCountFromTop or cls == CFG.RuntimeValueSeqCount or cls == CFG.RuntimeVarargCount
      or cls == CFG.RuntimeTableArrayLen or cls == CFG.RuntimeStringLen or cls == CFG.RuntimeLenNoMeta
      or cls == CFG.RuntimeOutcomeKind or cls == CFG.RuntimeOutcomeCount
      or cls == CFG.RuntimeOutcomeValueTag or cls == CFG.RuntimeOutcomeValuePayloadI64
      or cls == CFG.RuntimeOutcomeErrorKind or cls == CFG.RuntimeOutcomeErrorValueTag
      or cls == CFG.RuntimeOutcomeErrorValuePayloadI64 or cls == CFG.RuntimeOutcomeSavedPc
      or cls == CFG.RuntimeOutcomeYieldKind then return "i64"
  elseif cls == CFG.RuntimePayloadF64 or cls == CFG.RuntimeOutcomeValuePayloadF64 then return "f64"
  elseif cls == CFG.RuntimeTruthiness or cls == CFG.RuntimeTypeTest or cls == CFG.RuntimeRawGetHit or cls == CFG.RuntimeTableRawSetCanWrite or cls == CFG.RuntimeTableWriteBarrierNeeded or cls == CFG.RuntimeArithmeticNumericOk then return "bool"
  elseif cls == CFG.ValueExpr then
    local v = e.value
    if class(v) == CFG.ConstValue then
      local ck = class(v.const)
      if ck == CFG.F64Const then return "f64" elseif ck == CFG.BoolConst then return "bool" else return "i64" end
    end
  elseif cls == CFG.Convert then return render_type(e.type) end
  return "i64"
end

local function render_op(op, indent)
  indent = indent or "    "
  local cls = class(op)
  if cls == CFG.Let then
    return indent .. "let " .. render_place(op.dst) .. ": " .. infer_expr_type(op.expr) .. " = " .. render_expr(op.expr)
  elseif cls == CFG.RuntimeStackStore then
    return indent .. render_value(op.stack) .. "[as(index, " .. render_value(op.index) .. ")] = " .. render_value(op.value)
  elseif cls == CFG.RuntimeTopStore then
    return indent .. render_value(op.top_ptr) .. "[as(index, 0)] = " .. render_value(op.top)
  elseif cls == CFG.RuntimeTableRawSet then
    local tables, tablev, key, value = render_value(op.tables), render_value(op.table_value), render_value(op.key), render_value(op.value)
    local tbl = tables .. "[as(index, " .. tablev .. ".payload_i64)]"
    local array_hit = par(tablev .. ".tag == " .. tag_lit("TableTag") .. " and " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " and " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " and " .. key .. ".payload_i64 <= " .. tbl .. ".array_len")
    local lines = {
      indent .. "if " .. array_hit .. " then",
      indent .. "    " .. tbl .. ".array[as(index, " .. key .. ".payload_i64 - " .. i64_lit(1) .. ")] = " .. value,
      indent .. "else",
      indent .. "    var hash_done: bool = false",
    }
    local hash_valid = par((render_hash_valid(tables, tablev):gsub("__KEY__", key)))
    for i = 0, ObjectModel.HASH_PROBE_LIMIT - 1 do
      local e = render_hash_entry(tables, tablev, i)
      local in_cap = par(hash_valid .. " and " .. tbl .. ".hash_capacity > " .. i64_lit(i))
      lines[#lines + 1] = indent .. "    if not hash_done and " .. in_cap .. " and " .. render_hash_match(e, key) .. " then"
      lines[#lines + 1] = indent .. "        " .. e .. ".value = " .. value
      lines[#lines + 1] = indent .. "        hash_done = true"
      lines[#lines + 1] = indent .. "    end"
    end
    for i = 0, ObjectModel.HASH_PROBE_LIMIT - 1 do
      local e = render_hash_entry(tables, tablev, i)
      local in_cap = par(hash_valid .. " and " .. tbl .. ".hash_capacity > " .. i64_lit(i))
      lines[#lines + 1] = indent .. "    if not hash_done and " .. in_cap .. " and " .. render_hash_insertable(e) .. " then"
      lines[#lines + 1] = indent .. "        " .. e .. ".state = " .. hash_state_lit("Occupied")
      lines[#lines + 1] = indent .. "        " .. e .. ".key = " .. key
      lines[#lines + 1] = indent .. "        " .. e .. ".value = " .. value
      lines[#lines + 1] = indent .. "        " .. tbl .. ".hash_count = " .. tbl .. ".hash_count + " .. i64_lit(1)
      lines[#lines + 1] = indent .. "        hash_done = true"
      lines[#lines + 1] = indent .. "    end"
    end
    lines[#lines + 1] = indent .. "end"
    return table.concat(lines, "\n")
  elseif cls == CFG.RuntimeTableWriteBarrier then
    local tables, tablev, value = render_value(op.tables), render_value(op.table_value), render_value(op.value)
    local tbl = tables .. "[as(index, " .. tablev .. ".payload_i64)]"
    local cond = render_table_barrier_needed(tables, tablev, value)
    return table.concat({
      indent .. "if " .. cond .. " then",
      indent .. "    " .. tbl .. ".barrier_count = " .. tbl .. ".barrier_count + " .. i64_lit(1),
      indent .. "    " .. tbl .. ".barrier_epoch = " .. tbl .. ".gc_epoch",
      indent .. "    " .. tbl .. ".barrier_last_child_tag = " .. value .. ".tag",
      indent .. "    " .. tbl .. ".barrier_last_child_payload = " .. value .. ".payload_i64",
      indent .. "end",
    }, "\n")
  elseif cls == CFG.Assign then
    return indent .. render_place(op.dst) .. " = " .. render_value(op.src)
  elseif cls == CFG.Store then
    return indent .. render_place(op.dst) .. " = " .. render_value(op.src)
  elseif cls == CFG.Assert then
    return indent .. "if not " .. render_expr(op.condition) .. " then return as(i64, 0) end"
  end
  error("unsupported MoonCFG.Op reached emission: " .. tostring(op and op.kind))
end

local function block_label(ref_or_id)
  local id = ref_or_id and ref_or_id.id or ref_or_id
  return render_name(id and id.name)
end

local function render_jump_args(args)
  local out = {}
  for _, a in ipairs(args or {}) do out[#out + 1] = render_name(a.name) .. " = " .. render_value(a.value) end
  return table.concat(out, ", ")
end

local function render_jump(ref, args)
  return "jump " .. block_label(ref) .. "(" .. render_jump_args(args) .. ")"
end

local function render_terminator(term, indent, mode)
  indent = indent or "    "
  mode = mode or "function"
  local cls = class(term)
  if cls == CFG.Return then
    local xs = {}
    for _, v in ipairs(term.values or {}) do xs[#xs + 1] = render_value(v) end
    if mode == "region" then
      if #xs == 0 then return indent .. "yield" end
      return indent .. "yield " .. table.concat(xs, ", ")
    end
    if #xs == 0 then return indent .. "return" end
    return indent .. "return " .. table.concat(xs, ", ")
  elseif cls == CFG.Jump then
    return indent .. render_jump(term.target, term.args)
  elseif cls == CFG.Branch then
    return table.concat({
      indent .. "if " .. render_choice(term.choice) .. " then " .. render_jump(term.if_true, {}) .. " end",
      indent .. render_jump(term.if_false, {}),
    }, "\n")
  elseif cls == CFG.BranchArgs then
    return table.concat({
      indent .. "if " .. render_choice(term.choice) .. " then " .. render_jump(term.if_true, term.true_args or {}) .. " end",
      indent .. render_jump(term.if_false, term.false_args or {}),
    }, "\n")
  elseif cls == CFG.Unreachable then
    if mode == "region" then return indent .. "yield " .. i64_lit(0) end
    return indent .. "return " .. i64_lit(0)
  end
  error("unsupported MoonCFG.Terminator reached emission: " .. tostring(term and term.kind))
end

local function render_returns(returns)
  local rs = returns or {}
  if #rs == 0 then return "void" end
  if #rs == 1 then return render_type(rs[1]) end
  local out = {}
  for _, r in ipairs(rs) do out[#out + 1] = render_type(r) end
  return table.concat(out, ", ")
end

local function index_blocks(region)
  local by_key, entry, others = {}, nil, {}
  local entry_key = region.entry and render_name(region.entry.name)
  for _, block in ipairs(region.blocks or {}) do
    local key = render_name(block.id and block.id.name)
    by_key[key] = block
    if key == entry_key then entry = block else others[#others + 1] = block end
  end
  return by_key, entry, others
end

local function render_block_params(params)
  local out = {}
  for _, p in ipairs(params or {}) do out[#out + 1] = render_param(p) end
  return table.concat(out, ", ")
end

local function render_entry_param_defaults(params)
  local out = {}
  for _, p in ipairs(params or {}) do
    local name = render_name(p.name)
    out[#out + 1] = name .. ": " .. render_type(p.type) .. " = " .. name
  end
  return table.concat(out, ", ")
end

local function render_region_block(block, is_entry, result_ty, entry_params)
  local lines = {}
  local header = is_entry and "    entry " or "    block "
  local params = is_entry and render_entry_param_defaults(entry_params or {}) or render_block_params(block.params or {})
  lines[#lines + 1] = header .. block_label(block.id) .. "(" .. params .. ")"
  for _, op in ipairs(block.ops or {}) do lines[#lines + 1] = render_op(op, "        ") end
  lines[#lines + 1] = render_terminator(block.terminator, "        ", "region", result_ty)
  lines[#lines + 1] = "    end"
  return lines
end

local function render_region_return(region, result_ty)
  local _by_key, entry, others = index_blocks(region)
  local lines = {}
  lines[#lines + 1] = "    return region -> " .. result_ty
  for _, line in ipairs(render_region_block(entry, true, result_ty, region.params or {})) do lines[#lines + 1] = line end
  for _, block in ipairs(others) do
    for _, line in ipairs(render_region_block(block, false, result_ty)) do lines[#lines + 1] = line end
  end
  lines[#lines + 1] = "    end"
  return lines
end

local function render_kernel(kernel, opts)
  local params = {}
  for _, p in ipairs(kernel.params or {}) do params[#params + 1] = render_param(p) end
  local name = opts.name or render_name(kernel.id and kernel.id.name) or "lua_compile_kernel"
  name = render_name(name)
  local lines = {}
  lines[#lines + 1] = ValueModel.TYPE_DECL
  lines[#lines + 1] = OutcomeModel.TYPE_DECL
  lines[#lines + 1] = StackModel.TYPE_DECL
  lines[#lines + 1] = ObjectModel.TYPE_DECL
  lines[#lines + 1] = ""
  local result_ty = render_returns(kernel.returns)
  lines[#lines + 1] = "local " .. name .. " = func(" .. table.concat(params, ", ") .. ") -> " .. result_ty
  local blocks = kernel.body and kernel.body.blocks or {}
  if #blocks == 1 then
    local block = blocks[1]
    for _, op in ipairs(block.ops or {}) do lines[#lines + 1] = render_op(op, "    ") end
    lines[#lines + 1] = render_terminator(block.terminator, "    ", "function", result_ty)
  else
    for _, line in ipairs(render_region_return(kernel.body, result_ty)) do lines[#lines + 1] = line end
  end
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "return " .. name
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function M.emit(kernel, opts)
  opts = opts or {}
  local ok, errors = Validate.validate(kernel)
  if not ok then error("MoonCFG validation failed before emission: " .. table.concat(errors, "; "), 2) end
  return render_kernel(kernel, opts)
end

return M
