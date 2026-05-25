-- harness.lua
-- Top-level JIT harness command dispatcher
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.1

local M = {}

-- Load harness modules
function M.init()
    M.corpus = require("tools.jit_harness.corpus")
    M.profile_static = require("tools.jit_harness.profile_static")
    M.fact_trace = require("tools.jit_harness.fact_trace")
    M.seed_l0 = require("tools.jit_harness.seed_l0")
    M.layer_closure = require("tools.jit_harness.layer_closure")
end

-- Profile AWFY corpus
function M.profile_awfy(awfy_root, output_dir)
    print("\n=== Harness: Profile AWFY ===")

    -- Step 1: Load AWFY corpus
    local corpus = M.corpus.load_awfy_corpus(awfy_root)
    M.corpus.report_corpus(corpus)

    -- Step 2: Save corpus DB
    if not output_dir then
        output_dir = awfy_root .. "/build/harness_output"
    end
    os.execute("mkdir -p " .. output_dir)

    local corpus_db_path = output_dir .. "/corpus_db.json"
    local ok = M.corpus.write_corpus_db(corpus, corpus_db_path)
    print(string.format("Corpus DB saved to: %s", corpus_db_path))

    return corpus
end

-- Build L0 seed manifest
function M.seed_l0_manifest(corpus, output_dir)
    print("\n=== Harness: Build L0 Seed Manifest ===")

    -- Step 1: Load manual seeds
    local manual_seeds = M.seed_l0.load_manual_l0_seeds({
        manual_priority = 100,
    })
    print(string.format("Manual seeds loaded: %d", #manual_seeds))

    -- Step 2: Derive corpus seeds (would require static profiling in production)
    -- For now, just use manual seeds
    local corpus_seeds = {}

    -- Step 3: Merge
    local manifest = M.seed_l0.build_l0_seed_manifest(manual_seeds, corpus_seeds)
    M.seed_l0.report_l0_seeds(manifest)

    -- Step 4: Validate
    local validation = M.seed_l0.validate_l0_seed_manifest(manifest)
    print(string.format("\nValidation: valid=%s, errors=%d, warnings=%d",
        validation.valid and "true" or "false",
        #validation.errors,
        #validation.warnings))

    -- Step 5: Save manifest
    if not output_dir then
        output_dir = "build/harness_output"
    end
    os.execute("mkdir -p " .. output_dir)

    local manifest_path = output_dir .. "/l0_seed_manifest.json"
    local ok = M.seed_l0.write_l0_seed_manifest(manifest, manifest_path)
    print(string.format("L0 manifest saved to: %s", manifest_path))

    return manifest
end

-- Build L1 layer (closure over L0)
function M.build_l1_layer(l0_manifest, output_dir)
    print("\n=== Harness: Build L1 Layer ===")

    local layer_result = M.layer_closure.build_layer({
        seeds = l0_manifest.seeds,
    }, {
        max_arity = 2,  -- For L1, limit to pairs
        max_candidates = 500,
        budget = {
            max_arity = 2,
            max_opcodes = 8,
            max_size = 300,
            max_holes = 15,
            max_relocs = 10,
        }
    })

    M.layer_closure.report_layer(layer_result)

    if not output_dir then
        output_dir = "build/harness_output"
    end
    os.execute("mkdir -p " .. output_dir)

    -- Save layer manifest
    local layer_path = output_dir .. "/l1_candidates.json"
    -- (Would save here in production)

    return layer_result
end

-- Main command dispatcher
function M.main(argv)
    M.init()

    local command = argv[1] or "help"

    if command == "help" then
        print([[
Lua JIT Harness
Usage: luajit harness.lua <command> [args]

Commands:
  profile-awfy                  Profile AWFY corpus
  seed-l0 <awfy_root>           Build L0 seed manifest
  build-l1 <awfy_root>          Build L1 layer (pairs)
  build-layer <awfy_root> <n>   Build Ln layer
  export-runtime                Export runtime library
  report                        Generate reports
  test                          Run test pipeline
]])
        return 0

    elseif command == "profile-awfy" then
        local awfy_root = argv[2] or "."
        M.profile_awfy(awfy_root)
        return 0

    elseif command == "seed-l0" then
        local awfy_root = argv[2] or "."
        M.seed_l0_manifest(nil, awfy_root .. "/build/harness_output")
        return 0

    elseif command == "build-l1" then
        local awfy_root = argv[2] or "."
        local corpus = M.profile_awfy(awfy_root)
        local manifest = M.seed_l0_manifest(corpus, awfy_root .. "/build/harness_output")
        M.build_l1_layer(manifest, awfy_root .. "/build/harness_output")
        return 0

    elseif command == "test" then
        -- Simple test pipeline
        print("\n=== Running Harness Test Pipeline ===")
        local awfy_root = argv[2] or "."

        print("\nStep 1: Profile AWFY")
        local corpus = M.profile_awfy(awfy_root)

        print("\nStep 2: Build L0 seeds")
        local manifest = M.seed_l0_manifest(corpus, awfy_root .. "/build/harness_output")

        print("\nStep 3: Build L1 candidates")
        local l1 = M.build_l1_layer(manifest, awfy_root .. "/build/harness_output")

        print("\n=== Test Pipeline Complete ===")
        return 0

    else
        print("Unknown command: " .. command)
        return 1
    end
end

return M
