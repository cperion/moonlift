# SponJIT — A Fact-Guided Bytecode Absorption JIT

*the "sponge JIT": it soaks up hot interpreter work in contiguous patches and
leaves the rest as residual.*

**Type:** system architecture description (not a paper).
**Audience:** VM / C / assembly engineers.
**Status:** design, mostly unverified. Claims marked `[UNVERIFIED]` are conjectures
awaiting the experiments in §19. The mechanism is specified to MVP-buildable depth;
the *numbers* do not exist yet.

SponJIT is a runtime compiler for a Lua VM built on one idea:

```text
JIT compilation is bytecode absorption under assumptions —
soaking hot interpreter work into simple native code, in contiguous patches,
guided by facts, leaving complex or unstable work as explicit residual.
A guard is the operation that buys absorbability by spending an exit.
```

Current runtime spine: `SPONJIT_RUNTIME_DESIGN.md`.

That document records the sharpened binding-time split:

```text
SSA is THE fact-consuming layer.
Runtime observes facts/exits, canonicalizes signatures, performs cache lookup,
copy/patches artifacts, and records misses. Runtime does not optimize.
```

This architecture document keeps the broader absorption/tiling vocabulary. The runtime
spine document is the source of truth for the current JIT loop.

The output is not a pure native trace. It is a **mixed plan**:

```text
[native absorber] [residual boundary] [native absorber] [native absorber] ...
```

Unabsorbed bytecode is not failure. It is a residual boundary. If it gets hot, the
runtime absorbs it later.

This also unifies interpretation, baseline compilation, and optimization:

```text
interpreter = the all-residual plan          (0% absorbed)
baseline    = a plan with simple absorbers   (some absorbed)
optimizer   = the same replacement loop run at richer facts
```

Interpretation is not outside the JIT model. It is the zero-absorption state of the
same plan representation. Compilation is local replacement of residual work with
native absorbers. Optimization is repeated replacement where residual pressure remains.

This document unifies two earlier framings — *tiling* (how you cover a region) and
*absorption* (what you optimize). They are one system: **absorption is the objective;
tiling is the mechanism; the residual boundary is the always-legal bail-tile.**

---

## 0. The thesis on one screen

Runtime thesis:

```text
precompile SSA forms offline
  => runtime materialization is copy-and-patch, not compilation
    => re-specialization is cheap enough to do repeatedly
      => guard failures and exits become datapoints, not defeat
        => each stable observed mode gets its own tight monomorphic artifact
          => hysteresis + cache keep the system convergent and economical
```

Absorption vocabulary:

```text
ABSORBER         a native unit that consumes bytecode work under a contract
                 (= a "tile": legal-when, code, facts-out, exits, residual obligations)
RESIDUAL         an explicit decision NOT to absorb yet (= the bail-tile, always legal)
PLAN             a mixed cover of a region: absorbers + residuals, linked
INTERPRETER      the all-residual plan; zero absorption, still the same model
COMPILER         replaces pressured residual spans with absorbers
OPTIMIZER        the same replacement loop after more facts have been bought/observed
THE LOOP         absorb the hottest absorbable boundary; publish a better plan; repeat
```

The two-phase model `translate -> optimize` is rejected. There is one operation,
run at increasing fact-richness:

```text
  poor facts                              rich facts
  ----------                              ----------
  only residual / generic is legal        a specialized absorber becomes legal
  => you "compiled" (translated)          => you "specialized"
                  \                       /
                   same selector, same loop, driven only by the fact set
```

```text
absorption = specialization = compilation, at increasing fact-richness.
a guard turns an observed fact into a proven fact by spending an exit.
absorb what is simple.  residualize what is complex.  revisit what stays hot.
```

### 0.1 Primal and dual

SponJIT is the **dual** of a covering JIT. They measure the same quantity from
opposite sides:

```text
TILING (primal):     count what you BUILD    — native cover; minimize cost(cover)
ABSORPTION (dual):   count what you REMOVE   — interpreter work; minimize residual pressure
                     the residual IS the uncovered part. same thing, opposite sign.
```

Same expressive power (a residual boundary == a generic bail-tile), but the dual
has a better objective (demand-driven: work where hot interpreter work remains) and
a better zero-state (all-residual = the bare interpreter = free). Mixed plans are an
*intended steady state*, not a degraded outcome — which is the whole point for
polymorphic, branch-balanced, and phase-changing code.

---

## 1. The minimal model

The entire engine before any optimization-pressure machinery:

```text
an absorber    = (legal-when: FactMask, cost, code, facts-out, exits, residual obligations)
a residual     = the bail-tile: always legal, "continue in the interpreter here"
a plan         = ordered absorbers + residuals; each absorber legal under running facts
initial plan   = all residuals; this is ordinary interpretation represented in-plan
the loop       = reduce hot residual pressure: absorb the hottest absorbable spot,
                 publish, repeat until stable or budgeted out
why it works:  an absorber produces facts for its neighbor; richer facts make a
                 better neighbor absorbable; repeat. no separate optimizer exists.
```

Five lines. Residency, presence holes, mode caches, in-tile selectors appear
**nowhere** here. Each is a response to a measured problem (§7–§14), absent until a
profiler forces it. A feature earns entry only if it can be phrased as *"this changes
which absorber is legal"* or *"this changes residual pressure."*

### 1.1 The objective (stated once, used everywhere)

```text
minimize:   total_cost = native_plan_cost
                       + hot_residual_pressure      (§7, INCLUSIVE OF SEAM TAX)
                       + exit_pressure
```

The seam tax (§7) is the load-bearing correction over the naive absorption metric,
and it is what makes the sponge absorb in patches instead of speckles.

### 1.2 Interpretation is zero absorption

SponJIT does not sit beside the interpreter as a separate phase. It starts as the
interpreter:

```text
Plan 0 = [residual for everything]
```

Then hot residual spans are replaced in place by absorbers:

```text
[Residual A B C D E]
        │ pressure on B,C
        ▼
[Residual A] [B+C native] [Residual D E]
        │ more facts / more pressure
        ▼
[A+B+C native] [Residual D] [E native]
```

This gives a single continuum:

```text
interpretation  ->  baseline  ->  optimization
0% absorbed     ->  some      ->  more, under richer facts
```

The system must not pay full recording cost all the time. Observation is pressure-triggered:

```text
always-on: cheap hotness / residual counters
burst:     fact recording when pressure crosses a threshold
attached:  guard, exit, and seam counters on compiled plans
off/decay: stable regions reduce or disable counters
```

So "the interpreter is the all-residual plan" does **not** mean "the interpreter is
always tracing." It means the interpreter and compiler share the same plan model,
while fact gathering is sampled and demand-driven.

---

## 2. Relation to existing designs — SponJIT is a generalization, not an alternative

There is a single design space. Its axes:

```text
  tile granularity   (how much one absorber covers: one opcode .. whole region)
  retile budget      (0 = compile once, never repair  ..  >0 = local reabsorption)
  residual policy    (zero-residual-by-fiat  ..  residual is first-class & priced)
```

The known strategies are corners of this space — the *same machine* at different
settings, not analogies:

