# Hysteretic Fact-Propagating Tiling JIT

## Status

Design proposal / research architecture for the experimental Lua VM JIT.

Current SponJIT runtime design has been sharpened in `SPONJIT_RUNTIME_DESIGN.md`:
SSA is the sole fact-consuming optimizer; runtime tiling/cover search is demoted to
cache lookup plus copy/patch. This older document remains useful for the hysteresis,
fact propagation, and tiling vocabulary, but the current binding-time split is in the
runtime design doc.

This document describes a JIT model based on **adaptive executable tiling**:

```text
JIT compilation = choose a low-cost cover of hot execution with executable tiles.
Optimization = facts and decisions propagating across tile boundaries.
Retiling = local repair when observed behavior disagrees with the current cover.
```

The design is inspired by Copy-and-Patch compilation, baseline JITs, inline caches,
trace JITs, and compiler fixed-point optimization passes, but it changes the unit of
runtime compilation from "a trace" or "an opcode" to a **tile cover** that can be
incrementally refined and cached.

The intended audience is senior VM, C, and assembly engineers. The document is
careful to separate mechanism from speculation and to state what must be verified.

---

## 1. Executive summary

Traditional JIT mental models often look like this:

```text
interpreter -> record hot trace -> optimize trace -> emit machine code -> run
```

This works extremely well when the hot path is stable. It works less well when a
region is:

- polymorphic;
- branch-balanced;
- phase-changing;
- dependent on table/call shapes that alternate;
- profitable only after several local simplifications expose more facts.

In those cases, a trace compiler may produce a brittle trace with many side exits,
or may decide the region is not worth compiling. We call this failure mode,
informally:

```text
TGU = trace give-up
```

The proposed model instead treats compilation as a **tiling problem**:

```text
hot bytecode/control region + observed facts
    -> choose executable tiles from a finite tile library
    -> copy/patch/link selected tiles
    -> observe exits and fact stability
    -> locally retile when profitable
    -> cache alternative tilings with hysteresis
```

A tile is not just code bytes. It is code plus a contract:

```text
Tile = pattern + code + patch holes + required facts + checked facts
     + produced facts + killed facts + exits + dependencies + cost model
```

The key idea is **decision propagation**:

```text
Choosing one tile can create stronger boundary facts.
Those facts may enable a better neighboring tile.
That neighboring tile may expose still more facts.
Repeated local retiling discovers optimizations incrementally.
```

This makes runtime JIT compilation more like a cheap fixed-point process over
native tiles than a one-shot translation of a trace.

---

## 2. Relation to existing designs

### 2.1 Interpreter

An interpreter can be seen as a tiler with one universal tile shape:

```text
[opcode handler] -> indirect dispatch -> [opcode handler] -> ...
```

The tile is correct and compact, but dispatch dominates and runtime constants are
not burned into the instruction stream.

### 2.2 Baseline JIT

A baseline JIT typically emits one machine-code fragment per bytecode:

```text
[bytecode 0 code] [bytecode 1 code] [bytecode 2 code] ...
```

This removes indirect dispatch and can burn bytecode operands into code. It is a
fixed tiling: one tile per bytecode, with limited local specialization.

### 2.3 Copy-and-Patch / Deegen-style baseline JIT

Copy-and-Patch turns precompiled object-code stencils into runtime codegen:

```text
build time:
  C/C++/IR semantic fragment -> compiler -> object file -> stencil bytes + relocs

runtime:
  memcpy stencil bytes -> patch relocation holes -> link continuations
```

Deegen demonstrates that this can generate high-quality baseline JIT code and
inline-cache stubs automatically from bytecode semantics.

In tiling terms, Copy-and-Patch gives us cheap tile materialization:

```text
copy + patch + link
```

This proposal uses that cheap materialization to support **repeated local retiling**,
not only initial bytecode-to-native translation.

### 2.4 LuaJIT-style tracing

A trace JIT records a hot path, specializes it, optimizes it, and emits code.
The trace is effectively a large tile:

```text
[whole optimized trace]
```

This can be excellent when the path is monomorphic and stable. The failure mode is
that frequent side exits mean the one chosen story is incomplete or unstable.

This proposal generalizes the unit:

```text
not one opcode only;
not one whole trace only;
but a variable-size adaptive tile cover.
```

---

## 3. Core concept: executable tiles

A tile covers a bytecode/control pattern under a fact contract.

