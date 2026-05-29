-- build_bank.lua — Generate libsponbank.c from the compiled stencil object.
--
-- Inputs:
--   build/cp_lib/stencils.o
--   build/cp_lib/stencils.text.bin        raw .text from stencils.o
--   build/cp_lib/stencil_syms.txt         "addr size func" from nm -S
--   $SPON_TMP/grammar_result_{1..N}.json  forms; each form MUST include func
--   $SPON_TMP/grammar_holes_{1..N}.json    hole catalogs by func
--
-- Output:
--   build/cp_lib/libsponbank.c
--
-- Policy:
--   * include every emitted function with size > 0, including tiny return-only
--     floor/residual stencils;
--   * index every included form in the selector candidate tables;
--   * use exact func names as the join key — never truncated hashes.

package.path = "src/?.lua;src/?/init.lua;" .. package.path

local Util = require("src.util")
local Sig = require("src.fact_signature")

local M = {}

local TMPDIR = os.getenv("SPON_TMP") or "/tmp"
local function tmp(name) return TMPDIR .. "/" .. name end

local OP = {}
local OPS_LIST = {"MOVE","LOADI","LOADF","LOADK","LOADKX","LOADFALSE","LFALSESKIP",
  "LOADTRUE","LOADNIL","GETUPVAL","SETUPVAL","GETTABUP","GETTABLE","GETI","GETFIELD",
  "SETTABUP","SETTABLE","SETI","SETFIELD","NEWTABLE","SELF","ADDI","ADDK","SUBK",
  "MULK","MODK","POWK","DIVK","IDIVK","BANDK","BORK","BXORK","SHLI","SHRI","ADD",
  "SUB","MUL","MOD","POW","DIV","IDIV","BAND","BOR","BXOR","SHL","SHR","MMBIN",
  "MMBINI","MMBINK","UNM","BNOT","NOT","LEN","CONCAT","CLOSE","TBC","JMP","EQ",
  "LT","LE","EQK","EQI","LTI","LEI","GTI","GEI","TEST","TESTSET","CALL","TAILCALL",
  "RETURN","RETURN0","RETURN1","FORLOOP","FORPREP","TFORPREP","TFORCALL","TFORLOOP",
  "SETLIST","CLOSURE","VARARG","GETVARG","ERRNNIL","VARARGPREP","EXTRAARG"}
for i, n in ipairs(OPS_LIST) do OP[n] = i - 1 end

local function hex32(n)
  n = Sig.u32(n or 0)
  local hi = math.floor(n / 65536) % 65536
  local lo = n % 65536
  return string.format("%04x%04x", hi, lo)
end

local function op_int(op)
  local name = type(op) == "table" and op.op or op
  return OP[name] or 255
end

local function packed_pattern(ops)
  local k = 0
  for i, op in ipairs(ops or {}) do
    if i > 4 then break end
    k = k + op_int(op) * (256 ^ (i - 1))
  end
  return k
end

local function pattern_key_number(ops)
  local len = #(ops or {})
  return len * 4294967296 + packed_pattern(ops)
end

local function pattern_key_literal(ops)
  local len = #(ops or {})
  return string.format("0x%x%sULL", len, hex32(packed_pattern(ops)))
end

local function encode_fact_sig(facts)
  return Sig.with_literal(Sig.encode(facts or {}))
end

local function sig_from_json(x, label, func)
  if not x or x.lo == nil or x.hi == nil then
    error(string.format("grammar_result JSON for %s is missing precise contract field %s; rebuild stencils with current src/worker_compile.lua", tostring(func), tostring(label)))
  end
  return Sig.with_literal(Sig.normalize(x))
end

local function load_contract(form)
  local c = assert(form.contract, "grammar_result JSON is missing .contract; rebuild stencils with current src/worker_compile.lua")
  return {
    selector = sig_from_json(c.selector_sig, "selector_sig", form.func),
    required = sig_from_json(c.required_sig, "required_sig", form.func),
    checked = sig_from_json(c.checked_sig, "checked_sig", form.func),
    produced = sig_from_json(c.produced_sig, "produced_sig", form.func),
    killed = sig_from_json(c.killed_sig, "killed_sig", form.func),
  }
