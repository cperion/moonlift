-- lua_compile/diagnostics.lua -- structured debug formatting.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")

local M = {}

local function class_name(v)
  local cls = pvm.classof(v)
  if not cls then return type(v) end
  local plan = rawget(cls, "__plan")
  return (plan and plan.name) or tostring(cls)
end
M.class_name = class_name

local function scalar(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local function render(v, depth, seen)
  depth = depth or 0
  seen = seen or {}
  if type(v) ~= "table" then return scalar(v) end
  if seen[v] then return "<cycle>" end
  local cls = pvm.classof(v)
  if not cls then
    if depth > 4 then return "{...}" end
    seen[v] = true
    local parts = {}
    for i = 1, #v do parts[#parts + 1] = render(v[i], depth + 1, seen) end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
  end
  local fields = rawget(cls, "__fields") or {}
  if #fields == 0 then return tostring(v.kind or class_name(v):match("[^.]+$")) end
  if depth > 4 then return (v.kind or class_name(v)) .. "(...)" end
  seen[v] = true
  local parts = {}
  for _, f in ipairs(fields) do parts[#parts + 1] = f.name .. "=" .. render(v[f.name], depth + 1, seen) end
  seen[v] = nil
  return tostring(v.kind or class_name(v):match("[^.]+$")) .. "(" .. table.concat(parts, ",") .. ")"
end

function M.render(node) return render(node) end

function M.diagnostic(d)
  if not d then return "<no diagnostic>" end
  return string.format("diagnostic stage=%s pc=%s reason=%s op=%s message=%s",
    tostring(d.stage and d.stage.kind),
    tostring(d.pc and d.pc.id),
    tostring(d.reason and d.reason.kind),
    tostring(d.source_op and d.source_op.kind),
    tostring(d.message or ""))
end

function M.report(result)
  local cls = Schema.classof(result)
  local T = Schema.get()
  if cls == T.LuaCompile.Result then return render(result) end
  return render(result)
end

return M
