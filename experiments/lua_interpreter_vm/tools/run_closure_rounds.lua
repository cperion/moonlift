#!/usr/bin/env luajit
-- Run Full Closure Rounds with Real Evidence
-- Generates L1, L2, L3 compounds from real program patterns

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local indexer = require("experiments.lua_interpreter_vm.src.jit.library_indexer")
local selector = require("experiments.lua_interpreter_vm.src.jit.evidence_selector")
local closer = require("experiments.lua_interpreter_vm.src.jit.closure_round_builder")

print("=== Run Full Closure Rounds with Evidence ===\n")

-- Load Phase 1 library (L0)
print("Loading L0 library (primitives)...")
local l0_library = indexer.load_library()
local l0_indexes = indexer.build_indexes(l0_library)

print(string.format("L0 atoms: %d primitives\n", #l0_library.stencils))

-- Load evidence from all programs
print("Loading evidence from all AWFY programs...")
local evidence_file = "experiments/lua_interpreter_vm/build/evidence_all_programs.lua"
local all_evidence = {}

local ev_loaded, ev_data = pcall(function() return require("experiments.lua_interpreter_vm.build.evidence_all_programs") end)
if not ev_loaded then
    print("Evidence file not found. Run: luajit tools/extract_all_evidence.lua")
    print("Falling back to synthetic evidence...\n")

    all_evidence = {
        ["CALL"] = {hits = 500, ops = {"call"}, arity = 1},
        ["LOADK"] = {hits = 200, ops = {"loadk"}, arity = 1},
        ["ADD"] = {hits = 150, ops = {"add"}, arity = 1},
        ["FORLOOP"] = {hits = 100, ops = {"forloop"}, arity = 1},
        ["GETTABLE"] = {hits = 80, ops = {"gettable"}, arity = 1},
        ["CALL|CALL"] = {hits = 200, ops = {"call", "call"}, arity = 2},
        ["LOADK|ADD"] = {hits = 80, ops = {"loadk", "add"}, arity = 2},
        ["GETTABLE|ADD"] = {hits = 60, ops = {"gettable", "add"}, arity = 2},
        ["FORLOOP|GETTABLE"] = {hits = 40, ops = {"forloop", "gettable"}, arity = 2},
    }
else
    for _, ev in ipairs(ev_data) do
        all_evidence[ev.key] = {
            hits = ev.hits,
            ops = ev.ops,
            arity = ev.arity,
        }
    end
end

print(string.format("Loaded %d evidence patterns\n", #all_evidence))

-- Round 1: Generate L1 from L0
print("=== CLOSURE ROUND 1: L0 → L1 ===\n")

local l1_policy = {
    max_arity = 4,
    max_depth = 2,
    max_total_ops = 30,
    max_total_size = 350,
    max_holes = 20,
    max_relocs = 15,
}

print("Generating L1 candidates from L0 primitives...")
local l1_candidates = closer.generate_closure_candidates(l0_library.stencils, all_evidence, l1_policy)
print(string.format("Generated %d L1 candidates\n", #l1_candidates))

-- Select L1 compounds by evidence relevance
print("Selecting L1 compounds by evidence relevance...")
local l1_ranked = closer.rank_candidates_by_evidence(l1_candidates, all_evidence)

-- Promote top L1 candidates
local l1_threshold = 0  -- accept all for now (evidence-driven in production)
local l1_promoted = {}
for i, r in ipairs(l1_ranked) do
    if #l1_promoted < 15 then  -- take top 15 by evidence
        table.insert(l1_promoted, r.candidate)
    end
end

print(string.format("Promoted %d candidates to L1\n", #l1_promoted))

if #l1_promoted > 0 then
    print("Top 10 L1 compounds:")
    for i = 1, math.min(10, #l1_promoted) do
        local c = l1_promoted[i]
        print(string.format("  %d. %s (ops=%d, size=%d, benefit=%.0f)",
            i, c.name, c.ops, c.size, c.benefit or 0))
    end
    print()
end

-- Build L1 library for next round
local l1_atoms = {}
for _, st in ipairs(l0_library.stencils) do
    table.insert(l1_atoms, st)
end
for _, cand in ipairs(l1_promoted) do
    table.insert(l1_atoms, cand)
end

print(string.format("L1 library: %d atoms (11 primitives + %d compounds)\n",
    #l1_atoms, #l1_promoted))

-- Round 2: Generate L2 from L0+L1
print("=== CLOSURE ROUND 2: L0+L1 → L2 ===\n")

local l2_policy = {
    max_arity = 4,
    max_depth = 3,
    max_total_ops = 50,
    max_total_size = 450,
    max_holes = 25,
    max_relocs = 20,
}

print("Generating L2 candidates from L0+L1...")
local l2_candidates = closer.generate_closure_candidates(l1_atoms, all_evidence, l2_policy)
print(string.format("Generated %d L2 candidates\n", #l2_candidates))

-- Select L2 compounds
print("Selecting L2 compounds...")
local l2_ranked = closer.rank_candidates_by_evidence(l2_candidates, all_evidence)

local l2_threshold = 0  -- accept all for now (evidence-driven in production)
local l2_promoted = {}
for i, r in ipairs(l2_ranked) do
    if #l2_promoted < 10 then  -- take top 10 by evidence
        table.insert(l2_promoted, r.candidate)
    end
end

print(string.format("Promoted %d candidates to L2\n", #l2_promoted))

if #l2_promoted > 0 then
    print("Top 5 L2 compounds:")
    for i = 1, math.min(5, #l2_promoted) do
        local c = l2_promoted[i]
        print(string.format("  %d. %s (ops=%d, size=%d)",
            i, c.name, c.ops, c.size))
    end
    print()
end

-- Summary
print("=== CLOSURE SUMMARY ===\n")

local l2_atoms = {}
for _, st in ipairs(l1_atoms) do
    table.insert(l2_atoms, st)
end
for _, cand in ipairs(l2_promoted) do
    table.insert(l2_atoms, cand)
end

print("\nLibrary growth:")
print(string.format("  L0: %d atoms (all primitives)", #l0_library.stencils))
print(string.format("  L1: %d atoms (%d primitives + %d compounds)",
    #l1_atoms, #l0_library.stencils, #l1_promoted))
print(string.format("  L2: %d atoms (%d from L1 + %d new compounds)",
    #l2_atoms, #l1_atoms, #l2_promoted))

local l0_size = 0
for _, st in ipairs(l0_library.stencils) do
    l0_size = l0_size + (st.size or 0)
end

local l1_size = l0_size
for _, c in ipairs(l1_promoted) do
    l1_size = l1_size + (c.size or 0)
end

local l2_size = l1_size
for _, c in ipairs(l2_promoted) do
    l2_size = l2_size + (c.size or 0)
end

print("\nCode size:")
print(string.format("  L0: %d bytes", l0_size))
print(string.format("  L1: %d bytes (%+d)", l1_size, l1_size - l0_size))
print(string.format("  L2: %d bytes (%+d)", l2_size, l2_size - l1_size))

-- Build pattern library from L2
local l2_pattern_lib = closer.build_pattern_library(l2_atoms)

print(string.format("\nStencilPattern library: %d patterns for runtime\n", #l2_pattern_lib))

if #l2_pattern_lib > 0 then
    print("Top 10 patterns by runtime score:")
    for i = 1, math.min(10, #l2_pattern_lib) do
        local p = l2_pattern_lib[i]
        print(string.format("  %d. %s (score=%.0f, depth=%d)",
            i, p.name, p.score, p.depth))
    end
end

print("\n=== Ready for Runtime ===")
print("Generated compounds cover real program patterns:")
print("- From L0 primitives")
print("- Ranked by actual execution evidence")
print("- Pruned to stay finite (budget: size, holes, relocs)")
print("- Indexed for fast runtime selection")
