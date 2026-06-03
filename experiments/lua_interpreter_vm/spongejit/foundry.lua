#!/usr/bin/env luajit
-- foundry.lua — maintained offline LuaCompile foundry entry point.
--
-- Maintained architecture:
--   opcode windows + facts/evidence
--   -> LuaCompile.Unit
--   -> LuaRT / LuaExec / LuaSem / LuaNF / LuaContract
--   -> MoonCFG.Kernel + emitted Moonlift source
--   -> ASDL StencilTemplate artifacts generated from MoonCFG/LuaExec shapes
--   -> semantic representative key (`MoonCFG + LuaContract + Stencil.VariantKey`)
--
-- Source opcode windows are preserved as aliases/members of semantic
-- representatives. Runtime materialization is handled by the Moonlift-native
-- fact-selection and copy/patch design.
--
-- Usage:
--   luajit foundry.lua [--corpus-mode] [--out DIR] [--max-files N]
--                      [--max-windows N] [--max-fact-combos N] [--max-arity N]

local source = debug.getinfo(1, "S").source
local function cwd()
  local p = io.popen("pwd")
  local s = p and p:read("*l") or "."
  if p then p:close() end
  return s or "."
end
local spongejit = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*/spongejit)") or cwd()
package.path = spongejit .. "/?.lua;" .. spongejit .. "/?/init.lua;" .. spongejit .. "/src/?.lua;" .. spongejit .. "/src/?/init.lua;" .. spongejit .. "/../../../lua/?.lua;" .. spongejit .. "/../../../lua/?/init.lua;" .. package.path

local function dirname(path)
  return tostring(path or "."):gsub("/+$", ""):match("^(.*)/[^/]+$") or "."
end

local lua_vm_root = dirname(spongejit)
local experiments_root = dirname(lua_vm_root)
local root = dirname(experiments_root)

local LuaFoundry = require("lua_compile.lua_compile_foundry")

local DEFAULTS = {
  corpus_awfy_root = root .. "/experiments/lua_interpreter_vm",
  corpus_moonlift_root = root .. "/lua/moonlift",
  out_dir = spongejit .. "/build/lua_compile_foundry",
  max_files = 200,
  max_regions = 10000,
  max_windows = 100000,
  max_fact_combos = 32,
  max_arity = 2,
  corpus_mode = false,
}

local function load_corpus_windows(config)
  print("[foundry] loading corpus opcode windows for LuaCompile...")
  local Loader = require("src.loader")
  local workloads = {}
  local function add_from(root_dir, prefix)
    local profile = Loader.profile_lua_root(root_dir, { max_files = config.max_files })
    for _, w in ipairs(Loader.workloads_from_profile(profile, {
      max_regions = config.max_regions,
      max_len = math.max(1, config.max_arity),
      min_len = 1,
      fact_mode = "none",
      operand_only = true,
    })) do
      w.name = prefix .. tostring(w.name or "")
      workloads[#workloads + 1] = w
    end
  end
  add_from(config.corpus_awfy_root, "awfy_")
  add_from(config.corpus_moonlift_root, "moonlift_")

  local by_key, windows = {}, {}
  local function key(ops)
    local parts = {}
    for _, op in ipairs(ops or {}) do
      local fields = {}
      if type(op) == "table" then
        local keys = {}
        for k in pairs(op) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do fields[#fields + 1] = tostring(k) .. "=" .. tostring(op[k]) end
      else
        fields[1] = tostring(op)
      end
      parts[#parts + 1] = table.concat(fields, ",")
    end
    return table.concat(parts, "|")
  end
  for _, w in ipairs(workloads) do
    local events = w.events or {}
    for i = 1, #events do
      local ops = {}
      for j = i, math.min(#events, i + config.max_arity - 1) do
        ops[#ops + 1] = events[j]
        local k = key(ops)
        local cur = by_key[k]
        if not cur then
          cur = { ops = {}, count = 0, examples = {} }
          for n, op in ipairs(ops) do cur.ops[n] = op end
          by_key[k] = cur
          windows[#windows + 1] = cur
        end
        cur.count = cur.count + (tonumber(events[i].freq or 1) or 1)
        if #cur.examples < 3 then cur.examples[#cur.examples + 1] = tostring(w.name or "?") .. ":pc" .. tostring(i) end
      end
    end
  end
  table.sort(windows, function(a, b)
    if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
    return key(a.ops) < key(b.ops)
  end)
  local clipped = {}
  for i = 1, math.min(#windows, tonumber(config.max_windows or #windows) or #windows) do clipped[i] = windows[i] end
  print(string.format("[foundry] %d workload regions -> %d opcode windows", #workloads, #clipped))
  return clipped
end

local function run(config)
  local windows
  if config.corpus_mode then windows = load_corpus_windows(config)
  else windows = LuaFoundry.grammar_windows(config) end

  print(string.format("[foundry] compiling %d windows through LuaCompile", #windows))
  local result = LuaFoundry.run_windows(windows, {
    max_fact_combos = config.max_fact_combos,
    max_arity = config.max_arity,
  })
  LuaFoundry.write_artifacts(result, config.out_dir)
  print(string.format("[foundry] done: reps=%d compiles=%d ok=%d rejected=%d out=%s/lua_compile_representatives.json",
    result.stats.unique_representatives or 0,
    result.stats.compiles or 0,
    result.stats.ok or 0,
    result.stats.rejected or 0,
    config.out_dir))
  return result
end

local function main(args)
  local config = {}
  for k, v in pairs(DEFAULTS) do config[k] = v end
  args = args or arg or {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--max-files" then config.max_files = tonumber(args[i+1]); i = i + 1
    elseif a == "--max-regions" then config.max_regions = tonumber(args[i+1]); i = i + 1
    elseif a == "--max-windows" then config.max_windows = tonumber(args[i+1]); i = i + 1
    elseif a == "--max-fact-combos" then config.max_fact_combos = tonumber(args[i+1]); i = i + 1
    elseif a == "--max-arity" then config.max_arity = tonumber(args[i+1]); i = i + 1
    elseif a == "--out" then config.out_dir = args[i+1]; i = i + 1
    elseif a == "--corpus-mode" then config.corpus_mode = true
    end
    i = i + 1
  end
  return run(config)
end

if arg and arg[0] and tostring(arg[0]):match("foundry%.lua$") then main(arg) end

return { main = main, run = run }
