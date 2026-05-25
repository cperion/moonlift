-- seed_l0.lua
-- Builds the L0 seed manifest
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.8

local M = {}

-- Manual L0 seed templates
-- These are examples of obviously useful stencil families to seed L0 with
M.MANUAL_SEEDS = {
    -- Value operations
    {name = "LOADI_direct", arities = {1}},
    {name = "LOADK_direct", arities = {1}},
    {name = "MOVE_direct", arities = {1}},

    -- Arithmetic
    {name = "ADD_i64_known", arities = {2}},
    {name = "ADD_i64_guarded", arities = {2, 3}},
    {name = "SUB_i64_known", arities = {2}},
    {name = "MUL_i64_known", arities = {2}},
    {name = "DIV_i64_known", arities = {2}},

    -- Comparisons
    {name = "EQ_i64", arities = {2}},
    {name = "LT_i64", arities = {2}},
    {name = "LE_i64", arities = {2}},
    {name = "COMPARE_BRANCH_i64", arities = {2, 3}},

    -- Control flow
    {name = "TEST_JMP_truthy", arities = {2}},
    {name = "JMP_direct", arities = {1}},

    -- Loops
    {name = "FORLOOP_i64", arities = {1, 2}},
    {name = "FORPREP_i64", arities = {1, 2}},

    -- Tables
    {name = "GETTABLE_generic", arities = {2}},
    {name = "SETTABLE_generic", arities = {2}},
    {name = "GETFIELD_string_key", arities = {2}},
    {name = "SETFIELD_string_key", arities = {2}},

    -- Calls
    {name = "CALL_generic", arities = {1, 2}},
    {name = "CALL_CALL_compound", arities = {2}},

    -- Returns
    {name = "RETURN1_from_slot", arities = {1}},
    {name = "RETURN_varargs", arities = {1, 2}},

    -- Projections
    {name = "PROJECT_slots_1", arities = {1}},
    {name = "PROJECT_slots_2", arities = {2}},
    {name = "PROJECT_slots_3", arities = {3}},
}

-- Load manual L0 seeds from configuration
function M.load_manual_l0_seeds(config)
    config = config or {}

    local seeds = {}

    for _, seed_spec in ipairs(M.MANUAL_SEEDS) do
        if not config.exclude or not config.exclude[seed_spec.name] then
            table.insert(seeds, {
                id = seed_spec.name,
                name = seed_spec.name,
                arities = seed_spec.arities,
                source = "manual",
                priority = config.manual_priority or 100,
            })
        end
    end

    return seeds
end

