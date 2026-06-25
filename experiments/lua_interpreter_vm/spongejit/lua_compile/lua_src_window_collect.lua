-- lua_src_window_collect.lua -- opcode stream -> LuaSrc.Window.

local B = require("lua_compile.builders")
local pvm = require("lalin.pvm")
local Decode = require("lua_compile.lua_src_from_puc_decode")
local Compile = B.T.LuaCompile

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

local function canonical_plain_with_extra(ev, next_ev)
  return Decode.canonical_event(with_following_extraarg(ev, next_ev))
end

function M.event_batch(events)
  if pvm.classof(events) == Compile.SourceEventBatch then return events end
  events = events or {}
  local out = {}
  for i, ev in ipairs(events) do
    if pvm.classof(ev) == Compile.CanonicalPucEvent or pvm.classof(ev) == Compile.DecodedSourceOp then
      out[i] = ev
    else
      out[i] = canonical_plain_with_extra(ev, events[i + 1])
    end
  end
  return Compile.SourceEventBatch(out)
end

local phase = pvm.phase("spongejit_lua_src_collect_window", function(batch)
  local ops = {}
  for i, ev in ipairs((batch and batch.events) or {}) do ops[i] = Decode.decode_event(ev) end
  return B.window(ops)
end)

function M.collect(events)
  return pvm.one(phase(M.event_batch(events or {})))
end

M.phase = phase
return M
