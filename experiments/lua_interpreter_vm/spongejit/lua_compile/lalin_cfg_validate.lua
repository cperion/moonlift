-- lalin_cfg_validate.lua -- structural honesty checks for LalinCFG kernels.

local pvm = require("lalin.pvm")
local Validate = require("lua_compile.validate")
local B = require("lua_compile.builders")
local T = B.T
local CFG, RT = T.LalinCFG, T.LuaRT
local ValueModel = require("lua_compile.lua_rt_value_model")
local OutcomeModel = require("lua_compile.lua_rt_outcome_model")
local StackModel = require("lua_compile.lua_rt_stack_model")
local ObjectModel = require("lua_compile.lua_rt_object_model")
local CallModel = require("lua_compile.lua_rt_call_model")

local M = {}

-- Future typed semantic ASDL constructors are allowed as constructors, but
-- lowercase semantic strings remain forbidden fallback tags. LuaExec static
-- invocation must be typed/inlined before LalinCFG; LalinCFG.EmitRegion,
-- Continue, and Exit remain unsupported guardrails here.
local FORBIDDEN_STRINGS = {
  call = true,
  close = true,
  generic_for = true,
  setlist = true,
  getvarg = true,
  out_tag = true,
  out_event_kind = true,
}

local SUPPORTED_OPS = {
  [CFG.Let] = true,
  [CFG.Assign] = true,
  [CFG.Store] = true,
  [CFG.RuntimeStackStore] = true,
  [CFG.RuntimeValueSeqStore] = true,
  [CFG.RuntimeCallFrameStoreArgs] = true,
  [CFG.RuntimeTopStore] = true,
  [CFG.RuntimeTableRawSet] = true,
  [CFG.RuntimeTableWriteBarrier] = true,
  [CFG.Assert] = true,
}

