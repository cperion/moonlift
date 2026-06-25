# Semantic optimization ASDL 
Find the semantic ASDL facts that make fast lowering emerge automatically for LalinCode/Kernel lowering, using benchmark gaps vs gcc -O3 as evidence rather than ad-hoc loop recognizers.
**Workflow ID**: wf-semantic-optimization-asdl
**Started**: 2026-06-15 18:55:51
---

## Scout Output — 2026-06-15 18:59:46

## Files Retrieved

1. `benchmarks/bench_c_vs_cranelift.lua` (lines 1-325) — Benchmark harness and exact `sum_loop`, `ptr_sum`, `view_sum`, `triad_store` source.
2. `lua/lalin/schema/code.asdl` (lines 1-218) — `LalinCode` schema: memory access, contracts, integer semantics, CFG/code IR.
3. `lua/lalin/schema/flow.asdl` (lines 1-56) — `LalinFlow` schema: edges, loops, counted domains, inductions/ranges.
4. `lua/lalin/schema/mem.asdl` (lines 1-68) — `LalinMem` schema: access facts, bases, indices, patterns, alias/dependence facts.
5. `lua/lalin/schema/kernel.asdl` (lines 1-109) — `LalinKernel` schema: streams, safety, reductions, schedules, planned/no-plan kernels.
6. `lua/lalin/schema/lower.asdl` (lines 1-16) — `LalinLower` schema: function lowering choice, kernel vs code.
7. `lua/lalin/schema/back.asdl` (lines 1-288) — `LalinBack` schema: backend commands, memory info, vector ops, target facts, alias facts.
8. `lua/lalin/code_flow_facts.lua` (lines 1-337) — Flow fact builder.
9. `lua/lalin/code_mem_facts.lua` (lines 1-276) — Memory fact builder.
10. `lua/lalin/code_kernel_plan.lua` (lines 1-526) — Kernel planner and rejection logic.
11. `lua/lalin/code_lower_plan.lua` (lines 1-42) — Chooses `LowerFuncKernel` only for whole-function kernel plans.
12. `lua/lalin/lower_to_back.lua` (lines 1-560) — Kernel and fallback lowering to `LalinBack`.
13. `lua/lalin/lower_to_c.lua` (lines 1-24) — C lowering explicitly ignores kernel plans today.
14. `lua/lalin/code_to_back.lua` (lines 1-496) — Conservative generic Code→Back lowering.
15. `lua/lalin/code_to_c.lua` (lines 1-584) — Generic Code→C lowering.
16. `lua/lalin/c_emit.lua` (lines 1-463) — C emitter; emits gotos/block params.
17. `lua/lalin/c_helpers.lua` (lines 1-448) — C helpers are `static inline`; integer ops use unsigned wrap.
18. `lua/lalin/tree_to_code.lua` (lines 300-344, 470-550, 630-710, 850-910, 1415-1510) — Code memory accesses, view/index lowering, contract lowering.
19. `lua/lalin/tree_contract_facts.lua` (lines 1-73) — Converts source `requires` / param modifiers to tree contract facts.
20. `lua/lalin/frontend_pipeline.lua` (lines 1-348) — Both Cranelift and C paths build Flow/Mem/Kernel/Lower facts before lowering.
21. `tests/test_code_kernel_plan.lua` (lines 1-132) — Existing expectations for contracted loops vs unsafe loops.
22. `tests/test_code_lower_plan.lua` (lines 1-180) — Existing expectations for vector kernel lowering when contracts are present.
23. `src/lib.rs` (lines 1-260) — Cranelift setup; `opt_level=speed`.
24. `src/decode.rs` (lines 50-55, 360-712) — Wire decoding into Cranelift IR, memory flags, vector ops.
25. `lua/lalin/back_command_binary.lua` (lines 1-520) — BackProgram binary encoder, memory flags, vector load/store emission.

## Key Code

### Benchmark kernels have no useful contracts

`benchmarks/bench_c_vs_cranelift.lua`:

```lua
{
    name = "ptr_sum",
    src = [[func bench_ptr_sum(p: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + p[i])
    end
end]],
}
```

```lua
{
    name = "triad_store",
    src = [[func bench_triad_store(out: ptr(i32), a: ptr(i32), b: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        out[i] = a[i] + b[i] * k
        jump loop(i = i + 1)
    end
end]],
}
```

No `requires bounds(...)`, `requires disjoint(...)`, `noalias`, `readonly`, or `writeonly` in the actual benchmark cases.

### Tree→Code marks all normal memory as may-trap

`lua/lalin/tree_to_code.lua` lines 318-319:

```lua
local function memory_access(ctx, mode, source_ty, code_type)
    return Code.CodeMemoryAccess(mode, code_type or code_ty(ctx, source_ty), align_of(ctx, source_ty), Code.CodeMayTrap, false, nil)
end
```

Loads/stores use that directly:

```lua
append_inst(ctx, Code.CodeInstLoad(dst, place, memory_access(ctx, Code.CodeMemoryRead, source_ty, code_ty(ctx, source_ty))), ...)
append_inst(ctx, Code.CodeInstStore(place, value, memory_access(ctx, Code.CodeMemoryWrite, source_ty, code_ty(ctx, source_ty))), ...)
```

### Mem facts are conservative

`lua/lalin/code_mem_facts.lua`:

```lua
elseif cls == Code.CodePlaceDeref then
    local base, index, pattern = normalize_addr(place.addr, place.ty, ptr_offsets, view_data, inductions, value_ops)
    return base, index, pattern, Mem.MemBoundsUnknown("deref bounds require Mem/contract proof")
```

Alias/dependence are always unknown:

```lua
out[#out + 1] = Mem.MemAliasUnknown(accesses[i].id, accesses[j].id, "code_mem_facts foundation is conservative")
```

```lua
out[#out + 1] = Mem.MemDependenceUnknown(accesses[i].id, accesses[j].id, "dependence analysis deferred")
```

### Kernel planner rejects unknown bounds/traps/alias/dependence

`lua/lalin/code_kernel_plan.lua`:

```lua
if pvm.classof(access.bounds) == Mem.MemBoundsUnknown then
    if bounds_contract ~= nil then
        ...
    else
        rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "memory bounds are unknown")
    end
end
if access.trap == Mem.MemMayTrap and bounds_contract == nil then
    rejects[#rejects + 1] = Kernel.KernelRejectTrap(access.id, "may-trap access lacks bounds/nontrap proof")
end
```

```lua
else
    rejects[#rejects + 1] = Kernel.KernelRejectAlias(fact, "no noalias/disjoint proof for kernel streams")
end
```

```lua
else
    rejects[#rejects + 1] = Kernel.KernelRejectDependence(fact, "dependence is unknown")
end
```

### Kernel schedule vectorizes only contiguous streams

```lua
local vector_ok = #streams > 0
for _, stream in ipairs(streams) do
    if stream.pattern ~= Mem.MemAccessContiguous then vector_ok = false end
end
if vector_ok then return Kernel.KernelScheduleVector(Kernel.KernelLaneVector(elem_ty, 4), 1, 1, Kernel.KernelTailScalar, proofs), rejected end
```

A pure scalar reduction like `sum_loop` has `#streams == 0`, so it receives `KernelScheduleScalarIndex`.

### Lowering ignores many facts conservatively

Generic Code→Back:

```lua
local function int_semantics(k)
    return Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose)
end
```

```lua
return Back.BackMemoryInfo(
    Back.BackAccessId("code:" .. tag),
    Back.BackAlignKnown(access.align or 1),
    Back.BackDerefBytes(bytes, "CodeMemoryAccess"),
    Back.BackMayTrap,
    Back.BackMayNotMove,
    access_mode(access.mode)
)
```

Kernel→Back also emits conservative memory:

```lua
Back.BackMemoryInfo(..., Back.BackAlignUnknown, Back.BackDerefBytes(...), Back.BackMayTrap, Back.BackMayNotMove, ...)
```

### C path computes facts but ignores kernel lowering

`lua/lalin/lower_to_c.lua`:

```lua
-- C lowering is intentionally a pure CodeToC projection for now.
-- LalinLower/LalinKernel are accepted so the frontend can use the same
-- pipeline shape as Back, but this path must not install partial
-- point optimizations.
return CodeToC.module(code_module, opts)
```

### Rust/Cranelift consumes only simple MemFlags

`src/decode.rs`:

```rust
fn mf(bits: u32) -> MemFlags {
    let mut f = MemFlags::new();
    if bits & 1 != 0 { f.set_notrap(); }
    if bits & 2 != 0 { f.set_aligned(); }
    if bits & 4 != 0 { f.set_can_move(); }
    f
}
```

`BackAliasFact` is not lowered to Cranelift; binary encoder skips it:

```lua
elseif k == "CmdTargetModel" or k == "CmdAliasFact" then
    -- skip, no-op in Rust decoder
```

## Relationships

Pipeline for both benchmark backends:

```text
source
→ parse/typecheck/layout
→ tree_to_code
→ code_flow_facts
→ code_mem_facts
→ code_kernel_plan
→ code_lower_plan
→ Cranelift: lower_to_back
→ C: lower_to_c → CodeToC only
```

Important split:

- Cranelift path uses `LowerToBack`.
  - If `LowerFuncKernel`, it emits kernel-specific Back commands.
  - Else it falls back to generic `CodeToBack`.
- C path computes the same kernel facts but intentionally ignores them and emits generic C.

Actual benchmark fact outcomes from inspection:

### `sum_loop`

- Contracts: `0`
- Flow: counted loop, 2 inductions (`i`, `acc`)
- Mem accesses: `0`
- Kernel: `KernelPlanned`, whole-function, `KernelEffectFold`, `KernelResultFold`
- Schedule: `KernelScheduleScalarIndex`
- Lowering: `LowerFuncKernel`
- Back command counts include scalar only: `CmdCompare=1`, `CmdIntBinary=2`

### `ptr_sum`

- Contracts: `0`
- Flow: counted loop, 2 inductions
- Mem: 1 load, contiguous induction index, but:
  - `MemBoundsUnknown`
  - `MemMayTrap`
- Kernel: `KernelNoPlan`
  - rejects: `"memory bounds are unknown"`, `"may-trap access lacks bounds/nontrap proof"`
- Lowering: `LowerFuncCode`
- Back: scalar load loop, no vector kernel

### `view_sum`

- Contracts: `0`
- Flow: counted loop
- Mem: 3 accesses observed; final data load is contiguous but:
  - derived view base
  - `MemBoundsUnknown`
  - `MemMayTrap`
  - alias unknowns from local/view accesses
- Kernel: `KernelNoPlan`
  - rejects trap/bounds and alias
- Lowering: `LowerFuncCode`

### `triad_store`

- Contracts: `0`
- Flow: counted loop, 1 induction
- Mem: 2 loads + 1 store, all contiguous induction indexed, but:
  - all `MemBoundsUnknown`
  - all `MemMayTrap`
  - all pairwise aliases unknown
  - write-related dependences unknown
- Kernel: `KernelNoPlan`
  - rejects bounds, trap, alias, dependence
- Lowering: `LowerFuncCode`

## Observations

- Current ASDL can represent many desired facts: bounds, disjoint/noalias, readonly/writeonly, alignment, nontrap, no-dependence, vector schedules, alias facts, target features, no-wrap integer semantics.
- Current builders often do not derive or propagate those facts:
  - `code_mem_facts` emits alias/dependence unknown by default.
  - `tree_to_code` emits `CodeMayTrap` for ordinary loads/stores.
  - `code_kernel_plan.contract_index` uses bounds/disjoint/noalias but ignores readonly/writeonly/same_len/window_bounds.
  - `CodeContractReadonly` / `Writeonly` exist but do not appear to affect `MemAccessFact`, kernel planning, or Back memory info.
  - `BackAliasFact` exists but is skipped by binary encoder / Rust decoder.
  - `BackIntSemantics` has no-wrap variants, but lowering emits `BackIntWrap/BackIntMayLose`.
- `sum_loop` is recognized as a returned reduction, but lowering emits a scalar loop, not a closed-form arithmetic result.
- `ptr_sum`, `view_sum`, and `triad_store` have enough Flow/Mem shape to see contiguous induction-indexed memory, but no safety facts, so kernel planning rejects them.
- C+gcc-O3 receives generic C with gotos/helpers, not kernel C. GCC still optimizes it better than Cranelift for these cases.
- Quick benchmark run showed median Cranelift vs shared-O3 gaps:
  - `sum_loop`: Cranelift ~0.449 ns/item, C-O3 ~0.065 ns/item
  - `ptr_sum`: Cranelift ~0.231 ns/item, C-O3 ~0.071 ns/item
  - `view_sum`: Cranelift ~0.236 ns/item, C-O3 ~0.076 ns/item
  - `triad_store`: Cranelift ~0.449 ns/item, C-O3 ~0.300 ns/item

## Knowledge-builder Output — 2026-06-15 19:02:35

### What Matters Most for This Problem

- **Semantic safety invariants**: bounds, non-trapping memory, aliasing, dependence, and integer range/no-wrap facts must be sound before vector/closed-form lowering.
- **Fact placement and propagation**: facts should not be planner-local if generic lowering, C lowering, Back lowering, and future passes need them.
- **Contract vs automatic inference boundary**: bare `ptr + n` cannot automatically imply validity/disjointness unless the language semantics say so.
- **Benchmark attribution**: distinguish gaps caused by missing Lalin semantics from gaps caused by Cranelift lacking GCC-style loop/vector optimizations.
- **Preserving observable behavior**: trap behavior, overflow behavior, and alias-dependent store/load ordering are the constraints that make “fast lowering” nontrivial.

---

### Non-Obvious Observations

#### 1. The ASDL already has many of the right nouns, but the proof ownership is misplaced

`CodeContractFact`, `MemAccessFact`, `KernelSafety`, and `BackMemoryInfo` all model overlapping ideas: bounds, traps, aliasing, movement, and alignment.

The hidden problem is not absence of vocabulary; it is that **proofs are consumed too late and too locally**.

Example: `code_kernel_plan.lua` can turn `CodeContractBounds` into `KernelAssumeBounds`, but that proof does not update `MemAccessFact.bounds`, `MemTrap`, or `BackMemoryInfo`. So the same access may be:

- “assumed safe” inside `KernelSafety`,
- still `MemBoundsUnknown` in memory facts,
- still emitted as `BackMayTrap`,
- still `BackMayNotMove`.

That means semantic facts do not become reusable compiler facts. They become planner-local excuses.

#### 2. Bounds contracts are currently too weakly connected to loop ranges

`CodeContractBounds(base, len)` says a base has a length, but the planner treats its mere presence as enough to bless stream accesses.

What is missing is the composed fact:

```text
for every executed iteration i in loop domain:
    access index expression is within [0, len)
    byte range [addr, addr + access_size) is inside object
```

That requires combining:

- `FlowCountedDomain(start, stop, step, exclusive)`
- induction range semantics
- access element size
- access offset
- signedness/index type
- contract/view length
- loop guard polarity

Right now, the planner’s “bounds contract exists” shortcut skips most of that composition. That is dangerous because a contract on `p` with length `len` does not prove `p[i]` safe unless the loop’s `i` range is related to `len`.

#### 3. `view_sum` exposes a semantic loss that `ptr_sum` does not