```text
                          tile granularity
        small ───────────────────────────────────────► large
          │                                              │
   interpreter ──── baseline JIT ──────────── trace JIT (LuaJIT)
   (all-residual    (1 absorber/op,            (1 absorber = whole region,
    plan,            retile=0, no facts)        retile=0, zero residual by fiat)
    absorption=0)
          │
          └──────────────── SPONJIT ────────────────┘
              (window-sized absorbers, retile>0,
               residual first-class & priced, selection-only)
```

A LuaJIT trace **is** an absorption plan whose absorber covers the whole recorded
region and whose residual is forbidden. The mapping is exact:

```text
LuaJIT                          SponJIT at (granularity=region, retile=0, residual=∅)
------                          -----------------------------------------------------
trace = linear hot path     ≡   plan with one whole-region absorber
guard in the trace          ≡   checked-fact on the absorber
SNAPSHOT at a guard         ≡   PROJECTION at an exit            (the same object;
                                LuaJIT delta-encodes snapshots — reuse that, §15)
side exit                   ≡   absorber exit
side trace at a hot exit    ≡   a cached alternative plan (but whole-region)
trace tree                  ≡   the mode/plan cache (max-granularity case)
compile-once                ≡   retile budget = 0
```

### 2.1 The sharp statement of LuaJIT's weakness

```text
LuaJIT has NO CONCEPT OF AN ACCEPTABLE RESIDUAL.
a trace is all-native-or-bail. mixed steady-state is inexpressible.
=> when it cannot absorb everything, it absorbs nothing (trace give-up).
its brittleness is not a bug; it is the price of residual = ∅ by fiat.
```

SponJIT's position — sub-region absorbers, `retile>0`, *priced* residual — is the
unique region of the space that can (a) repair locally and (b) stay mixed. That is
not generality for its own sake; it is aimed exactly at LuaJIT's failure mode.

### 2.2 The one thing LuaJIT has that this tier does not

LuaJIT runs an SSA optimizer **inside** the trace (allocation sinking, CSE,
reassociation, loop-invariant motion) before emission. Those are entangled graph
rewrites (§18) — out of scope for selection-based absorption. So SponJIT-at-the-
corner is *LuaJIT minus its optimizer*. The way you would recover that optimizer is
the §18 escape hatch taken to its limit: a curated super-absorber grown to whole-
region size and synthesized online. The single price of that limit is the one
invariant SponJIT refuses to pay: **online codegen.** The §18 tier boundary and the
no-codegen line (§9.1) are the same line; LuaJIT is on the far side of it.

### 2.3 Open axis: meta-tracing

Meta-tracing (PyPy/RPython: trace the interpreter loop, not the program) appears to
be a **region-formation policy** (a variation of §12.0 / how you record), stacked on
the same granularity/retile/residual axes — not a fourth corner. `[UNVERIFIED]` If
it does not fit those three axes, that reveals a fourth knob worth naming.

---

## 3. Core objects

### 3.1 Absorber (= tile)

```c
typedef uint64_t FactMask;     /* one bit per fact in a fixed vocabulary */
typedef uint32_t AbsorberId;
typedef uint32_t RegionId;

typedef struct {
    AbsorberId id;
    PatternKey pattern;         /* bytecode window / control shape absorbed */

    FactMask   required;        /* must hold at entry (caller guarantees)   */
    FactMask   checked;         /* absorber guards these; true on success    */
    FactMask   produced;        /* true after successful absorption          */
    FactMask   killed;          /* invalidated by this absorber's effects    */

    ExitDesc   exits[MAX_EXITS];/* guard-fail, slow path, branch, call, yield */
    DepDesc    deps[MAX_DEPS];  /* shape / metatable / call-target / ... epochs */

    PatchDesc  patches[MAX_PATCHES];  /* incl. presence + residency holes (§9) */
    ClobberDesc clobbers;       /* residency-kill derives from this (§11)    */
    CostModel  cost;
} AbsorberDesc;
```

Bytes may come from a mined C stencil, hand asm, a raw template, or a curated fused
artifact. **The runtime does not care which** (§9). Copy-and-patch is the
materializer, not the theory.

### 3.2 Residual boundary (= the always-legal bail-tile)

```text
ResidualBoundary = "continue in interpreter / generic VM here, for now"
```

First-class. Carries counters: hit count, cycle estimate, exit-reason distribution,
observed facts, successor info. A cold residual is fine. A **hot** residual is
absorption pressure (§7). Crucially, a residual sitting *between* two absorbers also
carries the cost of two native↔interpreter crossings (§7 seam tax) — absorbing it
deletes those, which is why islands grow by accretion.

### 3.3 Plan

```text
Plan = ordered, linkable sequence of absorbers and residual boundaries

bytecode:   A  B  C  D  E  F  G
plan V0:   [A] [B residual] [C] [D residual] [E] [F] [G]      (all speckles)
plan V1:   [A+B native]     [C] [D residual] [E+F native] [G] (patches forming)
plan V2:   [A+B+C native]   [D residual]     [E+F+G native]   (two saturated patches)
```

A region is successful even while mixed. There is no requirement of one global story.

---

## 4. Facts

Facts are not profiling annotations. They are **boundary summaries that make absorber
composition legal and profitable.** Each must answer: who established it; what role;
in what scope; what kills it; what projection if it fails; which absorbers it unlocks.

### 4.1 The six roles

```text
ObservedFact   from profiling. NEVER sufficient for unsafe code alone.
RequiredFact   must be guaranteed by predecessor / guard / entry.
CheckedFact    validated by this absorber; true ONLY on the success edge.
ProducedFact   created by this absorber's semantics on success.
KilledFact     invalidated by this absorber's writes / effects.
DecisionFact   introduced by choosing a specialized plan; scoped to success path.
```

The guard (§5) is precisely the operator that moves a fact `Observed -> Checked`.

### 4.2 Transfer function

```text
facts_out = (facts_in - killed) + produced + checked_on_success
```

```text
            facts_in
               │
      ┌────────▼─────────┐
      │    ABSORBER       │  required ⊆ facts_in   (else illegal -> residual)
      │  checked guards   │  on success: + checked
      │  effects          │  always:     - killed, + produced
      └────────┬─────────┘
               │ success
               ▼            success facts flow to the next absorber
            facts_out       exit edges carry the PROJECTION, not the facts (§15)
```

### 4.3 Kills are the whole safety story

A produced/checked fact is valid **only until something kills it.** In Lua the kill
set is large: a call may trigger a metamethod that mutates a shape; `setmetatable`
kills a metatable assumption; GC may move/collect. The single correctness invariant:

```text
never let an assumption outlive its kill.
```

Speculative facts outliving one absorber are backed by invalidatable dependencies
(shape epoch, metatable epoch, global-slot epoch, call-target epoch, upvalue version,
proto/code identity, debug-hook state, GC-barrier state). A dependency epoch moving
invalidates or redirects the plan (§12, §17).

---

## 5. The guard — the operation that buys absorbability

```text
A guard is an assumption.  An assumption narrows the world.
Information flows ONE WAY through a successful guard.
```