-- Derive L0 seeds from corpus profile
function M.derive_corpus_l0_seeds(profile, config)
    config = config or {}
    config.min_frequency = config.min_frequency or 2
    config.max_seeds = config.max_seeds or 50

    local seeds = {}
    local seed_map = {}

    -- Extract frequent opcode windows as seed candidates
    if profile.window_counts then
        local sorted_windows = {}

        for window_key, count in pairs(profile.window_counts) do
            if count >= config.min_frequency then
                table.insert(sorted_windows, {key = window_key, count = count})
            end
        end

        table.sort(sorted_windows, function(a, b) return a.count > b.count end)

        -- Take top N windows as seeds
        for i = 1, math.min(config.max_seeds, #sorted_windows) do
            local w = sorted_windows[i]
            local ops = {}
            for op in string.gmatch(w.key, "[^|]+") do
                table.insert(ops, op)
            end

            local seed_id = "corpus_" .. w.key
            if not seed_map[seed_id] then
                table.insert(seeds, {
                    id = seed_id,
                    name = seed_id,
                    ops = ops,
                    arity = #ops,
                    frequency = w.count,
                    source = "corpus",
                    priority = math.floor(100 * w.count / sorted_windows[1].count),
                })
                seed_map[seed_id] = true
            end
        end
    end

    return seeds
end

-- Merge manual and corpus-derived seeds
function M.merge_l0_seeds(manual_seeds, corpus_seeds)
    local merged = {}
    local seen = {}

    -- Add manual seeds first (higher priority)
    for _, seed in ipairs(manual_seeds) do
        table.insert(merged, seed)
        seen[seed.id] = true
    end

    -- Add corpus seeds that don't conflict
    for _, seed in ipairs(corpus_seeds) do
        if not seen[seed.id] then
            table.insert(merged, seed)
            seen[seed.id] = true
        end
    end

    -- Sort by priority descending
    table.sort(merged, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.id < b.id
    end)

    return merged
end

-- Build L0 seed manifest
function M.build_l0_seed_manifest(manual_seeds, corpus_seeds, config)
    config = config or {}

    local manifest = {
        timestamp = os.time(),
        manual_seed_count = #manual_seeds,
        corpus_seed_count = #corpus_seeds,
        seeds = M.merge_l0_seeds(manual_seeds, corpus_seeds),
        config = {
            manual_priority = config.manual_priority or 100,
            min_frequency = config.min_frequency or 2,
            max_corpus_seeds = config.max_corpus_seeds or 50,
        },
    }

    return manifest
end

-- Validate L0 seed manifest
function M.validate_l0_seed_manifest(manifest)
    local report = {
        total_seeds = #manifest.seeds,
        manual_seeds = manifest.manual_seed_count,
        corpus_seeds = manifest.corpus_seed_count,
        errors = {},
        warnings = {},
    }

    -- Check for duplicates
    local seen = {}
    for _, seed in ipairs(manifest.seeds) do
        if seen[seed.id] then
            table.insert(report.warnings, string.format("Duplicate seed: %s", seed.id))
        end
        seen[seed.id] = true
    end

    -- Check arity is reasonable
    for _, seed in ipairs(manifest.seeds) do
        local arity = seed.arity or (#(seed.arities or {}) > 0 and math.max(unpack(seed.arities)) or 1)
        if arity < 1 or arity > 4 then
            table.insert(report.errors, string.format("Invalid arity for %s: %d", seed.id, arity))
        end
    end

    report.valid = #report.errors == 0

    return report
end

-- Write L0 seed manifest
function M.write_l0_seed_manifest(manifest, output_path)
    -- Simple JSON-like output
    local json_str = "{\n"
    json_str = json_str .. '  "timestamp": ' .. manifest.timestamp .. ",\n"
    json_str = json_str .. '  "seed_count": ' .. #manifest.seeds .. ",\n"
    json_str = json_str .. '  "manual": ' .. manifest.manual_seed_count .. ",\n"
    json_str = json_str .. '  "corpus": ' .. manifest.corpus_seed_count .. ",\n"
    json_str = json_str .. '  "seeds": [\n'

    for i, seed in ipairs(manifest.seeds) do
        json_str = json_str .. '    {\n'
        json_str = json_str .. '      "id": "' .. seed.id .. '",\n'
        json_str = json_str .. '      "name": "' .. seed.name .. '",\n'
        json_str = json_str .. '      "arity": ' .. (seed.arity or 1) .. ",\n"
        json_str = json_str .. '      "source": "' .. (seed.source or "unknown") .. '",\n'
        json_str = json_str .. '      "priority": ' .. (seed.priority or 0) .. '\n'
        json_str = json_str .. '    }' .. (i < #manifest.seeds and "," or "") .. '\n'
    end

    json_str = json_str .. '  ]\n'
    json_str = json_str .. '}\n'

    local f = io.open(output_path, "w")
    if not f then
        return false, "cannot write to " .. output_path
    end

    f:write(json_str)
    f:close()
    return true
end

-- Report L0 seeds
function M.report_l0_seeds(manifest)
    print("\n=== L0 Seed Manifest ===")
    print(string.format("Total seeds: %d", #manifest.seeds))
    print(string.format("Manual seeds: %d", manifest.manual_seed_count))
    print(string.format("Corpus-derived seeds: %d", manifest.corpus_seed_count))

    print("\n  Top 20 seeds by priority:")
    for i = 1, math.min(20, #manifest.seeds) do
        local seed = manifest.seeds[i]
        print(string.format("    %2d. %s (source=%s, priority=%d)",
            i, seed.name, seed.source or "unknown", seed.priority or 0))
    end
end

return M
