-- lua_rt_arity_model.lua -- LuaRT typed arity/result-route semantics.
--
-- The ASDL architecture models value carriers separately from result routing
-- and frame effects.  This module validates the complete products while the
-- current lowerer supports only the existing fixed/open value-sequence slice.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local RT = T.LuaRT

local M = {}

local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function kind(v) return v and v.kind or nil end

M.ARITY_KIND = { FixedArity = true, OpenArity = true, VarargArity = true, UnknownArity = true }
M.RESULT_ROUTE_KIND = {
  DirectReturnRoute = true,
  OutcomeReturnRoute = true,
  StackWindowRoute = true,
  ContinuationRoute = true,
  TailCallFrameRoute = true,
  YieldRoute = true,
  ClosePendingRoute = true,
}
M.FRAME_EFFECT_KIND = {
  SetTopEffect = true,
  StoreSeqEffect = true,
  ReplaceFrameEffect = true,
  PreserveFrameEffect = true,
}
M.EXECUTABLE_ADJUSTMENT = {
  ExactCount = true,
  FillNilTo = true,
  TruncateTo = true,
  OpenResult = true,
  PropagateOpenTail = true,
}

local function count_value(c)
  if type(c) == "number" then return c end
  if c and type(c.value) == "number" then return c.value end
  if c and type(c.count) == "number" then return c.count end
  if c and type(c.n) == "number" then return c.n end
  return nil
end

function M.fixed_count_value(count_spec)
  if cls(count_spec) ~= RT.FixedCount then return nil end
  return count_value(count_spec.count)
end

function M.adjustment_target_count(adjustment)
  local k = kind(adjustment)
  if k == "ExactCount" or k == "FillNilTo" or k == "TruncateTo" then
    return count_value(adjustment.count)
  end
  return nil
end

function M.adjustment_supported_now(adjustment)
  return M.EXECUTABLE_ADJUSTMENT[kind(adjustment)] == true
end

local function arity_kind_for(provided, wanted, adjustment)
  if cls(provided) == RT.UnknownCount or cls(wanted) == RT.UnknownCount then return RT.UnknownArity end
  if cls(provided) == RT.DynamicCount or cls(wanted) == RT.DynamicCount then return RT.UnknownArity end
  if cls(provided) == RT.OpenFromVarargs or cls(provided) == RT.OpenFromVarargsAtBase then return RT.VarargArity end
  if cls(wanted) == RT.OpenFromVarargs or cls(wanted) == RT.OpenFromVarargsAtBase then return RT.VarargArity end
  if kind(adjustment) == "OpenResult" or kind(adjustment) == "PropagateOpenTail" then return RT.OpenArity end
  if cls(provided) == RT.OpenFromTop or cls(wanted) == RT.OpenFromTop then return RT.OpenArity end
  if cls(provided) == RT.FixedCount and cls(wanted) == RT.FixedCount then return RT.FixedArity end
  return RT.UnknownArity
end

function M.shape_for_adjustment(provided, wanted, adjustment)
  return RT.ArityShape(provided, wanted, adjustment, arity_kind_for(provided, wanted, adjustment))
end

local function route_for_legacy_kind(channel_kind)
  if type(channel_kind) ~= "string" then return channel_kind end
  if channel_kind == "DirectReturnChannel" then return RT.DirectReturnRoute end
  if channel_kind == "OutcomeReturnChannel" then return RT.OutcomeReturnRoute end
  if channel_kind == "ContinuationReturnChannel" then return RT.ContinuationRoute end
  if channel_kind == "TailCallReturnChannel" or channel_kind == "CallFrameResultChannel" then return RT.StackWindowRoute end
  return assert(RT[channel_kind], "unknown LuaRT.ResultRouteKind: " .. channel_kind)
end

local function default_destination_for_route(route)
  local k = kind(route)
  if k == "DirectReturnRoute" then return RT.ReturnDestination end
  if k == "OutcomeReturnRoute" then return RT.OutcomeDestination end
  if k == "ContinuationRoute" then return RT.ContinuationDestination(RT.Name("result_cont")) end
  if k == "TailCallFrameRoute" then return RT.TailCallDestination(RT.FrameRef(RT.Name("tail_frame"))) end
  if k == "YieldRoute" then return RT.YieldDestination(RT.ResumeReturn) end
  if k == "ClosePendingRoute" then return RT.ClosePendingDestination(RT.CloseChain(RT.FrameRef(RT.Name("close_frame")), {})) end
  return RT.StackWindowDestination(RT.StackWindow(RT.ReturnWindow, RT.FrameRef(RT.Name("result_frame")), RT.Slot(0), RT.FixedCount(0)))
end

function M.result_channel(channel_kind, seq_or_id, count_or_destination, maybe_count)
  local route = route_for_legacy_kind(channel_kind)
  local id, destination, count
  if cls(seq_or_id) == RT.Name then
    id = seq_or_id
    destination = count_or_destination
    count = maybe_count
  else
    id = RT.Name("result")
    destination = default_destination_for_route(route)
    count = count_or_destination
  end
  return RT.ResultChannel(id, route, destination, count)
end

function M.result_bundle(seq, channel)
  return RT.ResultBundle(seq, channel)
end

function M.normalization(source, shape, channel, effects)
  return RT.ArityNormalization(source, shape, RT.ResultBundle(source, channel), effects or {})
end

function M.is_fixed_shape(shape)
  return cls(shape) == RT.ArityShape
    and kind(shape.kind) == "FixedArity"
    and cls(shape.provided) == RT.FixedCount
    and cls(shape.wanted) == RT.FixedCount