```text
                  ┌──────────────────────────┐
input facts  ---> │          TILE            │ ---> output facts
                  │ code bytes               │
                  │ patch holes              │
                  │ guards/checks            │
                  │ side exits / slow paths  │
                  │ dependencies             │
                  └───────────┬──────────────┘
                              │
                              v
                       exit / fallback / IC miss
```

### 3.1 Tile record

A tile record should be explicit enough that a runtime tiler can select and link
it without understanding its internal assembly.

```c
typedef struct TileDesc {
    TileId id;

    PatternKey pattern;          // bytecode/window/control pattern covered
    FactMask required_facts;     // must be true at tile entry
    FactMask checked_facts;      // tile validates these with guards
    FactMask produced_facts;     // true on successful fallthrough/hit
    FactMask killed_facts;       // invalidated by writes/calls/effects

    ExitDesc exits[MAX_EXITS];   // guard fail, branch, call, yield, throw, etc.
    DepDesc deps[MAX_DEPS];      // table shape, metatable, call target, proto, etc.

    PatchDesc patches[MAX_PATCHES];
    RelocDesc relocs[MAX_RELOCS];
    ClobberDesc clobbers;

    uint32_t hot_size;
    uint32_t cold_size;
    uint32_t code_align;

    CostModel cost;
} TileDesc;
```

The tile's implementation can be produced by GCC object mining, handwritten
assembly, raw-byte templates, or another offline producer. Runtime selection should
not care which producer created it.

### 3.2 Tile examples

Generic opcode tile:

```text
ADD_generic_boundary
  covers:        ADD
  requires:      pc/base/top known, side-exit projection available
  checks:        none or minimal dispatch-compatible checks
  produces:      unknown result
  kills:         destination slot facts
  exits:         slow/interpreter boundary if dynamic semantics needed
```

Fact-specialized opcode tile:

```text
ADD_i64_guarded
  covers:        ADD
  requires:      stack layout known, side-exit projection available
  checks:        lhs is integer, rhs is integer
  produces:      dst is integer, dst freshly defined
  kills:         old dst facts
  exits:         guard_fail -> fallback/retile/interpreter
```

Fused tile:

```text
ADD_i64_RETURN1
  covers:        ADD; RETURN1
  requires:      return consumes ADD result, side-exit projection available
  checks:        lhs is integer, rhs is integer
  produces:      terminal return
  kills:         not relevant after return
  exits:         guard_fail -> fallback at ADD pc
```

IC-like tile:

```text
GETFIELD_shape_slot_IC
  covers:        GETFIELD / table string-key access
  requires:      key constant known
  checks:        receiver is table, shape id matches cached shape
  produces:      result loaded from known slot, optional value-kind fact
  deps:          table shape epoch, metatable epoch
  exits:         shape miss -> IC miss handler / fallback tile
```

---

## 4. Compilation as tiling

Given a hot region:

```text
pc0      pc1        pc2       pc3       pc4
LOADK -> GETTABLE -> ADD -> TEST/JMP -> RETURN
```

A tile cover may be:

```text
[LOADK] [GETTABLE_generic] [ADD_generic] [TEST_JMP] [RETURN]
```

or, after facts are known:

```text
[LOADK] [GETTABLE_array_i64 + ADD_i64] [TEST_JMP + RETURN]
```

or, for a stable hot loop:

```text
[loop_header_guard] [loop_body_supertile] [loop_backedge]
```

The runtime compiler is a tiler:

```text
Input:
  hot region R
  entry facts F
  observed profile P
  available tile library L

Output:
  executable plan = ordered/linkable tile cover of R
```

### 4.1 Cost function

The tiler minimizes expected cost, not just static instruction count.

```text
cost(plan) =
    expected_cycles(plan)
  + exit_probability(plan) * exit_cost(plan)
  + code_size_penalty(plan)
  + materialization_cost(plan)
  + invalidation_risk(plan)
  + hysteresis_margin(plan_switch)
```

Where:

- `expected_cycles` comes from offline measurements, static estimates, and runtime
  counters;
- `exit_probability` comes from observed guard failures / side exits;
- `materialization_cost` is low for copy-and-patch but not zero;
- `invalidation_risk` penalizes brittle dependencies like table shapes or call
  targets if they churn;
- `hysteresis_margin` prevents oscillation between near-equal plans.

### 4.2 Dynamic programming sketch

For a linear trace window, a simple DP tiler is enough for an MVP.

