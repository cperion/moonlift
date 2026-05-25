#!/usr/bin/env luajit
-- Test the populate_physical function

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local fixture_builder = require("experiments.lua_interpreter_vm.src.jit.fixture_builder")
local library_builder = require("experiments.lua_interpreter_vm.src.jit.library_builder")

print("=== Test populate_physical ===")

-- Create a simple test promotion plan
local test_plan = {
    library = {
        {name = "test_cand_1", kind = "compound_candidate", status = "candidate"},
        {name = "test_cand_2", kind = "compound_candidate", status = "candidate"},
    }
}

-- Create test compiled data
local test_compiled = {
    extracted = {
        ["test_cand_1"] = {
            bytes_hex = "55 48 89 e5 48 89 ec 5d c3",
            size = 9,
            holes = {{kind="imm32", offset=5}},
            relocations = {},
        },
        ["test_cand_2"] = {
            bytes_hex = "48 83 ec 08 48 83 c4 08 c3",
            size = 9,
            holes = {},
            relocations = {},
        }
    }
}

local result = fixture_builder.populate_physical(test_plan, test_compiled)

if result then
    print("populate_physical succeeded")
    print("Library size:", #result.library)

    for i, cand in ipairs(result.library) do
        print(string.format("\n[%d] %s", i, cand.name))
        if cand.physical then
            print("  Status:", cand.status)
            print("  Bytes:", cand.physical.bytes_hex)
            print("  Size:", cand.physical.size)
            print("  Holes:", #cand.physical.holes)
        else
            print("  NO PHYSICAL DATA")
        end
    end
else
    print("populate_physical failed")
end

print("\n=== Test passed ===")
