-- lalin_cfg_abi.lua -- typed LalinCFG parameter/type helpers.
--
-- Accepted LuaCompile kernels use these typed value parameters directly.  This
-- module intentionally exposes no out_tag/out_* semantic protocol ABI and no
-- retired normal-form parameter derivation.

local B = require("lua_compile.builders")
local CFG = B.T.LalinCFG

local M = {}

function M.name(s) return CFG.Name(tostring(s or "")) end
function M.ty(s) return CFG.TypeRef(tostring(s or "void")) end
function M.param(s, lalin_type)
  return CFG.Param(M.name(s), M.ty(lalin_type), CFG.ValueParam)
end

function M.slot_i64_name(slot) return string.format("slot_%d_i64", tonumber(slot and slot.id or slot) or 0) end
function M.slot_f64_name(slot) return string.format("slot_%d_f64", tonumber(slot and slot.id or slot) or 0) end
function M.vararg_i64_name(base, index) return string.format("vararg_%d_%d_i64", tonumber(base and base.id or base) or 0, tonumber(index and index.value or index) or 0) end
function M.vararg_f64_name(base, index) return string.format("vararg_%d_%d_f64", tonumber(base and base.id or base) or 0, tonumber(index and index.value or index) or 0) end
function M.const_i64_name(k) return string.format("const_%d_i64", tonumber(k and k.id or k) or 0) end
function M.const_f64_name(k) return string.format("const_%d_f64", tonumber(k and k.id or k) or 0) end

function M.default_params() return {} end

return M
