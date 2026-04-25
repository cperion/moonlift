# Moonlift Vectorization ASDL Redesign

This document records the coherent ASDL-first vectorization redesign.

The correction is important:

> We do **not** add vectorization as a pile of compatibility wrappers or staged
> migration patches. The compiler pipeline is a whole, and the ASDL must be one
> coherent unit.

PVM `phase(...)` remains the dispatch/execution mechanism, but the design is not
“phase 1 compatibility, phase 2 wrapper, phase 3 cleanup.” The design starts from
one ASDL model for vector-capable lowering, then the Lua/Rust code is made to
match that model.

---

## 1. Current ASDL diagnosis

Current `MoonliftVec` is useful as a prototype, but it is not a coherent vector
compiler model yet.

Current shape:

```asdl
module MoonliftVec {
    VecBinOp
    VecReject
    VecExprFact
    VecLocalFact
    VecEnv
    VecReduction
    VecStmtFact
    VecBodyFacts
    VecDomainFact
    VecLoopFact
    VecPlan
}
```

Problems:

1. **Facts and plans are mixed in one shallow ladder.**
   `VecLoopFact -> VecPlan -> BackProgram` skips the real IR boundary.

2. **`VecPlan` encodes hand-written cases, not a general vector program shape.**
   `VecAddReductionPlan`, `VecUnrolledAddReductionPlan`, and
   `VecChunkedI32AddReductionPlan` are too close to current experiments.

3. **Legality has no first-class home.**
   Bounded-narrowing is currently recognized by helper logic instead of a proof
   value that every consumer can inspect.

4. **Target capability has no ASDL representation.**
   The reason `i32x4` is good and `i64x2` is limited is not represented as data.

5. **Vector IR is implicit in Lua construction of `BackCmd`s.**
   `vector_to_back.lua` currently builds blocks, ramps, accumulators, tails, and
   chunked loops directly as `Back` commands. Those are meaningful compiler IR
   structures and must be ASDL values before `Back`.

6. **Memory/dependence cannot fit cleanly into the current model.**
   Real vectorization of views/slices needs access, alias, bounds, and dependence
   facts. The current `VecStmtRejected("stores are not vectorizable")` cannot
   evolve into that cleanly.

7. **Diagnostics are string-oriented.**
   Strings are okay as payloads, but the reason category must be represented by
   variants.

The fix is not compatibility shims. The fix is a new coherent `MoonliftVec` ASDL
model.

---

## 2. Coherent compiler shape

The vector-capable compiler path should be one semantic lowering path:

```text
MoonliftSem
  -> MoonliftVec.VecModule
  -> MoonliftBack.BackProgram
```

`VecModule` is not “an optimization report.” It is the machine-shaping IR between
`Sem` and `Back` for vector-capable numeric code.

Scalar-only lowering can still exist, but the long-term closed backend should be:

```text
Sem -> Vec-aware mid IR -> Back
```

where the mid IR can choose scalar or vector loop shapes explicitly.

So the real root is not `VecPlan`. The root is:

```asdl
VecModule = (VecFunc* funcs) unique
VecFunc = VecFuncScalar(...)
        | VecFuncVector(...)
        | VecFuncMixed(...)
```

A loop can lower to scalar, vector, or rejected/scalar fallback **inside the same
coherent IR vocabulary**.

---

## 3. ASDL design principles

### 3.1 The unit is a vector-capable IR, not a pass report

Do not model vectorization as:

```text
facts + candidates + report + legacy Back shim
```

Model it as:

```text
VecModule containing chosen explicit code shapes
```

Facts/proofs/candidates still exist, but as subvalues needed to justify the chosen
shape.

### 3.2 Facts must be referential

Expression facts, memory accesses, and reductions need IDs.

Without IDs:

- range facts cannot refer to subexpressions cleanly
- diagnostics cannot point at facts
- candidates cannot refer to proofs without duplicating trees
- invariant hoisting becomes helper-cache driven

### 3.3 Legality is carried by the chosen shape

A vector loop node must carry the proofs that make it legal.

Example:

```asdl
VecLoopVector(..., VecProof* proofs, VecTail tail, VecLoopBody body)
```

Then `VecIR -> Back` does not ask “is this legal?” It only lowers an already legal
IR node.

