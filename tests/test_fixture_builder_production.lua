#!/usr/bin/env luajit
-- Test of fixture_builder with production codegen

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local fixture_builder = require("experiments.lua_interpreter_vm.src.jit.fixture_builder")

-- Test candidates from promotion plan structure
local test_candidates = {
    {
        name = "test_const",
        id = 1,
        ops = {
            {op = "ConstInt", args = {value = "imm"}},
            {op = "Jump", args = {target = "next"}},
        },
        replacement = {kind = "code_stencil_needed"},
    },
    {
        name = "test_add",
        id = 2,
        ops = {
            {op = "ReadSlot", args = {slot = "lhs"}},
            {op = "ReadSlot", args = {slot = "rhs"}},
            {op = "AddIntWrap", args = {lhs = "lhs", rhs = "rhs"}},
            {op = "Jump", args = {target = "next"}},
        },
        replacement = {kind = "code_stencil_needed"},
    },
}

print("=== Compile and extract ===")
local result, err = fixture_builder.compile_and_extract(test_candidates)
if not result then
    print("ERROR:", err)
    os.exit(1)
end

print("Compilation successful!")

-- Use candidate_map instead (maps sanitized names to data)
local count = 0
for name, data in pairs(result.candidate_map) do
    print(string.format("  Generated: %s (%d bytes)", name, data.size))
    count = count + 1
end
print("Total generated functions:", count)

print("\nExtracted data by name:")
for name, data in pairs(result.extracted) do
    print(string.format("  %s: %d bytes, %d holes", name, data.size, #data.holes))
    if #data.holes > 0 then
        for _, hole in ipairs(data.holes) do
            print(string.format("    - %s at offset %d", hole.kind, hole.offset))
        end
    end
end

print("\n=== Test promotion plan population ===")
local promotion_plan = {
    library = test_candidates
}

local populated, err = fixture_builder.populate_physical(promotion_plan, result)
if not populated then
    print("ERROR:", err)
    os.exit(1)
end

print("Population successful!")
print("Updated candidates:")
for i, cand in ipairs(populated.library) do
    if cand.physical then
        print(string.format("  [%d] %s: %d bytes, %d holes",
            i, cand.name, cand.physical.size, #cand.physical.holes))
    else
        print(string.format("  [%d] %s: NOT POPULATED", i, cand.name))
    end
end

print("\n✓ All tests passed")
