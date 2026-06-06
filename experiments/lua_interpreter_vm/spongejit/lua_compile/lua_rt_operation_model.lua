-- lua_rt_operation_model.lua -- Lua operation, operand, companion, and metamethod context.
-- Structural validation only; executable arithmetic support remains in lowerer gates.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local RT = T.LuaRT
local Metatable = require("lua_compile.lua_rt_metatable_model")

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function kind(v) return v and v.kind or nil end
local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate_operation_operand(operand)
  local errors = {}
  if cls(operand) ~= RT.OperationOperand then add(errors, "expected LuaRT.OperationOperand"); return false, errors end
  if not member(operand.source, RT.OperandSourceKind) then add(errors, "source must be LuaRT.OperandSourceKind") end
  if not member(operand.value, RT.ValueRef) then add(errors, "value must be LuaRT.ValueRef") end
  if type(operand.flipped) ~= "boolean" then add(errors, "flipped must be boolean") end
  return #errors == 0, errors
end

function M.validate_companion_context(companion)
  local errors = {}
  if not member(companion, RT.CompanionContext) then add(errors, "expected LuaRT.CompanionContext"); return false, errors end
  local k = kind(companion)
  if k == "MMBINCompanion" or k == "MMBINICompanion" or k == "MMBINKCompanion" then
    if cls(companion.pc) ~= RT.Pc then add(errors, "pc must be LuaRT.Pc") end
    if not member(companion.method, RT.Metamethod) then add(errors, "method must be LuaRT.Metamethod") end
    if (k == "MMBINICompanion" or k == "MMBINKCompanion") and type(companion.operands_flipped) ~= "boolean" then add(errors, "operands_flipped must be boolean") end
  elseif k == "ExtraArgCompanion" then
    if cls(companion.pc) ~= RT.Pc then add(errors, "pc must be LuaRT.Pc") end
    if cls(companion.ax) ~= RT.Ax then add(errors, "ax must be LuaRT.Ax") end
  end
  return #errors == 0, errors
end

function M.validate_lua_operation(operation)
  local errors = {}
  if cls(operation) ~= RT.LuaOperation then add(errors, "expected LuaRT.LuaOperation"); return false, errors end
  if cls(operation.pc) ~= RT.Pc then add(errors, "pc must be LuaRT.Pc") end
  if not member(operation.kind, RT.OperationKind) then add(errors, "kind must be LuaRT.OperationKind") end
  for i, operand in ipairs(operation.operands or {}) do
    local ok, errs = M.validate_operation_operand(operand)
    if not ok then for _, e in ipairs(errs) do add(errors, "operands[" .. i .. "] " .. e) end end
  end
  for i, result in ipairs(operation.results or {}) do
    if not member(result, RT.ValueRef) then add(errors, "results[" .. i .. "] must be LuaRT.ValueRef") end
  end
  local ok_companion, companion_errors = M.validate_companion_context(operation.companion)
  if not ok_companion then for _, e in ipairs(companion_errors) do add(errors, "companion " .. e) end end
  local ok_path, path_errors = Metatable.validate_metamethod_lookup_path(operation.metamethod_path)
  if not ok_path then for _, e in ipairs(path_errors) do add(errors, "metamethod_path " .. e) end end
  return #errors == 0, errors
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({
    "OperationKind", "OperandSourceKind", "OperationOperand", "CompanionContext", "LuaOperation",
    "OpAdd", "OpSub", "OpBand", "OpBNot", "OpConcat", "OpEq",
    "RegisterOperand", "ImmediateOperand", "ConstantOperand",
    "NoCompanion", "MMBINCompanion", "MMBINICompanion", "MMBINKCompanion", "ExtraArgCompanion",
  }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
