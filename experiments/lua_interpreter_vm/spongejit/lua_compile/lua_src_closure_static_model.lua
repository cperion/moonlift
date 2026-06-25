-- lua_src_closure_static_model.lua -- strict evidence-backed source CLOSURE slice.
--
-- This module is the source-CLOSURE evidence lookup boundary.  It accepts only
-- typed no-upvalue Lua closure values with a proven direct Lua closure target,
-- static callee binding, and successful GC allocation effect.  It does not
-- allocate dynamically, capture upvalues, dispatch to the VM, or accept C/FFI/
-- metamethod targets.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local Src, Fact, RT, Exec, GC = T.LuaSrc, T.LuaFact, T.LuaRT, T.LuaExec, T.LuaGC
local StaticRegion = require("lua_compile.lua_exec_static_region_model")

local M = {}

local function cls(v) return pvm.classof(v) end
local function kind(v) return v and v.kind or nil end
local function add(errors, msg) errors[#errors + 1] = msg end
local function pc_id(pc) return tonumber(pc and pc.id or pc) or 0 end
local function slot_id(slot) return tonumber(slot and slot.id or slot) or 0 end

local function is_src_slot_subject(subject, sid)
  return subject and subject.kind == "SrcSlot" and subject.slot and subject.slot.id == sid
end

local function payload_matches(payload, closure_op)
  return payload and payload.pc and payload.pc.id == closure_op.pc.id
    and is_src_slot_subject(payload.subject, closure_op.a.id)
end

function M.find_static_closure_payload(evidence, closure_op)
  for _, payload in ipairs((evidence and evidence.payloads) or {}) do
    if kind(payload) == "StaticClosureValuePayload" and payload_matches(payload, closure_op) then
      return payload, nil
    end
  end
  return nil, { "lua_exec:source_closure_missing_static_evidence:" .. tostring(closure_op and closure_op.pc and closure_op.pc.id) .. ":StaticClosureValuePayload" }
end

local function validate_allocation(effect, errors)
  if cls(effect) ~= GC.GCAllocationEffect then
    add(errors, "source CLOSURE allocation must be LuaGC.GCAllocationEffect")
    return
  end
  if cls(effect.result) ~= GC.Allocated then
    add(errors, "source CLOSURE allocation must be successful Allocated result")
  end
end

function M.validate_static_closure_slice(closure_op, payload)
  local errors = {}
  if cls(closure_op) ~= Src.CLOSURE then add(errors, "expected LuaSrc.CLOSURE") end
  if cls(payload) ~= Fact.StaticClosureValuePayload then add(errors, "missing StaticClosureValuePayload") end
  if #errors > 0 then return false, errors end

  if not payload_matches(payload, closure_op) then add(errors, "StaticClosureValuePayload pc/subject does not match CLOSURE") end
  if cls(payload.closure) ~= RT.ClosureIdentity then add(errors, "StaticClosureValuePayload closure must be LuaRT.ClosureIdentity") end
  if cls(payload.target) ~= RT.ResolvedCallTarget then add(errors, "StaticClosureValuePayload target must be LuaRT.ResolvedCallTarget") end
  if cls(payload.binding) ~= Exec.StaticRegionBinding then add(errors, "StaticClosureValuePayload binding must be LuaExec.StaticRegionBinding") end
  validate_allocation(payload.allocation, errors)
  if #errors > 0 then return false, errors end

  local closure = payload.closure
  local target = payload.target
  if closure.proto.proto.id ~= closure_op.proto.id then
    add(errors, "source CLOSURE proto does not match ClosureIdentity proto")
  end
  if #(closure.upvalues or {}) ~= 0 then
    add(errors, "source CLOSURE with upvalues is not supported in this slice")
  end
  if cls(target.target) ~= RT.DirectLuaClosureTarget then
    add(errors, "source CLOSURE target must be DirectLuaClosureTarget, got " .. tostring(kind(target.target)))
  end
  if kind(target.identity) ~= "LuaClosureTargetIdentity" then
    add(errors, "source CLOSURE identity must be LuaClosureTargetIdentity, got " .. tostring(kind(target.identity)))
  end
  if kind(target.callable) ~= "CallableLuaClosure" then
    add(errors, "source CLOSURE callable must be CallableLuaClosure, got " .. tostring(kind(target.callable)))
  end
  if cls(target.target) == RT.DirectLuaClosureTarget and target.target.closure ~= closure.closure then
    add(errors, "source CLOSURE resolved target closure does not match ClosureIdentity")
  end
  if kind(target.identity) == "LuaClosureTargetIdentity" then
    if target.identity.closure ~= closure.closure then add(errors, "source CLOSURE identity closure does not match ClosureIdentity") end
    if target.identity.proto.id ~= closure.proto.proto.id then add(errors, "source CLOSURE identity proto does not match ClosureIdentity proto") end
    if type(target.identity.closure_handle) ~= "number" or target.identity.closure_handle < 0 then add(errors, "source CLOSURE invalid closure handle") end
  end

  local binding_ok, binding_errors = StaticRegion.validate_static_region_binding(payload.binding)
  if not binding_ok then for _, e in ipairs(binding_errors) do add(errors, "static binding " .. e) end end
  return #errors == 0, errors
end

local function build_products_uncached(closure_op, payload)
  local ok, errors = M.validate_static_closure_slice(closure_op, payload)
  if not ok then return nil, errors end
  return Exec.StaticClosureProducts(
    pc_id(closure_op.pc),
    slot_id(closure_op.a),
    closure_op.proto,
    payload.closure,
    payload.target,
    payload.binding,
    payload.allocation,
    payload.target.identity.closure_handle
  ), nil
end

local product_phase = pvm.phase("spongejit_lua_src_closure_static_products", function(closure_op, evidence)
  local payload, payload_errors = M.find_static_closure_payload(evidence, closure_op)
  if not payload then return Exec.StaticClosureProductsReject(payload_errors or { "source_closure_missing_static_evidence" }) end
  local products, errors = build_products_uncached(closure_op, payload)
  if not products then return Exec.StaticClosureProductsReject(errors or { "source_closure_products_failed" }) end
  return Exec.StaticClosureProductsOk(products)
end)

function M.products(closure_op, evidence)
  local result = pvm.one(product_phase(closure_op, evidence))
  if pvm.classof(result) == Exec.StaticClosureProductsReject then return nil, result.errors end
  return result.products, nil
end

function M.build_closure_products(closure_op, payload)
  -- Compatibility wrapper for callers that already performed payload lookup;
  -- source lowering uses M.products so the semantic product construction is a
  -- named PVM boundary.
  return build_products_uncached(closure_op, payload)
end

M.phase = product_phase
M.build_closure_products_uncached = build_products_uncached

function M.closure_payload_matches_call(closure_payload, call_payloads)
  if not closure_payload or not call_payloads or not call_payloads.target or not call_payloads.region then return false, "missing_closure_or_call_payloads" end
  local cp = closure_payload
  local target_payload, region_payload = call_payloads.target, call_payloads.region
  if target_payload.closure.closure ~= cp.closure.closure then return false, "closure_ref_mismatch" end
  if target_payload.closure.proto.proto.id ~= cp.closure.proto.proto.id then return false, "closure_proto_mismatch" end
  if target_payload.target.identity.closure_handle ~= cp.target.identity.closure_handle then return false, "closure_handle_mismatch" end
  if region_payload.binding.region.id.name.text ~= cp.binding.region.id.name.text then return false, "static_binding_region_mismatch" end
  return true
end

return M
