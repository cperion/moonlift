-- stencil_key.lua -- stable structural identity keys for ASDL stencil artifacts.
--
-- Stencil keys are backend-artifact keys derived from ASDL values. They must
-- not recover Lua semantics from opcode/protocol/old-backend descriptor names.

local pvm = require("moonlift.pvm")

local M = {}

local OLD_SPON_BANK = "spon" .. "bank"
local OLD_SPON_DESC = "Spon" .. "Desc"
local OLD_SPON_STENCIL = "Spon" .. "Stencil"
local OLD_OPCODE_HELPER = "Opcode" .. "Helper"
local OLD_HELPER_CALL = "Helper" .. "Call"

local FORBIDDEN_EXACT = {
  call = true,
  close = true,
  generic_for = true,
  setlist = true,
  getvarg = true,
  out_tag = true,
  out_event_kind = true,
  [OLD_SPON_BANK] = true,
  [OLD_SPON_DESC] = true,
  [OLD_SPON_STENCIL] = true,
  [OLD_OPCODE_HELPER] = true,
  [OLD_HELPER_CALL] = true,
}

local function class_name(cls, v)
  return tostring((cls and cls.__plan and cls.__plan.name) or (v and v.kind) or cls or "table")
end

local function forbidden_string_reason(s)
  s = tostring(s or "")
  local lower = s:lower()
  if FORBIDDEN_EXACT[s] or FORBIDDEN_EXACT[lower] then return "forbidden stencil key string: " .. s end
  if s:match("^OP_") or lower:match("^op_") then return "opcode-shaped stencil key string: " .. s end
  if lower:match("opcode") then return "opcode descriptor string forbidden in stencil key: " .. s end
  if lower:match("protocol") then return "protocol descriptor string forbidden in stencil key: " .. s end
  if lower:match("out_tag") or lower:match("out_event_kind") then return "out protocol string forbidden in stencil key: " .. s end
  if lower:match(OLD_SPON_BANK) then return "old backend bank string forbidden in stencil key: " .. s end
  if s:match(OLD_SPON_DESC) or s:match(OLD_SPON_STENCIL) or s:match(OLD_OPCODE_HELPER) or s:match(OLD_HELPER_CALL) then return "old backend descriptor/helper string forbidden in stencil key: " .. s end
  return nil
end

local function check_strings(v, errors, seen)
  local tv = type(v)
  if tv == "string" then
    local reason = forbidden_string_reason(v)
    if reason then errors[#errors + 1] = reason end
    return
  end
  if tv ~= "table" then return end
  seen = seen or {}; if seen[v] then return end; seen[v] = true
  local cls = pvm.classof(v)
  if cls and rawget(cls, "__fields") then
    for _, f in ipairs(cls.__fields) do check_strings(v[f.name], errors, seen) end
  elseif not cls then
    for _, x in pairs(v) do check_strings(x, errors, seen) end
  end
  seen[v] = nil
end

function M.check_no_forbidden_strings(node)
  local errors = {}
  check_strings(node, errors, {})
  return #errors == 0, errors
end

local function assert_clean(node)
  local ok, errors = M.check_no_forbidden_strings(node)
  if not ok then error(table.concat(errors, "\n"), 2) end
end

local function key_value(v, seen, field_name)
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
    for _, name in ipairs(names) do parts[#parts + 1] = tostring(name) .. "=" .. key_value(v[name], seen, name) end
    seen[v] = nil
    return table.concat(parts, "|")
  end
  local is_array = true
  local n = 0
  for k in pairs(v) do
    if type(k) ~= "number" then is_array = false; break end
    if k > n then n = k end
  end
  local parts = {}
  if is_array then
    for i = 1, n do parts[#parts + 1] = key_value(v[i], seen) end
  else
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. key_value(v[k], seen) end
  end
  seen[v] = nil
  return "[" .. table.concat(parts, ",") .. "]"
end

function M.semantic_key(node)
  assert_clean(node)
  return key_value(node, {})
end

function M.variant_key(variant)
  assert_clean(variant)
  return "Stencil.VariantKey\n" .. key_value(variant, {})
end

function M.template_key(template)
  assert_clean(template)
  return "Stencil.Template\n" .. key_value(template, {})
end

function M.representative_key(semantic_node, contract_key, variant)
  return table.concat({
    M.semantic_key(semantic_node),
    "-- LuaContract --",
    tostring(contract_key or ""),
    "-- Stencil.VariantKey --",
    M.variant_key(variant),
  }, "\n")
end

return M
