# SponJIT Runtime Design — Exit-Authored Signature Cache

**Type:** JIT architecture spine  
**Audience:** VM / C / assembly engineers  
**Status:** design; shadow validation in progress  

This document records the current SponJIT design after the consolidation decision:

```text
SSA is THE fact-consuming layer.
Runtime does not optimize. Runtime observes, canonicalizes, caches, patches, and executes.
```

The main contrast with LuaJIT is not merely that SponJIT precompiles some code. The
contrast is a different binding-time split:

```text
LuaJIT:
  runtime observes -> runtime records -> runtime optimizes SSA/IR -> runtime emits

SponJIT:
  runtime observes -> runtime records signatures/exits -> offline/background SSA emits templates
  runtime later does fast signature-cache lookup + copy/patch
```

Cheap copy-and-patch materialization buys the right to be wrong. SponJIT can choose a
tight monomorphic artifact, watch it, and replace it when behavior moves, without
paying a runtime optimizer cost on the hot path.

---

## 0. Thesis

```text
precompile SSA forms offline
  => runtime materialization is copy-and-patch, not compilation
    => re-specialization is cheap enough to do repeatedly
      => guard failures and exits become datapoints, not defeat
        => each stable observed mode gets its own tight monomorphic artifact
          => hysteresis + cache keep the system convergent and economical
```

LuaJIT pays a high runtime compile cost, so it must commit hard to a trace and repair
with side traces. SponJIT pays optimizer cost outside the hot path, so it can treat a
bad specialization as information:

```text
side exit / guard failure = observed fact delta = request for a better cached artifact
```

The target regime is not universal superiority. It is workloads where monomorphic
structure is real but non-stationary:

```text
stable enough to amortize a specialized artifact;
mobile enough that one-shot speculative compilation goes stale.
```

---

## 1. Runtime responsibility

The runtime is intentionally dumb.

```text
runtime responsibilities:
  collect cheap facts
  canonicalize facts into a signature
  look up artifact by (region, signature)
  copy/patch/link artifact if needed
  execute artifact
  record guard exits and cache misses
  fall back to the generic floor on miss
```

Runtime does **not**:

```text
run SSA
run a graph optimizer
perform tiling / cover search
reason about fact consequences
choose which guards can be deleted
invent new code shapes
```

Runtime may fill holes, because hole filling is mechanical:

```text
constants
slot offsets
field offsets
continuation addresses
dependency-cell addresses
exit-stub addresses
residency endpoints under a fixed convention
```

The rule:

```text
SSA decides what holes exist.
Runtime only fills them.
```

---

## 2. SSA responsibility

SSA is the only fact consumer.

```text
facts -> semantic graph -> SSA specialization -> simplification -> lowering -> artifact template
```

SSA decides:

```text
which facts are assumptions
which facts need guards
which guards are redundant
which operations can be deleted / folded / forwarded
which atom/stencil cover to use
which holes remain dynamic
which projections are required
which dependencies invalidate the artifact
```

Tiling does not disappear. It moves into the SSA backend:

```text
optimized SSA graph -> instruction/atom selection -> copy-patch template
```

Atoms are now both:

```text
runtime objects: bytes + holes + contract + exits + deps
foundry objects: semantic expansion / SSA summary + fact masks
```

---

## 3. Region signature cache

Each hot region owns a cache keyed by canonical fact signature.

```text
RegionCache[R]:
  S_i64_shapeA     -> artifact A
  S_f64_shapeA     -> artifact B
  S_i64_shapeB     -> artifact C
  generic          -> generic floor artifact
```

Polymorphism lives in the cache, not inside one giant artifact.

A bimorphic site should converge to:

```text
signature S1 -> tight monomorphic artifact for S1
signature S2 -> tight monomorphic artifact for S2
```

not:

```text
one artifact with a large internal polymorphic decision tree
```

The cache key must be canonicalized aggressively. It should include facts that change
SSA consequences, and project out facts that only create noise.

Examples of useful signature axes:

```text
numeric kind: i64 / f64 / other
table shape id
metatable absence / epoch
known call target id
array-hit / field-slot classification
loop invariant class
bounds relation class
```

