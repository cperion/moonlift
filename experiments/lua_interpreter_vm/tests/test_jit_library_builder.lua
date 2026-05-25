-- Offline stencil library generator/pruner tests.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Builder = require("experiments.lua_interpreter_vm.src.jit.library_builder")

local manifest = {
    kind = "CandidateManifest",
    candidates = {
        {
            name = "cand_a",
            class = "value.a",
            implements = "value.a",
            pattern_key = "a",
            semantic_pattern = {
                name = "a",
                class = "value.a",
                ops = { { op = "A", args = {} } },
                effects = { "PURE" },
                exits = {},
                projections = {},
            },
            extracted = { size = 10, holes = {}, relocs = {}, bytes_hex = "aa" },
            score = { status = "complete", size = 10 },
        },
        {
            name = "cand_b",
            class = "value.b",
            implements = "value.b",
            pattern_key = "b",
            semantic_pattern = {
                name = "b",
                class = "value.b",
                ops = { { op = "B", args = {} } },
                effects = { "PURE" },
                exits = {},
                projections = {},
            },
            extracted = { size = 12, holes = {}, relocs = {}, bytes_hex = "bb" },
            score = { status = "complete", size = 12 },
        },
        {
            name = "cand_bad",
            class = "bad",
            pattern_key = "bad",
            semantic_pattern = { name = "bad", class = "bad", ops = { { op = "BAD", args = {} } }, effects = {}, exits = {}, projections = {} },
            extracted = { size = 1 },
            score = { status = "incomplete", size = 1 },
        },
    },
}

local atoms = Builder.atoms_from_manifest(manifest)
assert(#atoms == 2)
assert(atoms[1].status == "promoted_primitive")

local plan = Builder.build_promotion_plan(manifest, {
    max_depth = 1,
    max_arity = 2,
    max_promotions_per_round = 8,
    max_variants = 2,
    min_benefit = 1,
}, { ["*"] = 10 })

assert(plan.primitive_count == 2)
assert(#plan.rounds == 1)
assert(plan.rounds[1].candidate_count == 4)
assert(plan.rounds[1].promoted_count > 0)
assert(plan.library_count == plan.primitive_count + plan.rounds[1].promoted_count)

local saw_ab = false
for _, c in ipairs(plan.rounds[1].promoted) do
    local ops = {}
    for _, op in ipairs(c.ops) do ops[#ops + 1] = op.op end
    if table.concat(ops, ",") == "A,B" then
        saw_ab = true
        assert(c.status == "promotion_candidate")
        assert(c.replacement.kind == "code_stencil_needed")
        assert(c.summary.closure_depth == 1)
    end
end
assert(saw_ab)

local kept, rejected = Builder.prune_candidates(plan.rounds[1].candidates, {
    max_depth = 1,
    max_arity = 2,
    max_promotions_per_round = 1,
    max_variants = 1,
    min_benefit = 1,
})
assert(#kept == 1)
assert(#rejected >= 1)

print("JIT library builder: ok")
