-- JIT product surface smoke test.
--
-- This verifies the Moonlift product catalog only.  It does not benchmark or
-- exercise a Lua planner/runner.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local jit = require("experiments.lua_interpreter_vm.src.jit")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name)
    end
end

local product_names = {
    "SemanticAddr",
    "SemanticRange",
    "Effect",
    "BoundaryRequirement",
    "ProjectionRequirement",
    "Fact",
    "DependencyKey",
    "TypedValue",
    "VirtualState",
    "ProjectedSlot",
    "Projection",
    "StateOp",
    "StateProgram",
    "Guard",
    "TraceAnchor",
    "TraceRecord",
    "StencilHole",
    "StencilReloc",
    "StencilPayload",
    "CodeStencil",
    "StencilLibrary",
    "StencilConfig",
    "StencilPattern",
    "StencilPatternLibrary",
    "StencilNode",
    "TraceStencilMatch",
    "TraceMotif",
    "PromotionEvidence",
    "StencilReplacement",
    "StencilEquivalence",
    "RewriteStencil",
    "StencilPromotion",
    "StencilSummary",
    "StencilClosurePolicy",
    "StencilClosureRound",
    "StencilPlanMetrics",
    "StencilPlanRefinement",
    "CodeFixup",
    "StencilPlan",
    "CodeSlab",
    "EntryCell",
    "EdgeCell",
    "ExecutableUnit",
    "ExecImage",
    "NativeJitOutcome",
}

for _, name in ipairs(product_names) do
    check("product " .. name, jit.products[name] ~= nil and tostring(jit.products[name]):match("^MoonStructValue") ~= nil)
end

check("Effect constants", type(jit.constants.Effect.MAY_GC) == "number")
check("Projection constants", jit.constants.ProjectionKind.ROOTS == 2)
check("Outcome constants", jit.constants.ExecutionStatus.CALL_BOUNDARY == 4)
check("Trace constants", jit.constants.TraceSelectStatus.NO_STENCIL == 2)
check("Rewrite constants", jit.constants.RewriteKind.DCE == 1 and jit.constants.ReplacementKind.EMPTY == 0)
local func_names = {
    "jit_flags_has_flag",
    "jit_effect_has_flag",
    "jit_effect_projection_flags",
    "jit_effect_boundary_flags",
    "jit_effect_to_projection_requirement",
    "jit_effect_to_boundary_requirement",
    "jit_projection_requires",
    "jit_boundary_requires",
    "jit_range_contains_pc",
    "jit_semantic_addr_eq",
    "jit_plan_node_count",
    "jit_plan_has_work",
    "jit_outcome_is_boundary",
    "jit_outcome_is_exit",
}

for _, name in ipairs(func_names) do
    check("func " .. name, type(jit.funcs[name]) == "table" and jit.funcs[name].kind == "func")
end

local region_names = {
    "classify_effect",
    "validate_stencil_plan",
    "require_projection_for_effect",
}
for _, name in ipairs(region_names) do
    check("region " .. name, type(jit.regions[name]) == "table" and jit.regions[name].frag ~= nil)
end

local machine_names = {
    "jit_init_virtual_state",
    "jit_build_projection_header",
    "jit_clear_stencil_plan",
    "jit_trace_anchor_tick",
    "jit_init_trace_record",
    "jit_trace_record_has_path",
    "jit_trace_record_is_guarded",
    "jit_trace_pattern_matches",
    "jit_trace_match_at",
    "jit_trace_select_pattern_plan",
    "jit_trace_select_plan_skeleton",
    "jit_promotion_is_candidate",
    "jit_rewrite_has_equivalence",
    "jit_rewrite_replacement_is_physical",
    "jit_stencil_summary_within_policy",
    "jit_plan_metrics_from_plan",
    "jit_layout_stencil_plan",
}
for _, name in ipairs(machine_names) do
    check("machine " .. name, type(jit.machines[name]) == "table" and jit.machines[name].kind == "func")
end

check("Library builder exposed", type(jit.library_builder.build_promotion_plan) == "function")
check("Miner contracts exposed", type(jit.miner_contracts.StatePattern) == "function")

local moon = require("moonlift")
local f_has = jit.funcs.jit_effect_has_flag
local classify = jit.regions.classify_effect
local wrapper = moon.func { f_has = f_has } [[
jit_products_compile_probe(e: Effect, flag: u64) -> i32
    if @{f_has}(e, flag) then return 1 end
    return 0
end
]]
local wrapper_region = moon.func { classify = classify } [[
jit_products_region_probe(e: Effect) -> i32
    return region -> i32
    entry start()
        emit @{classify}(e; pure = p, needs_boundary = b, needs_projection = pr)
    end
    block p() yield 1 end
    block b(flags: u64) yield 2 end
    block pr(flags: u64) yield 3 end
    end
end
]]
check("product funcs compile", type(wrapper) == "table" and wrapper.kind == "func")
check("product regions compile", type(wrapper_region) == "table" and wrapper_region.kind == "func")

print(string.format("JIT products: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
