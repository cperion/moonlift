-- fragment_projection.lua -- mandatory exit projection recipes for native fragments.

local M = {}

local function copy_array(xs)
  local out = {}
  for i, x in ipairs(xs or {}) do out[i] = x end
  return out
end

function M.synced_frame(exit, source)
  return {
    kind = "SYNCED_FRAME",
    reason = exit and exit.reason or "exit",
    pc = exit and exit.pc or source or 0,
    entries = {},
  }
end

function M.box_i64(logical_slot, value_index, exit, source)
  return {
    kind = "BOX_I64",
    value_type = "I64",
    logical_slot = logical_slot,
    value_index = value_index,
    reason = exit and exit.reason or "exit",
    pc = exit and exit.pc or source or 0,
    entries = {},
  }
end

function M.for_exit(st, n, config)
  return M.synced_frame(n and n.exit, n and n.source)
end

function M.validate_projection(p)
  if type(p) ~= "table" then return false, "missing projection" end
  if p.kind ~= "SYNCED_FRAME" and p.kind ~= "BOX_I64" then return false, "unknown projection kind: " .. tostring(p.kind) end
  if p.pc == nil then return false, "projection missing pc" end
  if p.kind == "SYNCED_FRAME" and not p.entries then p.entries = {} end
  if p.entries then p.entries = copy_array(p.entries) end
  return true
end

return M
