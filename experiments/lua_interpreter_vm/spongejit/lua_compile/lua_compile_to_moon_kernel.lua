-- lua_compile_to_moon_kernel.lua -- LuaCompile.Unit -> MoonKernel product.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local LuaExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local LuaExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")
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

local function needs_outcome_mode(exec_kernel)
  return contains_class(exec_kernel, T.LuaExec.Error)
      or contains_class(exec_kernel, T.LuaExec.Yield)
      or contains_class(exec_kernel, T.LuaExec.TableRawSet)
      or contains_class(exec_kernel, T.LuaExec.TableRawGetExpr)
      or contains_class(exec_kernel, T.LuaExec.LenNoMetaExpr)
      or contains_class(exec_kernel, T.LuaExec.StringConcat2Expr)
      or contains_class(exec_kernel, T.LuaExec.NormalizeResultsExpr)
      or contains_class(exec_kernel, T.LuaExec.ResultChannelExpr)
      or contains_class(exec_kernel, T.LuaRT.OpenFromTop)
      or contains_class(exec_kernel, T.LuaRT.OpenFromVarargs)
      or contains_class(exec_kernel, T.LuaRT.OpenFromVarargsAtBase)
      or contains_class(exec_kernel, T.LuaExec.ArithmeticNoMetaExpr)
      or contains_class(exec_kernel, T.LuaExec.ArithmeticNumericChoice)
end

local function contains_error(errors, needle)
  for _, e in ipairs(errors or {}) do
    if tostring(e):find(needle, 1, true) then return true end
  end
  return false
end

local function lower_exec_to_cfg(exec_kernel)
  local opts = needs_outcome_mode(exec_kernel) and { outcome = true, outcome_projection = "kind" } or nil
  local cfg_kernel, cfg_errors = LuaExecToMoon.lower(exec_kernel, opts)
  if not cfg_kernel and not opts and contains_error(cfg_errors, "unsupported_lua_value_return_without_projection") then
    cfg_kernel, cfg_errors = LuaExecToMoon.lower(exec_kernel, { outcome = true, outcome_projection = "kind" })
  end
  return cfg_kernel, cfg_errors
end

local function compile_value(unit)
  -- Accepted MoonKernel compilation has one executable route:
  -- LuaSrc.Window -> LuaExec.Kernel -> MoonCFG.Kernel. Unsupported source
  -- windows return diagnostics; there are no silent success fallbacks.
  local exec_kernel, exec_errors = LuaExecLower.lower(unit.source, unit.evidence)
  if not exec_kernel then
    return Errors.compile_reject_from_errors("lua_exec_lower", unit.source, exec_errors, "unsupported_semantic_case")
  end

  local cfg_kernel, cfg_errors = lower_exec_to_cfg(exec_kernel)
  if not cfg_kernel then
    return Errors.compile_reject_from_errors("lua_exec_to_moon_cfg_lower", unit.source, cfg_errors, "internal_invariant_failure")
  end

  return T.LuaCompile.Ok(T.LuaCompile.MoonKernel(cfg_kernel))
end

local phase = pvm.phase("spongejit_lua_compile_to_moon_kernel", function(unit)
  return compile_value(unit)
end)

function M.compile(unit)
  return pvm.one(phase(unit))
end

M.phase = phase
M.compile_uncached = compile_value

return M
