-- lua_src_window_collect.lua -- opcode stream -> LuaSrc.Window.

local B = require("lua_compile.builders")
local Decode = require("lua_compile.lua_src_from_puc_decode")

local M = {}

local function op_name(ev)
  return ev and (ev.op or ev.name or ev.opcode_name)
end

local function kflag(ev)
  return ev and ev.k ~= nil and tonumber(ev.k) ~= 0 and ev.k ~= false
end

local function needs_following_extraarg(ev)
  local op = op_name(ev)
  return op == "LOADKX" or ((op == "SETLIST" or op == "NEWTABLE") and kflag(ev))
end

local function with_following_extraarg(ev, next_ev)
  if not needs_following_extraarg(ev) or op_name(next_ev) ~= "EXTRAARG" then return ev end
  local copy = {}
  for k, v in pairs(ev) do copy[k] = v end
  copy.extraarg = next_ev.ax or next_ev.bx or 0
  return copy
end

function M.collect(events)
  events = events or {}
  local ops = {}
  for i, ev in ipairs(events) do ops[i] = Decode.decode(with_following_extraarg(ev, events[i + 1])) end
  return B.window(ops)
end

return M