### 3.4 Target choice is part of the IR construction input

Target facts are ASDL input to construction, not scattered constants.

### 3.5 Back remains flat execution facts

`BackProgram` should stay flat and mechanical. It is not where vector loop meaning
lives.

---

## 4. Proposed coherent `MoonliftVec` ASDL

This is the proposed replacement shape for the current `MoonliftVec` module.

It is one coherent unit. It contains facts, proofs, selected shapes, and vector IR
because those values refer to one another.

```asdl
module MoonliftVec {
    -- ------------------------------------------------------------
    -- identities
    -- ------------------------------------------------------------

    VecExprId = (string text) unique
    VecLoopId = (string text) unique
    VecAccessId = (string text) unique
    VecValueId = (string text) unique
    VecBlockId = (string text) unique

    -- ------------------------------------------------------------
    -- scalar/vector machine-independent type shape
    -- ------------------------------------------------------------

    VecElem = VecElemBool
            | VecElemI8 | VecElemI16 | VecElemI32 | VecElemI64
            | VecElemU8 | VecElemU16 | VecElemU32 | VecElemU64
            | VecElemF32 | VecElemF64
            | VecElemIndex

    VecShape = VecScalarShape(VecElem elem) unique
             | VecVectorShape(VecElem elem, number lanes) unique

    VecBinOp = VecAdd | VecSub | VecMul
             | VecBitAnd | VecBitOr | VecBitXor
             | VecShl | VecLShr | VecAShr
             | VecEq | VecNe | VecLt | VecLe | VecGt | VecGe

    VecUnaryOp = VecNeg | VecNot | VecBitNot | VecPopcount | VecClz | VecCtz

    -- ------------------------------------------------------------
    -- structured rejects and proofs
    -- ------------------------------------------------------------

    VecReject = VecRejectUnsupportedLoop(MoonliftVec.VecLoopId loop, string reason) unique
              | VecRejectUnsupportedExpr(MoonliftVec.VecExprId expr, string reason) unique
              | VecRejectUnsupportedStmt(string stmt_id, string reason) unique
              | VecRejectUnsupportedMemory(MoonliftVec.VecAccessId access, string reason) unique
              | VecRejectDependence(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, string reason) unique
              | VecRejectRange(MoonliftVec.VecExprId expr, string reason) unique
              | VecRejectTarget(MoonliftVec.VecShape shape, string reason) unique
              | VecRejectCost(string reason) unique

    VecProof = VecProofDomain(string reason) unique
             | VecProofRange(MoonliftVec.VecRangeFact range, string reason) unique
             | VecProofNoMemoryDependence(MoonliftVec.VecAccessId* accesses, string reason) unique
             | VecProofReduction(MoonliftVec.VecReductionFact reduction, string reason) unique
             | VecProofNarrowSafe(MoonliftVec.VecReductionFact reduction, MoonliftVec.VecElem narrow_elem, number chunk_elems, string reason) unique
             | VecProofTarget(MoonliftVec.VecTargetFact fact, string reason) unique

    -- ------------------------------------------------------------
    -- target facts
    -- ------------------------------------------------------------

    VecTarget = VecTargetCraneliftJit
              | VecTargetNamed(string name) unique

    VecTargetFact = VecTargetSupportsShape(MoonliftVec.VecShape shape) unique
                  | VecTargetSupportsBinOp(MoonliftVec.VecShape shape, MoonliftVec.VecBinOp op) unique
                  | VecTargetSupportsUnaryOp(MoonliftVec.VecShape shape, MoonliftVec.VecUnaryOp op) unique
                  | VecTargetPrefersUnroll(MoonliftVec.VecShape shape, number unroll, number rank) unique
                  | VecTargetPrefersScalarTail
                  | VecTargetSupportsMaskedTail
                  | VecTargetVectorBits(number bits) unique

    VecTargetModel = (MoonliftVec.VecTarget target, MoonliftVec.VecTargetFact* facts) unique

    -- ------------------------------------------------------------
    -- expression graph facts
    -- ------------------------------------------------------------

    VecExprFact = VecExprConst(MoonliftVec.VecExprId id, MoonliftSem.SemExpr expr, MoonliftSem.SemType ty) unique
                | VecExprInvariant(MoonliftVec.VecExprId id, MoonliftSem.SemExpr expr, MoonliftSem.SemType ty) unique
                | VecExprLaneIndex(MoonliftVec.VecExprId id, MoonliftSem.SemBinding binding, MoonliftSem.SemType ty) unique
                | VecExprLocal(MoonliftVec.VecExprId id, MoonliftSem.SemBinding binding, MoonliftVec.VecExprId value, MoonliftSem.SemType ty) unique
                | VecExprUnary(MoonliftVec.VecExprId id, MoonliftVec.VecUnaryOp op, MoonliftVec.VecExprId value, MoonliftSem.SemType ty) unique
                | VecExprBin(MoonliftVec.VecExprId id, MoonliftVec.VecBinOp op, MoonliftVec.VecExprId lhs, MoonliftVec.VecExprId rhs, MoonliftSem.SemType ty) unique
                | VecExprSelect(MoonliftVec.VecExprId id, MoonliftVec.VecExprId cond, MoonliftVec.VecExprId then_value, MoonliftVec.VecExprId else_value, MoonliftSem.SemType ty) unique
                | VecExprLoad(MoonliftVec.VecExprId id, MoonliftVec.VecAccessId access, MoonliftSem.SemType ty) unique
                | VecExprRejected(MoonliftVec.VecExprId id, MoonliftVec.VecReject reject) unique

    VecExprGraph = (MoonliftVec.VecExprFact* exprs) unique

    -- ------------------------------------------------------------
    -- range facts
    -- ------------------------------------------------------------

    VecRangeFact = VecRangeUnknown(MoonliftVec.VecExprId expr) unique
                 | VecRangeExact(MoonliftVec.VecExprId expr, string value) unique
                 | VecRangeUnsigned(MoonliftVec.VecExprId expr, string min, string max) unique
                 | VecRangeBitAnd(MoonliftVec.VecExprId expr, string mask, string max_value) unique
                 | VecRangeDerived(MoonliftVec.VecExprId expr, string min, string max, MoonliftVec.VecProof* proofs) unique

    -- ------------------------------------------------------------
    -- domain and induction facts
    -- ------------------------------------------------------------

    VecDomain = VecDomainCounted(MoonliftSem.SemExpr start, MoonliftSem.SemExpr stop, MoonliftSem.SemExpr step) unique
              | VecDomainRejected(MoonliftVec.VecReject reject) unique

    VecInduction = VecPrimaryInduction(MoonliftSem.SemBinding binding, MoonliftSem.SemExpr start, MoonliftSem.SemExpr step) unique
                 | VecDerivedInduction(MoonliftSem.SemBinding binding, MoonliftVec.VecExprId expr) unique

    -- ------------------------------------------------------------
    -- memory facts
    -- ------------------------------------------------------------

    VecAccessKind = VecAccessLoad | VecAccessStore

    VecAccessPattern = VecAccessContiguous
                     | VecAccessStrided(number stride)
                     | VecAccessGather
                     | VecAccessScatter
                     | VecAccessUnknown

    VecAlignment = VecAlignmentKnown(number bytes)
                 | VecAlignmentUnknown
                 | VecAlignmentAssumed(number bytes, MoonliftVec.VecProof proof) unique

    VecBounds = VecBoundsProven(MoonliftVec.VecProof proof) unique
              | VecBoundsUnknown(MoonliftVec.VecReject reject) unique

    VecMemoryFact = VecMemoryAccess(MoonliftVec.VecAccessId id,
                                    MoonliftVec.VecAccessKind kind,
                                    MoonliftSem.SemExpr base,
                                    MoonliftVec.VecExprId index,
                                    MoonliftSem.SemType elem_ty,
                                    MoonliftVec.VecAccessPattern pattern,
                                    MoonliftVec.VecAlignment alignment,
                                    MoonliftVec.VecBounds bounds) unique

    VecDependenceFact = VecNoDependence(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, MoonliftVec.VecProof proof) unique
                      | VecDependenceUnknown(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, MoonliftVec.VecReject reject) unique
                      | VecLoopCarriedDependence(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, MoonliftVec.VecReject reject) unique

    -- ------------------------------------------------------------
    -- reductions and reassociation
    -- ------------------------------------------------------------

    VecReassoc = VecReassocWrapping
               | VecReassocExact
               | VecReassocFloatFastMath
               | VecReassocRejected(MoonliftVec.VecReject reject) unique

    VecReductionFact = VecReductionAdd(MoonliftSem.SemCarryPort carry,
                                       MoonliftVec.VecExprId value,
                                       MoonliftVec.VecReassoc reassoc) unique
                     | VecReductionMul(MoonliftSem.SemCarryPort carry,
                                       MoonliftVec.VecExprId value,
                                       MoonliftVec.VecReassoc reassoc) unique
                     | VecReductionBitAnd(MoonliftSem.SemCarryPort carry,
                                          MoonliftVec.VecExprId value) unique
                     | VecReductionBitOr(MoonliftSem.SemCarryPort carry,
                                         MoonliftVec.VecExprId value) unique
                     | VecReductionBitXor(MoonliftSem.SemCarryPort carry,
                                          MoonliftVec.VecExprId value) unique

    VecStoreFact = VecStoreFact(MoonliftVec.VecMemoryFact access,
                                MoonliftVec.VecExprId value) unique

    -- ------------------------------------------------------------
    -- complete semantic loop model
    -- ------------------------------------------------------------

    VecLoopFacts = VecLoopFacts(MoonliftVec.VecLoopId loop,
                                MoonliftVec.VecDomain domain,
                                MoonliftVec.VecInduction* inductions,
                                MoonliftVec.VecExprGraph exprs,
                                MoonliftVec.VecMemoryFact* memory,
                                MoonliftVec.VecDependenceFact* dependences,
                                MoonliftVec.VecRangeFact* ranges,
                                MoonliftVec.VecStoreFact* stores,
                                MoonliftVec.VecReductionFact* reductions,
                                MoonliftVec.VecReject* rejects) unique

    -- ------------------------------------------------------------
    -- explicit chosen lowering shapes
    -- ------------------------------------------------------------

    VecTail = VecTailNone
            | VecTailScalar
            | VecTailMasked(MoonliftVec.VecProof proof) unique

    VecLoopShape = VecLoopScalar(MoonliftVec.VecLoopId loop, MoonliftVec.VecReject* vector_rejects) unique
                 | VecLoopVector(MoonliftVec.VecLoopId loop,
                                 MoonliftVec.VecShape shape,
                                 number unroll,
                                 MoonliftVec.VecTail tail,
                                 MoonliftVec.VecProof* proofs) unique
                 | VecLoopChunkedNarrowVector(MoonliftVec.VecLoopId loop,
                                               MoonliftVec.VecShape narrow_shape,
                                               number unroll,
                                               number chunk_elems,
                                               MoonliftVec.VecTail tail,
                                               MoonliftVec.VecProof narrow_proof,
                                               MoonliftVec.VecProof* proofs) unique

    VecShapeScore = VecShapeScore(MoonliftVec.VecLoopShape shape,
                                  number elems_per_iter,
                                  number rank,
                                  string rationale) unique

    VecLoopDecision = VecLoopDecision(MoonliftVec.VecLoopFacts facts,
                                      MoonliftVec.VecLoopShape chosen,
                                      MoonliftVec.VecShapeScore* considered) unique

    -- ------------------------------------------------------------
    -- vector-capable IR: this is the real middle IR
    -- ------------------------------------------------------------

    VecValue = VecScalarValue(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem) unique
             | VecVectorValue(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem, number lanes) unique

    VecParam = VecScalarParam(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem) unique
             | VecVectorParam(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem, number lanes) unique

    VecCmd = VecCmdConstInt(MoonliftVec.VecValueId dst, MoonliftVec.VecElem elem, string raw) unique
           | VecCmdSplat(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecValueId scalar) unique
           | VecCmdRamp(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecValueId base, string* offsets) unique
           | VecCmdBin(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecBinOp op, MoonliftVec.VecValueId lhs, MoonliftVec.VecValueId rhs) unique
           | VecCmdSelect(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecValueId cond, MoonliftVec.VecValueId then_value, MoonliftVec.VecValueId else_value) unique
           | VecCmdIreduce(MoonliftVec.VecValueId dst, MoonliftVec.VecElem narrow_elem, MoonliftVec.VecValueId value, MoonliftVec.VecProof proof) unique
           | VecCmdUextend(MoonliftVec.VecValueId dst, MoonliftVec.VecElem wide_elem, MoonliftVec.VecValueId value) unique
           | VecCmdExtractLane(MoonliftVec.VecValueId dst, MoonliftVec.VecValueId vec, number lane) unique
           | VecCmdHorizontalReduce(MoonliftVec.VecValueId dst, MoonliftVec.VecBinOp op, MoonliftVec.VecValueId* vectors) unique
           | VecCmdLoad(MoonliftVec.VecValueId dst,
                        MoonliftVec.VecShape shape,
                        MoonliftVec.VecMemoryFact access,
                        MoonliftVec.VecValueId addr) unique
           | VecCmdStore(MoonliftVec.VecMemoryFact access,
                         MoonliftVec.VecShape shape,
                         MoonliftVec.VecValueId addr,
                         MoonliftVec.VecValueId value) unique
           | VecCmdBack(MoonliftBack.BackCmd cmd) unique

    VecTerminator = VecJump(MoonliftVec.VecBlockId dest, MoonliftVec.VecValueId* args) unique
                  | VecBrIf(MoonliftVec.VecValueId cond,
                            MoonliftVec.VecBlockId then_block, MoonliftVec.VecValueId* then_args,
                            MoonliftVec.VecBlockId else_block, MoonliftVec.VecValueId* else_args) unique
                  | VecReturnVoid
                  | VecReturnValue(MoonliftVec.VecValueId value) unique

    VecBlock = VecBlock(MoonliftVec.VecBlockId id,
                        MoonliftVec.VecParam* params,
                        MoonliftVec.VecCmd* cmds,
                        MoonliftVec.VecTerminator terminator) unique

    VecFunc = VecFuncScalar(MoonliftSem.SemFunc func, MoonliftVec.VecLoopDecision* decisions, MoonliftBack.BackFuncPlan scalar_plan) unique
            | VecFuncVector(MoonliftSem.SemFunc func, MoonliftVec.VecLoopDecision* decisions, MoonliftVec.VecBlock* blocks) unique
            | VecFuncMixed(MoonliftSem.SemFunc func, MoonliftVec.VecLoopDecision* decisions, MoonliftVec.VecBlock* blocks) unique

    VecModule = VecModule(MoonliftSem.SemModule source,
                          MoonliftVec.VecTargetModel target,
                          MoonliftVec.VecFunc* funcs) unique
}
```