```text
best[0] = empty plan
for i in 0..n-1:
  for each tile t starting at i:
    if t.required_facts satisfied by facts_at[i]:
      j = i + t.covered_len
      next_facts = transfer(facts_at[i], t)
      candidate = best[i] + t
      update best[j] if candidate cheaper
```

The important part is that tile transfer changes boundary facts:

```text
facts_after_tile =
    (facts_before - tile.killed_facts)
  + tile.produced_facts
  + facts_guarded_on_success(tile.checked_facts)
```

For control-flow regions, the same concept becomes graph covering with edge
frequencies. The MVP should start with linear hot traces and small branch diamonds.

---

## 5. Fact propagation and decision propagation

### 5.1 Facts are boundary summaries

Facts are not merely profiling annotations. They are boundary summaries that make
tile composition legal and profitable.

```text
[Tile A] --produces facts--> [Tile B] --produces facts--> [Tile C]
```

Example:

```text
[ADD_i64_guarded]
  on success produces: dst is integer

[RETURN1_slot]
  if it consumes dst, can become: ADD_i64_RETURN1
```

### 5.2 Decisions create scoped facts

A fact can be observed, proven, guarded, or chosen.

```text
observed fact:
  slot 1 was integer in the last N executions

checked fact:
  this tile verifies slot 1 is integer before using it

produced fact:
  this tile writes an integer to slot 2

decision fact:
  this plan chooses the integer path and routes non-integers to an exit
```

The last category is why **decision propagation** is more precise than plain fact
propagation. Choosing a guarded tile creates a scoped world:

```text
inside this plan, after this guard succeeds, slot 1 is integer
```

That scoped fact may enable neighboring optimizations.

### 5.3 Compiler-pass analogy

Classic optimization passes often work because one simplification exposes another:

```text
constant fold -> dead-code elimination -> copy propagation -> more folding
```

Here the native-tile analog is:

```text
tile choice -> boundary fact -> neighbor retile -> stronger tile -> more facts
```

Example progression:

```text
generation 0:
[GETTABLE_generic] [ADD_generic] [RETURN1]

runtime observes:
  table shape stable
  key is integer
  ADD operands are integer
  RETURN consumes ADD result

generation 1:
[GETTABLE_array_i64] [ADD_i64] [RETURN1]

generation 2:
[GETTABLE_array_i64 + ADD_i64] [RETURN1]

generation 3:
[GETTABLE_array_i64 + ADD_i64 + RETURN1]
```

The optimization was discovered incrementally, not all at once.

---

## 6. Retiling instead of one-shot recompilation

A one-shot trace compiler asks:

```text
Can I compile this trace well enough?
```

A tiling JIT asks:

```text
Is the current tile cover still the best cover for the observed behavior?
```

Side exits are not only failures; they are feedback.

```text
side exit = evidence that a tile, seam, or fact decision is mispriced/incomplete
```

### 6.1 Local repair

If one tile exits too much:

```text
Plan V0:
[A] [B_fast] [C] [D]
       |
       v
   hot exits
```

Repair only the neighborhood:

```text
Plan V1:
[A] [B_weaker] [C_specialized] [D]
```

or split into cases:

```text
Plan V1:
[A] [B_i64]     [D]
[A] [B_f64]     [D]
[A] [B_generic] [D]
```

This avoids throwing away the whole region when the problem is local.

### 6.2 Plan versions

Each compiled region has immutable published plans.

```c
typedef struct PlanVersion {
    RegionId region;
    uint32_t generation;
    FactSignature signature;
    TileId *tiles;
    void *entry;
    ExitCounters exits;
    HitCounters hits;
    CostEstimate cost;
    DependencySet deps;
    struct PlanVersion *fallback;
} PlanVersion;
```

Publication should be atomic with respect to executing threads/coroutines. Old
plans can be reclaimed when no frames can return to them.

---

## 7. Hysteresis and cached alternatives

Some regions do not have one stable best plan. They have modes.

```text
mode A: integers dominate
mode B: floats dominate
mode C: table shape 17 dominates
mode G: generic fallback
```

A trace compiler may see frequent exits and give up. The tiling model caches
alternatives:

```text
Region R cache:
  signature i64-heavy          -> Plan A
  signature f64-heavy          -> Plan B
  signature table-shape-17     -> Plan C
  unknown / unstable           -> Plan G
```

This is a region-scale generalization of inline caching.

