#!/usr/bin/env luajit
-- gen_foundry_cache.lua — Read foundry output, emit C region functions + cache
-- descriptors for the SponJIT PUC VM.
--
-- Uses the same enumeration pipeline as the foundry. For each unique form,
-- generates a C region function and a scan descriptor that sponjit_scan_proto
-- uses to install it at runtime.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/gen_foundry_cache%.lua$") or "experiments/lua_interpreter_vm/spongejit"
package.path = spongejit .. "/src/?.lua;" .. spongejit .. "/?.lua;" .. package.path

local Util = require("src.util")
local SSA = require("src.ssa")
local E = require("src.enumerate")
local Loader = require("src.loader")

local function q(s) return '"' .. tostring(s):gsub('"', '\\"') .. '"' end

-- ── SSA op → C code emitter ──────────────────────────────────────────

-- Each emitter takes: active_ops (array of node names), chunk_offset (which
-- op in the sequence), indent. Returns C code string.

local EMITTERS = {}

-- The active_ops list from SSA enumeration is a sequence of SSA node names
-- (strings like "load_slot", "guard_i64", "add_i64", etc.). We emit the
-- corresponding C operations.

local function next_chunk(ops, i)
  if i > #ops then return nil end
  local op = ops[i]
  local emitter = EMITTERS[op]
  if not emitter then return nil, "no emitter for " .. op end
  return emitter(ops, i)
end

function EMITTERS.load_slot(ops, i)
  return { code = "    /* load_slot: ra = s2v(base + RA(i)) */", consumed = 1 }
end

function EMITTERS.store_slot(ops, i)
  return { code = "    /* store_slot: s2v(base + RA(i)) = ra */", consumed = 1 }
end

function EMITTERS.guard_i64(ops, i)
  return { code = "    /* guard_i64: assert ttisinteger(s2v(base + ...)) */", consumed = 1 }
end

function EMITTERS.guard_table(ops, i)
  return { code = "    /* guard_table: assert ttis table */", consumed = 1 }
end

function EMITTERS.guard_shape(ops, i)
  return { code = "    /* guard_shape: assert shape matches */", consumed = 1 }
end

function EMITTERS.guard_metatable_absent(ops, i)
  return { code = "    /* guard_metatable_absent: assert metatable == NULL */", consumed = 1 }
end

function EMITTERS.unbox_i64(ops, i)
  return { code = "    /* unbox_i64 */", consumed = 1 }
end

function EMITTERS.box_i64(ops, i)
  return { code = "    /* box_i64 */", consumed = 1 }
end

function EMITTERS.add_i64(ops, i)
  return { code = "    /* add_i64 */", consumed = 1 }
end

function EMITTERS.const_i64(ops, i)
  return { code = "    /* const_i64 */", consumed = 1 }
end

function EMITTERS.const_nil(ops, i)
  return { code = "    /* const_nil */", consumed = 1 }
end

function EMITTERS.const_bool(ops, i)
  return { code = "    /* const_bool */", consumed = 1 }
end

function EMITTERS.return1(ops, i)
  return { code = "    /* return1 */", consumed = 1 }
end

function EMITTERS.return0(ops, i)
  return { code = "    /* return0 */", consumed = 1 }
end

function EMITTERS.call_boundary(ops, i)
  return { code = "    /* call_boundary */", consumed = 1 }
end

function EMITTERS.tailcall_boundary(ops, i)
  return { code = "    /* tailcall_boundary */", consumed = 1 }
end

function EMITTERS.table_field_load(ops, i)
  return { code = "    /* table_field_load */", consumed = 1 }
end

function EMITTERS.table_field_store(ops, i)
  return { code = "    /* table_field_store */", consumed = 1 }
end

function EMITTERS.residual_boundary(ops, i)
  return { code = "    /* residual_boundary */", consumed = 1 }
end

function EMITTERS.guard_call_target(ops, i)
  return { code = "    /* guard_call_target */", consumed = 1 }
end

function EMITTERS.move_value(ops, i)
  return { code = "    /* move_value */", consumed = 1 }
end

function EMITTERS.jump(ops, i)
  return { code = "    /* jump */", consumed = 1 }
end

function EMITTERS.branch(ops, i)
  return { code = "    /* branch */", consumed = 1 }
end

-- ── Form → C code generation ────────────────────────────────────────

local function sanitize(s)
  return (tostring(s or ""):gsub("[^%w_]", "_"))
end

local function form_id(form)
  local nf = table.concat(form.normal_form or {}, "_")
  if #nf > 48 then nf = nf:sub(1, 48) end
  return "f_" .. sanitize(nf)
end