For `ptr_sum(p, n)`, the compiler genuinely cannot infer that `p` is valid for `n` elements from a bare pointer unless Lalin defines that as a function precondition.

For `view_sum`, however, the source constructs:

```lalin
let v: view(i32) = view(p, n)
...
v[i]
```

This should carry stronger semantic structure than raw pointer indexing:

```text
view.data = p
view.len = n
view.stride = 1
loop i ranges over [0, n)
```

The current memory facts lose this by representing view provenance as `MemBaseDerived(..., "view data")` / string reasons and by producing extra local/view descriptor accesses. This suggests that view bounds/provenance facts are present in the source shape but not preserved structurally through ASDL.

The non-obvious distinction:

- `ptr_sum` lacks source-level validity semantics.
- `view_sum` has source-level descriptor semantics, but they are not represented strongly enough.

#### 4. Alias rejection is stricter than vector safety requires

`code_mem_facts.lua` emits `MemAliasUnknown` for every pair of accesses. `code_kernel_plan.lua` rejects unknown alias facts for all stream pairs.

That conflates **aliasing** with **unsafe dependence**.

Read/read aliasing is harmless for vectorization. In `triad_store`, `a[i]` and `b[i]` may alias without changing semantics. The important questions are:

- can a write affect a later read?
- can two writes conflict?
- is there loop-carried dependence?
- if same base/same index, is scalar order preserved?

Current alias rejection requires stronger facts than needed. This especially matters for kernels with many loads: they can be rejected for lack of noalias even when no write-related dependence exists.

#### 5. Dependence facts need loop-relative meaning, not just pairwise access IDs

`MemDependenceFact` has `MemNoDependence` and `MemLoopCarriedDependence`, but current generation emits only unknowns for write-related pairs.

For vectorization, the key semantic fact is not merely “these two accesses may alias.” It is more specific:

```text
across loop iterations, store at iteration i cannot affect load/store at iteration j
for any reordered/vectorized execution grouping
```

This depends on:

- common base/provenance,
- induction expression,
- element size,
- constant offset,
- stride,
- iteration order,
- dependence distance.

`MemIndexInduction` captures some shape, but there is no derived “same index safe”, “disjoint index ranges”, or “loop-carried distance” fact being produced. Existing `MemSameBaseSameIndexSafe` hints at this, but it is unused/underived and lives under alias rather than as a first-class dependence/scheduling fact.

#### 6. Pointer provenance is too stringly to support automatic semantic lowering

`MemBaseDerived(base, reason)` and `BackProvDerived(reason)` encode important provenance through strings like `"view data"` or `"field offset"`.

That is a hidden blocker because automatic lowering needs machine-readable distinctions:

- field projection,
- byte offset,
- view data projection,
- window/slice projection,
- derived pointer preserving object bounds,
- derived pointer that may leave object.

As strings, these cannot reliably drive bounds, alias, or provenance reasoning. This conflicts with Lalin’s own ASDL philosophy: semantic state should not hide in strings.

#### 7. Trap semantics are modeled three times but not consistently propagated

There are three layers:

- `CodeTrapMode`: source/IR-level access may trap or must not trap.
- `MemTrap`: analyzed memory fact.
- `BackTrap`: backend lowering flag.

Normal memory starts as `CodeMayTrap`, so `MemMayTrap`, and generic lowering emits `BackMayTrap`.

Even kernel lowering emits `BackMayTrap`, despite planning having safety proofs/assumptions. So the backend never receives `notrap` even when the kernel planner believes the stream is safe.

That creates a semantic contradiction:

```text
Kernel plan says: safe enough to vectorize.
Back emission says: access may trap and may not move.
```

This likely limits backend motion and makes facts unavailable outside explicit kernel lowering.

#### 8. `BackMotion` and alias facts are dead weight today for optimization

`BackMemoryInfo` can express:

```text
BackNonTrapping
BackCanMove
BackAlignKnown
BackDerefBytes
```

But generic and kernel lowering mostly emit:

```text
BackMayTrap
BackMayNotMove
BackAlignUnknown
```

Also, `BackAliasFact` exists but is skipped by the binary encoder / Rust decoder. Therefore, even if higher-level facts existed, most would not influence Cranelift unless they are used before Back emission to create explicit vector/closed-form code.

This means some benchmark gaps cannot be closed by “just add ASDL facts” unless those facts are consumed before or during lowering.

#### 9. Flow ranges are not precise enough for bounds or integer optimization

`FlowCountedDomain` records start/stop/step and exclusivity, but lacks several facts needed for safe transformations:

- signed vs unsigned comparison semantics,
- non-negativity of trip count,
- normalized trip count,
- step direction,
- no-wrap of induction update,
- exact max iteration value,
- whether exit comparison is `i >= n`, `i < n`, etc.

`FlowRangeDerived(init, stop, "counted loop induction")` is not enough to prove `0 <= i < n`, especially when `n` may be signed and negative.

This matters for both:

- proving memory bounds,
- replacing reductions with formulas.

#### 10. Integer semantics are a major hidden reason `sum_loop` is hard

`sum_loop` looks simple, but the fast GCC result is likely from recognizing the arithmetic series:

```text
sum_{i=0}^{n-1} i = n * (n - 1) / 2
```

Lalin currently recognizes it only as a scalar reduction. To safely lower to closed form, the compiler needs facts about:

- loop trip count,
- induction exact range,
- accumulator overflow behavior,
- multiplication/division exactness or modular arithmetic validity,
- signedness of `n`,
- behavior for `n <= 0`.

Because Lalin integer ops use explicit wrap semantics, this is not the same as C signed-overflow UB. The semantic fact needed is not just “reduction over induction”; it is “this reduction has a closed-form value under Lalin’s integer semantics.”

So the `sum_loop` gap is mostly a missing high-level algebra/range fact plus Cranelift not doing this idiom itself.

#### 11. `ptr_sum` is primarily missing safety semantics, not access-shape recognition

The scout showed `ptr_sum` already has:

```text
counted loop
contiguous induction-indexed load
```

The blocker is:

```text
MemBoundsUnknown
MemMayTrap
```

This is not an ad-hoc loop recognition problem. The shape is recognized. What is missing is a valid semantic basis for saying `p[0:n]` is dereferenceable and nontrapping.

Without an explicit contract, view semantics, or language-level pointer extent rule, automatic inference would be unsound.

#### 12. `triad_store` combines two different missing semantics

`triad_store` is blocked by both:

1. **safety/bounds facts** for `out`, `a`, and `b`;
2. **alias/dependence facts** involving `out`.

The loads `a` and `b` do not need to be mutually noalias. The write stream `out` needs stronger reasoning relative to reads/writes.

GCC may optimize this with runtime alias checks or conservative vectorization strategies. LalinKernel currently has no notion of guarded/versioned facts such as:

```text
if runtime disjointness check succeeds, vector path is safe;
else scalar path preserves semantics.
```

So part of the `triad_store` gap is missing semantics/facts, and part is lack of GCC-style runtime versioning/vectorization machinery.

#### 13. C/gcc-O3 is not using LalinKernel facts, so it is an imperfect semantic oracle

The C path computes Flow/Mem/Kernel/Lower facts but ignores them. GCC optimizes generic emitted C.

Therefore benchmark gaps mean:

```text
GCC can recover or assume enough semantics from C + UB/model + optimizer heuristics.
Cranelift path cannot, unless Lalin makes those semantics explicit.
```

But not every GCC win maps to a missing ASDL fact. Some map to backend optimizer capabilities:

- scalar evolution,
- loop idiom recognition,
- runtime alias checks,
- autovectorization,
- horizontal reductions,
- unrolling/interleaving,
- target-specific vector width selection.

The ASDL direction should separate “semantic facts Lalin must know” from “backend optimizations Cranelift will not invent.”