Examples of facts to project out unless they affect optimization:

```text
exact object identity when shape is enough
exact constant value when only type matters
residency location if patch holes can handle it
rare debug-only metadata
```

---

## 4. Guard failures are facts

A guard is a question asked by the artifact:

```text
is this value i64?
does this table still have shape S?
is this call target still F?
```

A guard failure is the runtime answering with a precise fact delta:

```text
artifact assumed: x:i64
runtime observed: x:f64
```

That failure is not merely an exit. It is a candidate compiler job:

```text
(region R, old signature S_i64, exit reason x:f64)
  -> observed alternative signature S_f64
  -> maybe enqueue SSA job for (R, S_f64)
```

Thus:

```text
exit stream = admission-controlled SSA work queue
```

The cache is authored by exits. A served exit reason should remove itself from the
future exit stream because the new artifact is built for that reason.

---

## 5. Execution lifecycle

### 5.1 Cache hit

```text
observe cheap facts
signature = canonicalize(facts)
artifact = region_cache[signature]
patch holes if artifact instance not already live
execute artifact
```

### 5.2 Cache miss

```text
observe cheap facts
signature = canonicalize(facts)
artifact missing
run generic floor artifact immediately
record miss/signature
if hot and stable: enqueue offline/background SSA job
```

A miss must not stall on SSA. The generic floor is mandatory.

### 5.3 Guard failure

```text
artifact exits with reason E
record E as observed fact delta
project interpreter state
resume generic floor / interpreter / residual path
if E clusters hot and stable: enqueue SSA job for alternative signature
```

### 5.4 Artifact publication

```text
SSA job completes
artifact template validated
artifact inserted into region cache under signature S
future executions hit S
old generic/residual pressure falls
```

---

## 6. Generic floor

Every region must have an always-legal floor.

The floor may be:

```text
interpreter residual path
baseline opcode absorber sequence
generic copy-patch artifact with conservative guards
```

But it must satisfy:

```text
cache miss never blocks on compiler
unsupported signature still runs correctly
megamorphic region has a stable non-specialized steady state
```

This keeps worst case bounded:

```text
bad specialization policy => falls back to generic performance, not a stall or crash
```

---

## 7. Hysteresis

Hysteresis has three separate jobs.

### 7.1 Convergence gate

Prevent oscillation between signatures:

```text
S1 hot briefly -> S2 hot briefly -> S1 hot briefly
```

Do not republish or switch until the new mode persists.

### 7.2 Amortization gate

Do not create an artifact unless expected benefit exceeds cost:

```text
benefit_per_hit * expected_hits_before_change
  > materialization_cost + metadata_cost + cache_pressure_cost
```

### 7.3 Compile-queue admission

Do not enqueue SSA jobs for noise.

A signature/exit reason must be:

```text
hot enough
stable enough
clustered enough
not megamorphic
not already served by a nearby artifact
```

before it earns an SSA job.

---

## 8. Megamorphic cutoff

Guard failures are optimization opportunities only when their reasons cluster.

Good:

```text
80% x:i64
20% x:f64
```

Likely response:

```text
cache two monomorphic artifacts
```

Bad:

```text
shape1, shape2, shape3, ..., shape50 with flat distribution
```

Response:

```text
mark axis or region megamorphic
stop specializing that axis
use generic floor or coarser signature
```

The megamorphic cutoff prevents artifact explosion.

Possible policy:

```text
if distinct_signatures_in_window > N and top_k_coverage < threshold:
    coarsen signature or mark generic
```

---

## 9. Artifact cache and pack budget

Enumeration may be large offline. Published artifacts are budgeted.

Research target:

```text
selected artifact pack <= 50 MB
```

Selection should eventually optimize under both speed and size:

```text
cycles_saved
cycles_saved_per_byte
metadata_bytes
projection_bytes
selector/cache pressure
reuse count
```

Hard rules:

```text
dedupe semantic normal-form hash
keep Pareto frontier over speed / bytes / exits / projection size
longer artifact must beat best composition of shorter artifacts
retire artifacts whose signatures stop occurring
```