```text
            observed: "x was i64 in 99% of hits"   (cannot make code safe)
                              │
                         ┌────▼────┐
                         │  GUARD  │  if x is i64 ...
                         └──┬───┬──┘
                  success   │   │   fail
                   (proven) │   │
            x is i64 here ◄─┘   └─► exit: project state, leave (§15)
                              ▲
       the absorbability downstream is PURCHASED by this exit.
       no exit ⇒ no clarification ⇒ the guard absorbs nothing.
```

```text
guard:  ObservedFact  --(spend one exit)-->  CheckedFact
guard_value = absorption_unlocked_downstream - expected_exit_cost
```

```text
BAD guard:  one opcode slightly faster, exits often, no downstream unlock.
GOOD guard: one guard proves type/shape for MANY downstream absorbers.
```

### 5.1 A guard clarifies "the rest" — *until a kill*

The reach of a guard is the span its success edge dominates *before something in the
kill set fires*. This single rule predicts the two key Lua cases (§13):

```text
guard "t is a table, no metatable":  body kills? none.  -> clarifies every iteration. hoistable.
guard "i within array bounds":       body kills? yes — i is the induction var.
                                                          -> clarifies one iteration only.
```

Honest form: *a guard clarifies the rest, up to the next effect that kills the fact;
its value equals how far that reach extends.*

### 5.2 Redundant-guard elimination falls out for free

If guard A produces `x:i64`, a downstream absorber B that *required* `x:i64` has its
requirement met — `A.checked ⊇ B.required` — so B's check is dead and patched out
(§9). "A guard clarifies the rest" and "checked-facts satisfy downstream required-
facts, so downstream checks are deleted" are the same statement. No separate pass.

---

## 6. Absorption waves

The key dynamic: absorbing one unit produces facts that make neighbors absorbable.

```text
gen 0:  [GETTABLE residual] [ADD residual] [RETURN]
observe: table shape stable; key integer; ADD operands integer
gen 1:  [GETTABLE_array_guarded] [ADD_i64] [RETURN]
        facts propagate: GETTABLE result observed integer; ADD result fresh; RETURN consumes it
gen 2:  [GETTABLE_array_guarded + ADD_i64] [RETURN]      (seam absorbed; §7, §11)
gen 3:  [GETTABLE_array_guarded + ADD_i64 + RETURN]      (selection of a curated absorber)
```

No general runtime optimizer. Each step is **selection of a known absorber under
richer facts** — the same machine at higher fact-richness (§0). "Discovery" here is
selection over a finite library, capped by that library, *not* open-ended rewriting.

---

## 7. The absorption metric — residual pressure, inclusive of seam tax

This is the merged objective and the section that resolves the optimal-grain
question both earlier framings circled.

### 7.1 Per-absorber benefit

```text
benefit(absorber) =
      interpreter_work_removed         (dispatches, tag checks, generic semantics,
                                        stack traffic, table-lookup work, call dispatch)
    + downstream_absorption_unlocked   (facts that make neighbors absorbable)
    + seams_deleted · crossing_cost    (see 7.3 — the load-bearing term)
    - native_execution_cost
    - expected_exit_cost
    - materialization_cost
    - code_size_penalty
    - invalidation_risk
    - seams_created · crossing_cost     (see 7.3)
```

### 7.2 Residual pressure — the naive form is WRONG

A residual boundary does not cost one interpreter-opcode. A residual *between two
native absorbers* manufactures two native↔interpreter transitions, each of which is a
full state reconcile (the same machinery as a side exit, §15):

```text
[native ...] │ [residual C] │ [native ...]
             ▲              ▲
        exit→interp     interp→re-enter
        (project state) (re-establish leases / residency)

WRONG:  residual_pressure = Σ_b  freq(b) · interp_cost(b)
RIGHT:  residual_pressure = Σ_b  freq(b) · ( interp_cost(b) + seam_in(b) + seam_out(b) )
                                                            └──── the seam tax ────┘
```

### 7.3 The seam tax makes the sponge self-organize toward the right grain

The seam delta of absorbing a window depends on its *neighborhood*, and this is what
prevents both fragmentation and over-absorption **without a hand-tuned grain knob**:

```text
neighborhood of the window being absorbed        seam delta        verdict
------------------------------------------        ----------        ---------------------------
residual on BOTH sides (isolated in interp sea)   +2 seams created  PENALIZED — absorb only if
                                                                    interp work removed is large
native on ONE side, residual on the other         0 (net)          neutral — judged on work alone
native on BOTH sides (interior residual)          -2 seams deleted  STRONGLY FAVORED — absorbing
                                                                    here removes work AND two crossings
```

Consequences — the dynamics fall out for free:

```text
1. ACCRETION: residuals adjacent to a native island are cheap to absorb (delete a seam),
   so islands GROW BY ACCRETION. the sponge soaks up contiguous patches, not speckles.
   fragmentation (native confetti in an interpreter sea) is self-penalizing.

2. LOWER BOUND on grain: set by the seam tax — do not fragment; isolated absorption rarely pays.

3. UPPER BOUND on grain: set by the no-codegen line (§9.1, §18) — do not grow an island
   past what SELECTION can cover. beyond that you would need synthesis = a trace = LuaJIT.

4. THE GRAIN IS A FIXED POINT, not a tunable: grow islands by accretion until the next
   absorption either does not pay (seam/exit cost wins) or would require synthesis.
```

So the optimal grain — the thing the fusion-vs-locality and the
fragmentation-vs-brittleness tensions both pointed at — is **emergent**: the seam tax
sets the floor, the no-codegen invariant sets the ceiling, and absorption naturally
settles between them. `[UNVERIFIED: that the fixed point is stable across real
workloads — this is exactly what §19 must measure.]`

### 7.4 The accept rule (used by the loop, §12)

```text
absorb a window iff   Δpressure = freq · interp_work_removed
                                + seam_delta(neighborhood) · crossing_cost
                                + downstream_unlock
                                - native_cost - exit_cost - materialization
                      exceeds the hysteresis margin (§12).
```

The neighborhood term is why the loop targets **interior residuals between hot
islands first**: they pay twice (work removed + two seams deleted).

---

## 8. Absorber foundry — fixed arity, recursive basis growth

Runtime SponJIT is a selector/materializer. The broad search happens AOT in an
**absorber foundry**.

The foundry starts from one simple condition:

```text
A₀ = opcode absorbers
```

Then it recursively enriches the atom basis:

```text
for k = 0..K:
    Cₖ = all legal arity≤4 compositions over Aₖ
    Gₖ = semantic graphs produced by expanding Cₖ under candidate facts
    Sₖ = bounded SSA-normalized versions of Gₖ
    Vₖ = contract/projection/dependency-valid candidates from Cₖ ∪ Sₖ
    Pₖ = candidates scored against corpus residual pressure + cost model
    Wₖ = selected winners: profitable, verified, non-dominated
    Aₖ₊₁ = Aₖ ∪ Wₖ
```

This is the scalable trick:

```text
fixed arity, growing basis.
```

Effective opcode span grows because selected sponges become new atoms. The exponent
stays fixed at four.

```text
not:  opcode^8, opcode^16, ...
but:  n₀^4, n₁^4, n₂^4, ... where n grows only by selected winners
```

