-- lua_region_validate.lua -- LuaRegion topology invariants.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local Region = T.LuaRegion

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate(region_set)
  local errors = {}
  if pvm.classof(region_set) ~= Region.RegionSet then add(errors, "expected LuaRegion.RegionSet") end
  for i, r in ipairs((region_set and region_set.regions) or {}) do
    local cls = pvm.classof(r)
    if not Region.Region.members[cls] then add(errors, "region " .. i .. " is not LuaRegion.Region") end
    if #(r.edges or {}) == 0 then add(errors, "region " .. i .. " has no edges") end
    if r.slots and r.slots.first.id > r.slots.last.id then add(errors, "region " .. i .. " has invalid slot window") end
  end
  return #errors == 0, errors
end

return M
