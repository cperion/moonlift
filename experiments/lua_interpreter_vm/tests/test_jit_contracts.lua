-- JIT contract surface smoke test.
--
-- The current simplified JIT has one concrete contract surface: the empirical
-- miner products plus the curated stencil-library catalog.  Older placeholder
-- region/product headers were removed with the multi-tier prototype.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local miner = require("experiments.lua_interpreter_vm.src.jit.miner_contracts")
local stencils = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local fixtures = require("experiments.lua_interpreter_vm.src.jit.stencil_fixtures")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name)
    end
end

local p = miner.StatePattern {
    name = "smoke.pattern",
    class = "smoke",
    ops = {
        miner.StateOp("ReadSlot", { slot = "a" }),
        miner.StateOp("WriteSlot", { slot = "b" }),
    },
    effects = { "PURE" },
}

local c = miner.StencilCandidate {
    name = "smoke.candidate",
    implements = "value.move.sB_to_sA.fall",
    pattern = p,
    source = "func smoke() -> void return end",
}

local manifest = miner.CandidateManifest {
    target = "smoke",
    candidates = {
        {
            name = c.name,
            pattern_key = p.canonical_key,
            extracted = { size = 0 },
            score = miner.CandidateScore { status = "complete" },
        },
    },
}

local ok, errors = miner.validate_manifest(manifest)
check("StateOp", p.ops[1].kind == "StateOp")
check("StatePattern canonical key", type(p.canonical_key) == "string" and p.canonical_key:match("ReadSlot") ~= nil)
check("StencilCandidate", c.kind == "StencilCandidate" and c.implements == "value.move.sB_to_sA.fall")
check("CandidateManifest validate", ok and #errors == 0)
check("JSON encoder", miner.encode_json(manifest):match('"CandidateManifest"') ~= nil)

local required_stencils = {
    "entry.vm_state_to_unit",
    "edge.jump_indirect",
    "project.live_slots.bundle",
    "value.move.sB_to_sA.fall",
    "value.load_i64.imm_to_sA.fall",
    "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit",
    "loop.forloop_i64.sA_Bx.loop_or_exit",
    "table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow",
    "call.known_lclosure.sF_args.enter_lua",
    "super.method_self_move_call.ic1",
}

for _, name in ipairs(required_stencils) do
    local s = stencils.by_name[name]
    check("stencil " .. name, type(s) == "table" and s.kind == "CodeStencilSpec")
end

check("semantic entries present", #stencils.semantic_entries() >= 10)
check("catalog entries present", #stencils.catalog_entries() >= 10)
check("seed fixtures present", #fixtures.seed_fixtures >= 4)
check("fixture maps to spec", fixtures.first_fixture("value.load_i64.imm_to_sA.fall").spec_name == "value.load_i64.imm_to_sA.fall")
check("constants present", type(stencils.Tag.INTEGER) == "number" and type(stencils.Op.ADD) == "number")

print(string.format("JIT contracts: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
