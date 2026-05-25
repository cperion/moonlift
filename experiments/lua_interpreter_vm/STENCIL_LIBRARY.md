# Moonlift Lua VM — Stencil Library Plan

The JIT backend is copy-and-patch stencil materialization.

This document is the implementation contract for stencil-library construction and runtime use. Lua
probe code, LuaJIT FFI runners, Lua planners, and byte-shaped benchmark probes are not the JIT and
must not be treated as runtime compiler progress.

The hard boundary is:

```text
OFFLINE / BUILD-TIME / PROMOTION TIME
  evidence -> candidate kernels -> primitive/compound/rewrite stencil products -> verified library

RUNTIME / HOT JIT TIME
  TraceRecord or conservative range -> select existing stencil products
  -> layout -> copy/stamp/payload/fixup/publish/link
```

Runtime tracing may collect evidence and may select from the existing library. It must not generate
new stencil shapes or run a general compiler.

---

# 1. Non-negotiable runtime boundary

The real runtime JIT consists of explicit Moonlift products and machines:

```text
StateProgram
VirtualState
Effect
Projection
Guard
TraceAnchor
TraceRecord
CodeStencil
StencilPattern
StencilPatternLibrary
TraceStencilMatch
StencilPlan
ExecImage
ExecutableUnit
EntryCell
EdgeCell
NativeJitOutcome
```

The current product/control surface lives at:

```text
experiments/lua_interpreter_vm/src/jit/products.lua
experiments/lua_interpreter_vm/src/jit/constants.lua
experiments/lua_interpreter_vm/src/jit/funcs.lua
experiments/lua_interpreter_vm/src/jit/regions.lua
experiments/lua_interpreter_vm/src/jit/machines.lua
```

The current offline generator/pruner lives at:

```text
experiments/lua_interpreter_vm/src/jit/library_builder.lua
experiments/lua_interpreter_vm/tools/generate_stencil_library.lua
```

Runtime machines currently include structural checks, trace anchor/record setup, and bounded maximal
matching over an already-built `StencilPatternLibrary`:

```text
jit_trace_anchor_tick
jit_init_trace_record
jit_trace_pattern_matches
jit_trace_match_at
jit_trace_select_pattern_plan
jit_layout_stencil_plan
```

These are Moonlift product/machine routines. They do not synthesize new machine-code fragments.

---

# 2. What stays as evidence only

The empirical miner remains useful:

```text
experiments/lua_interpreter_vm/src/jit/miner_contracts.lua
experiments/lua_interpreter_vm/tools/mine_stencils.lua
experiments/lua_interpreter_vm/tools/profile_awfy_puc.lua
```

Miner/profiler output is evidence:

```text
CandidateManifest
candidate assembly/object bytes
hole and relocation observations
AWFY opcode/motif profiles
runtime trace motifs
branch/fact/guard frequencies
exit and projection frequencies
```

Evidence is not the runtime stencil library.

A candidate becomes a `CodeStencil`, `StencilPattern`, or `RewriteStencil` only after it is promoted
as an explicit product with:

```text
semantic contract
input/output StateShape or pattern contract
Effect / forbidden effects
ProjectionRequirement / BoundaryRequirement
DependencyRequirement
holes / relocs / payloads for physical CodeStencils
ABI metadata
clobber metadata
verification against interpreter-derived semantics
negative tests
materialization tests where physical bytes exist
```

---

# 3. Three-layer stencil library

## 3.1 Primitive CodeStencils

Primitive stencils are physical machine-code fragments for one small semantic operation:

```text
value.move.sB_to_sA.fall
value.load_i64.imm_to_sA.fall
guard.int.sA.next_or_exit
arith.add_i64.sB_sC_to_sA.fall
branch.jump.pc_relative
projection.write_slot
edge.jump_indirect
```

## 3.2 Compound CodeStencils

Compound stencils are larger physical fragments promoted from common patterns, trace motifs, and
fact-specialized sequences:

```text
guard_pair_add_store
truthy_test_jump
projection.bundle_3
forloop_i64_add_acc
array_get_i64_add_acc_forloop
method_self_move_call.ic1
```

