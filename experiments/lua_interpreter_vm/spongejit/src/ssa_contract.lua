-- ssa_contract.lua -- precise TileTemplate fact-transfer contracts from SSA.
--
-- The foundry lowers a source opcode tuple under a FactEnv.  This module turns
-- the resulting guarded/effectful SSA into the runtime contract used during image
-- construction:
--
--   facts_out = (facts_in - killed) | produced | checked
--
-- `selector_sig` is the projected FactEnv used to find this candidate in the bank.
-- `required_sig` is the part of that FactEnv not checked by this tile itself.
-- `checked_sig` is established by surviving guard nodes on the success edge.
-- `produced_sig` is created by successful tile semantics (currently frame stores
-- with known boxed-i64 producers).
-- `killed_sig` is invalidated by frame writes and Lua-visible effects.

local Sig = require("src.fact_signature")
local IR = require("src.ssa_ir")

local M = {}

local function copy_array(xs)
  local out = {}
  for i, x in ipairs(xs or {}) do out[i] = x end
  return out
end

local function active_nodes(g)
  local out = {}
  for _, n in ipairs((g and g.nodes) or {}) do if not n.removed then out[#out + 1] = n end end
  return out
end

local function value_producers(g)
  local prod = {}
  for _, n in ipairs((g and g.nodes) or {}) do
    if not n.removed then
      for _, v in ipairs(n.outputs or {}) do prod[v] = n end
    end
  end
  return prod
end

local function slot_number(slot)
  if type(slot) == "number" then return slot end
  if type(slot) == "string" then return tonumber(slot:match("^R(%d+)$") or slot:match("^(%d+)$")) end
  return nil
end

local function producer_chain_has_i64_box(prod, vid, seen)
  seen = seen or {}
  if not vid or seen[vid] then return false end
  seen[vid] = true
  local p = prod[vid]
  if not p then return false end
  if p.op == "BoxI64" then return true end
  if p.op == "Move" and p.inputs and p.inputs[1] then return producer_chain_has_i64_box(prod, p.inputs[1], seen) end
  return false
end

local function node_kills_all_vm_facts(n)
  if n.effect == "call" or n.op == "Call" or n.op == "KnownCall" or n.op == "TailCall" then return true end
  if n.effect == "heap_write" or n.op == "FieldStore" or n.op == "ArrayStore" then return true end
  if n.effect == "gc_barrier" or n.op == "BarrierCheck" then return true end
  return false
end

function M.from_result(ssa_result, facts)
  local g = assert(ssa_result and ssa_result.graph, "ssa_contract requires ssa_result.graph")
  local selector = Sig.encode(facts or ssa_result.facts or {})
  local checked = Sig.empty()
  local produced = Sig.empty()
  local killed = Sig.empty()
  local prod = value_producers(g)
  local deps = {}
  local exit_pcs = {}

  for _, n in ipairs(active_nodes(g)) do
    if n.guard and n.guard.fact then
      checked = Sig.bor(checked, Sig.encode({n.guard.fact}))
    end
    for _, d in ipairs(n.deps or {}) do deps[#deps + 1] = d end
    if n.exit then exit_pcs[#exit_pcs + 1] = {pc = n.source or 0, reason = n.exit.reason or "exit"} end

    if n.op == "FrameStore" then
      local slot = slot_number(n.args and n.args.slot)
      killed = Sig.bor(killed, Sig.slot_kill(slot))
      if producer_chain_has_i64_box(prod, n.inputs and n.inputs[1]) then
        produced = Sig.bor(produced, Sig.i64_slot(slot))
      end
    end

    if node_kills_all_vm_facts(n) then
      killed = Sig.bor(killed, Sig.all_table_and_payload_facts())
    end

    if IR.HARD_BARRIER[n.op] then
      -- Control/runtime boundaries end any local slot/table leases for subsequent
      -- same-image tiles.  If the node exits/returns, there may be no successor;
      -- carrying a conservative kill is still the correct contract.
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
    exits = exit_pcs,
  }
end

return M