local function emit_region_function(form, form_idx)
  local ops = form.active_ops or {}
  local lines = {}
  local fid = form_id(form) .. "_" .. tostring(form_idx)

  lines[#lines + 1] = ""
  lines[#lines + 1] = "/* Form: " .. (form.description or table.concat(form.source_ops or {}, "|")) .. " */"
  lines[#lines + 1] = "/*   source_ops = " .. table.concat(form.source_ops or {}, " ") .. " */"
  lines[#lines + 1] = "/*   active_ops = " .. table.concat(ops, " ") .. " */"
  lines[#lines + 1] = "static void sponjit_region_" .. fid .. "(lua_State *L, CallInfo *ci, StkId base,"
  lines[#lines + 1] = "                                  TValue *k, LClosure *cl,"
  lines[#lines + 1] = "                                  const Instruction *pc_,"
  lines[#lines + 1] = "                                  const Instruction **ret_pc) {"

  for i = 1, #ops do
    local result, err = next_chunk(ops, i)
    if result then
      lines[#lines + 1] = result.code
    else
      lines[#lines + 1] = "    /* UNKNOWN: " .. tostring(err) .. " */"
    end
  end

  local nops = #(form.source_ops or {})
  lines[#lines + 1] = "    *ret_pc = pc_ + " .. nops .. ";"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n"), fid
end

local function emit_scan_entry(form, fid, form_idx)
  local src_ops = form.source_ops or {}
  local pattern = {}
  for _, op in ipairs(src_ops) do
    pattern[#pattern + 1] = "OP_" .. op
  end
  local n = #src_ops
  if n < 1 then return nil end

  return string.format('  { .opcodes = {%s}, .nops = %d, .region_fn = sponjit_region_%s }',
    table.concat(pattern, ", "), n, fid)
end

-- ── produce.h ────────────────────────────────────────────────────────

local function emit_header(forms, scan_entries)
  local out = {}
  out[#out + 1] = "/* Auto-generated by gen_foundry_cache.lua — " .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. " */"
  out[#out + 1] = "/* Forms: " .. #forms .. " */"
  out[#out + 1] = ""
  out[#out + 1] = "#ifndef SPONJIT_GENERATED_FORMS_H"
  out[#out + 1] = "#define SPONJIT_GENERATED_FORMS_H"
  out[#out + 1] = ""

  -- Forward declarations
  for _, entry in ipairs(scan_entries) do
    out[#out + 1] = "static void " .. entry.fn_name .. "(lua_State *, CallInfo *, StkId, TValue *, LClosure *, const Instruction *, const Instruction **);"
  end

  out[#out + 1] = ""
  out[#out + 1] = "/* Scan descriptor: tells sponjit_scan_proto what to look for */"
  out[#out + 1] = "typedef struct {"
  out[#out + 1] = "    OpCode opcodes[8];"
  out[#out + 1] = "    int nops;"
  out[#out + 1] = "    SponJitRegionFn region_fn;"
  out[#out + 1] = "} SponJitFormDesc;"
  out[#out + 1] = ""
  out[#out + 1] = "static SponJitFormDesc sponjit_forms[] = {"

  for _, entry in ipairs(scan_entries) do
    out[#out + 1] = "    " .. entry.scan_line .. ","
  end

  out[#out + 1] = "};"
  out[#out + 1] = "#define SPONJIT_FORM_COUNT " .. #scan_entries
  out[#out + 1] = ""
  out[#out + 1] = "#endif /* SPONJIT_GENERATED_FORMS_H */"
  return table.concat(out, "\n")
end

-- ── Main ─────────────────────────────────────────────────────────────

local function main()
  local config = {
    max_files = 200,
    max_regions = 10000,
    max_windows = 50000,
    max_fact_combos = 1024,
    max_arity = 4,
    max_forms = 100,      -- top N forms to generate
    corpus_root = "lua/moonlift",
    out_dir = spongejit .. "/build",
  }

  -- Parse args
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--max-forms" then config.max_forms = tonumber(arg[i+1]); i = i + 1
    elseif a == "--corpus" then config.corpus_root = arg[i+1]; i = i + 1
    elseif a == "--out" then config.out_dir = arg[i+1]; i = i + 1
    end
    i = i + 1
  end

  print("[gen] loading corpus from " .. config.corpus_root)
  local profile = Loader.profile_lua_root(config.corpus_root, { max_files = config.max_files })
  local ws = Loader.workloads_from_profile(profile, {
    max_regions = config.max_regions, max_len = 6, min_len = 2, fact_mode = "balanced",
  })
  print("[gen] workloads: " .. #ws)

  print("[gen] enumerating forms...")
  local result = E.enumerate(ws, {
    max_arity = config.max_arity,
    max_windows = config.max_windows,
    max_fact_axes = 12,
    max_fact_combos = config.max_fact_combos,
  })
  local all_forms = result.forms or {}
  print(string.format("[gen] %d windows → %d compiles → %d unique forms",
    result.stats.windows or 0, result.stats.compiles or 0, #all_forms))

  -- Take top N
  local top_n = math.min(config.max_forms, #all_forms)
  local top = {}
  for j = 1, top_n do top[j] = all_forms[j] end
  print("[gen] generating C code for top " .. top_n .. " forms")

  -- Generate
  local scan_entries = {}
  local fn_bodies = {}
  for fi, form in ipairs(top) do
    local body, fid = emit_region_function(form, fi)
    fn_bodies[#fn_bodies + 1] = body
    local scan_line = emit_scan_entry(form, fid, fi)
    if scan_line then
      scan_entries[#scan_entries + 1] = { fn_name = "sponjit_region_" .. fid, scan_line = scan_line }
    end
  end

  local header = emit_header(top, scan_entries)
  local out_h = config.out_dir .. "/generated_forms.h"
  local out_c = config.out_dir .. "/generated_forms.c"

  Util.mkdir_p(config.out_dir)

  local c_code = {}
  c_code[#c_code + 1] = '/* Auto-generated by gen_foundry_cache.lua */'
  c_code[#c_code + 1] = '#include "lvm.h"'
  c_code[#c_code + 1] = '#include "generated_forms.h"'
  c_code[#c_code + 1] = ''
  for _, body in ipairs(fn_bodies) do
    c_code[#c_code + 1] = body
  end
  c_code[#c_code + 1] = ''

  Util.write_file(out_h, header)
  Util.write_file(out_c, table.concat(c_code, "\n"))
  print(string.format("[gen] wrote %s (%d bytes)", out_h, #header))
  print(string.format("[gen] wrote %s (%d bytes)", out_c, #table.concat(c_code, "")))
  print("[gen] done")
end

if arg and #arg > 0 then
  main()
end

return { main = main }
