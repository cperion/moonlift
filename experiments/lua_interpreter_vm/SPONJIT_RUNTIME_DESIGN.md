# SponJIT Runtime Design — Greedy Adaptive Image Materialization from a Bank

**Type:** JIT architecture spine
**Audience:** VM / C / assembly engineers
**Status:** design; shadow validation in progress

SponJIT does not compile traces. It does not maintain a code cache of newly
compiled artifacts. It does not run an optimizer. The runtime is a **bank selector**:
per region it holds a floor image, an active image, and small tile-site memory for
fact exits / hysteresis. Everything code-generating lives offline.

```text
The bank is the system. The runtime selects templates from it and materializes images.
```

Terminology invariant:

```text
Bank          = immutable library of TileTemplates / stencils
TileTemplate  = prebuilt bytes + holes + contracts + exits + projection metadata
Image         = executable cover produced at runtime by selecting TileTemplates,
                copy-patching them, linking their continuations, and publishing code

The bank does not contain images. The runtime builds images from bank templates.
```

The foundry enumerates, dedupes, and ships a read-only bank of fused tile templates.
The runtime mmap's the bank at startup, observes facts in hot regions, greedily
picks a tile sequence from bank templates, copy-patches the selected templates into
an executable image, and publishes the image by atomically repointing the region's
active pointer. A guard failure projects state, reports a fact delta, and asks the
selector to move down the candidate ladder for that failed span. If no weaker
same-span candidate works, the span is split; if splitting reaches arity 1, L0 is
guaranteed.

The main contrast with LuaJIT is not that SponJIT precompiles. It is the binding
time:

```text
LuaJIT:
  runtime observes -> runtime records -> runtime optimizes SSA/IR -> runtime emits

SponJIT:
  offline foundry enumerates + optimizes + dedupes -> bank
  runtime observes facts -> selects from bank -> copy/patch -> swap image
```

Copy-and-patch materialization is cheap enough to allow the runtime to be wrong. A
failed assumption is not a failed image in the trace-JIT sense; it is a request to
choose the next valid bank candidate for that span. The replacement is another image
materialized from bank templates, not a recompilation.

---

## 0. Thesis

```text
Offline:
  the foundry enumerates bounded tile compositions,
  consumes facts with SSA,
  normalizes/dedupes semantic forms,
  enumerates multimorphic fact-env unions where corpus pressure justifies them,
  and exports verified copy-and-patch tile templates as a read-only bank.

Runtime:
  per region, hold a floor (L0 image, always installed), an active pointer,
  and small tile-site memory.
  observe facts in hot regions under hysteresis.
  greedily select the largest / highest-score TileTemplates the current leases allow.
  copy-patch the tiles into a fresh image. atomically repoint active.
  on guard failure, record the exit fact delta and move the failed span down its
  candidate ladder: weaker same-span tile -> multimorphic/generic same-span tile
  -> split into lower-arity tiles -> L0 floor.
  because L0 is total, region cover replacement never misses.

The runtime never builds anything that was not already in the bank.
It never compiles. It never optimizes. It never reasons about fact consequences.
It selects, copies, patches, and swaps. That is the JIT.
```

The system can be wrong because being wrong is cheap:

```text
guard failure  = observed fact delta = local request to choose a weaker candidate
bank miss      = same-span replacement missed; split the span, eventually reaching L0
```

Neither case requires the runtime to think. The first case logs a fact for the next
training corpus; the second case is the megamorphic response by definition.

The stable state is not one optimized trace and not a cache of monomorphic artifacts.
It is the region's natural adaptive mesh:

```text
coarse tiles where facts are stable,
weaker or multimorphic tiles where facts alternate predictably,
fine tiles where only a small articulation point is polymorphic,
L0 floor tiles where the bank has no useful specialization.
```

The simplicity comes from delegating semantic/code-generation decisions to the
foundry, where they can be exhaustive, measured, and capped, and reducing runtime
adaptation to bounded bank selection.

---

## 1. Runtime responsibility

The runtime is intentionally simple, but not blind.

