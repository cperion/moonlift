-- lua_rt_value_model.lua -- explicit LuaRT TValue runtime representation.
--
-- This module centralizes the mapping from ASDL-visible LuaRT value tag
-- constructors to the Lalin runtime value struct used by LalinCFG emission.
-- It is representation metadata only: no helper calls, interpreter dispatch, or
-- semantic fallback live here.

local pvm = require("lalin.pvm")
local B = require("lua_compile.builders")
local T = B.T
local RT = T.LuaRT

local M = {}

M.TYPE_NAME = "LuaRTValue"
M.TYPE_DECL = "struct LuaRTValue tag: i64; payload_i64: i64; payload_f64: f64 end"
M.FFI_CDEF = [[
typedef struct { int64_t tag; int64_t payload_i64; double payload_f64; } LuaRTValue;
]]
M.TAG_FIELD = "tag"
M.PAYLOAD_I64_FIELD = "payload_i64"
M.PAYLOAD_F64_FIELD = "payload_f64"

M.TAG_ORDER = {
  "NilTag",
  "EmptySlotTag",
  "AbsentKeyTag",
  "NoTableTag",
  "FalseTag",
  "TrueTag",
  "IntegerTag",
  "FloatTag",
  "ShortStringTag",
  "LongStringTag",
  "TableTag",
  "LuaClosureTag",
  "CClosureTag",
  "LightCFunctionTag",
  "UserdataTag",
  "LightUserdataTag",
  "ThreadTag",
  "CDataTag",
}

M.TAG = {}
for i, name in ipairs(M.TAG_ORDER) do M.TAG[name] = i - 1 end

M.NIL_KIND_TAG = {
  OrdinaryNil = "NilTag",
  EmptySlotSentinel = "EmptySlotTag",
  AbsentKeySentinel = "AbsentKeyTag",
  NoTableSentinel = "NoTableTag",
}

M.NIL_KIND_PAYLOAD = {
  OrdinaryNil = 0,
  EmptySlotSentinel = 1,
  AbsentKeySentinel = 2,
  NoTableSentinel = 3,
}

local function kind(v) return v and v.kind or nil end

function M.tag_value(tag_name)
  local v = M.TAG[tag_name]
  assert(v ~= nil, "unknown LuaRT tag: " .. tostring(tag_name))
  return v
end

function M.tag_name_for_nil_kind(nil_kind)
  local k = kind(nil_kind)
  return M.NIL_KIND_TAG[k]
end

function M.payload_for_nil_kind(nil_kind)
  return M.NIL_KIND_PAYLOAD[kind(nil_kind)] or 0
end

function M.tag_name_for_tvalue(tv)
  local cls = pvm.classof(tv)
  if cls == RT.NilValue then return M.tag_name_for_nil_kind(tv.kind) end
  if cls == RT.BoolValue then return (tv.kind == RT.LuaTrue or kind(tv.kind) == "LuaTrue") and "TrueTag" or "FalseTag" end
  if cls == RT.IntValue then return "IntegerTag" end
  if cls == RT.FloatValue then return "FloatTag" end
  if cls == RT.StringValue then return (tv.kind == RT.LongString or kind(tv.kind) == "LongString") and "LongStringTag" or "ShortStringTag" end
  if cls == RT.TableValueNode then return "TableTag" end
  if cls == RT.LuaClosureValue then return "LuaClosureTag" end
  if cls == RT.CClosureValue then return "CClosureTag" end
  if cls == RT.LightCFunctionValue then return "LightCFunctionTag" end
  if cls == RT.UserdataValueNode then return "UserdataTag" end
  if cls == RT.LightUserdataValue then return "LightUserdataTag" end
  if cls == RT.ThreadValueNode then return "ThreadTag" end
  if RT.CDataValueNode and cls == RT.CDataValueNode then return "CDataTag" end
  return nil
end

function M.payload_i64_for_tvalue(tv)
  local cls = pvm.classof(tv)
  if cls == RT.NilValue then return M.payload_for_nil_kind(tv.kind) end
  if cls == RT.BoolValue then return (tv.kind == RT.LuaTrue or kind(tv.kind) == "LuaTrue") and 1 or 0 end
  if cls == RT.IntValue then return tonumber(tv.value) or 0 end
  -- Reference-bearing TValue nodes carry handles in payload_i64 when a handle is
  -- available. Structural ASDL refs are not runtime addresses, so constants use
  -- 0 until a later allocation/symbol lowering patches a real handle.
  return 0
end

function M.payload_f64_for_tvalue(tv)
  if pvm.classof(tv) == RT.FloatValue then return tonumber(tv.value) or 0 end
  return 0
end

M.TYPE_TEST_TAGS = {
  IsNil = { "NilTag" },
  IsOrdinaryNil = { "NilTag" },
  IsFalse = { "FalseTag" },
  IsFalsey = { "NilTag", "FalseTag" },
  IsTruthy = { "EmptySlotTag", "AbsentKeyTag", "NoTableTag", "TrueTag", "IntegerTag", "FloatTag", "ShortStringTag", "LongStringTag", "TableTag", "LuaClosureTag", "CClosureTag", "LightCFunctionTag", "UserdataTag", "LightUserdataTag", "ThreadTag", "CDataTag" },
  IsBoolean = { "FalseTag", "TrueTag" },
  IsInteger = { "IntegerTag" },
  IsFloat = { "FloatTag" },
  IsNumber = { "IntegerTag", "FloatTag" },
  IsString = { "ShortStringTag", "LongStringTag" },
  IsTable = { "TableTag" },
  IsLuaClosure = { "LuaClosureTag" },
  IsCClosure = { "CClosureTag" },
  IsFunction = { "LuaClosureTag", "CClosureTag", "LightCFunctionTag" },
  IsUserdata = { "UserdataTag" },
  IsThread = { "ThreadTag" },
  IsCData = { "CDataTag" },
  IsCollectable = { "ShortStringTag", "LongStringTag", "TableTag", "LuaClosureTag", "CClosureTag", "UserdataTag", "ThreadTag", "CDataTag" },
  IsAbsentKey = { "AbsentKeyTag" },
  IsEmptySlot = { "EmptySlotTag" },
}

function M.tags_for_type_test(test)
  return M.TYPE_TEST_TAGS[kind(test)]
end

function M.validate_against_schema()
  local missing = {}
  for member in pairs(RT.ValueTag.members or {}) do
    local singleton = member
    local name = singleton and singleton.kind
    if name and M.TAG[name] == nil then missing[#missing + 1] = name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