So the foundry learns a bounded-arity absorber grammar:

```text
opcodes  = alphabet
absorbers = words
higher absorbers = phrases
selected phrases become new vocabulary
```

A selected absorber is just another atom if it exposes the same contract and, for
future foundry layers, a semantic expansion:

```text
runtime identity: bytes/holes/contract/cost            (opaque to runtime)
foundry identity: semantic expansion or SSA summary    (transparent offline)

pattern span; required/checked/produced/killed facts; exits/projection;
dependencies; residency endpoints; cost; code artifact or implementation plan.
```

This split is load-bearing: runtime treats an atom as a black box, but the foundry
can reopen selected atoms and compose their semantics in later layers.

The foundry may enumerate the abstract universe exhaustively at arity≤4 because this
is AOT. It must not realize every tuple as code. It runs a sieve:

```text
1. enumerate opcode/atom tuples arity≤4
2. reject impossible shape/control/effect compositions
3. expand only applicable fact axes
4. expand tuple semantics into a small graph
5. apply facts and build SSA
6. run bounded SSA normalization / simplification
7. lower surviving SSA nodes back to the fixed absorber/stencil vocabulary
8. compose contracts and projections
9. score residual-pressure reduction and seam deletion
10. check lowering/template availability
11. compile/mine/verify only survivors
12. benchmark and export selected winners
```

SSA is not a runtime tier here. It is the AOT foundry's **canonical fact consumer**,
sitting after tuple composition and before scoring. Facts specialize the semantic
graph; SSA turns those facts into consequences; selection interns useful consequences
as absorbers. The output is the same kind of absorber as any other producer emits.

Detailed design: `SPONJIT_FOUNDRY_SSA.md`.

Selection must be brutal to prevent basis pollution. A compound atom is selected only
if it beats composing its children directly and is useful under corpus pressure:

```text
selected iff verified
          and projection-safe
          and profitable vs child cover
          and not dominated by an existing atom
          and code size / exit risk acceptable
          and useful for observed or residual-pressure-predicted workloads
```

### 8.1 SSA as the fact consumer, not a runtime compiler

The smartest place for SSA intelligence is:

```text
AOT foundry, between arity≤4 atom composition and empirical scoring.
```

Too early, on single opcodes, SSA sees too little. Too late, after selection, it may
miss candidates that only become excellent after simplification. At runtime, SSA would
be a different tier. In the foundry, SSA is where facts become executable
consequences.

A bounded SSA producer may do:

```text
DCE / CSE / copy forwarding / constant folding
redundant guard elimination
store-load forwarding
simple invariant guard motion under the kill-set test
recognized-schema bounds elimination
small scalar replacement under a residency/projection budget
```

It must respect hard barriers:

```text
CALL / yield / throw / metamethod / debug-hook / GC-observable boundaries
```

And hard budgets:

```text
register/residency pressure
projection metadata size
code size
exit count and exit projection cost
```

A candidate produced by SSA is selected only if it beats the best cover of its
children. This prevents adding a compound atom that is semantically pretty but not
faster than composing existing atoms.

SSA also gives the foundry a semantic normal form. Different opcode tuples may reduce
to the same optimized graph, so absorber identity can eventually be keyed by:

```text
optimized_semantic_normal_form_hash
```

not just by source opcode pattern. This is how the foundry can learn reusable semantic
sponges instead of overfitting to superficial bytecode spelling.

### 8.2 Implementation backends

Handwritten assembly fits as an implementation backend, not as the search mechanism:

```text
use GCC/C templates and SSA-produced candidates for discovery;
replace with hand asm only for foundational or repeatedly-selected hot atoms/seams.
```

This section is the AOT counterpart of SponJIT's runtime rule:

```text
offline foundry = exhaustive discovery over a bounded local chemistry
runtime SponJIT = bounded selection from the exported absorber basis
```

---

## 9. Materialization — copy-and-patch backend, parameterized absorbers

Materialization must be cheap enough for *repeated local reabsorption*, so the MVP
uses copy-and-patch. But the thesis (§0) is independent of the backend.

### 9.1 The runtime never generates code

```text
RUNTIME does:     observe -> match -> select -> copy -> patch -> link -> publish
RUNTIME does NOT: run GCC/LLVM, synthesize instructions, recombine stencils into
                  new instructions, do general register allocation or peephole codegen.
```

This bright line keeps verification tractable (§17). Crossing it is a *different
engine* (§18), not an extension.

### 9.2 Parameterized absorbers — the variant explosion is an illusion

The "variants" of ADD —

```text
ADD_i64_guarded   ADD_i64_lhs_proven   ADD_i64_no_overflow   ADD_i64_in_rax_out_rax ...
```

— are not different programs. They are one base pattern with independent binary
switches. Promote each *orthogonal* choice to a patch hole:

```c
typedef enum { HOLE_CONST, HOLE_CONT, HOLE_PRESENCE, HOLE_RESIDENCY } HoleKind;

/* one AOT artifact; many behaviors, decision vector supplied at copy time */
typedef struct { AbsorberId base; PatchDesc holes[MAX_HOLES]; } ParamAbsorber;
```

```text
ParamAbsorber ADD =
  base bytes
  + hole[0]: lhs guard      ∈ {present, skip}    <- presence
  + hole[1]: rhs guard      ∈ {present, skip}    <- presence
  + hole[2]: overflow check ∈ {present, skip}    <- presence
  + hole[3]: result boxing  ∈ {present, skip}    <- presence
  + hole[4]: operand in     ∈ {slot, gpr, xmm}   <- residency
  + hole[5]: result out     ∈ {slot, gpr, xmm}   <- residency
  + hole[6]: continuation   ∈ {addr}             <- continuation

   AOT enumerates BASE PATTERNS          (additive, small)
   RUNTIME instantiates DECISION VECTORS (cheap, copy+patch, no codegen)
   product of variants  ->  collapses to  ->  sum of base patterns × hole arities
   N × M fused absorbers ->                ->  N + M endpoints
```

A presence hole patched to `skip` writes a jump-over or relocates a cold region — the
**same primitive** as patching an immediate. **Presence/residency holes are resolved
once at PATCH TIME and emit straight-line code with no internal branch.** They are
*not* runtime selectors (§10), and they do not violate §9.1.

### 9.3 The closing loop: a propagated fact IS a hole value

```text
absorber A produces "lhs proven i64"  ──► patches absorber B's hole[0] to `skip`
```

Fact propagation (§4.2) and materialization (§9) are the same operation seen from two
sides. A propagated fact is the value you patch into a downstream decision hole.

### 9.4 Footprint and clobber are functions of the decision vector

```text
1. disabled subsections must NOT sit inline as nops (wastes i-cache).
   disable = branch to a cold-split region. AOT producer emits optional regions as
   patchable branch points (cf. LLVM patchpoints / stackmaps).
2. ClobberDesc is NOT constant: skip the overflow check -> its flags clobber vanishes;
   disable a guard -> its scratch reg frees. clobbers (and exit projection, §15) are a
   function of the realized decision vector. small lookup, but parameterized.
```

### 9.5 Patch holes (catalogue)

