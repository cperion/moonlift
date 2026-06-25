#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Opt-in future completeness gate: this is intentionally stricter than the
-- main suite and is not part of the green implemented-slice gate until the
-- corresponding LalinCFG regions exist. It must never treat rejection as success.

local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local T = Schema.get()

local names = {}
for cls in pairs(T.LuaSrc.Op.members) do
  local kind = cls.kind
  if kind and kind ~= "UnsupportedOpcode" then names[#names + 1] = kind end
end
table.sort(names)

local function luaexec_ok(case)
  local r = C.compile_to_lalin_kernel(C.unit_from_events(case.events, case.evidence or {}))
  if r.kind ~= "Ok" then return false, r end
  local k = r.product and r.product.kernel
  if not (k and k.id and k.id.name and k.id.name.text == "lua_exec_core_kernel") then
    return false, { route = k and k.id and k.id.name and k.id.name.text or "unknown" }
  end
  return true, r
end

local valid_cases = {
  { label = "LuaExec ADD fixture", events = { {op="ADD", pc=1, a=1, b=1, c=2}, {op="RETURN1", pc=2, a=1} } },
  { label = "raw/no-metatable GETTABLE fixture", events = { {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} } },
  { label = "raw/no-metatable SETTABLE fixture", events = { {op="SETTABLE", pc=1, a=2, b=3, c=1, k=false} } },
  { label = "variable-count VARARG fixture", events = { {op="VARARG", pc=1, a=1, c=0}, {op="RETURN", pc=2, a=1, b=0} } },
  { label = "multivalue RETURN fixture", events = { {op="RETURN", pc=1, a=1, b=0} } },
  { label = "ERRNNIL runtime-check fixture", events = { {op="ERRNNIL", pc=1, a=1} } },
}

local red = {}
for _, case in ipairs(valid_cases) do
  local ok, r = luaexec_ok(case)
  if not ok then
    local reason = r.diagnostic and r.diagnostic.reason and r.diagnostic.reason.kind or r.route or tostring(r.kind)
    red[#red + 1] = case.label .. " -> " .. reason
  end
end

local legacy_only = {
  { label = "unsupported MUL must not fallback", events = { {op="MUL",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, evidence = { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"} } },
  { label = "unsupported FORPREP must not fallback", events = { {op="FORPREP",pc=1,a=1,sbx=1}, {op="RETURN0",pc=2} } },
  { label = "unsupported SETLIST must not drop side effect", events = { {op="SETLIST",pc=1,a=1,vb=1,vc=1,k=false}, {op="RETURN0",pc=2} } },
}
for _, case in ipairs(legacy_only) do
  local r = C.compile_to_lalin_kernel(C.unit_from_events(case.events, case.evidence or {}))
  if r.kind ~= "Reject" then red[#red + 1] = case.label .. " -> unexpected Ok" end
end

if #red > 0 then
  io.stderr:write("SpongeJIT LuaCompile completion is RED: supported LuaExec/LalinCFG fixtures still reject\n")
  for _, line in ipairs(red) do io.stderr:write("  ", line, "\n") end
  error("LuaCompile lowering incomplete: supported fixtures did not compile through LuaExec/LalinCFG", 0)
end

print("ok - SpongeJIT LuaCompile completion (LuaExec/LalinCFG semantic fixtures)")
