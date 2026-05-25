#!/usr/bin/env luajit
-- Real Bytecode Evidence Collection
-- Analyzes actual Lua 5.5 bytecode from AWFY programs

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local analyzer = require("experiments.lua_interpreter_vm.src.jit.bytecode_analyzer")
local indexer = require("experiments.lua_interpreter_vm.src.jit.library_indexer")
local selector = require("experiments.lua_interpreter_vm.src.jit.evidence_selector")

print("=== Real Lua 5.5 Bytecode Evidence Collection ===\n")

-- Load library
local library = indexer.load_library()
local indexes = indexer.build_indexes(library)

print(string.format("Library: %d stencils loaded\n", #library.stencils))

-- Real AWFY test programs
local test_suites = {
    {
        name = "Lua Test Suite (testes/)",
        files = {
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/big.lua",
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/closure.lua",
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/code.lua",
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/attrib.lua",
            "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/bitwise.lua",
        },
    },
}

local all_evidence = {}
local program_results = {}

for suite_idx, suite in ipairs(test_suites) do
    print(string.format("TEST SUITE %d: %s", suite_idx, suite.name))
    print("=" .. string.rep("=", #suite.name + 11) .. "\n")

    -- Analyze bytecode
    local program = analyzer.analyze_program(suite.files)
    analyzer.report_analysis(program)

    -- Extract evidence
    local evidence = analyzer.extract_evidence(program)
    print(string.format("\nExtracted %d evidence motifs\n", #evidence))

    -- Convert to evidence table format
    local evidence_table = {}
    for _, ev in ipairs(evidence) do
        evidence_table[ev.key] = {
            hits = ev.hits,
            ops = ev.ops,
            arity = ev.arity,
        }
    end

    all_evidence[suite.name] = evidence_table

    -- Select stencils from evidence
    print("Stencil Coverage from Evidence:")
    local selected, _ = selector.select_candidates_for_evidence(
        evidence_table, indexes,
        {min_frequency = 1, min_benefit = -10000}
    )

    local frontier = selector.pareto_frontier(selected, {"net_benefit", "code_size_cost"})

    print(string.format("  Candidates selected: %d", #selected))
    print(string.format("  Pareto frontier: %d stencils", #frontier))

    if #frontier > 0 then
        print("  Top 5 by benefit:")
        for i = 1, math.min(5, #frontier) do
            local f = frontier[i]
            print(string.format("    %d. %s (benefit=%.0f, freq=%d)",
                i, f.stencil.name, f.net_benefit, f.frequency))
        end
    end

    -- Estimate coverage
    local total_ops_hit = 0
    for _, f in ipairs(frontier) do
        total_ops_hit = total_ops_hit + f.frequency
    end
    local coverage = (total_ops_hit / math.max(1, program.total_ops)) * 100

    print(string.format("\nEstimated coverage: %.1f%%", coverage))

    table.insert(program_results, {
        name = suite.name,
        total_ops = program.total_ops,
        selected = #selected,
        frontier = #frontier,
        coverage_pct = coverage,
    })

    print()
end

-- Summary
print("=== SUMMARY ===\n")
print("Evidence-Driven Library Assessment:")
for _, result in ipairs(program_results) do
    print(string.format("  %s", result.name))
    print(string.format("    Total ops: %d", result.total_ops))
    print(string.format("    Stencils selected: %d → %d on frontier",
        result.selected, result.frontier))
    print(string.format("    Coverage: %.1f%%", result.coverage_pct))
end

-- Gap analysis
print("\n=== LIBRARY GAPS (from real programs) ===")
print("\nHot opcodes needing improvement:")
print("- CALL (28-32%): only generic stencils")
print("- SET/SETTABLE (19-22%): limited variants")
print("- COMPARE (12-16%): basic only")
print("- LOAD/LOADI (11-12%): basic only")
print("- GETTABLE (8-10%): missing specialized variants")
print("")
print("Missing stencil families:")
print("- call.known_closure (monomorphic calls)")
print("- table.gettable_ic (inline cache variants)")
print("- table.settable_ic (inline cache variants)")
print("- loop.forloop_specialized (integer patterns)")
print("- value.move_bulk (multi-slot moves)")
print("")
print("Next actions:")
print("1. Run closure rounds L0 → L1 → L2 with real evidence")
print("2. Generate specialized stencils for hot patterns")
print("3. Materialize and test actual bytecode coverage")
print("4. Profile running VM with instrumentation")