```text
bytecode operands; stack-slot offsets; constants; continuation addresses;
side-exit targets; slow-path data pointers; dependency/version cells;
presence holes (patch-time specialization); residency holes (§11);
optional branch-to-fallthrough link glue (the only "rewrite", §18.2).
```

---

## 10. Binding times — corrected: selectors are a special case, not a default

A specialization decision can bind at three times. **Two are first-class; the middle
one is demoted.** This corrects the earlier "three co-equal bindings" framing.

```text
bound at AOT       -> enumerate base patterns                (the absorber library)
bound at PATCH     -> presence / residency / const hole       (resolved once, §9) — FIRST-CLASS
bound at RUNTIME   -> in-tile selector: a live branch on facts inside the code — DEMOTED
```

### 10.1 Why the runtime selector is demoted — the absorption metric makes it legible

```text
an in-tile selector that switches on facts is a SMALL INTERPRETER.
native code shaped  if i64 ... else if f64 ... else residual  has RE-IMPLEMENTED
bytecode dispatch in native code — the exact work absorption exists to remove.
under the residual-pressure metric (§7), its internal branches count as
UN-ABSORBED DISPATCH. it is negative absorption. the metric discourages it automatically.
```

The covering framing hid this (a branch is just a branch); the absorption framing
exposes it. So the default is:

```text
stable simple case            -> specialized absorber + side exit
unstable / high-entropy case  -> residual boundary
genuine local low-arity        -> inline cache / curated meta-absorber  (ONLY here)
   persistent polymorphism
```

### 10.2 When a selector IS allowed (the inline-cache exception)

Some sites are reliably *bimorphic* and *simultaneously* hot (not phase-separated): a
residual throws away both fast paths; a mode-split (§14) thrashes because both modes
are hot at once. A 2-way IC branch is then genuinely optimal. Permitted iff:

```text
- polymorphism is LOW-ARITY, LOCAL, and PERSISTENT, and
- the branch is measurably cheaper than the exit it replaces, and
- it is structured as an inline cache (shape IC, call-target IC; numeric i64/f64
  only if measurement proves it).
Rule: do not route inside an absorber unless the branch beats exiting AND the
      polymorphism is local, low-arity, persistent. measurement-gated, never default.
```

### 10.3 The three are one idea at three granularities

```text
monomorphic specialization (baked) = an inline cache with one case
in-tile selector (IC exception)    = a polymorphic inline cache
plan mode (§14)                    = a region-level cache
```

---

## 11. Residency as a first-class fact — the seam absorber

Most non-algebraic wins are **deleted seam traffic** (§7). When ADD writes slot R2 and
RETURN1 reloads it, the whole win is deleting that store/reload. You don't need a
fused instruction — you need the two absorbers to *agree on where the value lives.*

```text
type fact:        "R2 is i64"
residency fact:   "R2 is live in rax, unboxed, freshly produced"

RETURN1 ships residency variants (hole[in] ∈ {slot,gpr}); the selector picks the
rax-consuming variant exactly when the producer advertises rax residency.
the store and reload are never emitted. still select/copy/patch/link. no codegen.
```

```text
[ADD_i64 -> rax] [RETURN1 <- rax]      seam is free; nobody emitted the traffic
needs each op in {in: slot|gpr} × {out: slot|gpr} variants (ADDITIVE, §9.2)
```

Residency is how the §7 seam tax actually gets *paid down*: it is the mechanism that
turns a –2-seam accretion opportunity into deleted instructions.

### 11.1 Residency is the dual of ClobberDesc

```text
type fact:       sparse kills, long live range (killed only by a write to R2)
residency fact:  DENSE kills, short range (killed by ANY absorber clobbering rax)
```

So residency-kill is **not hand-authored** — it falls out of `clobbers` (§9.4),
reindexed by location instead of value. Produced-residency = the exit convention;
killed-residency = the clobber set. First-class residency adds no maintenance burden.

### 11.2 The tiler is now a register allocator — so pin the convention

```text
absorbers ADVERTISE a small fixed set of residency contracts (calling-conv variants).
the selector MATCHES advertised endpoints. it does NOT SEARCH allocations.
(searching => DP state includes the register file => exponential.)
the convention does the allocator's work offline; the runtime stays a matcher.
```

### 11.3 Residency as a lease — the correctness spine

```text
every live value's source of truth is ALWAYS its canonical stack slot.
a register is a LEASE on top of that home.
invariant: at any observation point (exit, re-entrant call, yield, debug hook, GC
           safepoint), every outstanding lease is reconciled to its slot OR recorded
           in the exit projection so the stub reconciles it.

=> residency NEVER makes the hot path slower than slot-always:
   value consumed before any observation point -> store/reload never existed (pure win)
   value crosses one -> pay a reconcile == exactly what slot-always paid.
   the entire price is concentrated in EXIT METADATA. bounded per absorber.
```

### 11.4 Residency is projected OUT of the cache key

```text
type      = a MODE. part of region identity. belongs in FactSignature (§14).
residency = an implementation detail of ONE plan. canonicalize it away before the key.
WRONG: cache Plan(i64, R2-in-rax) and Plan(i64, R2-in-rcx) as distinct -> fragmentation.
RULE:  residency propagates through the selector like a fact, but is excluded from FactSignature.
```

### 11.5 Honest constant

Residency is `{slot, gpr, xmm}` plus oddities (gpr-pair, fixed regs for div/shift).
Library growth is "classes × operands" — still additive, still offline, not literally
×2. Window size is bounded by register pressure (fine for 2–8 ops on x86-64).

---

## 12. The reabsorption loop and why it terminates

### 12.0 Region formation (Pass 0)

A hotness counter (backedge / call site) trips; record forward from the trigger pc
appending `(pc, op, operands)` until a stop (cold branch, size cap, un-inlined call,
or loop closure). Output is an ordered bytecode run — the substrate, not yet a plan.

### 12.1 Non-monotone facts force a convergence rule

```text
exits RETRACT facts (a failing guard kills a downstream-relied-on fact),
so the fact lattice is NON-MONOTONE and the fixpoint can oscillate.
=> the loop is not self-terminating. it needs a damping rule.
   HYSTERESIS IS THAT RULE — a termination condition, not an optimization trick.
```

```text
specialize    if benefit high and stable     e.g. success > 80% over N hits
despecialize  only after sustained failure   e.g. success < 55% over M hits, M > N
the gap between thresholds prevents ping-pong.
```

### 12.2 "Cheapest plan" is aspirational — it is a local fixpoint

```text
1. the objective (§7) has NON-LOCAL terms (seam delta couples neighbors; invalidation
   risk couples absorbers sharing a dep epoch; hysteresis is a property of the SWITCH).
   => optimal substructure fails => no global optimum from a local DP.
2. local reabsorption is ORDER-DEPENDENT (§13): A-before-B ≠ B-before-A.
honest slogan: not "the cheapest plan," but
   "a cheap, stable plan reachable by local reabsorption from where we started."
```

### 12.3 The cover DP (mechanism for one window), local cost only

State is `(position × fact-signature)` — two covers reaching a pc with different facts
unlock different absorbers; signatures are coarse (§11.4) so the product stays tiny.