```text
runtime responsibilities:
  collect cheap hotness / residual counters
  burst-record facts when pressure crosses a threshold
  canonicalize observed facts into local lease state
  greedily select TileTemplates from the bank under hysteresis
  copy/patch/link selected tiles into a fresh image
  atomically swap the region's active pointer
  record guard exits as fact deltas
  maintain small tile-site penalties/cooldowns to avoid oscillation
  repair by candidate-ladder descent and span splitting, not runtime compilation
```

Runtime does **not**:

```text
run SSA
run a graph optimizer
maintain a mutable runtime artifact cache
manage cache eviction
reason about semantic fact consequences
choose which guards are redundant by analysis
synthesize new instructions
lower new machine code
run a general register allocator
detect megamorphism via dedicated logic
```

The only executable thing the runtime *adapts* over time is the active pointer. The
bank is read-only and the floor is fixed. Tile-site memory is metadata only: it
records recent exits, unstable facts, and cooldowns so the next image build chooses
a less brittle bank candidate.

Rule:

```text
Foundry creates the bank of TileTemplates.
Runtime builds the active image by selecting TileTemplates from the bank.
The floor is always there underneath.
```

---

## 2. The bank

The bank is the only multi-entry data structure in SponJIT. It is built offline by
the foundry, written to disk as a self-contained file, and mmap'd read-only at VM
startup.

```text
Bank layout (sketch):
  header
    magic, version, target ABI, ISA flags
    layer 0 directory  (raw-op tiles, arity 1..4; arity-1 is total)
    layer 1 directory  (meta-tiles: arity 1..4 over L0 atoms)
    layer 2 directory  (meta-tiles: arity 1..4 over L1 atoms)
    layer 3 directory  (meta-tiles: arity 1..4 over L2 atoms)
    multimorphic directory  (tiles enumerated over fact-env unions)
  selector index
    key:   (pattern_hash, fact_signature)
    value: tile_id
  tile records
    bytes + relocation table + exit descriptors + projection metadata
    + dependency epoch references + cost estimate + foundry identity
  string/symbol tables for HOLE names
  dependency epoch table layout
```

The bank is **immutable at runtime**. The runtime never writes to it. New banks are
produced by offline training runs and shipped as part of a VM update or, when
opted in, generated per-program via a profile-guided rebuild step. Bank rebuilds are
not part of the live JIT loop.

Selection is a bounded walk over a pre-sorted candidate ladder, not a compiler pass:

```text
candidates = bank.lookup_candidates(pattern_key)   -- sorted by foundry score
for tile in candidates:
    if tile.required_facts ⊆ local_leases and not penalized(tile):
        choose tile
```

A miss at one ladder level is not an error. It means the current span has no legal
candidate under the local leases and penalties. The runtime then tries a weaker
same-span candidate, then the tile's lower-layer child cover, and finally L0
arity-1. There is fallback search over the finite bank; there is no cache promotion,
no synthesis, and no code generation.

### 2.1 Layered bank, single active selection

The bank is layered by **recursive composition depth**, not by raw opcode arity.
The arity limit is always 1..4. What changes per layer is the atom being composed:
raw PUC opcode at L0, selected L0 atom at L1, selected L1 atom at L2, and so on.
A separate directory may hold multimorphic tiles (§7).

```text
bank layers      (built by foundry, indexed offline)
  L0  arity 1..4 over raw PUC opcodes; arity-1 is total and forms the floor
  L1  arity 1..4 over L0 atoms       (up to 16 raw ops)
  L2  arity 1..4 over L1 atoms       (up to 64 raw ops)
  L3  arity 1..4 over L2 atoms       (up to 256 raw ops)
  Lm  multimorphic fact-env unions   (§7)

runtime image   (one per region, built by selection)
  a sequence of tiles/meta-tiles, each drawn from some bank layer,
  covering the region's PCs left to right.
```

The runtime does not run four layers at once for a PC. It selects one cover. On a
higher-layer tile exit, replacement descends to weaker same-span candidates or to
that tile's child metaops; descent can repeat until L0 arity-1, which is total.

A region's active image is a heterogeneous sequence: a stretch of hot stable
arithmetic might be covered by an L3 tile, an adjacent call boundary might fall to an
L0 tile, an articulation between them might land on a multimorphic tile, the rest of
the function might stay at L0. The cover is what the bank can supply for the
observed facts at each PC, no more.

