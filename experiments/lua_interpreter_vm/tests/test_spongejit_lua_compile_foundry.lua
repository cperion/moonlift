#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./experiments/lua_interpreter_vm/spongejit/src/?.lua;./experiments/lua_interpreter_vm/spongejit/src/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Foundry = require("lua_compile.lua_compile_foundry")

assert(package.loaded["src.ssa"] == nil, "LuaCompile foundry must not require old src.ssa")
assert(package.loaded["src.ssa_ir"] == nil, "LuaCompile foundry must not require old src.ssa_ir")
assert(package.loaded["src.ssa_to_stencil"] == nil, "LuaCompile foundry must not require old src.ssa_to_stencil")
assert(package.loaded["src.stencil_lower"] == nil, "LuaCompile foundry must not require old src.stencil_lower")

local windows = {
  {
    ops = { { op = "ADDI", pc = 1, a = 1, b = 1, c = 128, sc = 1 }, { op = "RETURN1", pc = 2, a = 1 } },
    count = 3,
    fact_bundles = { { { slot = 1, predicate = "is_i64" } } },
  },
  {
    ops = { { op = "ADDK", pc = 1, a = 1, b = 1, c = 2 }, { op = "RETURN1", pc = 2, a = 1 } },
    count = 5,
    fact_bundles = { { { slot = 1, predicate = "is_i64" }, { const = 2, predicate = "const_i64", value = 1 } } },
  },
}

local result = Foundry.run_windows(windows, { max_fact_combos = 4 })
assert(result.schema == "sponjit.lua_compile_foundry.v2")
assert(result.stats.windows == 2)
assert(result.stats.compiles == 2)
assert(result.stats.ok == 2)
assert(result.stats.unique_representatives == 1, "ADDI and ADDK should dedupe by MoonCFG+LuaContract, not source opcode chain")

local rep = result.representatives[1]
assert(rep.moon_cfg_key and #rep.moon_cfg_key > 20, "MoonCFG key missing")
assert(rep.contract_key and #rep.contract_key > 20, "contract key missing")
assert(rep.stencil_variant_key and rep.stencil_variant_key:find("Stencil", 1, true), "Stencil variant key missing")
assert(rep.representative_key:find("MoonCFG", 1, true), "representative must include MoonCFG identity")
assert(rep.representative_key:find("LuaContract", 1, true), "representative must pair MoonCFG and LuaContract")
assert(rep.representative_key:find("Stencil.VariantKey", 1, true), "representative must include Stencil.VariantKey identity")
assert(not rep.representative_key:find("OP_", 1, true), "representative key must not be opcode-shaped")
assert(not rep.representative_key:find("spon" .. "bank", 1, true), "representative key must not use old bank ABI")
assert(rep.moonlift_source and rep.moonlift_source:match("local lua_compile_foundry_kernel = func"), "Moonlift source missing")
assert(not rep.moonlift_source:match("out_tag"), "MoonCFG emitted source must not use out_tag")
assert(rep.moon_cfg_kernel and rep.moon_cfg_kernel.kind == "InlineSpan", "MoonCFG kernel summary missing")
assert(#rep.aliases == 2, "source opcode windows must survive as aliases")
local saw_addi, saw_addk = false, false
for _, a in ipairs(rep.aliases) do
  local op = a.source_ops and a.source_ops[1] and a.source_ops[1].op
  if op == "ADDI" then saw_addi = true end
  if op == "ADDK" then saw_addk = true end
  assert(a.count == 3 or a.count == 5)
end
assert(saw_addi and saw_addk, "aliases must preserve distinct source opcode windows")

local tmp = os.tmpname()
os.remove(tmp)
local mk_ok = os.execute("mkdir -p " .. string.format("%q", tmp))
assert(mk_ok == true or mk_ok == 0)
Foundry.write_artifacts(result, tmp)
local f = assert(io.open(tmp .. "/lua_compile_representatives.json", "rb"))
local text = f:read("*a"); f:close()
assert(text:match("lua_compile_foundry%.v2"), "artifact schema missing")
assert(text:match("moonlift_source"), "artifact must include emitted source")
assert(text:match("moon_cfg_key") and text:match("contract_key") and text:match("stencil_variant_key"), "artifact must include MoonCFG, contract, and stencil variant keys")

-- Maintained worker entrypoint writes LuaCompile vocabulary artifacts.
local chunk = { schema = "sponjit.lua_compile_foundry.chunk.v1", chunk = 1, windows = windows }
Foundry.write_json(tmp .. "/lua_compile_chunk_1.json", chunk)
local cmd = "cd experiments/lua_interpreter_vm/spongejit && SPON_TMP=" .. string.format("%q", tmp) .. " MAX_FACT_COMBOS=4 luajit src/worker_compile.lua 1 >/tmp/lua_compile_foundry_worker.out 2>/tmp/lua_compile_foundry_worker.err"
local ok = os.execute(cmd)
assert(ok == true or ok == 0, "worker_compile.lua LuaCompile worker failed; see /tmp/lua_compile_foundry_worker.err")
local wf = assert(io.open(tmp .. "/lua_compile_worker_1.json", "rb"))
local worker_text = wf:read("*a"); wf:close()
assert(worker_text:match("lua_compile_foundry%.v2"), "worker artifact schema missing")
assert(worker_text:match("moonlift_source") and worker_text:match("stencil_variant_key"), "worker artifact must include MoonCFG emission and stencil identity")
assert(not package.loaded["src.ssa"], "worker test must not load old src.ssa in this process")

os.execute("rm -rf " .. string.format("%q", tmp))
print("ok - SpongeJIT LuaCompile foundry replacement")