```text
best[(0, entry_sig)] = (empty, 0, entry_facts)
for each reachable (i, sig):
  facts_i = best[(i,sig)].facts
  for each absorber t legal at i (t.required ⊆ facts_i), incl. the residual bail-tile:
     j        = i + t.covered_len
     facts_j  = transfer(facts_i, t)
     cost_j   = best[(i,sig)].cost + LOCAL_cost(t)   # cycles + exit_prob·exit_cost + size
     relax best[(j, signature_of(facts_j))]
window_plan = argmin over sigs of best[(n, sig)]
```

The DP uses **local cost only**. The non-local terms — seam delta (§7.3), invalidation
risk, hysteresis — are applied at the **accept gate** (§12.4), never inside the DP.
This is what keeps the DP an honest DP and resolves the old per-plan-vs-per-switch
hysteresis contradiction: hysteresis lives at the switch.

### 12.4 The loop

```text
while region hot and budget remains:
    execute current plan; collect residual pressure (§7), exit reasons, observed facts
    spot   = choose_max_pressure_boundary(region)   # interior residuals between hot islands first (§7.3)
    window = expand_around(spot, max_ops = K)        # K in 2..8 for MVP
    facts  = facts_at_window_entry(window)
    plan   = cover_dp(window, facts)                 # §12.3, local cost only

    if Δpressure(plan, window) > hysteresis_margin:   # §7.4 + §12.1, with SEAM DELTA
        materialize(plan)                             # §9 copy/patch/link
        publish_plan_patch(region, window, plan)      # §14.1 atomic
        cache_by_fact_signature(plan)                 # §14
    else:
        keep_residual_or_raise_threshold(spot)
```

Bounded, not an unbounded optimizing compiler.

### 12.5 Bounding enumeration

```text
max window / max absorbers per cover; preindexed selector tables keyed
(PatternKey, FactSignature); reject absorbers whose deps are unstable; prefer observed
signatures; cap code size + materialization budget per slice. worst case is bounded.
```

---

## 13. Fact-flow direction and loops

```text
do facts flow STRICTLY FORWARD along the cover, or can an absorber constrain its predecessor?
forward-only  => locality holds; the loop stays local; the model stays ~5 lines.
backward flow => predecessor constraints => a real fixpoint solver => locality lost.
```

MVP chooses **forward-only along straight-line covers.** Loops break the clean version
(the backedge carries invariants backward) and cannot be dodged for Lua.

### 13.1 The loop rule: establish-at-header + presence-skip-in-body

```text
1. select a loop-header absorber that ESTABLISHES the invariant fact once at entry
2. the fact propagates across the backedge — survives iff nothing in the body kills it
3. patch the body absorber's guard PRESENCE hole to `skip` (§9)
"hoist the guard" was never a code move. it is "assert once at the header + toggle off
 the redundant re-checks." the fact lattice carries invariance across the backedge.
```

### 13.2 The kill-set test splits the free hoist from the tier boundary

```text
for i = 1, n do  s = s + t[i]  end

guard "t is a table, no metatable":  ⋂ body kills = ∅  -> loop-invariant by the machinery.
                                                          FREE HOIST (presence-skip in body).
guard "i within array bounds":       i is the IV; each iteration KILLS "i in range".
                                                          NOT hoistable by facts. needs IV-range
                                                          reasoning. => TIER BOUNDARY (§18).
```

The kill-set emptiness test is the **decision procedure** for which half a guard falls
into — mechanical, not judgment. Type/shape invariance hoists for free; array
bounds-check elimination is a separate analysis and is out of scope.

---

## 14. Mode caching — region-scale inline cache

Some regions have modes, not a single best plan. A trace JIT reads this as
instability and gives up; SponJIT caches alternatives keyed by fact signature.

```text
Region R cache:
  signature i64-heavy        -> Plan A
  signature f64-heavy        -> Plan B
  signature table-shape-17   -> Plan C
  unknown / high-entropy     -> Plan G (mostly residual)

inline cache: one SITE caches cases.   SponJIT: one REGION caches absorption plans.
```

Switching to a cached mode is selection, not regeneration. Signatures contain **type
modes only — never residency** (§11.4).

### 14.1 Plan versions

```c
typedef struct PlanVersion {
    RegionId            region;
    uint32_t            generation;
    FactSignature       signature;     /* type modes only; residency excluded */
    /* mixed cover: */ AbsorberId     *units;  ResidualMap residuals;
    void               *entry;
    ExitCounters        exits;   HitCounters hits;   ResidualPressure pressure;
    DependencySet       deps;
    struct PlanVersion *fallback;
} PlanVersion;
```

```text
- published plans are IMMUTABLE
- plan switching / patching is ATOMIC w.r.t. executing threads & coroutines
- old plans stay valid until no frame can return to them
- invalidation redirects to fallback / interpreter BEFORE freeing code
```

---

## 15. Projection / deopt — the real cost, and the seam cost are the same object

Every exit AND every native↔residual seam (§7) must reconstruct lower-tier state.
This is where speculative JITs sink most complexity; it is budgeted, not waved away.

```text
a side exit OR a seam crossing must reconstruct:
  resume pc; frame/base/top; live stack slots; pending call/return state;
  dirty register leases (reconcile to slots, §11.3); materialized values for any
  skipped/reordered work; debug/error/yield observability state.
if projection is not known, the absorber is ILLEGAL.
```

Reuse LuaJiT's trick: **delta-encode projections between guards** so reconstruction is
cheap (§2). Residency adds a bounded "materialize live registers to slots" prologue to
each register-resident exit (it is the inverse of the residency contract, §11.3).

```text
KEY UNIFICATION: a seam crossing IS a projection. this is why the §7 seam tax is real
and quantifiable — its cost is exactly the projection cost you already must compute.
```

---

## 16. Runtime architecture

```text
OFFLINE (build time) — the expensive work:
  - generate parameterized base absorbers (§9.2)
  - compile C/asm templates; mine bytes, relocations, holes, hot/cold sections
  - VERIFY each absorber contract against its semantic expansion (§17)
  - benchmark/estimate costs; export library + selector metadata
    (preindexed by PatternKey, FactSignature)

RUNTIME — selection and linking only:
  1. execute current mixed plan (initially: the all-residual interpreter plan)
  2. collect cheap always-on counters; burst-record facts only when pressure justifies it
  3. collect: hits, guard fails, exit reasons, residual pressure (§7), observed facts, dep invalidations
  4. pick max-pressure boundary (interior residuals first)
  5. cover-DP a local window (§12.3)
  6. materialize: copy -> patch decision vector -> link (§9)
  7. publish PlanVersion (atomic, §14)
  8. revisit only when counters justify it (hysteresis, §12)
```

```text
   ┌──────────────────────┐
   │ Interpreter / Plan N  │  (mixed: native islands + residual sea)
   └──────────┬───────────┘
              │ residual pressure, exits, facts (§7)
              ▼
     ┌──────────────────┐
     │ Pressure Analyzer │  finds hottest interior residual / bad seam
     └────────┬─────────┘
              ▼
     ┌──────────────────┐
     │ Cover DP + Gate   │  §12: local DP, then seam/hysteresis accept-gate
     └────────┬─────────┘
              ▼
     ┌──────────────────┐
     │ Copy/Patch/Link   │  §9: fill holes (incl. facts->presence, residency)
     └────────┬─────────┘
              ▼
     ┌──────────────────┐
     │ Publish Plan N+1  │  §14: atomic, cached by signature; islands grow by accretion
     └──────────────────┘
```