end

local function load_syms(path)
  local syms = {}
  local f = assert(io.open(path, "r"), "cannot open symbol table: " .. path)
  for line in f:lines() do
    local a, sz, n = line:match("^(%S+) (%S+) (z_[%w_]+)$")
    if a and sz and n then
      syms[n] = {addr=tonumber(a, 16), size=tonumber(sz, 16)}
    end
  end
  f:close()
  return syms
end

local function load_holes(n_chunks)
  local holes_by_func = {}
  local total = 0
  for ci = 1, n_chunks do
    local ok, holes = pcall(function() return Util.read_json(tmp("grammar_holes_" .. ci .. ".json")) end)
    if ok then
      for _, h in ipairs(holes or {}) do
        if h.func then
          local by_id = {}
          for _, hole in ipairs(h.holes or {}) do
            if hole.id ~= nil then by_id[tonumber(hole.id)] = hole end
          end
          h.by_id = by_id
          holes_by_func[h.func] = h
          total = total + 1
        end
      end
    end
  end
  return holes_by_func, total
end

local RELOC_KIND = {
  R_X86_64_32 = 1,
  R_X86_64_32S = 2,
  R_X86_64_PLT32 = 3,
  R_X86_64_PC32 = 4,
}

local ROLE_KIND = {
  unknown = 0,
  slot = 1,
  imm = 2,
  const = 3,
  bool = 4,
  exit = 5,
  fail = 6,
  shape_offset = 7,
  shape_id = 8,
  metatable_offset = 9,
  field_offset = 10,
  array_base_offset = 11,
  call_target = 12,
  barrier = 13,
  slot_store = 14,
}

local function classify_role(role)
  role = tostring(role or "")
  if role == "fail" then return ROLE_KIND.fail, -1 end
  if role == "imm" or role == "sC" or role == "sBx" then return ROLE_KIND.imm, 0 end
  if role == "k_idx" or role == "k_i64" then return ROLE_KIND.const, 0 end
  if role == "bool_val" then return ROLE_KIND.bool, 0 end
  if role == "shape_offset" then return ROLE_KIND.shape_offset, 0 end
  if role == "shape_id" then return ROLE_KIND.shape_id, 0 end
  if role == "metatable_offset" then return ROLE_KIND.metatable_offset, 0 end
  if role == "field_offset" then return ROLE_KIND.field_offset, 0 end
  if role == "array_base_offset" then return ROLE_KIND.array_base_offset, 0 end
  if role == "call_target" then return ROLE_KIND.call_target, 0 end
  if role == "barrier" then return ROLE_KIND.barrier, 0 end
  if role:match("^exit_") or role:match("^unlowered_") then return ROLE_KIND.exit, 0 end
  local store_slot = role:match("^slot_R(%d+)$")
  if store_slot then return ROLE_KIND.slot_store, tonumber(store_slot) end
  local slot = role:match("^R(%d+)$")
  if slot then return ROLE_KIND.slot, tonumber(slot) end
  if role == "cur" or role == "slot_cur" then return ROLE_KIND.slot, -1 end
  return ROLE_KIND.unknown, 0
end

local PUC_PATCHABLE_ROLES = {
  [ROLE_KIND.unknown] = true,
  [ROLE_KIND.slot] = true,
  [ROLE_KIND.imm] = true,
  [ROLE_KIND.const] = true,
  [ROLE_KIND.bool] = true,
  [ROLE_KIND.exit] = true,
  [ROLE_KIND.fail] = true,
  [ROLE_KIND.slot_store] = true,
}

local function is_puc_patchable_tile(t)
  for _, r in ipairs(t.relocs or {}) do
    if r.reloc_kind ~= RELOC_KIND.R_X86_64_32 and r.reloc_kind ~= RELOC_KIND.R_X86_64_32S then return false end
    if not PUC_PATCHABLE_ROLES[r.role_kind] then return false end
    if (r.role_kind == ROLE_KIND.slot or r.role_kind == ROLE_KIND.slot_store) and (r.role_arg == nil or r.role_arg < 0 or r.role_arg >= 256) then return false end
  end
  return true
end

