# SponJIT Foundry — Grammar-Driven Enumeration

**Type:** architecture description
**Audience:** VM / C / assembly engineers
**Status:** active prototype plus design notes. Current `spongejit/` foundry path is
semantic SSA → hole-parametric Stencil IR → C stencil → object/relocation mining
→ generated bank metadata. Older sections of this document still describe the
pre-Stencil-IR `normal_form_hash`/`ssa_to_c` boundary and other removed ideas;
read old sections as historical context, not exact current code.

The foundry enumerates valid PUC Lua 5.5 opcode sequences, lowers them through
semantic SSA into hole-parametric Stencil IR, emits C with HOLEs, and produces a
read-only bank of pre-compiled binary stencils via GCC.

The bank is the entire code-generation intelligence of the system. The runtime is a
selector (`SPONJIT_RUNTIME_DESIGN.md`): it holds floor + active images, small
tile-site memory, and walks precomputed candidate ladders from the bank. Anything
semantic or code-generating lives offline, in the foundry, where it is bounded by
wall-clock-of-the-build-machine rather than wall-clock-of-the-user-program.

Terminology invariant:

```text
Bank          = read-only library of TileTemplates / stencils
TileTemplate  = the foundry output: bytes, HOLE relocations, contracts, exits,
                projection metadata, dependency metadata, and foundry identity
Image         = runtime output: an executable cover assembled by selecting and
                copy-patching TileTemplates from the bank

The foundry never ships Images in the bank. It ships the stencil vocabulary used
by the runtime to build Images.
```

The semantic SSA layer (`spongejit/src/ssa_lift.lua`, `ssa_ir.lua`, `ssa_opt.lua`)
is the **fact-consuming semantic lowering layer**, not a general optimizer. It
consumes opcode semantics plus a fact environment and chooses specialized core
operations when the facts justify them; otherwise it emits structured exits. The
Stencil IR layer (`ssa_to_stencil.lua`, `stencil_ir.lua`, `stencil_normalize.lua`)
is the **canonical materialization shape**: typed data holes, slot classes,
semantic exits, and native-fragment lowering inputs. `stencil_to_fragment.lua`
emits abstract native-fragment descriptors from that Stencil IR.

It is not a runtime IR and not a general optimizing compiler. The current boundary is:

```text
consume facts -> semantic SSA -> Stencil IR shape -> abstract native-fragment descriptor
```

The runtime never sees this SSA. The runtime observes facts, maintains local lease
state, walks prebuilt candidate ladders in the bank, copy-patches selected templates
into an Image, and swaps region.active. All fact-consequence reasoning lives here,
in Foundry SSA; runtime fact handling is limited to subset checks, penalties, and
ladder descent.

---

## 1. Role in SponJIT

SponJIT's runtime model is image materialization from a bank of TileTemplates. The foundry trains the bank
exhaustively AOT:

```text
A₀ = raw opcode atoms (L0 — the floor source)
for k = 0..K:
    enumerate arity 2..4 tuples over Aₖ
    expand tuple semantics
    enumerate applicable fact environments
    run semantic SSA
    lower to Stencil IR / bank candidate
    verify / score / benchmark
    select top cap
    Aₖ₊₁ = Aₖ ∪ selected
```

Semantic SSA is the canonical fact consumer in this loop. Stencil IR is the
canonical code-shape/bank-shape representation. The runtime does not optimize.
Observed runtime facts and exit clusters are inputs to *next-run* foundry training,
not to a runtime optimizer.

```text
Facts do not directly select handwritten lowerings.
Facts specialize a semantic graph.
SSA turns those facts into consequences.
Stencil IR turns those consequences into reusable patchable shapes.
Selection interns the useful consequences as bank tiles.
```

---

## 2. Non-goals

Foundry SSA does **not**:

```text
- run on the hot runtime path;
- synthesize arbitrary runtime instructions;
- require the runtime to build SSA, discover new tile shapes,
  optimize effect graphs, synthesize code, or lower machine instructions;
- require the runtime to maintain a cache, manage eviction, or detect megamorphism;
- perform whole-program optimization;
- require a general register allocator;
- excuse missing projection metadata;
- cross opaque Lua observable effect boundaries.
```

Foundry SSA may rely on the runtime to:

```text
- select one TileTemplate per window from the bank by greedy candidate-ladder lookup
- skip candidates whose required facts contradict local leases or site penalties
- copy/patch/link the selected TileTemplates into an Image
- atomically swap region.active to the new image
- on tile exit, update local lease/site memory and reselect the failed span;
  if same-span replacement misses, split the span; if arity reaches 1, use L0
- on dep invalidation or extreme instability, fall back to the floor image
```

If a candidate cannot be projected, dependency-tracked, or lowered to the fixed
stencil vocabulary, it is rejected.

---

## 3. Inputs and outputs

### 3.1 Inputs