```text
inline cache:
  one site caches multiple cases

tiling JIT:
  one region caches multiple tile covers
```

### 7.1 Avoiding thrash

Naive retile-on-exit will oscillate. Use hysteresis.

```text
specialize if:
  observed benefit > high threshold

despecialize/switch away only if:
  sustained failure > lower-confidence threshold for long enough
```

Diagram:

```text
          specialize threshold
                 ▲
                 │
generic ─────────┼──────────────> specialized
                 │
                 ▼
          despecialize threshold
```

Example thresholds:

```text
switch generic -> i64 plan if i64 success rate > 80% over N hits
switch i64 plan -> generic only if i64 success rate < 55% over M hits
```

The gap prevents ping-pong.

### 7.2 Cached retile

Retiling cost is amortized:

```text
first time mode A appears: materialize Plan A
first time mode B appears: materialize Plan B
later switches: choose cached plan, do not regenerate code
```

The runtime policy becomes:

```text
if current plan exits too much:
  sig = classify observed mode
  if cache has plan for sig:
    switch/link to cached plan
  else if profitable under hysteresis:
    retile, publish, cache
  else:
    use generic fallback
```

---

## 8. Runtime architecture

### 8.1 Offline/build-time responsibilities

The expensive work happens offline:

```text
- generate candidate tiles;
- compile C/assembly templates with GCC or assembler;
- mine object bytes, relocations, holes, hot/cold sections;
- verify tile contracts;
- benchmark or estimate tile costs;
- export tile library and selector metadata.
```

The runtime must not do general code generation or optimization over arbitrary IR.
It should only:

```text
observe -> match -> tile -> copy -> patch -> link -> publish
```

### 8.2 Runtime responsibilities

Runtime loop:

```text
1. Interpret or execute existing plan.
2. Collect counters:
   - hit counts;
   - guard failures;
   - side-exit reasons;
   - branch frequencies;
   - observed value/table/call facts;
   - dependency invalidations.
3. Identify hot region or bad seam.
4. Select tile cover from finite library.
5. Materialize with copy-and-patch.
6. Publish PlanVersion.
7. Revisit only when counters justify it.
```

### 8.3 High-level flow

```text
               ┌──────────────────────┐
               │ Interpreter / Plan N │
               └──────────┬───────────┘
                          │ profile, exits, facts
                          v
                 ┌──────────────────┐
                 │ Region Analyzer  │
                 └────────┬─────────┘
                          │ hot region / bad seam
                          v
                 ┌──────────────────┐
                 │ Runtime Tiler    │
                 └────────┬─────────┘
                          │ tile cover
                          v
                 ┌──────────────────┐
                 │ Copy/Patch/Link  │
                 └────────┬─────────┘
                          │
                          v
                 ┌──────────────────┐
                 │ Publish Plan N+1 │
                 └──────────────────┘
```

---

## 9. Copy-and-patch details relevant to this design

### 9.1 Runtime constants

A tile needs patch holes for runtime constants:

```text
- bytecode operands;
- stack slot offsets;
- constant table addresses;
- branch targets;
- slow-path data pointers;
- IC state pointers;
- dependency/version cells;
- continuation addresses.
```

For compiler-produced stencils, these holes are usually represented as external
symbols and relocation records in the object file.

### 9.2 Derived constants

Do not only patch root bytecode operands if the compiled code wants derived forms.
For example:

```text
slot ordinal -> slot byte offset = base + slot * sizeof(Value)
```

A good tile producer should expose derived patch constants so the final code can
use immediate addressing modes instead of computing offsets at runtime.

### 9.3 Symbol/address range caveat

When using external-symbol addresses as pseudo-constants, the native compiler and
ABI may assume symbol addresses live in a restricted range. A correct pipeline must
ensure patched values respect the addressing-mode/code-model assumptions used to
compile the stencil, or transform constants so they do.

For x86-64 small code model, this usually means being careful with signed 32-bit
addressing displacements and compiler assumptions about external symbol ranges.
If the value cannot be represented safely, the tile should either use a different
patch form or be rejected for that target.

### 9.4 Hot/cold split

Tiles should be allowed to have hot and cold sections:

```text
hot path: guards and common success path
cold path: slow setup, IC miss, interpreter bridge, error/yield/call boundary
```

The tiler links hot paths for locality and can place cold paths separately.

### 9.5 Jump-to-fallthrough

If tile A's success continuation is tile B immediately following in memory, the
linker/materializer should be able to erase or avoid an unconditional jump:

```text
[A ... jmp B] [B ...]
```

becomes:

```text
[A ... fallthrough] [B ...]
```

This matters because tile covers are meaningful only if seams are cheap.

---

## 10. Fact and dependency discipline

This document does not prescribe the final fact vocabulary, but it prescribes the
shape facts must have.

A usable fact must answer:

```text
1. Who established it?
2. Is it observed, required, checked, produced, or decided?
3. What scope is it valid in?
4. What invalidates it?
5. What projection is needed if it fails?
6. Which tile choices does it unlock?
```

### 10.1 Fact kinds by role

```text
ObservedFact:
  learned from profiling; not sufficient for unsafe code by itself.

RequiredFact:
  must be guaranteed by predecessor tile/guard/entry condition.

CheckedFact:
  validated by this tile; true only on success edge.

ProducedFact:
  created by this tile's semantics on success.

KilledFact:
  invalidated by this tile's writes/effects.

DecisionFact:
  introduced by choosing a guarded/specialized plan; scoped to success path.
```

### 10.2 Dependencies

Speculative facts need invalidation mechanisms:

```text
- table shape epoch;
- metatable epoch;
- global slot epoch;
- closure/call target epoch;
- upvalue location/version;
- debug hook state;
- GC barrier protocol state;
- proto/code identity.
```

A tile that assumes such a dependency must record it in the plan. If the dependency
changes, the plan is invalidated or redirected to fallback.

### 10.3 Projection

Every side exit must be able to reconstruct the lower-tier state:

```text
- pc to resume at;
- frame/base/top;
- live stack slots;
- pending return/call state;
- materialized values for virtualized/reordered operations;
- error/yield/debug-hook observability state.
```

If projection is not known, the tile is not legal, regardless of performance.

---

## 11. Selection and retiling algorithm

### 11.1 Region selection

Start with simple regions:

```text
- linear hot traces;
- loop bodies with one backedge;
- small branch diamonds;
- local windows around hot exits.
```

Avoid whole-program or arbitrary CFG tiling until the linear model works.

### 11.2 Local retile loop

```text
while budget_remaining:
    spot = choose_hot_exit_or_expensive_seam(region)
    window = expand_window(spot, max_ops = K)

    entry_facts = facts_at_window_entry(window)
    observed = profile_for_window(window)

    covers = enumerate_legal_covers(window, entry_facts, observed)
    best = choose_min_cost(covers)

    if best improves current by hysteresis_margin:
        materialize best
        publish new plan version
        cache by fact signature
    else:
        mark window stable or raise threshold
```

### 11.3 Enumeration control

The tile library can be large. Runtime enumeration must be bounded:

```text
- maximum window size;
- maximum tile count per cover;
- preindexed selector tables by PatternKey and FactSignature;
- reject tiles whose dependencies are currently unstable;
- prefer observed fact signatures;
- cap code size and materialization budget per time slice.
```

The runtime tiler should be predictable enough that worst-case behavior is bounded.

---

## 12. Example: arithmetic return

Bytecode:

```text
pc0: ADD     R2, R0, R1
pc1: RETURN1 R2
```

Initial plan:

```text
[ADD_generic] [RETURN1]
```

Profile observes:

```text
R0 integer 99% of hits
R1 integer 99% of hits
ADD result immediately returned
non-integer exits rare
```

Retile:

```text
[ADD_i64_guarded] [RETURN1]
```

Facts after ADD success:

```text
R2 is integer
R2 freshly produced
R2 consumed by RETURN1
```

Next retile:

```text
[ADD_i64_RETURN1]
```

If integer guard failures later rise above threshold:

```text
cache keeps ADD_i64_RETURN1 for integer mode
fallback uses ADD_generic_RETURN1 or [ADD_generic][RETURN1]
```

---

## 13. Example: table access plus arithmetic

Bytecode:

```text
pc0: GETTABLE R2, R0, R1
pc1: ADD      R3, R2, R4
pc2: RETURN1  R3
```

Generation 0:

```text
[GETTABLE_generic] [ADD_generic] [RETURN1]
```

Observed mode:

```text
R0 is table
R1 is integer
array hit
metatable absent
GETTABLE result usually integer
R4 integer
```

Generation 1:

```text
[GETTABLE_array_guarded] [ADD_i64_guarded] [RETURN1]
```

Boundary propagation:

```text
GETTABLE_array_guarded success -> R2 loaded from array, maybe value-kind observed
ADD_i64_guarded success        -> R3 integer and freshly produced
RETURN1 consumes R3
```

Generation 2:

```text
[GETTABLE_array_i64 + ADD_i64] [RETURN1]
```

Generation 3:

```text
[GETTABLE_array_i64 + ADD_i64 + RETURN1]
```

If the table shape alternates between two shapes, cache two plans or use a
polymorphic tile/IC chain:

```text
Plan A: shape 17 fast path
Plan B: shape 23 fast path
Plan G: generic fallback
```

---

## 14. Engineering invariants

The following invariants are non-negotiable.

### 14.1 Correctness

```text
- Interpreter semantics are the source of truth.
- Every tile contract is verified against its semantic expansion.
- Every guard failure has a precise exit target and projection.
- Every speculative dependency is recorded and invalidatable.
- Debug hooks, errors, yields, metamethods, and GC barriers are not skipped.
- No tile may hide an observable Lua effect behind a pure-looking fact.
```

### 14.2 Runtime simplicity

```text
- Runtime does not run GCC/LLVM.
- Runtime does not synthesize arbitrary machine code.
- Runtime only selects, copies, patches, links, and publishes known tiles.
- Runtime enumeration and retiling budgets are bounded.
```

### 14.3 Plan management

```text
- Plan versions are immutable once published.
- Plan switching is atomic.
- Old plans remain valid until no execution can return to them.
- Invalidation redirects to fallback or interpreter before freeing code.
```

### 14.4 Measurement discipline

```text
- Retiling is driven by counters, not hope.
- Hysteresis prevents oscillation.
- Code size and compile/materialization cost are part of the score.
- A specialized tile with high exit rate is worse than a generic tile.
```

---

## 15. MVP proposal

A minimal prototype should prove the model without solving every VM problem.

### 15.1 Tile library

```text
L0:
  one generic tile per opcode or opcode boundary

L1:
  one-op fact-specialized tiles:
    ADD_i64
    SUB_i64
    MUL_i64
    LT_i64
    EQ_i64
    GETTABLE_array_guarded
    GETFIELD_shape_guarded
    CALL_known_boundary
    RETURN1

L2:
  small fused tiles:
    ADD_i64_RETURN1
    TEST_JMP
    LT_i64_BRANCH
    GETTABLE_array_i64_ADD_i64
```

### 15.2 Runtime support

```text
- linear hot trace recording;
- per-tile hit and exit counters;
- simple fact signatures for integers/table shape/call target;
- DP tiler over windows of 2..8 opcodes;
- plan cache keyed by region + fact signature;
- hysteresis thresholds;
- copy-and-patch materializer;
- fallback to interpreter.
```

### 15.3 Success criteria

The MVP succeeds if it demonstrates:

```text
1. local retile improves a hot region without recompiling the whole function;
2. propagated facts enable a fused tile not selected in generation 0;
3. cached alternatives avoid repeated recompilation for polymorphic behavior;
4. hysteresis prevents plan thrashing;
5. fallback/projection correctness survives guard failures.
```

---

## 16. Open questions

These are deliberately left open for engineering exploration.

```text
- How large should retile windows be before overhead dominates?
- How rich should fact signatures be before cache explosion occurs?
- Which facts should be guarded inline vs delegated to IC stubs?
- How should branchy CFG regions be tiled beyond linear traces?
- How should code memory be reclaimed under coroutines and side exits?
- What is the best policy for generic fallback strengthening?
- How much hot/cold splitting is needed for tile seams to remain cheap?
- How often should plan switching occur in phase-changing workloads?
```

---

## 17. Summary

The proposed JIT technique is:

```text
Hysteretic Fact-Propagating Tiling JIT
```

Its central claims are:

```text
1. JIT compilation can be modeled as executable tiling.
2. Copy-and-Patch makes tile materialization cheap enough for repeated local retile.
3. Tile decisions produce scoped boundary facts.
4. Those facts propagate to neighbors and unlock further local optimizations.
5. Side exits are feedback for retiling, not just trace failure.
6. Polymorphic or phase-changing regions should cache multiple tilings.
7. Hysteresis makes this adaptive system stable instead of thrashy.
```

Short slogan:

```text
JIT = adaptive tiling + decision propagation + cached retile.
```

Or:

```text
Trace instability is not failure.
It is evidence that the region needs another tile cover.
```
