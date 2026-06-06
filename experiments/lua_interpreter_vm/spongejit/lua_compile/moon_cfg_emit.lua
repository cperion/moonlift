-- moon_cfg_emit.lua -- mechanical MoonCFG -> Moonlift source renderer.
--
-- This renderer prints MoonCFG only.  It must not inspect source semantics to
-- choose semantics and must not synthesize out_tag/protocol continuations.

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

local function ptr_null(type_name)
  return "as(ptr(" .. type_name .. "), " .. i64_lit(0) .. ")"
end

local function ptr_not_null(expr, type_name)
  return par(expr .. " ~= " .. ptr_null(type_name))
end

local function lua_value_ptr_null()
  return ptr_null(ValueModel.TYPE_NAME)
end

local fresh_block_counter = 0
local function fresh_block_name(prefix)
  fresh_block_counter = fresh_block_counter + 1
  return render_name(prefix .. "_" .. tostring(fresh_block_counter))
end

local function raw_get_absent_value()
  return render_box("AbsentKeyTag", i64_lit(ValueModel.payload_for_nil_kind(B.T.LuaRT.AbsentKeySentinel)), f64_lit(0))
end

local function render_string_len(strings, value)
  local block = fresh_block_name("rt_string_len")
  local idx = block .. "_idx"
  return table.concat({
    "block " .. block .. "() -> i64",
    "    if " .. render_tag_any(value, { "ShortStringTag", "LongStringTag" }) .. " then",
    "        if " .. value .. ".payload_i64 < " .. i64_lit(0) .. " then yield " .. par(i64_lit(0) .. " - " .. value .. ".payload_i64") .. " end",
    "        let " .. idx .. ": index = as(index, " .. value .. ".payload_i64)",
    "        yield " .. strings .. "[" .. idx .. "].byte_len",
    "    end",
    "    yield " .. i64_lit(0),
    "end",
  }, "\n")
end

local function numeric_kind_lit(kind_name)
  return i64_lit(ObjectModel.string_numeric_kind_value(kind_name))
end

local function render_is_string(value)
  return render_tag_any(value, { "ShortStringTag", "LongStringTag" })
end

local function render_numeric_tag(value)
  return render_tag_any(value, { "IntegerTag", "FloatTag" })
end

local function render_numeric_kind_safe(strings, value)
  local block = fresh_block_name("rt_num_kind")
  local idx = block .. "_idx"
  local rec = strings .. "[" .. idx .. "]"
  return table.concat({
    "block " .. block .. "() -> i64",
    "    if " .. render_tag_compare(value, "IntegerTag") .. " then yield " .. i64_lit(1) .. " end",
    "    if " .. render_tag_compare(value, "FloatTag") .. " then yield " .. i64_lit(2) .. " end",
    "    if " .. render_is_string(value) .. " then",
    "        if " .. value .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    "            let " .. idx .. ": index = as(index, " .. value .. ".payload_i64)",
    "            if " .. rec .. ".numeric_kind == " .. numeric_kind_lit("DecimalInteger") .. " then yield " .. i64_lit(1) .. " end",
    "            if " .. rec .. ".numeric_kind == " .. numeric_kind_lit("DecimalFloat") .. " then yield " .. i64_lit(2) .. " end",
    "        end",
    "    end",
    "    yield " .. i64_lit(0),
    "end",
  }, "\n")
end

local function render_numeric_i64_safe(strings, value)
  local block = fresh_block_name("rt_num_i64")
  local idx = block .. "_idx"
  local rec = strings .. "[" .. idx .. "]"
  return table.concat({
    "block " .. block .. "() -> i64",
    "    if " .. render_tag_compare(value, "IntegerTag") .. " then yield " .. value .. ".payload_i64 end",
    "    if " .. render_is_string(value) .. " then",
    "        if " .. value .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    "            let " .. idx .. ": index = as(index, " .. value .. ".payload_i64)",
    "            if " .. rec .. ".numeric_kind == " .. numeric_kind_lit("DecimalInteger") .. " then yield " .. rec .. ".numeric_i64 end",
    "        end",
    "    end",
    "    yield " .. i64_lit(0),
    "end",
  }, "\n")
end

local function render_numeric_f64_safe(strings, value)
  local block = fresh_block_name("rt_num_f64")
  local idx = block .. "_idx"
  local rec = strings .. "[" .. idx .. "]"
  return table.concat({
    "block " .. block .. "() -> f64",
    "    if " .. render_tag_compare(value, "IntegerTag") .. " then yield as(f64, " .. value .. ".payload_i64) end",
    "    if " .. render_tag_compare(value, "FloatTag") .. " then yield " .. value .. ".payload_f64 end",
    "    if " .. render_is_string(value) .. " then",
    "        if " .. value .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    "            let " .. idx .. ": index = as(index, " .. value .. ".payload_i64)",
    "            if " .. rec .. ".numeric_kind == " .. numeric_kind_lit("DecimalInteger") .. " then yield as(f64, " .. rec .. ".numeric_i64) end",
    "            if " .. rec .. ".numeric_kind == " .. numeric_kind_lit("DecimalFloat") .. " then yield " .. rec .. ".numeric_f64 end",
    "        end",
    "    end",
    "    yield " .. f64_lit(0),
    "end",
  }, "\n")
end

local function render_arithmetic_numeric_ok(op, strings, left, right)
  local k = op and op.kind
  if k ~= "ArithAdd" then return "false" end
  local block = fresh_block_name("rt_arith_ok")
  local lk, rk = block .. "_lk", block .. "_rk"
  return table.concat({
    "block " .. block .. "() -> bool",
    "    let " .. lk .. ": i64 = " .. render_numeric_kind_safe(strings, left),
    "    if " .. lk .. " == " .. i64_lit(0) .. " then yield false end",
    "    let " .. rk .. ": i64 = " .. render_numeric_kind_safe(strings, right),
    "    if " .. rk .. " == " .. i64_lit(0) .. " then yield false end",
    "    yield true",
    "end",
  }, "\n")
end

local function render_arithmetic_error_value(op, _strings, left, right)
  local k = op and op.kind
  if k ~= "ArithAdd" then return left end
  local left_primitive_numeric = render_tag_any(left, { "IntegerTag", "FloatTag" })
  return ValueModel.TYPE_NAME .. "{ tag = select(" .. left_primitive_numeric .. ", " .. right .. ".tag, " .. left .. ".tag), payload_i64 = select(" .. left_primitive_numeric .. ", " .. right .. ".payload_i64, " .. left .. ".payload_i64), payload_f64 = select(" .. left_primitive_numeric .. ", " .. right .. ".payload_f64, " .. left .. ".payload_f64) }"
end

local function render_arithmetic_no_meta(op, strings, left, right)
  local k = op and op.kind
  if k ~= "ArithAdd" then return render_nil_value() end
  local lk = render_numeric_kind_safe(strings, left)
  local rk = render_numeric_kind_safe(strings, right)
  local numeric = par(lk .. " ~= " .. i64_lit(0) .. " and " .. rk .. " ~= " .. i64_lit(0))
  local both_int = par(lk .. " == " .. i64_lit(1) .. " and " .. rk .. " == " .. i64_lit(1))
  local int_sum = par(render_numeric_i64_safe(strings, left) .. " + " .. render_numeric_i64_safe(strings, right))
  local float_sum = par(render_numeric_f64_safe(strings, left) .. " + " .. render_numeric_f64_safe(strings, right))
  return ValueModel.TYPE_NAME .. "{ tag = select(" .. both_int .. ", " .. tag_lit("IntegerTag") .. ", select(" .. numeric .. ", " .. tag_lit("FloatTag") .. ", " .. tag_lit("NilTag") .. ")), payload_i64 = select(" .. both_int .. ", " .. int_sum .. ", " .. i64_lit(0) .. "), payload_f64 = select(" .. par(numeric .. " and not " .. both_int) .. ", " .. float_sum .. ", " .. f64_lit(0) .. ") }"
end

local function cdata_type_id_lit(type_id)
  return i64_lit(type_id and type_id.id or 0)
end

local function render_cdata_record(cdata_bank, idx)
  return cdata_bank .. "[" .. idx .. "]"
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
  local scalar_ok = width == info.width
  local aligned = info.align <= 1 or (off % info.align) == 0
  local block = fresh_block_name("rt_cdata_access_ok")
  local idx = block .. "_idx"
  local cd = render_cdata_record(cdata_bank, idx)
  return table.concat({
    "block " .. block .. "() -> bool",
    "    if " .. cdata_value .. ".tag == " .. tag_lit("CDataTag") .. " then",
    "        if " .. cdata_value .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    "            let " .. idx .. ": index = as(index, " .. cdata_value .. ".payload_i64)",
    "            if " .. cd .. ".type_id == " .. cdata_type_id_lit(type_id) .. " then",
    "                if " .. (scalar_ok and "true" or "false") .. " then",
    "                    if " .. (aligned and "true" or "false") .. " then",
    "                        if " .. i64_lit(off) .. " >= " .. i64_lit(0) .. " then",
    "                            if " .. i64_lit(off + width) .. " <= " .. cd .. ".size_bytes then yield true end",
    "                        end",
    "                    end",
    "                end",
    "            end",
    "        end",
    "    end",
    "    yield false",
    "end",
  }, "\n")
end

