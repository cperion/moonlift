-- lua_compile_to_moon_kernel.lua -- LuaCompile.Unit -> MoonKernel product.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local ToNF = require("lua_compile.lua_compile_to_normal_form")
local LuaExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
local LuaExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")
local ClosedLower = require("lua_compile.lua_src_to_moon_cfg_closed")
local MoonLower = require("lua_compile.lua_nf_to_moon_cfg_lower")
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

local function compile_value(unit)
  -- First try the semantic LuaExec path for closed core-value windows.  This
  -- keeps Lua truthiness/value/return semantics in LuaRT/LuaExec before the
  -- mechanical MoonCFG lowering. Existing MoonCFG/NF paths remain as migration
  -- fallbacks for slices LuaExec does not own yet.
  local exec_kernel = LuaExecLower.lower(unit.source, unit.evidence)
  if exec_kernel then
    local opts = nil
    if contains_class(exec_kernel, T.LuaExec.Error) or contains_class(exec_kernel, T.LuaExec.Yield)
        or contains_class(exec_kernel, T.LuaExec.TableRawSet)
        or contains_class(exec_kernel, T.LuaExec.TableRawGetExpr)
        or contains_class(exec_kernel, T.LuaExec.LenNoMetaExpr)
        or contains_class(exec_kernel, T.LuaExec.StringConcat2Expr)
        or contains_class(exec_kernel, T.LuaExec.ArithmeticNoMetaExpr)
        or contains_class(exec_kernel, T.LuaExec.ArithmeticNumericChoice) then
      opts = { outcome = true, outcome_projection = "kind" }
    end
    local cfg_kernel, cfg_errors = LuaExecToMoon.lower(exec_kernel, opts)
    if not cfg_kernel then error("LuaExec produced a kernel that MoonCFG lowering rejected: " .. table.concat(cfg_errors or {}, "; ")) end
    return T.LuaCompile.Ok(T.LuaCompile.MoonKernel(cfg_kernel))
  end

  -- Closed bytecode-window control is source-topology-sensitive.  Try this
  -- narrow path before the scalar LuaNF path so in-window jumps/branches become
  -- MoonCFG blocks instead of the older external JumpExit/ConditionalJumpExit.
  if ClosedLower.is_candidate(unit.source) then
    local closed_kernel = ClosedLower.lower(unit.source, unit.evidence)
    if closed_kernel then return T.LuaCompile.Ok(T.LuaCompile.MoonKernel(closed_kernel)) end
  end

  local r = ToNF.compile(unit)
  if pvm.classof(r) == T.LuaCompile.Reject then return r end
  local product = r.product
  local kernel, lower_errors = MoonLower.lower(product.nf, product.contract)
  if not kernel then
    return T.LuaCompile.Reject(MoonLower.rejection_for(product.nf, lower_errors))
  end
  return T.LuaCompile.Ok(T.LuaCompile.MoonKernel(kernel))
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
