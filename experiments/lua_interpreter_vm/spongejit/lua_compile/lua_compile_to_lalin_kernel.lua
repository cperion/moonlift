-- lua_compile_to_lalin_kernel.lua -- LuaCompile.Unit -> LalinKernel product.

local pvm = require("lalin.pvm")
local B = require("lua_compile.builders")
local LuaExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local LuaExecToLalin = require("lua_compile.lua_exec_to_lalin_cfg_lower")
local Errors = require("lua_compile.errors")
local T = B.T

local M = {}

local function contains_class(v, target, seen)
  if type(v) ~= "table" then return false end
  seen = seen or {}; if seen[v] then return false end; seen[v] = true
  if pvm.classof(v) == target then return true end
  local cls = pvm.classof(v)
  if cls and cls.__fields then
    for _, f in ipairs(cls.__fields) do if contains_class(v[f.name], target, seen) then return true end end
  elseif not cls then
    for _, x in pairs(v) do if contains_class(x, target, seen) then return true end end
  end
  return false
end

local function needs_outcome_mode(exec_product)
  return contains_class(exec_product, T.LuaExec.Error)
      or contains_class(exec_product, T.LuaExec.Yield)
      or contains_class(exec_product, T.LuaExec.TableRawSet)
      or contains_class(exec_product, T.LuaExec.TableRawGetExpr)
      or contains_class(exec_product, T.LuaExec.LenNoMetaExpr)
      or contains_class(exec_product, T.LuaExec.StringConcat2Expr)
      or contains_class(exec_product, T.LuaExec.NormalizeResultsExpr)
      or contains_class(exec_product, T.LuaExec.ResultChannelExpr)
      or contains_class(exec_product, T.LuaExec.ReceiveCallResults)
      or contains_class(exec_product, T.LuaExec.EmitRegion)
      or contains_class(exec_product, T.LuaRT.OpenFromTop)
      or contains_class(exec_product, T.LuaRT.OpenFromVarargs)
      or contains_class(exec_product, T.LuaRT.OpenFromVarargsAtBase)
      or contains_class(exec_product, T.LuaExec.ArithmeticNoMetaExpr)
      or contains_class(exec_product, T.LuaExec.ArithmeticNumericChoice)
end

local function contains_error(errors, needle)
  for _, e in ipairs(errors or {}) do
    if tostring(e):find(needle, 1, true) then return true end
  end
  return false
end

local function lower_exec_to_cfg(exec_product)
  local opts = needs_outcome_mode(exec_product) and { outcome = true, outcome_projection = "kind" } or nil
  local is_module = pvm.classof(exec_product) == T.LuaExec.Module
  local cfg_kernel, cfg_errors
  if is_module then
    cfg_kernel, cfg_errors = LuaExecToLalin.lower_module(exec_product, "lua_exec_core_kernel", opts)
  else
    cfg_kernel, cfg_errors = LuaExecToLalin.lower(exec_product, opts)
  end
  if not cfg_kernel and not opts and contains_error(cfg_errors, "unsupported_lua_value_return_without_projection") then
    if is_module then
      cfg_kernel, cfg_errors = LuaExecToLalin.lower_module(exec_product, "lua_exec_core_kernel", { outcome = true, outcome_projection = "kind" })
    else
      cfg_kernel, cfg_errors = LuaExecToLalin.lower(exec_product, { outcome = true, outcome_projection = "kind" })
    end
  end
  return cfg_kernel, cfg_errors
end

local function compile_value(unit)
  -- Accepted LalinKernel compilation has one executable route:
  -- LuaSrc.Window -> LuaExec.Kernel/LuaExec.Module -> LalinCFG.Kernel.
  -- LuaExec.Module is typed static region composition inlined before LalinCFG;
  -- unsupported source windows return diagnostics with no fallback.
  local exec_product, exec_errors = LuaExecLower.lower(unit.source, unit.evidence)
  if not exec_product then
    return Errors.compile_reject_from_errors("lua_exec_lower", unit.source, exec_errors, "unsupported_semantic_case")
  end

  local cfg_kernel, cfg_errors = lower_exec_to_cfg(exec_product)
  if not cfg_kernel then
    return Errors.compile_reject_from_errors("lua_exec_to_lalin_cfg_lower", unit.source, cfg_errors, "internal_invariant_failure")
  end

  return T.LuaCompile.Ok(T.LuaCompile.LalinKernel(cfg_kernel))
end

local phase = pvm.phase("spongejit_lua_compile_to_lalin_kernel", function(unit)
  return compile_value(unit)
end)

function M.compile(unit)
  return pvm.one(phase(unit))
end

M.phase = phase
M.compile_uncached = compile_value

return M