#### 14. Kernel scheduling currently ignores target facts

`KernelScheduleVector` hardcodes 4 lanes. `BackTargetFact` can represent SSE2/AVX2/AVX512, vector op support, preferred unroll, masked tails, etc., but these facts do not appear to drive scheduling.

So even when semantic facts become sufficient, schedule quality may lag GCC because GCC picks vector widths, unrolls, and tails using target information. This is a backend/scheduler limitation, not a safety-semantics limitation.

#### 15. “Automatic fast lowering” and “explicit contracts” are not opposites

The real distinction should be:

- automatic derivation from source semantics where the source carries enough meaning, e.g. views, locals, globals, structured regions;
- explicit contracts where bare pointers do not carry enough meaning, e.g. `ptr + n` bounds, noalias/disjointness;
- conservative fallback where neither exists.

The current benchmarks use bare pointers without contracts, so expecting automatic noalias/bounds inference would require changing the language contract of `ptr(T)` or relying on unsound assumptions.

---

### Benchmark Gap Attribution

- **`sum_loop`**
  - Missing semantics: closed-form reduction/algebraic range facts.
  - Backend limitation: Cranelift does not synthesize GCC-style arithmetic-series replacement.
  - Not primarily memory/bounds related.

- **`ptr_sum`**
  - Missing semantics: pointer extent / bounds / nontrap facts.
  - Existing shape recognition is already sufficient.
  - Backend limitation: Cranelift will not autovectorize scalar loop anyway, but LalinKernel is blocked before scheduling.

- **`view_sum`**
  - Missing semantics: structural view provenance, view length/stride, loop-domain-to-view-bounds relation.
  - Current ASDL has pieces, but view meaning is degraded into derived/string provenance and ordinary memory accesses.

- **`triad_store`**
  - Missing semantics: bounds/nontrap for all streams; write-related alias/dependence facts.
  - Overly strict current alias rejection also rejects harmless read/read aliasing.
  - Backend limitation: no runtime alias versioning or target-aware vector scheduling like GCC.

---

### Knowledge Gaps

- Exact Lalin language semantics for `ptr(T)` validity and `view(T)` construction: does a view assert dereferenceability or only carry a descriptor?
- Whether traps are observable enough to forbid any reordering, or whether failed contracts make behavior undefined.
- What GCC actually emits for `sum_loop` under current C helper lowering: formula, vector loop, or something else.

## Approach-proposer Output — 2026-06-15 19:03:33

### Approach A: Proof-Carrying Fact Normalization

- **Core idea**: Keep the current pipeline shape, but add a canonical semantic fact layer that composes contracts, flow ranges, view provenance, memory facts, and algebraic facts before planning/lowering.

- **Key changes**:
  - Add/extend ASDL facts in `flow.asdl`, `mem.asdl`, possibly new `sem.asdl`.
  - Add a semantic normalization phase between `code_mem_facts` and `code_kernel_plan`.
  - Convert contracts into reusable facts, not planner-local assumptions.
  - Lowering consumes resolved facts for `notrap`, `can_move`, alignment, no-dependence, vector streams, and closed-form reductions.

- **Tradeoff**: Optimizes for incremental integration with existing LalinFlow/LalinMem/LalinKernel architecture; sacrifices some simplicity because facts must be carefully composed across layers.

- **Risk**: If the proof layer becomes too permissive, it may bless unsafe memory/vector transformations; if too conservative, benchmark gaps remain.

- **Rough sketch**:
  - Introduce normalized facts such as:
    - `FlowTripCountExact`
    - `FlowInductionRange`
    - `FlowInductionNoWrap`
    - `MemAccessInBounds`
    - `MemAccessNonTrap`
    - `MemAccessMovable`
    - `MemNoLoopCarriedDependence`
    - `MemDependenceDistance`
    - `AlgebraClosedFormReduction`
  - Convert source contracts:
    - `requires bounds(p, n)` becomes an object extent fact.
    - `requires disjoint(out, a, n)` becomes a no-overlap/no-dependence fact.
    - `readonly`/`writeonly` become access-effect facts.
  - Automatically derive facts from structured sources:
    - locals/globals have known object extents.
    - `view(p, n)` gives `data`, `len`, `stride`, and access bounds if loop domain proves `0 <= i < n`.
  - Update `code_kernel_plan.lua` to require normalized semantic facts instead of inspecting raw contracts.
  - Update `lower_to_back.lua` and `code_to_back.lua` to emit:
    - `BackNonTrapping`
    - `BackCanMove`
    - `BackAlignKnown`
    - vector kernels when streams are contiguous and safe.
  - Add an algebra pass for `sum_loop`:
    - recognize induction fold `acc += i`
    - require exact trip count and integer semantics proof
    - emit closed-form arithmetic under Lalin wrap semantics.

- **Benchmark handling**:
  - `sum_loop`: uses `AlgebraClosedFormReduction`.
  - `ptr_sum`: needs explicit `bounds(p, n)` or language-level pointer extent; otherwise remains scalar.
  - `view_sum`: automatically derives bounds/nontrap from view length and loop range.
  - `triad_store`: needs bounds for all streams; no-dependence comes from disjoint contracts or derived same-index/distance reasoning.

---

### Approach B: First-Class Semantic Memory Objects

- **Core idea**: Move safety and provenance out of analysis heuristics and into explicit semantic memory objects/types, so fast lowering emerges from source-level ownership, view, and region meaning.

- **Key changes**:
  - Strengthen ASDL around memory provenance and extents.
  - Replace stringly `MemBaseDerived(..., "view data")` with structured provenance.
  - Treat views/slices/bounded pointers as semantic memory capabilities.
  - Kernel planning works over memory objects and access intervals rather than raw pointer expressions.

- **Tradeoff**: Optimizes for soundness and long-term semantic clarity; sacrifices backward compatibility and requires more frontend/type-system work.

- **Risk**: Existing pointer-heavy code may not optimize unless rewritten to use views, bounded pointers, or explicit contracts.

- **Rough sketch**:
  - Add structured provenance ASDL:
    - `MemObjectParam`
    - `MemObjectView`
    - `MemObjectSlice`
    - `MemObjectField`
    - `MemObjectLocal`
    - `MemObjectUnknownPtr`
  - Add extent/capability facts:
    - `MemExtentKnown(base, len, elem_ty)`
    - `MemStrideKnown(base, stride)`
    - `MemReadonlyObject`
    - `MemWriteonlyObject`
    - `MemUniqueObject`
    - `MemSharedObject`
  - Lower source constructs directly into semantic objects:
    - `view(p, n)` creates a bounded strided memory object.
    - `p: ptr(T)` remains an unbounded raw pointer unless annotated.
    - `noalias`, `readonly`, `writeonly`, `bounds` become object capabilities.
  - Define access facts as projections from objects:
    - `v[i]` over `view(i32)` becomes access to object `v.data` with interval `[i, i+1)`.
    - Bounds proof comes from `i` range + `v.len`.
    - Trap proof comes from object validity + interval containment.
  - Kernel planner consumes object/access interval facts:
    - read/read alias is allowed.
    - write/read or write/write requires no loop-carried dependence.
    - same-base same-index may be legal if scalar order is preserved.
  - Lowering emits optimized code only when objects carry enough facts:
    - vector load/store streams for contiguous views.
    - `BackNonTrapping`/`BackCanMove` from object capabilities.
    - scalar fallback for raw unknown pointers.

- **Benchmark handling**:
  - `sum_loop`: independent algebraic reduction fact still needed.
  - `ptr_sum`: raw pointer version does not auto-vectorize unless pointer semantics are changed or a bounded pointer contract is added.
  - `view_sum`: becomes the canonical fast case because view semantics carry extent/stride/provenance.
  - `triad_store`: best expressed as views:
    - `out: view(i32) writeonly`
    - `a: view(i32) readonly`
    - `b: view(i32) readonly`
    - optional uniqueness/disjointness determines whether stores can be vectorized without guards.

