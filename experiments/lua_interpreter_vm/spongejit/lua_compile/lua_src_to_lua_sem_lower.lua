-- lua_src_to_lua_sem_lower.lua -- LuaSrc.Window + LuaFact.Evidence -> LuaSem.Result.
--
-- LuaSem consumes opcode meaning. Unsupported cases are structured rejections,
-- not fallback helpers or descriptor stubs. Every real LuaSrc.Op alternative is
-- present in the semantic decision table below.

local B = require("lua_compile.builders")
local T = B.T
local Src, Sem, Fact = T.LuaSrc, T.LuaSem, T.LuaFact
local pvm = require("moonlift.pvm")
local Env = require("lua_compile.lua_sem_env")
local Guard = require("lua_compile.lua_sem_guard")
local Write = require("lua_compile.lua_sem_write")
local Reject = require("lua_compile.lua_sem_reject")
local Contradiction = require("lua_compile.lua_fact_contradiction")
local RuntimeImport = require("lua_compile.lua_fact_from_runtime_observe")

local M = {}

local function subject_key(s)
  if s.kind == "SrcSlot" then return "slot:" .. s.slot.id end
  if s.kind == "Const" then return "const:" .. s.k.id end
  if s.kind == "CanonSlot" then return "canon:" .. s.slot_class end
  if s.kind == "Upvalue" then return "up:" .. s.up.id end
  if s.kind == "TableValue" then return "table:" .. s.id end
  if s.kind == "Memory" then return "mem:" .. s.domain end
  if s.kind == "Callsite" then return "call:" .. s.pc.id end
  if s.kind == "Global" then return "global" end
  return tostring(s.kind)
end

