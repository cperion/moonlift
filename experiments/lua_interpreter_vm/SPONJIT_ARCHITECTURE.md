# SponJIT — A Fact-Guided Bytecode Absorption JIT

*the "sponge JIT": it soaks up hot interpreter work in contiguous patches and
leaves the rest as residual.*

**Vocabulary mapping for implementors:**

```text
Conceptual term      Implementation term
---------------      -------------------
absorber / tile      TileTemplate (prebuilt in bank) / TileInstance (patched into an image)
residual             residual tile (L0 floor) / interpreter boundary
plan                 Image (one per region, immutable, swapped atomically)
reabsorption         re-selection from the bank on demotion
absorption pressure  residual pressure + seam pressure
bank                 the read-only, offline-built library of all tile templates
floor                the always-installed L0 image of a region
```

**Bank/Image invariant:**

```text
BANK  = read-only TileTemplate / stencil library, built offline by the foundry
IMAGE = runtime-materialized executable cover, produced by tiling a region with
        TileTemplates from the bank and copy-patching them into code memory

The bank never contains images. It contains the vocabulary.
An image is the installed sentence assembled from that vocabulary.
```

**Type:** system architecture description (not a paper).
**Audience:** VM / C / assembly engineers.
**Status:** design, with the foundry partially built (≈6.5 K real stencils emitted
to .o files; runtime selection pending). Claims marked `[UNVERIFIED]` are conjectures
awaiting the experiments in §19. The mechanism is specified to MVP-buildable depth;
the *numbers* do not yet exist for the runtime.

SponJIT is a runtime compiler for a Lua VM built on one idea:

```text
JIT compilation is bytecode absorption under assumptions —
soaking hot interpreter work into simple native code, in contiguous patches,
guided by facts, leaving complex or unstable work as explicit residual.
A guard is the operation that buys absorbability by spending an exit.
```

The runtime spine (`SPONJIT_RUNTIME_DESIGN.md`) records the binding-time split:

```text
SSA is THE fact-consuming layer, offline.
The foundry enumerates and exports a read-only bank of fused tile templates.
Runtime holds floor + active per region plus small tile-site memory. It observes
facts under hysteresis, greedily selects tile templates from the bank, copy-patches
them into an image, and atomically swaps active. Runtime does not optimize or emit
code. Its only adaptation is bounded re-selection from prebuilt bank candidates.
```

The output for any region is not a pure native trace. It is a **mixed image**
materialized from bank tile templates:

```text
[L3 native tile] [L0 floor tile] [L2 native tile] [L1 native tile] [L0 floor tile] ...
```

Unabsorbed bytecode is not failure. It is an L0 tile in the image — the same kind
of stencil a per-op baseline JIT would emit. When facts stabilize and the bank
covers the new signature, a richer tile replaces it on the next image build. When a
rich tile exits, that does not condemn the whole image: the failed span walks down
its candidate ladder. If no weaker same-span tile works, the span splits; at arity
1, L0 is guaranteed.

This unifies interpretation, baseline, and optimization:

```text
interpreter equivalent = all-L0 image                          (0% absorbed)
baseline               = image with mostly L0 + a few L1 tiles (some absorbed)
optimizer              = the same image with L2/L3/multimorphic tiles selected
                         from the bank under richer facts
```

L0 is not outside the JIT model. It is the zero-absorption state of the same image
representation. Composition is local replacement of L0 tiles with higher-arity bank
tiles. Optimization is repeated re-selection where residual pressure remains and
the bank covers it.

This document unifies two earlier framings — *tiling* (how you cover a region) and
*absorption* (what you optimize). They are one system: **absorption is the objective;
tiling is the mechanism; the L0 floor is the always-legal bail-tile.**

---

## 0. The thesis on one screen

Runtime thesis:

```text
precompile fused tile templates offline into a read-only bank
  => runtime materialization is copy-and-patch from bank templates, not compilation
    => optimistic greedy selection starts coarse and fact-rich
      => guard failures and exits become local fact deltas for the failed span
        => the span moves down/sideways in its candidate ladder, or splits
          => stable areas remain coarse; polymorphic articulations become fine
            => L0 totality + hysteresis keep the system convergent and correct
```

Absorption vocabulary:

```text
ABSORBER         a native tile that consumes bytecode work under a contract
                 (legal-when, code, facts-out, exits, residual obligations)
L0 / FLOOR       the base layer: raw PUC opcode tiles of arity 1..4, always enough
                 to cover a region; arity-1 L0 is total over all opcodes
L{k+1}           tiles formed by composing arity 1..4 tuples of L{k} atoms
                 (so max raw span grows 4x per layer)
IMAGE            an immutable, atomically-publishable cover of a region: a sequence
                 of tiles/meta-tiles each drawn from some bank layer
BANK             the read-only library of tile templates and meta-tile templates
INTERPRETER      conceptually the all-L0 image; zero absorption; still the same model
RUN              execute current image; collect counters; eventually re-select
RE-SELECT        on exit or hysteresis re-trigger: build a new image from bank templates,
                 preserving old choices except spans whose facts changed
THE LOOP         observe -> greedy select -> materialize -> run -> exits train local ladders -> reselect
```

**Important terminology rule:** layers are **recursive composition depth**, not raw
opcode arity. The arity bound is always 1..4 at every layer; what changes is the
atom being composed.

```text
L0 atom = raw opcode tile, arity 1..4 over PUC opcodes
L1 atom = composition of 1..4 L0 atoms        (up to 16 raw ops)
L2 atom = composition of 1..4 L1 atoms        (up to 64 raw ops)
L3 atom = composition of 1..4 L2 atoms        (up to 256 raw ops)
...
```

A failed higher-layer tile descends to its child metaops; if needed the descent
continues until L0 arity-1, which is total.

The two-phase model `translate -> optimize` is rejected. There is one operation,
run at increasing fact-richness:

```text
  poor facts                              rich facts
  ----------                              ----------
  generic L0/L1 covers                     richer same-layer or higher-layer metaops
  => you "compiled" (translated)          => you "specialized"
                  \                       /
                   same selector, same loop, driven only by the fact set
```

```text
absorption = specialization = selecting TileTemplates from the bank at increasing fact-richness.
a guard turns an observed fact into a proven fact by spending an exit.
absorb what is simple.  residualize what is complex.  revisit what stays hot.
```

### 0.1 Primal and dual

SponJIT is the **dual** of a covering JIT. They measure the same quantity from
opposite sides:

```text
TILING (primal):     count what you BUILD    — native cover; minimize cost(cover)
ABSORPTION (dual):   count what you REMOVE   — interpreter work; minimize residual pressure
                     the L0 floor IS the uncovered part. same thing, opposite sign.
```

Same expressive power (an L0 tile == a generic bail-tile), but the dual has a better
objective (demand-driven: work where hot interpreter work remains) and a better
zero-state (all-L0 = the baseline JIT = free at startup). Mixed images are an
*intended steady state*, not a degraded outcome — which is the whole point for
polymorphic, branch-balanced, and phase-changing code.

---

## 1. The minimal model

The entire engine before any optimization-pressure machinery:

```text
a tile        = (legal-when: FactMask, cost, code, facts-out, exits, residual obligations)
a floor tile  = an L0 tile; base-layer arity 1..4 over raw opcodes, with arity-1 total
an image      = ordered tiles; each tile legal under entry facts
the bank      = read-only, offline-built table of all tile templates
floor image   = an image composed entirely of L0 tiles; the always-installed baseline
the loop      = reduce hot residual pressure: when facts stabilize, look up the bank for
                richer tiles; if found, build a fresh image and atomically swap; otherwise
                stay at the floor
why it works: a higher-arity tile produces facts for its neighbor; richer facts make
              a richer next tile selectable; repeat. no separate optimizer exists.
```

