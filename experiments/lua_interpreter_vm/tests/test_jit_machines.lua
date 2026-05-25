-- Runtime checks for real Moonlift JIT product machines.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local jit = require("experiments.lua_interpreter_vm.src.jit")
local C = jit.constants
local M = jit.machines

ffi.cdef [[
typedef struct TestJitSemanticAddr { void* proto; intptr_t pc; uint32_t frame; } TestJitSemanticAddr;
typedef struct TestJitEffect { uint64_t flags; } TestJitEffect;
typedef struct TestJitStencilConfig { uint16_t kind; uint16_t op; uint16_t value_type; uint8_t lhs_loc; uint8_t rhs_loc; uint8_t out_loc; uint64_t passthrough_mask; uint32_t pattern_id; } TestJitStencilConfig;
typedef struct TestJitCodeStencil { uint8_t kind; uint16_t op; TestJitEffect effect; uint8_t* bytes; intptr_t size; void* holes; intptr_t hole_count; void* relocs; intptr_t reloc_count; void* payloads; intptr_t payload_count; uint8_t abi; uint64_t clobbers; } TestJitCodeStencil;
typedef struct TestJitStencilPattern { uint32_t id; uint16_t* ops; intptr_t op_count; uint64_t required_effects; uint64_t forbidden_effects; TestJitCodeStencil* stencil; uint32_t score; uint32_t flags; } TestJitStencilPattern;
typedef struct TestJitStencilPatternLibrary { TestJitStencilPattern* patterns; intptr_t pattern_count; uint64_t generation; } TestJitStencilPatternLibrary;
typedef struct TestJitStencilNode { TestJitCodeStencil* stencil; TestJitStencilConfig config; uint32_t next; uint32_t alt; uint32_t label; uint32_t boundary_id; uint32_t projection_id; } TestJitStencilNode;
typedef struct TestJitStencilPlan { TestJitStencilNode* nodes; intptr_t node_count; void* fixups; intptr_t fixup_count; void* projections; intptr_t projection_count; intptr_t estimated_size; } TestJitStencilPlan;
typedef struct TestJitProjection { uint32_t id; uint8_t kind; TestJitSemanticAddr addr; uint32_t frame; intptr_t base; intptr_t top; void* slots; intptr_t slot_count; uint32_t* roots; intptr_t root_count; uint64_t flags; } TestJitProjection;
typedef struct TestJitTypedValue { uint32_t id; uint8_t kind; uint32_t type_tag; uint64_t payload0; uint64_t payload1; uint16_t op; uint32_t lhs; uint32_t rhs; } TestJitTypedValue;
typedef struct TestJitFact { uint16_t kind; uint32_t value; uint64_t aux0; uint64_t aux1; } TestJitFact;
typedef struct TestJitDependencyKey { uint16_t kind; uint8_t* ptr0; uint64_t aux0; uint64_t generation; } TestJitDependencyKey;
typedef struct TestJitVirtualState { TestJitSemanticAddr addr; uint32_t frame; intptr_t base; intptr_t top; uint32_t* slot_values; intptr_t slot_count; TestJitTypedValue* values; intptr_t value_count; TestJitFact* facts; intptr_t fact_count; TestJitDependencyKey* deps; intptr_t dep_count; } TestJitVirtualState;
typedef struct TestJitGuard { uint16_t kind; uint32_t value_id; uint32_t dep_index; uint32_t projection_id; uint32_t flags; uint64_t aux0; uint64_t aux1; } TestJitGuard;
typedef struct TestJitStateOp { uint16_t kind; uint16_t op; uint32_t a; uint32_t b; uint32_t c; uint64_t aux0; uint64_t aux1; TestJitEffect effect; } TestJitStateOp;
typedef struct TestJitTraceAnchor { TestJitSemanticAddr addr; uint8_t kind; uint8_t status; uint32_t counter; uint32_t blacklist; uint64_t generation; } TestJitTraceAnchor;
typedef struct TestJitTraceRecord { TestJitTraceAnchor anchor; TestJitStateOp* ops; intptr_t op_count; TestJitGuard* guards; intptr_t guard_count; TestJitProjection* snapshots; intptr_t snapshot_count; TestJitDependencyKey* deps; intptr_t dep_count; uint32_t flags; } TestJitTraceRecord;
typedef struct TestJitTraceStencilMatch { intptr_t start; intptr_t covered_ops; TestJitCodeStencil* stencil; TestJitStencilConfig config; uint32_t score; uint32_t flags; } TestJitTraceStencilMatch;
typedef struct TestJitPromotionEvidence { uint32_t motif_id; uint64_t hits; uint64_t total_ops; uint64_t guard_successes; uint64_t exits; int64_t byte_savings; int64_t ns_savings; uint32_t confidence; } TestJitPromotionEvidence;
typedef struct TestJitStencilReplacement { uint8_t kind; TestJitCodeStencil* stencil; TestJitStencilNode* nodes; intptr_t node_count; uint32_t flags; } TestJitStencilReplacement;
typedef struct TestJitStencilEquivalence { uint32_t contract_id; uint64_t input_hash; uint64_t output_hash; uint64_t effect_flags; uint64_t projection_flags; } TestJitStencilEquivalence;
typedef struct TestJitRewriteStencil { uint32_t id; uint8_t kind; TestJitStencilPattern* pattern; TestJitFact* required_facts; intptr_t required_fact_count; uint64_t forbidden_effects; TestJitStencilReplacement replacement; TestJitStencilEquivalence equivalence; uint32_t flags; } TestJitRewriteStencil;
typedef struct TestJitStencilSummary { intptr_t covered_ops; uint8_t closure_depth; uint8_t max_arity; uint64_t effect_flags; uint64_t projection_flags; intptr_t dep_count; uint32_t exit_count; intptr_t hole_count; intptr_t code_size; int64_t cost_score; } TestJitStencilSummary;
typedef struct TestJitStencilClosurePolicy { uint8_t max_arity; uint8_t max_depth; intptr_t max_covered_ops; intptr_t max_code_size; intptr_t max_holes; uint32_t max_exits; uint32_t max_variants; } TestJitStencilClosurePolicy;
typedef struct TestJitStencilPlanMetrics { intptr_t node_count; intptr_t covered_ops; uint8_t max_depth; uint32_t granularity_score; intptr_t estimated_size; } TestJitStencilPlanMetrics;
]]