```text
AtomTuple:
  arity 2..4 tuple over current foundry basis Aₖ

FactEnv:
  applicable fact combination for the tuple
    -- monomorphic: a single signature
    -- fact profile: observed signatures for capping

AtomSemantics:
  semantic expansion for each atom

CorpusPressure:
  observed signature distributions per pattern, aggregated across runs;
  drives fact-combo capping policy

Budgets:
  register/residency budget
  code size budget
  projection metadata budget
  exit count budget
  selection-cap budget per layer
```

Atoms have two identities:

```text
runtime identity: bytes/holes/contract/cost            opaque to runtime
foundry identity: semantic expansion or SSA summary    transparent offline
```

Selected bank tiles must preserve the foundry identity so later layers can reopen
them for further composition.

### 3.2 Output

```text
CandidateBankTile:
  source tuple
  fact environment / signature
  stencil_hash                 -- canonical C/code shape
  contract_key                 -- selector/fact-transfer identity
  semantic SSA summary / Stencil IR lowering plan
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
-> materialize -> benchmark/score -> selection cap -> bank
```

---

## 4. Core pipeline

The simplest foundry strategy is exhaustive enumeration over the bounded local
space:

```text
A₀ = raw opcode atoms
for layer k:
    Cₖ = all arity 2..4 tuples over Aₖ
    Sₖ = {}
    for tuple in Cₖ:
        for fact_env in applicable_fact_combinations(tuple):
            Sₖ += SSA(tuple, fact_env)
    Wₖ = selected materializable useful SSA forms
    Aₖ₊₁ = Aₖ ∪ Wₖ
```

So the composition universe is always:

```text
raw ops + selected Stencil IR / SSA-normalized atoms from prior layers
```

All SSA forms can be generated and deduped offline. Only selected forms become atoms
in the bank; unselected forms are measurements, not basis pollution.

Concrete per-candidate loop:

```text
for tuple in arity2_to_4(Aₖ):
  for fact_env in applicable_fact_envs(tuple):
      graph0 = expand_semantics(tuple)
      graph1 = apply_facts(graph0, fact_env)
      ssa    = build_ssa(graph1)
      graph2 = optimize_ssa(ssa)

      if not legal_effects(graph2): continue
      if not projection_possible(graph2): continue
      if not deps_valid(graph2): continue
      if not register_budget_ok(graph2): continue

      candidate = lower_to_stencil(graph2)
      if not candidate: continue

      measure_or_model(candidate)
      record(candidate)
```

The decisive point:

```text
SSA is between tuple composition and scoring.
```

Too early, it sees only single opcodes. Too late, the foundry may select the wrong
candidates. Runtime is too late and ruled out by design.

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
fact_profile_note      optional offline metric for fact capping
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

For profile-guided fact capping, observed signatures are metrics, not runtime tile unions:

```text
fact_env = {S1: facts1, S2: facts2}
SSA builds an internal discriminator + per-arm specialized bodies.
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

Every guard failure, residual boundary, call/yield/error edge, and image→floor
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

The runtime's response to any guard failure is the same: project state, jump to
floor at the corresponding PC, continue. Projection design lives entirely in the
foundry; the runtime mechanism is one indirect jump to a stub.

---

## 10. Residency / register budget

Foundry SSA does not assume a general runtime allocator. Lowering must fit the
fixed SponJIT residency convention.

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

Residency conventions are part of the bank's tile contracts. The runtime composes
tiles by matching advertised entry/exit residency endpoints — selection sees
residency as a property of a tile, not a search axis. Tiles whose residency
contracts do not match at a boundary are not composed; an L0 tile (which sources
all operands from canonical slots) is always a legal joiner.

---

## 11. Lowering to stencil vocabulary

After SSA optimization, the graph must lower to the fixed stencil/atom vocabulary
the bank supports.

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

## 12. Stencil IR canonical forms

Semantic SSA gives candidate identity Lua meaning; Stencil IR gives candidate
identity a reusable patchable code shape.

Different opcode tuples can normalize to the same Stencil IR candidate:

```text
LOADK MOVE RETURN1   -> return_const-like stencil shape
LOADK RETURN1        -> return_const-like stencil shape

SELF MOVE CALL       -> self_call-like stencil shape
GETFIELD MOVE CALL   -> field_call-like stencil shape