Six lines. Residency, presence holes, mode caches, in-tile selectors appear
**nowhere** here. Each is a response to a measured problem (§7–§14), absent until a
profiler forces it. A feature earns entry only if it can be phrased as *"this changes
which tile is selected from the bank"* or *"this changes residual pressure."*

### 1.1 The objective (stated once, used everywhere)

```text
minimize:   total_cost = native_image_cost
                       + hot_residual_pressure      (§7, INCLUSIVE OF SEAM TAX)
                       + exit_pressure
```

The seam tax (§7) is the load-bearing correction over the naive absorption metric,
and it is what makes the sponge absorb in patches instead of speckles.

### 1.2 The floor is zero absorption

SponJIT does not sit beside the interpreter as a separate phase. Every region starts with an L0 cover:

```text
Image 0 = [L0 tile covering raw ops 0..3] [L0 tile covering raw ops 4..7] ...
```

L0 itself is an arity-1..4 raw-op layer; it is not only single-op. Arity-1 L0 is
the total fallback. Then hot, fact-stable spans are replaced by recursive metaops
materialized from bank templates:

```text
raw ops:  A B C D | E F G H | I J K L | M N O P
          │ L0 arity-4 tiles over raw opcodes
          ▼
image:   [L0 A..D] [L0 E..H] [L0 I..L] [L0 M..P]
          │ compose four L0 atoms
          ▼
image:   [L1 A..P]
          │ compose four L1 atoms later
          ▼
image:   [L2 up to 64 raw ops]
```

The invariant is arity≤4 at every foundry step; the basis changes from raw opcodes
to selected atoms from the previous layer.

This gives a single continuum:

```text
all-L0 baseline ->  partial-fusion image ->  rich-fusion image
0% absorbed     ->  some absorbed         ->  more, under richer facts
```

The system must not pay full recording cost all the time. Observation is pressure-
triggered:

```text
always-on: cheap hotness / residual counters
burst:     fact recording when pressure crosses a threshold
attached:  guard, exit, and seam counters on installed images
off/decay: stable regions reduce or disable counters
```

So "the floor is the all-L0 image" does **not** mean "the runtime is always
tracing." It means the runtime and bank share the same image model, while fact
gathering is sampled and demand-driven.

---

## 2. Relation to existing designs — SponJIT is a generalization, not an alternative

There is a single design space. Its axes:

```text
  tile granularity   (how much one tile covers: one opcode .. whole region)
  retile budget      (0 = compile once, never repair  ..  >0 = swap on demotion)
  residual policy    (zero-residual-by-fiat  ..  L0 is first-class & priced)
```

The known strategies are corners of this space — the *same machine* at different
settings, not analogies:

```text
                          tile granularity
        small ───────────────────────────────────────► large
          │                                              │
   interpreter ──── baseline JIT ──────────── trace JIT (LuaJIT)
   (all-L0 image    (1 tile/op,                (1 tile = whole region,
    runtime,         retile=0, no facts)        retile=0, zero residual by fiat)
    absorption=0)
          │
          └──────────────── SPONJIT ────────────────┘
              (window-sized tiles arity≤4, retile>0,
               L0 residual first-class & priced, selection-only)
```

A LuaJIT trace **is** an absorption image whose single tile covers the whole
recorded region and whose residual is forbidden. The mapping is exact:

```text
LuaJIT                          SponJIT at (granularity=region, retile=0, residual=∅)
------                          -----------------------------------------------------
trace = linear hot path     ≡   image with one whole-region tile
guard in the trace          ≡   checked-fact on the tile
SNAPSHOT at a guard         ≡   PROJECTION at an exit            (the same object;
                                LuaJIT delta-encodes snapshots — reuse that, §15)
side exit                   ≡   tile exit → floor
side trace at a hot exit    ≡   a separate bank tile selected on a different signature
trace tree                  ≡   the bank's multimorphic directory (max-granularity case)
compile-once                ≡   retile budget = 0; bank is read-only at runtime
```

### 2.1 The sharp statement of LuaJIT's weakness

```text
LuaJIT has NO CONCEPT OF AN ACCEPTABLE RESIDUAL.
a trace is all-native-or-bail. mixed steady-state is inexpressible.
=> when it cannot absorb everything, it absorbs nothing (trace give-up).
its brittleness is not a bug; it is the price of residual = ∅ by fiat.
```

SponJIT's position — sub-region tiles arity≤4, `retile>0`, *priced* L0 residual — is
the unique region of the space that can (a) repair locally and (b) stay mixed. That
is not generality for its own sake; it is aimed exactly at LuaJIT's failure mode.

### 2.2 The one thing LuaJIT has that this tier does not

LuaJIT runs an SSA optimizer **inside** the trace (allocation sinking, CSE,
reassociation, loop-invariant motion) before emission. Those are entangled graph
rewrites (§18) — out of scope for selection-based absorption. So SponJIT-at-the-
corner is *LuaJIT minus its optimizer*. The way you would recover that optimizer is
the §18 escape hatch taken to its limit: a curated super-tile grown to whole-region
size and synthesized online. The single price of that limit is the one invariant
SponJIT refuses to pay: **online codegen.** The §18 tier boundary and the no-
codegen line (§9.2) are the same line; LuaJIT is on the far side of it.

### 2.3 Open axis: meta-tracing

Meta-tracing (PyPy/RPython: trace the interpreter loop, not the program) appears to
be a **region-formation policy** (a variation of §12.0 / how you record), stacked on
the same granularity/retile/residual axes — not a fourth corner. `[UNVERIFIED]` If
it does not fit those three axes, that reveals a fourth knob worth naming.

---

## 3. Core objects

### 3.1 Tile (= absorber)

```c
typedef uint64_t FactMask;     /* one bit per fact in a fixed vocabulary */
typedef uint32_t TileId;
typedef uint32_t RegionId;

typedef struct {
    TileId     id;
    PatternKey pattern;         /* bytecode window / control shape covered */
    uint8_t    layer;           /* L0..L3, or LM (multimorphic) */

    FactMask   required;        /* must hold at entry (caller guarantees)   */
    FactMask   checked;         /* tile guards these; true on success        */
    FactMask   produced;        /* true after successful execution           */
    FactMask   killed;          /* invalidated by this tile's effects        */

    ExitDesc   exits[MAX_EXITS];/* guard-fail, slow path, branch, call, yield */
    DepDesc    deps[MAX_DEPS];  /* shape / metatable / call-target / ... epochs */

    PatchDesc  patches[MAX_PATCHES];  /* incl. presence + residency holes (§9) */
    ClobberDesc clobbers;       /* residency-kill derives from this (§11)    */
    CostModel  cost;
} TileDesc;
```

Bytes come from a mined C stencil (§9). **The runtime does not care which layer
produced the tile** — selection treats them all as bank entries with contracts.
Copy-and-patch is the materializer, not the theory.

### 3.2 L0 floor tile (= the always-legal bail-tile)

```text
L0 floor tile = "use the generic per-opcode stencil here"
```

First-class. Carries counters: hit count, cycle estimate, exit-reason distribution,
observed facts, successor info. A cold L0 tile is fine. A **hot** L0 tile is
absorption pressure (§7). Crucially, an L0 tile sitting *between* two higher-arity
tiles carries the cost of two register/residency boundary crossings (§7 seam tax) —
absorbing the L0 into a higher-arity tile deletes those, which is why islands grow
by accretion.

### 3.3 Image (= plan)

