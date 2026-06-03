#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local Foundry = require("lua_compile.lua_compile_foundry")

local artifact = os.getenv("LUA_COMPILE_CORPUS_ARTIFACT") or "experiments/lua_interpreter_vm/spongejit/build/lua_compile_corpus100/lua_compile_representatives.json"
local min_windows = tonumber(os.getenv("LUA_COMPILE_CORPUS_MIN_WINDOWS") or "100") or 100

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

if not exists(artifact) then
  if os.getenv("LUA_COMPILE_CORPUS_REQUIRED") == "1" then
    error("missing LuaCompile corpus artifact: " .. artifact .. "\nrun: (cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100)")
  end
  print("ok - SpongeJIT LuaCompile corpus100 skipped (artifact not built; run make test-lua-compile-corpus100)")
  os.exit(0)
end

local result = Foundry.read_json(artifact)
if result.schema ~= "sponjit.lua_compile_foundry.v2" then
  if os.getenv("LUA_COMPILE_CORPUS_REQUIRED") == "1" then
    error("stale LuaCompile corpus artifact schema " .. tostring(result.schema) .. "; rerun make test-lua-compile-corpus100")
  end
  print("ok - SpongeJIT LuaCompile corpus100 skipped (stale pre-Stencil artifact; run make test-lua-compile-corpus100)")
  os.exit(0)
end
if result.representatives and result.representatives[1]
   and not tostring(result.representatives[1].representative_key or ""):match("MoonCFG") then
  if os.getenv("LUA_COMPILE_CORPUS_REQUIRED") == "1" then
    error("stale LuaCompile corpus artifact does not contain MoonCFG representatives; rerun make test-lua-compile-corpus100")
  end
  print("ok - SpongeJIT LuaCompile corpus100 skipped (stale pre-MoonCFG artifact; run make test-lua-compile-corpus100)")
  os.exit(0)
end

local REQUIRED_OP_FIELDS = { "proto", "pc", "opcode", "word", "a", "b", "c", "k", "bx", "sbx", "ax", "sb", "sc", "sj", "vb", "vc" }
local function full_operand_window(ops)
  if not ops or #ops == 0 then return false end
  for _, op in ipairs(ops) do
    if type(op) ~= "table" then return false end
    for _, k in ipairs(REQUIRED_OP_FIELDS) do
      if op[k] == nil then return false end
    end
  end
  return true
end

local windows = {}
local aliases = 0
local partial_aliases = 0
for _, rep in ipairs(result.representatives or {}) do
  assert(type(rep.representative_key) == "string" and rep.representative_key:match("MoonCFG") and rep.representative_key:match("LuaContract") and rep.representative_key:match("Stencil%.VariantKey"), "representative key must include MoonCFG + LuaContract + Stencil.VariantKey identity")
  assert(rep.stencil_variant_key, "representative must carry Stencil.VariantKey identity")
  assert(not rep.stencil_variant_key:match("OP_"), "stencil variant key must not be opcode-shaped")
  assert(not rep.stencil_variant_key:match("spon" .. "bank"), "stencil variant key must not use old bank ABI")
  assert(type(rep.moonlift_source) == "string" and rep.moonlift_source:match("func%("), "representative must carry emitted Moonlift source")
  assert(not rep.moonlift_source:match("out_tag"), "MoonCFG source must not use out_tag protocol ABI")
  assert(not rep.moonlift_source:match("Spon") and not rep.moonlift_source:match("stencil") and not rep.moonlift_source:match("bank"), "Moonlift source must not use backend artifact vocabulary")
  for _, a in ipairs(rep.aliases or {}) do
    aliases = aliases + 1
    if full_operand_window(a.source_ops) then
      windows[a.ops_key or tostring(aliases)] = true
    else
      partial_aliases = partial_aliases + 1
    end
  end
end

local successful_windows = 0
for _ in pairs(windows) do successful_windows = successful_windows + 1 end
local stats = result.stats or {}
assert((stats.windows or 0) >= min_windows, "artifact did not examine enough corpus windows")
assert((stats.ok or 0) >= min_windows, "expected at least " .. min_windows .. " successful LuaCompile compiles, got " .. tostring(stats.ok))
assert(partial_aliases == 0, "corpus100 artifact contains partial/opcode-only successful aliases: " .. tostring(partial_aliases))
assert(successful_windows >= min_windows, "expected at least " .. min_windows .. " distinct full-operand bytecode windows, got " .. tostring(successful_windows))

local compiled = 0
for _, rep in ipairs(result.representatives or {}) do
  local name = "lua_compile_corpus_rep_" .. tostring(rep.representative_id or compiled + 1)
  local chunk, load_err = moon.loadstring(rep.moonlift_source, "=(" .. name .. ")")
  assert(chunk, load_err)
  local fn = chunk()
  local native, compile_err = fn:compile()
  assert(native, compile_err)
  native:free()
  compiled = compiled + 1
end

assert(compiled == #(result.representatives or {}), "not all representatives compiled through Moonlift")
print(string.format("ok - SpongeJIT LuaCompile corpus100 (%d successful windows, %d reps compiled through Moonlift)", successful_windows, compiled))
