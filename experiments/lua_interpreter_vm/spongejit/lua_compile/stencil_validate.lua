-- stencil_validate.lua -- fail-closed validators for ASDL stencil artifacts.
--
-- Stencil artifacts are copy-and-patch backend metadata. They may describe code
-- bytes, typed holes, relocations, symbols, ABI, and placement. They must not
-- encode Lua opcode/protocol semantics or old backend descriptor identities.

local pvm = require("lalin.pvm")
local B = require("lua_compile.builders")
local T = B.T
local S = T.Stencil
local Key = require("lua_compile.stencil_key")

local M = {}

local OLD_BANK = "spon" .. "bank"
local OLD_DESC = "Spon" .. "Desc"
local OLD_STENCIL = "Spon" .. "Stencil"
local OLD_OPCODE_HELPER = "Opcode" .. "Helper"
local OLD_HELPER_CALL = "Helper" .. "Call"

local function add(errors, msg) errors[#errors + 1] = msg end
local function cls(v) return pvm.classof(v) end
local function is(v, c)
  return cls(v) == c or v == c or (cls(v) and cls(c) and cls(v) == cls(c))
end
local function name_text(n)
  if type(n) == "table" and n.text ~= nil then return tostring(n.text) end
  return tostring(n or "")
end
local function symbol_key(sym) return name_text(sym and sym.name) end

local function forbidden_string_reason(s)
  s = tostring(s or "")
  local lower = s:lower()
  local exact = {
    call = true, close = true, generic_for = true, setlist = true, getvarg = true,
    out_tag = true, out_event_kind = true,
  }
  if exact[s] or exact[lower] then return "forbidden protocol/string tag: " .. s end
  if s:match("^OP_") or lower:match("^op_") then return "opcode-shaped stencil name: " .. s end
  if lower:match("opcode") then return "opcode descriptor string forbidden: " .. s end
  if lower:match("protocol") then return "protocol descriptor string forbidden: " .. s end
  if lower:match("interpreter") or lower:match("execute[_%-]?opcode") or lower:match("resume[_%-]?lua") then return "interpreter/helper stencil string forbidden: " .. s end
  if lower:match("out_tag") or lower:match("out_event_kind") then return "out protocol ABI string forbidden: " .. s end
  if lower:match(OLD_BANK) then return "old backend bank string forbidden: " .. s end
  if s:match(OLD_DESC) or s:match(OLD_STENCIL) or s:match(OLD_OPCODE_HELPER) or s:match(OLD_HELPER_CALL) then return "old backend descriptor/helper string forbidden: " .. s end
  return nil
end

local function walk(v, fn, seen)
  local tv = type(v)
  if tv ~= "table" then fn(v); return end
  seen = seen or {}; if seen[v] then return end; seen[v] = true
  fn(v)
  local c = cls(v)
  if c and rawget(c, "__fields") then
    for _, f in ipairs(c.__fields) do walk(v[f.name], fn, seen) end
  elseif not c then
    for _, x in pairs(v) do walk(x, fn, seen) end
  end
end

local function validate_no_forbidden_strings(node, errors)
  local ok, key_errors = Key.check_no_forbidden_strings(node)
  for _, e in ipairs(key_errors) do add(errors, e) end
  walk(node, function(v)
    if type(v) == "string" then
      local reason = forbidden_string_reason(v)
      if reason then add(errors, reason) end
    end
  end)
  return ok and #errors == 0
end

local function validate_variant_key(variant, errors, opts)
  if not is(variant, S.VariantKey) then add(errors, "expected Stencil.VariantKey"); return end
  if is(variant.stencil_kind, S.RuntimeBoundaryStencil) and not (opts and opts.allow_runtime_boundary) then
    add(errors, "RuntimeBoundaryStencil requires explicit allow_runtime_boundary")
  end
  if not T.Stencil.StencilKind.members[cls(variant.stencil_kind)] then add(errors, "variant has invalid StencilKind") end
  if not T.LalinCFG.KernelKind.members[cls(variant.kernel_kind)] then add(errors, "variant has invalid LalinCFG.KernelKind") end
  if not is(variant.contract, T.CompileContract.Contract) then add(errors, "variant contract must be CompileContract.Contract") end
  if not is(variant.placement, S.Placement) then add(errors, "variant placement must be Stencil.Placement") end
  if not is(variant.target_abi, S.TargetABI) then add(errors, "variant target_abi must be Stencil.TargetABI") end
  if not is(variant.features, S.FeatureSet) then add(errors, "variant features must be Stencil.FeatureSet") end
end

local function validate_symbol(sym, errors, where)
  if not is(sym, S.Symbol) then add(errors, where .. " expected Stencil.Symbol"); return end
  if not T.Stencil.SymbolKind.members[cls(sym.kind)] then add(errors, where .. " invalid SymbolKind") end
  if not T.Stencil.SymbolVisibility.members[cls(sym.visibility)] then add(errors, where .. " invalid SymbolVisibility") end
  if (tonumber(sym.offset) or 0) < 0 then add(errors, where .. " symbol offset must be >= 0") end
end

local function collect_symbols(list, out, errors, where)
  for i, sym in ipairs(list or {}) do
    validate_symbol(sym, errors, where .. " symbol " .. i)
    out[symbol_key(sym)] = sym
  end
end

local function validate_hole(hole, errors, i)
  if not is(hole, S.PatchHole) then add(errors, "hole " .. i .. " expected Stencil.PatchHole"); return end
  if not T.Stencil.PatchKind.members[cls(hole.kind)] then add(errors, "hole " .. i .. " invalid PatchKind") end
  if not T.Stencil.PatchEncoding.members[cls(hole.encoding)] then add(errors, "hole " .. i .. " invalid PatchEncoding") end
  if not T.Stencil.PatchSource.members[cls(hole.source)] then add(errors, "hole " .. i .. " invalid PatchSource") end
  if (tonumber(hole.offset) or -1) < 0 then add(errors, "hole " .. i .. " offset must be >= 0") end
  if (tonumber(hole.width_bytes) or 0) <= 0 then add(errors, "hole " .. i .. " width_bytes must be > 0") end
end

local function validate_reloc(reloc, symbols, errors, i)
  if not is(reloc, S.Reloc) then add(errors, "reloc " .. i .. " expected Stencil.Reloc"); return end
  if not T.Stencil.RelocKind.members[cls(reloc.kind)] then add(errors, "reloc " .. i .. " invalid RelocKind") end
  if (tonumber(reloc.offset) or -1) < 0 then add(errors, "reloc " .. i .. " offset must be >= 0") end
  validate_symbol(reloc.target, errors, "reloc " .. i .. " target")
  if symbols and not symbols[symbol_key(reloc.target)] then add(errors, "reloc " .. i .. " target does not resolve: " .. symbol_key(reloc.target)) end
end

local function validate_code(code, errors)
  if not is(code, S.CodeBlobRef) then add(errors, "expected Stencil.CodeBlobRef"); return end
  if (tonumber(code.byte_size) or 0) <= 0 then add(errors, "CodeBlobRef.byte_size must be > 0") end
  if not tostring(code.content_hash or ""):match("^sha256:") then add(errors, "CodeBlobRef.content_hash must start with sha256:") end
end

local function validate_plan(plan, holes_by_id, symbols, errors)
  if not is(plan, S.MaterializationPlan) then add(errors, "expected Stencil.MaterializationPlan"); return end
  for i, site in ipairs(plan.patch_sites or {}) do
    if not is(site, S.PatchSite) then add(errors, "patch site " .. i .. " expected Stencil.PatchSite")
    else
      local id = name_text(site.hole and site.hole.id)
      if not holes_by_id[id] then add(errors, "patch site " .. i .. " references undeclared hole: " .. id) end
      if not T.Stencil.PatchValue.members[cls(site.value)] then add(errors, "patch site " .. i .. " invalid PatchValue") end
    end
  end
  for i, step in ipairs(plan.link_steps or {}) do
    if not T.Stencil.LinkStep.members[cls(step)] then add(errors, "link step " .. i .. " invalid LinkStep") end
    if is(step, S.ResolveExternalSymbol) and symbols and not symbols[symbol_key(step.symbol)] then add(errors, "link step " .. i .. " external symbol does not resolve: " .. symbol_key(step.symbol)) end
    if (is(step, S.ResolveInternalBranch) or is(step, S.ResolveInternalCall)) and symbols then
      if not symbols[symbol_key(step.from)] then add(errors, "link step " .. i .. " from symbol does not resolve: " .. symbol_key(step.from)) end
      if not symbols[symbol_key(step.to)] then add(errors, "link step " .. i .. " to symbol does not resolve: " .. symbol_key(step.to)) end
    end
    if is(step, S.ApplyReloc) then validate_reloc(step.reloc, symbols, errors, i) end
  end
  if not is(plan.entry, S.EntryPoint) then add(errors, "plan entry must be Stencil.EntryPoint")
  else
    validate_symbol(plan.entry.symbol, errors, "entry")
    if symbols and not symbols[symbol_key(plan.entry.symbol)] then add(errors, "entry symbol does not resolve: " .. symbol_key(plan.entry.symbol)) end
    if not is(plan.entry.abi, S.TargetABI) then add(errors, "entry abi must be Stencil.TargetABI") end
  end
end

function M.validate_variant_key(variant, opts)
  local errors = {}
  validate_variant_key(variant, errors, opts or {})
  validate_no_forbidden_strings(variant, errors)
  return #errors == 0, errors
end

function M.validate_template(template, opts)
  opts = opts or {}
  local errors = {}
  if not is(template, S.StencilTemplate) then
    add(errors, "expected Stencil.StencilTemplate")
    return false, errors
  end
  validate_variant_key(template.variant, errors, opts)
  if is(template.kind, S.RuntimeBoundaryStencil) and not opts.allow_runtime_boundary then
    add(errors, "RuntimeBoundaryStencil requires explicit allow_runtime_boundary")
  end
  if not T.Stencil.StencilKind.members[cls(template.kind)] then add(errors, "template has invalid StencilKind") end
  validate_code(template.code, errors)

  local symbols = {}
  collect_symbols(template.local_symbols or {}, symbols, errors, "template local")
  local holes_by_id = {}
  for i, hole in ipairs(template.holes or {}) do
    validate_hole(hole, errors, i)
    holes_by_id[name_text(hole.id)] = hole
  end
  for i, reloc in ipairs(template.relocs or {}) do validate_reloc(reloc, symbols, errors, i) end
  validate_plan(template.plan, holes_by_id, symbols, errors)
  validate_no_forbidden_strings(template, errors)
  return #errors == 0, errors
end

function M.validate_materialized_image(image, opts)
  opts = opts or {}
  local errors = {}
  if not is(image, S.MaterializedImage) then
    add(errors, "expected Stencil.MaterializedImage")
    return false, errors
  end
  validate_code(image.code, errors)
  validate_symbol(image.entry, errors, "materialized entry")
  if type(image.bytes) ~= "string" then add(errors, "materialized bytes must be a string") end
  if image.code and type(image.bytes) == "string" and #image.bytes ~= tonumber(image.code.byte_size) then
    add(errors, "materialized bytes length must match CodeBlobRef.byte_size")
  end
  if (tonumber(image.entry_offset) or -1) < 0 then add(errors, "materialized entry_offset must be >= 0") end
  if type(image.bytes) == "string" and (tonumber(image.entry_offset) or 0) >= #image.bytes then add(errors, "materialized entry_offset out of range") end
  for i, record in ipairs(image.records or {}) do
    if not T.Stencil.MaterializationRecord.members[cls(record)] then
      add(errors, "materialization record " .. i .. " invalid MaterializationRecord")
    elseif is(record, S.AppliedPatch) then
      if (tonumber(record.offset) or -1) < 0 then add(errors, "materialization patch record " .. i .. " offset must be >= 0") end
      if (tonumber(record.width_bytes) or 0) <= 0 then add(errors, "materialization patch record " .. i .. " width_bytes must be > 0") end
      if not T.Stencil.PatchEncoding.members[cls(record.encoding)] then add(errors, "materialization patch record " .. i .. " invalid encoding") end
    elseif is(record, S.AppliedReloc) then
      if (tonumber(record.offset) or -1) < 0 then add(errors, "materialization reloc record " .. i .. " offset must be >= 0") end
      if not T.Stencil.RelocKind.members[cls(record.kind)] then add(errors, "materialization reloc record " .. i .. " invalid kind") end
    end
  end
  -- Do not scan image.bytes as text: it is concrete binary code, not semantic metadata.
  local metadata = {
    template_name = image.template_name,
    code_symbol = image.code and image.code.symbol,
    content_hash = image.code and image.code.content_hash,
    entry = image.entry,
    entry_offset = image.entry_offset,
    records = image.records,
  }
  validate_no_forbidden_strings(metadata, errors)
  return #errors == 0, errors
end

function M.validate_publish_entry_metadata(entry, opts)
  opts = opts or {}
  local errors = {}
  if not is(entry, S.PublishEntryMetadata) then
    add(errors, "expected Stencil.PublishEntryMetadata")
    return false, errors
  end
  validate_variant_key(entry.variant, errors, opts)
  validate_symbol(entry.entry, errors, "publish entry")
  if (tonumber(entry.entry_offset) or -1) < 0 then add(errors, "publish entry_offset must be >= 0") end
  if (tonumber(entry.image_size) or 0) <= 0 then add(errors, "publish image_size must be > 0") end
  if not tostring(entry.image_hash or ""):match("^sha256:") then add(errors, "publish image_hash must start with sha256:") end
  if not is(entry.target_abi, S.TargetABI) then add(errors, "publish target_abi must be Stencil.TargetABI") end
  if not is(entry.features, S.FeatureSet) then add(errors, "publish features must be Stencil.FeatureSet") end
  if tostring(entry.generation_id or "") == "" then add(errors, "publish generation_id must be non-empty") end
  if tostring(entry.entry_address_placeholder or "") == "" then add(errors, "publish entry_address_placeholder must be non-empty") end
  validate_no_forbidden_strings({
    template_name = entry.template_name,
    entry = entry.entry,
    entry_address_placeholder = entry.entry_address_placeholder,
    image_hash = entry.image_hash,
    generation_id = entry.generation_id,
  }, errors)
  return #errors == 0, errors
end

function M.validate_materialized_bundle(bundle, opts)
  opts = opts or {}
  local errors = {}
  if not is(bundle, S.MaterializedBundle) then
    add(errors, "expected Stencil.MaterializedBundle")
    return false, errors
  end
  if tostring(bundle.generation_id or "") == "" then add(errors, "bundle generation_id must be non-empty") end
  if not tostring(bundle.manifest_digest or ""):match("^sha256:") then add(errors, "bundle manifest_digest must start with sha256:") end
  if #(bundle.images or {}) == 0 then add(errors, "bundle must contain at least one MaterializedImage") end
  if #(bundle.images or {}) ~= #(bundle.entries or {}) then add(errors, "bundle images/entries count mismatch") end
  local image_by_template = {}
  for i, image in ipairs(bundle.images or {}) do
    local ok, ierr = M.validate_materialized_image(image, opts)
    for _, e in ipairs(ierr) do add(errors, "bundle image " .. i .. ": " .. e) end
    local tname = name_text(image.template_name)
    if image_by_template[tname] then add(errors, "duplicate bundle image template: " .. tname) end
    image_by_template[tname] = image
  end
  local seen_entries = {}
  for i, entry in ipairs(bundle.entries or {}) do
    local ok, eerr = M.validate_publish_entry_metadata(entry, opts)
    for _, e in ipairs(eerr) do add(errors, "bundle entry " .. i .. ": " .. e) end
    local tname = name_text(entry.template_name)
    local image = image_by_template[tname]
    if not image then add(errors, "publish entry has no matching image: " .. tname) end
    if seen_entries[tname] then add(errors, "duplicate publish entry template: " .. tname) end
    seen_entries[tname] = true
    if image then
      if tonumber(entry.image_size) ~= #(image.bytes or "") then add(errors, "publish entry image_size mismatch for " .. tname) end
      local want_hash = "sha256:" .. require("lua_compile.stencil_materialize").sha256_hex(image.bytes or "")
      if tostring(entry.image_hash) ~= want_hash then add(errors, "publish entry image_hash mismatch for " .. tname) end
      if tonumber(entry.entry_offset) ~= tonumber(image.entry_offset) then add(errors, "publish entry offset mismatch for " .. tname) end
    end
  end
  validate_no_forbidden_strings({ id = bundle.id, generation_id = bundle.generation_id, manifest_digest = bundle.manifest_digest }, errors)
  return #errors == 0, errors
end

function M.validate_module(module, opts)
  opts = opts or {}
  local errors = {}
  if not is(module, S.StencilModule) then
    add(errors, "expected Stencil.StencilModule")
    return false, errors
  end
  if not is(module.bank, S.BankIndex) then add(errors, "module bank must be Stencil.BankIndex") end
  if not is(module.linkage, S.Linkage) then add(errors, "module linkage must be Stencil.Linkage") end
  local symbols = {}
  collect_symbols(module.symbols or {}, symbols, errors, "module")
  if module.linkage then
    collect_symbols(module.linkage.exported or {}, symbols, errors, "linkage exported")
    collect_symbols(module.linkage.imported or {}, symbols, errors, "linkage imported")
    for i, reloc in ipairs(module.linkage.required_relocs or {}) do validate_reloc(reloc, symbols, errors, i) end
  end
  local template_names = {}
  for i, template in ipairs(module.templates or {}) do
    local ok, terr = M.validate_template(template, opts)
    for _, e in ipairs(terr) do add(errors, "template " .. i .. ": " .. e) end
    template_names[name_text(template.name)] = true
  end
  if module.bank then
    for i, variant in ipairs(module.bank.variants or {}) do
      local ok, verr = M.validate_variant_key(variant, opts)
      for _, e in ipairs(verr) do add(errors, "bank variant " .. i .. ": " .. e) end
    end
    for i, entry in ipairs(module.bank.entries or {}) do
      if not is(entry, S.TemplateIndexEntry) then add(errors, "bank entry " .. i .. " expected TemplateIndexEntry")
      else
        if not template_names[name_text(entry.template_name)] then add(errors, "bank entry " .. i .. " template_name does not resolve: " .. name_text(entry.template_name)) end
        local ok, verr = M.validate_variant_key(entry.key, opts)
        for _, e in ipairs(verr) do add(errors, "bank entry " .. i .. ": " .. e) end
      end
    end
  end
  validate_no_forbidden_strings(module, errors)
  return #errors == 0, errors
end

return M