local clear = assert(M.jit_clear_stencil_plan:compile())
local layout = assert(M.jit_layout_stencil_plan:compile())
local build_projection = assert(M.jit_build_projection_header:compile())
local init_state = assert(M.jit_init_virtual_state:compile())
local trace_tick = assert(M.jit_trace_anchor_tick:compile())
local init_trace = assert(M.jit_init_trace_record:compile())
local trace_has_path = assert(M.jit_trace_record_has_path:compile())
local trace_is_guarded = assert(M.jit_trace_record_is_guarded:compile())
local pattern_matches = assert(M.jit_trace_pattern_matches:compile())
local match_at = assert(M.jit_trace_match_at:compile())
local select_patterns = assert(M.jit_trace_select_pattern_plan:compile())
local trace_select = assert(M.jit_trace_select_plan_skeleton:compile())
local promotion_candidate = assert(M.jit_promotion_is_candidate:compile())
local rewrite_has_equivalence = assert(M.jit_rewrite_has_equivalence:compile())
local rewrite_replacement_physical = assert(M.jit_rewrite_replacement_is_physical:compile())
local summary_within_policy = assert(M.jit_stencil_summary_within_policy:compile())
local plan_metrics = assert(M.jit_plan_metrics_from_plan:compile())

local plan = ffi.new("TestJitStencilPlan[1]")
assert(clear(plan) == true)
assert(plan[0].node_count == 0 and plan[0].estimated_size == 0)

