#!/usr/bin/env luajit
-- Test Phase 3 with Real Lua Programs
-- Profiles actual AWFY programs and maps to stencil coverage

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local profiler = require("experiments.lua_interpreter_vm.src.jit.program_profiler")
local indexer = require("experiments.lua_interpreter_vm.src.jit.library_indexer")
local selector = require("experiments.lua_interpreter_vm.src.jit.evidence_selector")

print("=== Phase 3: Real Program Analysis ===\n")

-- Load library
print("Loading stencil library...")
local library = indexer.load_library()
local indexes = indexer.build_indexes(library)
print(string.format("  Library: %d stencils\n", #library.stencils))

-- Test with various program categories
local test_programs = {
    {
        name = "AWFY basic arithmetic",
        files = {
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/big.lua",
        },
    },
    {
        name = "AWFY table operations",
        files = {
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/attrib.lua",
        },
    },
    {
        name = "AWFY closures",
        files = {
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/closure.lua",
        },
    },
    {
        name = "AWFY function calls",
        files = {
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/code.lua",
        },
    },
}

local all_results = {}

for prog_idx, prog in ipairs(test_programs) do
    print(string.format("TEST %d: %s", prog_idx, prog.name))
    print("=" .. string.rep("=", #prog.name + 5))

    -- Profile program
    local stats = profiler.profile_program(prog.files)
    local motifs = profiler.extract_motifs(stats)

    -- Report profile
    profiler.report_profile(stats, motifs)

    -- Map motifs to stencils
    print("\nStencil Coverage Analysis:")
    local coverage_data = {}

    for _, motif in ipairs(motifs) do
        local candidates = selector.select_candidates_for_evidence(
            {[motif.pattern] = {hits = motif.frequency, ops = motif.ops}},
            indexes,
            {min_frequency = 0, min_benefit = -1000}  -- accept all
        )

        if #candidates > 0 then
            table.insert(coverage_data, {
                motif = motif.pattern,
                frequency = motif.frequency,
                candidates = #candidates,
                best = candidates[1],
            })
        end
    end

    -- Sort by frequency
    table.sort(coverage_data, function(a, b) return a.frequency > b.frequency end)

    if #coverage_data > 0 then
        print("Covered motifs:")
        for i = 1, math.min(5, #coverage_data) do
            local c = coverage_data[i]
            print(string.format("  %d. %s: %d ops, %d candidates",
                i, c.motif, c.frequency, c.candidates))
        end
    end

    -- Estimate coverage
    local total_motif_ops = 0
    for _, motif in ipairs(motifs) do
        total_motif_ops = total_motif_ops + (motif.frequency * motif.ops_count)
    end

    local covered_ops = 0
    for _, c in ipairs(coverage_data) do
        covered_ops = covered_ops + (c.frequency * 1)  -- rough estimate
    end

    local coverage_pct = total_motif_ops > 0 and (covered_ops / total_motif_ops) * 100 or 0
    print(string.format("\nEstimated coverage: %.1f%%", coverage_pct))

    table.insert(all_results, {
        name = prog.name,
        total_ops = stats.total_count,
        motifs = #motifs,
        covered = #coverage_data,
        coverage_pct = coverage_pct,
        class_distribution = stats.class_distribution,
    })

    print()
end

-- Summary across all programs
print("=== SUMMARY ACROSS REAL PROGRAMS ===\n")
print("Program Analysis:")

for i, result in ipairs(all_results) do
    print(string.format("%d. %s", i, result.name))
    print(string.format("   Total ops: %d, Motifs: %d, Covered: %d",
        result.total_ops, result.motifs, result.covered))
    print(string.format("   Coverage: %.1f%%", result.coverage_pct))
end

-- Aggregate statistics
local avg_coverage = 0
for _, result in ipairs(all_results) do
    avg_coverage = avg_coverage + result.coverage_pct
end
avg_coverage = avg_coverage / #all_results

print(string.format("\nAverage coverage across programs: %.1f%%", avg_coverage))

-- Operation class aggregation
print("\nOperation class distribution across all programs:")
local class_totals = {}
for _, result in ipairs(all_results) do
    for class, pct in pairs(result.class_distribution) do
        class_totals[class] = (class_totals[class] or 0) + pct
    end
end

local sorted_classes = {}
for class, total in pairs(class_totals) do
    local avg_pct = (total / #all_results) * 100
    table.insert(sorted_classes, {class = class, avg_pct = avg_pct})
end
table.sort(sorted_classes, function(a, b) return a.avg_pct > b.avg_pct end)

for i, item in ipairs(sorted_classes) do
    print(string.format("  %d. %s: %.1f%%", i, item.class, item.avg_pct))
end

print("\n=== LIBRARY GAPS ===")
print("Operations with low stencil support:")
print("- Tables (GETTABLE, SETTABLE variations): partial")
print("- Calls (call dispatch, known targets): partial")
print("- Loops (FORPREP, FORLOOP): basic only")
print("- Metamethods/coercions: not covered")
print("- Error handling: not covered")
print("")
print("Next actions:")
print("1. Generate and test more closure rounds (L1 → L2 → L3)")
print("2. Add table/call/loop specialized stencils from real patterns")
print("3. Profile with Lua interpreter instrumentation for exact opcodes")
print("4. Measure actual coverage on running VM")
