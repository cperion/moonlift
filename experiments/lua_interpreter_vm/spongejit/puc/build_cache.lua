#!/usr/bin/env luajit
-- build_cache.lua - Bridge foundry → stencil → embedded C cache.
--
-- At build time: enumerate forms, lower to stencil chains, emit C code
-- containing real stencil bytes + cache descriptors.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/build_cache%.lua$") or "experiments/lua_interpreter_vm/spongejit"
package.path = spongejit .. "/src/?.lua;" .. spongejit .. "/runtime/?.lua;" .. spongejit .. "/?.lua;" .. package.path

local Util = require("src.util")
local SSA = require("src.ssa")
local E = require("src.enumerate")
local Loader = require("src.loader")
local StencilModel = require("src.stencil_model")

-- ── Helpers ────────────────────────────────────────────────────────
local function sanitize(s) return (tostring(s or ""):gsub("[^%w_]", "_")) end

local hole_kind_map = {
  slot_offset = 0, field_offset = 1, array_base = 2, const_idx = 3,
  shape_id = 4, call_target = 5, barrier_color = 6, target_pc = 7,
  exit_addr = 8, resume_pc = 9, immediate_i64 = 10, index_scale = 11,
}
local function hole_kind_id(k) return hole_kind_map[k] or 0 end

