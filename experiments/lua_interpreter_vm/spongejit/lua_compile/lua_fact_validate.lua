-- lua_fact_validate.lua -- evidence-layer checks.

local Validate = require("lua_compile.validate")
local B = require("lua_compile.builders")
local T = B.T
local pvm = require("lalin.pvm")
local Payload = require("lua_compile.lua_fact_payload_lease")

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end
local function is_subject(s) return T.LuaFact.Subject.members[pvm.classof(s)] ~= nil end
local function is_predicate(p) return T.LuaFact.Predicate.members[pvm.classof(p)] ~= nil end
local function is_dependency(d) return T.LuaFact.Dependency.members[pvm.classof(d)] ~= nil end

local function validate_subject(s, errors, prefix)
  prefix = prefix or "subject"
  if not is_subject(s) then add(errors, prefix .. " is not LuaFact.Subject"); return end
  if s.kind == "SrcSlot" and pvm.classof(s.slot) ~= T.LuaSrc.Slot then add(errors, prefix .. ".slot missing") end
  if s.kind == "CanonSlot" and type(s.slot_class) ~= "number" then add(errors, prefix .. ".slot_class missing") end
  if s.kind == "Const" and pvm.classof(s.k) ~= T.LuaSrc.KRef then add(errors, prefix .. ".k missing") end
  if s.kind == "Upvalue" and pvm.classof(s.up) ~= T.LuaSrc.UpRef then add(errors, prefix .. ".up missing") end
  if s.kind == "TableValue" and type(s.id) ~= "number" then add(errors, prefix .. ".id missing") end
  if s.kind == "Callsite" and pvm.classof(s.pc) ~= T.LuaSrc.Pc then add(errors, prefix .. ".pc missing") end
  if s.kind == "Memory" and (type(s.domain) ~= "string" or s.domain == "") then add(errors, prefix .. ".domain missing") end
end

local function validate_deps(deps, errors, prefix)
  for i, d in ipairs(deps or {}) do
    if d == nil or not is_dependency(d) then add(errors, prefix .. ".deps[" .. i .. "] is not LuaFact.Dependency") end
  end
end

local function validate_fact(f, errors, i)
  local prefix = "fact[" .. i .. "]"
  if pvm.classof(f) ~= T.LuaFact.Fact then add(errors, prefix .. " is not LuaFact.Fact"); return end
  validate_subject(f.subject, errors, prefix .. ".subject")
  if not is_predicate(f.predicate) then add(errors, prefix .. ".predicate is not LuaFact.Predicate") end
  if type(f.value_key) ~= "string" then add(errors, prefix .. ".value_key must be string") end
  validate_deps(f.deps, errors, prefix)
  if f.predicate == T.LuaFact.ShapeEq and (f.value_key or "") == "" then add(errors, prefix .. " ShapeEq missing value_key") end
  if f.predicate == T.LuaFact.TargetEq and (f.value_key or "") == "" then add(errors, prefix .. " TargetEq missing value_key") end
end

function M.validate(evidence)
  local ok0, errors = Validate.lua_fact_evidence(evidence)
  errors = errors or {}
  if not ok0 then return false, errors end
  for i, f in ipairs(evidence.observed or {}) do validate_fact(f, errors, i) end
  for i, p in ipairs(evidence.payloads or {}) do
    local ok, perrs = Payload.validate(p)
    if not ok then for _, e in ipairs(perrs) do add(errors, "payload[" .. i .. "] " .. e) end end
  end
  if evidence.regions and pvm.classof(evidence.regions) ~= T.LuaRegion.RegionSet then add(errors, "evidence.regions is not LuaRegion.RegionSet") end
  return #errors == 0, errors
end

return M