```text
Image = ordered, linkable sequence of TileInstances, each materialized from a bank TileTemplate

bytecode:   A  B  C  D  E  F  G
image V0:   [L0 A] [L0 B] [L0 C] [L0 D] [L0 E] [L0 F] [L0 G]      (the floor)
image V1:   [L1 A+B] [L0 C] [L0 D] [L1 E+F] [L0 G]                (two L1 tiles)
image V2:   [L2 A+B+C] [L0 D] [L2 E+F+G]                          (two L2 islands)
```

A region is correct even while mixed. There is no requirement of one global story.

Images are immutable once published. Region.active points at one of them at a time
(initially the floor, V0). Publication is atomic pointer swap.

---

## 4. Facts

Facts are not profiling annotations. They are **boundary summaries that make tile
selection legal and profitable.** Each must answer: who established it; what role;
in what scope; what kills it; what projection if it fails; which tiles it unlocks.

### 4.1 The six roles

```text
ObservedFact   from profiling. NEVER sufficient for unsafe code alone.
RequiredFact   must be guaranteed by predecessor / guard / entry.
CheckedFact    validated by this tile; true ONLY on the success edge.
ProducedFact   created by this tile's semantics on success.
KilledFact     invalidated by this tile's writes / effects.
DecisionFact   introduced by selecting a specialized tile; scoped to success path.
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
      │      TILE         │  required ⊆ facts_in   (else illegal -> L0 floor here)
      │  checked guards   │  on success: + checked
      │  effects          │  always:     - killed, + produced
      └────────┬─────────┘
               │ success
               ▼            success facts flow to the next tile
            facts_out       exit edges carry the PROJECTION to the floor, not the facts (§15)
```

### 4.3 Kills are the whole safety story

A produced/checked fact is valid **only until something kills it.** In Lua the kill
set is large: a call may trigger a metamethod that mutates a shape; `setmetatable`
kills a metatable assumption; GC may move/collect. The single correctness invariant:

```text
never let an assumption outlive its kill.
```

Speculative facts outliving one tile are backed by invalidatable dependencies
(shape epoch, metatable epoch, global-slot epoch, call-target epoch, upvalue
version, proto/code identity, debug-hook state, GC-barrier state). A dependency
epoch moving demotes region.active to the floor (§12, §17).

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
            x is i64 here ◄─┘   └─► exit: project state, jump to floor (§15)
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
GOOD guard: one guard proves type/shape for MANY downstream tile selections.
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

If guard A produces `x:i64`, a downstream tile B that *required* `x:i64` has its
requirement met — `A.checked ⊇ B.required` — so B's check is dead and the foundry
omits it when SSA-lowering the fused tile (§8). "A guard clarifies the rest" and
"checked-facts satisfy downstream required-facts, so downstream checks are deleted"
are the same statement. The foundry handles this offline.

---

## 6. Absorption waves

The key dynamic: a higher-arity tile produces facts that make neighbors more
specializable.

```text
gen 0:  [L0 GETTABLE] [L0 ADD] [L0 RETURN]
observe: table shape stable; key integer; ADD operands integer
gen 1:  [L1 GETTABLE_array_guarded] [L1 ADD_i64] [L0 RETURN]
        facts propagate: GETTABLE result observed integer; ADD result fresh; RETURN consumes it
gen 2:  [L2 GETTABLE_array_guarded + ADD_i64] [L0 RETURN]      (boundary collapsed; §7, §11)
gen 3:  [L3 GETTABLE_array_guarded + ADD_i64 + RETURN]         (full fusion)
```

No general runtime optimizer. Each step is **selection of a known bank tile under
richer facts** — the same machine at higher fact-richness (§0). "Discovery" here is
selection over a finite library, capped by that library, *not* open-ended rewriting.

---

## 7. The absorption metric — residual pressure, inclusive of seam tax

This is the merged objective and the section that resolves the optimal-grain
question both earlier framings circled.

### 7.1 Per-tile benefit

```text
benefit(tile) =
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

An L0 tile between two higher-arity tiles does not cost one interpreter-opcode. An
L0 tile *between two specialized tiles* manufactures two register/residency
crossings, each of which is a state reconcile (the same machinery as a side exit,
§15):

```text
[L2  ...] │ [L0 C] │ [L2  ...]
          ▲         ▲
     exit→floor   floor→re-enter
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
L0 on BOTH sides (isolated in floor sea)          +2 seams created  PENALIZED — absorb only if
                                                                    interp work removed is large
specialized on ONE side, L0 on the other          0 (net)          neutral — judged on work alone
specialized on BOTH sides (interior L0)           -2 seams deleted  STRONGLY FAVORED — absorbing
                                                                    here removes work AND two crossings
```

Consequences — the dynamics fall out for free:

```text
1. ACCRETION: L0 tiles adjacent to a specialized island are cheap to absorb (delete
   a seam), so islands GROW BY ACCRETION. the sponge soaks up contiguous patches,
   not speckles. fragmentation (specialized confetti in an L0 sea) is self-penalizing.

2. LOWER BOUND on grain: set by the seam tax — do not fragment; isolated absorption
   rarely pays.

3. UPPER BOUND on grain: set by the no-codegen line (§9.2, §18) — do not grow an
   island past what SELECTION can cover. beyond that you would need synthesis = a
   trace = LuaJIT.

4. THE GRAIN IS A FIXED POINT, not a tunable: grow islands by accretion until the
   next absorption either does not pay (seam/exit cost wins) or would require
   synthesis.
```

So the optimal grain — the thing the fusion-vs-locality and the fragmentation-vs-
brittleness tensions both pointed at — is **emergent**: the seam tax sets the floor,
the no-codegen invariant sets the ceiling, and absorption naturally settles between
them. `[UNVERIFIED: that the fixed point is stable across real workloads — this is
exactly what §19 must measure.]`

### 7.4 The accept rule (used by image building, §12)

```text
include a higher-arity tile at window W iff
   Δpressure = freq · interp_work_removed
             + seam_delta(neighborhood) · crossing_cost
             + downstream_unlock
             - native_cost - exit_cost - materialization
             exceeds the hysteresis margin (§12).
```

The neighborhood term is why the loop targets **interior L0 tiles between
specialized islands first**: they pay twice (work removed + two seams deleted).

---

## 8. Absorber foundry — grammar-driven opcode enumeration

The foundry enumerates all valid opcode sequences up to arity 4 over the
PUC Lua 5.5 opcode set, then compiles each sequence to a binary stencil via
SSA → C → GCC. Multi-layer recursive composition (atoms → higher arity)
is the basis-growth strategy (§13). Multimorphic enumeration over fact-env
unions (§14) is a separate enumeration axis driven by corpus pressure.

```text
L0 = all PUC Lua 5.5 opcodes, classified by instruction format
     (iABC, ivABC, iABx, iAsBx, iAx, isJ — see lopcodes.h)
     L0 is the floor source.

for L = 1..4:
    C_L = all valid sequences of L opcodes (continuers + optional terminator)
    E   = deduplicate by SSA handler equivalence class
           (opcodes with same SSA lowering path -> same class)
    for each equivalence class:
        for each applicable fact combination:
            ssa = compile(ops, facts)
            if ssa has no RESIDUAL nodes:
                c_code = ssa_to_c(ssa, ops, facts)
                gcc -c -O2 -fno-pic -no-pie → .o
                extract .text bytes and HOLE relocations
                store: { name, text_bytes, hole_catalog, ops, facts }
```

Key properties:

```text
1. Enumeration is exhaustive at arity≤4 (AOT, not runtime)
2. SSA handler equivalence class reduces 3.2M raw sequences to 472K classes
   (6.8× reduction) — ADD and SUB share the same class because their SSA
   lowering follows the same path, only the final C operator differs