if not table.map then
  table.map = function(t, f)
    local out = {}
    for _, v in ipairs(t) do out[#out + 1] = f(v) end
    return out
  end
end

-- ── Stencil data ───────────────────────────────────────────────────
local function load_stencil_bytes(json_path)
  local lib = assert(Util.read_json(json_path), "cannot read " .. json_path)
  local stencils = lib.stencils or {}
  local result = {}
  local n = 0
  for name, s in pairs(stencils) do
    local hex = s.bytes_hex or ""
    local bytes = {}
    for b in hex:gmatch("%x%x") do bytes[#bytes + 1] = tonumber(b, 16) end
    result[name] = { bytes = bytes, size = #bytes, holes = s.holes or {} }
    n = n + 1
  end
  print("[build-cache] stencils: " .. n)
  return result
end

local function find_rets(bytes)
  local out = {}
  for i = 1, #bytes do if bytes[i] == 0xC3 then out[#out + 1] = i end end
  return out
end

local function hex_from_bytes(bytes)
  local out = {}
  for i = 1, #bytes do out[i] = string.format("0x%02x", bytes[i]) end
  return out
end

-- ── Enumerate ─────────────────────────────────────────────────────
local function enumerate(config)
  print("[build-cache] corpus: " .. config.corpus)
  local profile = Loader.profile_lua_root(config.corpus, { max_files = config.max_files })
  local ws = Loader.workloads_from_profile(profile, {
    max_regions = config.max_regions, max_len = 6, min_len = 2, fact_mode = "balanced",
  })
  print("[build-cache] workloads: " .. #ws)
  local result = E.enumerate(ws, {
    max_arity = config.max_arity, max_windows = config.max_windows,
    max_fact_axes = 12, max_fact_combos = config.max_fact_combos,
  })
  local forms = result.forms or {}
  print(string.format("[build-cache] %d windows → %d compiles → %d forms",
    result.stats.windows or 0, result.stats.compiles or 0, #forms))
  return forms
end

-- ── Build chain ────────────────────────────────────────────────────
-- Safety note:
-- Default cache output includes only opcode-complete, side-effect-contained
-- forms implemented by stencils_puc.c. Boundary/table/call/return forms can
-- still be emitted with --allow-unsafe for research, but are not installed in
-- correctness runs.
local UNSAFE_ACTIVE_OPS = {
  guard_table = true, guard_shape = true, guard_metatable_absent = true,
  guard_call_target = true, guard_array_hit = true, guard_bounds = true,
  call_boundary = true, call_boundary_known = true, tailcall_boundary = true,
  return0 = true, return1 = true, returnN = true,
  jump = true, branch = true,
  table_field_load = true, table_field_store = true,
  table_array_load = true, table_array_store = true,
  table_global_load = true, table_global_store = true,
  barrier_check = true, const_f64 = true, box_f64 = true, unbox_f64 = true,
  add_f64 = true, cmp_i64 = true, truthy_test = true,
}

local function source_ops_of(form)
  local src = form.source_ops or {}
  if #src > 0 then return src end
  local out, sk = {}, form.source_key or ""
  for part in sk:gmatch("[^|]+") do
    local opname = part:match("^(%w+)%(")
    if opname then out[#out + 1] = opname end
  end
  return out
end

local function normalized_ops(ops)
  local out = {}
  for _, op in ipairs(ops or {}) do
    -- guard_i64 is safe and redundant with unbox/add checks; ignore it for
    -- opcode-completeness matching while still keeping it in emitted chains.
    if op ~= "guard_i64" then out[#out + 1] = op end
  end
  return table.concat(out, " ")
end

local SAFE_PATTERNS = {
  ["MOVE"] = { ["load_slot store_slot"] = true },
  ["LOADI"] = { ["const_i64 box_i64 store_slot"] = true },
  ["LOADK"] = { ["load_const store_slot"] = true },
  ["LOADFALSE"] = { ["const_bool store_slot"] = true },
  ["LOADTRUE"] = { ["const_bool store_slot"] = true },
  ["ADDI|MMBINI"] = { ["load_slot unbox_i64 const_i64 add_i64 box_i64 store_slot residual_boundary"] = true },
  ["ADD|MMBIN"] = { ["load_slot unbox_i64 load_slot unbox_i64 add_i64 box_i64 store_slot residual_boundary"] = true },
  ["SUB|MMBIN"] = { ["load_slot unbox_i64 load_slot unbox_i64 sub_i64 box_i64 store_slot residual_boundary"] = true },
  ["MUL|MMBIN"] = { ["load_slot unbox_i64 load_slot unbox_i64 mul_i64 box_i64 store_slot residual_boundary"] = true },
}

local function executable_form_safe(form)
  local ops = form.active_ops or {}
  if #ops == 0 then return false, "empty chain" end
  for _, op in ipairs(ops) do
    if UNSAFE_ACTIVE_OPS[op] then return false, "unsafe stencil: " .. tostring(op) end
  end
  local src = source_ops_of(form)
  local src_key = table.concat(src, "|")
  local allowed = SAFE_PATTERNS[src_key]
  if not allowed then return false, "unsupported opcode pattern: " .. tostring(src_key) end
  local key = normalized_ops(ops)
  if not allowed[key] then return false, "incomplete stencil chain for " .. tostring(src_key) .. ": " .. key end
  return true
end

local function build_chain(form, stencil_data)
  local ops = form.active_ops or {}
  local chain = {}
  for _, op in ipairs(ops) do
    local sn = "stencil_" .. op
    local data = stencil_data[sn]
    if not data then data = stencil_data[op] end
    if not data then return nil, "no stencil: " .. tostring(op) end
    chain[#chain + 1] = data
  end
  return chain
end

local function put_i32_le(bytes, pos1, v)
  if v < 0 then v = v + 0x100000000 end
  bytes[pos1] = bit.band(v, 0xff)
  bytes[pos1 + 1] = bit.band(bit.rshift(v, 8), 0xff)
  bytes[pos1 + 2] = bit.band(bit.rshift(v, 16), 0xff)
  bytes[pos1 + 3] = bit.band(bit.rshift(v, 24), 0xff)
end

local function concat_chain(chain)
  local bytes = {}; local holes = {}; local offset = 0

  -- Fallthrough linking: RET \226\134\146 NOP. Safe with structured IF_OK control flow.
  for _, s in ipairs(chain) do
    local start0 = offset
    local ret_offsets = {}
    for _, r in ipairs(find_rets(s.bytes)) do ret_offsets[r] = true end
    for i = 1, #s.bytes do
      bytes[#bytes + 1] = ret_offsets[i] and 0x90 or s.bytes[i]
    end
    for _, h in ipairs(s.holes) do
      holes[#holes + 1] = { offset = start0 + (h.offset or 0), size = h.size or 4,
        kind = (tostring(h.kind or ""):gsub("^hole_", "")) }
    end
    offset = offset + #s.bytes
  end
  bytes[#bytes + 1] = 0xC3  -- final ret returns to caller
  offset = offset + 1
  return bytes, holes, offset
end

-- ── Emit C ─────────────────────────────────────────────────────────
local function emit_c(entries, opts)
  local lines = {}
  lines[#lines + 1] = "/* Auto-generated by build_cache.lua */"
  lines[#lines + 1] = "#include <string.h>"
  lines[#lines + 1] = "#include <sys/mman.h>"
  lines[#lines + 1] = "#include <stdint.h>"
  lines[#lines + 1] = ""

  local descs = {}
  for _, e in ipairs(entries) do
    local f, bytes, holes = e.form, e.bytes, e.holes
    local src_ops = f.source_ops or {}; if #src_ops == 0 then local sk = f.source_key or ''; src_ops = {}; for part in sk:gmatch('[^|]+') do local opname = part:match('^(%w+)%('); if opname then src_ops[#src_ops + 1] = opname end end end; local nops = #src_ops
    local fid = sanitize("f" .. e.idx .. "_" .. table.concat(f.active_ops or {}, "_"))

    lines[#lines + 1] = string.format("/* %s → %s */", table.concat(f.source_ops or {}, " "), table.concat(f.active_ops or {}, " "))
    lines[#lines + 1] = string.format("/* score=%d bytes=%d */", f.count or 1, #bytes)

    if #bytes == 0 then
      lines[#lines + 1] = string.format("static unsigned char sponjit_code_%s[] = { 0xC3 };", fid)
    else
      local hex = hex_from_bytes(bytes)
      local cname = "sponjit_code_" .. fid
      lines[#lines + 1] = string.format("static unsigned char %s[] = {", cname)
      local row = {}
      for i, hx in ipairs(hex) do
        row[#row + 1] = hx
        if #row >= 12 then
          lines[#lines + 1] = "  " .. table.concat(row, ", ") .. ","
          row = {}
        end
      end
      if #row > 0 then lines[#lines + 1] = "  " .. table.concat(row, ", ") .. "," end
      lines[#lines + 1] = "  0xC3 /* ret */"
      lines[#lines + 1] = "};"
    end

    if #holes > 0 then
      local hname = "sponjit_holes_" .. fid
      lines[#lines + 1] = string.format("static SponJitHole %s[] = {", hname)
      for _, h in ipairs(holes) do
        lines[#lines + 1] = string.format("  { .offset = %d, .size = %d, .kind = %d },", h.offset, h.size, hole_kind_id(h.kind))
      end
      lines[#lines + 1] = "};"
    end

    local src_ops = f.source_ops or {}
    if #src_ops == 0 then
      -- Extract from source_key which has format like "OP(...)|OP(...)|..."
      local sk = f.source_key or ""
      src_ops = {}
      for part in sk:gmatch("[^|]+") do
        local opname = part:match("^(%w+)%(")
        if opname then src_ops[#src_ops + 1] = opname end
      end
    end
    local nops_val = math.max(1, #src_ops)
    local pattern = "{}"
    if #src_ops > 0 then
      pattern = "{" .. table.concat(table.map(src_ops, function(o) return "OP_" .. tostring(o) end), ", ") .. "}"
    end
    local code_size = math.max(1, #bytes + 1)
    local hname = #holes > 0 and ("sponjit_holes_" .. fid) or "NULL"
    descs[#descs + 1] = string.format("  { .opcodes = %s, .nops = %d, .code = sponjit_code_%s, .code_size = %d, .holes = %s, .nholes = %d },",
      pattern, math.max(1, nops), fid, code_size, hname, #holes)
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "SponJitCacheDesc sponjit_cache_descs[] = {"
  if #descs == 0 then
    lines[#lines + 1] = "  { .opcodes = {}, .nops = 0, .code = NULL, .code_size = 0, .holes = NULL, .nholes = 0 },"
  else
    for _, d in ipairs(descs) do lines[#lines + 1] = d end
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = string.format("int sponjit_cache_desc_count = %d;", #entries)
  lines[#lines + 1] = string.format("int sponjit_cache_unsafe = %d;", opts and opts.allow_unsafe and 1 or 0)
  return table.concat(lines, "\n")
end

-- ── Main ───────────────────────────────────────────────────────────
local function main()
  local config = {
    corpus = "lua/moonlift", max_files = 200, max_regions = 10000,
    max_windows = 50000, max_fact_combos = 1024, max_arity = 4,
    max_forms = 30,
    allow_unsafe = false,
    stencil_lib = spongejit .. "/build/stencil_library_puc.json",
    out_dir = spongejit .. "/build",
  }
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--max-forms" then config.max_forms = tonumber(arg[i+1]); i = i + 1
    elseif a == "--corpus" then config.corpus = arg[i+1]; i = i + 1
    elseif a == "--out" then config.out_dir = arg[i+1]; i = i + 1
    elseif a == "--allow-unsafe" then config.allow_unsafe = true
    end
    i = i + 1
  end

  Util.mkdir_p(config.out_dir)
  local stencil_data = load_stencil_bytes(config.stencil_lib)
  local forms = enumerate(config)
  local top_n = math.min(config.max_forms, #forms)
  print("[build-cache] processing top " .. top_n .. " forms")

  local entries = {}
  local skipped_unsafe, skipped_missing = 0, 0
  for fi = 1, top_n do
    local f = forms[fi]
    if not config.allow_unsafe then
      local safe = executable_form_safe(f)
      if not safe then
        skipped_unsafe = skipped_unsafe + 1
      else
        local chain = assert(build_chain(f, stencil_data))
        local bytes, holes = concat_chain(chain)
        entries[#entries + 1] = { form = f, bytes = bytes, holes = holes, idx = fi }
      end
    else
      local chain, err = build_chain(f, stencil_data)
      if chain then
        local bytes, holes = concat_chain(chain)
        entries[#entries + 1] = { form = f, bytes = bytes, holes = holes, idx = fi }
      else
        skipped_missing = skipped_missing + 1
      end
    end
  end

  print(string.format("[build-cache] %d executable cache entries (%d skipped unsafe, %d skipped missing stencils)",
    #entries, skipped_unsafe, skipped_missing))
  local c_src = emit_c(entries, { allow_unsafe = config.allow_unsafe })
  local out_path = config.out_dir .. "/sponjit_cache_data.c"
  Util.write_file(out_path, c_src)
  print(string.format("[build-cache] wrote %s (%d bytes)", out_path, #c_src))
end

main()