local stencils = ffi.new("TestJitCodeStencil[2]")
stencils[0].size = 11
stencils[1].size = 31
local nodes = ffi.new("TestJitStencilNode[3]")
nodes[0].stencil = stencils + 0
nodes[1].stencil = nil
nodes[2].stencil = stencils + 1
plan[0].nodes = nodes
plan[0].node_count = 3
assert(layout(plan) == 42)
assert(plan[0].estimated_size == 42)

local addr = ffi.new("TestJitSemanticAddr[1]")
addr[0].proto = ffi.cast("void*", 0x1234)
addr[0].pc = 17
addr[0].frame = 9
local projection = ffi.new("TestJitProjection[1]")
assert(build_projection(projection, 7, C.ProjectionKind.ROOTS, addr, 3, 4, 5, C.ProjectionReq.ROOTS) == true)
assert(projection[0].id == 7)
assert(projection[0].kind == C.ProjectionKind.ROOTS)
assert(projection[0].addr.pc == 17)
assert(projection[0].frame == 3 and projection[0].base == 4 and projection[0].top == 5)
assert(projection[0].slot_count == 0 and projection[0].root_count == 0)
assert(projection[0].flags == C.ProjectionReq.ROOTS)

local slots = ffi.new("uint32_t[2]", { 10, 11 })
local state = ffi.new("TestJitVirtualState[1]")
assert(init_state(state, addr, 44, 100, 102, slots, 2, nil, 0, nil, 0, nil, 0) == true)
assert(state[0].addr.pc == 17)
assert(state[0].frame == 44 and state[0].base == 100 and state[0].top == 102)
assert(state[0].slot_values == slots and state[0].slot_count == 2)

local anchor = ffi.new("TestJitTraceAnchor[1]")
anchor[0].addr = addr[0]
anchor[0].kind = C.TraceAnchorKind.LOOP
anchor[0].status = C.TraceStatus.COLD
anchor[0].counter = 0
assert(trace_tick(anchor, 2) == false)
assert(anchor[0].counter == 1 and anchor[0].status == C.TraceStatus.COLD)
assert(trace_tick(anchor, 2) == true)
assert(anchor[0].counter == 2 and anchor[0].status == C.TraceStatus.RECORDING)

local ops = ffi.new("TestJitStateOp[2]")
local guards = ffi.new("TestJitGuard[1]")
local snapshots = ffi.new("TestJitProjection[1]")
local record = ffi.new("TestJitTraceRecord[1]")
assert(init_trace(record, anchor, ops, 2, guards, 1, snapshots, 1, nil, 0, 0) == true)
assert(trace_has_path(record) == true)
assert(trace_is_guarded(record) == true)
assert(trace_select(record, plan) == C.TraceSelectStatus.NO_STENCIL)
assert(plan[0].projections == snapshots and plan[0].projection_count == 1)

record[0].op_count = 0
assert(trace_select(record, plan) == C.TraceSelectStatus.EMPTY)