---

## 3. Per-region state

The runtime holds a small amount of metadata per hot region:

```c
typedef struct TileSiteMemory {
    uint16_t fail_count;
    uint16_t success_count;
    uint16_t cooldown;
    uint64_t recently_failed_facts;
} TileSiteMemory;

typedef struct Region {
    Image     *floor;   /* L0 image; never moves; always executable */
    Image     *active;  /* currently-selected image; may equal floor */
    uint32_t  hyst;     /* selection-attempt timing */
    TileSiteMemory *sites; /* one logical site per selected span / pc anchor */
    /* ... metadata: pc range, fact buffer, counters ... */
} Region;
```

```text
floor    points to a pre-built L0 image for the region. Composed at VM startup
         from L0 tiles in the bank (one per PC). Never deallocated. Never modified.
         It is the always-legal execution path.

active   points to the currently-installed image for the region. Initially equal
         to floor. When selection succeeds, active points at a freshly-built image
         richer than floor. When all guards in active succeed, active is used.
         When a guard fails, the exit projects state and execution continues in
         floor for the rest of that iteration.

hyst     a single integer that controls when selection is attempted.
         Selection is expensive (signature canonicalization, bank lookup,
         copy-patch, atomic publish). It does not run on every observation.
         hyst gates it: only attempt selection when facts have been stable
         for N consecutive observations.
```

That is still not a compiler cache. The executable state is two pointers: floor and
active. The extra site memory is small selector state used to avoid oscillation and
to walk the bank ladder intelligently.

### 3.1 Floor is mandatory and always installed

The floor is not a slow path that gets reached after the active image fails. The
floor is the **baseline executable form** of the region. It exists from the moment
the region is loaded. It is composed once at VM startup (or on first execution of
the region, depending on lazy/eager policy) by selecting L0 TileTemplates from the bank for
each PC.

```text
no region exists without a floor.
no PC exists without an L0 tile (L0 is one tile per generic opcode; the bank
  guarantees full coverage of the opcode set).
no signature, no facts, no observation is needed for the floor to be installed.
```

This is what makes "bank miss" a safe response: the floor is already there, already
executable, already correct. A bank miss does not stall, does not block on
compilation, does not throw. It is the no-op case of selection.

### 3.2 Image structure

An Image is an immutable, executable byte sequence with metadata:

```c
typedef struct Image {
    void          *code;        /* mmap'd RX page(s); the tile sequence */
    size_t         code_size;
    TileRef       *tiles;       /* which bank tile covers each PC range */
    uint32_t       n_tiles;
    ExitDesc      *exits;       /* per-tile guard exit projections */
    DependencySet  deps;        /* epochs this image speculates on */
    Image         *fallback;    /* always the region's floor */
    uint32_t       generation;
} Image;
```

```text
- code is the contiguous result of copy-patching the selected tiles in order
- exits carry projection metadata for each guard within each tile
- deps lists every shape/metatable/call-target epoch the image speculates on
- fallback is always the region's floor — there is no chain
- generation is a publication ordinal, monotonic per region
```

Images are immutable once published. A new image supersedes an old one by atomic
pointer swap of `region.active`. The old image is retained until no executing thread
is inside it, then freed. This is RCU-style code memory management; nothing more.

---

## 4. The selection step

Selection is the **only adaptive operation** at runtime. It runs under hysteresis,
not on every observation.

### 4.1 Inputs

```text
region              -- which hot region is being selected for
observed_facts      -- the burst-recorded fact distribution at this region's PCs
window              -- the contiguous run of PCs being covered
```

### 4.2 Canonicalization

Observed facts are reduced to a canonical signature. The signature is computed from
a fixed projection of the fact vocabulary onto the axes the foundry trained on:

```text
signature axes (the bank's training axes):
  numeric kind per slot         (i64 / f64 / other)
  table shape epoch per slot    (shape id or unknown)
  metatable presence per shape  (absent / present-known / unknown)
  known call target per call    (target id or unknown)
  array-vs-hash classification  per indexed access
  constant-key classification   per field access
  loop schema class             (counted / generic / none)
```