They are still finite library products. The runtime selector can choose them, but cannot create them.

## 3.3 RewriteStencils

Rewrite stencils are plan-level transformations. Some emit no bytes directly; they rewrite the plan
before physical materialization.

Examples:

```text
rewrite.dead_pure_node
  pattern: node produces ValueId v
  required: v has no users, node.effect == PURE
  replacement: empty

rewrite.redundant_guard
  pattern: guard fact F
  required: VirtualState already proves F
  replacement: empty

rewrite.bundle_projection_slots
  pattern: project_slot A; project_slot B; project_slot C
  replacement: projection.bundle_3

rewrite.guard_pair_add_to_supernode
  pattern: guard_int B; guard_int C; add_int B C A
  replacement: arith.add_i64_guarded_pair.sB_sC_to_sA.next_or_exit
```

DCE therefore exists as a zero-output rewrite stencil, not as a hidden optimizer pass.

Current explicit offline/promotion products include:

```text
TraceMotif
PromotionEvidence
StencilReplacement
StencilEquivalence
RewriteStencil
StencilPromotion
```

---

# 4. StencilPlan IR, closure, and emergent tiers

A `StencilPlan` is the JIT IR. It is not a general SSA optimizer IR; it is a physical-semantic plan
whose nodes already point at existing stencil/rewrite products.

Optimization is refinement of that IR:

```text
small stencil sequence
  -> RewriteStencil / StencilPattern match
  -> larger existing CodeStencil or empty replacement
  -> new StencilPlan
  -> rematerialized ExecutableUnit
  -> EntryCell/EdgeCell relink
```

## 4.1 Bounded-arity stencil closure

The offline library grows by bounded-arity closure:

```text
L0 = primitive stencils
L1 = close_4(L0)
L2 = close_4(L1)
L3 = close_4(L2)
```

A compound promoted in one round becomes an atom in the next. Keeping `max_arity <= 4` still allows
larger absorbed stencils over depth:

```text
depth 0: 1 original op
depth 1: up to 4 original ops
depth 2: up to 16 original ops
depth 3: up to 64 original ops
```

The closure loop is offline:

```text
enumerate compounds over current library, arity <= 4
check structural contracts
AOT generate/compile/classify physical candidates where needed
verify equivalence to expansion
measure/cost/prune
promote survivors back into the library
```

Budgets are explicit products/policy, not folklore:

```text
StencilSummary
StencilClosurePolicy
StencilClosureRound
StencilPlanMetrics
StencilPlanRefinement
```

## 4.2 Emergent granular tiers

Runtime tiering is an emergent property of stencil density:

```text
unit_v0: primitive stencils
unit_v1: shallow compound stencils
unit_v2: deeper closure compounds
unit_v3: trace-shaped compounds
```

There is still one selector and one materializer. Upgrading is:

```text
replan with stronger facts / larger existing stencils
rematerialize as a new ExecutableUnit
relink EntryCell/EdgeCell
reclaim old units at quiescence
```

The tier is stencil granularity, not a different compiler.

---

# 5. Runtime trace selection

Runtime trace selection is bounded maximal matching over existing products:

```text
TraceRecord + StencilPatternLibrary
  -> patterns starting at trace op i
  -> filter by opcode sequence, required effects, forbidden effects, facts/deps/projections
  -> choose largest/highest-scoring legal pattern
  -> emit StencilNode
  -> advance by covered_ops
```

This is `TraceStencilSelector`. It is not runtime stencil generation and not a general optimizer.

If no promoted pattern matches, runtime returns:

```text
TRACE_SELECT_NO_STENCIL
```

and falls back/declines. It must not invent ad-hoc code.

---

# 6. Offline promotion loop

The library grows outside the hot path:

```text
run representative VM programs
record/minE opcode motifs, trace motifs, facts, exits, projections
select candidate patterns worth promoting
generate Moonlift candidate kernels or compose primitive stencil candidates
AOT compile/dump/classify bytes where physical stencils are needed
verify holes/relocs/payloads/ABI/clobbers
prove/check equivalence against interpreter-derived contracts
promote to CodeStencil / StencilPattern / RewriteStencil
ship the finite library to runtime
```

