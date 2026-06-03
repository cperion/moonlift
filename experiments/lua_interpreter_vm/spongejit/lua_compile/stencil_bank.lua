-- stencil_bank.lua -- deterministic typed stencil bank selection/materialization.
--
-- This layer is intentionally VM/language agnostic. It indexes validated
-- Stencil.StencilModule values by stable Stencil.VariantKey identity and
-- template name, selects a template, and delegates byte copying/patching to
-- stencil_materialize. It must not inspect Lua opcodes, MoonCFG internals,
-- runtime values, or language semantics.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local S = T.Stencil
local Key = require("lua_compile.stencil_key")
local Validate = require("lua_compile.stencil_validate")
local Materialize = require("lua_compile.stencil_materialize")

local M = {}

local function cls(v) return pvm.classof(v) end
local function is(v, c) return cls(v) == c or v == c or (cls(v) and cls(c) and cls(v) == cls(c)) end
local function add(errors, msg) errors[#errors + 1] = msg end
local function name_text(n)
  if type(n) == "table" and n.text ~= nil then return tostring(n.text) end
  return tostring(n or "")
end

local function variant_key(v)
  if type(v) == "string" then
    local ok, errors = Key.check_no_forbidden_strings({ v })
    if not ok then return nil, errors end
    return v, {}
  end
  if not is(v, S.VariantKey) then return nil, { "expected Stencil.VariantKey or variant key string" } end
  local ok, errors = Validate.validate_variant_key(v)
  if not ok then return nil, errors end
  return Key.variant_key(v), {}
end

local function add_prefixed(errors, prefix, list)
  for _, e in ipairs(list or {}) do add(errors, prefix .. e) end
end

local function same_variant(a, b)
  local ka = Key.variant_key(a)
  local kb = Key.variant_key(b)
  return ka == kb, ka, kb
end

local function assert_no_forbidden(node, errors)
  local ok, forb = Key.check_no_forbidden_strings(node)
  add_prefixed(errors, "", forb)
  return ok
end

local function sorted_keys(map)
  local out = {}
  for k in pairs(map) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function M.build_index(module, opts)
  opts = opts or {}
  local errors = {}
  if not is(module, S.StencilModule) then
    return nil, { "expected Stencil.StencilModule" }
  end

  local ok, verr = Validate.validate_module(module, opts.validate_opts or opts)
  add_prefixed(errors, "", verr)
  assert_no_forbidden(module, errors)
  if #errors > 0 then return nil, errors end

  local templates_by_name = {}
  local templates_by_variant_key = {}
  for i, template in ipairs(module.templates or {}) do
    local tname = name_text(template.name)
    if templates_by_name[tname] then
      add(errors, "duplicate template name: " .. tname)
    else
      templates_by_name[tname] = template
    end

    local matches_kind = template.variant and template.kind and is(template.kind, template.variant.stencil_kind)
    if not matches_kind then add(errors, "template " .. tname .. " kind does not match variant stencil_kind") end

    local tk = Key.variant_key(template.variant)
    if templates_by_variant_key[tk] then
      add(errors, "duplicate template variant key for templates: " .. name_text(templates_by_variant_key[tk].name) .. " and " .. tname)
    else
      templates_by_variant_key[tk] = template
    end
  end

  local declared_variants = {}
  for i, variant in ipairs((module.bank and module.bank.variants) or {}) do
    local vk = Key.variant_key(variant)
    if declared_variants[vk] then
      add(errors, "duplicate variant key in bank variants at index " .. tostring(i))
    else
      declared_variants[vk] = variant
    end
  end

  local entries_by_variant_key = {}
  local entries_by_template_name = {}
  for i, entry in ipairs((module.bank and module.bank.entries) or {}) do
    if not is(entry, S.TemplateIndexEntry) then
      add(errors, "bank entry " .. tostring(i) .. " expected Stencil.TemplateIndexEntry")
    else
      local ename = name_text(entry.template_name)
      local ek = Key.variant_key(entry.key)
      if entries_by_variant_key[ek] then
        add(errors, "duplicate ambiguous bank entry for variant key at index " .. tostring(i))
      else
        entries_by_variant_key[ek] = entry
      end
      if entries_by_template_name[ename] then
        add(errors, "duplicate bank entry for template name: " .. ename)
      else
        entries_by_template_name[ename] = entry
      end
      if not declared_variants[ek] then
        add(errors, "bank entry " .. tostring(i) .. " key is not declared in bank variants")
      end

      local template = templates_by_name[ename]
      if not template then
        add(errors, "bank entry " .. tostring(i) .. " template_name does not resolve exactly one template: " .. ename)
      else
        local same, tk = same_variant(template.variant, entry.key)
        if not same then
          add(errors, "bank entry " .. tostring(i) .. " variant mismatch for template " .. ename)
        end
        if tk and templates_by_variant_key[tk] ~= template then
          add(errors, "bank entry " .. tostring(i) .. " variant key resolves ambiguous template for " .. ename)
        end
      end
    end
  end

  for vk in pairs(declared_variants) do
    if not entries_by_variant_key[vk] then add(errors, "bank variant has no template entry: " .. vk) end
  end

  if #errors > 0 then return nil, errors end

  local ordered_variant_keys = sorted_keys(entries_by_variant_key)
  local ordered_template_names = sorted_keys(templates_by_name)
  return {
    __stencil_bank_index = true,
    module = module,
    templates_by_name = templates_by_name,
    templates_by_variant_key = templates_by_variant_key,
    entries_by_variant_key = entries_by_variant_key,
    entries_by_template_name = entries_by_template_name,
    declared_variants = declared_variants,
    ordered_variant_keys = ordered_variant_keys,
    ordered_template_names = ordered_template_names,
  }, {}
end

local function as_index(module_or_index, opts)
  if type(module_or_index) == "table" and module_or_index.__stencil_bank_index then return module_or_index, {} end
  return M.build_index(module_or_index, opts or {})
end

function M.lookup(index, variant_or_key)
  if not (type(index) == "table" and index.__stencil_bank_index) then
    return nil, { "expected stencil bank index" }
  end
  local vk, kerr = variant_key(variant_or_key)
  if not vk then return nil, kerr end
  local entry = index.entries_by_variant_key[vk]
  if not entry then return nil, { "no template for variant key" } end
  local template = index.templates_by_name[name_text(entry.template_name)]
  if not template then return nil, { "selected template entry no longer resolves: " .. name_text(entry.template_name) } end
  return template, {}
end

function M.select_template(module_or_index, variant_or_key, opts)
  local index, ierr = as_index(module_or_index, opts or {})
  if not index then return nil, ierr end
  return M.lookup(index, variant_or_key)
end

function M.materialize(module_or_index, variant_or_key, code_blobs, opts)
  opts = opts or {}
  local index, ierr = as_index(module_or_index, opts.bank_opts or opts)
  if not index then return nil, ierr end
  local template, terr = M.lookup(index, variant_or_key)
  if not template then return nil, terr end
  return Materialize.materialize(template, code_blobs, opts.materialize_opts or opts)
end

function M.build_index_or_error(module, opts)
  local index, errors = M.build_index(module, opts)
  if not index then error(table.concat(errors or {}, "\n"), 2) end
  return index
end

function M.select_template_or_error(module_or_index, variant_or_key, opts)
  local template, errors = M.select_template(module_or_index, variant_or_key, opts)
  if not template then error(table.concat(errors or {}, "\n"), 2) end
  return template
end

function M.materialize_or_error(module_or_index, variant_or_key, code_blobs, opts)
  local image, errors = M.materialize(module_or_index, variant_or_key, code_blobs, opts)
  if not image then error(table.concat(errors or {}, "\n"), 2) end
  return image
end

return M