Anything not in this list is **projected out** before the lookup. Residency state,
exact constant values when only type matters, exact object identity when shape is
enough, debug-only metadata — none of it affects the key. The projection is the same
projection the foundry used when training; the runtime simply applies it to the
observed facts.

### 4.3 Greedy bank selection

Initial selection is optimistic and coarse-first:

```text
for pc in region:
  for len = min(4, region_end - pc) downto 1:
    pattern_key = encode(bytecode[pc .. pc+len))
    candidates  = bank.lookup_candidates(pattern_key)  -- best-first foundry score
    for tile in candidates:
      if tile.required_facts ⊆ local_leases and !site_penalizes(tile):
        emit tile into image
        pc += len
        goto next_pc
  emit L0(opcode[pc])
  pc += 1
```

The L0 fallback is guaranteed to succeed for every opcode, because L0 covers the
full opcode set with generic tiles. Selection therefore always produces an image;
the only question is how rich/coarse the image is.

On exit, the same selector is run with updated site memory. The failed span first
tries same-arity weaker candidates. If none work, the span is split and lower-arity
selection covers the subspans. Therefore:

```text
same-span replacement may miss;
same-region cover never misses because L0 is total.
```

### 4.4 Materialization

```text
allocate fresh RX page(s) sized for the tile sequence
for each tile_id:
    copy the tile's .text bytes into the image
    for each relocation in the tile's reloc table:
        compute the hole's runtime value
            (slot index, constant pool entry, exit target, dependency cell, ...)
        write the value at the hole's offset
record exit descriptors and dependency epochs in the Image header
mprotect the page RX
```

This is the same primitive as Deegen's copy-and-patch, applied to fused tiles. The
runtime touches no compiler.

### 4.5 Publish

```text
old_active = region.active
atomic_store(&region.active, new_image)
schedule old_active for free once no thread is executing in it
```

Atomicity is at the pointer level. Threads in `old_active` continue until they exit;
threads entering the region after the store see `new_image`. No lock; no stop-the-
world; no patching live code.

### 4.6 What selection does not do

```text
no SSA construction
no graph rewrite
no code synthesis
no general DP over a cost model
no register allocation
no exit-target rewriting
no new tile discovery
no cache eviction (there is no cache)
```

The cover the runtime produces is whatever the bank supplies for the observed
signatures. If the bank's coverage is poor, the image is mostly L0. If the bank's
coverage is rich, the image is mostly L2/L3/Lm. The runtime does not invent.

---

## 5. Hysteresis — selection-attempt timing

Hysteresis exists for one job: prevent selection from running on transient facts.

```text
on each burst-recorded observation at a region:
  if observed_signature == last_observed_signature:
      region.hyst += 1
  else:
      region.hyst  = 0
      last_observed_signature = observed_signature

  if region.hyst > selection_threshold AND
     region.active == region.floor:
      attempt selection
      reset region.hyst
```

That is the entire hysteresis machinery: one counter, one threshold, one comparison.
The counter advances when facts are stable and resets when they change. Selection
fires only when stability persists.

### 5.1 Hysteresis on exits and replacement

A guard failure is first a local selector event, not whole-region demotion.

```text
on tile exit:
  integrate observed fact delta into local lease state
  mark contradicted facts unstable at this tile site
  increment site fail_count / cooldown

  replacement = same_span_candidate_ladder(site, leases, penalties)
  if no replacement:
      replacement = lower_arity_cover(site.span, leases, penalties)
  if still no replacement:
      replacement = L0 cover for the span

  build a fresh image using old choices except the replacement span(s)
  atomic_store(&region.active, new_image)
```

The MVP may rebuild the whole image after computing this local replacement. The
conceptual operation remains local: a failed tile asks to move down or sideways in
its candidate ladder. Whole-region demotion to floor is reserved for extreme cases
such as repeated replacement failure, dependency invalidation, or memory pressure.

### 5.2 What hysteresis does not gate

```text
hysteresis does not gate compilation (there is none)
hysteresis does not gate cache eviction (there is no cache)
hysteresis does not gate megamorphic cutoff (the cutoff is bank-miss, §6)
```

Hysteresis gates *whether to attempt the bank lookup*. That is its scope.

---

