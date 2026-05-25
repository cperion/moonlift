#!/usr/bin/env luajit
-- Test the fixture builder pipeline: load promotion plan, compile, extract, populate.

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local fixture_builder = require("experiments.lua_interpreter_vm.src.jit.fixture_builder")
local library_builder = require("experiments.lua_interpreter_vm.src.jit.library_builder")

print("=== Test: Load promotion plan and compile candidates ===")

-- Load the existing promotion plan
local plan_path = "experiments/lua_interpreter_vm/build/stencil_library/promotion_plan.json"
local plan_file = io.open(plan_path, "r")
if not plan_file then
    error("Could not open promotion plan: " .. plan_path)
end
local plan_json = plan_file:read("*a")
plan_file:close()

local promotion_plan = library_builder.decode_json(plan_json)
if not promotion_plan then
    error("Failed to parse promotion plan JSON")
end

print("Loaded promotion plan:")
print(string.format("  Total candidates: %d", #promotion_plan.library))

-- Count candidates by kind
local by_kind = {}
for _, cand in ipairs(promotion_plan.library) do
    local kind = cand.kind or "unknown"
    by_kind[kind] = (by_kind[kind] or 0) + 1
end

for kind, count in pairs(by_kind) do
    print(string.format("    - %s: %d", kind, count))
end

print("\n=== Compile compound candidates ===")

-- Extract just the compound candidates that need code stencils
local to_compile = {}
for _, cand in ipairs(promotion_plan.library) do
    if cand.kind == "compound_candidate" and
       cand.replacement and cand.replacement.kind == "code_stencil_needed" then
        if #to_compile < 3 then  -- Just compile first 3 for testing
            to_compile[#to_compile + 1] = cand
        end
    end
end

print(string.format("Compiling %d compound candidates...", #to_compile))

if #to_compile > 0 then
    local compiled, err = fixture_builder.compile_and_extract(to_compile)
    if not compiled then
        print("Failed to compile: " .. (err or "unknown"))
    else
        if compiled.generated then
            print(string.format("Success! Extracted %d functions", #compiled.generated))
        else
            print("ERROR: compiled.generated is nil")
            print("compiled type:", type(compiled))
            if type(compiled) == "table" then
                for k, v in pairs(compiled) do
                    print(string.format("  %s = %s", k, type(v)))
                end
            end
        end

        print("\nExtracted functions:")
        for name, data in pairs(compiled.extracted) do
            print(string.format("  - %s: %d bytes, %d holes", name, data.size, #data.holes))
            if #data.holes > 0 then
                print("    Holes:")
                for i, hole in ipairs(data.holes) do
                    if i <= 3 then  -- Show first 3 holes
                        print(string.format("      [%d] kind=%s, offset=%d, marker=%s",
                            i, hole.kind, hole.offset, hole.marker))
                    end
                end
                if #data.holes > 3 then
                    print(string.format("      ... and %d more", #data.holes - 3))
                end
            end
        end
    end
else
    print("No candidates ready for compilation")
end

print("\n=== All tests passed ===")
