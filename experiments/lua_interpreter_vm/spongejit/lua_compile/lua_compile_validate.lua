-- lua_compile_validate.lua -- whole-pipeline invariants.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local M = {}

function M.validate_result(result)
  if not T.LuaCompile.Result.members[pvm.classof(result)] then return false, { "expected LuaCompile.Result" } end
  return true, {}
end

function M.validate_source_event(event)
  if not T.LuaCompile.SourceEvent.members[pvm.classof(event)] then return false, { "expected LuaCompile.SourceEvent" } end
  return true, {}
end

function M.validate_source_event_batch(batch)
  if pvm.classof(batch) ~= T.LuaCompile.SourceEventBatch then return false, { "expected LuaCompile.SourceEventBatch" } end
  for i, event in ipairs(batch.events or {}) do
    if not T.LuaCompile.SourceEvent.members[pvm.classof(event)] then return false, { "events[" .. tostring(i) .. "] expected LuaCompile.SourceEvent" } end
  end
  return true, {}
end

function M.validate_evidence_input(input)
  if pvm.classof(input) ~= T.LuaCompile.EvidenceInput then return false, { "expected LuaCompile.EvidenceInput" } end
  for i, record in ipairs(input.records or {}) do
    if not T.LuaCompile.EvidenceRecord.members[pvm.classof(record)] then return false, { "records[" .. tostring(i) .. "] expected LuaCompile.EvidenceRecord" } end
  end
  return true, {}
end

function M.validate_exec_lower_result(result)
  if not T.LuaCompile.ExecLowerResult.members[pvm.classof(result)] then return false, { "expected LuaCompile.ExecLowerResult" } end
  return true, {}
end

function M.validate_lalin_lower_result(result)
  if not T.LuaCompile.LalinLowerResult.members[pvm.classof(result)] then return false, { "expected LuaCompile.LalinLowerResult" } end
  return true, {}
end

function M.validate_static_inline_result(result)
  if not T.LuaCompile.StaticInlineResult.members[pvm.classof(result)] then return false, { "expected LuaCompile.StaticInlineResult" } end
  return true, {}
end

return M
