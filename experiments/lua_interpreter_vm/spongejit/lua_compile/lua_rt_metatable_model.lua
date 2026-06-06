-- lua_rt_metatable_model.lua -- metatable and metamethod semantic products.
-- Structural validation only: lookup execution and metamethod calls remain lowerer-gated.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local RT = T.LuaRT
local Arity = require("lua_compile.lua_rt_arity_model")
local CallModel = require("lua_compile.lua_rt_call_model")

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function kind(v) return v and v.kind or nil end
local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate_metatable_epoch(epoch)
  local errors = {}
  if cls(epoch) ~= RT.MetatableEpoch then add(errors, "expected LuaRT.MetatableEpoch"); return false, errors end
  if not member(epoch.metatable, RT.MetatableRef) then add(errors, "metatable must be LuaRT.MetatableRef") end
  if type(epoch.epoch) ~= "number" then add(errors, "epoch must be number") end
  return #errors == 0, errors
end

function M.validate_metamethod_slot(slot)
  local errors = {}
  if cls(slot) ~= RT.MetamethodSlot then add(errors, "expected LuaRT.MetamethodSlot"); return false, errors end
  if not member(slot.metatable, RT.MetatableRef) then add(errors, "metatable must be LuaRT.MetatableRef") end
  if not member(slot.method, RT.Metamethod) then add(errors, "method must be LuaRT.Metamethod") end
  if not member(slot.slot_value, RT.ValueRef) then add(errors, "slot_value must be LuaRT.ValueRef") end
  if type(slot.slot_epoch) ~= "number" then add(errors, "slot_epoch must be number") end
  return #errors == 0, errors
end

function M.validate_metamethod_lookup_step(step)
  local errors = {}
  if not member(step, RT.MetamethodLookupStep) then add(errors, "expected LuaRT.MetamethodLookupStep"); return false, errors end
  local k = kind(step)
  if k == "CheckReceiverMetatable" then
    if not member(step.receiver, RT.ValueRef) then add(errors, "receiver must be LuaRT.ValueRef") end
    local ok, errs = M.validate_metatable_epoch(step.epoch); if not ok then for _, e in ipairs(errs) do add(errors, "epoch " .. e) end end
  elseif k == "CheckTypeMetatable" then
    if not member(step.tag, RT.ValueTag) then add(errors, "tag must be LuaRT.ValueTag") end
    local ok, errs = M.validate_metatable_epoch(step.epoch); if not ok then for _, e in ipairs(errs) do add(errors, "epoch " .. e) end end
  elseif k == "CheckMetamethodSlot" then
    local ok, errs = M.validate_metamethod_slot(step.slot); if not ok then for _, e in ipairs(errs) do add(errors, "slot " .. e) end end
  elseif k == "FollowIndexTable" then
    if cls(step.table) ~= RT.TableRef then add(errors, "table must be LuaRT.TableRef") end
    if type(step.depth) ~= "number" then add(errors, "depth must be number") end
  elseif k == "InvokeMetamethodCandidate" then
    if not member(step["function"], RT.ValueRef) then add(errors, "function must be LuaRT.ValueRef") end
  end
  return #errors == 0, errors
end

function M.validate_metamethod_lookup_path(path)
  local errors = {}
  if cls(path) ~= RT.MetamethodLookupPath then add(errors, "expected LuaRT.MetamethodLookupPath"); return false, errors end
  if not member(path.receiver, RT.ValueRef) then add(errors, "receiver must be LuaRT.ValueRef") end
  if not member(path.method, RT.Metamethod) then add(errors, "method must be LuaRT.Metamethod") end
  for i, step in ipairs(path.steps or {}) do
    local ok, errs = M.validate_metamethod_lookup_step(step)
    if not ok then for _, e in ipairs(errs) do add(errors, "steps[" .. i .. "] " .. e) end end
  end
  if not member(path.result, RT.MetamethodLookupResult) then add(errors, "result must be LuaRT.MetamethodLookupResult") end
  return #errors == 0, errors
end

function M.validate_metamethod_dispatch(dispatch)
  local errors = {}
  if cls(dispatch) ~= RT.MetamethodDispatch then add(errors, "expected LuaRT.MetamethodDispatch"); return false, errors end
  local ok_path, path_errors = M.validate_metamethod_lookup_path(dispatch.path)
  if not ok_path then for _, e in ipairs(path_errors) do add(errors, "path " .. e) end end
  local ok_call, call_errors = CallModel.validate_call_shape(dispatch.call)
  if not ok_call then for _, e in ipairs(call_errors) do add(errors, "call " .. e) end end
  local ok_channel, channel_errors = Arity.validate_result_channel(dispatch.result_channel)
  if not ok_channel then for _, e in ipairs(channel_errors) do add(errors, "result_channel " .. e) end end
  return #errors == 0, errors
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({
    "Metamethod", "MetatableEpoch", "MetamethodSlot", "MetamethodLookupStep",
    "MetamethodLookupResult", "MetamethodLookupPath", "MetamethodDispatch",
    "CheckReceiverMetatable", "CheckTypeMetatable", "CheckMetamethodSlot",
    "FollowIndexTable", "InvokeMetamethodCandidate",
    "MetamethodFoundResult", "MetamethodMissingResult",
  }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
