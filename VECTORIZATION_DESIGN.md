# Moonlift ASDL-First Vectorization Design

This document designs Moonlift vectorization as **fact gathering and explicit IR
construction**, not as a hidden optimization pass.

For the coherent ASDL-first redesign, see:

- `moonlift/VECTORIZATION_ASDL_REDESIGN.md`

The purpose is to make the best machine-facing IR available from the semantic
program by representing every meaningful code-shape, legality, dependence, range,
and target choice as ASDL values.

```text
Sem
  -> Vec facts
  -> Vec candidates
  -> Vec plan
  -> Vec IR / vector skeleton
  -> Back facts
  -> Artifact
```

The backend must not rediscover source semantics from scalar loops. If a vector
choice matters, it must exist before backend replay as an ASDL value.

---

## 1. Non-goals

This is not a traditional opaque optimizer pass.

Avoid these designs:

- hidden Rust-side peepholes over scalar `BackCmd`s
- backend pattern matching like “this looks like a reduction loop”
- mutable side tables for alias/dependence/range information
- string tags for vector legality or rejection
- a single ad hoc “vectorize(loop)” helper that internally decides everything
- lowering directly from scalar `SemLoop` to clever vector `BackCmd`s without an
  explicit plan/skeleton value

The correct design is phase-separated:

1. recursively gather explicit facts
2. build explicit candidate plans
3. select/build an explicit vector skeleton
4. lower that skeleton to explicit `Back` facts

---

## 2. Design principle

Vectorization should be treated as a compiler-language feature over the semantic
IR:

```text
source ASDL semantics
  -> semantic loop/value/memory facts
  -> target-aware vector facts
  -> explicit vector program shape
```

A vectorized loop is not “the scalar loop, optimized.” It is a different explicit
program shape with its own:

- vector domain
- lane mapping
- induction mapping
- memory access mapping
- carried state mapping
- reductions
- masks/tails
- widening/narrowing proofs
- target lane width
- target operation support
- rejection diagnostics

Therefore Moonlift should represent it as ASDL.

---

## 3. Layer split

### Existing layers

```text
MoonliftSurface -> MoonliftElab -> MoonliftSem -> MoonliftBack
```

### Vectorization layers

Add/organize the vector path as:

```text
MoonliftSem
  -> MoonliftVecFacts
  -> MoonliftVecPlan
  -> MoonliftVecIR
  -> MoonliftBack
```

Current code already has the beginning of this in `MoonliftVec`:

- expression facts
- counted-loop facts
- add-reduction plans
- explicit rejections
- initial plan-to-Back lowering

The next design step is to split the current monolithic `MoonliftVec` vocabulary
into clearer sub-vocabularies while still keeping it in ASDL:

```text
MoonliftVecFact    -- what is true about the Sem program
MoonliftVecLegal   -- what vector transformations are legal
MoonliftVecTarget  -- what the target can do
MoonliftVecPlan    -- chosen vectorization strategy
MoonliftVecIR      -- explicit vector skeleton/program
```

They may live in one ASDL module initially, but the conceptual separation should
be maintained.

---

## 4. Phase pipeline

### 4.1 `Sem -> VecFacts`

Question answered:

> What structure is present in the semantic program?

Facts should be gathered recursively through PVM phases.

Core fact families:

- loop/domain facts
- induction facts
- expression/value facts
- invariant facts
- reduction facts
- memory access facts
- dependence facts
- range/bounds facts
- type/narrowing facts
- control-flow shape facts

Example facts:

```text
VecCountedLoop(loop_id, index, start, stop, step, body)
VecInduction(index, start, step)
VecExprLaneIndex(binding, ty)
VecExprInvariant(expr, ty)
VecReductionAdd(carry, value)
VecAccessLoad(base, index, elem_ty, stride, alignment, bounds)
VecAccessStore(base, index, elem_ty, stride, alignment, bounds)
VecNoLoopCarriedMemoryDependence(accesses, proof)
VecRangeUnsigned(expr, min, max)
VecRangeBitAnd(expr, mask, max_value)
```

Important: facts are descriptive. They do not say “vectorize this.”

### 4.2 `VecFacts -> VecLegal`

Question answered:

> Which vector transformations are legal, and why?

Legality should be explicit and diagnostic-rich.

Examples:

```text
VecLegalIndependentLanes(loop_id, proof)
VecLegalReduction(loop_id, reduction, reassociation_policy)
VecLegalContiguousLoad(access, elem_ty, alignment)
VecLegalStridedLoad(access, elem_ty, stride)
VecLegalMaskedTail(loop_id)
VecLegalScalarTail(loop_id)
VecLegalNarrowAccumulator(reduction, narrow_ty, chunk_elems, proof)
```

Rejects should also be explicit:

```text
VecRejectDependence(access_a, access_b, reason)
VecRejectNonAffineIndex(expr, reason)
VecRejectUnsupportedControlFlow(loop_id, reason)
VecRejectNarrowOverflow(reduction, attempted_ty, reason)
```

### 4.3 `Target -> VecTargetFacts`

Question answered:

> What vector shapes can this backend/target actually lower well?

This must be explicit ASDL, not hardcoded backend lore.

Examples:

```text
VecTargetCaps(
  vector_bits,
  supported_lanes,
  supported_ops,
  preferred_unrolls,
  supports_masks,
  supports_gathers,
  supports_horizontal_reduce
)
```

For current Cranelift/JIT reality, this likely starts as:

```text
VecTargetFixed128
VecLaneSet(i64: {2}, i32: {4}, f64: {2}, f32: {4})
VecPreferredUnrolls({1,2,4})
VecNoNativeMasking
VecScalarTailPreferred
```

This explains why `i32x4` plans can beat `i64x2`, and why Terra/LLVM still wins
with wider AVX-512 plans on the same host.

### 4.4 `VecFacts + VecLegal + VecTargetFacts -> VecCandidates`

Question answered:

> What vector programs could we build?

Do not immediately choose one plan. Build candidate ASDL values.

Examples:

```text
VecCandidateScalar(loop_id)
VecCandidateVectorMainScalarTail(loop_id, elem_ty, lanes, unroll)
VecCandidateUnrolledReduction(loop_id, elem_ty, lanes, unroll)
VecCandidateChunkedNarrowReduction(loop_id, narrow_ty, lanes, unroll, chunk_elems)
VecCandidatePredicatedTail(loop_id, elem_ty, lanes, unroll)
VecCandidateInterleavedMemory(loop_id, group)
```

Candidates carry all proofs they require.

### 4.5 `VecCandidates -> VecPlan`

Question answered:

> Which candidate do we choose, according to explicit policy?

This is where “best IR possible” belongs, but still as ASDL facts.

The selection policy should be explicit:

```text
VecPlanPolicy = VecPreferThroughput
              | VecPreferSmallCode
              | VecPreferLowLatency
              | VecPreferCompileSpeed
              | VecDebugEnumerateAll
```

Plan selection should return both the winner and ranked alternatives:

```text
VecPlanChoice(winner, alternatives, rationale)
VecPlanScore(candidate, score_facts)
```

Score facts should not be magic floats only. They should be inspectable:

```text
VecScoreFacts(
  vector_elems_per_iter,
  scalar_ops_removed,
  vector_ops_added,
  loop_overhead_factor,
  tail_strategy,
  expected_register_pressure,
  target_preference
)
```

This gives diagnostics like:

```text
chose i32x4_u4 chunked reduction because:
- bounded term proves i32 lane accumulation safe for 1048576 elements
- target supports i32x4 but not efficient i64x4
- unroll 4 reduces branch overhead without exceeding register budget
```

### 4.6 `VecPlan -> VecIR`

Question answered:

> What exact vector program shape should be lowered?

`VecIR` should be a machine-independent vector skeleton, one step above `Back`.

This is the layer we are currently missing. Today `vector_to_back.lua` lowers
plans directly to `BackProgram`. That was good for validation, but proper
autovectorization should introduce explicit vector IR so plan construction is not
entangled with Cranelift block details.

Example skeleton values:

```text
VecFunction(func_id, params, result, blocks)
VecLoopSkeleton(loop_id, domain, lanes, unroll, accumulators, body, tail)
VecVectorValue(id, elem_ty, lanes)
VecScalarValue(id, ty)
VecRamp(dst, base, offsets)
VecSplat(dst, scalar)
VecBin(dst, op, lhs, rhs)
VecExtractLane(dst, vec, lane)
VecHorizontalReduce(dst, op, vecs)
VecScalarTail(loop_id, start, stop, body)
VecChunkedOuterLoop(chunk_elems, inner)
```

`VecIR` should still not be target machine code. It should describe the vector
program we intend to build.

### 4.7 `VecIR -> Back`

Question answered:

