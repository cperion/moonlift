# SponJIT Foundry SSA

**Type:** architecture description  
**Audience:** VM / C / assembly engineers  
**Status:** design plus initial shadow implementation  

This document specifies the offline SSA engine used by the SponJIT absorber foundry.

The initial shadow implementation lives at:

```text
experiments/lua_interpreter_vm/tools/sponjit_shadow/foundry_ssa.lua
```

It is not a runtime IR and not a general optimizing compiler. It is a small,
VM-shaped, projection-aware SSA whose purpose is:

```text
consume facts -> simplify tuple semantics -> produce absorber candidates
```

The runtime never sees this SSA. Runtime SponJIT observes facts/exits, canonicalizes
them into signatures, looks up prebuilt artifacts, and copy/patches holes. All fact
consequence reasoning lives here, in Foundry SSA.

---

## 1. Role in SponJIT

SponJIT's runtime model is bytecode absorption under assumptions. The foundry trains
the absorber vocabulary AOT:

```text
A₀ = opcode absorbers
for k = 0..K:
    enumerate arity≤4 tuples over Aₖ
    expand tuple semantics
    apply facts
    run Foundry SSA
    lower to absorber candidate
    verify / score / benchmark
    select top cap
    Aₖ₊₁ = Aₖ ∪ selected
```

Foundry SSA is the canonical fact consumer in this loop — in the current runtime
design, it is the only fact-consuming optimizer. Runtime facts and guard failures are
inputs to SSA jobs, not inputs to a second runtime optimizer.

```text
Facts do not directly select handwritten lowerings.
Facts specialize a semantic graph.
SSA turns those facts into consequences.
Selection interns the useful consequences as new absorbers.
```

---

## 2. Non-goals

Foundry SSA does **not**:

```text
- run on the hot runtime path;
- synthesize arbitrary runtime instructions;
- require a runtime tiler / cover-search optimizer;
- perform whole-program optimization;
- require a general register allocator;
- excuse missing projection metadata;
- cross opaque Lua observable effect boundaries.
```

If a candidate cannot be projected, dependency-tracked, or lowered to the fixed
stencil/absorber vocabulary, it is rejected.

---

## 3. Inputs and outputs

### 3.1 Inputs

```text
AtomTuple:
  arity≤4 tuple over current foundry basis Aₖ

FactEnv:
  applicable fact combination for the tuple

AtomSemantics:
  semantic expansion for each atom

Budgets:
  register/residency budget
  code size budget
  projection metadata budget
  exit count budget
```

Atoms have two identities:

```text
runtime identity: bytes/holes/contract/cost            opaque to runtime
foundry identity: semantic expansion or SSA summary    transparent offline
```

Selected absorbers must preserve the foundry identity so later layers can reopen
them.

### 3.2 Output

```text
CandidateAbsorber:
  source tuple
  fact environment
  optimized semantic normal-form hash
  optimized SSA graph / lowering plan
  required / checked / produced / killed facts
  dependencies
  exits and projections
  residency endpoints
  estimated cost
  codegen/materialization plan
```

The candidate then enters the normal foundry gates:

```text
contract-valid -> projection-valid -> dependency-valid -> lowering-valid
-> materialize -> benchmark/score -> selection cap
```

---

## 4. Core pipeline

The simplest foundry strategy is exhaustive enumeration over the bounded local
space:

```text
A₀ = raw opcode atoms
for layer k:
    Cₖ = all arity≤4 tuples over Aₖ
    Sₖ = {}
    for tuple in Cₖ:
        for fact_env in applicable_fact_combinations(tuple):
            Sₖ += SSA(tuple, fact_env)
    Wₖ = selected materializable useful SSA forms
    Aₖ₊₁ = Aₖ ∪ Wₖ
```

So the composition universe is always:

```text
raw ops + selected SSA normal forms from prior layers
```

All SSA forms can be generated and deduped offline. Only selected forms become atoms;
unselected forms are measurements, not basis pollution.

Concrete per-candidate loop:

```text
for tuple in arity≤4(Aₖ):
  for fact_env in applicable_fact_envs(tuple):
      graph0 = expand_semantics(tuple)
      graph1 = apply_facts(graph0, fact_env)
      ssa    = build_ssa(graph1)
      graph2 = optimize_ssa(ssa)

      if not legal_effects(graph2): continue
      if not projection_possible(graph2): continue
      if not deps_valid(graph2): continue
      if not register_budget_ok(graph2): continue

      candidate = lower_to_absorber(graph2)
      if not candidate: continue

      measure_or_model(candidate)
      record(candidate)
```

The decisive point:

```text
SSA is between tuple composition and scoring.
```