## 6. Bank-miss is local ladder descent

In a cache-based JIT, the megamorphic cutoff is a runtime decision: detect that too
many signatures are appearing at a site, give up specializing, fall back. In
SponJIT, the response is local and bounded:

```text
the runtime attempts selection for a span.
selection walks the bank's candidate ladder for that pattern.
if no candidate is legal under current leases/penalties, split the span.
if splitting reaches arity 1, select L0.
that is the megamorphic response.
```

The foundry has already decided what tile shapes are worth shipping. A signature
the foundry did not enumerate is, by the foundry's own measurement, not worth that
particular specialized tile. The runtime inherits that decision by walking down to
a weaker candidate, a smaller cover, or the L0 floor.

### 6.1 Coarsening at the foundry, not the runtime

The traditional megamorphic response is to coarsen the signature: instead of
specializing on each shape, specialize on "anything with this field at this offset"
or "any numeric kind". In SponJIT this coarsening is a foundry-time tile-shape
decision (multimorphic tiles, §7). The runtime does not coarsen on the fly. It
either finds a tile or doesn't.

```text
foundry knows from corpus pressure: PC X often sees shapes {S1, S2, S3}.
foundry enumerates: a multimorphic tile that branches internally on shape.
foundry ships: that tile in the bank's multimorphic directory.
runtime observes: shapes S1..S3 at PC X.
runtime canonicalizes: signature = multimorphic-{S1,S2,S3}.
runtime selects: the multimorphic tile.
done.

if instead foundry never saw {S1,S2,S3} together:
  runtime canonicalizes: signature = mixed-shape (unknown).
  same-span specialized lookup misses.
  selector walks to weaker/generic same-span candidates, then smaller tiles, then L0.
  the miss is logged. next foundry training run may add a better tile.
```

This is why the runtime can be so simple: every code shape is precomputed, and the
live response is only ladder descent over that finite vocabulary.

---

## 7. Multimorphism is foundry-side

A PC that sees multiple stable signatures is not a runtime cache problem in
SponJIT. It is a tile-shape problem solved offline.

```text
observed runtime pattern at PC X:
  iteration 1: signature S1
  iteration 2: signature S2
  iteration 3: signature S1
  iteration 4: signature S2
  ...

old (cache-based) response:
  cache two monomorphic images, one for S1 and one for S2,
  dispatch by per-iteration signature canonicalization.

SponJIT response:
  foundry enumerates a multimorphic tile T_{S1∨S2} with an internal branch
    on a cheap discriminator (tag bits, shape epoch, call target id).
  bank holds T_{S1∨S2} once.
  runtime selects T_{S1∨S2}; the per-iteration branch lives inside the tile,
    compiled by GCC, with both arms specialized for their respective signatures.
```

The runtime never sees "two signatures at one PC". It sees one multimorphic signature
("any of {S1, S2}") and selects one tile.

### 7.1 What the foundry enumerates

The foundry does not enumerate every possible fact-env union — that is
combinatorial. It enumerates unions that **the training corpus observed**:

```text
corpus pressure data from AWFY + Moonlift (and any added workload):
  per PC, distribution of observed signatures across runs.

union enumeration policy:
  if a PC's top-K signatures cluster (e.g. top-2 covers > 90%):
      enumerate a multimorphic tile for the union of those K signatures.
  if a PC's signatures are flat-distributed across many shapes:
      no multimorphic tile. PC will fall to floor at runtime for that signature.
```

This keeps the bank's multimorphic directory bounded. The foundry only builds
multimorphic tiles for unions the world actually exhibits.

### 7.2 What multimorphic tiles look like inside

A multimorphic tile is a single fused tile with an internal discriminator. The
discriminator is the cheapest test that separates the union's arms — usually a
single load + compare against an immediate or a small switch:

```text
multimorphic ADD over {i64, f64}:
  load tag of lhs
  jump-table or compare-branch
    arm i64:  unboxed i64 add path
    arm f64:  unboxed f64 add path
    exit:     residual (state projection to floor)
  store result
```

The discriminator is a few cycles. The arms are as specialized as their monomorphic
counterparts would be. GCC compiled the whole thing in one go; the branch predictor
sees a consistent pattern (one arm dominates per call site over a given window).