---

## 5. Why this is coherent

The module has one root:

```asdl
VecModule
```

Everything else exists because `VecModule` needs it:

- facts justify decisions
- proofs justify legality
- target facts justify shape choices
- loop shapes choose scalar/vector/chunked lowering
- blocks/commands encode the chosen vector-capable IR
- `VecFuncScalar` is not “compatibility”; it is the scalar shape in the same IR

That last distinction is important. We are not adding compatibility fallback. We
are admitting that scalar code is one valid code shape inside the coherent vector-
capable compiler IR.

---

## 6. Relationship to `MoonliftBack`

`MoonliftBack` remains machine-facing, flat, Cranelift-replayable facts.

`MoonliftVec` should not be a thin alias for `Back`. It should carry meaning that
`Back` intentionally does not carry:

- domains
- inductions
- proofs
- vector shapes
- tail strategy
- narrowing strategy
- memory/dependence facts
- selected loop skeleton

The lowering boundary is:

```text
VecModule -> BackProgram
```

At that point, all semantic and vector decisions are already made.

---

## 7. Current code that becomes obsolete

The following current concepts should be replaced, not wrapped forever:

```asdl
VecEnv
VecStmtFact
VecBodyFacts
VecCountedLoop
VecLoopRejected
VecAddReductionPlan
VecUnrolledAddReductionPlan
VecChunkedI32AddReductionPlan
VecNoPlan
```

