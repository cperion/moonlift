-- lua_src_slot_alias.lua -- source slot inventory helpers.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local Src = T.LuaSrc

local M = {}

local function add_slot(out, s)
  if pvm.classof(s) == Src.Slot then out[s.id] = s end
end

local function walk(v, out, seen)
  if type(v) ~= "table" then return end
  seen = seen or {}; if seen[v] then return end; seen[v] = true
  if pvm.classof(v) == Src.Slot then add_slot(out, v); return end
  local cls = pvm.classof(v)
  if cls and cls.__fields then for _, f in ipairs(cls.__fields) do walk(v[f.name], out, seen) end
  elseif not cls then for _, x in pairs(v) do walk(x, out, seen) end end
end

function M.inventory(window)
  local by_id = {}
  walk(window, by_id)
  local ids = {}
  for id in pairs(by_id) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = by_id[id] end
  return out
end

return M
