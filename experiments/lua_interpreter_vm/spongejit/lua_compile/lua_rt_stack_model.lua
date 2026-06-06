-- lua_rt_stack_model.lua -- executable LuaRT stack/window/top/sequence/vararg substrate.
--
-- This module centralizes the Moonlift runtime representation used for Lua
-- stack windows, frame top, multivalue sequences, and vararg sources.  It is
-- representation metadata only: no interpreter dispatch, no protocol tags, and
-- no hidden helpers live here.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local RT = T.LuaRT
local ValueModel = require("lua_compile.lua_rt_value_model")

local M = {}

M.STACK_TYPE_NAME = "LuaRTStack"
M.WINDOW_TYPE_NAME = "LuaRTStackWindow"
M.SEQ_TYPE_NAME = "LuaRTValueSeq"
M.VARARG_TYPE_NAME = "LuaRTVarargSource"

M.TYPE_DECL = table.concat({
  "struct LuaRTStack values: ptr(" .. ValueModel.TYPE_NAME .. "); base: i64; top: i64 end",
  "struct LuaRTStackWindow values: ptr(" .. ValueModel.TYPE_NAME .. "); base: i64; count: i64 end",
  "struct LuaRTValueSeq kind: i64; count: i64; value0: " .. ValueModel.TYPE_NAME .. "; value1: " .. ValueModel.TYPE_NAME .. "; buffer: ptr(" .. ValueModel.TYPE_NAME .. "); base: i64 end",
  "struct LuaRTVarargSource kind: i64; values: ptr(" .. ValueModel.TYPE_NAME .. "); count: i64; table_handle: i64 end",
}, "\n")

M.SEQ_KIND_ORDER = {
  "FixedSeq",
  "OpenSeq",
  "AdjustedSeq",
  "VarargSeq",
  "CallResultSeq",
}
M.SEQ_KIND = {}
for i, name in ipairs(M.SEQ_KIND_ORDER) do M.SEQ_KIND[name] = i - 1 end

M.INLINE_VALUE_COUNT = 2
function M.requires_buffer_index(index) return index >= M.INLINE_VALUE_COUNT end

M.VARARG_KIND_ORDER = {
  "NoVarargs",
  "HiddenFrameVarargs",
  "VarargTableSource",
}
M.VARARG_KIND = {}
for i, name in ipairs(M.VARARG_KIND_ORDER) do M.VARARG_KIND[name] = i - 1 end

local function kind(v) return v and v.kind or nil end

function M.seq_kind_value(name)
  local v = M.SEQ_KIND[name]
  assert(v ~= nil, "unknown LuaRT.ValueSeqKind: " .. tostring(name))
  return v
end

function M.vararg_kind_value(name)
  local v = M.VARARG_KIND[name]
  assert(v ~= nil, "unknown LuaRT.VarargSource kind: " .. tostring(name))
  return v
end

function M.kind_name_for_vararg_source(source)
  local k = kind(source)
  if k == "NoVarargs" then return "NoVarargs" end
  if k == "HiddenFrameVarargs" then return "HiddenFrameVarargs" end
  if k == "VarargTableSource" then return "VarargTableSource" end
  return nil
end

function M.validate_against_schema()
  local missing = {}
  for member in pairs((RT.ValueSeqKind and RT.ValueSeqKind.members) or {}) do
    local name = member and member.kind
    if name and M.SEQ_KIND[name] == nil then missing[#missing + 1] = "LuaRT.ValueSeqKind." .. name end
  end
  for _, name in ipairs({ "NoVarargs", "HiddenFrameVarargs", "VarargTableSource" }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT.VarargSource." .. name end
    if M.VARARG_KIND[name] == nil then missing[#missing + 1] = "LuaRTVarargSourceKind." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
