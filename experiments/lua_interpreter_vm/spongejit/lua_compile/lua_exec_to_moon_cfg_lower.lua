-- lua_exec_to_moon_cfg_lower.lua -- mechanical LuaExec semantic CFG -> MoonCFG.
--
-- This pass consumes LuaExec/LuaRT semantic ASDL only.  It never inspects
-- LuaSrc opcodes and never emits protocol exits or helper handoffs. LuaRT
-- values lower to the explicit LuaRTValue runtime substrate (tag + payload
-- fields) before any tag, truthiness, or payload projection is emitted.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local RT, Exec, CFG, LC = T.LuaRT, T.LuaExec, T.MoonCFG, T.LuaContract
local ExecValidate = require("lua_compile.lua_exec_validate")
local ValueModel = require("lua_compile.lua_rt_value_model")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local StackModel = require("lua_compile.lua_rt_stack_model")
local ObjectModel = require("lua_compile.lua_rt_object_model")

local M = {}

local function cname(s) return CFG.Name(tostring(s)) end
local function type_ref(s) return CFG.TypeRef(tostring(s)) end
local function kid(s) return CFG.KernelId(cname(s)) end
local function rid(s) return CFG.RegionId(cname(s)) end
local function bid_from_exec(id) return CFG.BlockId(cname(id.name.text)) end
local function bref_from_exec(ref) return CFG.BlockRef(bid_from_exec(ref.id)) end
local function empty_contract() return LC.Contract(LC.Transfer({}, {}), {}, {}) end
local function cfg_arg_from_exec(arg, value) return CFG.Arg(cname(arg.name.text), value) end
local function key_value_ref(v)
  local cls = pvm.classof(v)
  if cls == RT.StackValue then return "stack:" .. tostring(v.frame.name.text) .. ":" .. tostring(v.slot.index) end
  if cls == RT.VarargValue then return "vararg:" .. tostring(v.vararg.frame.name.text) .. ":" .. tostring(v.index.value) end
  if cls == RT.TempValue then return "temp:" .. tostring(v.name.text) end
  if cls == RT.ConstValue then return "const:" .. tostring(v.const.index) end
  return tostring(cls) .. ":" .. tostring(v)
end
local function key_top_ref(top) return "top:" .. tostring(top and top.frame and top.frame.name and top.frame.name.text or "frame0") end
local function key_stack_ref(stack) return "stackref:" .. tostring(stack and stack.frame and stack.frame.name and stack.frame.name.text or "frame0") end
local function key_vararg_source(source)
  local cls = pvm.classof(source)
  if cls == RT.HiddenFrameVarargs then return "hidden_varargs:" .. tostring(source.frame.name.text) end
  if cls == RT.VarargTableSource then return "vararg_table:" .. tostring(source.table.name.text) end
  if cls == RT.NoVarargs then return "no_varargs" end
  return tostring(cls) .. ":" .. tostring(source)
end
local function bool_const(b) return CFG.ConstValue(CFG.BoolConst(b == true)) end
local function i64_const(n) return CFG.ConstValue(CFG.I64Const(tonumber(n) or 0)) end
local function f64_const(n) return CFG.ConstValue(CFG.F64Const(tonumber(n) or 0)) end