local function add(errors, msg) errors[#errors + 1] = msg end

local function text_of_name(n)
  if type(n) == "table" and n.text ~= nil then return tostring(n.text) end
  return tostring(n or "")
end

local function block_key(id) return text_of_name(id and id.name) end

local function walk(v, fn, seen)
  local tv = type(v)
  if tv ~= "table" then fn(v); return end
  seen = seen or {}
  if seen[v] then return end
  seen[v] = true
  fn(v)
  local cls = pvm.classof(v)
  if cls and rawget(cls, "__fields") then
    for _, f in ipairs(cls.__fields) do walk(v[f.name], fn, seen) end
  elseif not cls then
    for _, x in pairs(v) do walk(x, fn, seen) end
  end
end

local function param_name_set(params)
  local set, ordered = {}, {}
  for _, p in ipairs(params or {}) do
    local name = text_of_name(p.name)
    if set[name] then return nil, nil, "duplicate_param:" .. name end
    set[name] = true
    ordered[#ordered + 1] = name
  end
  return set, ordered, nil
end

local function validate_jump_args(term, target, where, errors)
  if not target then return end
  local expected, _ordered, perr = param_name_set(target.params or {})
  if perr then add(errors, where .. ":target_" .. perr); return end
  local seen = {}
  for _, arg in ipairs(term.args or {}) do
    local name = text_of_name(arg.name)
    if seen[name] then add(errors, where .. ":duplicate_arg:" .. name) end
    seen[name] = true
    if not expected[name] then add(errors, where .. ":unexpected_arg:" .. name) end
  end
  for name in pairs(expected) do
    if not seen[name] then add(errors, where .. ":missing_arg:" .. name) end
  end
end

local function validate_branch_choice(choice, where, errors)
  local cls = pvm.classof(choice)
  if cls == CFG.BoolChoice then return end
  if cls == CFG.NumericChoice then
    local k = choice.test and choice.test.kind
    if k == "NumEq" or k == "NumLt" or k == "NumLe" or k == "NumGt" or k == "NumGe" or k == "NumNonZero" then return end
    add(errors, where .. ":unsupported_numeric_choice:" .. tostring(k))
    return
  end
  add(errors, where .. ":unsupported_choice:" .. tostring(choice and choice.kind))
end

local function value_is_seq_like(v, env)
  local cls = pvm.classof(v)
  if cls == CFG.PlaceValue then
    local pcls = pvm.classof(v.place)
    if pcls == CFG.Temp then return env[text_of_name(v.place.name)] == StackModel.SEQ_TYPE_NAME end
    return true
  elseif cls == CFG.ParamValue then
    return true
  end
  return false
end

local function value_is_vararg_like(v, env)
  local cls = pvm.classof(v)
  if cls == CFG.PlaceValue then
    local pcls = pvm.classof(v.place)
    if pcls == CFG.Temp then return env[text_of_name(v.place.name)] == StackModel.VARARG_TYPE_NAME end
    return true
  elseif cls == CFG.ParamValue then
    return true
  end
  return false
end

local function value_is_raw_get_like(v, env)
  local cls = pvm.classof(v)
  if cls == CFG.PlaceValue then
    local pcls = pvm.classof(v.place)
    if pcls == CFG.Temp then return env[text_of_name(v.place.name)] == ObjectModel.RAW_GET_TYPE_NAME end
    return true
  elseif cls == CFG.ParamValue then
    return true
  end
  return false
end

local function value_is_outcome_like(v, env)
  local cls = pvm.classof(v)
  if cls == CFG.PlaceValue then
    local pcls = pvm.classof(v.place)
    if pcls == CFG.Temp then return env[text_of_name(v.place.name)] == "LuaRTOutcome" end
    return true
  elseif cls == CFG.ParamValue then
    return true
  end
  return false
end

local function value_is_runtime_like(v, env)
  local cls = pvm.classof(v)
  if cls == CFG.PlaceValue then
    local pcls = pvm.classof(v.place)
    if pcls == CFG.Temp then return env[text_of_name(v.place.name)] == "LuaRTValue" end
    return true
  elseif cls == CFG.ParamValue then
    return true
  end
  return false
end

local function validate_runtime_expr(expr, env, where, errors)
  local cls = pvm.classof(expr)
  if cls == CFG.RuntimeBoxNil then
    if not ValueModel.tag_name_for_nil_kind(expr.kind) then add(errors, where .. ":unsupported_nil_kind:" .. tostring(expr.kind and expr.kind.kind)) end
  elseif cls == CFG.RuntimeBoxBool or cls == CFG.RuntimeBoxI64 or cls == CFG.RuntimeBoxF64 then
    -- Scalar operand rendering validates through render_value; no string tags.
  elseif cls == CFG.RuntimeBoxRef then
    local tag_name = expr.tag and expr.tag.kind
    if not tag_name or ValueModel.TAG[tag_name] == nil then add(errors, where .. ":unsupported_runtime_ref_tag:" .. tostring(tag_name)) end
  elseif cls == CFG.RuntimeTag or cls == CFG.RuntimePayloadI64 or cls == CFG.RuntimePayloadF64 or cls == CFG.RuntimeTruthiness then
    if not value_is_runtime_like(expr.value, env) then add(errors, where .. ":runtime_projection_requires_runtime_value") end
  elseif cls == CFG.RuntimeTypeTest then
    if not value_is_runtime_like(expr.value, env) then add(errors, where .. ":runtime_type_test_requires_runtime_value") end
    if not ValueModel.tags_for_type_test(expr.test) then add(errors, where .. ":unsupported_runtime_type_test:" .. tostring(expr.test and expr.test.kind)) end
  elseif cls == CFG.RuntimeOutcomeReturn then
    for i, v in ipairs(expr.values or {}) do if not value_is_runtime_like(v, env) then add(errors, where .. ":runtime_outcome_value_" .. i .. "_requires_lua_rt_value") end end
  elseif cls == CFG.RuntimeOutcomeReturnSeq then
    if not value_is_seq_like(expr.seq, env) then add(errors, where .. ":runtime_outcome_return_seq_requires_seq") end
  elseif cls == CFG.RuntimeOutcomeError then
    if OutcomeModel.ERROR_KIND[expr.kind and expr.kind.kind] == nil then add(errors, where .. ":unsupported_error_kind:" .. tostring(expr.kind and expr.kind.kind)) end
    if not value_is_runtime_like(expr.error_value, env) then add(errors, where .. ":runtime_outcome_error_value_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeOutcomeYield then
    if OutcomeModel.YIELD_KIND[expr.resume_point and expr.resume_point.kind] == nil then add(errors, where .. ":unsupported_yield_kind:" .. tostring(expr.resume_point and expr.resume_point.kind)) end
    for i, v in ipairs(expr.values or {}) do if not value_is_runtime_like(v, env) then add(errors, where .. ":runtime_outcome_yield_value_" .. i .. "_requires_lua_rt_value") end end
  elseif cls == CFG.RuntimeOutcomeYieldSeq then
    if OutcomeModel.YIELD_KIND[expr.resume_point and expr.resume_point.kind] == nil then add(errors, where .. ":unsupported_yield_kind:" .. tostring(expr.resume_point and expr.resume_point.kind)) end
    if not value_is_seq_like(expr.seq, env) then add(errors, where .. ":runtime_outcome_yield_seq_requires_seq") end
  elseif cls == CFG.RuntimeStackLoad then
    -- Pointer/index values are Lalin-level parameters/temps validated by typechecking.
  elseif cls == CFG.RuntimeTopLoad or cls == CFG.RuntimeOpenCountFromTop then
    -- Explicit top/count arithmetic; no semantic helper.
  elseif cls == CFG.RuntimeValueSeqFixed then
    if #(expr.values or {}) > 2 then add(errors, where .. ":runtime_value_seq_fixed_supports_first_two_inline_values") end
    for i, v in ipairs(expr.values or {}) do if not value_is_runtime_like(v, env) then add(errors, where .. ":runtime_value_seq_value_" .. i .. "_requires_lua_rt_value") end end
  elseif cls == CFG.RuntimeValueSeqFromStack then
    -- Stack pointer/base/count are explicit Lalin values.
  elseif cls == CFG.RuntimeValueSeqFromVarargs then
    if not value_is_vararg_like(expr.varargs, env) then add(errors, where .. ":runtime_value_seq_from_varargs_requires_vararg_source") end
  elseif cls == CFG.RuntimeValueSeqAdjust then
    if not value_is_seq_like(expr.seq, env) then add(errors, where .. ":runtime_value_seq_adjust_requires_seq") end
    local ak = expr.adjustment and expr.adjustment.kind
    if ak ~= "ExactCount" and ak ~= "OpenResult" and ak ~= "FillNilTo" and ak ~= "TruncateTo" and ak ~= "PropagateOpenTail" then add(errors, where .. ":unsupported_result_adjustment:" .. tostring(ak)) end
  elseif cls == CFG.RuntimeValueSeqNormalize then
    if not value_is_seq_like(expr.seq, env) then add(errors, where .. ":runtime_value_seq_normalize_requires_seq") end
    local ak = expr.shape and expr.shape.adjustment and expr.shape.adjustment.kind
    if ak ~= "ExactCount" and ak ~= "OpenResult" and ak ~= "FillNilTo" and ak ~= "TruncateTo" and ak ~= "PropagateOpenTail" then add(errors, where .. ":unsupported_arity_normalization_adjustment:" .. tostring(ak)) end
  elseif cls == CFG.RuntimeValueSeqCount or cls == CFG.RuntimeValueSeqValue or cls == CFG.RuntimeValueSeqBuffer or cls == CFG.RuntimeValueSeqBase then
    if not value_is_seq_like(expr.seq, env) then add(errors, where .. ":runtime_value_seq_projection_requires_seq") end
  elseif cls == CFG.RuntimeClassifyCallee then
    if not value_is_runtime_like(expr.callee, env) then add(errors, where .. ":runtime_classify_callee_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeCallTargetCheck then
    if not value_is_runtime_like(expr.callee, env) then add(errors, where .. ":runtime_call_target_check_requires_lua_rt_value") end
    local ok, errs = CallModel.validate_resolved_call_target(expr.target)
    if not ok then for _, e in ipairs(errs) do add(errors, where .. ":runtime_call_target_check " .. e) end end
  elseif cls == CFG.RuntimeCallFramePrepare then
    if not value_is_seq_like(expr.args, env) then add(errors, where .. ":runtime_call_frame_prepare_requires_args_seq") end
    local ok, errs = CallModel.validate_call_frame_layout(expr.layout)
    if not ok then for _, e in ipairs(errs) do add(errors, where .. ":runtime_call_frame_prepare " .. e) end end
  elseif cls == CFG.RuntimeCallFrameResultSeq then
    local ok, errs = CallModel.validate_call_frame_layout(expr.layout)
    if not ok then for _, e in ipairs(errs) do add(errors, where .. ":runtime_call_frame_result_seq_layout " .. e) end end
    local rc_ok, rc_errs = CallModel.validate_call_result_channel(expr.channel)
    if not rc_ok then for _, e in ipairs(rc_errs) do add(errors, where .. ":runtime_call_frame_result_seq_channel " .. e) end end
  elseif cls == CFG.RuntimeVarargSource then
    -- values/count/table_handle are explicit materialized data fields.
  elseif cls == CFG.RuntimeVarargCount then
    if not value_is_vararg_like(expr.source, env) then add(errors, where .. ":runtime_vararg_count_requires_vararg_source") end
  elseif cls == CFG.RuntimeVarargGet then
    if not value_is_vararg_like(expr.source, env) then add(errors, where .. ":runtime_vararg_get_requires_vararg_source") end
    if not value_is_runtime_like(expr.key, env) then add(errors, where .. ":runtime_vararg_get_key_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeTableRawGet then
    if not value_is_runtime_like(expr.table_value, env) then add(errors, where .. ":runtime_table_raw_get_table_requires_lua_rt_value") end
    if not value_is_runtime_like(expr.key, env) then add(errors, where .. ":runtime_table_raw_get_key_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeTableRawSetCanWrite then
    if not value_is_runtime_like(expr.table_value, env) then add(errors, where .. ":runtime_table_raw_set_can_write_table_requires_lua_rt_value") end
    if not value_is_runtime_like(expr.key, env) then add(errors, where .. ":runtime_table_raw_set_can_write_key_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeTableWriteBarrierNeeded then
    if not value_is_runtime_like(expr.table_value, env) then add(errors, where .. ":runtime_table_write_barrier_table_requires_lua_rt_value") end
    if not value_is_runtime_like(expr.value, env) then add(errors, where .. ":runtime_table_write_barrier_value_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeRawGetHit or cls == CFG.RuntimeRawGetValue or cls == CFG.RuntimeRawGetValueOrNil then
    if not value_is_raw_get_like(expr.rawget, env) then add(errors, where .. ":runtime_raw_get_projection_requires_raw_get_result") end
  elseif cls == CFG.RuntimeTableArrayLen then
    if not value_is_runtime_like(expr.table_value, env) then add(errors, where .. ":runtime_table_len_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeStringLen then
    if not value_is_runtime_like(expr.value, env) then add(errors, where .. ":runtime_string_len_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeLenNoMeta or cls == CFG.RuntimeLenNoMetaOk then
    if not value_is_runtime_like(expr.value, env) then add(errors, where .. ":runtime_len_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeStringConcat2 then
    if not value_is_runtime_like(expr.left, env) then add(errors, where .. ":runtime_concat_left_requires_lua_rt_value") end
    if not value_is_runtime_like(expr.right, env) then add(errors, where .. ":runtime_concat_right_requires_lua_rt_value") end
  elseif cls == CFG.RuntimeArithmeticNumericOk or cls == CFG.RuntimeArithmeticNoMeta or cls == CFG.RuntimeArithmeticErrorValue then
    if not expr.strings then add(errors, where .. ":runtime_arithmetic_requires_strings_bank") end
    if not value_is_runtime_like(expr.left, env) then add(errors, where .. ":runtime_arithmetic_left_requires_lua_rt_value") end
    if not value_is_runtime_like(expr.right, env) then add(errors, where .. ":runtime_arithmetic_right_requires_lua_rt_value") end
    local ok = expr.op and expr.op.kind == "ArithAdd"
    if not ok then add(errors, where .. ":unsupported_runtime_arithmetic_op:" .. tostring(expr.op and expr.op.kind)) end
  elseif cls == CFG.RuntimeOutcomeKind or cls == CFG.RuntimeOutcomeCount or cls == CFG.RuntimeOutcomeValueTag
      or cls == CFG.RuntimeOutcomeValuePayloadI64 or cls == CFG.RuntimeOutcomeValuePayloadF64
      or cls == CFG.RuntimeOutcomeErrorKind or cls == CFG.RuntimeOutcomeErrorValueTag
      or cls == CFG.RuntimeOutcomeErrorValuePayloadI64 or cls == CFG.RuntimeOutcomeSavedPc
      or cls == CFG.RuntimeOutcomeYieldKind then
    if not value_is_outcome_like(expr.outcome, env) then add(errors, where .. ":runtime_outcome_projection_requires_outcome_value") end
  end
end

local function infer_let_type(expr)
  local cls = pvm.classof(expr)
  if cls == CFG.RuntimeBoxNil or cls == CFG.RuntimeBoxBool or cls == CFG.RuntimeBoxI64 or cls == CFG.RuntimeBoxF64 or cls == CFG.RuntimeBoxRef or cls == CFG.RuntimeStackLoad or cls == CFG.RuntimeVarargGet or cls == CFG.RuntimeValueSeqValue or cls == CFG.RuntimeRawGetValue or cls == CFG.RuntimeRawGetValueOrNil or cls == CFG.RuntimeStringConcat2 or cls == CFG.RuntimeArithmeticNoMeta or cls == CFG.RuntimeArithmeticErrorValue then return "LuaRTValue" end
  if cls == CFG.RuntimeOutcomeReturn or cls == CFG.RuntimeOutcomeReturnSeq or cls == CFG.RuntimeOutcomeError or cls == CFG.RuntimeOutcomeYield or cls == CFG.RuntimeOutcomeYieldSeq then return "LuaRTOutcome" end
  if cls == CFG.RuntimeValueSeqFixed or cls == CFG.RuntimeValueSeqFromStack or cls == CFG.RuntimeValueSeqFromVarargs or cls == CFG.RuntimeValueSeqAdjust or cls == CFG.RuntimeValueSeqNormalize or cls == CFG.RuntimeCallFrameResultSeq then return StackModel.SEQ_TYPE_NAME end
  if cls == CFG.RuntimeCallFramePrepare then return CallModel.FRAME_TYPE_NAME end
  if cls == CFG.RuntimeTableRawGet then return ObjectModel.RAW_GET_TYPE_NAME end
  if cls == CFG.RuntimeVarargSource then return StackModel.VARARG_TYPE_NAME end
  if cls == CFG.RuntimePayloadF64 or cls == CFG.RuntimeOutcomeValuePayloadF64 then return "f64" end
  if cls == CFG.RuntimeTruthiness or cls == CFG.RuntimeTypeTest or cls == CFG.RuntimeRawGetHit or cls == CFG.RuntimeTableRawSetCanWrite or cls == CFG.RuntimeTableWriteBarrierNeeded or cls == CFG.RuntimeLenNoMetaOk or cls == CFG.RuntimeArithmeticNumericOk or cls == CFG.RuntimeCallTargetCheck then return "bool" end
  if cls == CFG.RuntimeTag or cls == CFG.RuntimePayloadI64 or cls == CFG.RuntimeTopLoad or cls == CFG.RuntimeOpenCountFromTop or cls == CFG.RuntimeValueSeqCount or cls == CFG.RuntimeValueSeqBase or cls == CFG.RuntimeVarargCount or cls == CFG.RuntimeClassifyCallee
      or cls == CFG.RuntimeTableArrayLen or cls == CFG.RuntimeStringLen or cls == CFG.RuntimeLenNoMeta
      or cls == CFG.RuntimeOutcomeKind or cls == CFG.RuntimeOutcomeCount
      or cls == CFG.RuntimeOutcomeValueTag or cls == CFG.RuntimeOutcomeValuePayloadI64
      or cls == CFG.RuntimeOutcomeErrorKind or cls == CFG.RuntimeOutcomeErrorValueTag
      or cls == CFG.RuntimeOutcomeErrorValuePayloadI64 or cls == CFG.RuntimeOutcomeSavedPc
      or cls == CFG.RuntimeOutcomeYieldKind then return "i64" end
  if cls == CFG.RuntimeValueSeqBuffer then return "ptr(LuaRTValue)" end
  return nil
end

local function validate_expr(expr, env, where, errors)
  local cls = pvm.classof(expr)
  if cls == CFG.ValueExpr or cls == CFG.Primitive or cls == CFG.Load or cls == CFG.AddressOf or cls == CFG.Convert then return end
  if cls == CFG.RuntimeBoxNil or cls == CFG.RuntimeBoxBool or cls == CFG.RuntimeBoxI64 or cls == CFG.RuntimeBoxF64 or cls == CFG.RuntimeBoxRef
      or cls == CFG.RuntimeTag or cls == CFG.RuntimePayloadI64 or cls == CFG.RuntimePayloadF64 or cls == CFG.RuntimeTruthiness or cls == CFG.RuntimeTypeTest
      or cls == CFG.RuntimeOutcomeReturn or cls == CFG.RuntimeOutcomeReturnSeq or cls == CFG.RuntimeOutcomeError or cls == CFG.RuntimeOutcomeYield or cls == CFG.RuntimeOutcomeYieldSeq
      or cls == CFG.RuntimeStackLoad or cls == CFG.RuntimeTopLoad or cls == CFG.RuntimeOpenCountFromTop
      or cls == CFG.RuntimeValueSeqFixed or cls == CFG.RuntimeValueSeqFromStack or cls == CFG.RuntimeValueSeqFromVarargs or cls == CFG.RuntimeValueSeqAdjust or cls == CFG.RuntimeValueSeqNormalize
      or cls == CFG.RuntimeValueSeqCount or cls == CFG.RuntimeValueSeqValue or cls == CFG.RuntimeValueSeqBuffer or cls == CFG.RuntimeValueSeqBase
      or cls == CFG.RuntimeClassifyCallee or cls == CFG.RuntimeCallTargetCheck or cls == CFG.RuntimeCallFramePrepare or cls == CFG.RuntimeCallFrameResultSeq
      or cls == CFG.RuntimeVarargSource or cls == CFG.RuntimeVarargCount or cls == CFG.RuntimeVarargGet
      or cls == CFG.RuntimeTableRawGet or cls == CFG.RuntimeRawGetHit or cls == CFG.RuntimeRawGetValue or cls == CFG.RuntimeRawGetValueOrNil
      or cls == CFG.RuntimeTableRawSetCanWrite or cls == CFG.RuntimeTableWriteBarrierNeeded
      or cls == CFG.RuntimeTableArrayLen or cls == CFG.RuntimeStringLen or cls == CFG.RuntimeLenNoMeta or cls == CFG.RuntimeLenNoMetaOk or cls == CFG.RuntimeStringConcat2
      or cls == CFG.RuntimeArithmeticNumericOk or cls == CFG.RuntimeArithmeticNoMeta or cls == CFG.RuntimeArithmeticErrorValue
      or cls == CFG.RuntimeOutcomeKind or cls == CFG.RuntimeOutcomeCount or cls == CFG.RuntimeOutcomeValueTag
      or cls == CFG.RuntimeOutcomeValuePayloadI64 or cls == CFG.RuntimeOutcomeValuePayloadF64
      or cls == CFG.RuntimeOutcomeErrorKind or cls == CFG.RuntimeOutcomeErrorValueTag
      or cls == CFG.RuntimeOutcomeErrorValuePayloadI64 or cls == CFG.RuntimeOutcomeSavedPc
      or cls == CFG.RuntimeOutcomeYieldKind then
    validate_runtime_expr(expr, env, where, errors)
    return
  end
  add(errors, where .. ":unsupported_expr:" .. tostring(expr and expr.kind))
end

local function validate_region(region, kernel, errors)
  if pvm.classof(region) ~= CFG.Region then add(errors, "expected LalinCFG.Region body"); return end
  local blocks = region.blocks or {}
  if #blocks == 0 then add(errors, "region_has_no_blocks") end
  if #(kernel.returns or {}) > 1 then add(errors, "unsupported_kernel_return_arity:" .. tostring(#(kernel.returns or {}))) end
  local by_key = {}
  for i, block in ipairs(blocks) do
    if pvm.classof(block) ~= CFG.Block then add(errors, "region block " .. i .. " is not LalinCFG.Block") else
      local key = block_key(block.id)
      if by_key[key] then add(errors, "duplicate_block_id:" .. key) end
      by_key[key] = block
      local _set, _ordered, perr = param_name_set(block.params or {})
      if perr then add(errors, "block_" .. key .. ":" .. perr) end
      local env = {}
      for _, p in ipairs(block.params or {}) do
        if p.type and p.type.lalin_type == ValueModel.TYPE_NAME then env[text_of_name(p.name)] = "LuaRTValue" end
        if p.type and p.type.lalin_type == StackModel.SEQ_TYPE_NAME then env[text_of_name(p.name)] = StackModel.SEQ_TYPE_NAME end
        if p.type and p.type.lalin_type == StackModel.VARARG_TYPE_NAME then env[text_of_name(p.name)] = StackModel.VARARG_TYPE_NAME end
      end
      for _, p in ipairs(region.params or {}) do
        if p.type and p.type.lalin_type == ValueModel.TYPE_NAME then env[text_of_name(p.name)] = "LuaRTValue" end
        if p.type and p.type.lalin_type == StackModel.SEQ_TYPE_NAME then env[text_of_name(p.name)] = StackModel.SEQ_TYPE_NAME end
        if p.type and p.type.lalin_type == StackModel.VARARG_TYPE_NAME then env[text_of_name(p.name)] = StackModel.VARARG_TYPE_NAME end
      end
      for j, op in ipairs(block.ops or {}) do
        local cls = pvm.classof(op)
        if not SUPPORTED_OPS[cls] then add(errors, "unsupported_op:" .. key .. ":" .. tostring(j) .. ":" .. tostring(op and op.kind)) end
        if cls == CFG.Let then
          validate_expr(op.expr, env, "op:" .. key .. ":" .. tostring(j), errors)
          local ty = infer_let_type(op.expr)
          if ty then env[text_of_name(op.dst and op.dst.name)] = ty end
        elseif cls == CFG.RuntimeValueSeqStore then
          if not value_is_seq_like(op.seq, env) then add(errors, "op:" .. key .. ":" .. tostring(j) .. ":runtime_value_seq_store_requires_seq") end
        elseif cls == CFG.RuntimeCallFrameStoreArgs then
          local ok, errs = CallModel.validate_call_frame_layout(op.layout)
          if not ok then for _, e in ipairs(errs) do add(errors, "op:" .. key .. ":" .. tostring(j) .. ":runtime_call_frame_store_args " .. e) end end
          if not value_is_seq_like(op.args, env) then add(errors, "op:" .. key .. ":" .. tostring(j) .. ":runtime_call_frame_store_args_requires_seq") end
        elseif cls == CFG.RuntimeTableWriteBarrier then
          if not value_is_runtime_like(op.table_value, env) then add(errors, "op:" .. key .. ":" .. tostring(j) .. ":runtime_table_write_barrier_table_requires_lua_rt_value") end
          if not value_is_runtime_like(op.value, env) then add(errors, "op:" .. key .. ":" .. tostring(j) .. ":runtime_table_write_barrier_value_requires_lua_rt_value") end
        elseif cls == CFG.Assert then
          validate_expr(op.condition, env, "assert:" .. key .. ":" .. tostring(j), errors)
        end
      end
    end
  end
  local entry_key = block_key(region.entry)
  local entry = by_key[entry_key]
  if not entry then add(errors, "missing_entry_block:" .. entry_key)
  elseif #(entry.params or {}) > 0 then add(errors, "unsupported_entry_block_params") end

  local function check_target(ref, where)
    if pvm.classof(ref) ~= CFG.BlockRef then add(errors, where .. ":expected_block_ref"); return nil end
    local key = block_key(ref.id)
    local target = by_key[key]
    if not target then add(errors, where .. ":unresolved_block_ref:" .. key) end
    return target
  end
  for _, block in ipairs(blocks) do
    if pvm.classof(block) == CFG.Block then
      local key = block_key(block.id)
      local term = block.terminator
      local cls = pvm.classof(term)
      if cls == CFG.Jump then
        local target = check_target(term.target, "jump")
        validate_jump_args(term, target, "jump", errors)
      elseif cls == CFG.Branch then
        validate_branch_choice(term.choice, "branch", errors)
        local true_target = check_target(term.if_true, "branch.true")
        local false_target = check_target(term.if_false, "branch.false")
        if true_target and #(true_target.params or {}) ~= 0 then add(errors, "branch.true:target_requires_params") end
        if false_target and #(false_target.params or {}) ~= 0 then add(errors, "branch.false:target_requires_params") end
      elseif cls == CFG.BranchArgs then
        validate_branch_choice(term.choice, "branch_args", errors)
        local true_target = check_target(term.if_true, "branch_args.true")
        local false_target = check_target(term.if_false, "branch_args.false")
        validate_jump_args({ args = term.true_args or {} }, true_target, "branch_args.true", errors)
        validate_jump_args({ args = term.false_args or {} }, false_target, "branch_args.false", errors)
      elseif cls == CFG.Return then
        local want = #(kernel.returns or {})
        local got = #(term.values or {})
        if want ~= got then add(errors, "return_arity_mismatch:" .. key .. ":expected_" .. want .. ":got_" .. got) end
      elseif cls == CFG.Unreachable then
        -- Local poison terminator for intentionally unreachable blocks.
      elseif cls == CFG.Switch or cls == CFG.Exit or cls == CFG.Continue then
        add(errors, "unsupported_terminator:" .. tostring(term and term.kind))
      else
        add(errors, "unsupported_or_missing_terminator:" .. tostring(term and term.kind))
      end
    end
  end
end

function M.validate(kernel)
  local errors = {}
  if pvm.classof(kernel) ~= CFG.Kernel then add(errors, "expected LalinCFG.Kernel") end
  local ok_basic, basic = Validate.lalin_cfg_kernel(kernel)
  for _, e in ipairs(basic or {}) do add(errors, e) end
  walk(kernel, function(v)
    local tv = type(v)
    if tv == "string" and FORBIDDEN_STRINGS[v] then add(errors, "forbidden_string_semantic_tag:" .. v) end
    if tv == "table" then
      local cls = pvm.classof(v)
      local plan = cls and rawget(cls, "__plan")
      local cname = tostring((plan and plan.name) or v.kind or "")
      local retired = { "Lua" .. "Sem", "Lua" .. "NF", "Lua" .. "Contract", "Lua" .. "Place", "Normal" .. "Form" }
      for _, token in ipairs(retired) do
        if cname:match(token) then add(errors, "forbidden_legacy_schema_node:" .. cname) end
      end
      if cname:match("ProtocolExit") then add(errors, "forbidden_protocol_exit_concept:" .. cname) end
      if cls == CFG.Param then
        local pname = text_of_name(v.name)
        if pname:match("^out_") then add(errors, "forbidden_param:" .. pname) end
      end
    end
  end)
  if pvm.classof(kernel) == CFG.Kernel then
    validate_region(kernel.body, kernel, errors)
  end
  return #errors == 0 and ok_basic, errors
end

return M
