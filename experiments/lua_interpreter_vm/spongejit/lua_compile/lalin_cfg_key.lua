-- lalin_cfg_key.lua -- stable structural identity key for LalinCFG kernels.

local pvm = require("lalin.pvm")
local M = {}

local function class_name(cls, v)
  return tostring((cls and cls.__plan and cls.__plan.name) or (v and v.kind) or cls or "table")
end

local function key(v, seen, field_name)
  if field_name == "contract" then return "<contract elided>" end
  local tv = type(v)
  if tv ~= "table" then return tv .. ":" .. tostring(v) end
  seen = seen or {}; if seen[v] then return "<cycle>" end; seen[v] = true
  local cls = pvm.classof(v)
  if cls then
    local names, parts = {}, { class_name(cls, v) }
    for k in pairs(v) do
      if k ~= "__slot" and k ~= "kind" and type(k) ~= "function" then names[#names + 1] = k end
    end
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
    for _, name in ipairs(names) do parts[#parts + 1] = tostring(name) .. "=" .. key(v[name], seen, name) end
    seen[v] = nil
    return table.concat(parts, "|")
  end
  local parts = {}
  for i = 1, #v do parts[#parts + 1] = key(v[i], seen) end
  seen[v] = nil
  return "[" .. table.concat(parts, ",") .. "]"
end

local phase = pvm.phase("spongejit_lalin_cfg_key", function(kernel)
  return "LalinCFG\n" .. key(kernel)
end)

function M.key(kernel) return pvm.one(phase(kernel)) end

M.phase = phase
M.key_uncached = function(kernel) return "LalinCFG\n" .. key(kernel) end

return M
