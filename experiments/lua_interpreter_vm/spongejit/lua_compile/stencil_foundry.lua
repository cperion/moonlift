-- stencil_foundry.lua -- foundry-facing helpers for ASDL stencil identity.
--
-- This layer computes Stencil.VariantKey identity for MoonCFG artifacts. It does
-- not build binary templates; real StencilTemplate values require object-byte
-- extraction metadata through stencil_object_extract.lua.

local Key = require("lua_compile.stencil_key")
local Plan = require("lua_compile.stencil_materialization_plan")

local M = {}

function M.variant_for_kernel(kernel, contract, opts)
  return Plan.variant_for_kernel(kernel, contract, opts or {})
end

function M.representative_key(kernel, contract_key, variant)
  return Key.representative_key(kernel, contract_key, variant)
end

function M.artifact_summary(variant)
  if not variant then return nil end
  local abi = variant.target_abi or {}
  local features = variant.features or {}
  return {
    stencil_kind = variant.stencil_kind and variant.stencil_kind.kind,
    kernel_kind = variant.kernel_kind and variant.kernel_kind.kind,
    target = {
      triple = abi.triple,
      calling_convention = abi.calling_convention,
      pointer_width = abi.pointer_width,
      endian = abi.endian,
    },
    features = {
      arch = features.arch,
      os = features.os,
      cpu_features = features.cpu_features,
      codegen_version = features.codegen_version,
    },
  }
end

return M