local function render_cdata_scalar_load(cdata_bank, cdata_value, scalar, type_id, offset_bytes, width_bytes)
  local info = cdata_scalar_info(scalar)
  local off = tonumber(offset_bytes) or 0
  local width = tonumber(width_bytes) or 0
  local scalar_ok = width == info.width
  local aligned = info.align <= 1 or (off % info.align) == 0
  local block = fresh_block_name("rt_cdata_load")
  local idx = block .. "_idx"
  local cd = render_cdata_record(cdata_bank, idx)
  local load
  if info.moon_type == "i32" then
    load = render_box("IntegerTag", "as(i64, " .. cd .. ".data_i32[as(index, " .. i64_lit(off / 4) .. ")])", f64_lit(0))
  elseif info.moon_type == "i64" then
    load = render_box("IntegerTag", cd .. ".data_i64[as(index, " .. i64_lit(off / 8) .. ")]", f64_lit(0))
  elseif info.moon_type == "f64" then
    load = render_box("FloatTag", i64_lit(0), cd .. ".data_f64[as(index, " .. i64_lit(off / 8) .. ")]" )
  else
    error("unsupported cdata scalar type reached emission: " .. tostring(info.moon_type))
  end
  return table.concat({
    "block " .. block .. "() -> " .. ValueModel.TYPE_NAME,
    "    if " .. cdata_value .. ".tag == " .. tag_lit("CDataTag") .. " then",
    "        if " .. cdata_value .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    "            let " .. idx .. ": index = as(index, " .. cdata_value .. ".payload_i64)",
    "            if " .. cd .. ".type_id == " .. cdata_type_id_lit(type_id) .. " then",
    "                if " .. (scalar_ok and "true" or "false") .. " then",
    "                    if " .. (aligned and "true" or "false") .. " then",
    "                        if " .. i64_lit(off) .. " >= " .. i64_lit(0) .. " then",
    "                            if " .. i64_lit(off + width) .. " <= " .. cd .. ".size_bytes then yield " .. load .. " end",
    "                        end",
    "                    end",
    "                end",
    "            end",
    "        end",
    "    end",
    "    yield " .. render_nil_value(),
    "end",
  }, "\n")
end

local function render_table_array_len(tables, value)
  local block = fresh_block_name("rt_table_array_len")
  local idx = block .. "_idx"
  local tbl = tables .. "[" .. idx .. "]"
  return table.concat({
    "block " .. block .. "() -> i64",
    "    if " .. render_tag_compare(value, "TableTag") .. " then",
    "        if " .. value .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    "            let " .. idx .. ": index = as(index, " .. value .. ".payload_i64)",
    "            yield " .. tbl .. ".array_len",
    "        end",
    "    end",
    "    yield " .. i64_lit(0),
    "end",
  }, "\n")
end

local function hash_state_lit(name)
  return i64_lit(ObjectModel.hash_entry_state_value(name))
end

local function render_is_hash_key(value)
  return par(render_tag_compare(value, "IntegerTag") .. " or " .. render_is_string(value))
end

local function render_hash_key_equal_fields(entry_tag, entry_payload, key)
  local entry_is_string = par(entry_tag .. " == " .. tag_lit("ShortStringTag") .. " or " .. entry_tag .. " == " .. tag_lit("LongStringTag"))
  local both_int = par(entry_tag .. " == " .. tag_lit("IntegerTag") .. " and " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " and " .. entry_payload .. " == " .. key .. ".payload_i64")
  local both_string = par(entry_is_string .. " and " .. render_is_string(key) .. " and " .. entry_payload .. " == " .. key .. ".payload_i64")
  return par(both_int .. " or " .. both_string)
end

local function render_collectable_value(value)
  return render_tag_any(value, { "ShortStringTag", "LongStringTag", "TableTag", "LuaClosureTag", "CClosureTag", "UserdataTag", "ThreadTag", "CDataTag" })
end

local function render_table_barrier_needed(tables, tablev, value)
  local block = fresh_block_name("rt_table_barrier_needed")
  local idx = block .. "_idx"
  local tbl = tables .. "[" .. idx .. "]"
  return table.concat({
    "block " .. block .. "() -> bool",
    "    if " .. render_tag_compare(tablev, "TableTag") .. " then",
    "        if " .. tablev .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    "            let " .. idx .. ": index = as(index, " .. tablev .. ".payload_i64)",
    "            if " .. tbl .. ".gc_color == " .. i64_lit(ObjectModel.gc_color_value("Black")) .. " then",
    "                if " .. tbl .. ".gc_generation == " .. i64_lit(ObjectModel.gc_generation_value("Old")) .. " then",
    "                    if " .. render_collectable_value(value) .. " then yield true end",
    "                end",
    "            end",
    "        end",
    "    end",
    "    yield false",
    "end",
  }, "\n")
end

local function render_raw_get_initial_value()
  return ObjectModel.RAW_GET_TYPE_NAME .. "{ hit = false, value = " .. raw_get_absent_value() .. " }"
end

local function render_raw_get(tables, tablev, key)
  return render_raw_get_initial_value()
end

