-- lua_compile/lua_rt_validate.lua -- structural checks for LuaRT semantic ASDL.
--
-- These validators establish the semantic foundation only. They do not lower
-- opcodes, invoke runtime helpers, or bless interpreter/protocol handoffs.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local RT = T.LuaRT

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

return M
