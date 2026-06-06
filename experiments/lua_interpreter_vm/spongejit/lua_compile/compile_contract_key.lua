-- compile_contract_key.lua -- structural identity for CompileContract values.

local pvm = require("moonlift.pvm")
local Schema = require("lua_compile.schema")
local T = Schema.get()

local M = {}

-- Semantic assumptions are intentionally keyed structurally through ASDL fields.
-- Arity/result routes, call target identity, static region bindings, metatable
-- lookup paths, upvalue identity, GC/FFI effects, loop topology, and close plans
-- must never be encoded as variant strings.
local function key_value(v, seen)
  local tv = type(v)
  if tv == "nil" then return "nil" end
  if tv == "string" then return string.format("%q", v) end
  if tv == "number" or tv == "boolean" then return tostring(v) end
  if tv ~= "table" then return "<" .. tv .. ">" end

  seen = seen or {}
  if seen[v] then return "<cycle>" end
  seen[v] = true

  local cls = pvm.classof(v)
  if cls then
    local plan = rawget(cls, "__plan")
    local name = (plan and plan.name) or tostring(v.kind or cls)
    local fields = rawget(cls, "__fields") or {}
    local parts = { name }
    for _, f in ipairs(fields) do
      parts[#parts + 1] = f.name .. "=" .. key_value(v[f.name], seen)
    end
    seen[v] = nil
    return table.concat(parts, "|")
  end

  local arr = {}
  for i = 1, #v do arr[#arr + 1] = key_value(v[i], seen) end
  seen[v] = nil
  return "[" .. table.concat(arr, ",") .. "]"
end

function M.key(contract)
  assert(pvm.classof(contract) == T.CompileContract.Contract, "expected CompileContract.Contract")
  return "CompileContract\n" .. key_value(contract)
end

return M
