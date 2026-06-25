-- lua_rt_outcome_model.lua -- executable Lua outcome representation.
--
-- This module centralizes the mapping from ASDL-visible outcome/error/yield
-- constructors to the Lalin runtime outcome struct used by LalinCFG emission.
-- It is representation metadata only: no protocol tags, no out params, and no
-- host/interpreter resume dispatch live here.

local B = require("lua_compile.builders")
local T = B.T
local CFG, RT = T.LalinCFG, T.LuaRT
local ValueModel = require("lua_compile.lua_rt_value_model")

local M = {}

M.TYPE_NAME = "LuaRTOutcome"
M.TYPE_DECL = table.concat({
  "struct LuaRTOutcome",
  "  kind: i64; count: i64; value0: " .. ValueModel.TYPE_NAME .. "; value1: " .. ValueModel.TYPE_NAME .. ";",
  "  error_kind: i64; error_value: " .. ValueModel.TYPE_NAME .. "; saved_pc: i64; saved_top: i64; yield_kind: i64; value_buffer: ptr(" .. ValueModel.TYPE_NAME .. "); value_base: i64",
  "end",
}, "\n")

M.OUTCOME_KIND_ORDER = {
  "NormalReturnOutcome",
  "LuaErrorOutcome",
  "LuaYieldOutcome",
}
M.OUTCOME_KIND = {}
for i, name in ipairs(M.OUTCOME_KIND_ORDER) do M.OUTCOME_KIND[name] = i - 1 end

M.ERROR_KIND_ORDER = {
  "TypeError",
  "ArithmeticError",
  "CompareError",
  "TableIndexNilError",
  "TableIndexNaNError",
  "NotCallableError",
  "CloseError",
  "RuntimeError",
  "ErrNnilError",
}
M.ERROR_KIND = {}
for i, name in ipairs(M.ERROR_KIND_ORDER) do M.ERROR_KIND[name] = i - 1 end

M.YIELD_KIND_ORDER = {
  "ResumeCall",
  "ResumeMetamethod",
  "ResumeTableGet",
  "ResumeTableSet",
  "ResumeArithmetic",
  "ResumeComparison",
  "ResumeConcat",
  "ResumeClose",
  "ResumeReturn",
  "ResumeTForCall",
}
M.YIELD_KIND = {}
for i, name in ipairs(M.YIELD_KIND_ORDER) do M.YIELD_KIND[name] = i - 1 end

local function kind(v) return v and v.kind or nil end

function M.outcome_kind_value(name)
  local v = M.OUTCOME_KIND[name]
  assert(v ~= nil, "unknown Lua outcome kind: " .. tostring(name))
  return v
end

function M.error_kind_value(error_kind)
  local k = kind(error_kind)
  local v = M.ERROR_KIND[k]
  assert(v ~= nil, "unknown LuaRT.ErrorKind: " .. tostring(k))
  return v
end

function M.yield_kind_value(resume_point)
  local k = kind(resume_point)
  local v = M.YIELD_KIND[k]
  assert(v ~= nil, "unknown LuaRT.ResumePoint: " .. tostring(k))
  return v
end

function M.validate_against_schema()
  local missing = {}
  for member in pairs((CFG.OutcomeKind and CFG.OutcomeKind.members) or {}) do
    local name = member and member.kind
    if name and M.OUTCOME_KIND[name] == nil then missing[#missing + 1] = "LalinCFG.OutcomeKind." .. name end
  end
  for member in pairs(RT.ErrorKind.members or {}) do
    local name = member and member.kind
    if name and M.ERROR_KIND[name] == nil then missing[#missing + 1] = "LuaRT.ErrorKind." .. name end
  end
  for member in pairs(RT.ResumePoint.members or {}) do
    local name = member and member.kind
    if name and M.YIELD_KIND[name] == nil then missing[#missing + 1] = "LuaRT.ResumePoint." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