Their information survives in the coherent model:

| Old | New |
|---|---|
| `VecEnv` | construction-time environment only, not ASDL unless it carries meaning |
| `VecStmtFact` | `VecExprGraph`, `VecMemoryFact`, `VecReductionFact`, rejects |
| `VecBodyFacts` | `VecLoopFacts` |
| `VecCountedLoop` | `VecLoopFacts(... VecDomainCounted ...)` |
| `VecAddReductionPlan` | `VecLoopVector` decision + `VecBlock` skeleton |
| `VecChunkedI32AddReductionPlan` | `VecLoopChunkedNarrowVector` decision + `VecBlock` skeleton |
| `VecNoPlan` | `VecLoopScalar` with structured rejects |

---

## 8. What the current benchmark should become

The current sum kernel should produce a `VecModule` containing one vector function
with one loop decision:

```text
VecLoopDecision
  facts:
    domain: counted 0..n step 1
    induction: i
    expr graph: term = ((i * 1664525 + 1013904223) & 1023)
    range: term <= 1023
    reduction: acc += term, wrapping reassociation
  chosen:
    VecLoopChunkedNarrowVector(shape=i32x4, unroll=4, chunk_elems=1048576)
  considered:
    scalar
    i64x2_u1
    i64x2_u4
    i32x4_u4_chunked
```

