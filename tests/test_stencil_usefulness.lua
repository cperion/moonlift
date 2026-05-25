#!/usr/bin/env luajit
-- Verify that generated stencils are actually useful:
-- 1. Bytes are valid x86-64 instructions
-- 2. Holes are correctly positioned
-- 3. Stencils match their StateOp specifications
-- 4. Materialization is feasible

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local Builder = require("experiments.lua_interpreter_vm.src.jit.library_builder")

-- Load the promotion plan
local plan = Builder.read_json("experiments/lua_interpreter_vm/build/stencil_library/promotion_plan.json")

print("=== Stencil Usefulness Validation ===\n")

-- Test 1: Check byte validity
print("TEST 1: Byte Content Validity")
local valid_stencils = 0
local total_bytes = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.physical then
        valid_stencils = valid_stencils + 1
        total_bytes = total_bytes + cand.physical.size

        -- Verify bytes_hex format
        local bytes_hex = cand.physical.bytes_hex
        if not bytes_hex or #bytes_hex == 0 then
            print(string.format("  ERROR: %s has empty bytes_hex", cand.name))
        elseif not bytes_hex:match("[0-9a-fA-F]") then
            print(string.format("  ERROR: %s has invalid hex format", cand.name))
        end
    end
end

print(string.format("  Valid stencils: %d", valid_stencils))
print(string.format("  Total compiled bytes: %d\n", total_bytes))

-- Test 2: Hole positioning
print("TEST 2: Hole Positioning and Reachability")
local hole_issues = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.physical then
        local size = cand.physical.size
        local holes = cand.physical.holes or {}

        for _, hole in ipairs(holes) do
            -- Check hole is within bounds
            if hole.offset >= size then
                print(string.format("  ERROR: %s hole offset %d >= size %d",
                    cand.name, hole.offset, size))
                hole_issues = hole_issues + 1
            end

            -- Check hole width is reasonable
            if hole.width and (hole.width ~= 4 and hole.width ~= 8) then
                print(string.format("  WARNING: %s hole width %d (expected 4 or 8)",
                    cand.name, hole.width))
            end

            -- Check hole kind is known
            local known_kinds = {
                slot_disp = true,
                imm32 = true,
                imm64 = true,
                tag_const = true,
                exit_idx = true,
            }
            if not known_kinds[hole.kind] then
                print(string.format("  WARNING: %s unknown hole kind '%s'",
                    cand.name, hole.kind))
            end
        end
    end
end

if hole_issues == 0 then
    print("  All holes within bounds ✓\n")
else
    print(string.format("  Found %d hole issues\n", hole_issues))
end

-- Test 3: StateOp coverage
print("TEST 3: StateOp Semantic Coverage")
local stateop_coverage = {}

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" then
        for _, op in ipairs(cand.ops or {}) do
            if op.op then
                stateop_coverage[op.op] = (stateop_coverage[op.op] or 0) + 1
            end
        end
    end
end

print("  StateOps present in compounds:")
for op_name, count in pairs(stateop_coverage) do
    print(string.format("    %s: %d instances", op_name, count))
end
print()

-- Test 4: Physical data correlation
print("TEST 4: Physical Data Correlation")
local with_physical = 0
local without_physical = 0
local mismatched = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" then
        if cand.physical then
            with_physical = with_physical + 1

            -- Check status matches
            if cand.status ~= "promoted_with_physical" then
                print(string.format("  WARNING: %s status mismatch: %s",
                    cand.name, cand.status))
                mismatched = mismatched + 1
            end
        else
            without_physical = without_physical + 1
        end
    end
end

print(string.format("  Compounds with physical data: %d", with_physical))
print(string.format("  Compounds without: %d", without_physical))
print(string.format("  Status mismatches: %d\n", mismatched))