3. Fact combinations are enumerated per class (2^N where N = distinct slot axes)
4. GCC does all scalar optimization — the SSA layer only lowers semantics
5. Current measured result: ~6.5 K clean stencils, ~880 KB .text, ~136 B avg,
   GCC ICF merges to ~2 K canonical machine code blobs, ~18 K HOLE relocations.
```

A selected tile is just another atom in the bank if it exposes the same contract
and, for future foundry layers, a semantic expansion:

```text
runtime identity: bytes/holes/contract/cost            (opaque to runtime)
foundry identity: semantic expansion or SSA summary    (transparent offline)

pattern span; required/checked/produced/killed facts; exits/projection;
dependencies; residency endpoints; cost; code artifact or implementation plan.
```

This split is load-bearing: runtime treats a tile as a black box, but the foundry
can reopen selected tiles and compose their semantics in later layers.

The foundry may enumerate the abstract universe exhaustively at arity≤4 because this
is AOT. It must not realize every tuple as code. It runs a sieve:

```text
1. enumerate opcode/atom tuples arity≤4
2. reject impossible shape/control/effect compositions
3. expand only applicable fact axes
4. expand tuple semantics into a small graph
5. apply facts and build SSA
6. run bounded SSA normalization / simplification (§8.1)
7. lower surviving SSA nodes back to the fixed stencil vocabulary
8. compose contracts and projections
9. score residual-pressure reduction and seam deletion
10. check lowering/template availability
11. compile/mine/verify only survivors
12. benchmark and export selected winners to the bank
```

SSA is not a runtime tier here. It is the AOT foundry's **canonical fact consumer**,
sitting after tuple composition and before scoring. Facts specialize the semantic
graph; SSA turns those facts into consequences; selection interns useful consequences
as bank tiles. The output is the same kind of artifact as any other producer emits.

Detailed design: `SPONJIT_FOUNDRY_SSA.md`.

Selection must be brutal to prevent basis pollution. A compound atom is selected only
if it beats composing its children directly and is useful under corpus pressure:

```text
selected iff verified
          and projection-safe
          and profitable vs child cover
          and not dominated by an existing tile
          and code size / exit risk acceptable
          and useful for observed or residual-pressure-predicted workloads
```

### 8.1 SSA as a lowering layer — GCC does the optimization

The SSA layer does NOT optimize. It lowers Lua bytecode semantics to C.
GCC -O2 does all scalar optimization:

```text
SSA LAYER:                      GCC -O2:
- guard insertion               - constant folding
- frame load/store              - dead code elimination
- opcode dispatch               - copy propagation
- type analysis                 - dead store elimination
- value forwarding              - register allocation
- C code generation             - instruction selection
                                - peephole optimization
```

The SSA layer runs only 2 passes that GCC cannot do:

```text
pass_frame_forward:
  When the same frame slot is stored-then-loaded, alias the load to the store
  value. GCC cannot do this because different __H_N extern symbols look like
  different addresses (the SSA knows they are the same slot via data flow).

pass_guard_dominance:
  Remove ttisinteger guards when the same value was already guarded. GCC does
  not know Lua guard semantics.
```

All other optimization (constant folding, DCE, dead store elimination, copy
propagation) is delegated to GCC. This keeps the SSA layer simple, correct,
and fast — its only job is translating bytecode semantics to C.

SSA gives the foundry a semantic normal form. Different opcode tuples may reduce
to the same C code (via SSA normalization), so tile identity is keyed by:

```text
optimized_semantic_normal_form_hash
```

not just by source opcode pattern. This is how the bank can hold reusable semantic
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
runtime SponJIT = bounded selection from the exported bank
```

---

## 9. Materialization — copy-and-patch with extern symbol HOLEs

Materialization must be cheap enough for repeated image rebuilds on demotion.
The mechanism: each specialization point is an `extern const char __H_N[]`
reference in C. GCC compiles this to a `R_X86_64_32` relocation (or
`R_X86_64_PLT32` for function addresses). At image-build time, the runtime copies
the pre-compiled .text bytes from the bank to RWX memory and overwrites each
relocation offset with the actual value.

```c
/* Stencil C code with HOLEs */
extern const char __H_0[];  // slot offset
extern const char __H_1[];  // immediate value
extern const char __H_2[];  // fail handler address

void stencil_HASH(void *stack) {
    TValue *base = (TValue*)stack;
    int slot = (int)(uintptr_t)__H_0;  // → R_X86_64_32 reloc
    long long imm = (long long)(uintptr_t)__H_1;  // → R_X86_64_32S reloc
    base[slot].value_ = (unsigned long long)imm;
    base[slot].tt_ = 3;
    if (__builtin_expect(base[slot].tt_ != 3, 0))
        ((void(*)(void*))__H_2)(stack);  // → R_X86_64_PLT32 reloc
}
```

Each `__H_N` is an undefined symbol. GCC does not resolve it (compile with
`-c -fno-pic -no-pie`). The object file contains the relocation record alongside
the .text bytes:

```
OFFSET     TYPE          VALUE
00000001   R_X86_64_32   __H_0    ← slot offset (4 bytes to patch)
0000000f   R_X86_64_32S  __H_1    ← immediate value
0000002b   R_X86_64_PLT32 __H_2   ← fail handler address
```

At image-build time:

```c
void *code = mmap(NULL, size, PROT_RWX, MAP_PRIVATE|MAP_ANON, -1, 0);
memcpy(code, stencil_bytes, size);
// Patch each hole
*(uint32_t*)(code + 0x01) = actual_slot_number;
*(int32_t*) (code + 0x0f) = actual_immediate;
*(uint32_t*)(code + 0x2b) = (uint64_t)fail_handler - (code + 0x2b + 4);
// mprotect RX and atomic publish
```

### 9.1 Advantages over PatchDesc

This approach is simpler than the PatchDesc mechanism described in earlier
designs:

```text
PatchDesc approach (old):         Extern symbol approach (current):
- custom struct for each hole      - hole positions implicit in ELF relocations
- manual offset management         - no per-hole bookkeeping
- hand-written patching code       - generic: same loop for all stencils
- separate metadata per stencil    - one table per .o file
```

### 9.2 The runtime never generates code

```text
RUNTIME does:     observe -> canonicalize -> select -> copy -> patch -> link -> publish
RUNTIME does NOT: run GCC/LLVM, synthesize instructions, do general register
                  allocation or peephole codegen.
```

This bright line keeps verification tractable. Crossing it is a *different engine*.

```c
typedef enum { HOLE_CONST, HOLE_CONT, HOLE_PRESENCE, HOLE_RESIDENCY } HoleKind;

/* one AOT artifact; many behaviors, decision vector supplied at copy time */
typedef struct { TileId base; PatchDesc holes[MAX_HOLES]; } ParamTile;
```

```text
ParamTile ADD =
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
   N × M fused tiles    ->                ->  N + M endpoints
```

A presence hole patched to `skip` writes a jump-over or relocates a cold region — the
**same primitive** as patching an immediate. **Presence/residency holes are resolved
once at PATCH TIME and emit straight-line code with no internal branch.** They are
*not* runtime selectors (§10), and they do not violate §9.2.

### 9.3 The closing loop: a propagated fact IS a hole value

```text
tile A produces "lhs proven i64"  ──► patches tile B's hole[0] to `skip`
```

Fact propagation (§4.2) and materialization (§9) are the same operation seen from
two sides. A propagated fact is the value you patch into a downstream decision hole.

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

## 10. Binding times — selectors are a special case, not a default