local VM = require("experiments.lua_interpreter_vm.src.constants")
ops[0].op = VM.Op.LOADI
ops[0].effect.flags = 0
ops[1].op = VM.Op.ADD
ops[1].effect.flags = 0
record[0].op_count = 2
local op_loadi = ffi.new("uint16_t[1]", { VM.Op.LOADI })
local op_loadi_add = ffi.new("uint16_t[2]", { VM.Op.LOADI, VM.Op.ADD })
local pattern_stencils = ffi.new("TestJitCodeStencil[2]")
pattern_stencils[0].op = VM.Op.LOADI
pattern_stencils[0].size = 5
pattern_stencils[1].op = VM.Op.LOADI
pattern_stencils[1].size = 17
local patterns = ffi.new("TestJitStencilPattern[2]")
patterns[0].id = 10
patterns[0].ops = op_loadi
patterns[0].op_count = 1
patterns[0].stencil = pattern_stencils + 0
patterns[0].score = 1
patterns[1].id = 20
patterns[1].ops = op_loadi_add
patterns[1].op_count = 2
patterns[1].stencil = pattern_stencils + 1
patterns[1].score = 10
local pattern_lib = ffi.new("TestJitStencilPatternLibrary[1]")
pattern_lib[0].patterns = patterns
pattern_lib[0].pattern_count = 2
local match = ffi.new("TestJitTraceStencilMatch[1]")
assert(pattern_matches(record, patterns + 1, 0) == true)
assert(match_at(record, pattern_lib, 0, match) == true)
assert(match[0].covered_ops == 2)
assert(match[0].config.pattern_id == 20)
local selected_nodes = ffi.new("TestJitStencilNode[4]")
assert(select_patterns(record, pattern_lib, selected_nodes, 4, match, plan) == C.TraceSelectStatus.OK)
assert(plan[0].node_count == 1)
assert(plan[0].estimated_size == 17)
assert(selected_nodes[0].stencil == pattern_stencils + 1)
assert(selected_nodes[0].config.pattern_id == 20)

patterns[1].forbidden_effects = C.Effect.MAY_BRANCH
ops[1].effect.flags = C.Effect.MAY_BRANCH
assert(select_patterns(record, pattern_lib, selected_nodes, 4, match, plan) == C.TraceSelectStatus.NO_STENCIL)

local evidence = ffi.new("TestJitPromotionEvidence[1]")
evidence[0].hits = 100
evidence[0].ns_savings = 25
assert(promotion_candidate(evidence, 10, 1) == true)
assert(promotion_candidate(evidence, 1000, 1) == false)

local rewrite = ffi.new("TestJitRewriteStencil[1]")
rewrite[0].equivalence.contract_id = 77
rewrite[0].replacement.kind = C.ReplacementKind.EMPTY
assert(rewrite_has_equivalence(rewrite) == true)
assert(rewrite_replacement_physical(rewrite) == true)
rewrite[0].replacement.kind = C.ReplacementKind.CODE_STENCIL
rewrite[0].replacement.stencil = pattern_stencils + 0
assert(rewrite_replacement_physical(rewrite) == true)
rewrite[0].replacement.stencil = nil
assert(rewrite_replacement_physical(rewrite) == false)

local summary = ffi.new("TestJitStencilSummary[1]")
summary[0].covered_ops = 16
summary[0].closure_depth = 2
summary[0].max_arity = 4
summary[0].hole_count = 3
summary[0].exit_count = 1
summary[0].code_size = 96
local policy = ffi.new("TestJitStencilClosurePolicy[1]")
policy[0].max_arity = 4
policy[0].max_depth = 3
policy[0].max_covered_ops = 64
policy[0].max_code_size = 256
policy[0].max_holes = 8
policy[0].max_exits = 2
assert(summary_within_policy(summary, policy) == true)
summary[0].closure_depth = 4
assert(summary_within_policy(summary, policy) == false)
summary[0].closure_depth = 2
local metrics = ffi.new("TestJitStencilPlanMetrics[1]")
assert(plan_metrics(plan, metrics, 2, 1, 99) == true)
assert(metrics[0].node_count == plan[0].node_count and metrics[0].covered_ops == 2)
assert(metrics[0].max_depth == 1 and metrics[0].granularity_score == 99)

clear:free()
layout:free()
build_projection:free()
init_state:free()
trace_tick:free()
init_trace:free()
trace_has_path:free()
trace_is_guarded:free()
pattern_matches:free()
match_at:free()
select_patterns:free()
trace_select:free()
promotion_candidate:free()
rewrite_has_equivalence:free()
rewrite_replacement_physical:free()
summary_within_policy:free()
plan_metrics:free()

print("JIT machines: ok")
