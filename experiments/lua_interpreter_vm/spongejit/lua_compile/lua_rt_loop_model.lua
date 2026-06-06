-- lua_rt_loop_model.lua -- numeric/generic loop state and topology products.
-- Structural validation only; loop execution remains unsupported until lowered explicitly.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local RT = T.LuaRT

local M = {}
local function cls(v) return pvm.classof(v) end
local function member(v, sum) return v ~= nil and sum and sum.members and sum.members[cls(v)] or false end
local function add(errors, msg) errors[#errors + 1] = msg end

function M.validate_loop_topology(topology)
  local errors = {}
  if not member(topology, RT.LoopTopology) then add(errors, "expected LuaRT.LoopTopology"); return false, errors end
  if cls(topology.prep_pc) ~= RT.Pc then add(errors, "prep_pc must be LuaRT.Pc") end
  if topology.call_pc and cls(topology.call_pc) ~= RT.Pc then add(errors, "call_pc must be LuaRT.Pc") end
  if cls(topology.loop_pc) ~= RT.Pc then add(errors, "loop_pc must be LuaRT.Pc") end
  if cls(topology.body_start) ~= RT.Pc then add(errors, "body_start must be LuaRT.Pc") end
  if cls(topology.exit_pc) ~= RT.Pc then add(errors, "exit_pc must be LuaRT.Pc") end
  return #errors == 0, errors
end

function M.validate_numeric_for_state(state)
  local errors = {}
  if not member(state, RT.NumericForState) then add(errors, "expected LuaRT.NumericForState"); return false, errors end
  if cls(state.base) ~= RT.Slot then add(errors, "base must be LuaRT.Slot") end
  return #errors == 0, errors
end

function M.validate_generic_for_state(state)
  local errors = {}
  if cls(state) ~= RT.GenericForState then add(errors, "expected LuaRT.GenericForState"); return false, errors end
  if cls(state.base) ~= RT.Slot then add(errors, "base must be LuaRT.Slot") end
  if cls(state.wanted_results) ~= RT.Count then add(errors, "wanted_results must be LuaRT.Count") end
  return #errors == 0, errors
end

function M.validate_against_schema()
  local missing = {}
  for _, name in ipairs({ "LoopTopology", "NumericForTopology", "GenericForTopology", "NumericForState", "IntegerForState", "FloatForState", "GenericForState" }) do
    if RT[name] == nil then missing[#missing + 1] = "LuaRT." .. name end
  end
  table.sort(missing)
  return #missing == 0, missing
end

return M
