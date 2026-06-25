-- lua_rt_call_model.lua -- LuaRT call semantics and current call-frame support gate.
--
-- Call products are organized around one CallRef spine.  Structural validation
-- accepts the complete Lua call architecture; executable support remains limited
-- to fully contracted fixed-shape direct Lua-closure call-frame transfer.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local RT, Exec = T.LuaRT, T.LuaExec
local LuaFact = T.LuaFact
local LuaSrc = T.LuaSrc
local LuaFFI = T.LuaFFI
local Arity = require("lua_compile.lua_rt_arity_model")

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function kind(v) return v and v.kind or nil end
local function add(errors, msg) errors[#errors + 1] = msg end
local function same_node(a, b) return a == b end

M.CALL_TARGET = {
  UnknownCallTarget = true,
  DirectLuaClosureTarget = true,
  DirectCClosureTarget = true,
  DirectLightCFunctionTarget = true,
  MetamethodFunctionTarget = true,
  FFISymbolTarget = true,
}
M.CALL_STATE_KIND = {
  CallStart = true,
  CallTargetResolved = true,
  CallFramePrepared = true,
  CallRunning = true,
  CallResultsReady = true,
  CallErrored = true,
  CallYielded = true,
  CallUnsupported = true,
}
M.CALL_TARGET_IDENTITY = {
  UnknownTargetIdentity = true,
  LuaClosureTargetIdentity = true,
  CClosureTargetIdentity = true,
  LightCFunctionTargetIdentity = true,
  MetamethodTargetIdentity = true,
  FFISymbolTargetIdentity = true,
}
M.CALL_FRAME_STATE_KIND = {
  CallFrameUnprepared = true,
  CallFrameArgsStored = true,
  CallFrameActive = true,
  CallFrameResultsReady = true,
  CallFrameReleased = true,
  CallFrameUnsupported = true,
}
M.EXECUTABLE_FRAME_STATE = {
  CallFrameUnprepared = true,
  CallFrameArgsStored = true,
  CallFrameResultsReady = true,
}

M.FRAME_TYPE_NAME = "LuaRTCallFrame"
M.TYPE_DECL = [[
struct LuaRTCallFrame
    caller_stack: ptr(LuaRTValue);
    callee_stack: ptr(LuaRTValue);
    arg_base: i64;
    arg_count: i64;
    result_base: i64;
    result_count: i64;
    target_ok: bool;
end
]]

local function validate_deps(errors, deps, path)
  for i, dep in ipairs(deps or {}) do
    if cls(dep) ~= LuaFact.Dependency then add(errors, path .. " deps[" .. i .. "] must be LuaFact.Dependency") end
  end
end

local function fixed_count_value(count_spec) return Arity.fixed_count_value(count_spec) end
local function is_fixed_count(count_spec) return cls(count_spec) == RT.FixedCount and fixed_count_value(count_spec) ~= nil end

function M.call_target_callee(target)
  local c = cls(target)
  if c == RT.UnknownCallTarget then return target.callee end
  if c == RT.DirectLuaClosureTarget or c == RT.DirectCClosureTarget or c == RT.DirectLightCFunctionTarget or c == RT.MetamethodFunctionTarget or c == RT.FFISymbolTarget then
    return target.callee
  end
  return nil
end

function M.validate_call_shape(shape)
  local errors = {}
  if cls(shape) ~= RT.CallShape then add(errors, "expected LuaRT.CallShape"); return false, errors end
  if cls(shape.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  if not member(shape.callee, RT.ValueRef) then add(errors, "callee must be LuaRT.ValueRef") end
  if cls(shape.args) ~= RT.StackWindow then add(errors, "args must be LuaRT.StackWindow") end
  if not member(shape.wanted_results, RT.CountSpec) then add(errors, "wanted_results must be LuaRT.CountSpec") end
  if not member(shape.tail_mode, RT.TailCallMode) then add(errors, "tail_mode must be LuaRT.TailCallMode") end
  if not member(shape.yield_policy, RT.YieldPolicy) then add(errors, "yield_policy must be LuaRT.YieldPolicy") end
  return #errors == 0, errors
end

function M.validate_call_target(target)
  local errors = {}
  if not member(target, RT.CallTarget) then add(errors, "expected LuaRT.CallTarget"); return false, errors end
  local k = kind(target)
  if k == "UnknownCallTarget" then
    if not member(target.callee, RT.ValueRef) then add(errors, "callee must be LuaRT.ValueRef") end
  elseif k == "DirectLuaClosureTarget" or k == "DirectCClosureTarget" then
    if not member(target.callee, RT.ValueRef) then add(errors, "callee must be LuaRT.ValueRef") end
    if cls(target.closure) ~= RT.ClosureRef then add(errors, "closure must be LuaRT.ClosureRef") end
  elseif k == "DirectLightCFunctionTarget" then
    if not member(target.callee, RT.ValueRef) then add(errors, "callee must be LuaRT.ValueRef") end
    if cls(target["function"]) ~= RT.FunctionRef then add(errors, "function must be LuaRT.FunctionRef") end
  elseif k == "MetamethodFunctionTarget" then
    if not member(target.callee, RT.ValueRef) then add(errors, "callee must be LuaRT.ValueRef") end
    if cls(target.path) ~= RT.MetamethodLookupPath then add(errors, "path must be LuaRT.MetamethodLookupPath") end
  elseif k == "FFISymbolTarget" then
    if not member(target.callee, RT.ValueRef) then add(errors, "callee must be LuaRT.ValueRef") end
    if cls(target.symbol) ~= LuaFFI.CSymbolId then add(errors, "symbol must be LuaFFI.CSymbolId") end
  else
    add(errors, "unknown call target kind: " .. tostring(k))
  end
  return #errors == 0, errors
end

function M.validate_call_target_identity(identity)
  local errors = {}
  if not member(identity, RT.CallTargetIdentity) then add(errors, "expected LuaRT.CallTargetIdentity"); return false, errors end
  local k = kind(identity)
  if k == "LuaClosureTargetIdentity" then
    if cls(identity.closure) ~= RT.ClosureRef then add(errors, "closure must be LuaRT.ClosureRef") end
    if cls(identity.proto) ~= LuaSrc.KRef then add(errors, "proto must be LuaSrc.KRef") end
    if type(identity.closure_handle) ~= "number" then add(errors, "closure_handle must be number") end
    validate_deps(errors, identity.deps, "LuaClosureTargetIdentity")
  elseif k == "CClosureTargetIdentity" then
    if cls(identity.closure) ~= RT.ClosureRef then add(errors, "closure must be LuaRT.ClosureRef") end
    if type(identity.function_handle) ~= "number" then add(errors, "function_handle must be number") end
    validate_deps(errors, identity.deps, "CClosureTargetIdentity")
  elseif k == "LightCFunctionTargetIdentity" then
    if cls(identity["function"]) ~= RT.FunctionRef then add(errors, "function must be LuaRT.FunctionRef") end
    if type(identity.function_handle) ~= "number" then add(errors, "function_handle must be number") end
    validate_deps(errors, identity.deps, "LightCFunctionTargetIdentity")
  elseif k == "MetamethodTargetIdentity" then
    if cls(identity.path) ~= RT.MetamethodLookupPath then add(errors, "path must be LuaRT.MetamethodLookupPath") end
    validate_deps(errors, identity.deps, "MetamethodTargetIdentity")
  elseif k == "FFISymbolTargetIdentity" then
    if cls(identity.symbol) ~= LuaFFI.CSymbolId then add(errors, "symbol must be LuaFFI.CSymbolId") end
    validate_deps(errors, identity.deps, "FFISymbolTargetIdentity")
  elseif k ~= "UnknownTargetIdentity" then
    add(errors, "unknown call target identity kind: " .. tostring(k))
  end
  return #errors == 0, errors
end

function M.validate_resolved_call_target(target)
  local errors = {}
  if cls(target) ~= RT.ResolvedCallTarget then add(errors, "expected LuaRT.ResolvedCallTarget"); return false, errors end
  if cls(target.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  local ok_target, target_errors = M.validate_call_target(target.target)
  if not ok_target then for _, e in ipairs(target_errors) do add(errors, "target " .. e) end end
  local ok_identity, identity_errors = M.validate_call_target_identity(target.identity)
  if not ok_identity then for _, e in ipairs(identity_errors) do add(errors, "identity " .. e) end end
  if not member(target.callable, RT.CallableKind) then add(errors, "callable must be LuaRT.CallableKind") end
  return #errors == 0, errors
end

function M.validate_call_arg_channel(channel)
  local errors = {}
  if cls(channel) ~= RT.CallArgChannel then add(errors, "expected LuaRT.CallArgChannel"); return false, errors end
  if cls(channel.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  if cls(channel.args) ~= RT.ValueSeq then add(errors, "args must be LuaRT.ValueSeq") end
  local ok_shape, shape_errors = Arity.validate_arity_shape(channel.shape)
  if not ok_shape then for _, e in ipairs(shape_errors) do add(errors, "shape " .. e) end end
  return #errors == 0, errors
end

function M.validate_call_result_channel(channel)
  local errors = {}
  if cls(channel) ~= RT.CallResultChannel then add(errors, "expected LuaRT.CallResultChannel"); return false, errors end
  if cls(channel.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  local ok_channel, channel_errors = Arity.validate_result_channel(channel.channel)
  if not ok_channel then for _, e in ipairs(channel_errors) do add(errors, "channel " .. e) end end
  local ok_norm, norm_errors = Arity.validate_arity_normalization(channel.normalization)
  if not ok_norm then for _, e in ipairs(norm_errors) do add(errors, "normalization " .. e) end end
  return #errors == 0, errors
end

function M.validate_call_frame_layout(layout)
  local errors = {}
  if cls(layout) ~= RT.CallFrameLayout then add(errors, "expected LuaRT.CallFrameLayout"); return false, errors end
  if cls(layout.id) ~= RT.CallFrameRef then add(errors, "id must be LuaRT.CallFrameRef") end
  if cls(layout.caller) ~= RT.FrameRef then add(errors, "caller must be LuaRT.FrameRef") end
  if cls(layout.callee) ~= RT.FrameRef then add(errors, "callee must be LuaRT.FrameRef") end
  if cls(layout.callee_slot) ~= RT.Slot then add(errors, "callee_slot must be LuaRT.Slot") end
  if cls(layout.arg_base) ~= RT.Slot then add(errors, "arg_base must be LuaRT.Slot") end
  if not member(layout.arg_count, RT.CountSpec) then add(errors, "arg_count must be LuaRT.CountSpec") end
  if cls(layout.result_base) ~= RT.Slot then add(errors, "result_base must be LuaRT.Slot") end
  if not member(layout.result_count, RT.CountSpec) then add(errors, "result_count must be LuaRT.CountSpec") end
  if cls(layout.frame_slots) ~= RT.Count then add(errors, "frame_slots must be LuaRT.Count") end
  return #errors == 0, errors
end

function M.validate_call_spine(shape, target, args, results, frame)
  local errors = {}
  local call = shape and shape.call or target and target.call or args and args.call or results and results.call or frame and frame.call
  local function check(label, v)
    if v and v.call and call and not same_node(v.call, call) then add(errors, label .. " call ref mismatch") end
  end
  check("shape", shape); check("target", target); check("args", args); check("results", results); check("frame", frame)
  return #errors == 0, errors
end

function M.validate_call_frame_state(frame)
  local errors = {}
  if cls(frame) ~= RT.CallFrameState then add(errors, "expected LuaRT.CallFrameState"); return false, errors end
  if cls(frame.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  local ok_layout, layout_errors = M.validate_call_frame_layout(frame.layout)
  if not ok_layout then for _, e in ipairs(layout_errors) do add(errors, "layout " .. e) end end
  local ok_args, arg_errors = M.validate_call_arg_channel(frame.args)
  if not ok_args then for _, e in ipairs(arg_errors) do add(errors, "args " .. e) end end
  local ok_results, result_errors = M.validate_call_result_channel(frame.results)
  if not ok_results then for _, e in ipairs(result_errors) do add(errors, "results " .. e) end end
  local ok_target, target_errors = M.validate_resolved_call_target(frame.target)
  if not ok_target then for _, e in ipairs(target_errors) do add(errors, "target " .. e) end end
  if not member(frame.state, RT.CallFrameStateKind) then add(errors, "state must be LuaRT.CallFrameStateKind") end
  local spine_ok, spine_errors = M.validate_call_spine(nil, frame.target, frame.args, frame.results, frame)
  if not spine_ok then for _, e in ipairs(spine_errors) do add(errors, e) end end
  return #errors == 0, errors
end

function M.validate_call_state(state)
  local errors = {}
  if cls(state) ~= RT.CallState then add(errors, "expected LuaRT.CallState"); return false, errors end
  if cls(state.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  local shape_ok, shape_errors = M.validate_call_shape(state.shape)
  if not shape_ok then for _, e in ipairs(shape_errors) do add(errors, "shape " .. e) end end
  local ok, target_errors = M.validate_call_target(state.target)
  if not ok then for _, e in ipairs(target_errors) do add(errors, "target " .. e) end end
  if not member(state.state, RT.CallStateKind) then add(errors, "state must be LuaRT.CallStateKind") end
  local rc_ok, rc_errors = Arity.validate_result_channel(state.result_channel)
  if not rc_ok then for _, e in ipairs(rc_errors) do add(errors, "result_channel " .. e) end end
  if state.shape and state.shape.call and state.call ~= state.shape.call then add(errors, "shape call ref mismatch") end
  return #errors == 0, errors
end

function M.is_executable_resolved_target(target)
  local ok = M.validate_resolved_call_target(target)
  if not ok then return false, "invalid_resolved_target" end
  if cls(target.target) ~= RT.DirectLuaClosureTarget then return false, "unsupported_target_kind:" .. tostring(kind(target.target)) end
  if kind(target.identity) ~= "LuaClosureTargetIdentity" then return false, "unsupported_target_identity:" .. tostring(kind(target.identity)) end
  if kind(target.callable) ~= "CallableLuaClosure" then return false, "unsupported_callable:" .. tostring(kind(target.callable)) end
  if type(target.identity.closure_handle) ~= "number" or target.identity.closure_handle < 0 then return false, "invalid_closure_handle" end
  return true
end

function M.is_executable_frame_layout(layout)
  local ok = M.validate_call_frame_layout(layout)
  if not ok then return false, "invalid_frame_layout" end
  if not is_fixed_count(layout.arg_count) then return false, "dynamic_arg_count" end
  if not is_fixed_count(layout.result_count) then return false, "dynamic_result_count" end
  return true
end

local function is_executable_arg_channel(channel)
  local ok = M.validate_call_arg_channel(channel)
  if not ok then return false, "invalid_arg_channel" end
  if not is_fixed_count(channel.shape.provided) or not is_fixed_count(channel.shape.wanted) then return false, "dynamic_arg_arity" end
  if not Arity.adjustment_supported_now(channel.shape.adjustment) then return false, "unsupported_arg_adjustment" end
  return true
end

local function is_executable_result_channel(channel)
  local ok = M.validate_call_result_channel(channel)
  if not ok then return false, "invalid_result_channel" end
  if kind(channel.channel.kind) ~= "StackWindowRoute" then return false, "not_call_frame_result_route" end
  if not is_fixed_count(channel.channel.count) then return false, "dynamic_result_channel_count" end
  if not is_fixed_count(channel.normalization.shape.provided) or not is_fixed_count(channel.normalization.shape.wanted) then return false, "dynamic_result_normalization" end
  if not Arity.adjustment_supported_now(channel.normalization.shape.adjustment) then return false, "unsupported_result_adjustment" end
  return true
end

function M.is_executable_call_frame_state(frame)
  local ok = M.validate_call_frame_state(frame)
  if not ok then return false, "invalid_call_frame_state" end
  if not M.EXECUTABLE_FRAME_STATE[kind(frame.state)] then return false, "unsupported_frame_state:" .. tostring(kind(frame.state)) end
  local target_ok, target_reason = M.is_executable_resolved_target(frame.target)
  if not target_ok then return false, target_reason end
  local layout_ok, layout_reason = M.is_executable_frame_layout(frame.layout)
  if not layout_ok then return false, layout_reason end
  local args_ok, args_reason = is_executable_arg_channel(frame.args)
  if not args_ok then return false, args_reason end
  local results_ok, results_reason = is_executable_result_channel(frame.results)
  if not results_ok then return false, results_reason end
  return true
end

function M.is_phase1_executable_target(target) return M.is_executable_resolved_target(target) end

local function contract_lists(contract)
  return (contract and contract.obligations) or {}, (contract and contract.guarantees) or {}
end

function M.contract_allows_executable_call_region(contract)
  local obligations, guarantees = contract_lists(contract)
  local target, layout, args, results, prepared, produced
  for _, o in ipairs(obligations) do
    local k = kind(o)
    if k == "RequiresResolvedCallTarget" then target = o.target
    elseif k == "RequiresCallFrameLayout" then layout = o.layout
    elseif k == "RequiresCallArgChannel" then args = o.channel
    elseif k == "RequiresCallResultChannel" then results = o.channel end
  end
  for _, g in ipairs(guarantees) do
    local k = kind(g)
    if k == "ResolvesCallTarget" and target == nil then target = g.target
    elseif k == "PreparesCallFrame" then prepared = g.frame
    elseif k == "ProducesCallResults" then produced = g.channel end
  end
  if not (target and layout and args and results) then return false, "missing_call_contract" end
  local target_ok, target_reason = M.is_executable_resolved_target(target)
  if not target_ok then return false, target_reason end
  local layout_ok, layout_reason = M.is_executable_frame_layout(layout)
  if not layout_ok then return false, layout_reason end
  local args_ok, args_reason = is_executable_arg_channel(args)
  if not args_ok then return false, args_reason end
  local results_ok, results_reason = is_executable_result_channel(results)
  if not results_ok then return false, results_reason end
  if prepared then
    local prep_ok, prep_reason = M.is_executable_call_frame_state(prepared)
    if not prep_ok then return false, prep_reason end
  end
  if produced then
    local prod_ok, prod_reason = is_executable_result_channel(produced)
    if not prod_ok then return false, prod_reason end
  end
  return true
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({
    "CallTarget", "CallStateKind", "CallState", "TailCallMode", "YieldPolicy",
    "CallFrameRef", "CallTargetIdentity", "ResolvedCallTarget",
    "CallArgChannel", "CallFrameLayout", "CallFrameStateKind",
    "CallResultChannel", "CallFrameState",
  }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT." .. name end
  end
  for name in pairs(M.CALL_TARGET) do if RT[name] == nil then missing[#missing + 1] = "LuaRT.CallTarget." .. name end end
  for name in pairs(M.CALL_STATE_KIND) do if RT[name] == nil then missing[#missing + 1] = "LuaRT.CallStateKind." .. name end end
  for name in pairs(M.CALL_TARGET_IDENTITY) do if RT[name] == nil then missing[#missing + 1] = "LuaRT.CallTargetIdentity." .. name end end
  for name in pairs(M.CALL_FRAME_STATE_KIND) do if RT[name] == nil then missing[#missing + 1] = "LuaRT.CallFrameStateKind." .. name end end
  if Exec then
    for _, name in ipairs({
      "ResolvedCallTargetExpr", "CallArgChannelExpr", "CallFrameStateExpr",
      "CallResultChannelExpr", "PrepareCallFrame", "ReceiveCallResults",
      "RequiresResolvedCallTarget", "RequiresCallFrameLayout", "RequiresCallArgChannel",
      "RequiresCallResultChannel", "ResolvesCallTarget", "PreparesCallFrame",
      "ProducesCallResults", "CallContinuationRegion",
    }) do
      if Exec[name] == nil then missing[#missing + 1] = "LuaExec." .. name end
    end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