local function evidence_index(evidence)
  local idx = { payloads = (evidence and evidence.payloads) or {}, facts = {} }
  for _, f in ipairs((evidence and evidence.observed) or {}) do
    local sk = subject_key(f.subject)
    idx.facts[sk] = idx.facts[sk] or {}
    local pk = f.predicate.kind
    idx.facts[sk][pk] = idx.facts[sk][pk] or {}
    idx.facts[sk][pk][#idx.facts[sk][pk] + 1] = f
  end
  return idx
end
local function has(idx, subject, pred, value_key)
  local list = idx.facts[subject_key(subject)] and idx.facts[subject_key(subject)][pred.kind]
  if not list then return nil end
  if value_key == nil then return list[1] end
  value_key = tostring(value_key)
  for _, f in ipairs(list) do if tostring(f.value_key or "") == value_key then return f end end
  return nil
end
local function missing(subject, pred, value_key) return Fact.Fact(subject, pred, value_key or "", {}) end

local function i64_atom_for_slot(env, slot)
  env:alias(slot)
  return Sem.AtomI64(Sem.SlotI64(env:slot_class(slot)))
end
local function i64_imm(n) return Sem.AtomI64(Sem.ImmI64(type(n) == "table" and n or B.imm(n))) end
local function box_i64(x) return Sem.BoxI64(x) end
local function box_f64(x) return Sem.BoxF64(x) end
local function affine(terms, constant) return Sem.AffineI64(terms or {}, constant or 0) end
local function term(c, atom)
  if atom.kind == "AtomI64" then atom = atom.atom end
  return Sem.I64Term(c, atom)
end

local function const_i64_from_evidence(idx, k)
  local f = has(idx, Fact.Const(k), Fact.ConstI64)
  if f and tostring(f.value_key or ""):match("^-?%d+$") then return tonumber(f.value_key) end
  return nil
end

local function has_const_f64(ctx, k)
  return has(ctx.idx, Fact.Const(k), Fact.ConstF64) ~= nil
end

local function missing_payload(kind, subject, op, key)
  if kind == "shape" then return Fact.ShapePayload(subject, op.pc, "", {}) end
  if kind == "field" then return Fact.FieldPayload(subject, key or B.k(0), op.pc, "", {}) end
  if kind == "array" then return Fact.ArrayPayload(subject, op.pc, {}) end
  if kind == "barrier" then return Fact.BarrierPayload(op.pc, {}) end
  return nil
end

local function find_payload(ctx, kind, subject, key, shape_key)
  for _, p in ipairs(ctx.idx.payloads or {}) do
    if kind == "shape" and p.kind == "ShapePayload" and subject_key(p.subject) == subject_key(subject)
       and (shape_key == nil or p.shape_key == shape_key) then return p end
    if kind == "field" and p.kind == "FieldPayload" and subject_key(p.subject) == subject_key(subject)
       and p.key.id == key.id and (shape_key == nil or p.shape_key == shape_key) then return p end
    if kind == "array" and p.kind == "ArrayPayload" and subject_key(p.subject) == subject_key(subject) then return p end
    if kind == "call_target" and p.kind == "CallTargetPayload" and subject_key(p.subject) == subject_key(subject)
       and (shape_key == nil or p.target_key == shape_key) then return p end
  end
  return nil
end

local function find_barrier_payload(ctx, op)
  for _, p in ipairs(ctx.idx.payloads or {}) do
    if p.kind == "BarrierPayload" and p.pc.id == op.pc.id then return p end
  end
  return nil
end

local function require_fact(ctx, op, subject, pred, value, value_key)
  local f = has(ctx.idx, subject, pred, value_key)
  if not f then return nil, missing(subject, pred, value_key) end
  ctx.effects[#ctx.effects + 1] = Guard.observe(Guard.fact_guard(subject, pred, value, f.deps or {}, op.pc, value_key or f.value_key or ""))
  return f
end

local function require_i64(ctx, op, slot)
  local subject = Fact.SrcSlot(slot)
  local f = has(ctx.idx, subject, Fact.IsI64)
  if not f then return nil, missing(subject, Fact.IsI64) end
  ctx.effects[#ctx.effects + 1] = Guard.observe(Guard.fact_guard(subject, Fact.IsI64, Sem.SlotValue(Sem.SlotClass(slot.id)), f.deps or {}, op.pc))
  return true
end

local function guard_i64_nonzero(ctx, op, value)
  ctx.effects[#ctx.effects + 1] = Guard.observe(Sem.I64NonZeroGuard(value, op.pc))
end

local function require_f64(ctx, op, slot)
  local subject = Fact.SrcSlot(slot)
  local f = has(ctx.idx, subject, Fact.IsF64)
  if not f then return nil, missing(subject, Fact.IsF64) end
  ctx.effects[#ctx.effects + 1] = Guard.observe(Guard.fact_guard(subject, Fact.IsF64, Sem.SlotValue(Sem.SlotClass(slot.id)), f.deps or {}, op.pc))
  return true
end

local function require_string(ctx, op, slot)
  local subject = Fact.SrcSlot(slot)
  local f = has(ctx.idx, subject, Fact.IsString)
  if not f then return nil, missing(subject, Fact.IsString) end
  ctx.effects[#ctx.effects + 1] = Guard.observe(Guard.fact_guard(subject, Fact.IsString, Sem.SlotValue(Sem.SlotClass(slot.id)), f.deps or {}, op.pc))
  return true
end

local function string_for_slot(ctx, slot)
  ctx.env:alias(slot)
  return Sem.SlotString(ctx.env:slot_class(slot))
end

local function write_slot(ctx, slot, value)
  ctx.effects[#ctx.effects + 1] = Write.slot(ctx.env:slot_class(slot), value)
end

local function rk_value(ctx, rk)
  if rk.kind == "R" then return ctx.env:slot_value(rk.slot) end
  if rk.kind == "K" then return Sem.ConstValue(rk.k) end
  error("unknown RK " .. tostring(rk.kind))
end

local function reject(op, reason, missing_facts, missing_payloads)
  return Reject.reject(op, reason or "semantic_not_implemented", missing_facts or {}, missing_payloads or {})
end

local function checked_table_from_slot(ctx, slot, leases)
  return Sem.CheckedTable(ctx.env:slot_value(slot), leases or {})
end

local function checked_table_from_upvalue(up, leases)
  return Sem.UpvalueTable(up, leases or {})
end

local function require_table_fact(ctx, op, subject, value)
  return require_fact(ctx, op, subject, Fact.IsTable, value)
end

local function require_field_access(ctx, op, subject, value, key)
  local missing_facts, missing_payloads = {}, {}
  local shape_payload = find_payload(ctx, "shape", subject)
  if not shape_payload then missing_payloads[#missing_payloads + 1] = missing_payload("shape", subject, op) end
  local shape_key = shape_payload and shape_payload.shape_key
  local field_payload = shape_key and find_payload(ctx, "field", subject, key, shape_key) or nil
  if not field_payload then missing_payloads[#missing_payloads + 1] = missing_payload("field", subject, op, key) end

  local table_fact = require_table_fact(ctx, op, subject, value)
  if not table_fact then missing_facts[#missing_facts + 1] = missing(subject, Fact.IsTable) end
  if not shape_key or not require_fact(ctx, op, subject, Fact.ShapeEq, value, shape_key) then missing_facts[#missing_facts + 1] = missing(subject, Fact.ShapeEq, shape_key or "") end
  if not shape_key or not require_fact(ctx, op, subject, Fact.MetatableAbsent, value, shape_key) then missing_facts[#missing_facts + 1] = missing(subject, Fact.MetatableAbsent, shape_key or "") end
  local field_key = shape_key and RuntimeImport.field_value_key(shape_key, key) or ""
  if not require_fact(ctx, op, subject, Fact.FieldOffset, value, field_key) then missing_facts[#missing_facts + 1] = missing(subject, Fact.FieldOffset, field_key) end
  if #missing_facts > 0 then return nil, nil, "missing_fact", missing_facts, {} end
  if #missing_payloads > 0 then return nil, nil, "missing_payload_lease", {}, missing_payloads end
  return { shape_payload, field_payload }, field_payload
end

local function require_len_access(ctx, op, subject, value)
  local missing_facts, missing_payloads = {}, {}
  local shape_payload = find_payload(ctx, "shape", subject)
  if not shape_payload then missing_payloads[#missing_payloads + 1] = missing_payload("shape", subject, op) end
  local shape_key = shape_payload and shape_payload.shape_key
  if not require_table_fact(ctx, op, subject, value) then missing_facts[#missing_facts + 1] = missing(subject, Fact.IsTable) end
  if not shape_key or not require_fact(ctx, op, subject, Fact.ShapeEq, value, shape_key) then missing_facts[#missing_facts + 1] = missing(subject, Fact.ShapeEq, shape_key or "") end
  if not shape_key or not require_fact(ctx, op, subject, Fact.MetatableAbsent, value, shape_key) then missing_facts[#missing_facts + 1] = missing(subject, Fact.MetatableAbsent, shape_key or "") end
  if not require_fact(ctx, op, subject, Fact.ArrayLenOffset, value, shape_key or "") then missing_facts[#missing_facts + 1] = missing(subject, Fact.ArrayLenOffset, shape_key or "") end
  if #missing_facts > 0 then return nil, "missing_fact", missing_facts, {} end
  if #missing_payloads > 0 then return nil, "missing_payload_lease", {}, missing_payloads end
  return { shape_payload }
end

local function require_array_access(ctx, op, subject, value)
  local missing_facts, missing_payloads = {}, {}
  local array_payload = find_payload(ctx, "array", subject)
  if not array_payload then missing_payloads[#missing_payloads + 1] = missing_payload("array", subject, op) end
  if not require_table_fact(ctx, op, subject, value) then missing_facts[#missing_facts + 1] = missing(subject, Fact.IsTable) end
  if not require_fact(ctx, op, subject, Fact.ArrayHit, value) then missing_facts[#missing_facts + 1] = missing(subject, Fact.ArrayHit) end
  if not require_fact(ctx, op, subject, Fact.BoundsOk, value) then missing_facts[#missing_facts + 1] = missing(subject, Fact.BoundsOk) end
  if not require_fact(ctx, op, subject, Fact.ArrayBaseOffset, value) then missing_facts[#missing_facts + 1] = missing(subject, Fact.ArrayBaseOffset) end
  if #missing_facts > 0 then return nil, nil, "missing_fact", missing_facts, {} end
  if #missing_payloads > 0 then return nil, nil, "missing_payload_lease", {}, missing_payloads end
  return { array_payload }, array_payload
end

local function require_barrier(ctx, op, subject, owner, value)
  local f = require_fact(ctx, op, subject, Fact.BarrierClean, owner)
  local p = find_barrier_payload(ctx, op)
  if not f then return nil, "missing_fact", { missing(subject, Fact.BarrierClean) }, {} end
  if not p then return nil, "missing_payload_lease", {}, { missing_payload("barrier", subject, op) } end
  ctx.effects[#ctx.effects + 1] = Sem.BarrierAfterStore(owner, value, p)
  return true
end

local function key_const_from_slot(ctx, slot)
  local f = has(ctx.idx, Fact.SrcSlot(slot), Fact.KeyConst)
  if f then
    local id = tonumber(tostring(f.value_key or ""):match("(%d+)"))
    if id then return B.k(id), f end
  end
  return nil
end

local DECISION = {}
local DECISION_KIND = {}

local function add_decision(name, kind, fn)
  DECISION[name] = fn
  DECISION_KIND[name] = kind
end
local function add_reject(name, reason)
  add_decision(name, "reject", function(_ctx, op) return reject(op, reason or "semantic_not_implemented") end)
end

add_decision("MOVE", "semantic", function(ctx, op) write_slot(ctx, op.a, ctx.env:slot_value(op.b)) end)
add_decision("LOADI", "semantic", function(ctx, op) write_slot(ctx, op.a, box_i64(i64_imm(op.value))) end)
add_decision("LOADF", "semantic", function(ctx, op) write_slot(ctx, op.a, box_f64(Sem.ImmF64(op.value))) end)
add_decision("LOADK", "semantic", function(ctx, op) write_slot(ctx, op.a, Sem.ConstValue(op.k)) end)
add_decision("LOADKX", "semantic", function(ctx, op)
  if not op.has_extraarg then return reject(op, "unsupported_semantic_case") end
  write_slot(ctx, op.a, Sem.ConstValue(B.k(op.extraarg.value)))
  if ctx.next_op and ctx.next_op.kind == "EXTRAARG" then ctx.skip_next = true end
end)
add_decision("EXTRAARG", "semantic", function(_ctx, op)
  return reject(op, "unsupported_semantic_case")
end)
add_decision("LOADFALSE", "semantic", function(ctx, op) write_slot(ctx, op.a, Sem.Bool(false)) end)
add_decision("LFALSESKIP", "semantic", function(ctx, op)
  write_slot(ctx, op.a, Sem.Bool(false))
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.JumpObservation(op.pc, B.offset(1)))
end)
add_decision("LOADTRUE", "semantic", function(ctx, op) write_slot(ctx, op.a, Sem.Bool(true)) end)
add_decision("LOADNIL", "semantic", function(ctx, op)
  local n = math.max(1, op.count.value or 1)
  for i = 0, n - 1 do write_slot(ctx, B.slot(op.a.id + i), Sem.Nil) end
end)

add_decision("ADDI", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
  write_slot(ctx, op.a, box_i64(affine({ term(1, i64_atom_for_slot(ctx.env, op.lhs)) }, op.rhs.value)))
end)
add_decision("ADDK", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
  local kval = const_i64_from_evidence(ctx.idx, op.rhs)
  if not kval then return reject(op, "missing_fact", { missing(Fact.Const(op.rhs), Fact.ConstI64) }) end
  write_slot(ctx, op.a, box_i64(affine({ term(1, i64_atom_for_slot(ctx.env, op.lhs)) }, kval)))
end)
add_decision("SUBK", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
  local kval = const_i64_from_evidence(ctx.idx, op.rhs)
  if not kval then return reject(op, "missing_fact", { missing(Fact.Const(op.rhs), Fact.ConstI64) }) end
  write_slot(ctx, op.a, box_i64(affine({ term(1, i64_atom_for_slot(ctx.env, op.lhs)) }, -kval)))
end)
add_decision("ADD", "semantic", function(ctx, op)
  local ok1, miss1 = require_i64(ctx, op, op.lhs); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
  local ok2, miss2 = require_i64(ctx, op, op.rhs); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
  write_slot(ctx, op.a, box_i64(affine({ term(1, i64_atom_for_slot(ctx.env, op.lhs)), term(1, i64_atom_for_slot(ctx.env, op.rhs)) }, 0)))
end)
add_decision("SUB", "semantic", function(ctx, op)
  local ok1, miss1 = require_i64(ctx, op, op.lhs); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
  local ok2, miss2 = require_i64(ctx, op, op.rhs); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
  write_slot(ctx, op.a, box_i64(affine({ term(1, i64_atom_for_slot(ctx.env, op.lhs)), term(-1, i64_atom_for_slot(ctx.env, op.rhs)) }, 0)))
end)

local I64_K_OP = { MULK="MulI64", MODK="ModI64", IDIVK="IDivI64", BANDK="BitAndI64", BORK="BitOrI64", BXORK="BitXorI64" }
for name, ctor in pairs(I64_K_OP) do
  add_decision(name, "semantic", function(ctx, op)
    local ok, miss = require_i64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
    local kval = const_i64_from_evidence(ctx.idx, op.rhs)
    if not kval then return reject(op, "missing_fact", { missing(Fact.Const(op.rhs), Fact.ConstI64) }) end
    local lhs = i64_atom_for_slot(ctx.env, op.lhs)
    local rhs = i64_imm(kval)
    if name == "MODK" or name == "IDIVK" then guard_i64_nonzero(ctx, op, rhs) end
    write_slot(ctx, op.a, box_i64(Sem[ctor](lhs, rhs)))
  end)
end

local I64_RR_OP = { MUL="MulI64", MOD="ModI64", IDIV="IDivI64", BAND="BitAndI64", BOR="BitOrI64", BXOR="BitXorI64", SHL="ShlI64", SHR="ShrI64" }
for name, ctor in pairs(I64_RR_OP) do
  add_decision(name, "semantic", function(ctx, op)
    local ok1, miss1 = require_i64(ctx, op, op.lhs); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
    local ok2, miss2 = require_i64(ctx, op, op.rhs); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
    local lhs = i64_atom_for_slot(ctx.env, op.lhs)
    local rhs = i64_atom_for_slot(ctx.env, op.rhs)
    if name == "MOD" or name == "IDIV" then guard_i64_nonzero(ctx, op, rhs) end
    write_slot(ctx, op.a, box_i64(Sem[ctor](lhs, rhs)))
  end)
end

add_decision("SHLI", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.rhs); if not ok then return reject(op, "missing_fact", { miss }) end
  write_slot(ctx, op.a, box_i64(Sem.ShlI64(i64_imm(op.lhs.value), i64_atom_for_slot(ctx.env, op.rhs))))
end)
add_decision("SHRI", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
  write_slot(ctx, op.a, box_i64(Sem.ShrI64(i64_atom_for_slot(ctx.env, op.lhs), i64_imm(op.rhs.value))))
end)
add_decision("UNM", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.b); if not ok then return reject(op, "missing_fact", { miss }) end
  write_slot(ctx, op.a, box_i64(Sem.NegI64(i64_atom_for_slot(ctx.env, op.b))))
end)
add_decision("BNOT", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.b); if not ok then return reject(op, "missing_fact", { miss }) end
  write_slot(ctx, op.a, box_i64(Sem.BitNotI64(i64_atom_for_slot(ctx.env, op.b))))
end)
add_decision("LEN", "semantic", function(ctx, op)
  local subject = Fact.SrcSlot(op.b)
  local owner = ctx.env:slot_value(op.b)
  local leases, reason, mf, mp = require_len_access(ctx, op, subject, owner)
  if not leases then return reject(op, reason, mf, mp) end
  write_slot(ctx, op.a, box_i64(Sem.TableLenI64(checked_table_from_slot(ctx, op.b, leases))))
end)

-- PUC MMBIN* opcodes are fallback/metamethod companion markers for the
-- immediately preceding arithmetic opcode. They are semantic no-ops only after
-- that arithmetic opcode has already lowered on a typed fast path. A standalone
-- MMBIN* (or one not immediately following lowered arithmetic) is not coverage:
-- it would be a metamethod call and must reject until generic metamethod/call
-- lowering exists.
local ARITH_PREDECESSOR_FOR_MMBIN = {
  ADDI=true, ADDK=true, SUBK=true, MULK=true, MODK=true, POWK=true, DIVK=true, IDIVK=true,
  BANDK=true, BORK=true, BXORK=true, SHLI=true, SHRI=true,
  ADD=true, SUB=true, MUL=true, MOD=true, POW=true, DIV=true, IDIV=true,
  BAND=true, BOR=true, BXOR=true, SHL=true, SHR=true,
}
local function mmbin_marker(ctx, op)
  if not (ctx.prev_op and ARITH_PREDECESSOR_FOR_MMBIN[ctx.prev_op.kind]) then
    return reject(op, "unsupported_semantic_case")
  end
end
add_decision("MMBIN", "semantic", mmbin_marker)
add_decision("MMBINI", "semantic", mmbin_marker)
add_decision("MMBINK", "semantic", mmbin_marker)

local function f64_slot(ctx, slot) return Sem.SlotF64(ctx.env:slot_class(slot)) end
add_decision("DIVK", "semantic", function(ctx, op)
  local ok, miss = require_f64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
  if not has_const_f64(ctx, op.rhs) then return reject(op, "missing_fact", { missing(Fact.Const(op.rhs), Fact.ConstF64) }) end
  write_slot(ctx, op.a, box_f64(Sem.DivF64(f64_slot(ctx, op.lhs), Sem.ConstF64(op.rhs))))
end)
add_decision("POWK", "semantic", function(ctx, op)
  local ok, miss = require_f64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
  if not has_const_f64(ctx, op.rhs) then return reject(op, "missing_fact", { missing(Fact.Const(op.rhs), Fact.ConstF64) }) end
  write_slot(ctx, op.a, box_f64(Sem.PowF64(f64_slot(ctx, op.lhs), Sem.ConstF64(op.rhs))))
end)
add_decision("DIV", "semantic", function(ctx, op)
  local ok1, miss1 = require_f64(ctx, op, op.lhs); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
  local ok2, miss2 = require_f64(ctx, op, op.rhs); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
  write_slot(ctx, op.a, box_f64(Sem.DivF64(f64_slot(ctx, op.lhs), f64_slot(ctx, op.rhs))))
end)
add_decision("POW", "semantic", function(ctx, op)
  local ok1, miss1 = require_f64(ctx, op, op.lhs); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
  local ok2, miss2 = require_f64(ctx, op, op.rhs); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
  write_slot(ctx, op.a, box_f64(Sem.PowF64(f64_slot(ctx, op.lhs), f64_slot(ctx, op.rhs))))
end)

add_decision("CONCAT", "semantic", function(ctx, op)
  if op.first.id > op.last.id then return reject(op, "unsupported_semantic_case") end
  local parts = {}
  for id = op.first.id, op.last.id do
    local slot = B.slot(id)
    local ok, miss = require_string(ctx, op, slot); if not ok then return reject(op, "missing_fact", { miss }) end
    parts[#parts + 1] = string_for_slot(ctx, slot)
  end
  write_slot(ctx, op.a, Sem.StringValue(Sem.ConcatString(parts)))
end)

add_decision("RETURN1", "semantic", function(ctx, op)
  ctx.env:alias(op.value, op.pc, op.pc)
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.ReturnObservation(op.pc, ctx.env:slot_value(op.value)))
end)
add_decision("RETURN0", "semantic", function(ctx, op)
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.Return0Observation(op.pc))
end)
add_decision("RETURN", "semantic", function(ctx, op)
  if op.close_upvalues or ((op.c and op.c.value or 0) ~= 0) then return reject(op, "unsupported_semantic_case") end
  local n = op.nresults and op.nresults.value or 0
  if n == 1 then
    ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.Return0Observation(op.pc))
  elseif n == 2 then
    ctx.env:alias(op.base, op.pc, op.pc)
    ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.ReturnObservation(op.pc, ctx.env:slot_value(op.base)))
  else
    return reject(op, "unsupported_semantic_case")
  end
end)
add_decision("FORPREP", "semantic", function(ctx, op)
  local limit = B.slot(op.base.id + 1)
  local step = B.slot(op.base.id + 2)
  local ok0, miss0 = require_i64(ctx, op, op.base); if not ok0 then return reject(op, "missing_fact", { miss0 }) end
  local ok1, miss1 = require_i64(ctx, op, limit); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
  local ok2, miss2 = require_i64(ctx, op, step); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
  write_slot(ctx, op.base, box_i64(affine({ term(1, i64_atom_for_slot(ctx.env, op.base)), term(-1, i64_atom_for_slot(ctx.env, step)) }, 0)))
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.JumpObservation(op.pc, op.offset))
end)
add_decision("FORLOOP", "semantic", function(ctx, op)
  local limit = B.slot(op.base.id + 1)
  local step = B.slot(op.base.id + 2)
  local external = B.slot(op.base.id + 3)
  local ok0, miss0 = require_i64(ctx, op, op.base); if not ok0 then return reject(op, "missing_fact", { miss0 }) end
  local ok1, miss1 = require_i64(ctx, op, limit); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
  local ok2, miss2 = require_i64(ctx, op, step); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
  local new_index = affine({ term(1, i64_atom_for_slot(ctx.env, op.base)), term(1, i64_atom_for_slot(ctx.env, step)) }, 0)
  write_slot(ctx, op.base, box_i64(new_index))
  write_slot(ctx, external, box_i64(new_index))
  local step_nonnegative = Sem.CmpI64(Src.GeI, i64_atom_for_slot(ctx.env, step), i64_imm(0), true)
  local positive_ok = Sem.BoolAnd(step_nonnegative, Sem.CmpI64(Src.Le, new_index, i64_atom_for_slot(ctx.env, limit), true))
  local step_negative = Sem.CmpI64(Src.LtI, i64_atom_for_slot(ctx.env, step), i64_imm(0), true)
  local negative_ok = Sem.BoolAnd(step_negative, Sem.CmpI64(Src.Le, i64_atom_for_slot(ctx.env, limit), new_index, true))
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.ConditionalJumpObservation(op.pc, Sem.BoolOr(positive_ok, negative_ok), op.offset))
end)
add_decision("JMP", "semantic", function(ctx, op)
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.JumpObservation(op.pc, op.offset))
end)

local function conditional_jump(ctx, op, cmp)
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.ConditionalJumpObservation(op.pc, cmp, B.offset(1)))
end
local CMP_RR = { EQ=Src.Eq, LT=Src.Lt, LE=Src.Le }
for name, cmp_op in pairs(CMP_RR) do
  add_decision(name, "semantic", function(ctx, op)
    local ok1, miss1 = require_i64(ctx, op, op.lhs); if not ok1 then return reject(op, "missing_fact", { miss1 }) end
    local ok2, miss2 = require_i64(ctx, op, op.rhs); if not ok2 then return reject(op, "missing_fact", { miss2 }) end
    conditional_jump(ctx, op, Sem.CmpI64(cmp_op, i64_atom_for_slot(ctx.env, op.lhs), i64_atom_for_slot(ctx.env, op.rhs), op.polarity))
  end)
end
add_decision("EQK", "semantic", function(ctx, op)
  local ok, miss = require_i64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
  local kval = const_i64_from_evidence(ctx.idx, op.rhs)
  if not kval then return reject(op, "missing_fact", { missing(Fact.Const(op.rhs), Fact.ConstI64) }) end
  conditional_jump(ctx, op, Sem.CmpI64(Src.EqK, i64_atom_for_slot(ctx.env, op.lhs), i64_imm(kval), op.polarity))
end)
local CMP_RI = { EQI=Src.EqI, LTI=Src.LtI, LEI=Src.LeI, GTI=Src.GtI, GEI=Src.GeI }
for name, cmp_op in pairs(CMP_RI) do
  add_decision(name, "semantic", function(ctx, op)
    if op.rhs_is_float then return reject(op, "unsupported_semantic_case") end
    local ok, miss = require_i64(ctx, op, op.lhs); if not ok then return reject(op, "missing_fact", { miss }) end
    conditional_jump(ctx, op, Sem.CmpI64(cmp_op, i64_atom_for_slot(ctx.env, op.lhs), i64_imm(op.rhs.value), op.polarity))
  end)
end
add_decision("TEST", "semantic", function(ctx, op)
  ctx.env:alias(op.a, op.pc, op.pc)
  conditional_jump(ctx, op, Sem.IsTruthy(ctx.env:slot_value(op.a), op.polarity))
end)
add_decision("TESTSET", "semantic", function(ctx, op)
  ctx.env:alias(op.a, op.pc, op.pc)
  ctx.env:alias(op.b, op.pc, op.pc)
  local value = ctx.env:slot_value(op.b)
  local condition = Sem.IsTruthy(value, op.polarity)
  ctx.effects[#ctx.effects + 1] = Sem.Observe(Sem.TestSetObservation(op.pc, ctx.env:slot_class(op.a), value, condition, B.offset(1)))
end)

-- CFG reset: these are valid Lua operations but not accepted compiled success
-- until represented as MoonCFG regions. Do not emit protocol observations.
add_decision("CALL", "semantic", function(_ctx, op) return reject(op, "unsupported_semantic_case") end)
add_decision("TAILCALL", "semantic", function(_ctx, op) return reject(op, "unsupported_semantic_case") end)
add_decision("CLOSE", "semantic", function(_ctx, op) return reject(op, "unsupported_semantic_case") end)
add_decision("TBC", "semantic", function(_ctx, op) return reject(op, "unsupported_semantic_case") end)
add_decision("TFORPREP", "semantic", function(_ctx, op) return reject(op, "unsupported_semantic_case") end)
add_decision("TFORCALL", "semantic", function(_ctx, op) return reject(op, "unsupported_semantic_case") end)
add_decision("TFORLOOP", "semantic", function(_ctx, op) return reject(op, "unsupported_semantic_case") end)

add_decision("GETUPVAL", "semantic", function(ctx, op)
  write_slot(ctx, op.a, Sem.UpvalueValue(op.up))
end)
add_decision("NEWTABLE", "semantic", function(ctx, op)
  if op.uses_extraarg then return reject(op, "unsupported_semantic_case") end
  write_slot(ctx, op.a, Sem.TableObject(Sem.NewTable(op.array_hint, op.hash_hint)))
end)
add_decision("CLOSURE", "semantic", function(ctx, op)
  write_slot(ctx, op.a, Sem.ClosureObject(Sem.ProtoClosure(op.proto)))
end)
add_decision("SETLIST", "semantic", function(_ctx, op)
  return reject(op, "unsupported_semantic_case")
end)
local function write_vararg_results(ctx, op, dst, base, nresults)
  local n = nresults and nresults.value or 0
  if n == 0 then return reject(op, "unsupported_semantic_case") end
  for i = 1, math.max(0, n - 1) do
    write_slot(ctx, B.slot(dst.id + i - 1), Sem.VarargValue(base, B.count(i)))
  end
end
add_decision("VARARG", "semantic", function(ctx, op)
  if op.uses_vararg_table then return reject(op, "unsupported_semantic_case") end
  return write_vararg_results(ctx, op, op.a, B.slot(0), op.wanted)
end)
add_decision("GETVARG", "semantic", function(_ctx, op)
  return reject(op, "unsupported_semantic_case")
end)
add_decision("VARARGPREP", "semantic", function(_ctx, _op)
  -- Frame-entry vararg setup marker. In this PVM output, frame setup is not a
  -- hidden runtime action: fixed OP_VARARG reads become VarargTValue(base,index).
  -- GETVARG and open VARARG require MoonCFG region semantics before success.
end)
add_decision("ERRNNIL", "semantic", function(ctx, op)
  local subject = Fact.SrcSlot(op.a)
  local value = ctx.env:slot_value(op.a)
  for _, pred in ipairs({ Fact.IsI64, Fact.IsF64, Fact.IsTable, Fact.IsClosure, Fact.IsBool, Fact.IsTrue, Fact.IsFalse }) do
    if has(ctx.idx, subject, pred) then require_fact(ctx, op, subject, pred, value); return end
  end
  return reject(op, "missing_fact", { missing(subject, Fact.IsI64) })
end)
add_decision("SETUPVAL", "semantic", function(ctx, op)
  ctx.effects[#ctx.effects + 1] = Sem.DoWrite(Sem.UpvalueWrite(op.up, ctx.env:slot_value(op.value)))
end)
add_decision("NOT", "semantic", function(ctx, op)
  write_slot(ctx, op.a, Sem.BoolValue(Sem.NotTValue(ctx.env:slot_value(op.b))))
end)

local function field_read(ctx, op, dst, subject, owner_value, table_value, key)
  local leases, field_payload, reason, mf, mp = require_field_access(ctx, op, subject, owner_value, key)
  if not leases then return reject(op, reason, mf, mp) end
  write_slot(ctx, dst, Sem.FieldValue(Sem.TableField(table_value(leases), key, field_payload)))
end
local function field_write(ctx, op, subject, owner_value, table_value, key, value)
  local leases, field_payload, reason, mf, mp = require_field_access(ctx, op, subject, owner_value, key)
  if not leases then return reject(op, reason, mf, mp) end
  local address = Sem.TableField(table_value(leases), key, field_payload)
  ctx.effects[#ctx.effects + 1] = Sem.DoWrite(Sem.FieldWrite(address, value))
  local ok, breason, bmf, bmp = require_barrier(ctx, op, subject, owner_value, value)
  if not ok then return reject(op, breason, bmf, bmp) end
end

add_decision("GETFIELD", "semantic", function(ctx, op)
  local subject = Fact.SrcSlot(op.table)
  local owner = ctx.env:slot_value(op.table)
  return field_read(ctx, op, op.a, subject, owner, function(leases) return checked_table_from_slot(ctx, op.table, leases) end, op.key)
end)
add_decision("GETTABUP", "semantic", function(ctx, op)
  local subject = Fact.Upvalue(op.up)
  local owner = Sem.UpvalueValue(op.up)
  return field_read(ctx, op, op.a, subject, owner, function(leases) return checked_table_from_upvalue(op.up, leases) end, op.key)
end)
add_decision("SETFIELD", "semantic", function(ctx, op)
  local subject = Fact.SrcSlot(op.table)
  local owner = ctx.env:slot_value(op.table)
  return field_write(ctx, op, subject, owner, function(leases) return checked_table_from_slot(ctx, op.table, leases) end, op.key, rk_value(ctx, op.value))
end)
add_decision("SETTABUP", "semantic", function(ctx, op)
  local subject = Fact.Upvalue(op.up)
  local owner = Sem.UpvalueValue(op.up)
  return field_write(ctx, op, subject, owner, function(leases) return checked_table_from_upvalue(op.up, leases) end, op.key, rk_value(ctx, op.value))
end)

local function array_read(ctx, op, dst, table_slot, index)
  local subject = Fact.SrcSlot(table_slot)
  local owner = ctx.env:slot_value(table_slot)
  local leases, array_payload, reason, mf, mp = require_array_access(ctx, op, subject, owner)
  if not leases then return reject(op, reason, mf, mp) end
  local table_value = checked_table_from_slot(ctx, table_slot, leases)
  ctx.effects[#ctx.effects + 1] = Guard.observe(Sem.BoundsGuard(table_value, index, array_payload, op.pc))
  write_slot(ctx, dst, Sem.ArrayValue(Sem.TableArray(table_value, index, array_payload)))
end
local function array_write(ctx, op, table_slot, index, value)
  local subject = Fact.SrcSlot(table_slot)
  local owner = ctx.env:slot_value(table_slot)
  local leases, array_payload, reason, mf, mp = require_array_access(ctx, op, subject, owner)
  if not leases then return reject(op, reason, mf, mp) end
  local table_value = checked_table_from_slot(ctx, table_slot, leases)
  ctx.effects[#ctx.effects + 1] = Guard.observe(Sem.BoundsGuard(table_value, index, array_payload, op.pc))
  local address = Sem.TableArray(table_value, index, array_payload)
  ctx.effects[#ctx.effects + 1] = Sem.DoWrite(Sem.ArrayWrite(address, value))
  local ok, breason, bmf, bmp = require_barrier(ctx, op, subject, owner, value)
  if not ok then return reject(op, breason, bmf, bmp) end
end

add_decision("GETI", "semantic", function(ctx, op)
  return array_read(ctx, op, op.a, op.table, i64_imm(op.index.value))
end)
add_decision("SETI", "semantic", function(ctx, op)
  return array_write(ctx, op, op.table, i64_imm(op.index.value), rk_value(ctx, op.value))
end)
add_decision("GETTABLE", "semantic", function(ctx, op)
  if has(ctx.idx, Fact.SrcSlot(op.key), Fact.IsI64) and find_payload(ctx, "array", Fact.SrcSlot(op.table)) then
    local ok, miss = require_i64(ctx, op, op.key); if not ok then return reject(op, "missing_fact", { miss }) end
    return array_read(ctx, op, op.a, op.table, i64_atom_for_slot(ctx.env, op.key))
  end
  local key = key_const_from_slot(ctx, op.key)
  if key then
    local subject = Fact.SrcSlot(op.table)
    local owner = ctx.env:slot_value(op.table)
    return field_read(ctx, op, op.a, subject, owner, function(leases) return checked_table_from_slot(ctx, op.table, leases) end, key)
  end
  return reject(op, "missing_fact", { missing(Fact.SrcSlot(op.key), Fact.IsI64) })
end)
add_decision("SETTABLE", "semantic", function(ctx, op)
  if has(ctx.idx, Fact.SrcSlot(op.key), Fact.IsI64) and find_payload(ctx, "array", Fact.SrcSlot(op.table)) then
    local ok, miss = require_i64(ctx, op, op.key); if not ok then return reject(op, "missing_fact", { miss }) end
    return array_write(ctx, op, op.table, i64_atom_for_slot(ctx.env, op.key), rk_value(ctx, op.value))
  end
  local key = key_const_from_slot(ctx, op.key)
  if key then
    local subject = Fact.SrcSlot(op.table)
    local owner = ctx.env:slot_value(op.table)
    return field_write(ctx, op, subject, owner, function(leases) return checked_table_from_slot(ctx, op.table, leases) end, key, rk_value(ctx, op.value))
  end
  return reject(op, "missing_fact", { missing(Fact.SrcSlot(op.key), Fact.IsI64) })
end)
add_decision("SELF", "semantic", function(ctx, op)
  write_slot(ctx, B.slot(op.a.id + 1), ctx.env:slot_value(op.receiver))
  local subject = Fact.SrcSlot(op.receiver)
  local owner = ctx.env:slot_value(op.receiver)
  return field_read(ctx, op, op.a, subject, owner, function(leases) return checked_table_from_slot(ctx, op.receiver, leases) end, op.key)
end)

local function alias_source_slots(ctx, op)
  for _, field in ipairs({ "a", "lhs", "rhs", "b", "table", "key", "value", "base", "first", "last", "receiver" }) do
    if pvm.classof(op[field]) == Src.Slot then ctx.env:alias(op[field], op.pc, op.pc) end
  end
end

local function lower_value(window, evidence)
  local contradictions = Contradiction.find(evidence)
  if #contradictions > 0 then
    local op = window and window.ops and window.ops[1]
    return reject(op or Src.UnsupportedOpcode(B.pc(0), "<empty>"), "contradictory_evidence")
  end

  local ctx = { idx = evidence_index(evidence), env = Env.new(), effects = {} }

  local ops = (window and window.ops) or {}
  local i = 1
  while i <= #ops do
    local op = ops[i]
    ctx.next_op = ops[i + 1]
    ctx.skip_next = false
    alias_source_slots(ctx, op)
    if op.kind == "UnsupportedOpcode" then return reject(op, "unsupported_opcode") end
    local decision = DECISION[op.kind]
    if not decision then return reject(op, "unsupported_opcode") end
    local result = decision(ctx, op)
    if result then return result end
    ctx.prev_op = op
    i = i + (ctx.skip_next and 2 or 1)
  end

  return Sem.Accepted(Sem.Program(ctx.env:aliases_array(), ctx.effects))
end

local phase = pvm.phase("spongejit_lua_src_to_lua_sem_lower", function(window, evidence)
  return lower_value(window, evidence)
end)

function M.lower(window, evidence)
  return pvm.one(phase(window, evidence))
end

M.phase = phase
M.lower_uncached = lower_value

function M.decision_for(op_name)
  return DECISION_KIND[op_name]
end

M.SEMANTIC_DECISION = DECISION
M.SEMANTIC_DECISION_KIND = DECISION_KIND
return M