Tracing is an evidence source for this loop. Runtime traces answer:

```text
which paths recur
which facts are stable
which guards usually succeed
which exits dominate
which projected slots/root bundles recur
which values are dead
which primitive sequences deserve compound stencils
```

Promotion happens offline/build-time, not in the hot JIT.

---

# 7. Generation and pruning implementation

The first concrete generator is implemented now:

```sh
luajit experiments/lua_interpreter_vm/tools/generate_stencil_library.lua \
  experiments/lua_interpreter_vm/build/stencil_mining/candidate_manifest.json \
  experiments/lua_interpreter_vm/build/stencil_library \
  1 4
```

It writes:

```text
build/stencil_library/promotion_plan.json
build/stencil_library/promotion_report.md
```

The generator code path is:

```text
candidate_manifest.json
  -> library_builder.atoms_from_manifest
  -> library_builder.generate_closure_round
  -> library_builder.prune_candidates
  -> promotion_plan.json
```

The current generator promotes complete manifest candidates as primitive physical atoms and emits
compound closure candidates as `needs_physical_fixture`. Those compounds are not runtime-shippable
until an AOT fixture/promotion step gives them real bytes/holes/relocs.

## 7.1 Generation and pruning discipline

Stencil closure must be aggressive enough to discover useful compounds, but ruthless enough to keep
the shipped library finite.

## 7.2 Candidate generation

Each offline closure round uses the current library as its alphabet:

```text
input atoms = primitive CodeStencils + promoted compound CodeStencils + RewriteStencils
for arity in 2..max_arity:
  enumerate adjacent/composable atom sequences seen in traces or allowed by curated roots
  compose summaries: StateShape, facts, effects, exits, projections, deps, liveness, holes, cost
  reject structurally invalid compositions immediately
  canonicalize the expanded semantic pattern
  generate a candidate:
    physical candidate -> AOT Moonlift/Cranelift bytes + holes/relocs/payloads
    rewrite candidate  -> StencilReplacement + StencilEquivalence
```

Candidate generation is evidence-guided, not exhaustive over all bytecode strings. Sources include:

```text
AWFY opcode pairs/triples/motifs
runtime TraceRecord motifs
exit/profile counters
projection/root bundle frequencies
known Ring 0 safety stencils
hand-curated MVP patterns
```

## 7.3 Hard rejection gates

A candidate is rejected before benchmarking if any hard contract fails:

```text
input/output StateShape does not compose
continuation/exits cannot be mapped precisely
projection snapshot would be less precise than expansion
effect set is wider than allowed or hides a boundary
speculative fact lacks a dependency
holes/relocs/payloads exceed policy
code size exceeds policy
closure depth / covered ops / arity exceed policy
semantic equivalence proof/check is missing
```

## 7.4 Pruning and scoring

Survivors are pruned by Pareto frontier, not by one scalar alone. Keep only candidates that are not
dominated on:

```text
estimated hot execution cost
materialization cost
code size
hole/fixup count
exit count / snapshot cost
dependency count / invalidation risk
coverage of observed motifs
```

A useful first scoring model is:

```text
benefit = evidence_hits * (expanded_cost - candidate_cost)
        - code_size_tax
        - materialization_tax
        - exit_risk_tax
        - dependency_risk_tax
```

Promotion policy:

```text
keep top K per canonical pattern/fact-key/depth
keep mandatory Ring 0 safety stencils
keep primitive fallback stencils even if slow
reject compounds that do not beat their expansion by threshold
reject brittle trace-shape stencils with high exit rate or low guard success
```

Every promoted compound must keep its expansion available as fallback.

## 7.5 Library indexes for runtime

The runtime selector must not search the whole library. Promotion produces indexes such as:

```text
first opcode / first StateOp kind
covered op count / closure depth
required facts key
forbidden effects mask
projection/boundary class
pattern hash
```