> How do explicit vector skeleton commands become executable backend facts?

This lowering should be mostly mechanical:

- blocks become `BackBlockId`s
- vector values become `BackVec` values
- vector ops become `BackCmdVec*`
- tails become scalar `BackCmd*`
- reductions become extract/add or future horizontal-reduce commands

If Cranelift needs a workaround, represent the workaround as a `VecIR` lowering
strategy or `Back` command, not as a hidden Rust decision.

---

## 5. Core ASDL vocabulary draft

This is intentionally a draft, not final syntax.

```asdl
module MoonliftVec {
  VecElem = VecElemI8 | VecElemI16 | VecElemI32 | VecElemI64
          | VecElemU8 | VecElemU16 | VecElemU32 | VecElemU64
          | VecElemF32 | VecElemF64
          | VecElemIndex

  VecShape = VecShape(VecElem elem, number lanes) unique
  VecUnroll = VecUnroll(number factor) unique

  VecTargetFact = VecTargetFixedBits(number bits) unique
                | VecTargetSupportsShape(VecShape shape) unique
                | VecTargetSupportsOp(VecShape shape, VecBinOp op) unique
                | VecTargetPreferredUnroll(VecShape shape, number unroll) unique
                | VecTargetNoNativeMasks
                | VecTargetScalarTailPreferred

  VecRangeFact = VecRangeUnknown(MoonliftSem.SemExpr expr) unique
               | VecRangeUnsigned(MoonliftSem.SemExpr expr, string min, string max) unique
               | VecRangeBitAnd(MoonliftSem.SemExpr expr, string mask, string max) unique

  VecAccessKind = VecLoad | VecStore
  VecAccessPattern = VecAccessContiguous
                   | VecAccessStrided(number stride)
                   | VecAccessGather
                   | VecAccessScatter

  VecAccessFact = VecAccessFact(
      string access_id,
      VecAccessKind kind,
      MoonliftSem.SemExpr base,
      MoonliftSem.SemExpr index,
      MoonliftSem.SemType elem_ty,
      VecAccessPattern pattern,
      number alignment
  ) unique

  VecDependenceFact = VecNoDependence(VecAccessFact a, VecAccessFact b, VecProof proof) unique
                    | VecDependenceUnknown(VecAccessFact a, VecAccessFact b, VecReject reject) unique
                    | VecLoopCarriedDependence(VecAccessFact a, VecAccessFact b, VecReject reject) unique

  VecProof = VecProofRange(string reason) unique
           | VecProofAlias(string reason) unique
           | VecProofDomain(string reason) unique
           | VecProofBoundedNarrow(string reason) unique

  VecLegalFact = VecLegalIndependentLanes(string loop_id, VecProof proof) unique
               | VecLegalReduction(string loop_id, VecReduction reduction, VecProof proof) unique
               | VecLegalNarrowReduction(string loop_id, VecReduction reduction, VecElem narrow_elem, number chunk_elems, VecProof proof) unique
               | VecLegalScalarTail(string loop_id) unique
               | VecLegalMaskedTail(string loop_id) unique

  VecCandidate = VecCandidateMainScalarTail(string loop_id, VecShape shape, number unroll) unique
               | VecCandidateUnrolledReduction(string loop_id, VecShape shape, number unroll) unique
               | VecCandidateChunkedNarrowReduction(string loop_id, VecShape shape, number unroll, number chunk_elems) unique
               | VecCandidateNoVector(VecReject reject) unique

  VecPlanPolicy = VecPreferThroughput | VecPreferSmallCode | VecDebugEnumerateAll

  VecPlanScore = VecPlanScore(VecCandidate candidate, number elems_per_iter, number loop_overhead, number register_pressure, string rationale) unique

  VecPlanChoice = VecPlanChoice(VecCandidate winner, VecPlanScore* alternatives, string rationale) unique
}
```

---

## 6. VecIR draft

`VecIR` should be explicit enough that the `VecIR -> Back` phase does not need to
ask semantic questions.

