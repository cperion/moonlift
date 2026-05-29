-- fact_signature.lua -- canonical 64-bit selector/contract fact encoding.
--
-- This is the single source for the compact runtime fact universe exported by
-- SponBank.  Facts in the rich foundry lattice are projected into this fixed
-- 64-bit ABI.  A TileTemplate may also carry transfer masks over the same
-- universe: required/checked/produced/killed.

local bit = require("bit")

local M = {}

M.SLOT_FACT_BASE = {
  i64 = 0, is_i64 = 0,
  table = 8, is_table = 8,
  shape_known = 16,
  metatable_absent = 24,
  array_hit = 32,
  bounds_ok = 40,
  known_call_target = 48,
  key_i64 = 0,
}

M.GLOBAL_FACT_BIT = {
  barrier_clean = 56,
  const_i64 = 57,
  key_const = 58,
  nonzero_i64 = 59,
  shape_payload = 60,
  array_payload = 61,
  call_target_payload = 62,
}

local SLOT_FACT_BASES = {0, 8, 16, 24, 32, 40, 48}

local function u32(x)
  x = tonumber(x) or 0
  if x < 0 then x = x + 4294967296 end
  return x
end
M.u32 = u32

local function hex32(n)
  n = u32(n or 0)
  local hi = math.floor(n / 65536) % 65536
  local lo = n % 65536
  return string.format("%04x%04x", hi, lo)
end

function M.literal(sig)
  sig = sig or M.empty()
  return "0x" .. hex32(sig.hi or 0) .. hex32(sig.lo or 0) .. "ULL"
end

function M.empty()
  return {lo = 0, hi = 0, pop = 0}
end

local function add_bit_mut(sig, bitpos)
  if not bitpos or bitpos < 0 or bitpos > 63 then return end
  sig._seen = sig._seen or {}
  if sig._seen[bitpos] then return end
  sig._seen[bitpos] = true
  sig.pop = (sig.pop or 0) + 1
  if bitpos < 32 then
    sig.lo = u32(bit.bor(sig.lo or 0, bit.lshift(1, bitpos)))
  else
    sig.hi = u32(bit.bor(sig.hi or 0, bit.lshift(1, bitpos - 32)))
  end
end

function M.from_bits(bits)
  local sig = M.empty()
  for _, bitpos in ipairs(bits or {}) do add_bit_mut(sig, bitpos) end
  sig._seen = nil
  return sig
end

function M.normalize(sig)
  sig = sig or M.empty()
  return {lo = u32(sig.lo or 0), hi = u32(sig.hi or 0), pop = sig.pop or M.popcount(sig)}
end

function M.popcount(sig)
  sig = sig or M.empty()
  local n, x = 0, u32(sig.lo or 0)
  while x ~= 0 do x = bit.band(x, x - 1); n = n + 1 end
  x = u32(sig.hi or 0)
  while x ~= 0 do x = bit.band(x, x - 1); n = n + 1 end
  return n
end

function M.bor(a, b)
  a, b = M.normalize(a), M.normalize(b)
  local out = {lo = u32(bit.bor(a.lo, b.lo)), hi = u32(bit.bor(a.hi, b.hi))}
  out.pop = M.popcount(out)
  return out
end

function M.band(a, b)
  a, b = M.normalize(a), M.normalize(b)
  local out = {lo = u32(bit.band(a.lo, b.lo)), hi = u32(bit.band(a.hi, b.hi))}
  out.pop = M.popcount(out)
  return out
end

function M.minus(a, b)
  a, b = M.normalize(a), M.normalize(b)
  local out = {lo = u32(bit.band(a.lo, bit.bnot(b.lo))), hi = u32(bit.band(a.hi, bit.bnot(b.hi)))}
  out.pop = M.popcount(out)
  return out
end

function M.is_empty(sig)
  sig = sig or M.empty()
  return u32(sig.lo or 0) == 0 and u32(sig.hi or 0) == 0
end

function M.parse_slot(subject)
  local id = subject and subject.id
  if type(id) == "number" then return id end
  if type(id) == "string" then return tonumber(id:match("^R(%d+)$") or id:match("^(%d+)$")) end
  return nil
end

function M.fact_bit(f)
  local pred = tostring(f and f.predicate or "")
  local subject = (f and f.subject) or {}
  local slot = M.parse_slot(subject)
  local base = M.SLOT_FACT_BASE[pred]
  if base and slot and slot >= 0 and slot < 8 then return base + slot end
  if pred == "barrier_clean" then return M.GLOBAL_FACT_BIT.barrier_clean end
  if pred == "const_i64" then return M.GLOBAL_FACT_BIT.const_i64 end
  if pred == "key_const" then return M.GLOBAL_FACT_BIT.key_const end
  if pred == "nonzero_i64" then return M.GLOBAL_FACT_BIT.nonzero_i64 end
  if pred == "shape_eq" or pred == "field_offset" then return M.GLOBAL_FACT_BIT.shape_payload end
  if pred == "array_base_offset" then return M.GLOBAL_FACT_BIT.array_payload end
  if pred == "target_eq" then return M.GLOBAL_FACT_BIT.call_target_payload end
  return nil
end

function M.encode(facts)
  local bits = {}
  for _, f in ipairs(facts or {}) do
    local bitpos = M.fact_bit(f)
    if bitpos then bits[#bits + 1] = bitpos end
  end
  return M.from_bits(bits)
end

function M.with_literal(sig)
  sig = M.normalize(sig)
  sig.literal = M.literal(sig)
  return sig
end

function M.slot_kill(slot)
  slot = tonumber(slot)
  if not slot or slot < 0 or slot >= 8 then return M.empty() end
  local bits = {}
  for _, base in ipairs(SLOT_FACT_BASES) do bits[#bits + 1] = base + slot end
  return M.from_bits(bits)
end

function M.all_slot_facts()
  local out = M.empty()
  for slot = 0, 7 do out = M.bor(out, M.slot_kill(slot)) end
  return out
end

function M.all_table_and_payload_facts()
  local bits = {}
  for _, base in ipairs({8, 16, 24, 32, 40, 48}) do
    for slot = 0, 7 do bits[#bits + 1] = base + slot end
  end
  for _, bitpos in ipairs({56, 57, 58, 59, 60, 61, 62}) do bits[#bits + 1] = bitpos end
  return M.from_bits(bits)
end

function M.i64_slot(slot)
  slot = tonumber(slot)
  if not slot or slot < 0 or slot >= 8 then return M.empty() end
  return M.from_bits({M.SLOT_FACT_BASE.is_i64 + slot})
end

return M
