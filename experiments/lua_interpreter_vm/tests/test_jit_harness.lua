#!/usr/bin/env luajit
-- test_jit_harness.lua
-- Test JIT harness pipeline

local source = debug.getinfo(1, "S").source
local base = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*)/tests/test_jit_harness%.lua$") or "."
package.path = base .. "/?.lua;" .. base .. "/?/init.lua;" .. base .. "/../../?.lua;" .. base .. "/../../?/init.lua;" .. base .. "/../../lua/?.lua;" .. base .. "/../../lua/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local function test_fact_trace()
    print("\n=== Test: fact_trace ===")

    local ft = require("tools.jit_harness.fact_trace")

    -- Test value facts
    assert(ft.observe_value_fact(nil) == ft.ValueFact.NIL)
    assert(ft.observe_value_fact(true) == ft.ValueFact.TRUE)
    assert(ft.observe_value_fact(false) == ft.ValueFact.FALSE)
    assert(ft.observe_value_fact(42) == ft.ValueFact.INTEGER)
    assert(ft.observe_value_fact(3.14) == ft.ValueFact.FLOAT)
    assert(ft.observe_value_fact("hello") == ft.ValueFact.STRING)
    assert(ft.observe_value_fact({}) == ft.ValueFact.TABLE)

    print("  ✓ Value fact observation")

    -- Test table facts
    assert(ft.observe_table_fact({}) == ft.TableFact.EMPTY)
    assert(ft.observe_table_fact({1, 2, 3}) == ft.TableFact.ARRAY)
    assert(ft.observe_table_fact({a = 1, b = 2}) == ft.TableFact.HASH)
    assert(ft.observe_table_fact({1, 2, a = 3}) == ft.TableFact.MIXED)

    print("  ✓ Table fact observation")

    -- Test fact canonicalization
    local facts = {"int", "string", "int", "table", "string"}
    local canonical = ft.canonicalize_fact_set(facts)
    assert(#canonical == 3)
    assert(canonical[1] == "int")
    assert(canonical[2] == "string")
    assert(canonical[3] == "table")

    print("  ✓ Fact canonicalization")

    -- Test fact key encoding
    local key = ft.encode_fact_key({"int", "string"})
    assert(type(key) == "string")
    print("  ✓ Fact key encoding")

    print("  ✓ All fact_trace tests passed")
end

local function test_corpus()
    print("\n=== Test: corpus ===")

    local corpus = require("tools.jit_harness.corpus")

    -- Test simple hash
    local hash1 = corpus.simple_hash("hello world")
    assert(type(hash1) == "string")
    assert(string.find(hash1, "^%d+_"))
    print("  ✓ Simple hash")

    -- Test path to ID conversion
    local id = corpus.simple_hash("test/file.lua")
    assert(type(id) == "string")
    print("  ✓ Path to ID conversion")

    -- Test AWFY discovery (if AWFY exists)
    local awfy_files = corpus.discover_awfy(".")
    if #awfy_files > 0 then
        print(string.format("  ✓ AWFY discovery (found %d files)", #awfy_files))
    else
        print("  ⚠ No AWFY files found (skipping)")
    end

    print("  ✓ All corpus tests passed")
end

local function test_compile_static_profile()
    print("\n=== Test: compile + static profile ===")

    local compile = require("tools.jit_harness.compile")
    local profile_static = require("tools.jit_harness.profile_static")

    local bundle, err = compile.compile_lua_unit({ id = "inline", source = "return 1 + 2" }, {
        repo_root = base .. "/../..",
        allow_fallback = false,
    })
    assert(bundle, err and err.detail or "compile failed")
    assert(bundle.compiler == "lalin-lua-vm")
    assert(#bundle.protos[1].code == 5)

    local profile = profile_static.profile_proto_static(bundle, { max_arity = 4 })
    assert(profile.total_opcodes == 5)
    assert(profile.window_counts["LOADI"] == 2)
    assert(profile.window_counts["LOADI|LOADI"] == 1)

    print("  ✓ Real VM bytecode compile and static profile")
end

local function test_candidate_vm_stencil_compile()
    print("\n=== Test: candidate VM stencil compile ===")

    local emit = require("tools.jit_harness.candidate_emit")
    local compile = require("tools.jit_harness.candidate_compile")
    local mine = require("tools.jit_harness.object_mine")

    local out = "/tmp/lalin_jit_harness_test"
    os.execute("rm -rf " .. out)
    local kernel = emit.emit_candidate_kernel({ id = "LOADI_MOVE_smoke", arity = 2, ops = { "LOADI", "MOVE" } }, { output_dir = out .. "/kernels" })
    assert(kernel.abi == "jit_stencil_v0")
    assert(kernel.source:find("ptr%(LuaThread%)"))
    assert(emit.write_kernel_source(kernel, out .. "/kernels"))

    local obj = compile.compile_kernel(kernel, { output_dir = out .. "/objects", repo_root = base .. "/../.." })
    assert(obj.compiled, obj.error)
    local mined = mine.mine_object(obj, {}, {})
    assert(mined.valid)
    assert((mined.object_size or 0) > 0)

    print("  ✓ VM-shaped stencil emits, compiles, and mines deterministically")
end

local function test_seed_l0()
    print("\n=== Test: seed_l0 ===")

    local seed_l0 = require("tools.jit_harness.seed_l0")

    -- Test manual seed loading
    local manual = seed_l0.load_manual_l0_seeds({})
    assert(#manual > 0)
    print(string.format("  ✓ Manual seeds loaded: %d", #manual))

    -- Test seed merging
    local merged = seed_l0.merge_l0_seeds(manual, {})
    assert(#merged == #manual)
    print("  ✓ Seed merging")

    -- Test manifest building
    local manifest = seed_l0.build_l0_seed_manifest(manual, {})
    assert(manifest.manual_seed_count > 0)
    print(string.format("  ✓ Manifest building (seeds: %d)", #manifest.seeds))

    -- Test manifest validation
    local validation = seed_l0.validate_l0_seed_manifest(manifest)
    assert(validation.valid)
    print("  ✓ Manifest validation")

    print("  ✓ All seed_l0 tests passed")
end

local function test_layer_closure()
    print("\n=== Test: layer_closure ===")

    local lc = require("tools.jit_harness.layer_closure")

    -- Create mock seeds
    local seeds = {
        {name = "LOADI", arity = 1},
        {name = "ADD", arity = 1},
        {name = "MOVE", arity = 1},
    }

    -- Test can_sequence
    assert(lc.can_sequence(seeds[1], seeds[2]))
    print("  ✓ Sequence validation")

    -- Test cost estimation
    local cost = lc.estimate_cost(seeds)
    assert(cost.opcodes == 3)
    assert(cost.estimated_size > 0)
    print("  ✓ Cost estimation")

    -- Test budget checking
    local candidate = {
        nodes = seeds,
        arity = 3,
        ops = {"LOADI", "ADD", "MOVE"},
        cost = cost,
    }
    assert(lc.meets_budget(candidate))
    print("  ✓ Budget constraints")

    -- Test pair generation
    local pairs = lc.generate_pairs(seeds, {max_arity = 2, max_size = 300})
    assert(#pairs > 0)
    print(string.format("  ✓ Pair generation (%d pairs)", #pairs))

    -- Test candidate key assignment and shape metadata
    lc.apply_shape_metadata(candidate)
    lc.assign_candidate_key(candidate)
    assert(candidate.id == "LOADI|ADD|MOVE")
    assert(candidate.shape_kind == "fallthrough")
    assert(candidate.lowering == "generic_opcode_sequence")
    print("  ✓ Candidate key assignment and shape metadata")

    -- Test rewrite variants carry explicit legalization/shape metadata
    local expanded = lc.expand_fact_variants({ { arity = 2, ops = { "MOVE", "MOVE" }, cost = { opcodes = 2, estimated_size = 100, estimated_holes = 4, estimated_relocs = 2 } } }, {})
    local found_rewrite = false
    for _, cand in ipairs(expanded) do
        if cand.rewrite_kind == "move_move_forward" then
            found_rewrite = true
            assert(cand.kind == "REWRITE_STENCIL")
            assert(cand.shape_kind == "pure_rewrite")
            assert(cand.lowering == "move_move_forward")
            assert(cand.legalization_source == "operand_fact_rewrite_schema")
        end
    end
    assert(found_rewrite)
    print("  ✓ Rewrite shape legalization metadata")

    print("  ✓ All layer_closure tests passed")
end

local function test_harness_integration()
    print("\n=== Test: harness integration ===")

    local harness = require("tools.jit_harness.harness")
    harness.init()

    print("  ✓ Harness initialized")

    -- Check modules are loaded
    assert(harness.corpus)
    assert(harness.profile_static)
    assert(harness.seed_l0)
    assert(harness.layer_closure)

    print("  ✓ All modules loaded")
    print("  ✓ All harness integration tests passed")
end

-- Run all tests
print("=== JIT Harness Test Suite ===")

local failures = 0
local function run(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        failures = failures + 1
        print("✗ " .. name .. " error: " .. tostring(err))
    end
end

run("fact_trace", test_fact_trace)
run("corpus", test_corpus)
run("compile_static_profile", test_compile_static_profile)
run("candidate_vm_stencil_compile", test_candidate_vm_stencil_compile)
run("seed_l0", test_seed_l0)
run("layer_closure", test_layer_closure)
run("harness", test_harness_integration)

print("\n=== All Tests Complete ===")
if failures > 0 then
    print(string.format("FAILURES: %d", failures))
    os.exit(1)
end
