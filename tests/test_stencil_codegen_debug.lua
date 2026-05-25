#!/usr/bin/env luajit
-- Debug codegen to see what's being generated

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local Builder = require("experiments.lua_interpreter_vm.src.jit.library_builder")
local codegen = require("experiments.lua_interpreter_vm.src.jit.stencil_codegen_production")

local manifest = Builder.read_json("experiments/lua_interpreter_vm/build/stencil_mining/candidate_manifest.json")
local policy = Builder.default_policy {max_depth = 1, max_arity = 4, max_promotions_per_round = 64, max_variants = 2, min_hits = 1, min_benefit = 1}
local evidence = {["*"] = 10}
local plan = Builder.build_promotion_plan(manifest, policy, evidence)

-- Find a problematic candidate
local count = 0
for i, cand in ipairs(plan.library or {}) do
    if cand.kind == "compound_candidate" and cand.replacement and cand.replacement.kind == "code_stencil_needed" then
        count = count + 1
        if count == 1 then
            print("=== First Compound Candidate ===")
            print("Name:", cand.name)
            print("Ops count:", #cand.ops)
            print()

            local func, err = codegen.generate_function(cand)
            if func then
                print("Generated source:")
                print(func.source)
            else
                print("Error:", err)
            end
            break
        end
    end
end