local function render_raw_get_let(dst, tables, tablev, key, indent)
  local tbl_idx = dst .. "_table_index"
  local hptr = dst .. "_hash"
  local tbl = tables .. "[" .. tbl_idx .. "]"
  local lines = {
    indent .. "var " .. dst .. ": " .. ObjectModel.RAW_GET_TYPE_NAME .. " = " .. render_raw_get_initial_value(),
    indent .. "var " .. dst .. "_done: bool = false",
    indent .. "if " .. tablev .. ".tag == " .. tag_lit("TableTag") .. " then",
    indent .. "    if " .. tablev .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    indent .. "    let " .. tbl_idx .. ": index = as(index, " .. tablev .. ".payload_i64)",
    indent .. "    if " .. tbl .. ".metatable_kind == " .. i64_lit(ObjectModel.metatable_kind_value("NoMetatable")) .. " then",
    indent .. "    if " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " then",
    indent .. "        if " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " then",
    indent .. "            if " .. key .. ".payload_i64 <= " .. tbl .. ".array_len then",
    indent .. "                if " .. ptr_not_null(tbl .. ".array", ValueModel.TYPE_NAME) .. " then",
    indent .. "                    " .. dst .. ".hit = true",
    indent .. "                    " .. dst .. ".value = " .. tbl .. ".array[as(index, " .. key .. ".payload_i64 - " .. i64_lit(1) .. ")]",
    indent .. "                    " .. dst .. "_done = true",
    indent .. "                end",
    indent .. "            end",
    indent .. "        end",
    indent .. "    end",
    indent .. "    if not " .. dst .. "_done then",
    indent .. "        if " .. render_is_hash_key(key) .. " then",
    indent .. "            if " .. tbl .. ".hash_capacity > " .. i64_lit(0) .. " then",
    indent .. "                if " .. tbl .. ".hash_capacity <= " .. i64_lit(ObjectModel.HASH_PROBE_LIMIT) .. " then",
    indent .. "                    if " .. ptr_not_null(tbl .. ".hash", ObjectModel.HASH_ENTRY_TYPE_NAME) .. " then",
    indent .. "                        let " .. hptr .. ": ptr(" .. ObjectModel.HASH_ENTRY_TYPE_NAME .. ") = " .. tbl .. ".hash",
  }
  local loop = fresh_block_name(dst .. "_probe")
  local e = hptr .. "[as(index, " .. loop .. "_i)]"
  local prefix = loop .. "_entry"
  lines[#lines + 1] = indent .. "                        let " .. loop .. "_hit: bool = block " .. loop .. "(" .. loop .. "_i: i64 = " .. i64_lit(0) .. ") -> bool"
  lines[#lines + 1] = indent .. "                            if " .. dst .. "_done then yield true end"
  lines[#lines + 1] = indent .. "                            if " .. loop .. "_i >= " .. tbl .. ".hash_capacity then yield false end"
  lines[#lines + 1] = indent .. "                            let " .. prefix .. "_state: i64 = " .. e .. ".state"
  lines[#lines + 1] = indent .. "                            if " .. prefix .. "_state == " .. hash_state_lit("Occupied") .. " then"
  lines[#lines + 1] = indent .. "                                let " .. prefix .. "_key_tag: i64 = " .. e .. ".key.tag"
  lines[#lines + 1] = indent .. "                                let " .. prefix .. "_key_payload: i64 = " .. e .. ".key.payload_i64"
  lines[#lines + 1] = indent .. "                                if " .. render_hash_key_equal_fields(prefix .. "_key_tag", prefix .. "_key_payload", key) .. " then"
  lines[#lines + 1] = indent .. "                                    " .. dst .. ".hit = true"
  lines[#lines + 1] = indent .. "                                    " .. dst .. ".value = " .. e .. ".value"
  lines[#lines + 1] = indent .. "                                    " .. dst .. "_done = true"
  lines[#lines + 1] = indent .. "                                    yield true"
  lines[#lines + 1] = indent .. "                                end"
  lines[#lines + 1] = indent .. "                            end"
  lines[#lines + 1] = indent .. "                            jump " .. loop .. "(" .. loop .. "_i = " .. loop .. "_i + " .. i64_lit(1) .. ")"
  lines[#lines + 1] = indent .. "                        end"
  lines[#lines + 1] = indent .. "                        " .. dst .. "_done = " .. loop .. "_hit"
  lines[#lines + 1] = indent .. "                    end"
  lines[#lines + 1] = indent .. "                end"
  lines[#lines + 1] = indent .. "            end"
  lines[#lines + 1] = indent .. "        end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "        if not " .. dst .. "_done then"
  lines[#lines + 1] = indent .. "            " .. dst .. ".hit = true"
  lines[#lines + 1] = indent .. "            " .. dst .. ".value = " .. render_nil_value()
  lines[#lines + 1] = indent .. "        end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "end"
  return table.concat(lines, "\n")
end

local function render_table_raw_set_can_write(tables, tablev, key)
  return "false"
end

local function render_table_raw_set_can_write_let(dst, tables, tablev, key, indent)
  local tbl_idx = dst .. "_table_index"
  local tbl = tables .. "[" .. tbl_idx .. "]"
  local prefix_base = fresh_block_name("rt_raw_set_can_write")
  local hptr = prefix_base .. "_hash"
  local lines = {
    indent .. "var " .. dst .. ": bool = false",
    indent .. "if " .. tablev .. ".tag == " .. tag_lit("TableTag") .. " then",
    indent .. "    if " .. tablev .. ".payload_i64 >= " .. i64_lit(0) .. " then",
    indent .. "    let " .. tbl_idx .. ": index = as(index, " .. tablev .. ".payload_i64)",
    indent .. "    if " .. tbl .. ".metatable_kind == " .. i64_lit(ObjectModel.metatable_kind_value("NoMetatable")) .. " then",
    indent .. "    if " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " then",
    indent .. "        if " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " then",
    indent .. "            if " .. key .. ".payload_i64 <= " .. tbl .. ".array_len then",
    indent .. "                if " .. ptr_not_null(tbl .. ".array", ValueModel.TYPE_NAME) .. " then",
    indent .. "                    " .. dst .. " = true",
    indent .. "                end",
    indent .. "            end",
    indent .. "        end",
    indent .. "    end",
    indent .. "    if not " .. dst .. " then",
    indent .. "        if " .. render_is_hash_key(key) .. " then",
    indent .. "            if " .. tbl .. ".hash_capacity > " .. i64_lit(0) .. " then",
    indent .. "                if " .. tbl .. ".hash_capacity <= " .. i64_lit(ObjectModel.HASH_PROBE_LIMIT) .. " then",
    indent .. "                    if " .. ptr_not_null(tbl .. ".hash", ObjectModel.HASH_ENTRY_TYPE_NAME) .. " then",
    indent .. "                        let " .. hptr .. ": ptr(" .. ObjectModel.HASH_ENTRY_TYPE_NAME .. ") = " .. tbl .. ".hash",
  }
  local loop = fresh_block_name(prefix_base .. "_probe")
  local e = hptr .. "[as(index, " .. loop .. "_i)]"
  local prefix = loop .. "_entry"
  lines[#lines + 1] = indent .. "                        " .. dst .. " = block " .. loop .. "(" .. loop .. "_i: i64 = " .. i64_lit(0) .. ") -> bool"
  lines[#lines + 1] = indent .. "                            if " .. dst .. " then yield true end"
  lines[#lines + 1] = indent .. "                            if " .. loop .. "_i >= " .. tbl .. ".hash_capacity then yield false end"
  lines[#lines + 1] = indent .. "                            let " .. prefix .. "_state: i64 = " .. e .. ".state"
  lines[#lines + 1] = indent .. "                            if " .. prefix .. "_state == " .. hash_state_lit("Empty") .. " then"
  lines[#lines + 1] = indent .. "                                " .. dst .. " = true"
  lines[#lines + 1] = indent .. "                                yield true"
  lines[#lines + 1] = indent .. "                            end"
  lines[#lines + 1] = indent .. "                            if " .. prefix .. "_state == " .. hash_state_lit("Tombstone") .. " then"
  lines[#lines + 1] = indent .. "                                " .. dst .. " = true"
  lines[#lines + 1] = indent .. "                                yield true"
  lines[#lines + 1] = indent .. "                            end"
  lines[#lines + 1] = indent .. "                            if " .. prefix .. "_state == " .. hash_state_lit("Occupied") .. " then"
  lines[#lines + 1] = indent .. "                                let " .. prefix .. "_key_tag: i64 = " .. e .. ".key.tag"
  lines[#lines + 1] = indent .. "                                let " .. prefix .. "_key_payload: i64 = " .. e .. ".key.payload_i64"
  lines[#lines + 1] = indent .. "                                if " .. render_hash_key_equal_fields(prefix .. "_key_tag", prefix .. "_key_payload", key) .. " then"
  lines[#lines + 1] = indent .. "                                    " .. dst .. " = true"
  lines[#lines + 1] = indent .. "                                    yield true"
  lines[#lines + 1] = indent .. "                                end"
  lines[#lines + 1] = indent .. "                            end"
  lines[#lines + 1] = indent .. "                            jump " .. loop .. "(" .. loop .. "_i = " .. loop .. "_i + " .. i64_lit(1) .. ")"
  lines[#lines + 1] = indent .. "                        end"
  lines[#lines + 1] = indent .. "                    end"
  lines[#lines + 1] = indent .. "                end"
  lines[#lines + 1] = indent .. "            end"
  lines[#lines + 1] = indent .. "        end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "end"
  return table.concat(lines, "\n")
end

local function seq_field(seq_expr, index)
  return (tonumber(index) or 0) == 1 and seq_expr .. ".value1" or seq_expr .. ".value0"
end

local function seq_value_at_dynamic(seq_expr, index_expr)
  local block = fresh_block_name("rt_seq_value_at")
  return table.concat({
    "block " .. block .. "() -> " .. ValueModel.TYPE_NAME,
    "    if " .. index_expr .. " >= " .. seq_expr .. ".count then yield " .. render_nil_value() .. " end",
    "    if " .. index_expr .. " == " .. i64_lit(0) .. " then yield " .. seq_expr .. ".value0 end",
    "    if " .. index_expr .. " == " .. i64_lit(1) .. " then yield " .. seq_expr .. ".value1 end",
    "    if " .. ptr_not_null(seq_expr .. ".buffer", ValueModel.TYPE_NAME) .. " then",
    "        yield " .. seq_expr .. ".buffer[as(index, " .. seq_expr .. ".base + " .. index_expr .. ")]",
    "    end",
    "    yield " .. render_nil_value(),
    "end",
  }, "\n")
end

local function seq_value_at(seq_expr, index)
  index = tonumber(index) or 0
  if index == 0 then return "select(" .. seq_expr .. ".count >= " .. i64_lit(1) .. ", " .. seq_expr .. ".value0, " .. render_nil_value() .. ")" end
  if index == 1 then return "select(" .. seq_expr .. ".count >= " .. i64_lit(2) .. ", " .. seq_expr .. ".value1, " .. render_nil_value() .. ")" end
  return seq_value_at_dynamic(seq_expr, i64_lit(index))
end

local function buffer_value_at(buffer_expr, base_expr, count_expr, index)
  index = tonumber(index) or 0
  local idx = i64_lit(index)
  local block = fresh_block_name("rt_buffer_value_at")
  return table.concat({
    "block " .. block .. "() -> " .. ValueModel.TYPE_NAME,
    "    if " .. idx .. " >= " .. count_expr .. " then yield " .. render_nil_value() .. " end",
    "    if not " .. ptr_not_null(buffer_expr, ValueModel.TYPE_NAME) .. " then yield " .. render_nil_value() .. " end",
    "    yield " .. buffer_expr .. "[as(index, " .. base_expr .. " + " .. idx .. ")]",
    "end",
  }, "\n")
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

local function lua_count_value(count)
  if type(count) == "number" then return tonumber(count) or 0 end
  return tonumber(count and (count.value or count.count or count.n) or 0) or 0
end

local function slot_index(slot)
  return tonumber(slot and slot.index or 0) or 0
end

local function fixed_count_spec_value(count_spec)
  return lua_count_value(count_spec and count_spec.count)
end

local function adjustment_target_count(adjustment)
  local ak = adjustment and adjustment.kind
  if ak == "ExactCount" or ak == "FillNilTo" or ak == "TruncateTo" then return lua_count_value(adjustment.count) end
  return nil
end

local function render_outcome_index(outcome_expr, index, field)
  index = tonumber(index) or 0
  local idx = i64_lit(index)
  local block = fresh_block_name("rt_outcome_value_at")
  local value_expr = outcome_expr .. ".value0"
  if index == 1 then value_expr = outcome_expr .. ".value1"
  elseif index >= 2 then value_expr = outcome_expr .. ".value_buffer[as(index, " .. outcome_expr .. ".value_base + " .. idx .. ")]" end
  local fallback = field == "payload_f64" and f64_lit(0) or (field == "tag" and tag_lit("NilTag") or i64_lit(0))
  local lines = {
    "block " .. block .. "() -> " .. (field == "payload_f64" and "f64" or "i64"),
    "    if " .. idx .. " >= " .. outcome_expr .. ".count then yield " .. fallback .. " end",
  }
  if index >= 2 then lines[#lines + 1] = "    if not " .. ptr_not_null(outcome_expr .. ".value_buffer", ValueModel.TYPE_NAME) .. " then yield " .. fallback .. " end" end
  lines[#lines + 1] = "    yield " .. value_expr .. "." .. field
  lines[#lines + 1] = "end"
  return table.concat(lines, "\n")
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
        .. ", value_buffer = " .. lua_value_ptr_null()
        .. ", value_base = " .. i64_lit(0)
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
        .. ", value_buffer = " .. lua_value_ptr_null()
        .. ", value_base = " .. i64_lit(0)
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
        .. ", value_buffer = " .. lua_value_ptr_null()
        .. ", value_base = " .. i64_lit(0)
        .. ", error_kind = " .. i64_lit(0)
        .. ", error_value = " .. render_nil_value()
        .. ", saved_pc = " .. render_value(e.saved_pc)
        .. ", saved_top = " .. render_value(e.saved_top)
        .. ", yield_kind = " .. yield_kind_lit(e.resume_point) .. " }"
  elseif cls == CFG.RuntimeOutcomeReturnSeq then
    local seq = render_value(e.seq)
    return OutcomeModel.TYPE_NAME .. "{ kind = " .. outcome_kind_lit("NormalReturnOutcome")
        .. ", count = " .. seq .. ".count"
        .. ", value0 = " .. seq_value_at(seq, 0)
        .. ", value1 = " .. seq_value_at(seq, 1)
        .. ", value_buffer = " .. seq .. ".buffer"
        .. ", value_base = " .. seq .. ".base"
        .. ", error_kind = " .. i64_lit(0)
        .. ", error_value = " .. render_nil_value()
        .. ", saved_pc = " .. i64_lit(0)
        .. ", saved_top = " .. i64_lit(0)
        .. ", yield_kind = " .. i64_lit(0) .. " }"
  elseif cls == CFG.RuntimeOutcomeYieldSeq then
    local seq = render_value(e.seq)
    return OutcomeModel.TYPE_NAME .. "{ kind = " .. outcome_kind_lit("LuaYieldOutcome")
        .. ", count = " .. seq .. ".count"
        .. ", value0 = " .. seq_value_at(seq, 0)
        .. ", value1 = " .. seq_value_at(seq, 1)
        .. ", value_buffer = " .. seq .. ".buffer"
        .. ", value_base = " .. seq .. ".base"
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
      buffer_value_at(stack, base, count, 0),
      buffer_value_at(stack, base, count, 1),
      stack, base)
  elseif cls == CFG.RuntimeValueSeqFromVarargs then
    local src, count = render_value(e.varargs), render_value(e.count)
    return render_seq("VarargSeq", count,
      buffer_value_at(src .. ".values", i64_lit(0), count, 0),
      buffer_value_at(src .. ".values", i64_lit(0), count, 1),
      src .. ".values", i64_lit(0))
  elseif cls == CFG.RuntimeValueSeqAdjust then
    local seq = render_value(e.seq)
    local ak = e.adjustment and e.adjustment.kind
    local count = seq .. ".count"
    local target = adjustment_target_count(e.adjustment)
    if target ~= nil then count = i64_lit(target) end
    if ak ~= "ExactCount" and ak ~= "FillNilTo" and ak ~= "TruncateTo" and ak ~= "OpenResult" and ak ~= "PropagateOpenTail" then error("unsupported LuaRT.ResultAdjustment reached emission: " .. tostring(ak)) end
    return render_seq("AdjustedSeq", count, seq_value_at(seq, 0), seq_value_at(seq, 1), seq .. ".buffer", seq .. ".base")
  elseif cls == CFG.RuntimeValueSeqNormalize then
    local seq = render_value(e.seq)
    local ak = e.shape and e.shape.adjustment and e.shape.adjustment.kind
    local count = seq .. ".count"
    local target = adjustment_target_count(e.shape and e.shape.adjustment)
    if target ~= nil then count = i64_lit(target) end
    if ak ~= "ExactCount" and ak ~= "FillNilTo" and ak ~= "TruncateTo" and ak ~= "OpenResult" and ak ~= "PropagateOpenTail" then error("unsupported LuaRT.ArityNormalization reached emission: " .. tostring(ak)) end
    return render_seq("AdjustedSeq", count, seq_value_at(seq, 0), seq_value_at(seq, 1), seq .. ".buffer", seq .. ".base")
  elseif cls == CFG.RuntimeValueSeqCount then return render_value(e.seq) .. ".count"
  elseif cls == CFG.RuntimeValueSeqValue then return seq_value_at(render_value(e.seq), e.index)
  elseif cls == CFG.RuntimeValueSeqBuffer then return render_value(e.seq) .. ".buffer"
  elseif cls == CFG.RuntimeValueSeqBase then return render_value(e.seq) .. ".base"
  elseif cls == CFG.RuntimeClassifyCallee then
    local callee = render_value(e.callee)
    local block = fresh_block_name("rt_callee_kind")
    return table.concat({
      "block " .. block .. "() -> i64",
      "    if " .. callee .. ".tag == " .. tag_lit("LuaClosureTag") .. " then yield " .. i64_lit(1) .. " end",
      "    if " .. callee .. ".tag == " .. tag_lit("CClosureTag") .. " then yield " .. i64_lit(2) .. " end",
      "    if " .. callee .. ".tag == " .. tag_lit("LightCFunctionTag") .. " then yield " .. i64_lit(3) .. " end",
      "    yield " .. i64_lit(0),
      "end",
    }, "\n")
  elseif cls == CFG.RuntimeCallTargetCheck then
    local callee = render_value(e.callee)
    local identity = e.target and e.target.identity
    if class(identity) == RT.LuaClosureTargetIdentity then
      return par(render_tag_compare(callee, "LuaClosureTag") .. " and " .. callee .. ".payload_i64 == " .. i64_lit(identity.closure_handle))
    end
    return "false"
  elseif cls == CFG.RuntimeCallFramePrepare then
    local args = render_value(e.args)
    return CallModel.FRAME_TYPE_NAME .. "{ caller_stack = " .. render_value(e.caller_stack)
        .. ", callee_stack = " .. render_value(e.callee_stack)
        .. ", arg_base = " .. i64_lit(slot_index(e.layout and e.layout.arg_base))
        .. ", arg_count = " .. i64_lit(fixed_count_spec_value(e.layout and e.layout.arg_count))
        .. ", result_base = " .. i64_lit(slot_index(e.layout and e.layout.result_base))
        .. ", result_count = " .. i64_lit(fixed_count_spec_value(e.layout and e.layout.result_count))
        .. ", target_ok = " .. par(args .. ".count >= " .. i64_lit(0)) .. " }"
  elseif cls == CFG.RuntimeCallFrameResultSeq then
    local stack = render_value(e.callee_stack)
    local base = i64_lit(slot_index(e.layout and e.layout.result_base))
    local count = i64_lit(fixed_count_spec_value(e.layout and e.layout.result_count))
    return render_seq("CallResultSeq", count,
      buffer_value_at(stack, base, count, 0),
      buffer_value_at(stack, base, count, 1),
      stack, base)
  elseif cls == CFG.RuntimeVarargSource then
    return StackModel.VARARG_TYPE_NAME .. "{ kind = " .. vararg_kind_lit("HiddenFrameVarargs")
        .. ", values = " .. render_value(e.values)
        .. ", count = " .. render_value(e.count)
        .. ", table_handle = " .. render_value(e.table_handle) .. " }"
  elseif cls == CFG.RuntimeVarargCount then return render_value(e.source) .. ".count"
  elseif cls == CFG.RuntimeVarargGet then
    local src, key = render_value(e.source), render_value(e.key)
    local block = fresh_block_name("rt_vararg_get")
    local idx = block .. "_idx"
    return table.concat({
      "block " .. block .. "() -> " .. ValueModel.TYPE_NAME,
      "    if " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " then",
      "        if " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " then",
      "            if " .. key .. ".payload_i64 <= " .. src .. ".count then",
      "                let " .. idx .. ": index = as(index, " .. key .. ".payload_i64 - " .. i64_lit(1) .. ")",
      "                yield " .. src .. ".values[" .. idx .. "]",
      "            end",
      "        end",
      "    end",
      "    yield " .. render_nil_value(),
      "end",
    }, "\n")
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
    local block = fresh_block_name("rt_len_no_meta")
    local tidx = block .. "_table_idx"
    local tbl = tables .. "[" .. tidx .. "]"
    return table.concat({
      "block " .. block .. "() -> i64",
      "    if " .. render_is_string(v) .. " then",
      "        let " .. block .. "_string_len: i64 = " .. render_string_len(strings, v),
      "        yield " .. block .. "_string_len",
      "    end",
      "    if " .. render_tag_compare(v, "TableTag") .. " then",
      "        if " .. v .. ".payload_i64 >= " .. i64_lit(0) .. " then",
      "            let " .. tidx .. ": index = as(index, " .. v .. ".payload_i64)",
      "            if " .. tbl .. ".metatable_kind == " .. i64_lit(ObjectModel.metatable_kind_value("NoMetatable")) .. " then",
      "                yield " .. tbl .. ".array_len",
      "            end",
      "        end",
      "    end",
      "    yield " .. i64_lit(0),
      "end",
    }, "\n")
  elseif cls == CFG.RuntimeLenNoMetaOk then
    local v, tables = render_value(e.value), render_value(e.tables)
    local block = fresh_block_name("rt_len_no_meta_ok")
    local tidx = block .. "_table_idx"
    local tbl = tables .. "[" .. tidx .. "]"
    return table.concat({
      "block " .. block .. "() -> bool",
      "    if " .. render_is_string(v) .. " then yield true end",
      "    if " .. render_tag_compare(v, "TableTag") .. " then",
      "        if " .. v .. ".payload_i64 >= " .. i64_lit(0) .. " then",
      "            let " .. tidx .. ": index = as(index, " .. v .. ".payload_i64)",
      "            if " .. tbl .. ".metatable_kind == " .. i64_lit(ObjectModel.metatable_kind_value("NoMetatable")) .. " then yield true end",
      "        end",
      "    end",
      "    yield false",
      "end",
    }, "\n")
  elseif cls == CFG.RuntimeStringConcat2 then
    local left, right, strings = render_value(e.left), render_value(e.right), render_value(e.strings)
    local block = fresh_block_name("rt_concat2")
    local llen = block .. "_left_len"
    local rlen = block .. "_right_len"
    return table.concat({
      "block " .. block .. "() -> " .. ValueModel.TYPE_NAME,
      "    if not " .. render_is_string(left) .. " then yield " .. render_nil_value() .. " end",
      "    if not " .. render_is_string(right) .. " then yield " .. render_nil_value() .. " end",
      "    let " .. llen .. ": i64 = " .. render_string_len(strings, left),
      "    if " .. llen .. " < " .. i64_lit(0) .. " then yield " .. render_nil_value() .. " end",
      "    let " .. rlen .. ": i64 = " .. render_string_len(strings, right),
      "    if " .. rlen .. " < " .. i64_lit(0) .. " then yield " .. render_nil_value() .. " end",
      "    yield " .. render_box("ShortStringTag", par(i64_lit(0) .. " - " .. par(llen .. " + " .. rlen)), f64_lit(0)),
      "end",
    }, "\n")
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
  elseif cls == CFG.RuntimeOutcomeReturn or cls == CFG.RuntimeOutcomeReturnSeq or cls == CFG.RuntimeOutcomeError or cls == CFG.RuntimeOutcomeYield or cls == CFG.RuntimeOutcomeYieldSeq then return OutcomeModel.TYPE_NAME
  elseif cls == CFG.RuntimeValueSeqFixed or cls == CFG.RuntimeValueSeqFromStack or cls == CFG.RuntimeValueSeqFromVarargs or cls == CFG.RuntimeValueSeqAdjust or cls == CFG.RuntimeValueSeqNormalize or cls == CFG.RuntimeCallFrameResultSeq then return StackModel.SEQ_TYPE_NAME
  elseif cls == CFG.RuntimeCallFramePrepare then return CallModel.FRAME_TYPE_NAME
  elseif cls == CFG.RuntimeTableRawGet then return ObjectModel.RAW_GET_TYPE_NAME
  elseif cls == CFG.RuntimeVarargSource then return StackModel.VARARG_TYPE_NAME
  elseif cls == CFG.RuntimeValueSeqBuffer then return "ptr(" .. ValueModel.TYPE_NAME .. ")"
  elseif cls == CFG.RuntimeTag or cls == CFG.RuntimePayloadI64 or cls == CFG.RuntimeTopLoad or cls == CFG.RuntimeOpenCountFromTop or cls == CFG.RuntimeValueSeqCount or cls == CFG.RuntimeValueSeqBase or cls == CFG.RuntimeVarargCount or cls == CFG.RuntimeClassifyCallee
      or cls == CFG.RuntimeTableArrayLen or cls == CFG.RuntimeStringLen or cls == CFG.RuntimeLenNoMeta
      or cls == CFG.RuntimeOutcomeKind or cls == CFG.RuntimeOutcomeCount
      or cls == CFG.RuntimeOutcomeValueTag or cls == CFG.RuntimeOutcomeValuePayloadI64
      or cls == CFG.RuntimeOutcomeErrorKind or cls == CFG.RuntimeOutcomeErrorValueTag
      or cls == CFG.RuntimeOutcomeErrorValuePayloadI64 or cls == CFG.RuntimeOutcomeSavedPc
      or cls == CFG.RuntimeOutcomeYieldKind then return "i64"
  elseif cls == CFG.RuntimePayloadF64 or cls == CFG.RuntimeOutcomeValuePayloadF64 then return "f64"
  elseif cls == CFG.RuntimeTruthiness or cls == CFG.RuntimeTypeTest or cls == CFG.RuntimeRawGetHit or cls == CFG.RuntimeTableRawSetCanWrite or cls == CFG.RuntimeTableWriteBarrierNeeded or cls == CFG.RuntimeLenNoMetaOk or cls == CFG.RuntimeArithmeticNumericOk or cls == CFG.RuntimeCallTargetCheck then return "bool"
  elseif cls == CFG.ValueExpr then
    local v = e.value
    if class(v) == CFG.ConstValue then
      local ck = class(v.const)
      if ck == CFG.F64Const then return "f64" elseif ck == CFG.BoolConst then return "bool" else return "i64" end
    end
  elseif cls == CFG.Convert then return render_type(e.type) end
  return "i64"
end

local function append_assign_seq_value(lines, indent, dst, seq, idx)
  lines[#lines + 1] = indent .. dst .. " = " .. render_nil_value()
  lines[#lines + 1] = indent .. "if " .. idx .. " < " .. seq .. ".count then"
  lines[#lines + 1] = indent .. "    if " .. idx .. " == " .. i64_lit(0) .. " then " .. dst .. " = " .. seq .. ".value0 end"
  lines[#lines + 1] = indent .. "    if " .. idx .. " == " .. i64_lit(1) .. " then " .. dst .. " = " .. seq .. ".value1 end"
  lines[#lines + 1] = indent .. "    if " .. idx .. " >= " .. i64_lit(2) .. " then"
  lines[#lines + 1] = indent .. "        if " .. ptr_not_null(seq .. ".buffer", ValueModel.TYPE_NAME) .. " then " .. dst .. " = " .. seq .. ".buffer[as(index, " .. seq .. ".base + " .. idx .. ")] end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "end"
end

local function append_assign_buffer_value(lines, indent, dst, buffer, base, count, idx)
  lines[#lines + 1] = indent .. dst .. " = " .. render_nil_value()
  lines[#lines + 1] = indent .. "if " .. idx .. " < " .. count .. " then"
  lines[#lines + 1] = indent .. "    if " .. ptr_not_null(buffer, ValueModel.TYPE_NAME) .. " then " .. dst .. " = " .. buffer .. "[as(index, " .. base .. " + " .. idx .. ")] end"
  lines[#lines + 1] = indent .. "end"
end

local function render_seq_value_let(dst, e, indent)
  local seq = render_value(e.seq)
  local lines = { indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value() }
  append_assign_seq_value(lines, indent, dst, seq, i64_lit(e.index or 0))
  return table.concat(lines, "\n")
end

local function render_seq_let(dst, e, indent)
  local cls = class(e)
  local kind_name, count, v0, v1, buffer, base
  local pre_lines = {}
  if cls == CFG.RuntimeValueSeqFromStack then
    local stack = render_value(e.stack)
    local bname = dst .. "_buffer"
    pre_lines[#pre_lines + 1] = indent .. "let " .. bname .. ": ptr(" .. ValueModel.TYPE_NAME .. ") = " .. stack
    base = render_value(e.base)
    count = render_value(e.count)
    kind_name = "OpenSeq"
    buffer = bname
    v0 = buffer_value_at(buffer, base, count, 0)
    v1 = buffer_value_at(buffer, base, count, 1)
  elseif cls == CFG.RuntimeValueSeqFromVarargs then
    local src = render_value(e.varargs)
    local bname = dst .. "_buffer"
    pre_lines[#pre_lines + 1] = indent .. "let " .. bname .. ": ptr(" .. ValueModel.TYPE_NAME .. ") = " .. src .. ".values"
    count = render_value(e.count)
    kind_name = "VarargSeq"
    buffer = bname
    base = i64_lit(0)
    v0 = buffer_value_at(buffer, base, count, 0)
    v1 = buffer_value_at(buffer, base, count, 1)
  elseif cls == CFG.RuntimeCallFrameResultSeq then
    local stack = render_value(e.callee_stack)
    local bname = dst .. "_buffer"
    pre_lines[#pre_lines + 1] = indent .. "let " .. bname .. ": ptr(" .. ValueModel.TYPE_NAME .. ") = " .. stack
    base = i64_lit(slot_index(e.layout and e.layout.result_base))
    count = i64_lit(fixed_count_spec_value(e.layout and e.layout.result_count))
    kind_name = "CallResultSeq"
    buffer = bname
    v0 = buffer_value_at(buffer, base, count, 0)
    v1 = buffer_value_at(buffer, base, count, 1)
  elseif cls == CFG.RuntimeValueSeqAdjust or cls == CFG.RuntimeValueSeqNormalize then
    local seq = render_value(e.seq)
    local adjustment = cls == CFG.RuntimeValueSeqNormalize and e.shape and e.shape.adjustment or e.adjustment
    local ak = adjustment and adjustment.kind
    count = seq .. ".count"
    local target = adjustment_target_count(adjustment)
    if target ~= nil then count = i64_lit(target) end
    if ak ~= "ExactCount" and ak ~= "FillNilTo" and ak ~= "TruncateTo" and ak ~= "OpenResult" and ak ~= "PropagateOpenTail" then error("unsupported LuaRT arity adjustment reached emission: " .. tostring(ak)) end
    kind_name = "AdjustedSeq"
    buffer = seq .. ".buffer"
    base = seq .. ".base"
    v0 = seq_value_at(seq, 0)
    v1 = seq_value_at(seq, 1)
  else
    return nil
  end
  local lines = pre_lines
  lines[#lines + 1] = indent .. "var " .. dst .. ": " .. StackModel.SEQ_TYPE_NAME .. " = " .. render_seq(kind_name, count, nil, nil, buffer, base)
  if cls == CFG.RuntimeValueSeqFromStack or cls == CFG.RuntimeValueSeqFromVarargs or cls == CFG.RuntimeCallFrameResultSeq then
    append_assign_buffer_value(lines, indent, dst .. ".value0", buffer, base, count, i64_lit(0))
    append_assign_buffer_value(lines, indent, dst .. ".value1", buffer, base, count, i64_lit(1))
  else
    append_assign_seq_value(lines, indent, dst .. ".value0", render_value(e.seq), i64_lit(0))
    append_assign_seq_value(lines, indent, dst .. ".value1", render_value(e.seq), i64_lit(1))
  end
  return table.concat(lines, "\n")
end

local function render_outcome_seq_let(dst, e, indent)
  local seq = render_value(e.seq)
  local kind_name = class(e) == CFG.RuntimeOutcomeYieldSeq and "LuaYieldOutcome" or "NormalReturnOutcome"
  local lines = { indent .. "var " .. dst .. ": " .. OutcomeModel.TYPE_NAME .. " = " .. OutcomeModel.TYPE_NAME .. "{ kind = " .. outcome_kind_lit(kind_name)
      .. ", count = " .. seq .. ".count"
      .. ", value0 = " .. render_nil_value()
      .. ", value1 = " .. render_nil_value()
      .. ", value_buffer = " .. seq .. ".buffer"
      .. ", value_base = " .. seq .. ".base"
      .. ", error_kind = " .. i64_lit(0)
      .. ", error_value = " .. render_nil_value()
      .. ", saved_pc = " .. (class(e) == CFG.RuntimeOutcomeYieldSeq and render_value(e.saved_pc) or i64_lit(0))
      .. ", saved_top = " .. (class(e) == CFG.RuntimeOutcomeYieldSeq and render_value(e.saved_top) or i64_lit(0))
      .. ", yield_kind = " .. (class(e) == CFG.RuntimeOutcomeYieldSeq and yield_kind_lit(e.resume_point) or i64_lit(0)) .. " }" }
  append_assign_seq_value(lines, indent, dst .. ".value0", seq, i64_lit(0))
  append_assign_seq_value(lines, indent, dst .. ".value1", seq, i64_lit(1))
  return table.concat(lines, "\n")
end

local function emit_number_coerce_assign(lines, indent, dst, strings, value)
  local idx = dst .. "_string_idx"
  local rec = strings .. "[" .. idx .. "]"
  lines[#lines + 1] = indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value()
  lines[#lines + 1] = indent .. "if " .. render_tag_compare(value, "IntegerTag") .. " then"
  lines[#lines + 1] = indent .. "    " .. dst .. ".tag = " .. value .. ".tag"
  lines[#lines + 1] = indent .. "    " .. dst .. ".payload_i64 = " .. value .. ".payload_i64"
  lines[#lines + 1] = indent .. "    " .. dst .. ".payload_f64 = " .. value .. ".payload_f64"
  lines[#lines + 1] = indent .. "end"
  lines[#lines + 1] = indent .. "if " .. render_tag_compare(value, "FloatTag") .. " then"
  lines[#lines + 1] = indent .. "    " .. dst .. ".tag = " .. value .. ".tag"
  lines[#lines + 1] = indent .. "    " .. dst .. ".payload_i64 = " .. value .. ".payload_i64"
  lines[#lines + 1] = indent .. "    " .. dst .. ".payload_f64 = " .. value .. ".payload_f64"
  lines[#lines + 1] = indent .. "end"
  lines[#lines + 1] = indent .. "if " .. render_tag_compare(dst, "NilTag") .. " then"
  lines[#lines + 1] = indent .. "    if " .. render_is_string(value) .. " then"
  lines[#lines + 1] = indent .. "        if " .. value .. ".payload_i64 >= " .. i64_lit(0) .. " then"
  lines[#lines + 1] = indent .. "            let " .. idx .. ": index = as(index, " .. value .. ".payload_i64)"
  lines[#lines + 1] = indent .. "            if " .. rec .. ".numeric_kind == " .. numeric_kind_lit("DecimalInteger") .. " then"
  lines[#lines + 1] = indent .. "                " .. dst .. ".tag = " .. tag_lit("IntegerTag")
  lines[#lines + 1] = indent .. "                " .. dst .. ".payload_i64 = " .. rec .. ".numeric_i64"
  lines[#lines + 1] = indent .. "                " .. dst .. ".payload_f64 = " .. f64_lit(0)
  lines[#lines + 1] = indent .. "            end"
  lines[#lines + 1] = indent .. "            if " .. rec .. ".numeric_kind == " .. numeric_kind_lit("DecimalFloat") .. " then"
  lines[#lines + 1] = indent .. "                " .. dst .. ".tag = " .. tag_lit("FloatTag")
  lines[#lines + 1] = indent .. "                " .. dst .. ".payload_i64 = " .. i64_lit(0)
  lines[#lines + 1] = indent .. "                " .. dst .. ".payload_f64 = " .. rec .. ".numeric_f64"
  lines[#lines + 1] = indent .. "            end"
  lines[#lines + 1] = indent .. "        end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "end"
end

local function render_box_let(dst, tag_name, payload_i64, payload_f64, indent)
  return table.concat({
    indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value(),
    indent .. dst .. ".tag = " .. tag_lit(tag_name),
    indent .. dst .. ".payload_i64 = " .. (payload_i64 or i64_lit(0)),
    indent .. dst .. ".payload_f64 = " .. (payload_f64 or f64_lit(0)),
  }, "\n")
end

local function render_concat2_let(dst, strings, left, right, indent)
  local llen, rlen = dst .. "_left_len", dst .. "_right_len"
  local lines = { indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value() }
  lines[#lines + 1] = indent .. "if " .. render_is_string(left) .. " then"
  lines[#lines + 1] = indent .. "    if " .. render_is_string(right) .. " then"
  lines[#lines + 1] = indent .. "        let " .. llen .. ": i64 = " .. render_string_len(strings, left)
  lines[#lines + 1] = indent .. "        if " .. llen .. " >= " .. i64_lit(0) .. " then"
  lines[#lines + 1] = indent .. "            let " .. rlen .. ": i64 = " .. render_string_len(strings, right)
  lines[#lines + 1] = indent .. "            if " .. rlen .. " >= " .. i64_lit(0) .. " then"
  lines[#lines + 1] = indent .. "                " .. dst .. ".tag = " .. tag_lit("ShortStringTag")
  lines[#lines + 1] = indent .. "                " .. dst .. ".payload_i64 = " .. par(i64_lit(0) .. " - " .. par(llen .. " + " .. rlen))
  lines[#lines + 1] = indent .. "                " .. dst .. ".payload_f64 = " .. f64_lit(0)
  lines[#lines + 1] = indent .. "            end"
  lines[#lines + 1] = indent .. "        end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "end"
  return table.concat(lines, "\n")
end

local function render_vararg_get_let(dst, src, key, indent)
  local idx = dst .. "_idx"
  local elem = src .. ".values[" .. idx .. "]"
  return table.concat({
    indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value(),
    indent .. "if " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " then",
    indent .. "    if " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " then",
    indent .. "        if " .. key .. ".payload_i64 <= " .. src .. ".count then",
    indent .. "            let " .. idx .. ": index = as(index, " .. key .. ".payload_i64 - " .. i64_lit(1) .. ")",
    indent .. "            " .. dst .. ".tag = " .. elem .. ".tag",
    indent .. "            " .. dst .. ".payload_i64 = " .. elem .. ".payload_i64",
    indent .. "            " .. dst .. ".payload_f64 = " .. elem .. ".payload_f64",
    indent .. "        end",
    indent .. "    end",
    indent .. "end",
  }, "\n")
end

local function render_arithmetic_numeric_ok_let(dst, op, strings, left, right, indent)
  local lines = { indent .. "var " .. dst .. ": bool = false" }
  if op and op.kind == "ArithAdd" then
    local lnum, rnum = dst .. "_left_num", dst .. "_right_num"
    emit_number_coerce_assign(lines, indent, lnum, strings, left)
    lines[#lines + 1] = indent .. "if " .. render_numeric_tag(lnum) .. " then"
    emit_number_coerce_assign(lines, indent .. "    ", rnum, strings, right)
    lines[#lines + 1] = indent .. "    if " .. render_numeric_tag(rnum) .. " then"
    lines[#lines + 1] = indent .. "        " .. dst .. " = true"
    lines[#lines + 1] = indent .. "    end"
    lines[#lines + 1] = indent .. "end"
  end
  return table.concat(lines, "\n")
end

local function render_arithmetic_no_meta_let(dst, op, strings, left, right, indent)
  local lines = {}
  if not (op and op.kind == "ArithAdd") then return indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value() end
  local lnum, rnum = dst .. "_left_num", dst .. "_right_num"
  lines[#lines + 1] = indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value()
  emit_number_coerce_assign(lines, indent, lnum, strings, left)
  lines[#lines + 1] = indent .. "if " .. render_numeric_tag(lnum) .. " then"
  emit_number_coerce_assign(lines, indent .. "    ", rnum, strings, right)
  lines[#lines + 1] = indent .. "    if " .. render_numeric_tag(rnum) .. " then"
  lines[#lines + 1] = indent .. "        if " .. par(render_tag_compare(lnum, "IntegerTag") .. " and " .. render_tag_compare(rnum, "IntegerTag")) .. " then"
  lines[#lines + 1] = indent .. "            " .. dst .. ".tag = " .. tag_lit("IntegerTag")
  lines[#lines + 1] = indent .. "            " .. dst .. ".payload_i64 = " .. par(lnum .. ".payload_i64 + " .. rnum .. ".payload_i64")
  lines[#lines + 1] = indent .. "            " .. dst .. ".payload_f64 = " .. f64_lit(0)
  lines[#lines + 1] = indent .. "        end"
  lines[#lines + 1] = indent .. "        if not " .. par(render_tag_compare(lnum, "IntegerTag") .. " and " .. render_tag_compare(rnum, "IntegerTag")) .. " then"
  lines[#lines + 1] = indent .. "            let " .. dst .. "_lf: f64 = block " .. dst .. "_left_f64() -> f64"
  lines[#lines + 1] = indent .. "                if " .. render_tag_compare(lnum, "IntegerTag") .. " then yield as(f64, " .. lnum .. ".payload_i64) end"
  lines[#lines + 1] = indent .. "                yield " .. lnum .. ".payload_f64"
  lines[#lines + 1] = indent .. "            end"
  lines[#lines + 1] = indent .. "            let " .. dst .. "_rf: f64 = block " .. dst .. "_right_f64() -> f64"
  lines[#lines + 1] = indent .. "                if " .. render_tag_compare(rnum, "IntegerTag") .. " then yield as(f64, " .. rnum .. ".payload_i64) end"
  lines[#lines + 1] = indent .. "                yield " .. rnum .. ".payload_f64"
  lines[#lines + 1] = indent .. "            end"
  lines[#lines + 1] = indent .. "            " .. dst .. ".tag = " .. tag_lit("FloatTag")
  lines[#lines + 1] = indent .. "            " .. dst .. ".payload_i64 = " .. i64_lit(0)
  lines[#lines + 1] = indent .. "            " .. dst .. ".payload_f64 = " .. par(dst .. "_lf + " .. dst .. "_rf")
  lines[#lines + 1] = indent .. "        end"
  lines[#lines + 1] = indent .. "    end"
  lines[#lines + 1] = indent .. "end"
  return table.concat(lines, "\n")
end

local function render_arithmetic_error_value_let(dst, op, strings, left, right, indent)
  local lines = { indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. left }
  if op and op.kind == "ArithAdd" then
    local lnum = dst .. "_left_num"
    emit_number_coerce_assign(lines, indent, lnum, strings, left)
    lines[#lines + 1] = indent .. "if " .. render_numeric_tag(lnum) .. " then"
    lines[#lines + 1] = indent .. "    " .. dst .. ".tag = " .. right .. ".tag"
    lines[#lines + 1] = indent .. "    " .. dst .. ".payload_i64 = " .. right .. ".payload_i64"
    lines[#lines + 1] = indent .. "    " .. dst .. ".payload_f64 = " .. right .. ".payload_f64"
    lines[#lines + 1] = indent .. "end"
  end
  return table.concat(lines, "\n")
end

local function render_op(op, indent)
  indent = indent or "    "
  local cls = class(op)
  if cls == CFG.Let then
    if class(op.expr) == CFG.RuntimeBoxNil then
      return render_box_let(render_place(op.dst), ValueModel.tag_name_for_nil_kind(op.expr.kind), render_nil_kind_payload(op.expr.kind), f64_lit(0), indent)
    end
    if class(op.expr) == CFG.RuntimeBoxI64 then
      return render_box_let(render_place(op.dst), "IntegerTag", render_value(op.expr.value), f64_lit(0), indent)
    end
    if class(op.expr) == CFG.RuntimeBoxF64 then
      return render_box_let(render_place(op.dst), "FloatTag", i64_lit(0), render_value(op.expr.value), indent)
    end
    if class(op.expr) == CFG.RuntimeBoxRef then
      return render_box_let(render_place(op.dst), tag_name_from_runtime_tag(op.expr.tag), render_value(op.expr.handle), f64_lit(0), indent)
    end
    if class(op.expr) == CFG.RuntimeBoxBool then
      local dst, b = render_place(op.dst), render_value(op.expr.value)
      return table.concat({
        indent .. "var " .. dst .. ": " .. ValueModel.TYPE_NAME .. " = " .. render_nil_value(),
        indent .. "if " .. b .. " then",
        indent .. "    " .. dst .. ".tag = " .. tag_lit("TrueTag"),
        indent .. "    " .. dst .. ".payload_i64 = " .. i64_lit(1),
        indent .. "end",
        indent .. "if not " .. b .. " then",
        indent .. "    " .. dst .. ".tag = " .. tag_lit("FalseTag"),
        indent .. "    " .. dst .. ".payload_i64 = " .. i64_lit(0),
        indent .. "end",
      }, "\n")
    end
    if class(op.expr) == CFG.RuntimeValueSeqFromStack or class(op.expr) == CFG.RuntimeValueSeqFromVarargs or class(op.expr) == CFG.RuntimeCallFrameResultSeq or class(op.expr) == CFG.RuntimeValueSeqAdjust or class(op.expr) == CFG.RuntimeValueSeqNormalize then
      return render_seq_let(render_place(op.dst), op.expr, indent)
    end
    if class(op.expr) == CFG.RuntimeValueSeqValue then
      return render_seq_value_let(render_place(op.dst), op.expr, indent)
    end
    if class(op.expr) == CFG.RuntimeOutcomeReturnSeq or class(op.expr) == CFG.RuntimeOutcomeYieldSeq then
      return render_outcome_seq_let(render_place(op.dst), op.expr, indent)
    end
    if class(op.expr) == CFG.RuntimeOutcomeReturn or class(op.expr) == CFG.RuntimeOutcomeError or class(op.expr) == CFG.RuntimeOutcomeYield then
      return indent .. "var " .. render_place(op.dst) .. ": " .. OutcomeModel.TYPE_NAME .. " = " .. render_expr(op.expr)
    end
    if class(op.expr) == CFG.RuntimeTableRawGet then
      return render_raw_get_let(render_place(op.dst), render_value(op.expr.tables), render_value(op.expr.table_value), render_value(op.expr.key), indent)
    end
    if class(op.expr) == CFG.RuntimeTableRawSetCanWrite then
      return render_table_raw_set_can_write_let(render_place(op.dst), render_value(op.expr.tables), render_value(op.expr.table_value), render_value(op.expr.key), indent)
    end
    if class(op.expr) == CFG.RuntimeStringConcat2 then
      return render_concat2_let(render_place(op.dst), render_value(op.expr.strings), render_value(op.expr.left), render_value(op.expr.right), indent)
    end
    if class(op.expr) == CFG.RuntimeVarargGet then
      return render_vararg_get_let(render_place(op.dst), render_value(op.expr.source), render_value(op.expr.key), indent)
    end
    return indent .. "let " .. render_place(op.dst) .. ": " .. infer_expr_type(op.expr) .. " = " .. render_expr(op.expr)
  elseif cls == CFG.RuntimeStackStore then
    return indent .. render_value(op.stack) .. "[as(index, " .. render_value(op.index) .. ")] = " .. render_value(op.value)
  elseif cls == CFG.RuntimeValueSeqStore then
    local stack, base, seq = render_value(op.stack), render_value(op.base), render_value(op.seq)
    local loop = fresh_block_name("rt_seq_store")
    local i = loop .. "_i"
    local count, buffer, seq_base, stack_local = loop .. "_count", loop .. "_buffer", loop .. "_base", loop .. "_stack"
    local lines = {
      indent .. "let " .. stack_local .. ": ptr(" .. ValueModel.TYPE_NAME .. ") = " .. stack,
      indent .. "let " .. count .. ": i64 = " .. seq .. ".count",
      indent .. "if " .. count .. " >= " .. i64_lit(1) .. " then " .. stack_local .. "[as(index, " .. base .. ")] = " .. seq .. ".value0 end",
      indent .. "if " .. count .. " >= " .. i64_lit(2) .. " then " .. stack_local .. "[as(index, " .. base .. " + " .. i64_lit(1) .. ")] = " .. seq .. ".value1 end",
      indent .. "let " .. buffer .. ": ptr(" .. ValueModel.TYPE_NAME .. ") = " .. seq .. ".buffer",
      indent .. "let " .. seq_base .. ": i64 = " .. seq .. ".base",
      indent .. "let " .. loop .. "_done: i64 = block " .. loop .. "(" .. i .. ": i64 = " .. i64_lit(2) .. ") -> i64",
      indent .. "    if " .. i .. " >= " .. count .. " then yield " .. i .. " end",
      indent .. "    if " .. ptr_not_null(buffer, ValueModel.TYPE_NAME) .. " then " .. stack_local .. "[as(index, " .. base .. " + " .. i .. ")] = " .. buffer .. "[as(index, " .. seq_base .. " + " .. i .. ")] end",
      indent .. "    jump " .. loop .. "(" .. i .. " = " .. i .. " + " .. i64_lit(1) .. ")",
      indent .. "end",
    }
    return table.concat(lines, "\n")
  elseif cls == CFG.RuntimeCallFrameStoreArgs then
    local stack, seq = render_value(op.callee_stack), render_value(op.args)
    local base = i64_lit(slot_index(op.layout and op.layout.arg_base))
    local loop = fresh_block_name("rt_arg_store")
    local i = loop .. "_i"
    local count, buffer, seq_base, stack_local = loop .. "_count", loop .. "_buffer", loop .. "_base", loop .. "_stack"
    local lines = {
      indent .. "let " .. stack_local .. ": ptr(" .. ValueModel.TYPE_NAME .. ") = " .. stack,
      indent .. "let " .. count .. ": i64 = " .. seq .. ".count",
      indent .. "if " .. count .. " >= " .. i64_lit(1) .. " then " .. stack_local .. "[as(index, " .. base .. ")] = " .. seq .. ".value0 end",
      indent .. "if " .. count .. " >= " .. i64_lit(2) .. " then " .. stack_local .. "[as(index, " .. base .. " + " .. i64_lit(1) .. ")] = " .. seq .. ".value1 end",
      indent .. "let " .. buffer .. ": ptr(" .. ValueModel.TYPE_NAME .. ") = " .. seq .. ".buffer",
      indent .. "let " .. seq_base .. ": i64 = " .. seq .. ".base",
      indent .. "let " .. loop .. "_done: i64 = block " .. loop .. "(" .. i .. ": i64 = " .. i64_lit(2) .. ") -> i64",
      indent .. "    if " .. i .. " >= " .. count .. " then yield " .. i .. " end",
      indent .. "    if " .. ptr_not_null(buffer, ValueModel.TYPE_NAME) .. " then " .. stack_local .. "[as(index, " .. base .. " + " .. i .. ")] = " .. buffer .. "[as(index, " .. seq_base .. " + " .. i .. ")] end",
      indent .. "    jump " .. loop .. "(" .. i .. " = " .. i .. " + " .. i64_lit(1) .. ")",
      indent .. "end",
    }
    return table.concat(lines, "\n")
  elseif cls == CFG.RuntimeTopStore then
    return indent .. render_value(op.top_ptr) .. "[as(index, 0)] = " .. render_value(op.top)
  elseif cls == CFG.RuntimeTableRawSet then
    local tables, tablev, key, value = render_value(op.tables), render_value(op.table_value), render_value(op.key), render_value(op.value)
    local set_prefix = fresh_block_name("rt_raw_set")
    local tbl_idx = set_prefix .. "_table_index"
    local hptr = set_prefix .. "_hash"
    local tbl = tables .. "[" .. tbl_idx .. "]"
    local lines = {
      indent .. "if " .. tablev .. ".tag == " .. tag_lit("TableTag") .. " then",
      indent .. "    if " .. tablev .. ".payload_i64 >= " .. i64_lit(0) .. " then",
      indent .. "    let " .. tbl_idx .. ": index = as(index, " .. tablev .. ".payload_i64)",
      indent .. "    var array_slot: bool = false",
      indent .. "    if " .. key .. ".tag == " .. tag_lit("IntegerTag") .. " then",
      indent .. "        if " .. key .. ".payload_i64 >= " .. i64_lit(1) .. " then",
      indent .. "            if " .. key .. ".payload_i64 <= " .. tbl .. ".array_len then",
      indent .. "                array_slot = true",
      indent .. "                if " .. ptr_not_null(tbl .. ".array", ValueModel.TYPE_NAME) .. " then",
      indent .. "                    " .. tbl .. ".array[as(index, " .. key .. ".payload_i64 - " .. i64_lit(1) .. ")] = " .. value,
      indent .. "                end",
      indent .. "            end",
      indent .. "        end",
      indent .. "    end",
      indent .. "    if not array_slot then",
      indent .. "        if " .. render_is_hash_key(key) .. " then",
      indent .. "            if " .. tbl .. ".hash_capacity > " .. i64_lit(0) .. " then",
      indent .. "                if " .. tbl .. ".hash_capacity <= " .. i64_lit(ObjectModel.HASH_PROBE_LIMIT) .. " then",
      indent .. "                    if " .. ptr_not_null(tbl .. ".hash", ObjectModel.HASH_ENTRY_TYPE_NAME) .. " then",
      indent .. "                        let " .. hptr .. ": ptr(" .. ObjectModel.HASH_ENTRY_TYPE_NAME .. ") = " .. tbl .. ".hash",
      indent .. "                        var hash_done: bool = false",
    }
    local update_loop = fresh_block_name(set_prefix .. "_update")
    local update_e = hptr .. "[as(index, " .. update_loop .. "_i)]"
    local update_prefix = update_loop .. "_entry"
    lines[#lines + 1] = indent .. "                        hash_done = block " .. update_loop .. "(" .. update_loop .. "_i: i64 = " .. i64_lit(0) .. ") -> bool"
    lines[#lines + 1] = indent .. "                            if hash_done then yield true end"
    lines[#lines + 1] = indent .. "                            if " .. update_loop .. "_i >= " .. tbl .. ".hash_capacity then yield false end"
    lines[#lines + 1] = indent .. "                            let " .. update_prefix .. "_state: i64 = " .. update_e .. ".state"
    lines[#lines + 1] = indent .. "                            if " .. update_prefix .. "_state == " .. hash_state_lit("Occupied") .. " then"
    lines[#lines + 1] = indent .. "                                let " .. update_prefix .. "_key_tag: i64 = " .. update_e .. ".key.tag"
    lines[#lines + 1] = indent .. "                                let " .. update_prefix .. "_key_payload: i64 = " .. update_e .. ".key.payload_i64"
    lines[#lines + 1] = indent .. "                                if " .. render_hash_key_equal_fields(update_prefix .. "_key_tag", update_prefix .. "_key_payload", key) .. " then"
    lines[#lines + 1] = indent .. "                                    " .. update_e .. ".value = " .. value
    lines[#lines + 1] = indent .. "                                    hash_done = true"
    lines[#lines + 1] = indent .. "                                    yield true"
    lines[#lines + 1] = indent .. "                                end"
    lines[#lines + 1] = indent .. "                            end"
    lines[#lines + 1] = indent .. "                            jump " .. update_loop .. "(" .. update_loop .. "_i = " .. update_loop .. "_i + " .. i64_lit(1) .. ")"
    lines[#lines + 1] = indent .. "                        end"
    local insert_loop = fresh_block_name(set_prefix .. "_insert")
    local insert_e = hptr .. "[as(index, " .. insert_loop .. "_i)]"
    local insert_prefix = insert_loop .. "_entry"
    lines[#lines + 1] = indent .. "                        if not hash_done then"
    lines[#lines + 1] = indent .. "                            hash_done = block " .. insert_loop .. "(" .. insert_loop .. "_i: i64 = " .. i64_lit(0) .. ") -> bool"
    lines[#lines + 1] = indent .. "                                if hash_done then yield true end"
    lines[#lines + 1] = indent .. "                                if " .. insert_loop .. "_i >= " .. tbl .. ".hash_capacity then yield false end"
    lines[#lines + 1] = indent .. "                                let " .. insert_prefix .. "_state: i64 = " .. insert_e .. ".state"
    lines[#lines + 1] = indent .. "                                if " .. par(insert_prefix .. "_state == " .. hash_state_lit("Empty") .. " or " .. insert_prefix .. "_state == " .. hash_state_lit("Tombstone")) .. " then"
    lines[#lines + 1] = indent .. "                                    " .. insert_e .. ".state = " .. hash_state_lit("Occupied")
    lines[#lines + 1] = indent .. "                                    " .. insert_e .. ".key = " .. key
    lines[#lines + 1] = indent .. "                                    " .. insert_e .. ".value = " .. value
    lines[#lines + 1] = indent .. "                                    " .. tbl .. ".hash_count = " .. tbl .. ".hash_count + " .. i64_lit(1)
    lines[#lines + 1] = indent .. "                                    hash_done = true"
    lines[#lines + 1] = indent .. "                                    yield true"
    lines[#lines + 1] = indent .. "                                end"
    lines[#lines + 1] = indent .. "                                jump " .. insert_loop .. "(" .. insert_loop .. "_i = " .. insert_loop .. "_i + " .. i64_lit(1) .. ")"
    lines[#lines + 1] = indent .. "                            end"
    lines[#lines + 1] = indent .. "                        end"
    lines[#lines + 1] = indent .. "                    end"
    lines[#lines + 1] = indent .. "                end"
    lines[#lines + 1] = indent .. "            end"
    lines[#lines + 1] = indent .. "        end"
    lines[#lines + 1] = indent .. "    end"
    lines[#lines + 1] = indent .. "    end"
    lines[#lines + 1] = indent .. "end"
    return table.concat(lines, "\n")
  elseif cls == CFG.RuntimeTableWriteBarrier then
    local tables, tablev, value = render_value(op.tables), render_value(op.table_value), render_value(op.value)
    local idx = fresh_block_name("rt_barrier_table_index")
    local tbl = tables .. "[" .. idx .. "]"
    local cond = render_table_barrier_needed(tables, tablev, value)
    return table.concat({
      indent .. "if " .. cond .. " then",
      indent .. "    if " .. render_tag_compare(tablev, "TableTag") .. " then",
      indent .. "        if " .. tablev .. ".payload_i64 >= " .. i64_lit(0) .. " then",
      indent .. "            let " .. idx .. ": index = as(index, " .. tablev .. ".payload_i64)",
      indent .. "            " .. tbl .. ".barrier_count = " .. tbl .. ".barrier_count + " .. i64_lit(1),
      indent .. "            " .. tbl .. ".barrier_epoch = " .. tbl .. ".gc_epoch",
      indent .. "            " .. tbl .. ".barrier_last_child_tag = " .. value .. ".tag",
      indent .. "            " .. tbl .. ".barrier_last_child_payload = " .. value .. ".payload_i64",
      indent .. "        end",
      indent .. "    end",
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
  fresh_block_counter = 0
  local params = {}
  for _, p in ipairs(kernel.params or {}) do params[#params + 1] = render_param(p) end
  local name = opts.name or render_name(kernel.id and kernel.id.name) or "lua_compile_kernel"
  name = render_name(name)
  local lines = {}
  lines[#lines + 1] = ValueModel.TYPE_DECL
  lines[#lines + 1] = OutcomeModel.TYPE_DECL
  lines[#lines + 1] = StackModel.TYPE_DECL
  lines[#lines + 1] = CallModel.TYPE_DECL
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