Then the same `VecFuncVector` contains the explicit blocks/commands for the chosen
shape.

No separate compatibility lowering. No legacy plan wrapper.

---

## 9. Implementation implication

The next implementation should not add wrappers around current `VecPlan`.

It should do this instead:

1. Replace `MoonliftVec` ASDL with the coherent shape above, adjusted for actual
   parser/schema constraints.
2. Rewrite `vector_facts.lua` to build `VecLoopFacts` / `VecModule` data, not old
   plan variants.
3. Rewrite vector lowering to build `VecBlock` / `VecCmd` skeletons as ASDL.
4. Add one lowering from `VecModule` to `BackProgram`.
5. Update tests to assert the new ASDL values, not old `VecPlan` variants.

This is a breaking refactor. That is okay. The compiler pipeline is a whole.

---

## 10. PVM execution note

“We do not phase” here means: do not design the compiler as an incremental patch
stack with compatibility layers.

It does **not** mean “avoid `pvm.phase`.” In this repo, `pvm.phase(...)` is still
the correct way to implement typed dispatch from one ASDL value to another.

The correct use is:

```text
ASDL coherent unit first
then pvm.phase handlers implement transformations between those ASDL values
```

not:

```text
write helpers
add wrappers
patch compatibility
later hope the ASDL becomes coherent
```