```asdl
module MoonliftVecIR {
  VecIRScalar = VecIRScalar(string id, MoonliftBack.BackScalar ty) unique
  VecIRVector = VecIRVector(string id, MoonliftBack.BackScalar elem, number lanes) unique

  VecIRValue = VecIRScalarValue(VecIRScalar value) unique
             | VecIRVectorValue(VecIRVector value) unique

  VecIRDomain = VecIRCountedDomain(VecIRScalar start, VecIRScalar stop, VecIRScalar step) unique
              | VecIRChunkedDomain(VecIRScalar start, VecIRScalar stop, VecIRScalar chunk_elems, VecIRScalar step) unique

  VecIRTail = VecIRScalarTail(VecIRDomain domain, VecIRCmd* body) unique
            | VecIRMaskedTail(VecIRDomain domain, VecIRCmd* body) unique
            | VecIRNoTail

  VecIRCmd = VecIRSplat(VecIRVector dst, VecIRScalar value) unique
           | VecIRRamp(VecIRVector dst, VecIRScalar base, string* lane_offsets) unique
           | VecIRBin(VecIRVector dst, MoonliftVec.VecBinOp op, VecIRVector lhs, VecIRVector rhs) unique
           | VecIRExtractLane(VecIRScalar dst, VecIRVector value, number lane) unique
           | VecIRHorizontalReduce(VecIRScalar dst, MoonliftVec.VecBinOp op, VecIRVector* values) unique
           | VecIRWiden(VecIRScalar dst, VecIRScalar src) unique
           | VecIRNarrow(VecIRScalar dst, VecIRScalar src, MoonliftVec.VecProof proof) unique
           | VecIRLoad(VecIRVector dst, MoonliftVec.VecAccessFact access) unique
           | VecIRStore(MoonliftVec.VecAccessFact access, VecIRVector value) unique
           | VecIRScalarCmd(MoonliftBack.BackCmd cmd) unique

  VecIRLoop = VecIRMainLoop(
      string loop_id,
      VecIRDomain domain,
      MoonliftVec.VecShape shape,
      number unroll,
      VecIRVector* accumulators,
      VecIRCmd* preheader,
      VecIRCmd* body,
      VecIRCmd* reduce,
      VecIRTail tail
  ) unique

  VecIRProgram = VecIRProgram(VecIRLoop* loops) unique
}
```

Current `vector_to_back.lua` is effectively constructing this skeleton implicitly.
The next implementation step should make it explicit.

---

## 7. Memory/vectorization model

Most real vectorization requires memory facts.

Do not start with alias analysis hidden in helper functions. Model memory access
as facts:

```text
VecAccessFact
VecAccessGroup
VecDependenceFact
VecAliasFact
VecBoundsFact
VecAlignmentFact
```

Required questions:

- Is each access load-only, store-only, or load-store?
- Is the index affine in the loop induction variable?
- Is the stride constant?
- Is the access contiguous for lanes?
- Are stores independent across lanes?
- Are loads independent from stores?
- Is the access in-bounds for the vector main loop?
- Is the tail scalar or masked?
- Is alignment known, assumed, or unknown?

Rejecting vectorization because dependence is unknown should produce a value like:

```text
VecRejectDependenceUnknown(loop_id, access_a, access_b)
```

not a string buried in a helper.

---

## 8. Control flow model

Start with straight-line loop bodies plus reductions. Then add explicit forms:

1. `select` / predicated expressions
2. masked vector body
3. early-exit rejection
4. later, if-conversion facts

Control flow facts:

```text
VecControlStraightLine
VecControlPredicatedSelect
VecControlMaskedBody
VecControlEarlyExitRejected
```

A branch is not automatically vectorizable. It becomes vectorizable only if the
fact layer can build explicit predication/mask facts.

---

## 9. Reductions and reassociation

Integer addition over fixed-width arithmetic is generally wrapping in machine IR,
but Moonlift semantics should be explicit about whether reassociation is allowed.

Reduction facts should include policy:

```text
VecReductionAdd(carry, value, reassociation_policy)
```

Policies:

```text
VecReassocWrappingOK
VecReassocExactOnly
VecReassocFloatFastMathOnly
VecReassocRejected
```

Floating-point reductions require explicit source/semantic permission, e.g.
`fastmath`, `assume_reassoc`, or a future source construct. Do not silently
reassociate floats.

---

## 10. Range and narrowing

The `i32x4` chunked plan is the first proof that range facts matter.

Generalize it:

```text
VecRangeFact(expr)
VecNarrowingProof(expr, from_ty, to_ty, range, chunk_elems)
VecAccumulatorBound(reduction, elem_max, iterations_per_lane, max_acc)
```

Then valid plans include:

- `i64x2` direct accumulator
- `i32x4` chunked accumulator
- `u16x8` chunked accumulator for very small terms
- `u8x16` chunked accumulator for byte-like kernels

Each narrowing must carry a proof and a chunk size.