local function load_tile_relocs(o_path, tiles, holes_by_func)
  local sorted = {}
  for _, t in ipairs(tiles) do
    t.relocs = {}
    sorted[#sorted + 1] = t
  end
  table.sort(sorted, function(a, b) return a.addr < b.addr end)

  local cmd = "objdump -r " .. Util.shell_quote(o_path) .. " 2>/dev/null"
  local p = assert(io.popen(cmd, "r"), "cannot run objdump")
  local cursor, n_reloc, n_unowned, n_missing_meta = 1, 0, 0, 0
  for line in p:lines() do
    local off_hex, rtype, value = line:match("^(%x+)%s+(R_X86_64_%S+)%s+(%S+)")
    if off_hex and rtype and value then
      local hid = value:match("__H_(%d+)")
      if hid then
        local off = tonumber(off_hex, 16)
        hid = tonumber(hid)
        while cursor <= #sorted and off >= (sorted[cursor].addr + sorted[cursor].size) do
          cursor = cursor + 1
        end
        local t = sorted[cursor]
        if t and off >= t.addr and off < (t.addr + t.size) then
          local logical = holes_by_func[t.func] and holes_by_func[t.func].by_id and holes_by_func[t.func].by_id[hid]
          if not logical then n_missing_meta = n_missing_meta + 1 end
          local role = logical and logical.role or ""
          local role_kind, role_arg
          if logical and logical.role_kind then
            role_kind = ROLE_KIND[tostring(logical.role_kind)] or ROLE_KIND.unknown
            role_arg = tonumber(logical.role_arg or 0) or 0
          else
            role_kind, role_arg = classify_role(role)
          end
          t.relocs[#t.relocs + 1] = {
            code_offset = off - t.addr,
            hole_id = hid,
            reloc_kind = RELOC_KIND[rtype] or 0,
            role_kind = role_kind,
            role_arg = role_arg,
            op_idx = logical and tonumber(logical.op_idx or 0) or 0,
          }
          n_reloc = n_reloc + 1
        else
          n_unowned = n_unowned + 1
        end
      end
    end
  end
  p:close()

  local mismatched = 0
  for _, t in ipairs(tiles) do
    table.sort(t.relocs, function(a, b)
      if a.code_offset ~= b.code_offset then return a.code_offset < b.code_offset end
      return a.hole_id < b.hole_id
    end)
    local logical_count = holes_by_func[t.func] and #(holes_by_func[t.func].holes or {}) or 0
    if logical_count ~= #t.relocs then mismatched = mismatched + 1 end
    t.n_holes = #t.relocs
    t.flags = is_puc_patchable_tile(t) and 1 or 0
  end

  io.stderr:write(string.format("[bank] relocations_owned=%d unowned=%d missing_logical_metadata=%d logical_reloc_mismatches=%d\n",
    n_reloc, n_unowned, n_missing_meta, mismatched))
end

local function load_forms(n_chunks)
  local forms = {}
  local missing_func = 0
  for ci = 1, n_chunks do
    local ok, res = pcall(function() return Util.read_json(tmp("grammar_result_" .. ci .. ".json")) end)
    if ok then
      for _, f in ipairs(res.forms or {}) do
        if f.func then
          f.chunk = ci
          forms[#forms + 1] = f
        else
          missing_func = missing_func + 1
        end
      end
    end
  end
  if missing_func > 0 then
    error(string.format(
      "grammar_result JSON is stale: %d forms lack .func. Rebuild stencils with src/worker_compile.lua first.",
      missing_func))
  end
  return forms
end

function M.build_bank(o_path, n_chunks, output_dir)
  o_path = o_path or "build/cp_lib/stencils.o"
  n_chunks = n_chunks or 16
  output_dir = output_dir or "build/cp_lib"
  Util.mkdir_p(output_dir)

  local syms_path = output_dir .. "/stencil_syms.txt"

  local started = os.time()
  local function log(fmt, ...)
    io.stderr:write("[bank] " .. string.format(fmt, ...) .. "\n")
  end

  log("loading symbols/forms/holes")
  local syms = load_syms(syms_path)
  local holes_by_func, n_hole_entries = load_holes(n_chunks)
  local forms = load_forms(n_chunks)

  log("forms=%d hole_entries=%d", #forms, n_hole_entries)

  local tiles = {}
  local missing_sym, zero_size = 0, 0
  for _, f in ipairs(forms) do
    local sym = syms[f.func]
    if not sym then
      missing_sym = missing_sym + 1
    elseif not sym.size or sym.size <= 0 then
      zero_size = zero_size + 1
    else
      local contract = load_contract(f)
      local sig = contract.selector
      local holes = holes_by_func[f.func]
      tiles[#tiles + 1] = {
        tile_id = #tiles + 1,
        func = f.func,
        form = f,
        addr = sym.addr,
        size = sym.size,
        len = #(f.ops or {}),
        packed = packed_pattern(f.ops or {}),
        pattern_num = pattern_key_number(f.ops or {}),
        pattern_lit = pattern_key_literal(f.ops or {}),
        fact = sig,
        contract = contract,
        slotmaps = assert(f.stencil_slotmaps, "grammar_result JSON missing .stencil_slotmaps; rebuild with current Stencil IR worker"),
        n_holes = holes and #(holes.holes or {}) or 0,
      }
    end
  end

  log("included_tiles=%d missing_symbols=%d zero_size=%d", #tiles, missing_sym, zero_size)

  log("loading relocations")
  load_tile_relocs(o_path, tiles, holes_by_func)

  local hole_relocs = {}
  local slotmaps = {}
  for _, t in ipairs(tiles) do
    t.hole_start = #hole_relocs
    for _, r in ipairs(t.relocs or {}) do
      hole_relocs[#hole_relocs + 1] = r
    end
    t.slotmap_start = #slotmaps
    for _, sm in ipairs(t.slotmaps or {}) do
      slotmaps[#slotmaps + 1] = sm
    end
  end
  log("hole_relocations=%d slot_maps=%d", #hole_relocs, #slotmaps)

  local l0 = {}
  local by_pattern = {}
  for _, t in ipairs(tiles) do
    if t.len == 1 and t.fact.lo == 0 and t.fact.hi == 0 then
      local op = op_int((t.form.ops or {})[1])
      if not l0[op] then l0[op] = t.tile_id end
    end
    local pk = t.pattern_num
    if not by_pattern[pk] then by_pattern[pk] = {literal=t.pattern_lit, tiles={}} end
    by_pattern[pk].tiles[#by_pattern[pk].tiles + 1] = t
  end

  local pattern_keys = {}
  for pk, _ in pairs(by_pattern) do pattern_keys[#pattern_keys + 1] = pk end
  table.sort(pattern_keys)

  local candidates = {}
  local pattern_entries = {}
  for _, pk in ipairs(pattern_keys) do
    local group = by_pattern[pk]
    table.sort(group.tiles, function(a, b)
      if a.fact.pop ~= b.fact.pop then return a.fact.pop > b.fact.pop end
      if a.size ~= b.size then return a.size > b.size end
      return a.tile_id < b.tile_id
    end)
    local start = #candidates
    for _, t in ipairs(group.tiles) do candidates[#candidates + 1] = t.tile_id end
    pattern_entries[#pattern_entries + 1] = {literal=group.literal, start=start, count=#group.tiles}
  end

  log("patterns=%d candidates=%d", #pattern_entries, #candidates)

  local out = {}
  local function e(s) out[#out + 1] = s end

  e("/* Generated by src/build_bank.lua */")
  e("#include <stdint.h>")
  e("#include <stddef.h>")
  e("#include <stdlib.h>")
  e("#include \"sponbank.h\"")
  e("")
  e("typedef struct { uint64_t pattern_key; uint32_t start; uint32_t count; } PatternEntry;")
  e("")
  e("extern const unsigned char _binary_stencils_text_bin_start[];")
  e("#define spon_data ((const unsigned char *)_binary_stencils_text_bin_start)")
  e("")

  e("static const SponHoleReloc spon_holes[] = {")
  for _, r in ipairs(hole_relocs) do
    e(string.format("  {%d, %d, %d, %d, %d, %d},",
      r.code_offset, r.hole_id, r.reloc_kind, r.role_kind, r.op_idx, r.role_arg))
  end
  e("};")
  e(string.format("static const uint32_t spon_hole_count = %d;", #hole_relocs))
  e("")

  e("static const SponSlotMapEntry spon_slotmaps[] = {")
  for _, sm in ipairs(slotmaps) do
    e(string.format("  {%d, %d, %d},", sm.op_idx, sm.logical_slot, sm.field_kind))
  end
  e("};")
  e(string.format("static const uint32_t spon_slotmap_count = %d;", #slotmaps))
  e("")

  e("static const SponTileDesc spon_tiles[] = {")
  for _, t in ipairs(tiles) do
    e(string.format("  {%d, %d, %d, %d, %d, %d, %d, %d, %d, %s, %s, %s, %s, %s, %s}, /* %s */",
      t.tile_id, t.addr, t.size, t.hole_start or 0, t.slotmap_start or 0,
      t.len, t.n_holes, #(t.slotmaps or {}), t.flags or 0,
      t.fact.literal, t.pattern_lit,
      t.contract.required.literal, t.contract.checked.literal,
      t.contract.produced.literal, t.contract.killed.literal,
      t.func))
  end
  e("};")
  e(string.format("static const uint32_t spon_tile_count = %d;", #tiles))
  e("")

  e("static const SponTileId spon_l0[256] = {")
  local parts = {}
  for i = 0, 255 do
    parts[#parts + 1] = tostring(l0[i] or 0)
    if #parts == 16 then
      e("  " .. table.concat(parts, ", ") .. ",")
      parts = {}
    end
  end
  if #parts > 0 then e("  " .. table.concat(parts, ", ") .. ",") end
  e("};")
  e("")

  e("static const SponTileId spon_candidates[] = {")
  parts = {}
  for _, tid in ipairs(candidates) do
    parts[#parts + 1] = tostring(tid)
    if #parts == 20 then
      e("  " .. table.concat(parts, ", ") .. ",")
      parts = {}
    end
  end
  if #parts > 0 then e("  " .. table.concat(parts, ", ") .. ",") end
  e("};")
  e("")

  e("static const PatternEntry spon_patterns[] = {")
  for _, p in ipairs(pattern_entries) do
    e(string.format("  {%s, %d, %d},", p.literal, p.start, p.count))
  end
  e("};")
  e(string.format("static const uint32_t spon_pattern_count = %d;", #pattern_entries))
  e("")

  e("uint32_t spon_bank_tile_count(void) { return spon_tile_count; }")
  e("uint32_t spon_bank_pattern_count(void) { return spon_pattern_count; }")
  e("uint32_t spon_bank_hole_count(void) { return spon_hole_count; }")
  e("")
  e("const SponTileDesc *spon_get_tile(SponTileId id) {")
  e("  if (id == 0 || id > spon_tile_count) return NULL;")
  e("  return &spon_tiles[id - 1];")
  e("}")
  e("")
  e("const unsigned char *spon_tile_data(SponTileId id) {")
  e("  const SponTileDesc *t = spon_get_tile(id);")
  e("  return t ? spon_data + t->offset : NULL;")
  e("}")
  e("")
  e("const SponHoleReloc *spon_tile_holes(SponTileId id, uint32_t *out_n) {")
  e("  const SponTileDesc *t = spon_get_tile(id);")
  e("  if (!t) { if (out_n) *out_n = 0; return NULL; }")
  e("  if (out_n) *out_n = t->n_holes;")
  e("  return spon_holes + t->hole_start;")
  e("}")
  e("")
  e("const SponSlotMapEntry *spon_tile_slotmaps(SponTileId id, uint32_t *out_n) {")
  e("  const SponTileDesc *t = spon_get_tile(id);")
  e("  if (!t) { if (out_n) *out_n = 0; return NULL; }")
  e("  if (out_n) *out_n = t->n_slotmaps;")
  e("  return spon_slotmaps + t->slotmap_start;")
  e("}")
  e("")
  e("SponTileId spon_l0_for_opcode(uint32_t opcode) {")
  e("  return opcode < 256 ? spon_l0[opcode] : 0;")
  e("}")
  e("")
  e("static const PatternEntry *find_pattern(uint64_t key) {")
  e("  uint32_t lo = 0, hi = spon_pattern_count;")
  e("  while (lo < hi) {")
  e("    uint32_t mid = lo + ((hi - lo) >> 1);")
  e("    uint64_t mk = spon_patterns[mid].pattern_key;")
  e("    if (mk == key) return &spon_patterns[mid];")
  e("    if (mk < key) lo = mid + 1; else hi = mid;")
  e("  }")
  e("  return NULL;")
  e("}")
  e("")
  e("static uint64_t make_pattern_key(const uint32_t *bc, uint32_t pc, uint32_t len) {")
  e("  uint32_t packed = 0;")
  e("  for (uint32_t i = 0; i < len; i++) packed |= ((bc[pc + i] & 0xffu) << (i * 8));")
  e("  return (((uint64_t)len) << 32) | (uint64_t)packed;")
  e("}")
  e("")
  e("static int actual_slot_lookup(const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint16_t op_idx, uint8_t field_kind, uint8_t *out_slot);")
  e("")
  e("static SponFactSig remap_tile_sig(const SponTileDesc *t, SponFactSig sig, const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint32_t pc_base, int strict_slots) {")
  e("  if (!t || !actual_slots) return sig;")
  e("  uint8_t seen[8] = {0};")
  e("  uint8_t map[8] = {0};")
  e("  uint32_t nsm = 0;")
  e("  const SponSlotMapEntry *sms = spon_tile_slotmaps(t->tile_id, &nsm);")
  e("  for (uint32_t i = 0; i < nsm; i++) {")
  e("    uint8_t logical = sms[i].logical_slot;")
  e("    if (logical >= 8) continue;")
  e("    uint8_t actual = 0;")
  e("    if (!actual_slot_lookup(actual_slots, n_actual_slots, (uint16_t)(pc_base + sms[i].op_idx), sms[i].field_kind, &actual)) continue;")
  e("    seen[logical] = 1; map[logical] = actual;")
  e("  }")
  e("  SponFactSig out = sig & 0x7f00000000000000ULL;")
  e("  static const uint8_t bases[] = {0,8,16,24,32,40,48};")
  e("  for (uint32_t bi = 0; bi < sizeof(bases); bi++) {")
  e("    uint8_t base = bases[bi];")
  e("    for (uint8_t slot = 0; slot < 8; slot++) {")
  e("      SponFactSig bit = ((SponFactSig)1) << (base + slot);")
  e("      if ((sig & bit) == 0) continue;")
  e("      if (!seen[slot] || map[slot] >= 8) { if (strict_slots) out |= 0x8000000000000000ULL; continue; }")
  e("      uint8_t dst = map[slot];")
  e("      out |= ((SponFactSig)1) << (base + dst);")
  e("    }")
  e("  }")
  e("  return out;")
  e("}")
  e("")
  e("static SponFactSig apply_transfer(SponFactSig facts, const SponTileDesc *t, const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint32_t pc_base) {")
  e("  if (!t) return facts;")
  e("  SponFactSig killed = remap_tile_sig(t, t->killed_sig, actual_slots, n_actual_slots, pc_base, 0);")
  e("  SponFactSig produced = remap_tile_sig(t, t->produced_sig, actual_slots, n_actual_slots, pc_base, 0);")
  e("  SponFactSig checked = remap_tile_sig(t, t->checked_sig, actual_slots, n_actual_slots, pc_base, 0);")
  e("  facts &= ~killed;")
  e("  facts |= produced;")
  e("  facts |= checked;")
  e("  return facts;")
  e("}")
  e("")
  e("static const SponTileChoice *select_impl(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig observed_sig, uint32_t *out_n, SponSelectStats *stats) {")
  e("  static __thread SponTileChoice choices[4096];")
  e("  uint32_t n = 0;")
  e("  uint32_t pc = start;")
  e("  uint64_t probes = 0, checks = 0;")
  e("  while (pc < end && n < 4096) {")
  e("    SponTileId chosen = 0;")
  e("    uint32_t chosen_len = 1;")
  e("    for (int len = 4; len >= 1; len--) {")
  e("      if (pc + (uint32_t)len > end) continue;")
  e("      probes++;")
  e("      const PatternEntry *pe = find_pattern(make_pattern_key(bc, pc, (uint32_t)len));")
  e("      if (!pe) continue;")
  e("      for (uint32_t i = 0; i < pe->count; i++) {")
  e("        checks++;")
  e("        SponTileId tid = spon_candidates[pe->start + i];")
  e("        const SponTileDesc *t = spon_get_tile(tid);")
  e("        if (t && ((t->fact_sig & ~observed_sig) == 0)) { chosen = tid; chosen_len = (uint32_t)len; break; }")
  e("      }")
  e("      if (chosen) break;")
  e("    }")
  e("    if (!chosen) chosen = spon_l0_for_opcode(bc[pc] & 0xffu);")
  e("    choices[n].tile_id = chosen;")
  e("    choices[n].pc_start = pc;")
  e("    choices[n].pc_end = pc + chosen_len;")
  e("    n++;")
  e("    pc += chosen_len;")
  e("  }")
  e("  if (out_n) *out_n = n;")
  e("  if (stats) { stats->pattern_probes = probes; stats->candidate_checks = checks; stats->choices = n; }")
  e("  return choices;")
  e("}")
  e("")
  e("static int actual_slot_lookup(const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint16_t op_idx, uint8_t field_kind, uint8_t *out_slot) {")
  e("  for (uint32_t i = 0; i < n_actual_slots; i++) {")
  e("    if (actual_slots[i].op_idx == op_idx && actual_slots[i].field_kind == field_kind) { *out_slot = actual_slots[i].logical_slot; return 1; }")
  e("  }")
  e("  return 0;")
  e("}")
  e("")
  e("static int tile_matches_actual_slots(const SponTileDesc *t, const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint32_t pc_base) {")
  e("  if (!actual_slots) return 1;")
  e("  uint8_t seen[256] = {0};")
  e("  uint8_t map[256] = {0};")
  e("  uint8_t actual_seen[256] = {0};")
  e("  uint8_t actual_map[256] = {0};")
  e("  uint32_t nsm = 0;")
  e("  const SponSlotMapEntry *sms = spon_tile_slotmaps(t->tile_id, &nsm);")
  e("  for (uint32_t i = 0; i < nsm; i++) {")
  e("    uint8_t actual = 0;")
  e("    if (!actual_slot_lookup(actual_slots, n_actual_slots, (uint16_t)(pc_base + sms[i].op_idx), sms[i].field_kind, &actual)) return 0;")
  e("    uint8_t logical = sms[i].logical_slot;")
  e("    if (seen[logical] && map[logical] != actual) return 0;")
  e("    if (actual_seen[actual] && actual_map[actual] != logical) return 0;")
  e("    seen[logical] = 1;")
  e("    map[logical] = actual;")
  e("    actual_seen[actual] = 1;")
  e("    actual_map[actual] = logical;")
  e("  }")
  e("  return 1;")
  e("}")
  e("")
  e("static const SponTileChoice *select_flow_impl(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig entry_sig, SponFactSig observed_sig, uint16_t required_tile_flags, const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint32_t *out_n, SponSelectStats *stats) {")
  e("  static __thread SponTileChoice choices[4096];")
  e("  uint32_t n = 0;")
  e("  uint32_t pc = start;")
  e("  SponFactSig facts = entry_sig;")
  e("  uint64_t probes = 0, checks = 0;")
  e("  while (pc < end && n < 4096) {")
  e("    SponFactSig available_sig = observed_sig | facts;")
  e("    SponTileId chosen = 0;")
  e("    uint32_t chosen_len = 1;")
  e("    const SponTileDesc *chosen_t = NULL;")
  e("    for (int len = 4; len >= 1; len--) {")
  e("      if (pc + (uint32_t)len > end) continue;")
  e("      probes++;")
  e("      const PatternEntry *pe = find_pattern(make_pattern_key(bc, pc, (uint32_t)len));")
  e("      if (!pe) continue;")
  e("      for (uint32_t i = 0; i < pe->count; i++) {")
  e("        checks++;")
  e("        SponTileId tid = spon_candidates[pe->start + i];")
  e("        const SponTileDesc *t = spon_get_tile(tid);")
  e("        if (t && ((t->flags & required_tile_flags) == required_tile_flags) && tile_matches_actual_slots(t, actual_slots, n_actual_slots, pc)) {")
  e("          SponFactSig tfact = remap_tile_sig(t, t->fact_sig, actual_slots, n_actual_slots, pc, 1);")
  e("          SponFactSig treq = remap_tile_sig(t, t->required_sig, actual_slots, n_actual_slots, pc, 1);")
  e("          if (((tfact & ~available_sig) == 0) && ((treq & ~facts) == 0)) { chosen = tid; chosen_len = (uint32_t)len; chosen_t = t; break; }")
  e("        }")
  e("      }")
  e("      if (chosen) break;")
  e("    }")
  e("    if (!chosen) { chosen = spon_l0_for_opcode(bc[pc] & 0xffu); chosen_t = spon_get_tile(chosen); chosen_len = 1; }")
  e("    choices[n].tile_id = chosen;")
  e("    choices[n].pc_start = pc;")
  e("    choices[n].pc_end = pc + chosen_len;")
  e("    n++;")
  e("    facts = apply_transfer(facts, chosen_t, actual_slots, n_actual_slots, pc);")
  e("    pc += chosen_len;")
  e("  }")
  e("  if (out_n) *out_n = n;")
  e("  if (stats) { stats->pattern_probes = probes; stats->candidate_checks = checks; stats->choices = n; }")
  e("  return choices;")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_greedy_stats(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig sig, uint32_t *out_n, SponSelectStats *stats) {")
  e("  return select_impl(bc, start, end, sig, out_n, stats);")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_greedy(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig sig, uint32_t *out_n) {")
  e("  return select_impl(bc, start, end, sig, out_n, NULL);")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_flow_stats(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig entry_sig, SponFactSig observed_sig, uint32_t *out_n, SponSelectStats *stats) {")
  e("  return select_flow_impl(bc, start, end, entry_sig, observed_sig, 0, NULL, 0, out_n, stats);")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_flow(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig entry_sig, SponFactSig observed_sig, uint32_t *out_n) {")
  e("  return select_flow_impl(bc, start, end, entry_sig, observed_sig, 0, NULL, 0, out_n, NULL);")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_flow_flags_stats(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig entry_sig, SponFactSig observed_sig, uint16_t required_tile_flags, uint32_t *out_n, SponSelectStats *stats) {")
  e("  return select_flow_impl(bc, start, end, entry_sig, observed_sig, required_tile_flags, NULL, 0, out_n, stats);")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_flow_flags(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig entry_sig, SponFactSig observed_sig, uint16_t required_tile_flags, uint32_t *out_n) {")
  e("  return select_flow_impl(bc, start, end, entry_sig, observed_sig, required_tile_flags, NULL, 0, out_n, NULL);")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_flow_flags_slots_stats(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig entry_sig, SponFactSig observed_sig, uint16_t required_tile_flags, const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint32_t *out_n, SponSelectStats *stats) {")
  e("  return select_flow_impl(bc, start, end, entry_sig, observed_sig, required_tile_flags, actual_slots, n_actual_slots, out_n, stats);")
  e("}")
  e("")
  e("const SponTileChoice *spon_select_flow_flags_slots(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig entry_sig, SponFactSig observed_sig, uint16_t required_tile_flags, const SponSlotMapEntry *actual_slots, uint32_t n_actual_slots, uint32_t *out_n) {")
  e("  return select_flow_impl(bc, start, end, entry_sig, observed_sig, required_tile_flags, actual_slots, n_actual_slots, out_n, NULL);")
  e("}")

  local source = table.concat(out, "\n") .. "\n"
  local out_path = output_dir .. "/libsponbank.c"
  assert(Util.write_file(out_path, source))
  log("generated metadata C: %d bytes", #source)
  log("done in %ds", os.time() - started)
  return out_path
end

if arg and arg[0] and arg[0]:match("build_bank%.lua$") then
  M.build_bank(arg[1] or "build/cp_lib/stencils.o", tonumber(arg[2] or "16"), arg[3] or "build/cp_lib")
end

return M
