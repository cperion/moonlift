#!/usr/bin/env luajit
-- test_sponjit_shadow.lua
-- Smoke tests for the non-executing SponJIT shadow simulator.

local source = debug.getinfo(1, "S").source
local base = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*)/tests/test_sponjit_shadow%.lua$") or "."
package.path = base .. "/?.lua;" .. base .. "/?/init.lua;" .. base .. "/../../?.lua;" .. base .. "/../../?/init.lua;" .. base .. "/../../lua/?.lua;" .. base .. "/../../lua/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Workloads = require("tools.sponjit_shadow.workloads")
local Loader = require("tools.sponjit_shadow.loader")
local Sim = require("tools.sponjit_shadow.simulate")
local TimeSeries = require("tools.sponjit_shadow.timeseries")
local Foundry = require("tools.sponjit_shadow.foundry")
local FoundrySSA = require("tools.sponjit_shadow.foundry_ssa")
local FoundryEnum = require("tools.sponjit_shadow.foundry_enumerate")
local Tiler = require("tools.sponjit_shadow.tiler")

local function has_unit(units, id)
    for _, u in ipairs(units or {}) do if u.id == id then return true end end
    return false
end

local function test_arithmetic_return_oracle()
    local w = Workloads.get("arithmetic_return")
    local o = Sim.oracle(w.events, { crossing_cost = 55 })
    assert(has_unit(o.plan.units, "ADD_i64_RETURN1"), "oracle should pick ADD_i64_RETURN1")
    assert(o.cost.total < o.residual_cost.total, "oracle should beat all-residual")
    print("  ✓ arithmetic return oracle absorbs fused tile")
end

local function test_method_dispatch()
    local r = Sim.simulate(Workloads.get("method_dispatch_loop"), { max_window = 3, max_generations = 4 })
    local ids = table.concat(Sim.unit_ids(r.final_plan.units), "|")
    assert(ids:find("GETFIELD_shape_CALL_known", 1, true) or (ids:find("GETFIELD_shape_known_call", 1, true) and ids:find("CALL_known_boundary", 1, true)), "method dispatch should absorb shape/call")
    assert(Sim.plan_summary(r.final_plan).absorption_density > 0.5, "method dispatch should mostly absorb")
    print("  ✓ method dispatch absorbs shape/call path")
end

local function test_mixed_plan_residual()
    local r = Sim.simulate(Workloads.get("polymorphic_phase"), { max_window = 3, max_generations = 4, crossing_cost = 55 })
    local s = Sim.plan_summary(r.final_plan)
    assert(s.absorption_density > 0, "should absorb some work")
    assert(s.residual_ops > 0, "unstable GETTABLE should remain residual in this fixture")
    print("  ✓ polymorphic fixture produces mixed native/residual plan")
end

local function test_suite_all()
    for _, name in ipairs(Workloads.names()) do
        local r = Sim.simulate(Workloads.get(name), { max_window = 4, max_generations = 5 })
        assert(r.final_cost.total > 0)
        assert(r.oracle.cost.total > 0)
    end
    print("  ✓ suite workloads simulate")
end

local function test_profile_loader()
    local profile = {
        window_counts = {
            ["ADD|RETURN1"] = 100,
            ["GETFIELD|CALL"] = 80,
        }
    }
    local workloads = Loader.workloads_from_profile(profile, { max_regions = 4, fact_mode = "balanced" })
    assert(#workloads >= 2)
    local r = Sim.simulate(workloads[1], { max_window = 4, max_generations = 4 })
    assert(r.final_cost.total > 0)
    print("  ✓ profile loader creates shadow workloads")
end

local function test_timeseries()
    local r = TimeSeries.simulate(Workloads.get("phase_changing_method"), { observe_fraction = 0.1, max_window = 4, max_generations = 4 })
    assert(r.totals.online_cost > 0)
    assert(r.totals.oracle_cost > 0)
    assert(r.totals.cache_hits >= 1, "repeated phase should hit mode cache")
    print("  ✓ time-series mode cache simulation")
end

local function test_foundry_normal_form()
    local hash, nf, ssa = Foundry.normal_form_hash({ "SELF", "MOVE", "CALL" }, { "table", "shape_known", "metatable_absent", "key_const", "known_call_target" })
    assert(hash and #hash > 0)
    assert(table.concat(nf, "|") == "SELF_CALL")
    assert(ssa.stats.removed >= 1, "SSA should forward the MOVE")
    local facts = { "table", "shape_known", "metatable_absent", "key_const", "lhs_i64", "barrier_clean" }
    local producers = Foundry.producers_for_candidate({ ops = { "GETFIELD", "ADDI", "SETFIELD" }, fact_axes = facts })
    assert(#producers == 2)
    assert(producers[2].kind == "ssa_normalized")
    assert(table.concat(producers[2].normal_form, "|") == "FIELD_ADDI_UPDATE")
    print("  ✓ foundry SSA-normal-form scaffold")
end

local function test_foundry_ssa_engine()
    local r = FoundrySSA.compile({ "LOADI", "MOVE", "RETURN1" }, { "returns_prev" })
    assert(r.ok)
    assert(table.concat(r.normal_form, "|") == "LOADI_DIRECT|RETURN1")
    assert(r.stats.removed >= 1, "copy forwarding should remove MOVE")
    local f = FoundrySSA.compile({ "GETFIELD", "ADDI", "SETFIELD" }, { "table", "shape_known", "metatable_absent", "key_const", "lhs_i64", "barrier_clean" })
    assert(f.ok)
    assert(table.concat(f.normal_form, "|") == "FIELD_ADDI_UPDATE")
    assert(#f.checked_facts >= 3, "guards should consume facts")
    assert(#f.deps >= 1, "shape/metatable facts should create dependencies")
    print("  ✓ foundry SSA engine consumes facts")
end

local function test_foundry_enumerates_fact_combinations()
    local result = FoundryEnum.enumerate({ Workloads.arithmetic_return(), Workloads.method_dispatch_loop() }, {
        max_arity = 4,
        max_windows = 12,
        max_fact_combos = 256,
    })
    assert((result.stats.compiles or 0) > 0)
    assert((result.stats.unique_forms or 0) > 0)
    local saw_self_call = false
    for _, f in ipairs(result.forms or {}) do
        if table.concat(f.normal_form or {}, "|") == "GETFIELD|CALL" or table.concat(f.normal_form or {}, "|") == "SELF_CALL" then
            saw_self_call = true
            break
        end
    end
    assert(#result.forms > 0 and (result.forms[1].normal_form or result.forms[1].ops), "should produce ranked SSA forms")
    print("  ✓ foundry enumerates tuple × fact SSA forms")
end

local tests = {
    test_arithmetic_return_oracle,
    test_method_dispatch,
    test_mixed_plan_residual,
    test_suite_all,
    test_profile_loader,
    test_timeseries,
    test_foundry_normal_form,
    test_foundry_ssa_engine,
    test_foundry_enumerates_fact_combinations,
}

for _, t in ipairs(tests) do t() end
print("\nSponJIT shadow tests passed")