---

### Approach C: Guarded Semantic Specialization

- **Core idea**: Represent facts as either unconditional or runtime-guarded, allowing the compiler to generate fast vector/closed-form paths guarded by bounds/disjointness checks with scalar fallback.

- **Key changes**:
  - Extend ASDL with conditional facts and guard plans.
  - Add versioned lowering: fast path under proven runtime predicates, fallback path preserving original semantics.
  - Kernel planner may produce `KernelPlanGuarded` instead of rejecting unknown bounds/alias.
  - Lowering emits checks before vector kernels.

- **Tradeoff**: Optimizes for benchmark performance on bare pointers without requiring source contracts; sacrifices implementation simplicity and increases generated code size.

- **Risk**: Runtime guards must exactly match the semantic assumptions of the fast path; incorrect guard generation can miscompile aliasing or trapping cases.

- **Rough sketch**:
  - Add ASDL concepts:
    - `SemFactUnconditional(fact)`
    - `SemFactGuarded(guard_id, fact)`
    - `GuardBounds(base, len, access_range)`
    - `GuardDisjoint(base_a, range_a, base_b, range_b)`
    - `GuardAligned(base, align)`
    - `LowerFuncVersioned(guards, fast_lowering, fallback_lowering)`
  - Preserve current conservative facts as fallback truth.
  - When facts are unknown, planner asks whether a guard can establish them:
    - `p[i]` over loop `0 <= i < n` can be guarded by checking pointer range validity if the runtime model supports such checks.
    - `out/a/b` can be guarded by runtime disjointness checks.
  - Contracts suppress guards:
    - explicit `bounds`/`disjoint` become unconditional facts.
    - view-derived facts are unconditional if view construction semantically validates extent.
  - Lowering emits:
    - guard block
    - vector/optimized kernel block
    - scalar generic fallback block
  - Add closed-form reduction as an unconditional algebraic specialization for memory-free reductions.

- **Benchmark handling**:
  - `sum_loop`: emits closed-form reduction when range/integer facts prove it.
  - `ptr_sum`: can fast-lower with a bounds/nontrap guard if Lalin has a way to validate pointer extent at runtime; otherwise still needs contract.
  - `view_sum`: view extent gives unconditional bounds; no guard needed unless alias/movement facts are conditional.
  - `triad_store`: emits vector fast path under disjointness guards such as:
    - `out[0:n]` disjoint from `a[0:n]`
    - `out[0:n]` disjoint from `b[0:n]`
    - fallback scalar loop if checks fail.

---

### Comparison

- Pick **Approach A** if the goal is to make the current ASDL pipeline coherent with the least architectural disruption: facts become reusable compiler currency, and lowering consumes them consistently.
- Pick **Approach B** if the goal is to make Lalin’s semantic model explicit and durable: views, bounded memory, provenance, and access effects become first-class, with raw pointers remaining conservative.
- Pick **Approach C** if the goal is to close GCC-style benchmark gaps for bare-pointer code: runtime guards let the compiler create fast paths even when static contracts are absent.

## Critique Output — 2026-06-15 19:04:20

### Approach A: Proof-Carrying Fact Normalization

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Introduces a cross-cutting semantic fact layer used by flow, mem, kernel, and lowering. Coupling is real, but acceptable if ASDL facts remain explicit compiler currency rather than side tables. |
| **Cohesion** | 4/5 | Strong cohesion: contracts, flow ranges, memory safety, dependence, and algebra are normalized before consumers use them. This directly fixes today’s planner-local proof leakage. |
| **Migration cost** | 3/5 | Moderate. It preserves the current pipeline shape, but requires meaningful changes across `flow.asdl`, `mem.asdl`, `code_kernel_plan.lua`, `lower_to_back.lua`, and generic lowering. |
| **Philosophy fit** | 5/5 | Best match for “proper ASDL semantics, fast lowering falls out.” It makes semantic facts explicit, interned, reusable, and visible to lowering. |
| **Risk** | 3/5 | Main risk is unsound proof composition, especially bounds + signed loop ranges + trap behavior. But the risk is localizable and can be tested incrementally. |
| **Testability** | 5/5 | Highly testable: each normalized fact can have targeted tests, and existing rejection tests can be migrated from raw contract checks to semantic fact checks. |

**Verdict**: Strong yes  
**Key concern**: The proof layer must be stricter than the current planner shortcuts; especially, bounds contracts must be composed with exact loop-domain/range facts, not treated as blanket permission.

---

### Approach B: First-Class Semantic Memory Objects

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 2/5 | Long-term coupling is low because memory meaning becomes owned by explicit objects/capabilities instead of inferred ad hoc across passes. Short-term, it touches many layers. |
| **Cohesion** | 5/5 | Very cohesive. Provenance, extent, stride, readonly/writeonly, uniqueness, and access intervals all belong together semantically. This directly addresses the current stringly provenance problem. |
| **Migration cost** | 5/5 | Highest migration cost. Requires frontend/type-system changes, ASDL changes, memory fact rewrites, and likely source-level idiom changes for pointer-heavy code. |
| **Philosophy fit** | 5/5 | Excellent fit with Lalin’s rule that ASDL is the architecture and semantics must not hide in strings. This is the most semantically durable approach. |
| **Risk** | 4/5 | Risk is scope and adoption: raw pointer benchmarks may not improve unless code uses views/contracts. It may be architecturally right but slower to produce visible wins. |
| **Testability** | 4/5 | Testable around views, slices, locals, and object capabilities, but broad migration makes incremental validation more expensive than Approach A. |

**Verdict**: Yes with caveats  
**Key concern**: Avoid making this a large type-system rewrite before the compiler has a reusable normalized fact path. Otherwise it may be correct but too disruptive.

---

### Approach C: Guarded Semantic Specialization

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 5/5 | Strongly couples semantic facts, runtime guards, kernel planning, lowering, CFG generation, and fallback preservation. Versioned lowering would affect the whole backend path. |
| **Cohesion** | 3/5 | Conditional facts are a coherent idea, but guard generation, semantic validation, and optimized lowering become entangled. It risks mixing proof representation with performance strategy. |
| **Migration cost** | 5/5 | Deep refactor. Requires guarded facts, `LowerFuncVersioned`-style lowering, guard CFG emission, fallback preservation, and precise runtime range/disjointness semantics. |
| **Philosophy fit** | 3/5 | Partially fits if guards are represented as ASDL facts, but it is the most benchmark-driven option. It can feel like chasing GCC behavior rather than making Lalin semantics explicit first. |
| **Risk** | 5/5 | Highest soundness risk. Runtime guards must exactly imply nontrap, bounds, alias, and dependence facts. Bare pointer bounds guards may not even be meaningful without runtime extent metadata. |
| **Testability** | 3/5 | Individual guards can be tested, but validating equivalence between fast path and fallback across alias/trap cases is hard. Many bugs would be miscompilations, not simple rejects. |

**Verdict**: Significant concerns  
**Key concern**: Guard predicates must be semantically real in Lalin’s runtime model. Without actual pointer extent/provenance validation, guarded bounds for raw pointers are not sound.

---

### Summary

- **Recommended**: **Approach A**, with the semantic-memory clarity of **Approach B** as the natural direction for view/provenance facts. A best matches the existing pipeline while turning contracts, flow, mem, kernel, and lowering facts into reusable ASDL semantics.

- **Dark horse**: **Approach B**. It has the highest architectural upside and best long-term soundness story, especially for `view_sum`, but its migration cost is much higher and it may not immediately close raw-pointer benchmark gaps.

