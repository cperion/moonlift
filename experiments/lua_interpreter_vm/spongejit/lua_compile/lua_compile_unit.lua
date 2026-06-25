-- lua_compile_unit.lua -- LuaCompile.Unit construction.

local B = require("lua_compile.builders")
local pvm = require("lalin.pvm")
local Collect = require("lua_compile.lua_src_window_collect")
local FactObserve = require("lua_compile.lua_fact_from_runtime_observe")

local M = {}

function M.from_parts(source_window, evidence)
  return B.LuaCompile.Unit(source_window, evidence or B.empty_evidence())
end

local phase = pvm.phase("spongejit_lua_compile_unit_from_inputs", function(source_batch, evidence_input)
  local window = Collect.collect(source_batch)
  local evidence = FactObserve.import(evidence_input)
  return M.from_parts(window, evidence)
end)

function M.from_inputs(source_batch, evidence_input)
  return pvm.one(phase(source_batch, evidence_input))
end

function M.from_events(events, observations)
  local batch = Collect.event_batch(events or {})
  local evidence_input = FactObserve.evidence_input(observations or {})
  return M.from_inputs(batch, evidence_input)
end

M.phase = phase
return M