Too early, it sees only single opcodes. Too late, the foundry may select the wrong
candidates. Runtime is too late and too expensive.

---

## 5. IR shape

Foundry SSA is VM-shaped. It models values, guards, effects, projections, and
residency. It does not need arbitrary LLVM-like expressiveness.

### 5.1 Node record

```text
Node:
  id
  op
  inputs[]
  result_type
  source_span          bytecode pc / atom span
  effect_class
  deps[]
  projection_obligation
  residency_class
  flags
```

### 5.2 Value nodes

```text
const_nil
const_bool
const_i64
const_f64
load_slot
store_slot
load_const
load_upvalue
tag_of
bits_of
box_i64
box_f64
unbox_i64
unbox_f64
move_value
phi_value           only for small recognized control shapes / loops
```

### 5.3 Arithmetic / compare nodes

```text
add_i64
sub_i64
mul_i64
add_f64
cmp_i64
cmp_f64
truthy_test
```

### 5.4 Guard nodes

```text
guard_tag
guard_i64
guard_f64
guard_table
guard_shape
guard_metatable_absent
guard_array_hit
guard_field_slot
guard_call_target
guard_bounds       only for recognized loop schemas
```

Guard nodes create checked facts on their success edge and exits on failure.

### 5.5 Table nodes

```text
table_array_load
table_array_store
table_field_load
table_field_store
table_global_load
table_global_store
barrier_check
```

### 5.6 Control / boundary nodes

```text
branch
jump
return0
return1
returnN
call_boundary
tailcall_boundary
residual_boundary
loop_backedge
```

### 5.7 Projection nodes / metadata nodes

```text
project_pc
project_frame
project_base
project_top
project_slot
project_register_lease
project_virtual_value
project_dependency_epoch
```

These are metadata obligations, not hot-path computation unless lowered into an exit
stub.

---

## 6. Fact application

Facts specialize semantic nodes before and during SSA construction.

Examples:

```text
lhs_i64 / rhs_i64:
  generic ADD -> guard_i64(lhs), guard_i64(rhs), unbox_i64, add_i64, box_i64

table shape + metatable_absent + key_const:
  generic GETFIELD -> guard_table, guard_shape, table_field_load

known_call_target:
  generic CALL -> guard_call_target, call_boundary_known

result_dead:
  store result may be deleted if producer is effect-free under facts

barrier_clean:
  SETFIELD/SETTABLE may omit slow barrier path, with dependency/projection recorded
```

The fact environment also determines dependencies:

```text
shape_known            -> table shape epoch
metatable_absent       -> metatable epoch
known_call_target      -> closure/proto target epoch
barrier_clean          -> GC barrier protocol state
```

---

## 7. Optimization rules

Start small. The first foundry SSA should implement only rules that are obviously
useful for bounded local windows.

### 7.1 Required first rules

```text
DCE:
  delete nodes whose results are unused and whose effects are pure under facts

copy/value forwarding:
  MOVE chains collapse

constant folding:
  const operations fold to const nodes

box/unbox elimination:
  box_i64(unbox_i64(x)) and unbox_i64(box_i64(x)) collapse when legal

redundant guard elimination:
  guard fact already dominated by prior guard/fact is deleted

guard dominance merging:
  one guard can satisfy multiple downstream requirements

load forwarding:
  load_slot after known store_slot to same slot forwards value

store-load forwarding:
  table/slot store followed by same-location load forwards when alias facts allow

return folding:
  producer feeding RETURN1 can lower as producer_return form
```

### 7.2 Later rules

```text
small scalar replacement:
  only for tiny shapes with bounded virtual values and explicit projection

recognized loop invariant guard motion:
  only when kill-set test proves invariant survives body

recognized bounds-check elimination:
  only for named loop schemas and under register/projection budgets

simple reassociation:
  only for arithmetic where Lua semantics and overflow/floating behavior are preserved
```

---

## 8. Effect barriers

SSA must respect Lua observability.

Hard barriers:

```text
CALL / TAILCALL
may_yield
may_throw
may_metamethod
debug hook observable point
GC safepoint / allocation
unknown heap write
unknown table/metatable mutation
```

A rewrite may not move, delete, or reorder across a hard barrier unless the semantic
expansion explicitly proves it is unobservable and projection-safe.

This rule is what prevents Foundry SSA from becoming an unsound mini-compiler.

---

## 9. Projection discipline

Every guard failure, residual boundary, call/yield/error edge, and native→residual
seam needs a projection.

Projection must reconstruct:

```text
resume pc
frame / base / top
live stack slots
dirty register leases
virtual values created by SSA rewrites
pending call/return state
debug/error/yield observability state
dependency epochs required by fallback
```