local function add_error(state, msg) state.errors[#state.errors + 1] = msg; return nil end
local function copy_map(m)
  local out = {}
  for k, v in pairs(m or {}) do
    local c = {}; for kk, vv in pairs(v) do c[kk] = vv end
    out[k] = c
  end
  return out
end

local function tag_name(tag)
  return tag and tag.kind
end
local function is_bool_tag(tag)
  local k = tag_name(tag)
  return k == "FalseTag" or k == "TrueTag"
end
local function type_info(exec_type)
  local cls = pvm.classof(exec_type)
  if cls == Exec.MoonType then return exec_type.moon_type, { ty = exec_type.moon_type } end
  if exec_type == Exec.LuaValueType or (exec_type and exec_type.kind == "LuaValueType") then return ValueModel.TYPE_NAME, { ty = "lua_value" } end
  if exec_type == Exec.LuaValueSeqType or (exec_type and exec_type.kind == "LuaValueSeqType") then return StackModel.SEQ_TYPE_NAME, { ty = "lua_seq" } end
  if exec_type == Exec.LuaBoolType or (exec_type and exec_type.kind == "LuaBoolType") then return "bool", { ty = "bool" } end
  if exec_type == Exec.LuaNumberType or (exec_type and exec_type.kind == "LuaNumberType") then return "i64", { ty = "i64" } end
  if exec_type == Exec.LuaTableType or (exec_type and exec_type.kind == "LuaTableType") then return ValueModel.TYPE_NAME, { ty = "lua_value", tag = RT.TableTag } end
  if exec_type == Exec.LuaStringType or (exec_type and exec_type.kind == "LuaStringType") then return ValueModel.TYPE_NAME, { ty = "lua_value", type_test = RT.IsString } end
  if Exec.LuaValueWithTagType and cls == Exec.LuaValueWithTagType then
    return ValueModel.TYPE_NAME, { ty = "lua_value", tag = exec_type.tag }
  end
  if Exec.LuaValueWithTypeTestType and cls == Exec.LuaValueWithTypeTestType then
    return ValueModel.TYPE_NAME, { ty = "lua_value", type_test = exec_type.test }
  end
  return "i64", { ty = "i64" }
end
local function param_ty(p) local ty = type_info(p.type); return ty end
local function param_meta(p) local _moon, meta = type_info(p.type); return meta end
local function cfg_param(p) return CFG.Param(cname(p.name.text), type_ref(param_ty(p)), CFG.ValueParam) end

local function entry(value, ty, opts)
  opts = opts or {}
  opts.value = value
  opts.ty = ty
  return opts
end
local function emit_expr(state, prefix, expr, ty, opts)
  local place = CFG.Temp(cname((prefix or "tmp") .. tostring(state.temp_id)))
  state.temp_id = state.temp_id + 1
  state.current_ops[#state.current_ops + 1] = CFG.Let(place, expr)
  return entry(CFG.PlaceValue(place), ty, opts)
end
local function emit_runtime_expr(state, prefix, expr, opts)
  return emit_expr(state, prefix or "rtv", expr, "lua_value", opts)
end
local function emit_outcome_expr(state, prefix, expr, opts)
  return emit_expr(state, prefix or "outcome", expr, "lua_outcome", opts)
end
local function runtime_nil(state)
  return emit_runtime_expr(state, "out_nil", CFG.RuntimeBoxNil(RT.OrdinaryNil), { tag = RT.NilTag })
end

local function frame_from_value_ref(ref)
  local cls = pvm.classof(ref)
  if cls == RT.StackValue then return ref.frame end
  return nil
end

local function param_entry(env, name)
  local v = env.params[name]
  return v and v.value and v or nil
end

local function stack_param_name(frame) return tostring(frame and frame.name and frame.name.text or "frame0") .. "_stack" end
local function top_param_name(frame) return tostring(frame and frame.name and frame.name.text or "frame0") .. "_top" end
local function top_ptr_param_name(frame) return tostring(frame and frame.name and frame.name.text or "frame0") .. "_top_ptr" end
local function vararg_values_param_name(frame) return tostring(frame and frame.name and frame.name.text or "frame0") .. "_varargs" end
local function vararg_count_param_name(frame) return tostring(frame and frame.name and frame.name.text or "frame0") .. "_vararg_count" end
local function tables_param_name(frame) return tostring(frame and frame.name and frame.name.text or "frame0") .. "_tables" end
local function strings_param_name(frame) return tostring(frame and frame.name and frame.name.text or "frame0") .. "_strings" end

local function stack_value_for_ref(state, env, stack)
  local key = key_stack_ref(stack)
  if env.stacks[key] then return env.stacks[key] end
  local p = param_entry(env, stack_param_name(stack and stack.frame))
  if not p then return add_error(state, "missing_stack_parameter:" .. stack_param_name(stack and stack.frame)) end
  env.stacks[key] = entry(p.value, "ptr_lua_value")
  return env.stacks[key]
end

local function tables_value_for_frame(state, env, frame)
  local name = tables_param_name(frame)
  local p = param_entry(env, name)
  if not p then return add_error(state, "missing_tables_parameter:" .. name) end
  return p
end

local function strings_value_for_frame(state, env, frame)
  local name = strings_param_name(frame)
  local p = param_entry(env, name)
  if not p then return add_error(state, "missing_strings_parameter:" .. name) end
  return p
end

local function top_value_for_ref(state, env, top)
  local key = key_top_ref(top)
  if env.tops[key] then return env.tops[key] end
  local p = param_entry(env, top_param_name(top and top.frame))
  if p then env.tops[key] = entry(p.value, "i64"); return env.tops[key] end
  local pp = param_entry(env, top_ptr_param_name(top and top.frame))
  if pp then env.tops[key] = emit_expr(state, "top_load", CFG.RuntimeTopLoad(pp.value), "i64"); return env.tops[key] end
  return add_error(state, "missing_top_parameter_or_pointer:" .. top_param_name(top and top.frame))
end

local function set_top_value(state, env, top, value)
  local key = key_top_ref(top)
  env.tops[key] = value
  local pp = param_entry(env, top_ptr_param_name(top and top.frame))
  if pp then state.current_ops[#state.current_ops + 1] = CFG.RuntimeTopStore(pp.value, value.value) end
  return true
end

local function runtime_const_from_tvalue(tv, state)
  local cls = pvm.classof(tv)
  if cls == RT.NilValue then
    local tag = RT[ValueModel.tag_name_for_nil_kind(tv.kind)]
    return emit_runtime_expr(state, "nil", CFG.RuntimeBoxNil(tv.kind), { tag = tag })
  elseif cls == RT.BoolValue then
    local is_true = tv.kind == RT.LuaTrue or (tv.kind and tv.kind.kind == "LuaTrue")
    return emit_runtime_expr(state, is_true and "true" or "false", CFG.RuntimeBoxBool(bool_const(is_true)), { tag = is_true and RT.TrueTag or RT.FalseTag, type_test = RT.IsBoolean })
  elseif cls == RT.IntValue then
    return emit_runtime_expr(state, "i64v", CFG.RuntimeBoxI64(i64_const(tv.value)), { tag = RT.IntegerTag })
  elseif cls == RT.FloatValue then
    return emit_runtime_expr(state, "f64v", CFG.RuntimeBoxF64(f64_const(tv.value)), { tag = RT.FloatTag })
  elseif cls == RT.StringValue then
    local tag = (tv.kind == RT.LongString or (tv.kind and tv.kind.kind == "LongString")) and RT.LongStringTag or RT.ShortStringTag
    return emit_runtime_expr(state, "strv", CFG.RuntimeBoxRef(tag, i64_const(0)), { tag = tag })
  elseif cls == RT.TableValueNode then return emit_runtime_expr(state, "tablev", CFG.RuntimeBoxRef(RT.TableTag, i64_const(0)), { tag = RT.TableTag })
  elseif cls == RT.LuaClosureValue then return emit_runtime_expr(state, "luaclosurev", CFG.RuntimeBoxRef(RT.LuaClosureTag, i64_const(0)), { tag = RT.LuaClosureTag })
  elseif cls == RT.CClosureValue then return emit_runtime_expr(state, "cclosurev", CFG.RuntimeBoxRef(RT.CClosureTag, i64_const(0)), { tag = RT.CClosureTag })
  elseif cls == RT.LightCFunctionValue then return emit_runtime_expr(state, "lightcfv", CFG.RuntimeBoxRef(RT.LightCFunctionTag, i64_const(0)), { tag = RT.LightCFunctionTag })
  elseif cls == RT.UserdataValueNode then return emit_runtime_expr(state, "userdatav", CFG.RuntimeBoxRef(RT.UserdataTag, i64_const(0)), { tag = RT.UserdataTag })
  elseif cls == RT.LightUserdataValue then return emit_runtime_expr(state, "lightudv", CFG.RuntimeBoxRef(RT.LightUserdataTag, i64_const(0)), { tag = RT.LightUserdataTag })
  elseif cls == RT.ThreadValueNode then return emit_runtime_expr(state, "threadv", CFG.RuntimeBoxRef(RT.ThreadTag, i64_const(0)), { tag = RT.ThreadTag })
  elseif RT.CDataValueNode and cls == RT.CDataValueNode then return emit_runtime_expr(state, "cdatav", CFG.RuntimeBoxRef(RT.CDataTag, i64_const(0)), { tag = RT.CDataTag }) end
  return add_error(state, "unsupported_tvalue:" .. tostring(tv and tv.kind))
end

local function box_scalar(state, e)
  if e.ty == "lua_value" then return e end
  if e.ty == "i64" then return emit_runtime_expr(state, "box_i64", CFG.RuntimeBoxI64(e.value), { tag = RT.IntegerTag }) end
  if e.ty == "f64" then return emit_runtime_expr(state, "box_f64", CFG.RuntimeBoxF64(e.value), { tag = RT.FloatTag }) end
  if e.ty == "bool" then return emit_runtime_expr(state, "box_bool", CFG.RuntimeBoxBool(e.value), { type_test = RT.IsBoolean }) end
  if e.ty == "nil" then return emit_runtime_expr(state, "box_nil", CFG.RuntimeBoxNil(RT.OrdinaryNil), { tag = RT.NilTag }) end
  return add_error(state, "cannot_box_scalar_type:" .. tostring(e.ty))
end

local function resolve_exec_value(state, env, value)
  local cls = pvm.classof(value)
  if cls == Exec.ConstTValue then return runtime_const_from_tvalue(value.value, state) end
  if cls == Exec.TempValue then
    local name = value.name.text
    local v = env.temps[name] or env.params[name]
    if not v then return add_error(state, "unbound_temp_value:" .. tostring(name)) end
    return v
  end
  if cls == Exec.RuntimeValue then
    local key = key_value_ref(value.value)
    local v = env.values[key]
    if not v then return add_error(state, "unbound_runtime_value:" .. tostring(key)) end
    return v
  end
  if cls == Exec.RuntimeSeq then return lower_value_seq_runtime(state, env, value.seq, "runtime_value") end
  if cls == Exec.UnitValue then return entry(CFG.UnitValue, "void") end
  return add_error(state, "unsupported_exec_value:" .. tostring(value and value.kind))
end

local function runtime_truthiness(state, e)
  local rv = box_scalar(state, e)
  if not rv then return nil end
  return emit_expr(state, "truthy", CFG.RuntimeTruthiness(rv.value), "bool")
end

local function truthiness_of_ref(state, env, ref)
  local key = key_value_ref(ref)
  local v = env.values[key]
  if not v then return add_error(state, "unbound_truthiness_value:" .. tostring(key)) end
  return runtime_truthiness(state, v)
end

local function ensure_i64_payload(state, e, label)
  if e.ty == "i64" then return e end
  if e.ty ~= "lua_value" then return add_error(state, "i64_payload_requires_lua_value_or_i64:" .. tostring(label) .. ":" .. tostring(e.ty)) end
  if tag_name(e.tag) ~= "IntegerTag" then return add_error(state, "i64_payload_requires_integer_tag:" .. tostring(label) .. ":" .. tostring(tag_name(e.tag))) end
  return emit_expr(state, "unbox_i64", CFG.RuntimePayloadI64(e.value), "i64")
end

local function bool_payload(state, e, label)
  if e.ty == "bool" then return e end
  if e.ty ~= "lua_value" then return add_error(state, "bool_payload_requires_lua_value_or_bool:" .. tostring(label) .. ":" .. tostring(e.ty)) end
  local boolish = is_bool_tag(e.tag) or (e.type_test and e.type_test.kind == "IsBoolean")
  if not boolish then return add_error(state, "bool_payload_requires_boolean_proof:" .. tostring(label) .. ":" .. tostring(tag_name(e.tag)) .. ":" .. tostring(e.type_test and e.type_test.kind)) end
  local payload = emit_expr(state, "unbox_bool_payload", CFG.RuntimePayloadI64(e.value), "i64")
  return emit_expr(state, "unbox_bool", CFG.Primitive(CFG.Eq, { payload.value, i64_const(1) }), "bool")
end

local lower_count_spec
local lower_value_seq_runtime
local lower_vararg_source_runtime
local fixed_count_value

local function count_from_lua_count(count)
  return tonumber(count and (count.value or count.count) or 0) or 0
end

function lower_count_spec(state, env, count, window_base)
  local cls = pvm.classof(count)
  if cls == RT.FixedCount then return entry(i64_const(count_from_lua_count(count)), "i64") end
  if cls == RT.OpenFromTop then
    local top = top_value_for_ref(state, env, count.top); if not top then return nil end
    if window_base then return emit_expr(state, "open_count", CFG.RuntimeOpenCountFromTop(top.value, i64_const(window_base)), "i64") end
    return top
  end
  if cls == RT.OpenFromVarargs then
    local src = lower_vararg_source_runtime(state, env, count.source); if not src then return nil end
    return emit_expr(state, "vararg_count", CFG.RuntimeVarargCount(src.value), "i64")
  end
  if cls == RT.OpenFromVarargsAtBase then
    local src = lower_vararg_source_runtime(state, env, count.source); if not src then return nil end
    local n = emit_expr(state, "vararg_count", CFG.RuntimeVarargCount(src.value), "i64")
    return emit_expr(state, "top_from_vararg", CFG.Primitive(CFG.AddI64, { i64_const(count.base and count.base.index or 0), n.value }), "i64")
  end
  if cls == RT.DynamicCount then return add_error(state, "unsupported_dynamic_count_until_count_values_are_executable") end
  if cls == RT.UnknownCount then return add_error(state, "unsupported_unknown_count:" .. tostring(count.reason)) end
  return add_error(state, "unsupported_count_spec:" .. tostring(count and count.kind))
end

function lower_vararg_source_runtime(state, env, source)
  local key = key_vararg_source(source)
  if env.varargs[key] then return env.varargs[key] end
  local cls = pvm.classof(source)
  if cls == RT.HiddenFrameVarargs then
    local values = param_entry(env, vararg_values_param_name(source.frame))
    local count = param_entry(env, vararg_count_param_name(source.frame))
    if not values then return add_error(state, "missing_vararg_values_parameter:" .. vararg_values_param_name(source.frame)) end
    if not count then return add_error(state, "missing_vararg_count_parameter:" .. vararg_count_param_name(source.frame)) end
    local src = emit_expr(state, "vararg_src", CFG.RuntimeVarargSource(values.value, count.value, i64_const(0)), "lua_varargs")
    env.varargs[key] = src
    return src
  elseif cls == RT.VarargTableSource then
    return add_error(state, "vararg_table_source_placeholder_not_executable_until_table_model")
  elseif cls == RT.NoVarargs then
    return add_error(state, "no_varargs_source_has_no_executable_values")
  end
  return add_error(state, "unsupported_vararg_source:" .. tostring(source and source.kind))
end

function lower_value_seq_runtime(state, env, seq, label)
  label = label or "seq"
  if fixed_count_value(seq) ~= nil and #((seq and seq.values) or {}) > 0 then
    local count = lower_count_spec(state, env, seq.count); if not count then return nil end
    local values = {}
    for _, ref in ipairs(seq.values or {}) do
      local v = env.values[key_value_ref(ref)]
      if not v then break end
      local boxed = box_scalar(state, v); if not boxed then return nil end
      values[#values + 1] = boxed.value
    end
    if #values == #((seq and seq.values) or {}) then
      return emit_expr(state, label .. "_fixed_seq", CFG.RuntimeValueSeqFixed(count.value, values), "lua_seq")
    end
  end
  local origin_cls = pvm.classof(seq and seq.origin)
  local origin_kind = seq and seq.origin and seq.origin.kind
  if origin_cls == RT.FromStackWindow then
    local w = seq.origin.window
    local stack = stack_value_for_ref(state, env, RT.StackRef(w.frame)); if not stack then return nil end
    local count = lower_count_spec(state, env, w.count, w.base and w.base.index); if not count then return nil end
    return emit_expr(state, label .. "_stack_seq", CFG.RuntimeValueSeqFromStack(stack.value, i64_const(w.base and w.base.index or 0), count.value), "lua_seq")
  elseif origin_cls == RT.FromVarargs then
    local src = lower_vararg_source_runtime(state, env, seq.origin.source); if not src then return nil end
    local count = lower_count_spec(state, env, seq.count); if not count then return nil end
    return emit_expr(state, label .. "_vararg_seq", CFG.RuntimeValueSeqFromVarargs(src.value, count.value), "lua_seq")
  elseif origin_cls == RT.FromLiteralValues or origin_kind == "FromLiteralValues" then
    local count = lower_count_spec(state, env, seq.count); if not count then return nil end
    local values = {}
    for _, ref in ipairs(seq.values or {}) do
      local v = env.values[key_value_ref(ref)]
      if not v then return add_error(state, label .. ":unbound_seq_value:" .. key_value_ref(ref)) end
      local boxed = box_scalar(state, v); if not boxed then return nil end
      values[#values + 1] = boxed.value
    end
    return emit_expr(state, label .. "_fixed_seq", CFG.RuntimeValueSeqFixed(count.value, values), "lua_seq")
  elseif origin_cls == RT.FromAdjusted then
    local src = lower_value_seq_runtime(state, env, seq.origin.source, label .. "_adjust_src"); if not src then return nil end
    return emit_expr(state, label .. "_adjusted_seq", CFG.RuntimeValueSeqAdjust(src.value, RT.PropagateOpenTail), "lua_seq")
  end
  return add_error(state, label .. ":unsupported_sequence_origin:" .. tostring(seq and seq.origin and seq.origin.kind))
end

local NUMERIC_TEST = { Eq = CFG.NumEq, Lt = CFG.NumLt, Le = CFG.NumLe, Gt = CFG.NumGt, Ge = CFG.NumGe, NonZero = CFG.NumNonZero }
local function lower_expr(state, env, expr)
  local cls = pvm.classof(expr)
  if cls == Exec.ValueExpr then return resolve_exec_value(state, env, expr.value) end
  if cls == Exec.TruthinessExpr then return truthiness_of_ref(state, env, expr.value) end
  if cls == Exec.NotTruthinessExpr then
    local v = truthiness_of_ref(state, env, expr.value)
    if not v then return nil end
    return emit_expr(state, "not_exec", CFG.Primitive(CFG.Not, { v.value }), "bool")
  end
  if cls == Exec.TypeTestExpr then
    local v = env.values[key_value_ref(expr.value)]
    if not v then return add_error(state, "unbound_type_test_value:" .. key_value_ref(expr.value)) end
    return emit_expr(state, "typetest", CFG.RuntimeTypeTest(v.value, expr.test), "bool")
  end
  if cls == Exec.ProjectExpr then
    local v = env.values[key_value_ref(expr.value)]
    if not v then return add_error(state, "unbound_project_value:" .. key_value_ref(expr.value)) end
    local pk = expr.projection and expr.projection.kind
    if pk == "ProjectTag" then return emit_expr(state, "project_tag", CFG.RuntimeTag(v.value), "i64") end
    if pk == "ProjectPayloadBits" or pk == "ProjectInteger" or pk == "ProjectBool" then return emit_expr(state, "project_payload", CFG.RuntimePayloadI64(v.value), "i64") end
    if pk == "ProjectFloat" then return emit_expr(state, "project_f64", CFG.RuntimePayloadF64(v.value), "f64") end
    return add_error(state, "unsupported_lua_rt_projection:" .. tostring(pk))
  end
  if cls == Exec.StackLoadExpr then
    local stack = stack_value_for_ref(state, env, expr.stack); if not stack then return nil end
    return emit_runtime_expr(state, "stack_load", CFG.RuntimeStackLoad(stack.value, i64_const(expr.slot and expr.slot.index or 0)))
  end
  if cls == Exec.TopValueExpr then return top_value_for_ref(state, env, expr.top) end
  if cls == Exec.CountExpr then return lower_count_spec(state, env, expr.count) end
  if cls == Exec.ValueSeqExpr then return lower_value_seq_runtime(state, env, expr.seq, "expr_seq") end
  if cls == Exec.AdjustResultsExpr then
    local src = lower_value_seq_runtime(state, env, expr.seq, "adjust_src"); if not src then return nil end
    return emit_expr(state, "adjust_seq", CFG.RuntimeValueSeqAdjust(src.value, expr.adjustment), "lua_seq")
  end
  if cls == Exec.VarargAccessExpr then
    local acls = pvm.classof(expr.access)
    if acls == RT.VarargIndex then
      local src = lower_vararg_source_runtime(state, env, expr.access.source); if not src then return nil end
      local key = env.values[key_value_ref(expr.access.key)]
      if not key then return add_error(state, "unbound_vararg_index_key:" .. key_value_ref(expr.access.key)) end
      if tag_name(key.tag) ~= "IntegerTag" then return add_error(state, "vararg_string_n_and_non_integer_keys_require_string_model") end
      return emit_runtime_expr(state, "getvarg", CFG.RuntimeVarargGet(src.value, key.value))
    elseif acls == RT.VarargFixedCopy or acls == RT.VarargOpenCopy then
      local src = lower_vararg_source_runtime(state, env, expr.access.source); if not src then return nil end
      local count = acls == RT.VarargFixedCopy and i64_const(expr.access.count and expr.access.count.value or 0) or i64_const(expr.access.source and expr.access.source.count and expr.access.source.count.value or 0)
      return emit_expr(state, "vararg_copy_seq", CFG.RuntimeValueSeqFromVarargs(src.value, count), "lua_seq")
    elseif acls == RT.VarargNField then
      return add_error(state, "vararg_n_field_requires_string_model")
    end
    return add_error(state, "unsupported_vararg_access:" .. tostring(expr.access and expr.access.kind))
  end
  if cls == Exec.TableRawGetExpr then
    local tablev = env.values[key_value_ref(expr.table_value)]
    local key = env.values[key_value_ref(expr.key)]
    if not tablev then return add_error(state, "unbound_table_raw_get_table:" .. key_value_ref(expr.table_value)) end
    if not key then return add_error(state, "unbound_table_raw_get_key:" .. key_value_ref(expr.key)) end
    local tables = tables_value_for_frame(state, env, frame_from_value_ref(expr.table_value)); if not tables then return nil end
    return emit_expr(state, "rawget", CFG.RuntimeTableRawGet(tables.value, tablev.value, key.value), "lua_raw_get")
  end
  if cls == Exec.TableRawGetHitExpr then
    local raw = resolve_exec_value(state, env, expr.rawget)
    if not raw then return nil end
    if raw.ty ~= "lua_raw_get" then return add_error(state, "table_raw_get_hit_requires_raw_get_result:" .. tostring(raw.ty)) end
    return emit_expr(state, "rawget_hit", CFG.RuntimeRawGetHit(raw.value), "bool")
  end
  if cls == Exec.TableRawGetValueOrNilExpr then
    local raw = resolve_exec_value(state, env, expr.rawget)
    if not raw then return nil end
    if raw.ty ~= "lua_raw_get" then return add_error(state, "table_raw_get_value_requires_raw_get_result:" .. tostring(raw.ty)) end
    return emit_runtime_expr(state, "rawget_value", CFG.RuntimeRawGetValueOrNil(raw.value))
  end
  if cls == Exec.TableRawSetCanWriteExpr then
    local tablev = env.values[key_value_ref(expr.table_value)]
    local key = env.values[key_value_ref(expr.key)]
    if not tablev then return add_error(state, "unbound_table_raw_set_can_write_table:" .. key_value_ref(expr.table_value)) end
    if not key then return add_error(state, "unbound_table_raw_set_can_write_key:" .. key_value_ref(expr.key)) end
    local tables = tables_value_for_frame(state, env, frame_from_value_ref(expr.table_value)); if not tables then return nil end
    return emit_expr(state, "table_raw_set_can_write", CFG.RuntimeTableRawSetCanWrite(tables.value, tablev.value, key.value), "bool")
  end
  if cls == Exec.TableWriteBarrierNeededExpr then
    local tablev = env.values[key_value_ref(expr.table_value)]
    local val = env.values[key_value_ref(expr.value)]
    if not tablev then return add_error(state, "unbound_table_barrier_table:" .. key_value_ref(expr.table_value)) end
    if not val then return add_error(state, "unbound_table_barrier_value:" .. key_value_ref(expr.value)) end
    local boxed = box_scalar(state, val); if not boxed then return nil end
    local tables = tables_value_for_frame(state, env, frame_from_value_ref(expr.table_value)); if not tables then return nil end
    return emit_expr(state, "table_barrier_needed", CFG.RuntimeTableWriteBarrierNeeded(tables.value, tablev.value, boxed.value), "bool")
  end
  if cls == Exec.TableLenExpr then
    local tablev = env.values[key_value_ref(expr.table_value)]
    if not tablev then return add_error(state, "unbound_table_len_value:" .. key_value_ref(expr.table_value)) end
    local tables = tables_value_for_frame(state, env, frame_from_value_ref(expr.table_value)); if not tables then return nil end
    return emit_expr(state, "table_len", CFG.RuntimeTableArrayLen(tables.value, tablev.value), "i64")
  end
  if cls == Exec.StringLenExpr then
    local v = env.values[key_value_ref(expr.value)]
    if not v then return add_error(state, "unbound_string_len_value:" .. key_value_ref(expr.value)) end
    local strings = strings_value_for_frame(state, env, frame_from_value_ref(expr.value)); if not strings then return nil end
    return emit_expr(state, "string_len", CFG.RuntimeStringLen(strings.value, v.value), "i64")
  end
  if cls == Exec.LenNoMetaExpr then
    local v = env.values[key_value_ref(expr.value)]
    if not v then return add_error(state, "unbound_len_value:" .. key_value_ref(expr.value)) end
    local frame = frame_from_value_ref(expr.value)
    local strings = strings_value_for_frame(state, env, frame); if not strings then return nil end
    local tables = tables_value_for_frame(state, env, frame); if not tables then return nil end
    return emit_expr(state, "len_no_meta", CFG.RuntimeLenNoMeta(strings.value, tables.value, v.value), "i64")
  end
  if cls == Exec.StringConcat2Expr then
    local left = env.values[key_value_ref(expr.left)]
    local right = env.values[key_value_ref(expr.right)]
    if not left then return add_error(state, "unbound_concat_left:" .. key_value_ref(expr.left)) end
    if not right then return add_error(state, "unbound_concat_right:" .. key_value_ref(expr.right)) end
    local strings = strings_value_for_frame(state, env, frame_from_value_ref(expr.left)); if not strings then return nil end
    return emit_runtime_expr(state, "concat2", CFG.RuntimeStringConcat2(strings.value, left.value, right.value), { type_test = RT.IsString })
  end
  if cls == Exec.ArithmeticNumericOkExpr then
    local left = env.values[key_value_ref(expr.left)]
    local right = env.values[key_value_ref(expr.right)]
    if not left then return add_error(state, "unbound_arithmetic_ok_left:" .. key_value_ref(expr.left)) end
    if not right then return add_error(state, "unbound_arithmetic_ok_right:" .. key_value_ref(expr.right)) end
    local strings = strings_value_for_frame(state, env, frame_from_value_ref(expr.left) or frame_from_value_ref(expr.right)); if not strings then return nil end
    local lbox = box_scalar(state, left); if not lbox then return nil end
    local rbox = box_scalar(state, right); if not rbox then return nil end
    return emit_expr(state, "arith_ok", CFG.RuntimeArithmeticNumericOk(expr.op, strings.value, lbox.value, rbox.value), "bool")
  end
  if cls == Exec.ArithmeticNoMetaExpr then
    local left = env.values[key_value_ref(expr.left)]
    local right = env.values[key_value_ref(expr.right)]
    if not left then return add_error(state, "unbound_arithmetic_left:" .. key_value_ref(expr.left)) end
    if not right then return add_error(state, "unbound_arithmetic_right:" .. key_value_ref(expr.right)) end
    local strings = strings_value_for_frame(state, env, frame_from_value_ref(expr.left) or frame_from_value_ref(expr.right)); if not strings then return nil end
    local lbox = box_scalar(state, left); if not lbox then return nil end
    local rbox = box_scalar(state, right); if not rbox then return nil end
    local meta = {}
    if tag_name(lbox.tag) == "IntegerTag" and tag_name(rbox.tag) == "IntegerTag" and expr.op and expr.op.kind == "ArithAdd" then
      meta.tag = RT.IntegerTag
    elseif (tag_name(lbox.tag) == "IntegerTag" or tag_name(lbox.tag) == "FloatTag") and (tag_name(rbox.tag) == "IntegerTag" or tag_name(rbox.tag) == "FloatTag") then
      meta.type_test = RT.IsNumber
    end
    return emit_runtime_expr(state, "arith", CFG.RuntimeArithmeticNoMeta(expr.op, strings.value, lbox.value, rbox.value), meta)
  end
  if cls == Exec.ArithmeticErrorValueExpr then
    local left = env.values[key_value_ref(expr.left)]
    local right = env.values[key_value_ref(expr.right)]
    if not left then return add_error(state, "unbound_arithmetic_error_left:" .. key_value_ref(expr.left)) end
    if not right then return add_error(state, "unbound_arithmetic_error_right:" .. key_value_ref(expr.right)) end
    local strings = strings_value_for_frame(state, env, frame_from_value_ref(expr.left) or frame_from_value_ref(expr.right)); if not strings then return nil end
    local lbox = box_scalar(state, left); if not lbox then return nil end
    local rbox = box_scalar(state, right); if not rbox then return nil end
    return emit_runtime_expr(state, "arith_error_value", CFG.RuntimeArithmeticErrorValue(expr.op, strings.value, lbox.value, rbox.value))
  end
  if cls == Exec.NumberOpExpr then
    return add_error(state, "unsupported_lua_exec_number_expr_until_arithmetic_region_migration")
  end
  return add_error(state, "unsupported_lua_exec_expr:" .. tostring(expr and expr.kind))
end

local function bind_value_ref(env, ref, e) env.values[key_value_ref(ref)] = e end

local function lower_op(state, env, op)
  local cls = pvm.classof(op)
  if cls == Exec.AssignValue then
    local v = resolve_exec_value(state, env, op.src)
    if not v then return nil end
    local boxed = box_scalar(state, v)
    if not boxed then return nil end
    bind_value_ref(env, op.dst, boxed)
    return true
  elseif cls == Exec.Let then
    local v = lower_expr(state, env, op.expr)
    if not v then return nil end
    env.temps[op.dst.text] = v
    return true
  elseif cls == Exec.AssignSeq then
    local seq = lower_value_seq_runtime(state, env, op.src, "assign_seq"); if not seq then return nil end
    local adjusted = emit_expr(state, "assign_seq_adjust", CFG.RuntimeValueSeqAdjust(seq.value, op.adjustment), "lua_seq")
    local stack = stack_value_for_ref(state, env, RT.StackRef(op.dst.frame)); if not stack then return nil end
    local base = op.dst.base and op.dst.base.index or 0
    local v0 = emit_runtime_expr(state, "seq_store0", CFG.RuntimeValueSeqValue(adjusted.value, 0))
    state.current_ops[#state.current_ops + 1] = CFG.RuntimeStackStore(stack.value, i64_const(base), v0.value)
    local v1 = emit_runtime_expr(state, "seq_store1", CFG.RuntimeValueSeqValue(adjusted.value, 1))
    state.current_ops[#state.current_ops + 1] = CFG.RuntimeStackStore(stack.value, i64_const(base + 1), v1.value)
    return true
  elseif cls == Exec.SetTop then
    local count = lower_count_spec(state, env, op.count); if not count then return nil end
    return set_top_value(state, env, op.top, count)
  elseif cls == Exec.TableRawSet then
    local tablev = env.values[key_value_ref(op.table_value)]
    local key = env.values[key_value_ref(op.key)]
    local val = env.values[key_value_ref(op.value)]
    if not tablev then return add_error(state, "unbound_table_raw_set_table:" .. key_value_ref(op.table_value)) end
    if not key then return add_error(state, "unbound_table_raw_set_key:" .. key_value_ref(op.key)) end
    if not val then return add_error(state, "unbound_table_raw_set_value:" .. key_value_ref(op.value)) end
    local boxed = box_scalar(state, val); if not boxed then return nil end
    local tables = tables_value_for_frame(state, env, frame_from_value_ref(op.table_value)); if not tables then return nil end
    state.current_ops[#state.current_ops + 1] = CFG.RuntimeTableRawSet(tables.value, tablev.value, key.value, boxed.value)
    return true
  elseif cls == Exec.TableWriteBarrier then
    local tablev = env.values[key_value_ref(op.table_value)]
    local val = env.values[key_value_ref(op.value)]
    if not tablev then return add_error(state, "unbound_table_barrier_table:" .. key_value_ref(op.table_value)) end
    if not val then return add_error(state, "unbound_table_barrier_value:" .. key_value_ref(op.value)) end
    local boxed = box_scalar(state, val); if not boxed then return nil end
    local tables = tables_value_for_frame(state, env, frame_from_value_ref(op.table_value)); if not tables then return nil end
    state.current_ops[#state.current_ops + 1] = CFG.RuntimeTableWriteBarrier(tables.value, tablev.value, boxed.value)
    return true
  elseif cls == Exec.Project then
    local v = env.values[key_value_ref(op.src)]
    if not v then return add_error(state, "unbound_project_value:" .. key_value_ref(op.src)) end
    local projected = lower_expr(state, env, Exec.ProjectExpr(op.src, op.projection)); if not projected then return nil end
    env.temps[op.dst.text] = projected
    return true
  elseif cls == Exec.Guard or cls == Exec.EmitRegion then
    return add_error(state, "unsupported_lua_exec_op:" .. tostring(op.kind))
  end
  return add_error(state, "unsupported_or_missing_lua_exec_op:" .. tostring(op and op.kind))
end

local function lower_choice(state, env, choice)
  local cls = pvm.classof(choice)
  if cls == Exec.TruthinessChoice then
    local v = truthiness_of_ref(state, env, choice.value)
    if not v then return nil end
    return CFG.BoolChoice(v.value)
  elseif cls == Exec.TypeChoice then
    local v = env.values[key_value_ref(choice.value)]
    if not v then return add_error(state, "unbound_type_choice_value:" .. key_value_ref(choice.value)) end
    local boxed = box_scalar(state, v); if not boxed then return nil end
    local test = emit_expr(state, "type_choice", CFG.RuntimeTypeTest(boxed.value, choice.test), "bool")
    return CFG.BoolChoice(test.value)
  elseif cls == Exec.NumericChoice then
    local lv = env.values[key_value_ref(choice.left)]
    local rv = env.values[key_value_ref(choice.right)]
    if not lv then return add_error(state, "unbound_numeric_left:" .. key_value_ref(choice.left)) end
    if not rv then return add_error(state, "unbound_numeric_right:" .. key_value_ref(choice.right)) end
    local li = ensure_i64_payload(state, lv, "left"); if not li then return nil end
    local ri = ensure_i64_payload(state, rv, "right"); if not ri then return nil end
    local test = NUMERIC_TEST[choice.test and choice.test.kind]
    if not test then return add_error(state, "unsupported_numeric_test:" .. tostring(choice.test and choice.test.kind)) end
    return CFG.NumericChoice(test, li.value, ri.value)
  elseif cls == Exec.ArithmeticNumericChoice then
    local lv = env.values[key_value_ref(choice.left)]
    local rv = env.values[key_value_ref(choice.right)]
    if not lv then return add_error(state, "unbound_arithmetic_choice_left:" .. key_value_ref(choice.left)) end
    if not rv then return add_error(state, "unbound_arithmetic_choice_right:" .. key_value_ref(choice.right)) end
    local lbox = box_scalar(state, lv); if not lbox then return nil end
    local rbox = box_scalar(state, rv); if not rbox then return nil end
    local strings = strings_value_for_frame(state, env, frame_from_value_ref(choice.left) or frame_from_value_ref(choice.right)); if not strings then return nil end
    local ok = emit_expr(state, "arith_choice", CFG.RuntimeArithmeticNumericOk(choice.op, strings.value, lbox.value, rbox.value), "bool")
    return CFG.BoolChoice(ok.value)
  elseif cls == Exec.BoolChoice then
    local v = resolve_exec_value(state, env, choice.value)
    if not v then return nil end
    if v.ty ~= "bool" then return add_error(state, "bool_choice_requires_bool:" .. tostring(v.ty)) end
    return CFG.BoolChoice(v.value)
  end
  return add_error(state, "unsupported_lua_exec_choice:" .. tostring(choice and choice.kind))
end

local function lower_arg(state, env, arg)
  local v = resolve_exec_value(state, env, arg.value)
  if not v then return nil end
  return cfg_arg_from_exec(arg, v.value)
end
local function lower_args(state, env, args)
  local out = {}
  for _, arg in ipairs(args or {}) do
    local a = lower_arg(state, env, arg)
    if not a then return nil end
    out[#out + 1] = a
  end
  return out
end

local function lower_return_entry(state, e)
  if e.ty == "i64" then state.return_ty = state.return_ty or "i64"; if state.return_ty ~= "i64" then return add_error(state, "inconsistent_return_type:" .. state.return_ty .. ":i64") end; return e.value end
  if e.ty == "f64" then state.return_ty = state.return_ty or "f64"; if state.return_ty ~= "f64" then return add_error(state, "inconsistent_return_type:" .. state.return_ty .. ":f64") end; return e.value end
  if e.ty == "bool" then state.return_ty = state.return_ty or "bool"; if state.return_ty ~= "bool" then return add_error(state, "inconsistent_return_type:" .. state.return_ty .. ":bool") end; return e.value end
  if e.ty ~= "lua_value" then return add_error(state, "unsupported_return_value_type:" .. tostring(e.ty)) end
  local k = tag_name(e.tag)
  if k == "IntegerTag" then local p = ensure_i64_payload(state, e, "return"); if not p then return nil end; state.return_ty = state.return_ty or "i64"; if state.return_ty ~= "i64" then return add_error(state, "inconsistent_return_type:" .. state.return_ty .. ":i64") end; return p.value end
  if k == "FloatTag" then local p = emit_expr(state, "return_f64", CFG.RuntimePayloadF64(e.value), "f64"); state.return_ty = state.return_ty or "f64"; if state.return_ty ~= "f64" then return add_error(state, "inconsistent_return_type:" .. state.return_ty .. ":f64") end; return p.value end
  if k == "TrueTag" or k == "FalseTag" or (e.type_test and e.type_test.kind == "IsBoolean") then local b = bool_payload(state, e, "return"); if not b then return nil end; state.return_ty = state.return_ty or "bool"; if state.return_ty ~= "bool" then return add_error(state, "inconsistent_return_type:" .. state.return_ty .. ":bool") end; return b.value end
  if k == "NilTag" then local t = emit_expr(state, "return_nil_tag", CFG.RuntimeTag(e.value), "i64"); state.return_ty = state.return_ty or "i64"; if state.return_ty ~= "i64" then return add_error(state, "inconsistent_return_type:" .. state.return_ty .. ":i64") end; return t.value end
  return add_error(state, "unsupported_lua_value_return_without_projection:" .. tostring(k) .. ":" .. tostring(e.type_test and e.type_test.kind))
end

local function lower_return_values(state, env, seq)
  if seq.count and seq.count.kind == "FixedCount" and (seq.count.count or seq.count.value or 0) == 0 then return {} end
  local out = {}
  for _, ref in ipairs(seq.values or {}) do
    local v = env.values[key_value_ref(ref)]
    if not v then return add_error(state, "unbound_return_value:" .. key_value_ref(ref)) end
    local rv = lower_return_entry(state, v)
    if not rv then return nil end
    out[#out + 1] = rv
  end
  if #out == 0 then
    if state.return_ty and state.return_ty ~= "void" then return add_error(state, "inconsistent_return_type:" .. tostring(state.return_ty) .. ":void") end
    state.return_ty = "void"
  end
  return out
end

function fixed_count_value(seq)
  local c = seq and seq.count
  if c and c.kind == "FixedCount" then return tonumber(c.count or c.value or 0) or 0 end
  return nil
end

local function lower_seq_runtime_values(state, env, seq, label)
  local seq_entry = lower_value_seq_runtime(state, env, seq, label .. "_runtime")
  if not seq_entry then return nil end
  local count = emit_expr(state, label .. "_count", CFG.RuntimeValueSeqCount(seq_entry.value), "i64")
  local v0 = emit_runtime_expr(state, label .. "_value0", CFG.RuntimeValueSeqValue(seq_entry.value, 0))
  local v1 = emit_runtime_expr(state, label .. "_value1", CFG.RuntimeValueSeqValue(seq_entry.value, 1))
  return { v0.value, v1.value }, count.value
end

local OUTCOME_PROJECTION = {
  kind = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeKind(out) end },
  count = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeCount(out) end },
  value0_tag = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeValueTag(out, 0) end },
  value0_payload_i64 = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeValuePayloadI64(out, 0) end },
  value0_payload_f64 = { ty = "f64", expr = function(out) return CFG.RuntimeOutcomeValuePayloadF64(out, 0) end },
  value1_tag = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeValueTag(out, 1) end },
  value1_payload_i64 = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeValuePayloadI64(out, 1) end },
  value1_payload_f64 = { ty = "f64", expr = function(out) return CFG.RuntimeOutcomeValuePayloadF64(out, 1) end },
  error_kind = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeErrorKind(out) end },
  error_value_tag = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeErrorValueTag(out) end },
  error_value_payload_i64 = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeErrorValuePayloadI64(out) end },
  saved_pc = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeSavedPc(out) end },
  yield_kind = { ty = "i64", expr = function(out) return CFG.RuntimeOutcomeYieldKind(out) end },
}

local function project_outcome(state, outcome)
  local projection = state.outcome_projection or "kind"
  local spec = OUTCOME_PROJECTION[projection]
  if not spec then return add_error(state, "unsupported_outcome_projection:" .. tostring(projection)) end
  local p = emit_expr(state, "outcome_" .. projection, spec.expr(outcome.value), spec.ty)
  if state.return_ty and state.return_ty ~= spec.ty then return add_error(state, "inconsistent_return_type:" .. tostring(state.return_ty) .. ":" .. spec.ty) end
  state.return_ty = spec.ty
  return CFG.Return({ p.value })
end

local function lower_return_outcome(state, env, seq)
  local values, count = lower_seq_runtime_values(state, env, seq, "return")
  if not values then return nil end
  local out = emit_outcome_expr(state, "normal_outcome", CFG.RuntimeOutcomeReturn(count, values, i64_const(0)), { outcome_kind = "NormalReturnOutcome" })
  return project_outcome(state, out)
end

local function lower_error_outcome(state, env, err)
  local v = env.values[key_value_ref(err.error_object)]
  if not v then return add_error(state, "error_outcome_unbound_error_object:" .. key_value_ref(err.error_object)) end
  local boxed = box_scalar(state, v); if not boxed then return nil end
  local saved_pc = i64_const(err.saved_pc and err.saved_pc.value or 0)
  local saved_top = i64_const(0)
  local out = emit_outcome_expr(state, "error_outcome", CFG.RuntimeOutcomeError(err.kind, boxed.value, saved_pc, saved_top), { outcome_kind = "LuaErrorOutcome" })
  return project_outcome(state, out)
end

local function lower_yield_outcome(state, env, y)
  local values, count = lower_seq_runtime_values(state, env, y.yielded_values, "yield")
  if not values then return nil end
  local out = emit_outcome_expr(state, "yield_outcome", CFG.RuntimeOutcomeYield(y.resume_point, count, values, i64_const(y.saved_pc and y.saved_pc.value or 0), i64_const(0)), { outcome_kind = "LuaYieldOutcome" })
  return project_outcome(state, out)
end

local function const_bool_choice(choice)
  if pvm.classof(choice) == CFG.BoolChoice and pvm.classof(choice.value) == CFG.ConstValue and pvm.classof(choice.value.const) == CFG.BoolConst then
    return choice.value.const.value == true
  end
  return nil
end

local function lower_terminator(state, env, term)
  local cls = pvm.classof(term)
  if cls == Exec.Jump then
    local args = lower_args(state, env, term.args); if not args then return nil end
    return CFG.Jump(bref_from_exec(term.target), args)
  elseif cls == Exec.Branch then
    local choice = lower_choice(state, env, term.choice); if not choice then return nil end
    local c = const_bool_choice(choice)
    if c ~= nil then return CFG.Jump(bref_from_exec(c and term.if_true or term.if_false), {}) end
    return CFG.Branch(choice, bref_from_exec(term.if_true), bref_from_exec(term.if_false))
  elseif cls == Exec.BranchArgs then
    local choice = lower_choice(state, env, term.choice); if not choice then return nil end
    local targs = lower_args(state, env, term.true_args); local fargs = lower_args(state, env, term.false_args)
    if not targs or not fargs then return nil end
    local c = const_bool_choice(choice)
    if c ~= nil then return CFG.Jump(bref_from_exec(c and term.if_true or term.if_false), c and targs or fargs) end
    if #targs == 0 and #fargs == 0 then return CFG.Branch(choice, bref_from_exec(term.if_true), bref_from_exec(term.if_false)) end
    return CFG.BranchArgs(choice, bref_from_exec(term.if_true), targs, bref_from_exec(term.if_false), fargs)
  elseif cls == Exec.Return then
    if state.outcome_mode then return lower_return_outcome(state, env, term.values) end
    local values = lower_return_values(state, env, term.values); if not values then return nil end
    return CFG.Return(values)
  elseif cls == Exec.Error then
    if not state.outcome_mode then return add_error(state, "lua_exec_error_requires_outcome_mode") end
    return lower_error_outcome(state, env, term.error)
  elseif cls == Exec.Yield then
    if not state.outcome_mode then return add_error(state, "lua_exec_yield_requires_outcome_mode") end
    return lower_yield_outcome(state, env, term.yield)
  elseif cls == Exec.Unreachable then
    return CFG.Unreachable
  end
  return add_error(state, "unsupported_lua_exec_terminator:" .. tostring(term and term.kind))
end

local function base_env_for_region(region)
  local params = {}
  for _, p in ipairs(region.params or {}) do
    local meta = param_meta(p)
    meta.value = CFG.ParamValue(cname(p.name.text))
    params[p.name.text] = meta
  end
  return { values = {}, temps = {}, params = params, stacks = {}, tops = {}, varargs = {} }
end

local function lower_block(state, region_env, block)
  local env = { values = copy_map(region_env.values), temps = copy_map(region_env.temps), params = copy_map(region_env.params), stacks = copy_map(region_env.stacks), tops = copy_map(region_env.tops), varargs = copy_map(region_env.varargs) }
  for _, p in ipairs(block.params or {}) do
    local meta = param_meta(p)
    meta.value = CFG.ParamValue(cname(p.name.text))
    env.params[p.name.text] = meta
  end
  state.current_ops = {}
  for _, op in ipairs(block.ops or {}) do if not lower_op(state, env, op) then return nil end end
  local term = lower_terminator(state, env, block.terminator); if not term then return nil end
  local cfg_params = {}
  for _, p in ipairs(block.params or {}) do cfg_params[#cfg_params + 1] = cfg_param(p) end
  local ops = state.current_ops
  state.current_ops = nil
  return CFG.Block(bid_from_exec(block.id), cfg_params, ops, term)
end

local function lower_value(kernel, opts)
  opts = opts or {}
  local ok, errs = ExecValidate.kernel(kernel)
  if not ok then return nil, errs end
  local state = { errors = {}, temp_id = 1, return_ty = nil, current_ops = nil, outcome_mode = opts.outcome == true, outcome_projection = opts.outcome_projection or opts.projection }
  local region = kernel.body
  local region_env = base_env_for_region(region)
  local blocks = {}
  for _, block in ipairs(region.blocks or {}) do
    local b = lower_block(state, region_env, block)
    if not b then return nil, state.errors end
    blocks[#blocks + 1] = b
  end
  if #state.errors > 0 then return nil, state.errors end
  local returns = {}
  if state.return_ty and state.return_ty ~= "void" then returns = { type_ref(state.return_ty) } end
  local params = {}
  for _, p in ipairs(region.params or {}) do params[#params + 1] = cfg_param(p) end
  local cfg_region = CFG.Region(rid("lua_exec_core_body"), params, {}, bid_from_exec(region.entry), blocks)
  local cfg_kernel = CFG.Kernel(kid("lua_exec_core_kernel"), CFG.InlineSpan, params, returns, cfg_region, empty_contract())
  return cfg_kernel, nil
end

local phase = pvm.phase("spongejit_lua_exec_to_moon_cfg_lower", function(kernel)
  local cfg, errors = lower_value(kernel)
  if not cfg then error("LuaExec->MoonCFG lower failed inside cached phase: " .. table.concat(errors or {}, "; ")) end
  return cfg
end)

function M.lower(kernel, opts)
  opts = opts or {}
  local cfg, errors = lower_value(kernel, opts)
  if not cfg then return nil, errors end
  if opts.outcome then return cfg end
  return pvm.one(phase(kernel))
end

function M.lower_outcome(kernel, projection)
  return M.lower(kernel, { outcome = true, outcome_projection = projection or "kind" })
end

M.phase = phase
M.lower_uncached = lower_value

return M