Runtime matching then becomes bounded maximal lookup:

```text
look up candidates for trace[i]
try largest/deepest/highest-score first
verify facts/effects/deps/snapshots
emit node or decline
```

---

# 8. Curated stencil families

The empirical AWFY profile says the useful library must prioritize object/table/call patterns, not
only arithmetic.

Initial families:

```text
Ring 0: entry / exit / outcome / projection / edge / boundary
Ring 1: value movement and generic opcode roots
Ring 2: fact-specialized variants and inline caches
Ring 3: compound stencils promoted from mined motifs
Ring 4: rewrite stencils for plan-level elimination/fusion/bundling
```

## 8.1 Ring 0 skeleton

```text
entry.vm_state_to_unit
exit.to_interpreter_next
exit.to_interpreter_jump
outcome.ok
outcome.side_exit
outcome.call_boundary
outcome.runtime_boundary
edge.jump_indirect
edge.resolve_miss
project.live_slots.bundle
project.roots.bundle
project.resume_state
boundary.call_helper
boundary.return_to_vm_loop
```

## 8.2 Primitive roots

```text
value.move.sB_to_sA.fall
value.load_i64.imm_to_sA.fall
value.load_k.kB_to_sA.fall
value.load_bool.tag_to_sA.fall
value.load_nil.sA_count.fall
value.getupval.generic.sU_to_sA.fall
arith.add.generic.sB_sC_to_sA.next_or_mm
arith.addi.generic.sB_imm_to_sA.next_or_mm
branch.test.sA.true_or_false
cmp.eq.generic.sB_sC.true_or_false_or_mm
cmp.lt.generic.sB_sC.true_or_false_or_mm
loop.forprep.generic.sA_Bx.jump_or_exit
loop.forloop.generic.sA_Bx.loop_or_exit
call.generic.sF_args.boundary
return.zero
return.one.sA
```

## 8.3 AWFY-priority specialized variants

```text
table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow
table.setfield_shape_ic1.sT_kName_sV.next_or_slow_or_barrier
table.gettable_array_i64_ic1.sT_sK_to_sA.next_or_slow
table.settable_array_i64_ic1.sT_sK_sV.next_or_slow_or_barrier
table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow
table.gettabup_shape_ic1.sU_kName_to_sA.next_or_slow
call.known_lclosure.sF_args.enter_lua
call.known_cclosure.sF_args.enter_native
loop.forloop_i64_positive.sA_Bx.loop_or_exit
cmp.eq_i64_guarded.sB_sC.true_or_false_or_exit
cmp.lt_i64_guarded.sB_sC.true_or_false_or_exit
```

## 8.4 Compound/supernode targets

Promote only with proof that the contract equals the expanded sequence:

```text
super.method_self_move_call.ic1
super.field_field_test_branch.ic1
super.field_field_add_setfield.ic1
super.array_get_test_forloop.ic1
super.array_set_forloop.ic1
super.while_table_update_i64.ic1
super.projection_slots_3
super.guard_pair_add_store_i64
```

---

# 9. Speed discipline

The speed question must be answered only on the real runtime path:

```text
Moonlift product plan
-> existing CodeStencil / StencilPattern selection
-> real materializer/publisher
-> executable unit entered through VM/JIT gate
-> outcome mapped to vm_loop continuation
```

Benchmarks on Lua planners, LuaJIT FFI wrappers, or byte-shaped probes are not JIT benchmarks.
They may be used privately as probes, but they must not appear as implementation results.

Structural benchmarks may measure compiled Moonlift product machines, but they are not hot emitted
code performance.

---

# 10. Next implementation steps

1. Keep trace selection over existing `StencilPatternLibrary` products.
2. Add the first fixture-backed primitive `CodeStencil` records.
3. Add a tiny promoted pattern library for a known trace motif such as `LOADI + ADD` or `MOVE + ADD`.
4. Implement materialization skeleton over selected `StencilNode`s.
5. Add rewrite-stencil tests for zero-output DCE and projection bundling at plan level.
6. Only then wire VM hot anchors to trace recording/selection gates.
