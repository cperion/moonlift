-- stencil_materialization_plan.lua -- ASDL builders for stencil backend metadata.
--
-- This module builds typed metadata only. It does not produce object bytes and
-- does not infer Lua semantics from backend descriptors.

local B = require("lua_compile.builders")
local T = B.T
local S = T.Stencil
local Validate = require("lua_compile.stencil_validate")

local M = {}

function M.name(s) return S.Name(tostring(s or "")) end

function M.default_target_abi(opts)
  opts = opts or {}
  return S.TargetABI(
    tostring(opts.triple or os.getenv("MOONLIFT_TARGET_TRIPLE") or "native-unknown"),
    tostring(opts.calling_convention or "moonlift"),
    tostring(opts.pointer_width or (ffi and ffi.abi and ffi.abi("64bit") and "64" or "64")),
    tostring(opts.endian or "little")
  )
end

function M.default_feature_set(opts)
  opts = opts or {}
  local arch = opts.arch or (jit and jit.arch) or "unknown"
  local osname = opts.os or (jit and jit.os) or "unknown"
  return S.FeatureSet(
    tostring(arch),
    tostring(osname),
    tostring(opts.cpu_features or "baseline"),
    tostring(opts.codegen_version or "mooncfg-stencil-v1")
  )
end

function M.empty_placement()
  return S.Placement({}, {}, {})
end

function M.variant_for_kernel(kernel, contract, opts)
  opts = opts or {}
  assert(kernel and kernel.kind, "variant_for_kernel requires MoonCFG.Kernel")
  return S.VariantKey(
    opts.stencil_kind or S.KernelStencil,
    kernel.kind,
    contract or kernel.contract,
    opts.placement or M.empty_placement(),
    opts.target_abi or M.default_target_abi(opts),
    opts.features or M.default_feature_set(opts)
  )
end

local function patch_value_for(hole, value)
  if value and T.Stencil.PatchValue.members[require("moonlift.pvm").classof(value)] then return value end
  if value and T.Stencil.ImmediateOperand.members[require("moonlift.pvm").classof(value)] then return S.PatchImmediate(value) end
  if value and require("moonlift.pvm").classof(value) == S.StackOperand then return S.PatchStack(value) end
  if value and require("moonlift.pvm").classof(value) == S.RegisterOperand then return S.PatchRegister(value) end
  if value and require("moonlift.pvm").classof(value) == S.Symbol then return S.PatchSymbol(value) end
  return S.PatchComputed(hole.id)
end

function M.plan(entry_symbol, holes, patch_values, link_steps, opts)
  opts = opts or {}
  patch_values = patch_values or {}
  local sites = {}
  for _, hole in ipairs(holes or {}) do
    local id = hole.id and hole.id.text or ""
    local value = patch_values[id] or patch_values[hole]
    if value or opts.patch_all_holes then sites[#sites + 1] = S.PatchSite(hole, patch_value_for(hole, value)) end
  end
  local entry = S.EntryPoint(entry_symbol, opts.target_abi or M.default_target_abi(opts))
  return S.MaterializationPlan(sites, link_steps or {}, entry)
end

function M.template(args)
  args = args or {}
  assert(args.name, "template requires name")
  assert(args.variant, "template requires variant")
  assert(args.code, "template requires explicit CodeBlobRef")
  assert(args.entry_symbol, "template requires entry_symbol")
  local holes = args.holes or {}
  local relocs = args.relocs or {}
  local local_symbols = args.local_symbols or { args.entry_symbol }
  local plan = args.plan or M.plan(args.entry_symbol, holes, args.patch_values, args.link_steps, args)
  local template = S.StencilTemplate(
    type(args.name) == "table" and args.name or M.name(args.name),
    args.kind or S.KernelStencil,
    args.variant,
    args.code,
    holes,
    relocs,
    local_symbols,
    plan
  )
  local ok, errors = Validate.validate_template(template, args.validate_opts or {})
  if not ok then error(table.concat(errors, "\n"), 2) end
  return template
end

return M