A specialization decision can bind at three times. **Two are first-class; the middle
one is demoted.** This corrects the earlier "three co-equal bindings" framing.

```text
bound at AOT       -> enumerate base patterns                 (the bank)
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
stable simple case            -> monomorphic bank tile + exit to floor
unstable / high-entropy case  -> L0 floor for that PC
genuine clustered persistent  -> multimorphic bank tile (§14) with internal
   low-arity polymorphism        discriminator compiled by GCC
```

### 10.2 When a selector IS allowed (the multimorphic exception)

Some sites are reliably *bimorphic or trimorphic* and *simultaneously* hot (not
phase-separated): an L0 tile throws away both fast paths; a per-iteration cache
lookup would thrash because both modes are hot at once. A bounded internal branch
inside a multimorphic tile is then genuinely optimal. Permitted iff:

```text
- polymorphism is LOW-ARITY, LOCAL, and PERSISTENT in the training corpus, and
- the branch is measurably cheaper than the exit it replaces, and
- it is structured as a multimorphic tile (§14): one bank entry with internal
  discriminator and specialized arms; selected once at runtime.
Rule: do not route inside a tile unless the foundry enumerated the union from
      observed corpus pressure. measurement-gated, never default.
```

### 10.3 The three are one idea at three granularities

```text
monomorphic specialization (baked) = a tile with one fact env
multimorphic tile (§14)            = a tile with K fact envs joined by a discriminator
recursive-basis tile (§13)         = a tile composed from a previously-selected tile
                                     (a "phrase" tile, not a polymorphism device)
```

Note: the old "plan-mode cache" granularity is **gone**. Multimorphism lives inside
a single bank tile, not in a runtime cache of alternative plans.

---

## 11. Residency as a first-class fact — the seam tile

Most non-algebraic wins are **deleted seam traffic** (§7). When ADD writes slot R2
and RETURN1 reloads it, the whole win is deleting that store/reload. You don't need
a fused instruction — you need the two tiles to *agree on where the value lives.*

```text
type fact:        "R2 is i64"
residency fact:   "R2 is live in rax, unboxed, freshly produced"

RETURN1 ships residency variants (hole[in] ∈ {slot,gpr}); image build picks the
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
residency fact:  DENSE kills, short range (killed by ANY tile clobbering rax)
```

So residency-kill is **not hand-authored** — it falls out of `clobbers` (§9.4),
reindexed by location instead of value. Produced-residency = the exit convention;
killed-residency = the clobber set. First-class residency adds no maintenance burden.

### 11.2 The image builder is now a tile matcher — pin the convention

```text
tiles ADVERTISE a small fixed set of residency contracts (calling-conv variants).
image build MATCHES advertised endpoints. it does NOT SEARCH allocations.
(searching => state includes the register file => exponential.)
the convention does the allocator's work offline; the runtime stays a matcher.
```

L0 tiles always source operands from canonical slots and write results to slots —
so an L0 tile is always a legal joiner at any boundary. Higher-arity tiles match
each other when their advertised endpoints agree.

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
   the entire price is concentrated in EXIT METADATA. bounded per tile.
```

### 11.4 Residency is projected OUT of the signature

```text
type        = a MODE. part of region identity. part of the bank signature key.
residency   = an implementation detail of ONE image. canonicalized away before
              the key.
WRONG: distinguish "i64 with R2-in-rax" from "i64 with R2-in-rcx" as different
       bank keys -> fragmentation.
RULE:  residency propagates through image build like a fact, but is excluded from
       the bank key.
```

### 11.5 Honest constant

Residency is `{slot, gpr, xmm}` plus oddities (gpr-pair, fixed regs for div/shift).
Library growth is "classes × operands" — still additive, still offline, not literally
×2. Window size is bounded by register pressure (fine for 2–8 ops on x86-64).

---

## 12. The image-build loop and why it terminates

### 12.0 Region formation (Pass 0)

A hotness counter (backedge / call site) trips; record forward from the trigger pc
appending `(pc, op, operands)` until a stop (cold branch, size cap, un-inlined call,
or loop closure). Output is an ordered bytecode run — the substrate, not yet an
image. The substrate immediately gets a floor image (all-L0 templates copied from the bank); higher-
arity tiles arrive only after observation.

### 12.1 Non-monotone facts force a convergence rule

```text
exits RETRACT facts (a failing guard kills a downstream-relied-on fact),
so the fact lattice is NON-MONOTONE and the build can oscillate between selections.
=> the loop is not self-terminating. it needs a damping rule.
   HYSTERESIS IS THAT RULE — a termination condition, not an optimization trick.
```

```text
re-select   if benefit high and stable     e.g. signature dwell > N hits
demote      only after sustained failure   e.g. guard fail rate > F over M hits, M > N
the gap between thresholds prevents ping-pong.
```

Hysteresis at runtime is a single integer per region (§5 in
`SPONJIT_RUNTIME_DESIGN.md`). It gates *when to attempt re-selection*, not what to
build — the bank already decided what is buildable.

### 12.2 "Cheapest image" is aspirational — it is a local fixpoint

```text
1. the objective (§7) has NON-LOCAL terms (seam delta couples neighbors;
   invalidation risk couples tiles sharing a dep epoch; hysteresis is a property
   of the swap event). => no global optimum from a local image build.
2. local image construction is ORDER-DEPENDENT (§13): A-before-B ≠ B-before-A.
honest slogan: not "the cheapest image," but
   "a cheap, stable image reachable by bounded selection of bank templates under
    current facts."
```

### 12.3 The image-build DP (mechanism per region), local cost only

State is `(position × entry_fact_signature)` — two covers reaching a pc with
different facts unlock different tiles; signatures are coarse (§11.4) so the
product stays tiny.

```text
best[(0, entry_sig)] = (empty, 0, entry_facts)
for each reachable (i, sig):
  facts_i = best[(i,sig)].facts
  for each tile T in bank legal at i (T.required ⊆ facts_i), incl. L0:
     j        = i + T.covered_len
     facts_j  = transfer(facts_i, T)
     cost_j   = best[(i,sig)].cost + LOCAL_cost(T)   # cycles + exit_prob·exit_cost + size
     relax best[(j, signature_of(facts_j))]
window_plan = argmin over sigs of best[(n, sig)]
```

The DP uses **local cost only**. The non-local terms — seam delta (§7.3),
invalidation risk, hysteresis — are applied at the **accept gate** (§12.4), never
inside the DP. The DP is small in practice: at each position the bank offers
at most a few tile choices for the observed signature; the DP horizon is bounded
by max arity (≤4); the state space is `region_len × signature_count` and
signatures are coarsely canonicalized.

Bank lookup, not synthesis: every choice at every position is a (pattern,
signature) → tile lookup in the read-only bank, plus the always-available L0.

### 12.4 The loop

```text
while region hot and budget remains:
    execute current image (initially the floor); collect counters
    if hysteresis stabilizes on a new dominant signature for this region:
        image = build_image_via_dp(region, signature)    # §12.3, local cost only
        if Δpressure(image, region) > hysteresis_margin: # §7.4 + §12.1, with SEAM DELTA
            mprotect-RX; atomic_store(&region.active, image)
            schedule old active for free (unless it was the floor)
        else:
            keep current image; raise threshold
    if guard failure rate in region.active exceeds demotion threshold:
        atomic_store(&region.active, region.floor)
        log exit-reason distribution for the cross-run training signal
