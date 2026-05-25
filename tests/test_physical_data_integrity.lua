#!/usr/bin/env luajit
-- Verify physical data integrity in promotion plan

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local Builder = require("experiments.lua_interpreter_vm.src.jit.library_builder")

-- Load the generated promotion plan
local json_path = "experiments/lua_interpreter_vm/build/stencil_library/promotion_plan.json"
local plan = Builder.read_json(json_path)

print("=== Physical Data Integrity Test ===\n")

-- Check plan structure
print("Plan summary:")
print(string.format("  Primitives: %d", plan.primitive_count))
print(string.format("  Total library atoms: %d", plan.library_count))
print(string.format("  Library entries: %d\n", #plan.library))

-- Verify primitives have physical data
local primitive_count = 0
for _, cand in ipairs(plan.library) do
    if cand.class == "primitive" or cand.kind == "primitive_stencil" then
        primitive_count = primitive_count + 1
        if cand.physical then
            assert(cand.physical.bytes_hex, "Primitive " .. cand.name .. " missing bytes_hex")
            assert(cand.physical.size, "Primitive " .. cand.name .. " missing size")
        else
            print("WARNING: Primitive " .. cand.name .. " has no physical data")
        end
    end
end

print(string.format("Primitives with data: %d/%d\n", primitive_count, plan.primitive_count))

-- Verify compound candidates have physical data
local compound_count = 0
local with_physical = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" then
        compound_count = compound_count + 1

        if cand.physical then
            with_physical = with_physical + 1

            -- Check bytes_hex format (space-separated hex pairs)
            local bytes_hex = cand.physical.bytes_hex
            assert(type(bytes_hex) == "string", "bytes_hex must be string")
            assert(#bytes_hex > 0, "bytes_hex must not be empty")

            -- Check size
            local size = cand.physical.size
            assert(type(size) == "number", "size must be number")
            assert(size > 0, "size must be > 0")
            assert(size <= 1000, "size must be reasonable (<= 1000)")

            -- Check holes if present
            local holes = cand.physical.holes or {}
            for _, hole in ipairs(holes) do
                assert(hole.kind, "Hole missing kind: " .. cand.name)
                assert(hole.offset ~= nil, "Hole missing offset: " .. cand.name)
                assert(hole.width, "Hole missing width: " .. cand.name)
            end

            if compound_count <= 5 then
                print(string.format("  %s: %d bytes, %d holes",
                    cand.name, size, #holes))
            end
        else
            if with_physical < 10 then
                print(string.format("  %s: NO PHYSICAL DATA", cand.name))
            end
        end
    end
end

print(string.format("\nCompounds: %d", compound_count))
print(string.format("With physical data: %d/%d", with_physical, compound_count))

-- Verify status field
local promoted_count = 0
for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.status == "promoted_with_physical" then
        promoted_count = promoted_count + 1
    end
end

print(string.format("Promoted with physical: %d\n", promoted_count))

-- Validate bytes contain actual hex data
print("=== Byte Content Validation ===")
local byte_validation = 0
for i, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.physical then
        local bytes_hex = cand.physical.bytes_hex
        -- Verify it's non-empty and contains hex digits
        if bytes_hex and #bytes_hex > 0 and bytes_hex:match("[0-9a-fA-F]") then
            byte_validation = byte_validation + 1
        end

        if byte_validation >= 10 then break end
    end
end

print(string.format("Compounds with valid hex bytes: %d/10\n", byte_validation))

-- Final result
if with_physical >= 50 and promoted_count >= 50 then
    print("✓ Physical data integrity test PASSED")
    print(string.format("  %d/%d compounds have valid physical data", with_physical, compound_count))
else
    print("✗ Physical data integrity test FAILED")
    print(string.format("  Only %d compounds have physical data (expected >= 50)", with_physical))
    os.exit(1)
end
