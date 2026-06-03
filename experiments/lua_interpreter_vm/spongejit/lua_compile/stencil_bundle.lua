-- stencil_bundle.lua -- deterministic materialized stencil bundle builder.
--
-- This layer is intentionally VM/language agnostic. It consumes validated
-- Stencil.StencilModule metadata plus caller-supplied code bytes, materializes
-- selected templates in stable VariantKey/template-name order, and returns
-- explicit publish-ready metadata. It does not allocate executable memory,
-- call OS APIs, inspect Lua opcodes, recover MoonCFG semantics, or provide an
-- interpreter/protocol fallback.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local S = T.Stencil
local Key = require("lua_compile.stencil_key")
local Validate = require("lua_compile.stencil_validate")
local Bank = require("lua_compile.stencil_bank")
local Manifest = require("lua_compile.stencil_manifest")
local Materialize = require("lua_compile.stencil_materialize")

local M = {}

local function cls(v) return pvm.classof(v) end
local function is(v, c) return cls(v) == c or v == c or (cls(v) and cls(c) and cls(v) == cls(c)) end
local function add(errors, msg) errors[#errors + 1] = msg end
local function add_prefixed(errors, prefix, list)
  for _, e in ipairs(list or {}) do add(errors, prefix .. e) end
end
local function name_text(n)
  if type(n) == "table" and n.text ~= nil then return tostring(n.text) end
  return tostring(n or "")
end

local function validate_no_forbidden(node, errors)
  local ok, ferr = Key.check_no_forbidden_strings(node)
  add_prefixed(errors, "", ferr)
  return ok
end

local function variant_key(v)
  if type(v) == "string" then
    local errors = {}
    validate_no_forbidden({ v }, errors)
    if #errors > 0 then return nil, errors end
    return v, {}
  end
  if not is(v, S.VariantKey) then return nil, { "expected Stencil.VariantKey or variant key string" } end
  local ok, errors = Validate.validate_variant_key(v)
  if not ok then return nil, errors end
  return Key.variant_key(v), {}
end

local function normalize_selected_variants(selected, errors)
  local keys = {}
  local seen = {}
  for i, v in ipairs(selected or {}) do
    local key, kerr = variant_key(v)
    if not key then
      add_prefixed(errors, "selected variant " .. tostring(i) .. ": ", kerr)
    elseif seen[key] then
      add(errors, "duplicate selected variant key: " .. key)
    else
      seen[key] = true
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  return keys
end

local function compute_generation_id(manifest_digest, variant_keys, opts)
  opts = opts or {}
  if opts.generation_id then return tostring(opts.generation_id) end
  local seed = table.concat({ tostring(manifest_digest or ""), table.concat(variant_keys or {}, "\n") }, "\n-- selected variants --\n")
  return "bundle-sha256:" .. Materialize.sha256_hex(seed)
end

local function compute_bundle_id(generation_id, opts)
  if opts and opts.id then return S.Name(tostring(opts.id)) end
  local hex = tostring(generation_id or ""):match("sha256:([0-9a-f]+)") or Materialize.sha256_hex(tostring(generation_id or ""))
  return S.Name("stencil_bundle_" .. hex:sub(1, 16))
end

local function image_hash(image)
  return "sha256:" .. Materialize.sha256_hex(image.bytes or "")
end

local function entry_placeholder(generation_id, template, image, opts)
  if opts and opts.entry_address_placeholder then return tostring(opts.entry_address_placeholder) end
  local prefix = (opts and opts.entry_address_placeholder_prefix) or "unpublished"
  return table.concat({ prefix, tostring(generation_id), name_text(template.name), name_text(image.entry and image.entry.name) }, ":")
end

local function publish_metadata(template, image, generation_id, opts)
  return S.PublishEntryMetadata(
    template.variant,
    template.name,
    image.entry,
    image.entry_offset,
    entry_placeholder(generation_id, template, image, opts),
    #(image.bytes or ""),
    image_hash(image),
    template.variant.target_abi,
    template.variant.features,
    generation_id
  )
end

local function materialize_variant_keys(module, code_blobs, variant_keys, opts)
  opts = opts or {}
  local errors = {}

  if not is(module, S.StencilModule) then return nil, { "expected Stencil.StencilModule" } end

  local index, ierr = Bank.build_index(module, opts.bank_opts or opts)
  if not index then return nil, ierr end

  local manifest, merr = Manifest.build(module, code_blobs, opts.manifest_opts or opts)
  if not manifest then return nil, merr end
  if opts.manifest then
    local ok, cerr = Manifest.check(opts.manifest, module, code_blobs, opts.manifest_opts or opts)
    if not ok then add_prefixed(errors, "manifest mismatch: ", cerr) end
  end
  if opts.manifest_digest and tostring(opts.manifest_digest) ~= tostring(manifest.digest) then
    add(errors, "manifest digest mismatch: expected " .. tostring(opts.manifest_digest) .. ", got " .. tostring(manifest.digest))
  end
  if #errors > 0 then return nil, errors end

  local generation_id = compute_generation_id(manifest.digest, variant_keys, opts)
  local images, entries = {}, {}
  for _, key in ipairs(variant_keys or {}) do
    local template, terr = Bank.lookup(index, key)
    if not template then
      add_prefixed(errors, "variant " .. key .. ": ", terr)
    else
      local image, mat_err = Materialize.materialize(template, code_blobs, opts.materialize_opts or opts)
      if not image then
        add_prefixed(errors, "template " .. name_text(template.name) .. ": ", mat_err)
      else
        images[#images + 1] = image
        entries[#entries + 1] = publish_metadata(template, image, generation_id, opts.publish_opts or opts)
      end
    end
  end
  if #errors > 0 then return nil, errors end

  local bundle = S.MaterializedBundle(compute_bundle_id(generation_id, opts), generation_id, manifest.digest, images, entries)
  local ok, berr = Validate.validate_materialized_bundle(bundle, opts.validate_opts or opts)
  if not ok then return nil, berr end
  return bundle, { manifest = manifest, index = index }
end

function M.materialize_all(module, code_blobs, opts)
  opts = opts or {}
  local index, ierr = Bank.build_index(module, opts.bank_opts or opts)
  if not index then return nil, ierr end
  local keys = {}
  for _, key in ipairs(index.ordered_variant_keys or {}) do keys[#keys + 1] = key end
  return materialize_variant_keys(module, code_blobs, keys, opts)
end

function M.materialize_selected_variants(module, code_blobs, selected_variants, opts)
  opts = opts or {}
  local errors = {}
  local keys = normalize_selected_variants(selected_variants or {}, errors)
  if #keys == 0 and #errors == 0 then add(errors, "selected variants must not be empty") end
  if #errors > 0 then return nil, errors end
  return materialize_variant_keys(module, code_blobs, keys, opts)
end

M.materialize_selected = M.materialize_selected_variants
M.materialize_bundle = M.materialize_all

function M.materialize_all_or_error(module, code_blobs, opts)
  local bundle, meta_or_errors = M.materialize_all(module, code_blobs, opts)
  if not bundle then error(table.concat(meta_or_errors or {}, "\n"), 2) end
  return bundle, meta_or_errors
end

function M.materialize_selected_variants_or_error(module, code_blobs, selected_variants, opts)
  local bundle, meta_or_errors = M.materialize_selected_variants(module, code_blobs, selected_variants, opts)
  if not bundle then error(table.concat(meta_or_errors or {}, "\n"), 2) end
  return bundle, meta_or_errors
end

return M