- **Avoid**: **Approach C** as the first move. It is powerful, but too likely to become benchmark-driven specialization before the unconditional semantic model is sound. Runtime guards should only come after the facts they guard are precise and trustworthy.

## Documenter Output — 2026-06-15 19:05:53

# Architecture Decision: Semantic Optimization ASDL

Workflow: `wf-semantic-optimization-asdl`

## Goal

Enable Lalin’s compiler to derive, normalize, and reuse sound semantic facts—flow ranges, memory object/provenance facts, bounds/nontrap facts, dependence facts, and algebraic reduction facts—so LalinCode → LalinKernel/LalinBack lowering can emit fast scalar, vector, and closed-form code when the program semantics prove it safe, while preserving conservative fallback behavior for raw pointers and unknown facts.

## Incentives

The current benchmark gaps against `gcc -O3` are not primarily caused by missing loop-shape recognition. The compiler already recognizes counted loops and contiguous induction-indexed memory in cases like `ptr_sum`, `view_sum`, and `triad_store`. The blockers are missing or non-reusable semantic facts: memory bounds remain unknown, accesses remain may-trap, alias/dependence facts remain unknown, and view provenance is degraded into string reasons. Existing ASDL schemas contain many useful nouns, but facts are consumed too locally—especially inside `code_kernel_plan.lua`—and are not propagated to generic lowering, `BackMemoryInfo`, or Cranelift. This causes the compiler to reject vector kernels or emit conservative scalar code even when source semantics, contracts, or views should establish stronger guarantees.

Concrete pain points from the scout and analysis:

- `tree_to_code.lua` marks ordinary loads/stores as `CodeMayTrap`.
- `code_mem_facts.lua` emits `MemBoundsUnknown`, `MemAliasUnknown`, and `MemDependenceUnknown` by default.
- `code_kernel_plan.lua` can use contracts as planner-local assumptions, but those assumptions do not update reusable memory facts.
- `lower_to_back.lua` and `code_to_back.lua` emit conservative `BackMayTrap`, `BackMayNotMove`, and weak alignment/motion facts.
- `BackAliasFact` exists but is skipped by the binary encoder / Rust decoder.
- `view_sum` loses semantic view structure and becomes ordinary derived pointer reasoning.
- `sum_loop` is recognized as a scalar reduction but lacks closed-form algebra/range facts.

## Current State

The relevant pipeline is:

```text
source
→ parse/typecheck/layout
→ tree_to_code
→ code_flow_facts
→ code_mem_facts
→ code_kernel_plan
→ code_lower_plan
→ Cranelift: lower_to_back
→ C: lower_to_c
```

Both Cranelift and C paths compute Flow/Mem/Kernel/Lower facts. The Cranelift path consumes `LalinLower` through `lower_to_back.lua`; the C path currently ignores kernel plans and emits generic C through `CodeToC`.

Relevant files and roles:

| File | Role |
|---|---|
| `lua/lalin/schema/code.asdl` | LalinCode IR, memory access metadata, contracts, integer semantics |
| `lua/lalin/schema/flow.asdl` | LalinFlow facts: edges, counted loops, inductions, ranges |
| `lua/lalin/schema/mem.asdl` | LalinMem facts: accesses, bases, indices, bounds, alias/dependence |
| `lua/lalin/schema/kernel.asdl` | LalinKernel plans, streams, safety, schedules |
| `lua/lalin/schema/lower.asdl` | Function lowering decision: kernel vs code |
| `lua/lalin/schema/back.asdl` | LalinBack commands, memory info, vector ops, target facts |
| `lua/lalin/tree_to_code.lua` | Lowers typed tree to LalinCode |
| `lua/lalin/code_flow_facts.lua` | Derives flow/counting/induction facts |
| `lua/lalin/code_mem_facts.lua` | Derives memory access facts |
| `lua/lalin/code_kernel_plan.lua` | Plans/rejects kernels |
| `lua/lalin/code_lower_plan.lua` | Chooses whole-function kernel lowering or fallback |
| `lua/lalin/lower_to_back.lua` | Emits Back from kernel or generic code |
| `lua/lalin/code_to_back.lua` | Generic conservative Code → Back lowering |
| `lua/lalin/lower_to_c.lua` | C lowering; intentionally ignores kernel plans |
| `src/decode.rs` | Rust Cranelift decoder; consumes simple memory flags |

Today, `tree_to_code.lua` creates normal memory accesses as potentially trapping:

```lua
Code.CodeMemoryAccess(
  mode,
  ty,
  align,
  Code.CodeMayTrap,
  false,
  nil
)
```

`code_mem_facts.lua` recognizes access shape but remains conservative about safety. For pointer dereferences it emits unknown bounds:

```lua
Mem.MemBoundsUnknown("deref bounds require Mem/contract proof")
```

It also emits unknown alias and dependence facts for access pairs:

```lua
Mem.MemAliasUnknown(...)
Mem.MemDependenceUnknown(...)
```

`code_kernel_plan.lua` rejects memory streams when bounds, trap, alias, or dependence facts are unknown. It can treat some raw contracts as enough to proceed, but that proof is local to planning. The same access may still appear as `MemBoundsUnknown`, `MemMayTrap`, and later `BackMayTrap`.

Generic lowering in `code_to_back.lua` emits conservative integer and memory metadata:

```lua
Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose)
Back.BackMayTrap
Back.BackMayNotMove
```

Kernel lowering in `lower_to_back.lua` is also conservative for backend memory metadata. Even a planned-safe kernel may emit `BackMayTrap`, which contradicts the safety assumptions used to authorize vectorization.

Benchmark attribution in the current state:

- `sum_loop`
  - Recognized as a whole-function scalar reduction kernel.
  - Lowered as scalar loop, not closed form.
  - Missing exact trip-count/range and algebraic closed-form facts under Lalin integer semantics.

- `ptr_sum`
  - Counted loop and contiguous induction-indexed load are recognized.
  - Rejected because bare `ptr(i32)` provides no bounds/nontrap proof.
  - Correctly remains conservative without a contract or language-level pointer extent rule.

- `view_sum`
  - Source view carries stronger meaning than raw pointer indexing.
  - Current facts lose this structure into derived/string provenance and ordinary accesses.
  - Should become an automatic fast case once view object, extent, stride, and loop-domain facts are represented structurally.

- `triad_store`
  - Counted loop and contiguous load/store streams are recognized.
  - Rejected due to unknown bounds/nontrap plus unknown write-related alias/dependence.
  - Read/read aliasing is currently over-rejected even though it is harmless for vectorization.

## Chosen Target

The chosen direction is **Approach A as the implementation spine**, with **Approach B’s first-class structured memory/provenance semantics folded in where needed for views, memory objects, and provenance**. **Approach C guarded specialization is deferred.**

### Approach

The compiler will keep the existing broad pipeline shape:

```text
LalinCode
→ LalinFlow facts
→ LalinMem facts
→ normalized semantic facts
→ LalinKernel planning
→ LalinLower decision
→ LalinBack lowering
```

The central change is that contracts, flow ranges, memory access shape, view provenance, alias/dependence reasoning, and algebraic reductions become reusable normalized ASDL facts before planning and lowering consume them.

The kernel planner should no longer treat raw contracts as planner-local permission. Instead, contracts and source constructs are composed into normalized facts such as:

- exact loop domain / induction range facts,
- object extent and access interval facts,
- in-bounds/nontrap access facts,
- movable/no-loop-carried-dependence facts,
- structured view/provenance facts,
- closed-form reduction facts.

Lowering then consumes those same facts to emit:

- `BackNonTrapping` where proved,
- `BackCanMove` where motion is legal,
- known alignment/dereferenceability,
- vector kernels for safe contiguous streams,
- closed-form scalar code for proven algebraic reductions.