---

## 17. Correctness invariants

```text
CORRECTNESS
  - interpreter semantics are the source of truth
  - every absorber contract is verified OFFLINE against its semantic expansion
  - every guard failure has a precise exit + projection (§15)
  - every speculative dependency is recorded and invalidatable (§4.3)
  - debug hooks, errors, yields, metamethods, GC barriers are never skipped
  - an assumption never outlives its kill (§4.3)
RUNTIME SIMPLICITY
  - runtime never runs a compiler or synthesizes instructions (§9.1)
  - runtime only: select, copy, patch (incl. decision vector), link, publish
  - enumeration + reabsorption budgets are bounded (§12.5)
PLAN MANAGEMENT
  - plan versions immutable once published; switching atomic
  - old plans valid until unreachable; invalidation redirects to fallback before freeing code
MEASUREMENT
  - reabsorption is driven by residual pressure (§7), not hope
  - hysteresis prevents oscillation AND is the loop's termination condition (§12.1)
  - code size + materialization + SEAM cost are part of the score
  - a specialized absorber with a high exit rate is WORSE than a residual boundary
```

---

## 18. The tier boundary — what is out of scope, and why that is a strength

Entangled rewrites change the data-dependence graph; no decision vector expresses
them. They are the **ceiling** of selection-based absorption, not open questions.

```text
OUT OF SCOPE for the selector:
  allocation sinking / escape analysis;  general CSE;  reassociation;
  induction-variable range proof;  full bounds-check elimination;
  arbitrary graph rewriting;  global register allocation.
```

```text
WHAT SPONJIT IS:  a baseline-plus / strong mid-tier absorption engine.
  absorbs: dispatch, boxing, tag guards, residency/seam traffic, redundant-check
           elision, INVARIANT TYPE/SHAPE guard hoisting (§13.2), polymorphic sites (ICs).
  with:    zero runtime codegen; every emitted byte proven correct before run.
WHAT IT IS NOT:  a trace optimizer. it does not beat allocation sinking + reassociation,
                 and must not pretend to. that is LuaJIT's tier (§2.2), past the no-codegen line.
```

### 18.1 Buying back single cases without opening the door

```text
ALLOWED:   buy back named, individually-verified CURATED SUPER-ABSORBERS as artifacts,
           for specific hot shapes (most likely the loop-invariant BOUNDS check, §13.2 —
           the type half already hoists for free).
FORBIDDEN: general runtime composition that COMPUTES new instructions. the instant a
           "peephole" computes rather than deletes/substitutes, you have shipped a code
           generator: verification collapses, projection must reconstruct across unproven
           code, W^X / JIT-spray surface appears. that is a different engine (§2.2).
```

### 18.2 The link-time peephole catalogue (the only "rewriting" allowed)

```text
PERMITTED:  a FIXED, offline-VERIFIED catalogue that only DELETES or SUBSTITUTES from a
            pre-proven set:  erase jmp-to-fallthrough;  elide dead-store-then-reload at a
            seam (residency, §11).
FORBIDDEN:  any transform that COMPUTES an instruction from operands.
the bright line: deletion/substitution from a verified catalogue = link glue.
                 computation = codegen = a different engine.
```

---

## 19. MVP

Prove SponJIT as an absorption engine, not a full optimizing compiler.

### 19.1 Absorber library (parameterized base patterns, not a variant list)

```text
L0 generic:    MOVE LOADK LOADI LOAD{TRUE,FALSE,NIL} RETURN1 JMP TEST/JMP   (+ the residual bail-tile)
L1 specialized: ADD_i64 SUB_i64 MUL_i64 LT_i64 EQ_i64
                GETTABLE_array_guarded  GETFIELD_shape_guarded  CALL_known_boundary
L2 curated:    ADD_i64_RETURN1  LT_i64_BRANCH  TEST_JMP  GETTABLE_array_i64_ADD_i64
```

### 19.2 Runtime MVP

```text
- linear hot-region recorder (§12.0)
- mixed plan representation (absorbers + first-class residuals)
- per-boundary residual-pressure counters INCLUSIVE OF SEAM TAX (§7.2)
- simple fact signatures: integer-ness, table shape, known call target (NOT residency)
- cover-DP over (position × signature), windows of 2..8 ops, local cost (§12.3)
- copy-and-patch materializer with const/continuation/presence/residency holes (§9)
- mode cache keyed by type signature, with hysteresis (§12, §14)
- interpreter fallback with correct projection + lease reconcile (§15)
```

### 19.3 Workloads — they tell you which engine you built

```text
(1) numeric counted loop over an array   s = s + t[i]
      measures the BOUNDS-CHECK ceiling specifically (everything else you already get).
      expect: good, with a NAMEABLE ceiling at the IV-range boundary (§13.2).

(2) method-dispatch-heavy object loop     obj:method() in a loop
      shape-IC + known-call-target; almost purely orthogonal.
      expect: the SHOWCASE. cleanest test of "a produced fact enables a later absorber":
      does the shape-guard's produced fact flip the next window to a known-call-target absorber?

(3) allocation-churny table/closure code
      feels the absence of allocation sinking most.
      expect: tells you whether the §18 boundary is comfortable or painful for real workloads —
      i.e. whether you ever need the next tier.
```

### 19.4 Initial training corpus

The first foundry training set is deliberately small and complementary:

```text
AWFY      numeric loops, algorithmic kernels, table loops, branch/loop motifs
Moonlift  real compiler workload: AST/ASDL traversal, modules, tables, strings,
          builder APIs, validation passes, method/call-heavy compiler code
```

This is enough to train the first absorber basis without turning corpus curation into
its own project. AWFY prevents the basis from becoming only application/table shaped;
Moonlift prevents it from becoming only benchmark/numeric shaped.

The shadow simulator has a single command for this initial corpus:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua suite-initial \
  --awfy-root experiments/lua_interpreter_vm \
  --moonlift-root lua/moonlift \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_initial \
  --max-files 200 \
  --max-regions 50 \
  --fact-mode balanced
```

It can also run a hypothetical recursive foundry training loop where selected
proposals become abstract atoms for the next layer:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua foundry-initial \
  --awfy-root experiments/lua_interpreter_vm \
  --moonlift-root lua/moonlift \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_foundry \
  --max-files 100 \
  --max-regions 30 \
  --layers 3 \
  --layer-cap 12 \
  --fact-mode balanced
```

This does not prove native code exists. It validates the economics of:

```text
selected winners -> new atoms -> next layer arity≤4 search
```

before implementing the real foundry/materializer.

It writes:

```text
build/sponjit_shadow_initial/awfy/suite_report.md
build/sponjit_shadow_initial/moonlift/suite_report.md
build/sponjit_shadow_initial/combined/suite_report.md
build/sponjit_shadow_initial/combined/miss_report.json
```