---

## 10. Atom / SSA interaction

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
  required / checked / produced / killed facts
  normal-form hash
  effect summary
```

Runtime treats atoms as opaque artifacts. The foundry can reopen them.

Recursive learning:

```text
A₀ = opcode atoms
Cₖ = arity≤4 tuples over Aₖ
Sₖ = SSA(Cₖ × applicable fact combinations)
Wₖ = selected materializable useful SSA forms
Aₖ₊₁ = Aₖ ∪ Wₖ
```

So the basis at each layer is:

```text
raw ops + selected SSA normal forms from earlier layers
```

The foundry may enumerate many SSA forms, but only selected forms become atoms.
Next layer can reopen Aₖ₊₁ atoms and optimize across them.

So longer-range optimization comes from:

```text
fixed arity + growing semantic basis
```

not from unbounded runtime compilation.

---

## 11. Binding-time policy

The recommended default is strict:

```text
runtime never runs SSA
```

Runtime can enqueue work, but SSA runs outside the hot path:

```text
offline training run
background compiler process
next-run profile-guided rebuild
developer/foundry build step
```

If runtime synchronously invokes SSA for hot misses, SponJIT becomes much closer to a
traditional optimizing JIT. That may be a future experiment, but it drops the main
runtime-simplicity advantage.

Preferred policy:

```text
cache miss now: run generic floor
cache miss later: use published artifact if SSA job completed
```

---

## 12. Comparison with LuaJIT side traces

LuaJIT:

```text
hot path -> trace
exit -> side trace graft
polymorphism becomes trace tree shape
runtime pays optimizer/emitter cost
```

SponJIT:

```text
region -> signature cache
exit -> observed alternative signature
stable alternative -> offline/background SSA artifact
polymorphism becomes cache entries
runtime pays lookup + copy/patch
```

A LuaJIT side exit says:

```text
this trace was wrong here
```

A SponJIT guard exit says:

```text
this exact alternative fact signature exists here;
compile/cache that if it persists
```

---

## 13. Primary measurements

The load-bearing measurements are about signature stability and convergence.

Measure:

```text
signature dwell time
hits per signature before change
exit reason clustering
cache hit rate by region
cache miss rate by region
artifact publication latency
hits after publication
exit rate before/after publication
megamorphic cutoff frequency
artifact bytes per saved cycle
pack-size/speed curve
```

Critical question:

```text
Do hot exits cluster into a small number of stable alternative signatures?
```

If yes, the design can converge to cached monomorphic artifacts. If no, keep the
region generic/coarse.

---

## 14. Minimal implementation plan

### Phase 1 — observation model

```text
record region id
record cheap fact signature
record guard failures with reason
record dwell time and hit counts
report clustering / megamorphic stats
```

### Phase 2 — cache model

```text
region signature cache
mandatory generic floor
cache hit/miss counters
hysteresis thresholds
megamorphic cutoff
```

### Phase 3 — SSA integration

```text
signature -> FactEnv
FactEnv -> Foundry SSA
SSA -> semantic normal form + artifact candidate
publish candidate into simulated cache
```

### Phase 4 — real materialization

```text
lower SSA-selected atom cover to stencils
copy/patch holes
generate projection stubs
validate dependencies
install artifact
```

### Phase 5 — pack selection

```text
budget <= 50 MB
cycles_saved_per_byte
semantic-normal-form dedupe
retirement / eviction policy
```

---

## 15. Summary

SponJIT is now best described as:

```text
an exit-authored, signature-cached, offline-SSA-specialized copy-and-patch JIT
```

The central loop:

```text
runtime observes facts and exits
  -> hysteresis admits stable signatures
    -> SSA consumes those facts offline/background
      -> artifact templates are published
        -> runtime dispatches by signature and patches holes
          -> served exits disappear; remaining exits drive the next round
```

Facts are the shared currency. SSA consumes them. Artifacts embody them. Guard exits
create new ones. The runtime stays simple because all fact reasoning has one home:

```text
Foundry SSA.
```