```

Bounded, not an unbounded optimizing compiler.

### 12.5 Bounding enumeration

```text
max window / max tiles per image; preindexed bank tables keyed
(PatternKey, FactSignature); reject tiles whose deps are unstable; prefer observed
signatures; cap image size + materialization budget per region. worst case is bounded.
```

---

## 13. Fact-flow direction and loops

```text
do facts flow STRICTLY FORWARD along the image, or can a tile constrain its predecessor?
forward-only  => locality holds; image build stays local; the model stays ~6 lines.
backward flow => predecessor constraints => a real fixpoint solver => locality lost.
```

MVP chooses **forward-only along straight-line images.** Loops break the clean
version (the backedge carries invariants backward) and cannot be dodged for Lua.

### 13.1 The loop rule: establish-at-header + presence-skip-in-body

```text
1. select a loop-header tile that ESTABLISHES the invariant fact once at entry
2. the fact propagates across the backedge — survives iff nothing in the body kills it
3. patch the body tile's guard PRESENCE hole to `skip` (§9)
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

The kill-set emptiness test is the **decision procedure** for which half a guard
falls into — mechanical, not judgment. Type/shape invariance hoists for free; array
bounds-check elimination is a separate analysis and is out of scope.

---

## 14. Multimorphism — handled in the bank, not the runtime

A site that sees multiple stable fact environments is **not** a runtime cache
problem. SponJIT has no runtime cache. Multimorphism is handled offline by enumerating
a multimorphic tile that internalizes the dispatch:

```text
observed at PC X across the training corpus:
  signature S1 covers 60% of hits
  signature S2 covers 35% of hits
  S3..Sn cover the remaining 5%

foundry enumerates: multimorphic tile T_{S1 ∨ S2} with internal discriminator.
bank stores: T_{S1 ∨ S2} in the multimorphic directory.
runtime observes {S1, S2} at PC X.
runtime canonicalizes: signature = "multimorphic-{S1, S2}".
runtime selects: TileTemplate T_{S1 ∨ S2} from the bank and materializes it into the image.
done. one selection. one image. no per-iteration cache lookup.
```

Compare to a trace JIT: this reads instability as a single bank tile whose internal
branch is compiled by GCC, not as a tree of side traces.

```text
inline cache:  one SITE caches cases at runtime.    SponJIT: one BANK tile caches
                                                              the cases offline.
```

### 14.1 Internal discriminator

A multimorphic tile is a single fused tile with an internal branch on the cheapest
test that separates the union's arms — usually a tag-bit compare or shape-epoch
compare:

```text
multimorphic ADD over {i64, f64}:
  load tag of lhs
  jump-table or compare-branch on tag
    arm i64:  guard rhs i64; unbox; add_i64; box
    arm f64:  guard rhs f64; unbox; add_f64; box
    default:  residual -> projects to floor (§15)
```

Both arms are as specialized as their monomorphic counterparts. GCC compiles the
whole tile in one go.

### 14.2 Enumeration trigger

The foundry does not enumerate every possible union. It enumerates unions that the
training corpus actually exhibits:

```text
for each (pattern, PC):
    if top-K signatures cluster (top-2 ≥ 90% or top-3 ≥ 95% of hits):
        enumerate multimorphic tile T over those K signatures.
    else:
        no multimorphic tile. runtime falls to floor for non-monomorphic hits.
```

This bounds the multimorphic directory size and ensures every multimorphic tile
corresponds to a phenomenon the world has shown.

### 14.3 Why this collapses the runtime cache

```text
runtime cache:        per-iteration canonicalization + lookup + possible eviction
                      per-region cache key management
                      megamorphic detection logic

multimorphic tile:    one selection at hysteresis-stabilization time
                      per-iteration internal branch inside the tile (GCC-compiled)
                      no cache, no eviction, no detection logic
                      megamorphic response = bank miss = stay at floor
```

The discriminator cost is bounded and predictable; cache machinery is unbounded and
a source of bugs. Pushing polymorphism into the tile pushes it past the boundary
where the runtime has to think.

### 14.4 Image invariants

```text
- images are IMMUTABLE once published
- image switching is ATOMIC w.r.t. executing threads & coroutines
- old images stay valid until no frame can return to them
- dep-epoch invalidation atomically resets region.active to the floor BEFORE freeing
  the demoted image
- the floor is never freed
```

---

## 15. Projection / deopt — the real cost, and the seam cost are the same object

Every exit AND every higher-arity↔L0 seam (§7) must reconstruct lower-tier state.
This is where speculative JITs sink most complexity; it is budgeted, not waved away.

```text
a side exit OR a seam crossing must reconstruct:
  resume pc; frame/base/top; live stack slots; pending call/return state;
  dirty register leases (reconcile to slots, §11.3); materialized values for any
  skipped/reordered work; debug/error/yield observability state.
if projection is not known, the tile is ILLEGAL.
```

Reuse LuaJIT's trick: **delta-encode projections between guards** so reconstruction
is cheap (§2). Residency adds a bounded "materialize live registers to slots"
prologue to each register-resident exit (it is the inverse of the residency
contract, §11.3).

```text
KEY UNIFICATION: a seam crossing IS a projection. this is why the §7 seam tax is
real and quantifiable — its cost is exactly the projection cost you already must
compute. an exit and a seam are the same object differently typed.
```

---

## 16. Runtime architecture

```text
OFFLINE (build time) — the expensive work:
  - enumerate base atom tuples arity≤4 (§8)
  - apply fact-env combinations (monomorphic and multimorphic, §14)
  - compile C templates; mine bytes, relocations, holes, hot/cold sections
  - VERIFY each tile contract against its semantic expansion (§17)
  - benchmark/estimate costs; export bank file
    (preindexed by PatternKey, FactSignature; multimorphic in its own directory)

RUNTIME — selection and image swap only:
  1. on region first encounter: build floor image from bank L0 tiles
  2. execute current image (initially: floor)
  3. collect cheap always-on counters; burst-record facts only when pressure justifies it
  4. accumulate observations into local lease state
  5. hysteresis admits selection attempts
  6. greedily select largest/highest-score legal bank candidates; build image (§12.3)
  7. if image is non-trivially better than floor:
       materialize: copy bank bytes -> patch holes/exits -> link (§9)
       atomic_store(&region.active, new_image)
  8. on tile exit: project state, integrate fact delta, penalize failed assumption
  9. reselect the failed span: weaker same-span -> split -> L0
  10. log exit-reason distribution for next-run training (§11 in RUNTIME_DESIGN)
```

```text
   ┌──────────────────────────┐
   │ Region.active executing   │  (initially the floor; otherwise a selected image)
   └──────────┬───────────────┘
              │ counters, exit reasons, facts (§7)
              ▼
     ┌──────────────────────┐
     │ Hysteresis Counter    │  one integer per region
     └────────┬─────────────┘
              ▼
     ┌──────────────────────┐
     │ Bank Lookup (read-only)│  by (pattern, signature) → tile
     └────────┬─────────────┘
              ▼
     ┌──────────────────────┐
     │ Image Build (DP)      │  §12.3: bank lookups + seam/hysteresis accept-gate
     └────────┬─────────────┘
              ▼
     ┌──────────────────────┐
     │ Copy/Patch/Link       │  §9: copy bank bytes; fill holes (facts->presence, residency)
     └────────┬─────────────┘
              ▼
     ┌──────────────────────┐
     │ Atomic Image Publish  │  store new image into region.active
     └──────────────────────┘
```

---

## 17. Correctness invariants

