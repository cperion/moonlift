-- lua_compile/errors.lua -- structured compile diagnostic helpers.
--
-- Unsupported cases are compile/lower/select diagnostics.  This module contains
-- no fallback/helper logic and does not depend on retired semantic products.

local Schema = require("lua_compile.schema")
local T = Schema.get()
local Src = T.LuaSrc
local Compile = T.LuaCompile

local M = {}

local REASON = {
  contradictory_evidence = Compile.ContradictoryEvidence,
  missing_fact = Compile.MissingFact,
  missing_payload_lease = Compile.MissingPayloadLease,
  unsupported_opcode = Compile.UnsupportedOpcode,
  unsupported_fact_combination = Compile.UnsupportedFactCombination,
  unsupported_semantic_case = Compile.UnsupportedSemanticCase,
  semantic_not_implemented = Compile.UnsupportedSemanticCase,
  requires_fact_bundle = Compile.MissingFact,
  unsupported_loop_region = Compile.UnsupportedLoopRegion,
  unsupported_projection = Compile.UnsupportedProjection,
  validation_failure = Compile.ValidationFailure,
  lowering_failure = Compile.LoweringFailure,
  internal_invariant_failure = Compile.InternalInvariantFailure,
  stencil_materialization_failure = Compile.StencilMaterializationFailure,
}

local STAGE = {
  lua_src_decode = Compile.LuaSrcDecode,
  lua_src_validate = Compile.LuaSrcValidate,
  lua_exec_lower = Compile.LuaExecLower,
  lua_exec_validate = Compile.LuaExecValidate,
  lua_exec_to_lalin_cfg_lower = Compile.LalinCFGLower,
  lalin_cfg_lower = Compile.LalinCFGLower,
  lalin_cfg_validate = Compile.LalinCFGValidate,
  lalin_cfg_emit = Compile.LalinCFGEmit,
  stencil_validate = Compile.StencilValidate,
  stencil_materialize = Compile.StencilMaterialize,
  foundry = Compile.Foundry,
}

function M.reason(name)
  local r = REASON[name] or REASON[tostring(name or ""):lower()]
  if not r then error("unknown LuaCompile diagnostic reason: " .. tostring(name), 2) end
  return r
end

function M.stage(name)
  local s = STAGE[name] or STAGE[tostring(name or ""):lower()]
  if not s then error("unknown LuaCompile diagnostic stage: " .. tostring(name), 2) end
  return s
end

function M.diagnostic(stage, pc, reason, source_op, message, missing_facts, missing_payloads)
  local pc_node = type(pc) == "table" and pc or Src.Pc(tonumber(pc) or 0)
  local op = source_op or Src.UnsupportedOpcode(pc_node, "<unknown>")
  return Compile.Diagnostic(
    M.stage(stage),
    M.reason(reason),
    pc_node,
    op,
    tostring(message or ""),
    missing_facts or {},
    missing_payloads or {}
  )
end

function M.reject(stage, pc, reason, source_op, message, missing_facts, missing_payloads)
  return Compile.Reject(M.diagnostic(stage, pc, reason, source_op, message, missing_facts, missing_payloads))
end

local function first_source_op(window)
  local op = window and window.ops and window.ops[1]
  if op and op.pc then return op end
  return nil
end

function M.diagnostic_from_errors(stage, window, errors, reason)
  local op = first_source_op(window)
  local pc = op and op.pc or Src.Pc(0)
  return M.diagnostic(
    stage,
    pc,
    reason or "unsupported_semantic_case",
    op or Src.UnsupportedOpcode(pc, tostring(stage or "lua_compile")),
    table.concat(errors or {}, "; "),
    {},
    {}
  )
end

function M.compile_reject_from_errors(stage, window, errors, reason)
  return T.LuaCompile.Reject(M.diagnostic_from_errors(stage, window, errors, reason))
end

return M
