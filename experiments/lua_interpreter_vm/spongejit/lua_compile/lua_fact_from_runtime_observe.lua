-- lua_fact_from_runtime_observe.lua -- runtime observations -> LuaFact.Evidence.
--
-- This module is the stable evidence import boundary for runtime samples.  It
-- accepts plain Lua records with explicit subject/predicate/dependency/payload
-- fields and produces LuaFact ASDL values.  It does not adapt quarantined
-- execution APIs.

local B = require("lua_compile.builders")
local T = B.T
local Fact = T.LuaFact
local Compile = T.LuaCompile
local pvm = require("lalin.pvm")
local Closure = require("lua_compile.lua_fact_closure")

local M = {}

local function norm(s)
  return tostring(s or ""):gsub("([a-z0-9])([A-Z])", "%1_%2"):lower():gsub("[%s%-]+", "_")
end

local PRED = {
  is_nil = Fact.IsNil, nil_ = Fact.IsNil, nil_value = Fact.IsNil,
  is_false = Fact.IsFalse, false_ = Fact.IsFalse,
  is_true = Fact.IsTrue, true_ = Fact.IsTrue,
  is_bool = Fact.IsBool, bool = Fact.IsBool,
  is_i64 = Fact.IsI64, i64 = Fact.IsI64,
  is_f64 = Fact.IsF64, f64 = Fact.IsF64,
  is_number = Fact.IsNumber, number = Fact.IsNumber,
  is_string = Fact.IsString, string = Fact.IsString, str = Fact.IsString,
  is_table = Fact.IsTable, table = Fact.IsTable,
  is_closure = Fact.IsClosure, closure = Fact.IsClosure,
  nonzero_i64 = Fact.NonZeroI64, non_zero_i64 = Fact.NonZeroI64,
  const_i64 = Fact.ConstI64,
  const_f64 = Fact.ConstF64,
  key_const = Fact.KeyConst,
  shape_known = Fact.ShapeKnown,
  shape_eq = Fact.ShapeEq,
  metatable_absent = Fact.MetatableAbsent,
  field_offset = Fact.FieldOffset,
  array_hit = Fact.ArrayHit,
  bounds_ok = Fact.BoundsOk,
  array_base_offset = Fact.ArrayBaseOffset,
  array_len_offset = Fact.ArrayLenOffset,
  known_call_target = Fact.KnownCallTarget,
  target_eq = Fact.TargetEq,
  barrier_clean = Fact.BarrierClean,
}

local DEP = {
  shape_epoch = Fact.ShapeEpoch,
  metatable_epoch = Fact.MetatableEpoch,
  const_epoch = Fact.ConstEpoch,
  upvalue_epoch = Fact.UpvalueEpoch,
  table_epoch = Fact.TableEpoch,
  call_target_epoch = Fact.CallTargetEpoch,
  gc_barrier_protocol = Fact.GcBarrierProtocol,
  vm_abi_epoch = Fact.VmAbiEpoch,
}

local PAYLOAD = {
  shape = "shape", shape_payload = "shape",
  field = "field", field_payload = "field",
  array = "array", array_payload = "array",
  call_target = "call_target", calltarget = "call_target", call_target_payload = "call_target",
  static_closure_target = "static_closure_target", static_closure_target_payload = "static_closure_target",
  static_callee_region = "static_callee_region", static_callee_region_payload = "static_callee_region",
  static_closure_value = "static_closure_value", static_closure_value_payload = "static_closure_value",
  barrier = "barrier", barrier_payload = "barrier",
}

function M.field_value_key(shape_key, key)
  local kid = type(key) == "table" and key.id or key
  return tostring(shape_key or "") .. ":k" .. tostring(kid or 0)
end

local function as_number(v)
  if type(v) == "table" then v = v.id or v.value or v.slot or v.k or v.up or v.pc end
  return tonumber(tostring(v or "0"):match("%-?%d+")) or 0
end

local function as_pc(v) return type(v) == "table" and v or B.pc(as_number(v)) end
local function as_slot(v) return type(v) == "table" and v or B.slot(as_number(v)) end
local function as_k(v) return type(v) == "table" and v or B.k(as_number(v)) end
local function as_up(v) return type(v) == "table" and v or B.up(as_number(v)) end