```text
CORRECTNESS
  - interpreter semantics are the source of truth
  - every bank tile contract is verified OFFLINE against its semantic expansion
  - every guard failure has a precise exit + projection (§15)
  - every speculative dependency is recorded and invalidatable (§4.3)
  - debug hooks, errors, yields, metamethods, GC barriers are never skipped
  - an assumption never outlives its kill (§4.3)
  - the floor is correct for every region and is always installed
RUNTIME SIMPLICITY
  - runtime never runs a compiler or synthesizes instructions (§9.2)
  - runtime never holds a cache; the bank is the only multi-entry structure and
    is read-only at runtime
  - runtime only: select, copy, patch (incl. decision vector), link, atomically swap
  - selection + image-build budgets are bounded (§12.5)
IMAGE MANAGEMENT
  - images immutable once published; switching atomic via region.active store
  - old images valid until unreachable; invalidation redirects to floor BEFORE freeing
  - floor is never freed
MEASUREMENT
  - re-selection is driven by residual pressure (§7), not hope
  - hysteresis prevents oscillation AND is the loop's termination condition (§12.1)
  - code size + materialization + SEAM cost are part of the bank's selection score
  - a specialized tile with a high exit rate is WORSE than a floor L0 tile and
    is not retained by foundry selection
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
           elision, INVARIANT TYPE/SHAPE guard hoisting (§13.2), multimorphic
           sites via foundry-enumerated tiles (§14).
  with:    zero runtime codegen; every emitted byte proven correct before run.
WHAT IT IS NOT:  a trace optimizer. it does not beat allocation sinking + reassociation,
                 and must not pretend to. that is LuaJIT's tier (§2.2), past the
                 no-codegen line.
```

### 18.1 Buying back single cases without opening the door

```text
ALLOWED:   buy back named, individually-verified CURATED SUPER-TILES as bank
           artifacts, for specific hot shapes (most likely the loop-invariant
           BOUNDS check, §13.2 — the type half already hoists for free).
FORBIDDEN: general runtime composition that COMPUTES new instructions. the instant
           a "peephole" computes rather than deletes/substitutes, you have shipped
           a code generator: verification collapses, projection must reconstruct
           across unproven code, W^X / JIT-spray surface appears. that is a
           different engine (§2.2).
```

### 18.2 The link-time peephole catalogue (the only "rewriting" allowed)

```text
PERMITTED:  a FIXED, offline-VERIFIED catalogue that only DELETES or SUBSTITUTES
            from a pre-proven set:  erase jmp-to-fallthrough;  elide dead-store-
            then-reload at a seam (residency, §11).
FORBIDDEN:  any transform that COMPUTES an instruction from operands.
the bright line: deletion/substitution from a verified catalogue = link glue.
                 computation = codegen = a different engine.
```

---

## 19. MVP

Prove SponJIT as a selection engine, not a full optimizing compiler.

### 19.1 Bank — current status

```text
L0 generic:    every PUC Lua 5.5 opcode has a clean stencil (the floor source).
L1 specialized: ADD_i64 SUB_i64 MUL_i64 LT_i64 EQ_i64
                GETTABLE_array_guarded  GETFIELD_shape_guarded  CALL_known_boundary
L2 curated:    ADD_i64_RETURN1  LT_i64_BRANCH  TEST_JMP  GETTABLE_array_i64_ADD_i64
L3 curated:    selected arity-4 fused phrases from observed corpus pressure
LM multimorphic: pending corpus pressure data; not yet enumerated.

Current measured emission:
  ~6.5 K real stencils, ~880 KB .text, ~136 B avg, ~18 K HOLE relocations.
  GCC ICF collapses to ~2 K canonical machine code blobs (estimate).
```

### 19.2 Runtime MVP

```text
- bank file format, mmap reader
- per-region floor construction from L0 tiles
- linear hot-region recorder (§12.0)
- per-region: floor pointer, active pointer, hysteresis counter, tile-site memory
- always-on counters; pressure-triggered burst fact recording
- simple fact leases: integer-ness, table shape, known call target (NOT residency)
- window-level canonicalization into local lease state
- greedy bank lookup by pattern -> best-first candidate ladder
- image-build over position with same-span weakening, lower-arity splitting, L0 floor
- copy-and-patch materializer with const/continuation/presence/residency holes (§9)
- atomic publication via region.active store
- local replacement on tile exit; floor fallback on dep invalidation/extreme instability
- exit-reason log for local ladder training and cross-run foundry training
- floor is never freed; old images drained then freed
```

### 19.3 Workloads — they tell you which engine you built

```text
(1) numeric counted loop over an array   s = s + t[i]
      measures the BOUNDS-CHECK ceiling specifically (everything else you already
      get). expect: good, with a NAMEABLE ceiling at the IV-range boundary (§13.2).

(2) method-dispatch-heavy object loop     obj:method() in a loop
      shape-IC + known-call-target; almost purely orthogonal.
      expect: the SHOWCASE. cleanest test of "a produced fact enables a later
      tile": does the shape-guard's produced fact flip the next window to a
      known-call-target tile?

(3) allocation-churny table/closure code
      feels the absence of allocation sinking most.
      expect: tells you whether the §18 boundary is comfortable or painful for
      real workloads — i.e. whether you ever need the next tier.

(4) bimorphic table access (same site sees two stable shapes)
      tests the multimorphic-tile pipeline (§14). expect: foundry corpus pressure
      data identifies the union; bank holds T_{S1∨S2}; runtime selects it; per-
      iteration internal branch is cheap. confirms that multimorphism does not
      require a runtime cache.
```

### 19.4 Initial training corpus

The first foundry training set is deliberately small and complementary:

```text
AWFY      numeric loops, algorithmic kernels, table loops, branch/loop motifs
Moonlift  real compiler workload: AST/ASDL traversal, modules, tables, strings,
          builder APIs, validation passes, method/call-heavy compiler code
```

This is enough to train the first absorber basis without turning corpus curation
into its own project. AWFY prevents the basis from becoming only application/table
shaped; Moonlift prevents it from becoming only benchmark/numeric shaped.

The shadow simulator has a single command for this initial corpus (see existing
harness invocations). It writes:

```text
build/sponjit_shadow_initial/awfy/suite_report.md
build/sponjit_shadow_initial/moonlift/suite_report.md
build/sponjit_shadow_initial/combined/suite_report.md
build/sponjit_shadow_initial/combined/miss_report.json
```

The combined miss report is the input to the bank training step:

```text
training data      = AWFY + Moonlift bytecode/fact pressure
model parameters   = selected bank tiles + costs + selector metadata
training objective = minimize residual pressure under correctness gates and cap
```

Later corpora can be added as validation or holdout sets, but they are not required
for the first foundry loop.

### 19.5 Success criteria

```text
1. mixed L0/specialized images execute correctly
2. image build replaces L0 tiles with higher-arity bank tiles WITHOUT recompiling
3. a PRODUCED FACT enables a later tile not selected in image-build pass 0
4. ISLANDS GROW BY ACCRETION (interior L0 tiles absorbed first; no confetti) —
   validates §7.3
5. multimorphic tiles handle bimorphic sites without thrash or cache machinery
6. hysteresis prevents image thrash on a phase-changing workload
7. guard exits and dirty residency leases project correctly
8. demotion to floor preserves correctness in all failure modes
9. AWFY + Moonlift combined reports identify concrete next bank-tile proposals
```

---

## 20. Worked examples

### 20.1 Arithmetic return

```text
pc0: ADD R2,R0,R1   pc1: RETURN1 R2
floor:  [L0 ADD] [L0 RETURN1]                       (observe R0,R1 i64 ~99%)
v1:     [L1 ADD_i64_guarded] [L0 RETURN1]           (observed -> checked; §5)
v2:     [L2 ADD_i64 -> rax] [L1 RETURN1 <- rax]     (residency seam absorbed; §11)
 OR     [L2 ADD_i64_RETURN1]                        (curated arity-2; §6)
if i64 guard failures later rise:
  mark the i64 lease unstable at this tile site and reselect the span.
  same span may choose a weaker/generic or multimorphic ADD tile; if none exists,
  the span splits until L0 covers the delicate opcode.
  the exit is also logged so a later foundry cycle may add a better multimorphic ADD.
```

