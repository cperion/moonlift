-- ssa_contract.lua -- Tile fact-transfer contracts from Stencil IR.
--
-- Contracts are over the same 64-bit ABI as runtime facts, but slot facts are
-- encoded in canonical stencil slot-class space.  Generated bank selector code
-- remaps these masks to actual runtime slots using stencil.slotmaps.

local Sig = require("src.fact_signature")
local Facts = require("src.facts")

local M = {}

local function copy_array(xs)
  local out = {}
  for i, x in ipairs(xs or {}) do out[i] = x end
  return out
end

local function slot_number_from_subject(subj)
  local id = subj and subj.id
  if type(id) == "number" then return id end
  if type(id) == "string" then return tonumber(id:match("^R(%d+)$") or id:match("^(%d+)$")) end
  return nil
end

local function remap_fact_to_canonical(f, st)
  if type(f) ~= "table" then return f end
  local slot = slot_number_from_subject(f.subject)
  if slot == nil then return f end
  local cls = st and st.slot_class_by_concrete and st.slot_class_by_concrete[slot]
  if cls == nil then return f end
  local nf = {}
  for k, v in pairs(f) do nf[k] = v end
  nf.subject = Facts.slot("R" .. tostring(cls))
  return nf
end

local function remap_facts(facts, st)
  local out = {}
  for _, f in ipairs(facts or {}) do out[#out + 1] = remap_fact_to_canonical(f, st) end
  return out
end

local function node_kills_all_vm_facts(n)
  if n.effect == "call" or n.op == "ExitBoundary" then return true end
  if n.effect == "heap_write" or n.op == "FieldStore" or n.op == "ArrayStore" then return true end
  if n.effect == "gc_barrier" or n.op == "BarrierCheck" then return true end
  return false
end

local function op_is_hard_exit(n)
  return n.op == "ExitResidual" or n.op == "ExitBoundary" or n.op == "ExitUnlowered"
end

function M.from_result(ssa_result, facts)
  local st = assert(ssa_result and ssa_result.stencil, "ssa_contract requires ssa_result.stencil")
  local selector = Sig.encode(remap_facts(facts or ssa_result.facts or {}, st))
  local checked = Sig.empty()
  local produced = Sig.empty()
  local killed = Sig.empty()
  local deps = {}
  local exits = {}

  for _, n in ipairs(st.ops or {}) do
    if n.guard and n.guard.fact then
      checked = Sig.bor(checked, Sig.encode({remap_fact_to_canonical(n.guard.fact, st)}))
    end
    for _, d in ipairs(n.deps or {}) do deps[#deps + 1] = d end
    if n.exit then exits[#exits + 1] = {pc = n.source or 0, reason = n.exit.reason or "exit"} end

    if n.op == "StoreSlot" or n.op == "StoreI64Slot" then
      local slot = n.hole and n.hole.role_arg
      killed = Sig.bor(killed, Sig.slot_kill(slot))
      if n.op == "StoreI64Slot" then produced = Sig.bor(produced, Sig.i64_slot(slot)) end
    end

    if node_kills_all_vm_facts(n) then
      killed = Sig.bor(killed, Sig.all_table_and_payload_facts())
    end

    if op_is_hard_exit(n) then
      killed = Sig.bor(killed, Sig.all_slot_facts())
      killed = Sig.bor(killed, Sig.all_table_and_payload_facts())
    end
  end

  local required = Sig.minus(selector, checked)
  return {
    selector_sig = Sig.with_literal(selector),
    required_sig = Sig.with_literal(required),
    checked_sig = Sig.with_literal(checked),
    produced_sig = Sig.with_literal(produced),
    killed_sig = Sig.with_literal(killed),
    deps = copy_array(deps),
    exits = exits,
  }
end

return M