From the runtime's perspective the tile is one selection, one swap, no cache lookup
per iteration. The polymorphism is internal to the compiled code.

### 7.3 Megamorphism is "no multimorphic tile available"

When a PC sees so many signatures that no multimorphic tile in the bank covers them,
the runtime falls to the floor for that PC. The foundry's selection cap is what
draws the line; the runtime does not need to compute it.

```text
{S1, S2}     -> multimorphic tile in bank, runtime uses it.
{S1, S2, S3} -> if foundry enumerated this union, runtime uses it; else floor.
{S1..S20}    -> almost certainly not in bank, runtime stays on floor.
```

Megamorphic regions execute correctly on the floor. They are slow, but they are
slow at the rate of the L0 baseline, not the interpreter's worst case.

---

## 8. Execution lifecycle

### 8.1 Region first encountered

```text
on first execution of region R:
  floor = compose_L0_image(R)        -- one L0 TileTemplate per PC, copied from the bank
  active = floor
  hyst = 0
  jump into floor
```

### 8.2 Region runs at the floor

```text
each opcode in R executes in its L0 tile.
cheap always-on counters increment.
when residual pressure crosses a threshold:
  install fact-recording L0 variants (a small prologue per L0 tile that writes
  observed operand types/shapes to a per-region ring buffer).
keep running.
```

### 8.3 Facts stabilize

```text
each observation:
  compute window-level signature from the ring buffer.
  if signature == last_signature:
      region.hyst += 1
  else:
      region.hyst = 0
  if region.hyst > threshold and region.active == region.floor:
      attempt_selection(R, signature)
      region.hyst = 0
```

### 8.4 Selection succeeds

```text
attempt_selection(R, sig):
  for each window in R:
      pattern  = window_pattern(R, window)
      tile_id  = bank.lookup(pattern, sig.project_to_window(window))
      if tile_id == null:
          tile_id = bank.lookup(pattern, GENERIC)   -- L0
      append(tile_seq, tile_id)
  if tile_seq has at least one non-L0 tile:
      img = materialize(tile_seq)
      atomic_store(&R.active, img)
      schedule old active (== floor) NOT for free — floor is never freed.
  else:
      no win available; stay at floor.
```

### 8.5 Active runs

```text
each opcode in R now executes inside the active image's tile sequence.
guards inside each tile fire on operand checks.
on guard success: stay in active.
on guard failure:
  project state via the tile's exit descriptor.
  jump to floor at the corresponding PC.
  execute the rest of this iteration in floor.
  next iteration re-enters active at the region head.
  log the failure as an observed fact delta.
```

### 8.6 Guard failures accumulate

```text
region.guard_fail_count += 1 on each exit.
if region.guard_fail_count > demotion_threshold:
  atomic_store(&R.active, R.floor)
  schedule old active for free.
  region.guard_fail_count = 0
  region.hyst = 0
  -- subsequent observations may stabilize on a different signature, in which
  -- case selection fires again and a different bank tile is selected.
```

### 8.7 Stable steady state

```text
no recompilation. no cache walks. no LRU. no eviction.
active executes; guards hold; iterations complete; counters quiesce.
if facts ever shift, hysteresis re-stabilizes and 8.4 re-fires.
if facts shift to a signature the bank does not cover, demotion takes the region
  back to the floor, where it stays correctly.
```

---

## 9. Image publication

Image publication is the only mutation of live JIT state. Everything about it is
designed to be trivially correct:

```text
- images are immutable once published.
- swap is a single atomic pointer store on region.active.
- old images are retained until no thread is executing in them.
- the floor is never freed.
- no thread is ever inside a partially-built image (the atomic store is the
  visibility point).
```

### 9.1 Lifetime

```text
image lifecycle:
  build      -- allocate, copy-patch, mprotect RX
  publish    -- atomic store into region.active
  in-use     -- threads execute in it
  superseded -- a newer image took its place
  draining   -- waiting for all threads to leave
  freed      -- munmap the page
```

Draining is handled by RCU-style epoch tracking or a quiescent-state scan; this is
boring kernel-level technique. The JIT proper does not care.

### 9.2 Dependency epochs