The combined miss report is the input to the absorber proposal step:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua propose \
  --miss-report experiments/lua_interpreter_vm/build/sponjit_shadow_initial/combined/miss_report.json \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_initial/proposals
```

This treats absorber selection as model training:

```text
training data      = AWFY + Moonlift bytecode/fact pressure
model parameters   = selected absorber basis + costs + selector metadata
training objective = minimize residual pressure under correctness gates and cap
```

Later corpora can be added as validation or holdout sets, but they are not required
for the first foundry loop.

### 19.5 Success criteria

```text
1. mixed native/residual plans execute correctly
2. local absorption reduces residual pressure WITHOUT recompiling the whole function
3. a PRODUCED FACT enables a later absorber not selected in generation 0
4. ISLANDS GROW BY ACCRETION (interior residuals absorbed first; no confetti) — validates §7.3
5. cached modes avoid repeated recompilation on polymorphic behavior
6. hysteresis prevents plan thrash on a phase-changing workload
7. side exits and dirty residency leases project correctly
8. AWFY + Moonlift combined reports identify concrete next absorber proposals
```

---

## 20. Worked examples

### 20.1 Arithmetic return

```text
pc0: ADD R2,R0,R1   pc1: RETURN1 R2
gen0: [ADD residual] [RETURN1 residual]            (observe R0,R1 i64 ~99%)
gen1: [ADD_i64_guarded] [RETURN1]                  (observed -> checked; §5)
gen2: [ADD_i64 -> rax] [RETURN1 <- rax]            (residency seam absorbed; §11)
 OR   [ADD_i64_RETURN1]                            (curated L2; §6)
if i64 guard failures later rise: keep i64 plan for integer mode, fall to generic for the rest (§14)
```

### 20.2 Table access + arithmetic (absorption wave)

```text
pc0: GETTABLE R2,R0,R1   pc1: ADD R3,R2,R4   pc2: RETURN1 R3
gen0: [GETTABLE residual] [ADD residual] [RETURN1]
observe: R0 table@shape17; R1 int; array hit; no metatable; result int; R4 int
gen1: [GETTABLE_array_guarded] [ADD_i64_guarded] [RETURN1]
      GETTABLE success -> R2 from array; ADD success -> R3 i64 fresh; RETURN1 consumes R3
gen2: [GETTABLE_array_i64 -> rax] [ADD_i64 <- rax -> rax] [RETURN1 <- rax]   (seams absorbed)
if shape alternates 17/23 -> mode cache: Plan A(17) / Plan B(23) / Plan G(generic) (§14)
reached by FACT PROPAGATION ENABLING SELECTION, not by synthesizing code.
```

### 20.3 The loop (free hoist + the boundary)

```text
for i = 1, n do  s = s + t[i]  end
header: [loop_header: establish "t table, no metatable"]            (§13.1)
body:   [GETTABLE_array <- (i bounds CHECKED here)] [ADD_i64] [backedge]
        ^ "t table" PRESENCE-skipped in body: fact survived the backedge (kill-set ∅). FREE HOIST.
        ^ "i in bounds" CANNOT skip: i kills it each iteration. per-iteration check unless a
          curated bounds super-absorber is bought back (§18.1). TIER BOUNDARY.
```

### 20.4 A mixed plan and the seam tax (the new reasoning)

```text
region:  A  B  C(metamethod-heavy GETTABLE)  D  E
gen0:    [A res][B res][C res][D res][E res]                 all residual; pressure spread out
gen1:    [A+B native][C residual][D+E native]                two islands; C interior between them
   note: C is now an INTERIOR residual -> it pays the seam tax TWICE (in + out, §7.2)
         so C's residual pressure is HIGH even if C's interp cost is modest.
gen2 candidate: absorb C with a shape-guarded absorber + side exit on metamethod
   Δpressure = freq·interp(C) + 2·crossing_cost (two seams DELETED) + downstream_unlock
             - native(C) - exit_cost(metamethod) - materialization
   if metamethods are rare on C, the 2-seam deletion alone likely justifies absorbing it,
   MERGING the two islands into one:  [A+B+C+D+E native]
   if metamethods are frequent, C stays residual: a stable mixed plan (§2.1), not a failure.
this is §7.3 accretion in action: the sponge fills the gap between two patches first.
```

---

## 21. Summary

```text
THE IDEA (load-bearing, survived every simplification):
  JIT compilation is bytecode absorption under assumptions.
  interpretation is the all-residual plan — zero absorption in the same model.
  absorption = specialization = compilation, at increasing fact-richness — one operation.
  a guard turns an observed fact into a proven fact by spending an exit.
  SponJIT is the DUAL of a covering JIT: it minimizes work REMOVED, not code BUILT.

THE GENERALIZATION:
  interpreter / baseline / LuaJIT are corners of one space (granularity × retile × residual).
  LuaJIT's defining limit: it has NO ACCEPTABLE RESIDUAL — all-native-or-bail.
  SponJIT's first-class, PRICED residual is the axis LuaJIT lacks; mixed plans are a stable state.

THE MECHANISM (added only as measured problems demanded it):
  - facts: six roles; kills bound their reach
  - orthogonal specialization = patch-time decision holes on parameterized base absorbers
    (product collapses to a sum; a propagated fact IS a hole value)
  - binding times: bake (patch-time) and plan-mode (region cache) are first-class;
    the runtime selector is DEMOTED to a measurement-gated inline-cache special case,
    because the absorption metric makes internal dispatch legible as negative absorption
  - residency: a lease over a canonical home; dual of clobber; additive; out of the cache key;
    it is the mechanism that pays down the seam tax
  - the reabsorption loop is a LOCAL fixpoint over NON-MONOTONE facts;
    hysteresis is its termination condition, not a feature
  - facts flow forward; loops hoist invariant TYPE guards for free; the kill-set test
    exposes the bounds-check TIER BOUNDARY

THE OBJECTIVE (the merge's center):
  minimize freq-weighted residual pressure INCLUSIVE OF SEAM TAX.
  a seam (native<->residual crossing) IS a projection, so its cost is real and quantifiable.
  the seam tax makes the sponge self-organize: islands GROW BY ACCRETION (interior residuals
  absorbed first), fragmentation is self-penalizing, and the optimal grain is an EMERGENT
  FIXED POINT — floored by the seam tax, ceilinged by the no-codegen line — not a tuned knob.

THE BOUNDARY (a strength):
  entangled graph rewrites (BCE, allocation sinking, reassociation) are out of scope,
  bought back only as individually-verified curated super-absorbers. runtime never computes
  an instruction. that boundary is the line LuaJIT sits on the far side of.

STATUS:
  internally coherent; UNVERIFIED. run the §19.4 AWFY+Moonlift initial corpus first.
  if a shape-guard's produced fact flips the next window's selector on real bytecode,
  islands grow by accretion rather than confetti, and the combined miss report produces
  concrete absorber proposals, the thesis is demonstrated, not asserted.
```

```text
Absorb what is simple.  Residualize what is complex.  Revisit what stays hot.
A side exit is not a failure — it is a demand signal for residualization or another absorber.
A guard clarifies the rest — until something kills it.
The sponge soaks up contiguous patches and leaves the rest explicit.
```
