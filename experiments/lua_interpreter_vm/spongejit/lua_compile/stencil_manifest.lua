-- stencil_manifest.lua -- deterministic manifest/export layer for Stencil banks.
--
-- This module is intentionally VM/language agnostic. It turns validated
-- Stencil.StencilModule values into stable plain Lua data/text for storage and
-- debugging, and checks stored manifests against current modules plus optional
-- caller-supplied code blob metadata. It must not inspect Lua opcodes,
-- LalinCFG semantics, protocol tags, or interpreter/helper fallbacks.

local pvm = require("lalin.pvm")
local B = require("lua_compile.builders")
local T = B.T
local S = T.Stencil
local Key = require("lua_compile.stencil_key")
local Validate = require("lua_compile.stencil_validate")
local Bank = require("lua_compile.stencil_bank")
local Materialize = require("lua_compile.stencil_materialize")

local M = {}

M.SCHEMA = "sponjit.stencil_manifest.v1"

local function cls(v) return pvm.classof(v) end
local function is(v, c) return cls(v) == c or v == c or (cls(v) and cls(c) and cls(v) == cls(c)) end
local function add(errors, msg) errors[#errors + 1] = msg end

local function name_text(n)
  if type(n) == "table" and n.text ~= nil then return tostring(n.text) end
  return tostring(n or "")
end

local function kind_name(v)
  if type(v) ~= "table" then return tostring(v or "") end
  if v.kind ~= nil then return tostring(v.kind) end
  local c = cls(v)
  local plan = c and c.__plan and c.__plan.name
  if plan then return tostring(plan):match("%.([^%.]+)$") or tostring(plan) end
  return tostring(v)
end

local function class_name(v)
  local c = cls(v)
  local plan = c and c.__plan and c.__plan.name
  return tostring(plan or (v and v.kind) or c or type(v))
end

local function asdl_plain(v, seen)
  local tv = type(v)
  if tv ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return "<cycle>" end
  seen[v] = true
  local c = cls(v)
  if c and rawget(c, "__fields") then
    local fields = c.__fields or {}
    if #fields == 0 then
      seen[v] = nil
      return kind_name(v)
    end
    if c == S.Name then
      seen[v] = nil
      return name_text(v)
    end
    local out = { kind = kind_name(v) }
    for _, f in ipairs(fields) do out[f.name] = asdl_plain(v[f.name], seen) end
    seen[v] = nil
    return out
  end
  local out = {}
  for k, x in pairs(v) do out[k] = asdl_plain(x, seen) end
  seen[v] = nil
  return out
end

local function symbol_manifest(sym)
  return {
    name = name_text(sym.name),
    kind = kind_name(sym.kind),
    visibility = kind_name(sym.visibility),
    offset = tonumber(sym.offset) or 0,
  }
end

local function code_manifest(code)
  return {
    symbol = name_text(code.symbol),
    byte_size = tonumber(code.byte_size) or 0,
    content_hash = tostring(code.content_hash or ""),
  }
end

local function hole_manifest(hole)
  return {
    id = name_text(hole.id),
    kind = kind_name(hole.kind),
    offset = tonumber(hole.offset) or 0,
    width_bytes = tonumber(hole.width_bytes) or 0,
    encoding = asdl_plain(hole.encoding),
    source = asdl_plain(hole.source),
  }
end

local function reloc_manifest(reloc)
  return {
    id = name_text(reloc.id),
    kind = asdl_plain(reloc.kind),
    offset = tonumber(reloc.offset) or 0,
    target = symbol_manifest(reloc.target),
    addend = tonumber(reloc.addend) or 0,
  }
end

local function patch_site_manifest(site)
  return {
    hole = name_text(site.hole and site.hole.id),
    value = asdl_plain(site.value),
  }
end

local function link_step_manifest(step)
  local out = { kind = kind_name(step) }
  if is(step, S.ResolveInternalBranch) or is(step, S.ResolveInternalCall) then
    out.from = symbol_manifest(step.from)
    out.to = symbol_manifest(step.to)
  elseif is(step, S.ResolveExternalSymbol) then
    out.symbol = symbol_manifest(step.symbol)
  elseif is(step, S.ApplyReloc) then
    out.reloc = reloc_manifest(step.reloc)
  else
    out.value = asdl_plain(step)
  end
  return out
end

local function plan_manifest(plan)
  local patch_sites = {}
  for _, site in ipairs(plan.patch_sites or {}) do patch_sites[#patch_sites + 1] = patch_site_manifest(site) end
  table.sort(patch_sites, function(a, b) return tostring(a.hole) < tostring(b.hole) end)

  local link_steps = {}
  for i, step in ipairs(plan.link_steps or {}) do
    local m = link_step_manifest(step)
    m.index = i
    link_steps[#link_steps + 1] = m
  end
  table.sort(link_steps, function(a, b)
    local ak = tostring(a.kind) .. ":" .. tostring(a.index)
    local bk = tostring(b.kind) .. ":" .. tostring(b.index)
    return ak < bk
  end)

  return {
    entry = {
      symbol = symbol_manifest(plan.entry.symbol),
      abi = asdl_plain(plan.entry.abi),
    },
    patch_sites = patch_sites,
    link_steps = link_steps,
  }
end

local function template_manifest(template)
  local holes = {}
  for _, hole in ipairs(template.holes or {}) do holes[#holes + 1] = hole_manifest(hole) end
  table.sort(holes, function(a, b)
    if a.offset ~= b.offset then return a.offset < b.offset end
    return a.id < b.id
  end)

  local relocs = {}
  for _, reloc in ipairs(template.relocs or {}) do relocs[#relocs + 1] = reloc_manifest(reloc) end
  table.sort(relocs, function(a, b)
    if a.offset ~= b.offset then return a.offset < b.offset end
    return a.id < b.id
  end)

  local symbols = {}
  for _, sym in ipairs(template.local_symbols or {}) do symbols[#symbols + 1] = symbol_manifest(sym) end
  table.sort(symbols, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.offset < b.offset
  end)

  return {
    name = name_text(template.name),
    kind = kind_name(template.kind),
    variant_key = Key.variant_key(template.variant),
    code = code_manifest(template.code),
    holes = holes,
    relocs = relocs,
    local_symbols = symbols,
    plan = plan_manifest(template.plan),
  }
end

local function symbol_list_manifest(list)
  local out = {}
  for _, sym in ipairs(list or {}) do out[#out + 1] = symbol_manifest(sym) end
  table.sort(out, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.offset < b.offset
  end)
  return out
end

local function reloc_list_manifest(list)
  local out = {}
  for _, reloc in ipairs(list or {}) do out[#out + 1] = reloc_manifest(reloc) end
  table.sort(out, function(a, b)
    if a.offset ~= b.offset then return a.offset < b.offset end
    return a.id < b.id
  end)
  return out
end

local function lookup_blob(code, blobs)
  if blobs == nil then return nil, nil end
  if type(blobs) == "string" then return { bytes = blobs }, "<direct>" end
  if type(blobs) ~= "table" then return nil, nil end
  if type(blobs.bytes) == "string" or blobs.byte_size or blobs.content_hash then return blobs, "<direct>" end
  local direct = blobs[code]
  if type(direct) == "string" then return { bytes = direct }, "<code-ref>" end
  if type(direct) == "table" then return direct, "<code-ref>" end
  for _, key in ipairs({ name_text(code.symbol), tostring(code.content_hash or "") }) do
    local v = blobs[key]
    if type(v) == "string" then return { bytes = v }, key end
    if type(v) == "table" then return v, key end
  end
  return nil, nil
end

local function supplied_blob_manifest(code, blobs, errors)
  local meta, key = lookup_blob(code, blobs)
  if not meta then
    add(errors, "missing code blob for CodeBlobRef: " .. name_text(code.symbol))
    return nil
  end
  local bytes = meta.bytes
  local byte_size = meta.byte_size and tonumber(meta.byte_size) or (type(bytes) == "string" and #bytes or nil)
  local content_hash = meta.content_hash and tostring(meta.content_hash) or (type(bytes) == "string" and ("sha256:" .. Materialize.sha256_hex(bytes)) or nil)
  if not byte_size then add(errors, "missing code blob byte_size for CodeBlobRef: " .. name_text(code.symbol)) end
  if not content_hash then add(errors, "missing code blob content_hash for CodeBlobRef: " .. name_text(code.symbol)) end
  if byte_size and byte_size ~= tonumber(code.byte_size) then
    add(errors, "code blob byte_size mismatch for " .. name_text(code.symbol) .. ": expected " .. tostring(code.byte_size) .. ", got " .. tostring(byte_size))
  end
  if content_hash and content_hash ~= tostring(code.content_hash or "") then
    add(errors, "code blob content_hash mismatch for " .. name_text(code.symbol) .. ": expected " .. tostring(code.content_hash or "") .. ", got " .. tostring(content_hash))
  end
  return {
    symbol = name_text(code.symbol),
    lookup_key = tostring(key or ""),
    byte_size = byte_size or 0,
    content_hash = content_hash or "",
  }
end

local function collect_code_refs(module, errors)
  local by_symbol = {}
  local out = {}
  for _, template in ipairs(module.templates or {}) do
    local cm = code_manifest(template.code)
    local prev = by_symbol[cm.symbol]
    if prev and (prev.byte_size ~= cm.byte_size or prev.content_hash ~= cm.content_hash) then
      add(errors, "duplicate CodeBlobRef symbol with mismatched metadata: " .. cm.symbol)
    elseif not prev then
      by_symbol[cm.symbol] = cm
      out[#out + 1] = cm
    end
  end
  table.sort(out, function(a, b) return a.symbol < b.symbol end)
  return out, by_symbol
end

local function supplied_code_blob_manifest(module, code_blobs, errors)
  if code_blobs == nil then return nil end
  local seen = {}
  local out = {}
  for _, template in ipairs(module.templates or {}) do
    local sym = name_text(template.code.symbol)
    if not seen[sym] then
      seen[sym] = true
      local m = supplied_blob_manifest(template.code, code_blobs, errors)
      if m then out[#out + 1] = m end
    end
  end
  table.sort(out, function(a, b) return a.symbol < b.symbol end)
  return out
end

local function bank_manifest(module)
  local variants = {}
  for _, variant in ipairs((module.bank and module.bank.variants) or {}) do variants[#variants + 1] = Key.variant_key(variant) end
  table.sort(variants)

  local entries = {}
  for _, entry in ipairs((module.bank and module.bank.entries) or {}) do
    entries[#entries + 1] = { variant_key = Key.variant_key(entry.key), template_name = name_text(entry.template_name) }
  end
  table.sort(entries, function(a, b)
    if a.variant_key ~= b.variant_key then return a.variant_key < b.variant_key end
    return a.template_name < b.template_name
  end)

  return { variants = variants, entries = entries }
end

local function module_manifest(module, index, code_blobs, opts)
  local errors = {}
  local templates = {}
  for _, template in ipairs(module.templates or {}) do templates[#templates + 1] = template_manifest(template) end
  table.sort(templates, function(a, b) return a.name < b.name end)

  local code_refs = collect_code_refs(module, errors)
  local supplied_blobs = supplied_code_blob_manifest(module, code_blobs, errors)

  local linkage = module.linkage or S.Linkage({}, {}, {})
  local manifest = {
    schema = M.SCHEMA,
    bank = bank_manifest(module),
    templates = templates,
    code_refs = code_refs,
    symbols = symbol_list_manifest(module.symbols or {}),
    linkage = {
      exported = symbol_list_manifest(linkage.exported or {}),
      imported = symbol_list_manifest(linkage.imported or {}),
      required_relocs = reloc_list_manifest(linkage.required_relocs or {}),
    },
  }
  if supplied_blobs then manifest.code_blobs = supplied_blobs end
  if index and index.ordered_variant_keys then manifest.bank.ordered_variant_keys = index.ordered_variant_keys end
  return manifest, errors
end

local function add_prefixed(errors, prefix, list)
  for _, e in ipairs(list or {}) do add(errors, prefix .. e) end
end

function M.build(module, code_blobs, opts)
  opts = opts or {}
  local errors = {}
  local ok, verr = Validate.validate_module(module, opts.validate_opts or opts)
  if not ok then add_prefixed(errors, "", verr) end
  local index, berr = Bank.build_index(module, opts.bank_opts or opts)
  if not index then add_prefixed(errors, "", berr) end
  if #errors > 0 then return nil, errors end

  local manifest, merr = module_manifest(module, index, code_blobs, opts)
  add_prefixed(errors, "", merr)
  if #errors > 0 then return nil, errors end
  manifest.digest = M.digest(manifest)
  return manifest, {}
end

M.to_table = M.build
M.manifest = M.build
M.export = M.build

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false, 0 end
    if k > n then n = k end
  end
  for i = 1, n do if t[i] == nil then return false, n end end
  return true, n
end

local function key_literal(k)
  if type(k) == "string" and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then return k end
  return "[" .. string.format("%q", tostring(k)) .. "]"
end

local function encode(v, indent, opts)
  opts = opts or {}
  local tv = type(v)
  if tv == "nil" then return "nil" end
  if tv == "string" then return string.format("%q", v) end
  if tv == "number" or tv == "boolean" then return tostring(v) end
  if tv ~= "table" then return string.format("%q", tostring(v)) end

  indent = indent or ""
  local next_indent = indent .. "  "
  local arr, n = is_array(v)
  local parts = {}
  if arr then
    for i = 1, n do parts[#parts + 1] = next_indent .. encode(v[i], next_indent, opts) end
  else
    local keys = {}
    for k in pairs(v) do
      if not (opts.skip_digest and k == "digest") then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = next_indent .. key_literal(k) .. " = " .. encode(v[k], next_indent, opts)
    end
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

function M.content_string(manifest)
  if type(manifest) == "string" then return manifest end
  return encode(manifest, "", { skip_digest = true })
end

function M.to_string(manifest)
  if type(manifest) == "string" then return manifest end
  return encode(manifest, "", { skip_digest = false })
end

function M.digest(manifest_or_string)
  return "sha256:" .. Materialize.sha256_hex(M.content_string(manifest_or_string))
end

local function manifest_digest_ok(manifest, errors)
  if type(manifest) ~= "table" then return end
  if manifest.schema ~= M.SCHEMA then add(errors, "manifest schema mismatch: " .. tostring(manifest.schema)) end
  if manifest.digest then
    local got = M.digest(manifest)
    if manifest.digest ~= got then add(errors, "manifest digest mismatch: expected " .. tostring(manifest.digest) .. ", got " .. got) end
  end
end

function M.check(manifest, module, code_blobs, opts)
  opts = opts or {}
  local errors = {}
  manifest_digest_ok(manifest, errors)
  local current, cerr = M.build(module, code_blobs, opts)
  if not current then
    add_prefixed(errors, "current module: ", cerr)
    return false, errors
  end

  if type(manifest) == "string" then
    local current_string = M.to_string(current)
    if manifest ~= current_string then add(errors, "manifest string does not match current module") end
  elseif type(manifest) == "table" then
    local stored = M.content_string(manifest)
    local now = M.content_string(current)
    if stored ~= now then add(errors, "manifest content does not match current module") end
    if manifest.digest and manifest.digest ~= current.digest then add(errors, "manifest digest does not match current module digest") end
  else
    add(errors, "expected manifest table or string")
  end
  return #errors == 0, errors
end

function M.check_or_error(manifest, module, code_blobs, opts)
  local ok, errors = M.check(manifest, module, code_blobs, opts)
  if not ok then error(table.concat(errors or {}, "\n"), 2) end
  return true
end

return M