Each image lists the dependency epochs it speculates on. When any epoch advances
(e.g. a shape was mutated, a global was reassigned, a metatable installed):

```text
for each region whose active image depends on the advanced epoch:
  atomic_store(&region.active, region.floor)
  schedule old active for free
```

This is correctness, not optimization. An image speculating on a stale epoch is
unsafe; the runtime takes it down before any thread can re-enter. Demotion to the
floor is always safe; the floor's L0 tiles do not speculate.

---

## 10. The floor

The floor is the always-installed L0 image. It is the system's source of
truth-by-default.

### 10.1 What the floor contains

```text
one L0 tile per opcode in the region's PC range, concatenated.
each L0 tile is a generic stencil materialized from a bank template covering that opcode for
arbitrary operand types (the same kind of stencil Deegen would emit).
no fact-env specialization; no guards beyond what the opcode's semantics require.
no exits other than ordinary control flow + interpreter-equivalent error paths.
```

### 10.2 Properties

```text
- always executable
- always correct
- never freed
- composed once at region first encounter
- identical performance to a per-op stencil baseline JIT for that opcode set
```

### 10.3 Why the floor matters

```text
1. bank miss is safe        -- floor is already there.
2. demotion is safe         -- demote means active := floor.
3. dep invalidation is safe -- invalidation means active := floor.
4. cold start is safe       -- nothing higher than L0 needs to exist for execution.
5. megamorphic regions stay correct -- they just run at L0 speed.
```

A SponJIT region without a meaningful bank still runs. It runs at the L0 baseline.
The bank's value is what it adds on top.

---

## 11. Exits as local training signal and cross-run training signal

In an exit-authored *cache* design, a guard failure would trigger a new SSA job,
which would publish a new artifact into the cache, which the runtime would then
hit on subsequent iterations. In SponJIT, the runtime does not publish new code
artifacts; the foundry does, and the foundry runs offline.

Exits still carry information at two binding times:

```text
within a run:
  guard failure -> exit fact delta -> update tile-site leases/penalties
                -> choose next bank candidate for that span or split to smaller tiles.
  no new code artifact is ever synthesized for this signature within this run.

across runs:
  the program's exit log is exported as part of the runtime's profile output.
  the next foundry training run consumes the aggregated exit logs from many
  programs and extends the bank's coverage where exits clustered.
  next run of the program uses the updated bank.
```

This is a real loss of within-run adaptivity, paid for by the gain of runtime
simplicity. The bet is that this loss is small in practice:

```text
- short-lived scripts: little adaptation possible regardless.
- long-running programs: most facts stabilize early; once the bank covers them,
    runtime adaptation past that point yields diminishing returns.
- workloads that genuinely require within-run code synthesis: out of scope; that
    is LuaJIT's regime, past the no-codegen line (§13 in ARCHITECTURE).
```

The exit log is the runtime's only output to the offline world. It is append-only,
cheap, and not on the hot path (guards already pay an exit cost; logging adds a
counter increment).

---

## 12. Comparison with LuaJIT side traces

```text
LuaJIT:
  hot path -> trace
  exit -> side trace graft
  polymorphism becomes trace tree shape
  runtime pays optimizer/emitter cost
  invalidation: side traces have their own lifecycle, can be very expensive to manage

SponJIT:
  region -> floor + (eventually) selected active image
  exit -> demote to floor + log fact delta
  polymorphism becomes a multimorphic tile in the bank, selected as one tile
  runtime pays selection + copy/patch
  invalidation: atomic store of region.active = floor. drain. free.
```

A LuaJIT side exit says:

```text
this trace was wrong here. record a side trace if hot.
```

A SponJIT exit says:

```text
the bank's tile for signature S was wrong here. fall to the floor. if this
  happens enough, demote. eventually the offline training corpus will see this
  in the exit log and the next bank may cover the new signature.
```

LuaJIT's invariant is "all-native or bail." SponJIT's invariant is "either the bank
has a tile for what's happening or the floor handles it correctly." The floor is
always there; bailing means returning to L0 baseline speed, not interpreter speed.

---

## 13. Primary measurements

The load-bearing measurements are about bank coverage and signature stability.