Raw pointers remain conservative unless explicit contracts or language semantics provide bounds/nontrap/disjointness facts. Views and structured memory objects are the main automatic inference path.

### Semantic Fact Tower

The intended semantic tower is:

```text
Source syntax / typed tree
  ↓
LalinCode + CodeContractFact + CodeMemoryAccess
  ↓
LalinFlow: loop domains, inductions, ranges, trip counts
  ↓
LalinMem: access shape, base/provenance, index pattern, raw bounds/trap/alias facts
  ↓
Normalized semantic facts:
    - flow proofs
    - memory object/provenance proofs
    - bounds/nontrap/motion proofs
    - dependence proofs
    - algebraic reduction proofs
  ↓
LalinKernel / LalinLower:
    - safe stream plans
    - scalar/vector schedule selection
    - closed-form lowering eligibility
  ↓
LalinBack:
    - explicit optimized commands
    - accurate BackMemoryInfo
    - backend-visible flags where supported
```

The normalized layer is the compiler currency. A fact established for kernel planning must also be available to generic lowering and Back emission.

### Required ASDL Concepts

The exact spelling belongs to implementation, but the architecture requires ASDL-level concepts in these categories.

#### Flow facts

Needed to compose loop domains with access ranges and algebraic reductions:

```text
FlowTripCountExact
FlowInductionRange
FlowInductionNoWrap
FlowNormalizedCountedDomain
```

These facts must capture enough information to prove properties like:

```text
for all executed iterations:
  0 <= i < n
```

They must account for signedness, comparison polarity, step direction, exclusivity, and non-negative trip count.

#### Memory object and provenance facts

Approach B is folded into the memory layer here. Stringly provenance such as `MemBaseDerived(..., "view data")` is not sufficient.

Required concepts include structured memory objects/projections such as:

```text
MemObjectParam
MemObjectView
MemObjectSlice
MemObjectField
MemObjectLocal
MemObjectUnknownPtr

MemProvenanceViewData
MemProvenanceField
MemProvenanceOffset
MemProvenanceSlice
```

Views should produce structured facts:

```text
view(p, n)
  → object with data = p
  → extent = n elements
  → stride = 1 unless otherwise represented
  → provenance = view data projection
```

Accesses such as `v[i]` should become interval facts over the view object, not merely derived pointer dereferences with string reasons.

#### Bounds, trap, and motion facts

Required normalized memory facts include:

```text
MemAccessInBounds
MemAccessNonTrap
MemAccessMovable
MemAccessDerefBytes
MemAccessAlignKnown
```

A bounds contract is not by itself enough. The compiler must compose:

```text
object extent
+ access element size
+ access index expression
+ loop induction range
= access interval contained in object
```

Only then may it produce nontrap/in-bounds facts.

#### Alias and dependence facts

The architecture distinguishes aliasing from unsafe dependence.

Required concepts include:

```text
MemNoLoopCarriedDependence
MemDependenceDistance
MemSameBaseSameIndexSafe
MemReadReadAliasAllowed
```

Read/read aliasing must not reject a vectorizable kernel. Write/read and write/write pairs require dependence reasoning relative to loop iteration order, access interval, base/provenance, and index pattern.

#### Algebraic facts

For memory-free reductions like `sum_loop`, the compiler needs a semantic algebra layer:

```text
AlgebraClosedFormReduction
AlgebraReductionUnderWrapSemantics
```

This must be tied to exact trip-count/range facts and Lalin integer semantics. It is not enough to detect `acc += i`; the closed form must be valid under the language’s wrapping behavior and behavior for `n <= 0`.

### Contracts vs Automatic Inference

The decision preserves a strict boundary:

- **Automatic inference is valid when source semantics carry enough meaning.**
  - Locals/globals may have known extents.
  - Views carry extent/stride/provenance.
  - Loop domains may prove index ranges.
  - Read/read aliasing can be accepted when no write dependence exists.

- **Explicit contracts are required when bare pointers do not carry enough meaning.**
  - `ptr(i32)` alone does not imply `p[0:n]` is valid.
  - Bare pointer parameters do not imply disjointness.
  - `ptr_sum(p, n)` remains scalar unless a `bounds(p, n)`-style contract or language-level pointer extent rule exists.

- **Planner shortcuts are not acceptable.**
  - `requires bounds(p, n)` must be converted into object extent/access interval facts.
  - `requires disjoint(...)`, `noalias`, `readonly`, and `writeonly` must become reusable alias/effect/dependence facts.
  - Kernel planning consumes normalized facts, not raw contract presence.

### Lowering Consumption

Lowering must consume normalized facts consistently.

#### Kernel planning

`code_kernel_plan.lua` should require normalized facts for:

- access in-bounds,
- access nontrap,
- legal movement/reordering,
- no loop-carried dependence for write-related streams,
- safe stream pattern,
- reduction legality.

It should stop treating contracts as local exemptions.

#### Back lowering

`lower_to_back.lua` and `code_to_back.lua` should use normalized facts when building `BackMemoryInfo`:

```text
MemAccessNonTrap  → BackNonTrapping
MemAccessMovable  → BackCanMove
MemAccessAlignKnown → BackAlignKnown
MemAccessDerefBytes → BackDerefBytes
```

Kernel lowering must not emit conservative `BackMayTrap` for accesses whose safety was required to create the kernel.

#### C lowering

`lower_to_c.lua` currently ignores kernel plans. This decision does not require C lowering to become the optimization path. GCC benchmark results remain useful evidence, but the Lalin optimization path is semantic fact normalization feeding LalinKernel/LalinBack.

#### Cranelift backend

`src/decode.rs` currently consumes only simple memory flags:

```rust
notrap
aligned
can_move
```

The initial value comes from using semantic facts before/during Back emission to create explicit optimized code and accurate memory flags. Rich alias facts may remain unavailable to Cranelift until the wire format/decoder supports them.

### Benchmark Meaning Under the Chosen Design

| Benchmark | Expected semantic treatment |
|---|---|
| `sum_loop` | Use exact trip count, induction range, and algebraic reduction facts to emit closed-form code when valid under Lalin integer semantics. |
| `ptr_sum` | Shape is already recognized. Fast lowering requires explicit bounds/nontrap contract or future pointer extent semantics. Bare pointer remains conservative. |
| `view_sum` | Should become an automatic fast case through structured view object/provenance, extent, stride, and loop-domain-to-bounds composition. |
| `triad_store` | Requires bounds/nontrap for all streams and write-related no-dependence facts. Read/read aliasing must not block planning. Disjoint/noalias contracts or structured object facts provide stronger write safety. |

### Tradeoffs Acknowledged

This decision preserves the existing pipeline rather than replacing it with a full memory-object type-system rewrite. That reduces migration cost and lets existing LalinFlow/LalinMem/LalinKernel work evolve incrementally.

It also folds in structured memory/provenance semantics only where they are required for correctness and useful automatic inference, especially views. This avoids leaving important semantics hidden in strings while not forcing every raw pointer path to become a new object-capability system immediately.

The tradeoff is that the normalized fact layer becomes cross-cutting. Flow, memory, contracts, kernel planning, and lowering all depend on it. That coupling is accepted because the facts are explicit ASDL compiler currency rather than hidden side tables or planner-local assumptions.

### Risks Acknowledged

The main correctness risk is unsound proof composition. Bounds facts must be stricter than the current planner shortcut: a bounds contract plus a pointer does not prove every access safe unless the loop range and access interval are proven contained in the object extent.

Specific risks:

- signed loop bounds and negative `n` values can invalidate naive `0 <= i < n` assumptions;
- induction updates may wrap unless no-wrap/range facts prove otherwise;
- trap behavior must remain observable unless nontrap facts are established;
- vectorization must distinguish harmless aliasing from unsafe loop-carried dependence;
- closed-form reductions must respect Lalin integer semantics, not C signed-overflow assumptions;
- backend flags must not claim `notrap` or `can_move` unless the normalized facts prove them.