### 20.2 Table access + arithmetic (absorption wave)

```text
pc0: GETTABLE R2,R0,R1   pc1: ADD R3,R2,R4   pc2: RETURN1 R3
floor:  [L0 GETTABLE] [L0 ADD] [L0 RETURN1]
observe: R0 table@shape17; R1 int; array hit; no metatable; result int; R4 int
v1:     [L1 GETTABLE_array_guarded] [L1 ADD_i64_guarded] [L0 RETURN1]
        GETTABLE success -> R2 from array; ADD success -> R3 i64 fresh;
        RETURN1 consumes R3
v2:     [L2 GETTABLE_array_i64 -> rax] [L2 ADD_i64 <- rax -> rax] [L1 RETURN1 <- rax]
        (seams absorbed via residency-matching bank tiles)
if shape alternates 17/23:
  foundry training observes this; next corpus aggregation enumerates a
  multimorphic GETTABLE over shapes {17, 23}; bank holds T; runtime selects T;
  per-iteration internal branch on shape epoch chooses the right arm.
reached by FACT PROPAGATION ENABLING SELECTION, not by synthesizing code.
```

### 20.3 The loop (free hoist + the boundary)

```text
for i = 1, n do  s = s + t[i]  end
header: [L1 loop_header: establish "t table, no metatable"]            (§13.1)
body:   [L2 GETTABLE_array <- (i bounds CHECKED here)] [L2 ADD_i64] [L0 backedge]
        ^ "t table" PRESENCE-skipped in body: fact survived the backedge
          (kill-set ∅). FREE HOIST.
        ^ "i in bounds" CANNOT skip: i kills it each iteration. per-iteration
          check unless a curated bounds super-tile is bought back (§18.1).
          TIER BOUNDARY.
```

### 20.4 A mixed image and the seam tax (the reasoning)

```text
region:  A  B  C(metamethod-heavy GETTABLE)  D  E
v0:      [L0 A][L0 B][L0 C][L0 D][L0 E]              all-L0 floor; pressure spread out
v1:      [L1 A+B][L0 C][L1 D+E]                      two specialized islands;
                                                     C is interior L0
   note: C is now an INTERIOR L0 -> it pays the seam tax TWICE (in + out, §7.2)
         so C's residual pressure is HIGH even if C's interp cost is modest.
v2 candidate: absorb C with a shape-guarded bank tile + exit to floor on metamethod
   Δpressure = freq·interp(C) + 2·crossing_cost (two seams DELETED) + downstream_unlock
             - native(C) - exit_cost(metamethod) - materialization
   if metamethods are rare on C, the 2-seam deletion alone likely justifies
   absorbing it, MERGING the two islands into one:  [L3 A+B+C+D+E (mostly fused)]
   if metamethods are frequent, C stays L0: a stable mixed image (§2.1), not a failure.
this is §7.3 accretion in action: the sponge fills the gap between two patches first.
```

### 20.5 Bimorphic site handled by a multimorphic tile

```text
region with one hot GETFIELD on obj.x where obj has shape {S1, S2} bimorphically.
training corpus observes: 55% S1, 42% S2, 3% other.
foundry enumerates: T = multimorphic GETFIELD over {S1, S2} with internal
  shape-epoch discriminator. T goes into the bank's multimorphic directory.

runtime sees: shapes alternating S1/S2 in the hot loop.
canonicalization: signature = multimorphic-{S1, S2}.
bank lookup hits T.
image-build inserts T at the GETFIELD position; surrounding tiles match T's
  output residency endpoint.
execution: GCC-compiled internal branch picks S1-arm or S2-arm based on
  observed tag; both arms are as specialized as their monomorphic tiles
  would have been. no runtime cache. no per-iteration lookup.
```

---

## 21. Summary

```text
THE IDEA (load-bearing, survived every simplification):
  JIT compilation is bytecode absorption under assumptions.
  the all-L0 image is the baseline — zero absorption in the same model.
  absorption = specialization = selection-from-bank at increasing fact-richness —
    one operation.
  a guard turns an observed fact into a proven fact by spending an exit.
  SponJIT is the DUAL of a covering JIT: it minimizes work REMOVED, not code BUILT.

THE GENERALIZATION:
  interpreter / baseline / LuaJIT are corners of one space (granularity × retile × residual).
  LuaJIT's defining limit: it has NO ACCEPTABLE RESIDUAL — all-native-or-bail.
  SponJIT's first-class, PRICED L0 residual is the axis LuaJIT lacks; mixed images
  are a stable state.

THE BINDING TIME (the simplification):
  the bank is read-only at runtime and built offline by the foundry.
  the runtime holds two pointers per region — floor + active — and a hysteresis
  counter. it observes, canonicalizes, looks up the bank, copy-patches, and swaps.
  no cache. no eviction. no runtime SSA. no runtime codegen.
  multimorphism is a tile shape in the bank, not a runtime device.
  exits are a cross-run training signal, not a runtime cache author.

THE MECHANISM (added only as measured problems demanded it):
  - facts: six roles; kills bound their reach
  - orthogonal specialization = patch-time decision holes on parameterized base tiles
    (product collapses to a sum; a propagated fact IS a hole value)
  - binding times: AOT (the bank) and patch-time (image build) are first-class;
    the runtime selector is DEMOTED to a measurement-gated multimorphic-tile case
  - residency: a lease over a canonical home; dual of clobber; additive; out of
    the bank key; it is the mechanism that pays down the seam tax
  - hysteresis is the loop's termination condition, not a feature
  - facts flow forward; loops hoist invariant TYPE guards for free; the kill-set
    test exposes the bounds-check TIER BOUNDARY

THE OBJECTIVE (the merge's center):
  minimize freq-weighted residual pressure INCLUSIVE OF SEAM TAX.
  a seam (specialized↔L0 crossing) IS a projection, so its cost is real and
  quantifiable.
  the seam tax makes the sponge self-organize: islands GROW BY ACCRETION (interior
  L0 tiles absorbed first), fragmentation is self-penalizing, and the optimal grain
  is an EMERGENT FIXED POINT — floored by the seam tax, ceilinged by the no-codegen
  line — not a tuned knob.

THE BOUNDARY (a strength):
  entangled graph rewrites (BCE, allocation sinking, reassociation) are out of scope,
  bought back only as individually-verified curated super-tiles. runtime never
  computes an instruction. that boundary is the line LuaJIT sits on the far side of.

STATUS:
  foundry emits real .o files (~6.5 K stencils, ~880 KB, ~136 B avg, ~18 K HOLEs).
  runtime selection mechanism is design-complete; implementation pending.
  internally coherent; UNVERIFIED on real workloads — run the §19.4 AWFY+Moonlift
  initial corpus first.
  if a shape-guard's produced fact flips the next window's selected bank tile on
  real bytecode, islands grow by accretion rather than confetti, and the combined
  miss report produces concrete bank-tile proposals, the thesis is demonstrated,
  not asserted.
```

```text
Absorb what is simple.  Residualize what is complex.  Revisit what stays hot.
A side exit is not a failure — it is a demand signal for residualization or for
the next foundry run.
A guard clarifies the rest — until something kills it.
The sponge soaks up contiguous patches and leaves the rest as the L0 floor.
The bank is the system. The runtime selects templates from it and materializes images.
```
