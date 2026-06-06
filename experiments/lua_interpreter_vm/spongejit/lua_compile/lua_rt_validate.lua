-- lua_compile/lua_rt_validate.lua -- structural checks for LuaRT semantic ASDL.
--
-- These validators establish the semantic foundation only. They do not lower
-- opcodes, invoke runtime helpers, or bless interpreter/protocol handoffs.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local RT = T.LuaRT
local ArityModel = require("lua_compile.lua_rt_arity_model")
local CallModel = require("lua_compile.lua_rt_call_model")
local MetatableModel = require("lua_compile.lua_rt_metatable_model")
local OperationModel = require("lua_compile.lua_rt_operation_model")
local CloseModel = require("lua_compile.lua_rt_close_model")
local ClosureUpvalueModel = require("lua_compile.lua_rt_closure_upvalue_model")
local GCModel = require("lua_compile.lua_rt_gc_alloc_model")
local LoopModel = require("lua_compile.lua_rt_loop_model")
local CDataModel = require("lua_compile.lua_rt_cdata_model")
local FFIValidate = require("lua_compile.lua_ffi_validate")

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end
local function cls(v) return pvm.classof(v) end
local function is_member(sum, v)
  return v ~= nil and sum and sum.members and sum.members[cls(v)] or false
end

function M.tvalue(value)
  local errors = {}
  if not is_member(RT.TValue, value) then add(errors, "expected LuaRT.TValue") end
  return #errors == 0, errors
end

function M.frame(frame)
  local errors = {}
  if cls(frame) ~= RT.Frame then
    add(errors, "expected LuaRT.Frame")
    return false, errors
  end
  if cls(frame.id) ~= RT.FrameRef then add(errors, "frame.id must be LuaRT.FrameRef") end
  if cls(frame.stack) ~= RT.StackRef then add(errors, "frame.stack must be LuaRT.StackRef") end
  if cls(frame.top) ~= RT.TopRef then add(errors, "frame.top must be LuaRT.TopRef") end
  if not is_member(RT.VarargSource, frame.varargs) then add(errors, "frame.varargs must be LuaRT.VarargSource") end
  if cls(frame.close_chain) ~= RT.CloseChain then add(errors, "frame.close_chain must be LuaRT.CloseChain") end
  if cls(frame.pc) ~= RT.Pc then add(errors, "frame.pc must be LuaRT.Pc") end
  return #errors == 0, errors
end

function M.value_seq(seq)
  local errors = {}
  if cls(seq) ~= RT.ValueSeq then
    add(errors, "expected LuaRT.ValueSeq")
    return false, errors
  end
  if not is_member(RT.ValueSeqKind, seq.kind) then add(errors, "value sequence kind must be LuaRT.ValueSeqKind") end
  if not is_member(RT.CountSpec, seq.count) then add(errors, "value sequence count must be LuaRT.CountSpec") end
  if not is_member(RT.SequenceOrigin, seq.origin) then add(errors, "value sequence origin must be LuaRT.SequenceOrigin") end
  for i, value in ipairs(seq.values or {}) do
    if not is_member(RT.ValueRef, value) then add(errors, "value sequence value " .. i .. " must be LuaRT.ValueRef") end
  end
  return #errors == 0, errors
end

function M.arity_shape(shape)
  return ArityModel.validate_arity_shape(shape)
end

function M.result_channel(channel)
  return ArityModel.validate_result_channel(channel)
end

function M.result_bundle(bundle)
  return ArityModel.validate_result_bundle(bundle)
end

function M.frame_effect(effect)
  return ArityModel.validate_frame_effect(effect)
end

function M.arity_normalization(normalization)
  local ok, errors = ArityModel.validate_arity_normalization(normalization)
  if not ok then return ok, errors end
  local seq_ok, seq_errors = M.value_seq(normalization.source)
  if not seq_ok then
    errors = errors or {}
    for _, e in ipairs(seq_errors) do add(errors, "source " .. e) end
  end
  local result_ok, result_errors = M.result_bundle(normalization.result)
  if not result_ok then
    errors = errors or {}
    for _, e in ipairs(result_errors) do add(errors, "result " .. e) end
  end
  return #(errors or {}) == 0, errors or {}
end

function M.call_state(state)
  return CallModel.validate_call_state(state)
end

function M.call_target_identity(identity)
  return CallModel.validate_call_target_identity(identity)
end

function M.resolved_call_target(target)
  return CallModel.validate_resolved_call_target(target)
end

function M.call_arg_channel(channel)
  return CallModel.validate_call_arg_channel(channel)
end

function M.call_result_channel(channel)
  return CallModel.validate_call_result_channel(channel)
end

function M.call_frame_layout(layout)
  return CallModel.validate_call_frame_layout(layout)
end

function M.call_frame_state(frame)
  return CallModel.validate_call_frame_state(frame)
end

function M.call_shape(shape)
  return CallModel.validate_call_shape(shape)
end

function M.metamethod_lookup_path(path)
  return MetatableModel.validate_metamethod_lookup_path(path)
end

function M.metamethod_dispatch(dispatch)
  return MetatableModel.validate_metamethod_dispatch(dispatch)
end

function M.lua_operation(operation)
  return OperationModel.validate_lua_operation(operation)
end

function M.upvalue_identity(identity)
  return ClosureUpvalueModel.validate_upvalue_identity(identity)
end

function M.closure_identity(identity)
  return ClosureUpvalueModel.validate_closure_identity(identity)
end

function M.loop_topology(topology)
  return LoopModel.validate_loop_topology(topology)
end

function M.close_plan(plan)
  return CloseModel.validate_close_plan(plan)
end

function M.outcome_cause(cause)
  return CloseModel.validate_outcome_cause(cause)
end

function M.gc_effect(effect)
  return GCModel.validate_gc_effect(effect)
end

function M.ffi_call_shape(call)
  return FFIValidate.ffi_call_shape(call)
end

function M.ffi_callback_entry(entry)
  return FFIValidate.ffi_callback_entry(entry)
end

function M.cdata_ownership_transition(transition)
  return CDataModel.validate_ownership_transition(transition)
end

return M