function M.deps(xs)
  if xs == nil then return {} end
  if type(xs) ~= "table" then xs = { xs } end
  local out = {}
  for _, d in ipairs(xs) do
    if d ~= nil then
      if T.LuaFact.Dependency.members[pvm.classof(d)] then
        out[#out + 1] = d
      else
        out[#out + 1] = DEP[norm(d)] or d
      end
    end
  end
  return out
end

function M.predicate(x)
  if T.LuaFact.Predicate.members[pvm.classof(x)] then return x end
  return PRED[norm(x)]
end

local function subject_from_table(s)
  if T.LuaFact.Subject.members[pvm.classof(s)] then return s end
  local k = norm(s.kind or s.type or s.subject_kind)
  if k == "src_slot" or k == "slot" or k == "r" then return Fact.SrcSlot(as_slot(s.slot or s.id or s.value or s.n)) end
  if k == "canon_slot" or k == "canonical_slot" or k == "value" then return Fact.CanonSlot(as_number(s.slot_class or s.class or s.id or s.value)) end
  if k == "const" or k == "k" or k == "kref" then return Fact.Const(as_k(s.k or s.const or s.id or s.value)) end
  if k == "upvalue" or k == "up" or k == "upref" then return Fact.Upvalue(as_up(s.up or s.upvalue or s.id or s.value)) end
  if k == "table_value" or k == "tablevalue" then return Fact.TableValue(as_number(s.table_value or s.table_id or s.id or s.value)) end
  if k == "callsite" or k == "call_site" then return Fact.Callsite(as_pc(s.pc or s.id or s.value)) end
  if k == "memory" or k == "mem" then return Fact.Memory(tostring(s.domain or s.id or s.value or "")) end
  if k == "global" then return Fact.Global end
  return nil
end

function M.subject(obs)
  if T.LuaFact.Subject.members[pvm.classof(obs)] then return obs end
  if type(obs) ~= "table" then return Fact.Global end
  if obs.subject ~= nil then
    if type(obs.subject) == "table" then
      local s = subject_from_table(obs.subject); if s then return s end
    elseif obs.subject == "global" then
      return Fact.Global
    end
  end
  local direct = subject_from_table(obs)
  if direct then return direct end
  if obs.slot ~= nil then return Fact.SrcSlot(as_slot(obs.slot)) end
  if obs.src_slot ~= nil then return Fact.SrcSlot(as_slot(obs.src_slot)) end
  if obs.canon_slot ~= nil or obs.slot_class ~= nil then return Fact.CanonSlot(as_number(obs.canon_slot or obs.slot_class)) end
  if obs.up ~= nil or obs.upvalue ~= nil then return Fact.Upvalue(as_up(obs.up or obs.upvalue)) end
  if obs.k ~= nil or obs.const ~= nil then return Fact.Const(as_k(obs.k or obs.const)) end
  if obs.table_value ~= nil or obs.table_id ~= nil then return Fact.TableValue(as_number(obs.table_value or obs.table_id)) end
  if obs.callsite ~= nil or obs.callsite_pc ~= nil then return Fact.Callsite(as_pc(obs.callsite or obs.callsite_pc)) end
  if obs.memory ~= nil or obs.domain ~= nil then return Fact.Memory(tostring(obs.memory or obs.domain)) end
  if obs.global == true then return Fact.Global end
  return Fact.Global
end

function M.value_key(obs, pred)
  if obs.value_key ~= nil then return tostring(obs.value_key) end
  if pred == Fact.ShapeEq or pred == Fact.ShapeKnown or pred == Fact.MetatableAbsent then
    return tostring(obs.shape_key or obs.shape or obs.value or "")
  end
  if pred == Fact.FieldOffset then
    if obs.shape_key ~= nil and (obs.key ~= nil or obs.k ~= nil or obs.const ~= nil) then
      return M.field_value_key(obs.shape_key, obs.key or obs.k or obs.const)
    end
    return tostring(obs.field_key or obs.offset_key or obs.value or "")
  end
  if pred == Fact.ArrayLenOffset then
    return tostring(obs.shape_key or obs.shape or obs.value or "")
  end
  if pred == Fact.KeyConst then
    return tostring(obs.key or obs.k or obs.const or obs.value or "")
  end
  if pred == Fact.KnownCallTarget or pred == Fact.TargetEq then
    return tostring(obs.target_key or obs.target or obs.value or "")
  end
  if pred == Fact.ConstI64 or pred == Fact.ConstF64 then
    return tostring(obs.value or obs.const_value or "")
  end
  if pred == Fact.BarrierClean and obs.pc ~= nil then
    return tostring(obs.value or obs.barrier_key or "")
  end
  return tostring(obs.value or "")
end

function M.payload_kind(obs)
  return PAYLOAD[norm(obs.payload or obs.payload_kind or obs.lease or obs.lease_kind or obs.kind)]
end

function M.payload(obs)
  local kind = M.payload_kind(obs)
  if not kind then return nil end
  local s = M.subject(obs)
  if kind == "shape" then
    return Fact.ShapePayload(s, as_pc(obs.pc), tostring(obs.shape_key or obs.value_key or obs.value or ""), M.deps(obs.deps))
  elseif kind == "field" then
    return Fact.FieldPayload(s, as_k(obs.key or obs.k or obs.const), as_pc(obs.pc), tostring(obs.shape_key or obs.value_key or obs.value or ""), M.deps(obs.deps))
  elseif kind == "array" then
    return Fact.ArrayPayload(s, as_pc(obs.pc), M.deps(obs.deps))
  elseif kind == "call_target" then
    return Fact.CallTargetPayload(s, as_pc(obs.pc), tostring(obs.target_key or obs.value_key or obs.value or ""), M.deps(obs.deps))
  elseif kind == "static_closure_target" then
    return Fact.StaticClosureTargetPayload(s, as_pc(obs.pc), obs.closure, obs.target, M.deps(obs.deps))
  elseif kind == "static_callee_region" then
    return Fact.StaticCalleeRegionPayload(s, as_pc(obs.pc), obs.closure, obs.binding, obs.region, M.deps(obs.deps))
  elseif kind == "static_closure_value" then
    return Fact.StaticClosureValuePayload(s, as_pc(obs.pc), obs.closure, obs.target, obs.binding, obs.allocation or obs.gc_effect or obs.effect, M.deps(obs.deps))
  elseif kind == "barrier" then
    return Fact.BarrierPayload(as_pc(obs.pc), M.deps(obs.deps))
  end
  return nil
end

function M.records_from_observation(obs)
  local out = {}
  if T.LuaFact.Fact == pvm.classof(obs) then
    out[#out + 1] = Compile.EvidenceFact(obs)
    return out
  end
  if T.LuaFact.PayloadLease.members[pvm.classof(obs)] then
    out[#out + 1] = Compile.EvidencePayload(obs)
    return out
  end
  local p = M.payload(obs)
  if p then out[#out + 1] = Compile.EvidencePayload(p) end
  local pred = M.predicate(obs and (obs.predicate or (not p and obs.kind) or obs.fact))
  if pred then
    out[#out + 1] = Compile.EvidenceFact(Fact.Fact(M.subject(obs), pred, M.value_key(obs, pred), M.deps(obs.deps)))
  end
  return out
end

function M.evidence_input(observations, regions)
  if pvm.classof(observations) == Compile.EvidenceInput then return observations end
  local records = {}
  for _, obs in ipairs(observations or {}) do
    for _, r in ipairs(M.records_from_observation(obs)) do records[#records + 1] = r end
  end
  return Compile.EvidenceInput(records, regions or B.region_set({}))
end

local phase = pvm.phase("spongejit_lua_fact_import_evidence", function(input)
  local facts, payloads = {}, {}
  for _, record in ipairs((input and input.records) or {}) do
    local cls = pvm.classof(record)
    if cls == Compile.EvidenceFact then facts[#facts + 1] = record.fact
    elseif cls == Compile.EvidencePayload then payloads[#payloads + 1] = record.payload end
  end
  return Closure.close(Fact.Evidence(facts, payloads, (input and input.regions) or B.region_set({})))
end)

function M.import(input)
  return pvm.one(phase(input))
end

function M.observe(observations, regions)
  return M.import(M.evidence_input(observations or {}, regions))
end

M.phase = phase
M.PREDICATE_ALIASES = PRED
M.DEPENDENCY_ALIASES = DEP
M.PAYLOAD_ALIASES = PAYLOAD
return M