---

## 11. Immediate design TODO before coding

Before touching Lua implementation again, settle these ASDL questions:

1. Should `MoonliftVec` reference `MoonliftBack.BackCmd` in `VecCmdBack`, or should
   there be no Back escape hatch at all?
   - Preferred: no escape hatch in final design.
   - Temporary during implementation: avoid if we are doing a whole refactor.

2. Should `VecFuncScalar` carry `BackFuncPlan`, or should scalar lowering also be
   represented in `VecBlock`/`VecCmd`?
   - Preferred coherent answer: scalar lowering should eventually also be Vec IR
     or a separate `MoonliftMid` IR, not `BackFuncPlan`.
   - Short-term if scope is vector loops only: scalar functions can still use
     existing Sem->Back outside this path, but not as a compatibility wrapper.

3. Should `VecElemIndex` exist, or should index be resolved to pointer-sized
   signed/unsigned element before Vec?
   - Preferred: keep `VecElemIndex` at Vec level, resolve to `BackIndex` in
     `VecModule -> BackProgram`.

4. Should target facts live in `MoonliftVec` or a separate `MoonliftTarget` module?
   - Preferred: inside `MoonliftVec` initially because they directly determine
     vector shapes.

5. Should candidate scores be stored if the chosen IR is enough?
   - Preferred: yes, because diagnostics are architectural feedback, but they
     should be part of `VecLoopDecision`, not a separate report pipeline.

---

## 12. Bottom line

The right design is not:

```text
old VecPlan + wrappers + compatibility + later cleanup
```

The right design is:

```text
replace MoonliftVec with one coherent vector-capable middle IR
make facts/proofs/decisions/blocks all ASDL values
lower VecModule mechanically to BackProgram
```

That is the ASDL-first route.
