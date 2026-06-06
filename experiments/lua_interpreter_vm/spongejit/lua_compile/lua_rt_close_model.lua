-- lua_rt_close_model.lua -- close/TBC, outcome cause, and close ordering products.
-- Structural validation only; close execution remains fail-closed until lowered explicitly.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local RT = T.LuaRT
local Arity = require("lua_compile.lua_rt_arity_model")

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function kind(v) return v and v.kind or nil end
local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate_outcome_cause(cause)
  local errors = {}
  if not member(cause, RT.OutcomeCause) then add(errors, "expected LuaRT.OutcomeCause"); return false, errors end
  local k = kind(cause)
  if k == "CallCause" and cls(cause.call) ~= RT.CallRef then add(errors, "call must be LuaRT.CallRef") end
  if k == "MetamethodCause" and cls(cause.path) ~= RT.MetamethodLookupPath then add(errors, "path must be LuaRT.MetamethodLookupPath") end
  if k == "IteratorCause" and not member(cause.topology, RT.LoopTopology) then add(errors, "topology must be LuaRT.LoopTopology") end
  if k == "CloseCause" and cls(cause.chain) ~= RT.CloseChain then add(errors, "chain must be LuaRT.CloseChain") end
  if (k == "FinalizerCause" or k == "AllocationCause") and cls(cause[k == "FinalizerCause" and "finalizer" or "allocation"]) ~= RT.Name then add(errors, "name field must be LuaRT.Name") end
  return #errors == 0, errors
end

function M.validate_close_action(action)
  local errors = {}
  if not member(action, RT.CloseAction) then add(errors, "expected LuaRT.CloseAction"); return false, errors end
  local k = kind(action)
  if k == "CloseSkipFalsey" then
    if cls(action.item) ~= RT.CloseItem then add(errors, "item must be LuaRT.CloseItem") end
  elseif k == "CloseLookupMethod" then
    if cls(action.item) ~= RT.CloseItem then add(errors, "item must be LuaRT.CloseItem") end
    if cls(action.path) ~= RT.MetamethodLookupPath then add(errors, "path must be LuaRT.MetamethodLookupPath") end
  elseif k == "CloseInvokeMethod" then
    if cls(action.item) ~= RT.CloseItem then add(errors, "item must be LuaRT.CloseItem") end
    if cls(action.call) ~= RT.CallShape then add(errors, "call must be LuaRT.CallShape") end
  elseif k == "ClosePropagateOriginal" then
    local ok, errs = Arity.validate_result_bundle(action.result)
    if not ok then for _, e in ipairs(errs) do add(errors, "result " .. e) end end
  elseif k == "CloseReplaceWithError" then
    if cls(action.error) ~= RT.ErrorState then add(errors, "error must be LuaRT.ErrorState") end
  elseif k == "CloseYieldAndResume" then
    if cls(action.yield) ~= RT.YieldState then add(errors, "yield must be LuaRT.YieldState") end
  end
  return #errors == 0, errors
end

function M.validate_close_plan(plan)
  local errors = {}
  if cls(plan) ~= RT.ClosePlan then add(errors, "expected LuaRT.ClosePlan"); return false, errors end
  if cls(plan.chain) ~= RT.CloseChain then add(errors, "chain must be LuaRT.CloseChain") end
  local ok_cause, cause_errors = M.validate_outcome_cause(plan.cause)
  if not ok_cause then for _, e in ipairs(cause_errors) do add(errors, "cause " .. e) end end
  for i, action in ipairs(plan.actions or {}) do
    local ok, errs = M.validate_close_action(action)
    if not ok then for _, e in ipairs(errs) do add(errors, "actions[" .. i .. "] " .. e) end end
  end
  local ok_result, result_errors = Arity.validate_result_bundle(plan.pending_result)
  if not ok_result then for _, e in ipairs(result_errors) do add(errors, "pending_result " .. e) end end
  return #errors == 0, errors
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({ "CloseState", "OutcomeCause", "CloseAction", "ClosePlan", "DirectReturnCause", "CallCause", "CloseLookupMethod", "CloseInvokeMethod", "ClosePropagateOriginal" }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