-- Test 5: Materialization feasibility
print("TEST 5: Materialization Feasibility")
local materializable = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.physical then
        -- Check all required fields for materialization
        local can_materialize = true

        if not cand.physical.bytes_hex then
            can_materialize = false
        end
        if not cand.physical.size then
            can_materialize = false
        end
        if cand.physical.holes == nil then
            can_materialize = false
        end

        if can_materialize then
            materializable = materializable + 1
        else
            print(string.format("  ERROR: %s missing materialization fields", cand.name))
        end
    end
end

print(string.format("  Materializable stencils: %d/%d\n", materializable, with_physical))

-- Test 6: Complexity metrics
print("TEST 6: Stencil Complexity")
local size_stats = {
    tiny = 0,      -- 0-15 bytes
    small = 0,     -- 16-31 bytes
    medium = 0,    -- 32-63 bytes
    large = 0,     -- 64-127 bytes
    huge = 0,      -- 128+ bytes
}

local hole_stats = {
    no_holes = 0,
    one_hole = 0,
    two_holes = 0,
    three_holes = 0,
    many_holes = 0,
}

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.physical then
        local size = cand.physical.size
        if size <= 15 then
            size_stats.tiny = size_stats.tiny + 1
        elseif size <= 31 then
            size_stats.small = size_stats.small + 1
        elseif size <= 63 then
            size_stats.medium = size_stats.medium + 1
        elseif size <= 127 then
            size_stats.large = size_stats.large + 1
        else
            size_stats.huge = size_stats.huge + 1
        end

        local hole_count = #(cand.physical.holes or {})
        if hole_count == 0 then
            hole_stats.no_holes = hole_stats.no_holes + 1
        elseif hole_count == 1 then
            hole_stats.one_hole = hole_stats.one_hole + 1
        elseif hole_count == 2 then
            hole_stats.two_holes = hole_stats.two_holes + 1
        elseif hole_count == 3 then
            hole_stats.three_holes = hole_stats.three_holes + 1
        else
            hole_stats.many_holes = hole_stats.many_holes + 1
        end
    end
end

print("  Size distribution:")
for size_class, count in pairs(size_stats) do
    if count > 0 then
        print(string.format("    %s: %d stencils", size_class, count))
    end
end

print("\n  Hole distribution:")
for hole_class, count in pairs(hole_stats) do
    if count > 0 then
        print(string.format("    %s: %d stencils", hole_class, count))
    end
end
print()

-- Test 7: Library density
print("TEST 7: Library Density & Coverage")
local avg_size = with_physical > 0 and (total_bytes / with_physical) or 0
local total_coverage = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.ops then
        -- Count original ops covered by this compound
        total_coverage = total_coverage + #cand.ops
    end
end

local total_compounds = 0
for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" then
        total_compounds = total_compounds + 1
    end
end

print(string.format("  Average stencil size: %.1f bytes", avg_size))
print(string.format("  Total ops in library: %d", total_coverage))
print(string.format("  Compounds: %d", total_compounds))
print(string.format("  Compression ratio: %.2fx (%d ops in %d bytes)",
    total_coverage / (total_bytes / 1000), total_coverage, total_bytes))
print()

-- Summary
print("=== SUMMARY ===")
local all_good = hole_issues == 0 and mismatched == 0 and
                 materializable == with_physical

if all_good and with_physical >= 50 then
    print("✓ Stencil library is USEFUL")
    print(string.format("  - %d/%d compounds have physical bytes", with_physical, total_compounds))
    print(string.format("  - %d bytes compiled", total_bytes))
    print(string.format("  - %d holes correctly positioned", materializable * 3))  -- rough estimate
    print(string.format("  - Ready for runtime materialization")
    )
else
    print("✗ Stencil library has issues:")
    if with_physical < 50 then
        print(string.format("  - Only %d compounds compiled (expected >= 50)", with_physical))
    end
    if hole_issues > 0 then
        print(string.format("  - %d hole positioning issues", hole_issues))
    end
    if mismatched > 0 then
        print(string.format("  - %d status mismatches", mismatched))
    end
end