Guarded specialization is intentionally deferred because runtime guards would require exact semantic correspondence between guard predicates and the facts they imply. Without first having precise unconditional facts, guarded vector paths would carry high miscompilation risk.

## Initial Implementation Slices

1. **Introduce normalized semantic fact layer**
   - Add or extend ASDL schemas for flow, memory, provenance, and algebraic facts.
   - Add a phase between `code_mem_facts.lua` and `code_kernel_plan.lua`.
   - Convert existing contracts into reusable normalized facts.

2. **Strengthen flow range facts**
   - Derive exact trip counts and induction ranges for counted loops.
   - Track signedness, exclusivity, step, and no-wrap where provable.

3. **Represent structured view provenance**
   - Replace stringly view-derived memory reasoning with first-class view/object facts.
   - Preserve `view(p, n)` as extent/stride/provenance information.
   - Prove `v[i]` in-bounds when loop range implies `0 <= i < v.len`.

4. **Normalize memory safety**
   - Derive `MemAccessInBounds`, `MemAccessNonTrap`, alignment, dereference byte, and motion facts.
   - Require composed object extent + loop range + access interval proofs.

5. **Normalize dependence**
   - Stop rejecting read/read aliasing.
   - Derive no-loop-carried-dependence facts for same-index or disjoint access patterns where sound.
   - Keep write-related unknowns conservative.

6. **Update kernel planning**
   - Make `code_kernel_plan.lua` consume normalized facts instead of raw contract shortcuts.
   - Preserve explicit rejection reasons when facts are absent.

7. **Update Back lowering**
   - Use normalized facts in `lower_to_back.lua` and `code_to_back.lua`.
   - Emit `BackNonTrapping`, `BackCanMove`, known alignment, and dereferenceability only when proved.

8. **Add algebraic closed-form reduction path**
   - Start with `sum_loop`-style induction fold.
   - Require exact trip count, valid induction range, and integer semantics proof.
   - Emit explicit closed-form Back code rather than relying on Cranelift to discover it.

9. **Test by fact visibility and benchmark attribution**
   - Add targeted tests for each normalized fact.
   - Migrate kernel rejection tests to assert absence/presence of semantic facts.
   - Use benchmarks to confirm attribution: raw pointers without contracts remain conservative; views and contracted pointers gain fast paths when facts prove safety.

## Worker Output — 2026-06-15 19:27:44

## Completed
Implemented T002: normalized semantic loop fact derivation for counted loops.

## Files Changed
- `lua/lalin/code_flow_facts.lua` - added `semantic_facts` / `semantics`, deriving normalized counted-loop facts, conservative trip counts, induction ranges, and no-wrap only from existing no-overflow semantics.
- `tests/test_code_flow_facts.lua` - added focused coverage for `0 <= i < n` loop facts, no invented no-wrap, and conservative inclusive-stop handling.

## Notes
Verified with:
- `luajit tests/test_code_flow_facts.lua`
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`

Marked edit-plan task T002 done with evidence.

## Worker Output — 2026-06-15 19:47:14

## Completed
Implemented and marked done:
- T003 structured memory object/provenance facts
- T004 normalized memory safety from flow + bounded objects
- T005 kernel planning consumption of normalized facts
- T006 Back memory metadata from semantic facts
- T007 bounded-object semantic integration tests

Stopped at T008 due a real semantic/spec blocker.

## Files Changed
- `lua/lalin/code_mem_facts.lua`
  - Added `semantic_facts` / `semantics`.
  - Emits generic `MemObjectFact`s for params, contracts, locals, globals, data, views, projections.
  - Builds access intervals and safety facts from bounded objects + flow ranges.
  - Keeps raw pointer params conservative.
  - Partially normalizes contract bounds/disjoint/noalias.
- `lua/lalin/code_kernel_plan.lua`
  - Accepts optional normalized memory semantics.
  - Requires normalized in-bounds/nontrap proofs when supplied.
  - Relaxes read/read aliasing.
  - Uses semantic no-dependence for write-related streams.
- `lua/lalin/lower_to_back.lua`
  - Accepts `opts.mem_semantics`.
  - Emits `BackNonTrapping`, `BackCanMove`, known alignment/deref info when normalized facts prove them.
  - Resolves view descriptor data through local descriptor aliases for kernel lowering.
- `tests/test_code_mem_facts.lua`
  - Added object, safety, raw-pointer, view, strided-view, contract, kernel, and Back metadata coverage.
- `tests/test_code_kernel_plan.lua`
  - Added semantic memory planning coverage.
- `tests/test_code_lower_plan.lua`
  - Added Back metadata tests for semantic kernel memory facts.

## Notes
T008 was blocked after partial implementation. Bounds/disjoint/noalias are normalized, but `readonly`/`writeonly` need architecture clarification: current `MemSemanticFactSet` has no first-class effect fact, and deriving no-dependence from those contracts alone may be unsound without clarified alias/UB semantics.

Validation run:
- `luajit tests/test_code_mem_facts.lua`
- `luajit tests/test_code_flow_facts.lua`
- `luajit tests/test_code_kernel_plan.lua`
- `luajit tests/test_code_lower_plan.lua`
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_schema_compile_pipeline.lua`

## Worker Output — 2026-06-15 20:18:07

## Completed
Implemented all remaining ready edit-plan tasks T013–T020 for `wf-semantic-optimization-asdl`.

Highlights:
- Semantic facts now travel through ASDL-owned `KernelModulePlan`.
- Removed planner-local contract shortcuts; kernel planning consumes normalized semantic facts.
- Closed-form reductions are first-class kernel semantics.
- Memory projection provenance is typed, not stringly.
- Added relation facts for `same_len` / `window_bounds`.
- Added stride-aware interval safety for known positive strides.
- Kernel vector scheduling now uses `BackTargetModel` facts instead of hardcoded 4 lanes.
- Expanded benchmark cases with semantic attribution notes.

## Files Changed
- `lua/lalin/schema/kernel.asdl` - ASDL-carried semantics, closed-form result/proof types.
- `lua/lalin/schema/mem.asdl` - typed projection kinds, relation facts, semantic fact-set relations.
- `lua/lalin/code_kernel_plan.lua` - normalized-fact-only planning, closed-form result creation, target-aware scheduling.
- `lua/lalin/code_mem_facts.lua` - contract relations, typed projections, stride-aware safety.
- `lua/lalin/lower_to_back.lua` - reads semantics from `LowerModule.kernels`, lowers closed-form results.
- `lua/lalin/frontend_pipeline.lua` - public path carries semantics through kernel plan; passes target model.
- `lua/lalin/kernel_validate.lua` - validates ASDL-carried semantic nontrap proofs.
- `benchmarks/bench_c_vs_cranelift.lua` - added semantic benchmark variants and attribution notes.
- Tests updated:
  - `tests/test_schema_core.lua`
  - `tests/test_code_mem_facts.lua`
  - `tests/test_code_kernel_plan.lua`
  - `tests/test_code_lower_plan.lua`
  - `tests/test_kernel_validate.lua`

## Notes
Validation run:
- `luajit tests/test_schema_core.lua`
- `luajit tests/test_code_mem_facts.lua`
- `luajit tests/test_code_kernel_plan.lua`
- `luajit tests/test_code_lower_plan.lua`
- `luajit tests/test_kernel_validate.lua`
- `luajit tests/test_schema_compile_pipeline.lua`
- `luajit tests/test_parse_kernels.lua`

Benchmark smoke run completed with reduced quick settings; all checksums matched after using `as(index, 2)` for strided view stride.

Edit plan status: `20/20 done`, no ready/todo tasks remaining.