GETFIELD ADDI SETFIELD -> field_i64_update-like stencil shape
```

The foundry separates two keys:

```text
stencil_hash                 -- canonical C/code shape
stencil_hash + contract_key  -- bank form / selector contract identity
```

not only by source opcode tuple. This reduces basis pollution and helps bank tiles
transfer across superficial bytecode variation. ICF-style merging at GCC link time
may collapse identical machine code further.

---

## 13. Fact-space capping

Fact combinations are a foundry-time selection problem: enumerate only the fact
bundles justified by grammar constraints, profile pressure, and code-size/usefulness
budgets. Runtime does not build a cache or route through a special tile class; it
selects ordinary bank tiles by their contracts.

## 14. Interaction with recursive basis growth

SSA makes recursive basis learning stronger:

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

Higher layers compose the basis selected so far. Fact diversity is handled by
capping/profile-guiding ordinary fact-specialized tiles, not by a separate tile
kind. Runtime still sees only TileTemplates drawn from the bank, never SSA forms or
prebuilt Images.

---

## 15. Selection cap and the bank size budget

Enumeration may be large offline. Bank tiles are budgeted by selection.

Measurements are configuration-dependent and have changed across prototypes. The
old small shadow-foundry numbers are no longer representative of the current
Stencil IR bank path. For current size/count data, use `src/worker_compile.lua` outputs and
`foundry.lua` summaries, especially `grammar_fragments_N.json`,
`grammar_result_N.json`, and `foundry_layers.json`.

Important current metrics to track are:

```text
source opcode sequences
fact combinations compiled
unique stencil_hash values
unique contract shapes
unique fragment descriptor/code keys
abstract/non-executable fragment coverage
average data relocs/fragment
average control relocs/fragment
average projections/fragment
average Stencil IR ops/fragment
```

The pack budget is a soft constraint. The goal is not "fit in N MB" — the goal is to
beat per-op stencil JITs by *fusing*. The 50 MB number cited earlier in design
material was a soft ceiling, not a target. Selection retains fragments that
demonstrate fusion wins over their child cover; rejection is driven by foundry-side
measurement, not by a hard byte budget.

Hard rules:

```text
dedupe abstract fragment descriptors by stencil_hash + op_signature + contract_key
keep distinct bank forms by stencil_hash + contract_key
keep Pareto frontier over speed / bytes / exits / projection size
longer fragment must beat best composition of shorter fragments
retire fragments whose signatures never appear in corpus or runtime exit logs
```

---

## 16. Atom / SSA interaction

Atoms are where the offline and runtime worlds meet.

An atom carries:

```text
runtime identity:
  bytes
  patch holes
  guard exits
  projection metadata
  dependency cells
  cost / size

foundry identity:
  semantic expansion or SSA summary
  Stencil IR shape/hash
  required / checked / produced / killed facts
  contract key
  effect summary
  for fact caps: observed signature/profile metadata
```

Runtime treats TileTemplates as opaque artifacts. The foundry can reopen them for higher-
layer composition or replay through SSA when corpus pressure changes.

---

## 17. Implementation plan

### Phase 1 — IR skeleton

```text
- Node representation
- graph builder for a small opcode subset:
  MOVE, LOADK, LOADI, ADD, ADDI, RETURN1, GETFIELD, SETFIELD, CALL, SELF
- fact application for i64, shape, metatable_absent, known_call_target
- Stencil IR canonical hash
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
- floor seam projection estimate
```

Initial shadow status: projection obligations are counted and reported, but not yet
materialized into real exit stubs.

### Phase 4 — lowering plan

```text
- lower optimized nodes to stencil operations
- reject unsupported nodes
- estimate cost / size / projection cost
- emit real .o files with HOLE relocations
```

Current status: the production foundry path emits real `.o` files from Stencil IR,
mines HOLE relocations, and generates bank metadata. Counts and sizes depend on
`MAX_ARITY`, `MAX_FACT_COMBOS`, `FACT_AXIS_MODE`, corpus/fact axes, and whether a
full or sampled bank is being built.

### Phase 5 — fact-space metrics and caps

```text
- measure fact-combo explosion per opcode pattern
- keep structurally useful combinations
- cap facts by profile pressure and code-size budget
- report unique stencil_hash, contract shapes, emitted C functions, holes/tile
```

### Phase 6 — bank export

```text
- selection cap policy
- Pareto frontier maintenance
- normal-form dedup
- fact-cap/profile metadata layout
- bank file format
- runtime mmap reader
```

### Phase 7 — foundry integration

```text
- run SSA producer in bank training pipeline
- compare direct tuple vs SSA-normalized candidate
- report normal forms and projected wins
- exit-log ingestion for next-run training
```

---

## 18. Summary

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
profile-guided fact caps and fused tiles
```

The useful consequences are selected as bank tiles. Sites that the current bank does
not cover profitably fall back to weaker/generic tiles or L0; profile pressure can
then guide later fact caps and basis growth. Recursive basis growth interns
optimized semantic phrases as atoms, broadening higher layers without inflating the
runtime.

Runtime SponJIT remains mechanically simple:

```text
observe facts -> canonicalize signature -> bank lookup -> copy/patch -> swap active.
on failure: demote to floor. on persistent failure: stay at floor; log for next run.
```

The intelligence lives offline in the foundry, where it can be exhaustive,
measured, verified, and capped.