If SSA deletes, delays, sinks, or forwards a value, the projection must know how to
materialize interpreter-visible state on exit.

```text
projection impossible => candidate rejected
projection too large  => candidate loses in scoring or is budget-rejected
```

---

## 10. Residency / register budget

Foundry SSA does not assume a general runtime allocator. Lowering must fit the fixed
SponJIT residency convention.

Initial residency classes:

```text
slot
fixed_gpr0
fixed_gpr1
fixed_xmm0
```

Budgets:

```text
max_live_gpr
max_live_xmm
max_dirty_leases
max_projection_values
```

If the optimized graph exceeds budget:

```text
spill to canonical slot if profitable and projection-safe
else reject candidate
```

This is the main constraint on scalar replacement and large SSA rewrites.

---

## 11. Lowering to absorber vocabulary

After SSA optimization, the graph must lower to the fixed absorber/stencil node
vocabulary.

Allowed output nodes are those with known materialization templates:

```text
guard_i64
guard_shape
table_field_load
table_field_store
table_array_load
table_array_store
add_i64
cmp_i64
return1
call_boundary_known
jump / branch
projection stubs
```

If optimized SSA contains an unsupported node:

```text
candidate rejected
```

This preserves the no-runtime-codegen invariant.

---

## 12. Semantic normal forms

Foundry SSA gives candidate identity a semantic normal form.

Different opcode tuples can normalize to the same candidate:

```text
LOADK MOVE RETURN1   -> return_const
LOADK RETURN1        -> return_const

SELF MOVE CALL       -> self_call
GETFIELD MOVE CALL   -> field_call

GETFIELD ADDI SETFIELD -> field_i64_update
```

The foundry should eventually key candidates by:

```text
optimized_semantic_normal_form_hash
```

not only by source opcode tuple. This reduces basis pollution and helps absorbers
transfer across superficial bytecode variation.

---

## 13. Interaction with recursive basis growth

SSA makes recursive absorber learning stronger:

```text
composition creates semantic material for SSA
SSA simplifies it into a normal form
selection interns the useful normal form as a new atom
next layer composes that atom again
```

This means the foundry learns optimized semantic phrases, not just opcode phrases.

Examples:

```text
L1: GETFIELD_shape + CALL_known
    -> field_call atom

L2: field_call + ADDI + SETFIELD
    -> method_update atom, if legal and profitable

L2/L3: GETTABLE_array_i64 + ADD_i64 + RETURN1
       -> array_load_add_return atom
```

Runtime still sees only atoms.

---

## 14. Implementation plan

### Phase 1 — IR skeleton

```text
- Node representation
- graph builder for a small opcode subset:
  MOVE, LOADK, LOADI, ADD, ADDI, RETURN1, GETFIELD, SETFIELD, CALL, SELF
- fact application for i64, shape, metatable_absent, known_call_target
- semantic normal-form hash
```

Initial shadow status: implemented in `foundry_ssa.lua`.

### Phase 2 — first simplifier

```text
- DCE
- copy forwarding
- redundant guard elimination
- box/unbox elimination
- producer->RETURN1 folding
```

Initial shadow status: copy forwarding, redundant guard elimination, box/unbox
elimination, and basic DCE are implemented. Producer->RETURN1 is represented in
normal-form recognition; real lowering still comes later.

### Phase 3 — projection metadata

```text
- live slot model
- dirty lease model
- guard exit projection
- residual seam projection estimate
```

Initial shadow status: projection obligations are counted and reported, but not yet
materialized into real exit stubs.

### Phase 4 — lowering plan

```text
- lower optimized nodes to abstract absorber operations
- reject unsupported nodes
- estimate cost / size / projection cost
```

Initial shadow status: semantic normal forms and active SSA ops are emitted. Real
stencil lowering is still pending.

### Phase 5 — foundry integration

```text
- run SSA producer in absorber proposal/foundry pipeline
- compare direct tuple vs SSA-normalized candidate
- report normal forms and projected wins
```

---

## 15. Summary

```text
Foundry SSA is THE fact consumer of SponJIT.
```

Facts specialize semantic graphs. SSA turns those specializations into consequences:

```text
deleted guards
deleted stores/reloads
forwarded values
folded constants
merged projections
recognized semantic idioms
```

The useful consequences are selected as absorbers and added to the recursive basis.
Runtime SponJIT remains mechanically simple:

```text
observe facts/exits -> canonical signature -> cache lookup -> copy -> patch -> link
```

The intelligence moves offline into the foundry, where it can be exhaustive,
measured, verified, and capped.