end

function M.validate_arity_shape(shape)
  local errors = {}
  if cls(shape) ~= RT.ArityShape then errors[#errors + 1] = "expected LuaRT.ArityShape"; return false, errors end
  if not member(shape.provided, RT.CountSpec) then errors[#errors + 1] = "provided must be LuaRT.CountSpec" end
  if not member(shape.wanted, RT.CountSpec) then errors[#errors + 1] = "wanted must be LuaRT.CountSpec" end
  if not member(shape.adjustment, RT.ResultAdjustment) then errors[#errors + 1] = "adjustment must be LuaRT.ResultAdjustment" end
  if not member(shape.kind, RT.ArityKind) then errors[#errors + 1] = "kind must be LuaRT.ArityKind" end
  return #errors == 0, errors
end

function M.validate_result_channel(channel)
  local errors = {}
  if cls(channel) ~= RT.ResultChannel then errors[#errors + 1] = "expected LuaRT.ResultChannel"; return false, errors end
  if cls(channel.id) ~= RT.Name then errors[#errors + 1] = "id must be LuaRT.Name" end
  if not member(channel.kind, RT.ResultRouteKind) then errors[#errors + 1] = "kind must be LuaRT.ResultRouteKind" end
  if not member(channel.destination, RT.ResultDestination) then errors[#errors + 1] = "destination must be LuaRT.ResultDestination" end
  if not member(channel.count, RT.CountSpec) then errors[#errors + 1] = "count must be LuaRT.CountSpec" end
  return #errors == 0, errors
end

function M.validate_result_bundle(bundle)
  local errors = {}
  if cls(bundle) ~= RT.ResultBundle then errors[#errors + 1] = "expected LuaRT.ResultBundle"; return false, errors end
  if cls(bundle.values) ~= RT.ValueSeq then errors[#errors + 1] = "values must be LuaRT.ValueSeq" end
  local ok_channel, channel_errors = M.validate_result_channel(bundle.channel)
  if not ok_channel then for _, e in ipairs(channel_errors) do errors[#errors + 1] = "channel." .. e end end
  return #errors == 0, errors
end

function M.validate_frame_effect(effect)
  local errors = {}
  if cls(effect) ~= RT.FrameEffect then errors[#errors + 1] = "expected LuaRT.FrameEffect"; return false, errors end
  if not member(effect.kind, RT.FrameEffectKind) then errors[#errors + 1] = "kind must be LuaRT.FrameEffectKind" end
  if cls(effect.frame) ~= RT.FrameRef then errors[#errors + 1] = "frame must be LuaRT.FrameRef" end
  if cls(effect.window) ~= RT.StackWindow then errors[#errors + 1] = "window must be LuaRT.StackWindow" end
  if not member(effect.count, RT.CountSpec) then errors[#errors + 1] = "count must be LuaRT.CountSpec" end
  return #errors == 0, errors
end

function M.validate_arity_normalization(n)
  local errors = {}
  if cls(n) ~= RT.ArityNormalization then errors[#errors + 1] = "expected LuaRT.ArityNormalization"; return false, errors end
  if cls(n.source) ~= RT.ValueSeq then errors[#errors + 1] = "source must be LuaRT.ValueSeq" end
  local ok_shape, shape_errors = M.validate_arity_shape(n.shape)
  if not ok_shape then for _, e in ipairs(shape_errors) do errors[#errors + 1] = "shape." .. e end end
  local ok_result, result_errors = M.validate_result_bundle(n.result)
  if not ok_result then for _, e in ipairs(result_errors) do errors[#errors + 1] = "result." .. e end end
  for i, effect in ipairs(n.effects or {}) do
    local ok_effect, effect_errors = M.validate_frame_effect(effect)
    if not ok_effect then for _, e in ipairs(effect_errors) do errors[#errors + 1] = "effects[" .. i .. "]." .. e end end
  end
  return #errors == 0, errors
end

local function executable_count_spec(count_spec)
  local c = cls(count_spec)
  return c == RT.FixedCount or c == RT.OpenFromTop or c == RT.OpenFromVarargs or c == RT.OpenFromVarargsAtBase
end

function M.is_executable_normalization(n)
  local ok = M.validate_arity_normalization(n)
  if not ok then return false end
  if not M.adjustment_supported_now(n.shape.adjustment) then return false end
  if not executable_count_spec(n.shape.provided) then return false end
  if not executable_count_spec(n.shape.wanted) then return false end
  local ck = kind(n.result.channel.kind)
  return ck == "DirectReturnRoute" or ck == "OutcomeReturnRoute" or ck == "ContinuationRoute" or ck == "StackWindowRoute"
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({ "ArityKind", "ArityShape", "ArityNormalization", "ResultRouteKind", "ResultDestination", "ResultChannel", "ResultBundle", "FrameEffect", "FromArityNormalization" }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT." .. name end
  end
  for name in pairs(M.ARITY_KIND) do if RT[name] == nil then missing[#missing + 1] = "LuaRT.ArityKind." .. name end end
  for name in pairs(M.RESULT_ROUTE_KIND) do if RT[name] == nil then missing[#missing + 1] = "LuaRT.ResultRouteKind." .. name end end
  for name in pairs(M.FRAME_EFFECT_KIND) do if RT[name] == nil then missing[#missing + 1] = "LuaRT.FrameEffectKind." .. name end end
  table.sort(missing)
  return #missing == 0, missing
end

return M