```text
runtime measurements:
  per region:
    hits per signature before change (signature dwell)
    fraction of hits at active vs floor
    guard failure rate within active
    bank lookup miss rate
    exit-reason distribution (for the cross-run training signal)
    demotion frequency
    image build latency (selection + copy/patch + publish)
    image lifetime (publication to demotion or replacement)
```

```text
offline analysis measurements:
  bank coverage of corpus signatures
  bank size vs cycles saved
  multimorphic tile hit rate (do enumerated unions match observed unions?)
  signatures that occur often but are not covered (training gaps)
```

Critical questions:

```text
1. Do hot regions stabilize on signatures the bank already covers?
2. When they do not, do the new signatures cluster (so the next training run can
   cover them with one or a few additional tiles), or are they unbounded?
3. Is the L0 floor's performance a sufficient safety net for uncovered cases?
4. Does within-run demotion happen often enough to justify any extra mechanism, or
   is "stay at floor on miss" sufficient?
```

If hot facts stabilize and the bank's training corpus is representative, the design
converges to most regions running at active with high guard-success rates, and the
exit log adds incremental coverage in subsequent foundry runs. If facts are
chaotic, regions stay at floor and SponJIT becomes a fancy baseline JIT — still
correct, just not better than its L0 layer would suggest.

---

## 14. Minimal implementation plan

### Phase 1 — floor and bank loading

```text
- bank file format and reader
- mmap bank at VM startup
- per-region floor construction from L0 tiles
- execute regions at the floor
- always-on counters
- correctness: verify floor output matches interpreter on a corpus
```

### Phase 2 — observation

```text
- fact-recording L0 variants
- per-region ring buffer of observed facts
- pressure-triggered burst recording
- signature canonicalization at the window level
- hysteresis counter
```

### Phase 3 — selection

```text
- bank lookup by (pattern, signature)
- image materialization (copy-patch from selected tiles)
- atomic publication via region.active store
- guard exits and projection into the runtime exit handler
- tile-site memory: failed facts, success/fail counters, cooldowns
- local reselection by candidate ladder; whole-image rebuild with local replacement
```

### Phase 4 — multimorphism

```text
- multimorphic directory in bank
- internal-branch discriminator scheme
- multimorphic signature canonicalization at runtime
- foundry-side union enumeration policy
```

### Phase 5 — exit log

```text
- per-region exit log
- export at process exit (and periodically for long-lived processes)
- aggregator that turns exit logs into next-training-run input
- bank rebuild step that consumes the aggregator's output
```

### Phase 6 — invalidation

```text
- dependency epoch tracking
- atomic invalidation of all images depending on an advanced epoch
- floor fallback as the conservative invalidation response
- RCU-style free of superseded images
```

---

## 15. Summary

SponJIT is:

```text
a two-pointer adaptive selector over a precomputed bank of fused copy-and-patch
tile templates, with the foundry handling enumeration, optimization, multimorphism,
and selection caps offline.
```

The central loop:

```text
runtime observes facts in a hot region under hysteresis
  -> optimistic greedy selection chooses large/high-score bank candidates
    -> copy-patch, atomic swap region.active to the new image
      -> tile exits report fact deltas
        -> selector updates local leases/penalties and tries the next candidate
          -> if same-span replacement misses, split the span
            -> if arity reaches 1, L0 is guaranteed
              -> exit/miss logs feed the next foundry training run
```

State per region:

```text
floor   -- one pointer to a never-freed L0 image
active  -- one pointer to the currently-selected image (may equal floor)
hyst    -- selection-attempt timing
sites   -- small tile-site memory for exits, penalties, cooldowns
```

No code cache. No eviction. No LRU. No runtime SSA. No code synthesis. No register
allocator. No artifact lifecycle beyond "published, in-use, draining, freed."

The bank is everything. The runtime selects templates from it and materializes one
active image. The floor is the always-correct baseline. Hysteresis is the
selection-attempt timer. Exits are local ladder-training events and cross-run
foundry-training signals. Whole-region floor fallback remains the conservative
response to dependency invalidation or extreme instability, not the first response
to every tile exit.

The intelligence lives offline in the foundry, where it can be exhaustive,
measured, verified, and capped.