---

## 11. Tail strategy

Tail handling is part of the plan, not an implementation detail.

Tail choices:

```text
VecTailNone
VecTailScalar
VecTailMasked
VecTailPeelToAlignment
```

Current Cranelift path should prefer scalar tails unless target facts say masks
are available and worthwhile.

---

## 12. Diagnostics

Every vectorization attempt should be explainable.

Desired API shape:

```lua
local report = pvm.one(V.explain_vectorization(loop, target_caps, policy))
print(VecReport.render(report))
```

Report content:

- detected facts
- legal facts
- rejected facts
- candidates
- chosen plan
- generated VecIR summary
- fallback reason if no vector plan

Example:

```text
loop func.sum.stmt.1:
  counted domain: i in 0..n step 1
  induction: lane index i
  reduction: acc += ((i * 1664525 + 1013904223) & 1023)
  range: term <= 1023
  legal: independent lanes
  legal: add reduction, wrapping reassociation
  legal: i32 accumulator in chunks of 1048576 elements
  target: i64x2 supported, i32x4 supported, scalar tail preferred
  candidates:
    i64x2_u1: elems/iter=2
    i64x2_u4: elems/iter=8
    i32x4_u4_chunked: elems/iter=16, chunk_safe=true
  chose: i32x4_u4_chunked
```

---

## 13. Implementation sequence

### Step 1 — split current vector pipeline conceptually

Keep existing code working, but introduce clearer phase names:

```text
vector_loop_facts
vector_loop_legal_facts
vector_target_facts
vector_loop_candidates
vector_plan_choice
vector_plan_to_vec_ir
vector_ir_to_back
```

### Step 2 — introduce `MoonliftVecIR`

Move the currently implicit skeleton in `vector_to_back.lua` into ASDL values.

Milestone:

```text
VecPlan -> VecIR -> Back
```

must produce the same results as the current direct `VecPlan -> Back` path.

### Step 3 — make target capabilities explicit

Add a `VecTargetCaps` value for the current Cranelift JIT target.

Initially hardcode it in Lua as ASDL facts, but do not hardcode it inside the
lowering logic.

### Step 4 — generate and rank candidates

For the current reduction kernel, candidate generation should produce:

- scalar fallback
- `i64x2_u1`
- `i64x2_u2`
- `i64x2_u4`
- `i32x4_u1_chunked`
- `i32x4_u2_chunked`
- `i32x4_u4_chunked`

Then choose according to target facts and policy.

### Step 5 — memory facts

Add vector load/store facts for views/slices once their runtime model is stable.

Initial memory kernels:

```moonlift
for i in 0..n do
  out[i] = a[i] + b[i]
end
```

Needed facts:

- three contiguous accesses
- `out` no-alias with `a`/`b`, or explicit overlap rejection
- in-bounds domain
- scalar tail

### Step 6 — predication / select

Support `select` as vector mask/value selection when target facts can lower it.

### Step 7 — richer reductions

Add:

- min/max reductions
- bitwise reductions
- float reductions only with explicit reassociation permission

---

## 14. Current status after first implementation work

Already implemented today:

- `MoonliftVec` fact vocabulary
- counted range-loop add-reduction detection
- explicit vector backend commands
- base `i64x2` vector reduction lowering
- unrolled `i64x2` vector reduction lowering
- bounded chunked `i32x4` vector reduction lowering
- scalar tail lowering
- Terra comparison benchmark track

Observed local full-run numbers for the current sum-reduction kernel:

```text
moonlift_scalar     63.235 ms
moonlift_vec2       31.933 ms
moonlift_vec2_u4    19.176 ms
moonlift_i32x4_u4   12.746 ms
terra                5.401 ms
```

So the ASDL path already reduced the Terra gap from about `11.7x` to about
`2.36x` on this kernel.

The remaining gap is now explainable as plan/target shape:

- Cranelift path is effectively v128 here
- Terra/LLVM emits wider AVX-512 vector code on this host
- we need explicit target facts, candidate ranking, VecIR skeletons, memory facts,
  and eventually wider/lower-level vector backend support where available

---

## 15. Rule of thumb

If a vectorization decision affects generated code, it must be one of:

- a `VecFact`
- a `VecLegalFact`
- a `VecTargetFact`
- a `VecCandidate`
- a `VecPlan`
- a `VecIR` node
- a `BackCmd`

If it is only a helper `if`, it is probably in the wrong layer.
