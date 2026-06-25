-- worker_compile.lua -- LuaCompile foundry worker.
-- Usage: luajit src/worker_compile.lua <chunk_id>
--
-- Maintained offline foundry path:
--   opcode sequence + foundry evidence -> LuaCompile.Unit -> LuaRT/LuaExec
--   -> LalinCFG.Kernel/Lalin source -> LalinCFG + CompileContract + Stencil.VariantKey.
--
-- This worker only uses the maintained ASDL/LalinCFG/stencil compiler path.

package.path = '../?.lua;../?/init.lua;?.lua;?/init.lua;src/?.lua;src/?/init.lua;../../../lua/?.lua;../../../lua/?/init.lua;' .. package.path

local Foundry = require("lua_compile.lua_compile_foundry")

local ci = tonumber(arg[1])
assert(ci, "usage: luajit src/worker_compile.lua <chunk_id>")

local tmpdir = os.getenv("SPON_TMP") or "build/lua_compile_foundry"
local progress = tonumber(os.getenv("WORKER_PROGRESS_SEQS") or "1000") or 1000
local config = {
  max_fact_combos = tonumber(os.getenv("MAX_FACT_COMBOS") or "32") or 32,
  max_arity = tonumber(os.getenv("MAX_ARITY") or "2") or 2,
}

local function tmp(name) return tmpdir .. "/" .. name end
local chunk = Foundry.read_json(tmp("lua_compile_chunk_" .. ci .. ".json"))
local windows = chunk.windows or chunk

io.stderr:write(string.format("[LCW%d] START windows=%d max_fact_combos=%s\n", ci, #windows, tostring(config.max_fact_combos)))
if progress > 0 then io.stderr:write(string.format("[LCW%d] compiling LuaCompile windows...\n", ci)) end

local result = Foundry.run_windows(windows, config)
result.chunk = ci
Foundry.write_json(tmp("lua_compile_worker_" .. ci .. ".json"), result)

io.stderr:write(string.format("[LCW%d] DONE windows=%d compiles=%d ok=%d rejected=%d reps=%d out=%s\n",
  ci,
  result.stats.windows or 0,
  result.stats.compiles or 0,
  result.stats.ok or 0,
  result.stats.rejected or 0,
  result.stats.unique_representatives or 0,
  tmp("lua_compile_worker_" .. ci .. ".json")))
