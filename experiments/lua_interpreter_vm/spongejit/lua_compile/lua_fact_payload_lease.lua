-- lua_fact_payload_lease.lua -- payload lease construction/validation.

local B = require("lua_compile.builders")
local T = B.T
local Fact = T.LuaFact
local pvm = require("lalin.pvm")

local M = {}

function M.shape(subject, pc, shape_key, deps)
  return Fact.ShapePayload(subject, type(pc) == "table" and pc or B.pc(pc), tostring(shape_key or ""), deps or {})
end
function M.field(subject, key, pc, shape_key, deps)
  return Fact.FieldPayload(subject, type(key) == "table" and key or B.k(key), type(pc) == "table" and pc or B.pc(pc), tostring(shape_key or ""), deps or {})
end
function M.array(subject, pc, deps)
  return Fact.ArrayPayload(subject, type(pc) == "table" and pc or B.pc(pc), deps or {})
end
function M.call_target(subject, pc, target_key, deps)
  return Fact.CallTargetPayload(subject, type(pc) == "table" and pc or B.pc(pc), tostring(target_key or ""), deps or {})
end
function M.static_closure_target(subject, pc, closure, target, deps)
  return Fact.StaticClosureTargetPayload(subject, type(pc) == "table" and pc or B.pc(pc), closure, target, deps or {})
end
function M.static_callee_region(subject, pc, closure, binding, region, deps)
  return Fact.StaticCalleeRegionPayload(subject, type(pc) == "table" and pc or B.pc(pc), closure, binding, region, deps or {})
end
function M.static_closure_value(subject, pc, closure, target, binding, allocation, deps)
  return Fact.StaticClosureValuePayload(subject, type(pc) == "table" and pc or B.pc(pc), closure, target, binding, allocation, deps or {})
end
function M.barrier(pc, deps)
  return Fact.BarrierPayload(type(pc) == "table" and pc or B.pc(pc), deps or {})
end

local function add(errors, msg) errors[#errors + 1] = msg end
local function is_subject(s) return T.LuaFact.Subject.members[pvm.classof(s)] ~= nil end
local function is_pc(pc) return pvm.classof(pc) == T.LuaSrc.Pc end
local function is_k(k) return pvm.classof(k) == T.LuaSrc.KRef end
local function is_closure_identity(v) return pvm.classof(v) == T.LuaRT.ClosureIdentity end
local function is_resolved_call_target(v) return pvm.classof(v) == T.LuaRT.ResolvedCallTarget end
local function is_static_region_binding(v) return pvm.classof(v) == T.LuaExec.StaticRegionBinding end
local function is_exec_region(v) return pvm.classof(v) == T.LuaExec.Region end
local function is_gc_effect(v) return T.LuaGC.GCEffect.members[pvm.classof(v)] ~= nil end
local function deps_ok(deps, errors)
  for i, d in ipairs(deps or {}) do
    if d == nil or not T.LuaFact.Dependency.members[pvm.classof(d)] then add(errors, "payload dependency " .. i .. " is not LuaFact.Dependency") end
  end
end

function M.validate(payload)
  local errors = {}
  local cls = pvm.classof(payload)
  if not T.LuaFact.PayloadLease.members[cls] then return false, { "expected LuaFact.PayloadLease" } end
  if payload.kind == "ShapePayload" then
    if not is_subject(payload.subject) then add(errors, "ShapePayload missing subject") end
    if not is_pc(payload.pc) then add(errors, "ShapePayload missing pc") end
    if type(payload.shape_key) ~= "string" or payload.shape_key == "" then add(errors, "ShapePayload missing shape_key") end
  elseif payload.kind == "FieldPayload" then
    if not is_subject(payload.subject) then add(errors, "FieldPayload missing subject") end
    if not is_k(payload.key) then add(errors, "FieldPayload missing key") end
    if not is_pc(payload.pc) then add(errors, "FieldPayload missing pc") end
    if type(payload.shape_key) ~= "string" or payload.shape_key == "" then add(errors, "FieldPayload missing shape_key") end
  elseif payload.kind == "ArrayPayload" then
    if not is_subject(payload.subject) then add(errors, "ArrayPayload missing subject") end
    if not is_pc(payload.pc) then add(errors, "ArrayPayload missing pc") end
  elseif payload.kind == "CallTargetPayload" then
    if not is_subject(payload.subject) then add(errors, "CallTargetPayload missing subject") end
    if not is_pc(payload.pc) then add(errors, "CallTargetPayload missing pc") end
    if type(payload.target_key) ~= "string" or payload.target_key == "" then add(errors, "CallTargetPayload missing target_key") end
  elseif payload.kind == "StaticClosureTargetPayload" then
    if not is_subject(payload.subject) then add(errors, "StaticClosureTargetPayload missing subject") end
    if not is_pc(payload.pc) then add(errors, "StaticClosureTargetPayload missing pc") end
    if not is_closure_identity(payload.closure) then add(errors, "StaticClosureTargetPayload missing closure identity") end
    if not is_resolved_call_target(payload.target) then add(errors, "StaticClosureTargetPayload missing resolved target") end
  elseif payload.kind == "StaticCalleeRegionPayload" then
    if not is_subject(payload.subject) then add(errors, "StaticCalleeRegionPayload missing subject") end
    if not is_pc(payload.pc) then add(errors, "StaticCalleeRegionPayload missing pc") end
    if not is_closure_identity(payload.closure) then add(errors, "StaticCalleeRegionPayload missing closure identity") end
    if not is_static_region_binding(payload.binding) then add(errors, "StaticCalleeRegionPayload missing static region binding") end
    if not is_exec_region(payload.region) then add(errors, "StaticCalleeRegionPayload missing LuaExec.Region") end
  elseif payload.kind == "StaticClosureValuePayload" then
    if not is_subject(payload.subject) then add(errors, "StaticClosureValuePayload missing subject") end
    if not is_pc(payload.pc) then add(errors, "StaticClosureValuePayload missing pc") end
    if not is_closure_identity(payload.closure) then add(errors, "StaticClosureValuePayload missing closure identity") end
    if not is_resolved_call_target(payload.target) then add(errors, "StaticClosureValuePayload missing resolved target") end
    if not is_static_region_binding(payload.binding) then add(errors, "StaticClosureValuePayload missing static region binding") end
    if not is_gc_effect(payload.allocation) then add(errors, "StaticClosureValuePayload missing GC allocation effect") end
  elseif payload.kind == "BarrierPayload" then
    if not is_pc(payload.pc) then add(errors, "BarrierPayload missing pc") end
  end
  deps_ok(payload.deps, errors)
  return #errors == 0, errors
end

return M
