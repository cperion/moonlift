# Lalin Semantic Lowering Architecture

Status: design decision. This document is intentionally concrete. It names the
ASDL modules, the phase tree, the lowering contracts, the metadata that may cross
the backend boundary, and the things we explicitly will not do.

The previous tower proved the direction but left too many choices implicit. This
version removes those hidden choices.

---

## 0. The decision in one page

Lalin native performance will not be built from recognizers.

The compiler will lower through this fixed tree:

```text
LalinTree
  -> LalinCode
  -> LalinGraph
  -> LalinFlow
  -> LalinValue
  -> LalinMem
  -> LalinEffect
  -> LalinKernel
  -> LalinSchedule
  -> LalinLower
  -> LuaTrace / C / native stencil bank realization
```

Each arrow is a PVM phase boundary. Each phase has one job. Each phase produces
ASDL values, not Lua side tables as architecture.

The most important change is this:

```text
Lowering is fragment-based.
```

A function is not lowered as either "generic code" or "whole-function kernel".
A function is covered by ordered lowering fragments:

```text
prologue block range       -> Code lowering
inner counted loop         -> Kernel + Schedule lowering
call block                 -> Code lowering with Effect facts
epilogue block range       -> Code lowering
```

The second most important change:

```text
Facts shape ordinary Code lowering.
```

Memory, arithmetic, value, and effect facts are not just admission tests for
Kernel. Ordinary loads/stores/ops/calls consume the same facts during executable
lowering. If a fact cannot be consumed by an active executable backend, it stays
in the planning layers and does not cross the backend boundary.

---

## 1. Non-negotiable rules

1. **LalinCode is the executable meaning boundary.** Backends do not recurse into
   LalinTree for semantics.
2. **No hidden compiler state as architecture.** Lua maps may be caches, but any
   meaning needed by another phase must be an ASDL value.
3. **No whole-function performance cliff.** Whole-function kernel lowering is a
   special case of fragment lowering, not the model.
4. **No decorative backend ASDL.** A backend fact is executable and consumed by
   LuaTrace, C, or a native stencil bank, or it stays in planning.
5. **No benchmark recognizers.** If a transform matters, its proof is a general
   Flow/Value/Mem/Effect fact.
6. **Kernel is semantic. Schedule is target-specific. Lower is compositional.**
7. **Views and leases are first-class Code/Mem facts.** No backend lowering
   keyed by hidden `ctx.view_values`-style side tables.
8. **Fallback lowering is fact-aware.** Falling back from Kernel to Code must
   not discard facts.
9. **PVM phases are vocabulary boundaries.** A phase answers one question and
   emits one ASDL vocabulary.
10. **Fail loud at executable boundaries.** Silent metadata loss is forbidden;
    unsupported semantic metadata is kept before Back or rejected by encoding.

---

## 2. Module tree and files

The target schema tree is:

```text
lua/lalin/schema/code.lua       existing; canonical Code, extended for leases/views
lua/lalin/schema/graph.lua      new; Code graph indices
lua/lalin/schema/flow.lua       existing; loop/control facts, tightened
lua/lalin/schema/value.lua      new; symbolic values, affine/reduction/algebra facts
lua/lalin/schema/mem.lua        existing; memory objects/access/safety/lease facts
lua/lalin/schema/effect.lua     new; calls, invalidation, noescape, trap/effect summaries
lua/lalin/schema/kernel.lua     existing; semantic kernels only, no schedules
lua/lalin/schema/schedule.lua   new; target-specific schedules/profitability
lua/lalin/schema/lower.lua      replace; compositional function fragment plan
lua/lalin/schema/back.lua       existing; executable Back only, no decorative facts
```

Implementation modules mirror the schema tree:

```text
lua/lalin/tree_to_code.lua
lua/lalin/code_graph.lua
lua/lalin/code_flow_facts.lua
lua/lalin/code_value_facts.lua
lua/lalin/code_mem_facts.lua
lua/lalin/code_effect_facts.lua
lua/lalin/code_kernel_plan.lua
lua/lalin/code_kernel_plan_rules.lua
lua/lalin/code_schedule_plan.lua
lua/lalin/code_schedule_plan_rules.lua
lua/lalin/code_lower_plan.lua
lua/lalin/lower_to_back.lua
```

`code_to_back.lua` remains only as the internal implementation of
`LowerStrategyCode`; it no longer owns a separate architecture.

---

## 3. PVM phase tree

The phase graph is fixed:

```lua
local code      = pvm.phase("tree_to_code", tree)
local graph     = pvm.phase("code_graph", code)
local flow      = pvm.phase("code_flow_facts", code, graph)
local value     = pvm.phase("code_value_facts", code, graph, flow)
local mem       = pvm.phase("code_mem_facts", code, graph, flow, value, contracts)
local effect    = pvm.phase("code_effect_facts", code, graph, mem)
local kernels   = pvm.phase("code_kernel_plan", code, graph, flow, value, mem, effect)
local schedules = pvm.phase("code_schedule_plan", code, kernels, flow, value, mem, effect, target)
local lower     = pvm.phase("code_lower_plan", code, graph, kernels, schedules, target)
local back      = pvm.phase("lower_to_back", code, graph, flow, value, mem, effect, kernels, schedules, lower)
local wire      = pvm.phase("back_encode", back, target)
```

A later implementation may split phases further, but it may not merge semantic
vocabularies back into a single opaque lowering pass.

---

## 4. LalinCode commitments

LalinCode remains the canonical executable IR. It must explicitly represent the
values that later phases need.

### 4.1 Views are explicit Code values

Backend lowering must not reconstruct views from hidden Lua state.

Add or standardize these Code operations if not already present in this exact
meaning:

```asdl
CodeInst = ...
    | CodeInstViewMake(LalinCode.CodeValueId dst,
                       LalinCode.CodeType elem_ty,
                       LalinCode.CodeValueId data,
                       LalinCode.CodeValueId len,
                       LalinCode.CodeValueId stride,
                       LalinCode.CodeOrigin origin) unique
    | CodeInstViewData(LalinCode.CodeValueId dst, LalinCode.CodeValueId view, LalinCode.CodeOrigin origin) unique
    | CodeInstViewLen(LalinCode.CodeValueId dst, LalinCode.CodeValueId view, LalinCode.CodeOrigin origin) unique
    | CodeInstViewStride(LalinCode.CodeValueId dst, LalinCode.CodeValueId view, LalinCode.CodeOrigin origin) unique
```

A view may still lower to multiple machine values, but the decomposition is Code,
not a backend side table.

### 4.2 Leases are Code types until checked

Lease-ness is not a machine representation, but it is Code meaning.

```asdl
CodeType = ...
    | CodeTyLease(LalinCode.CodeType base, LalinType.Type source_ty) unique
```

Lowering may erase `CodeTyLease(base)` to `base` only after `LalinEffect` proves
no escape and no invalidating same-store operation crosses the live range.

### 4.3 Handles remain opaque Code values

```asdl
CodeType = ...
    | CodeTyHandle(LalinCode.CodeType repr, LalinType.Type source_ty) unique
```

Allowed Code operations on handles:

- copy
- same-type equality/inequality
- pass/return/store as value
- compare with declared invalid value

Forbidden in safe Code:

- arithmetic
- bitwise ops
- pointer casts
- repr casts, except trusted store-private operations represented as explicit
  unsafe/effectful operations

### 4.4 Contracts are Code facts, not parser trivia

Contracts produce `CodeContractFactSet`. Later phases consume this ASDL. No phase
may inspect raw source contract syntax.

---

## 5. LalinGraph ASDL

`LalinGraph` is the shared index over Code. It is deliberately non-semantic.

```asdl
module LalinGraph {
    GraphBlockId = (LalinCode.CodeFuncId func, LalinCode.CodeBlockId block) unique
    GraphInstRef = (LalinCode.CodeFuncId func, LalinCode.CodeBlockId block, LalinCode.CodeInstId inst) unique
    GraphEdge = (LalinGraph.GraphBlockId from, LalinGraph.GraphBlockId to, string kind) unique

    GraphUse = (LalinCode.CodeValueId value, LalinGraph.GraphInstRef? inst, LalinGraph.GraphBlockId? term_block, string role) unique
    GraphDef = (LalinCode.CodeValueId value, LalinGraph.GraphInstRef? inst, LalinCode.CodeParamId? param) unique

    GraphLoopId = (string text) unique
    GraphLoop = (LalinGraph.GraphLoopId id,
                 LalinCode.CodeFuncId func,
                 LalinGraph.GraphBlockId header,
                 LalinGraph.GraphBlockId* body,
                 LalinGraph.GraphEdge* latches,
                 LalinGraph.GraphEdge* exits) unique

    CodeFuncGraph = (LalinCode.CodeFuncId func,
                     LalinGraph.GraphEdge* edges,
                     LalinGraph.GraphDef* defs,
                     LalinGraph.GraphUse* uses,
                     LalinGraph.GraphLoop* loops) unique

    CodeGraph = (LalinCode.CodeModuleId module, LalinGraph.CodeFuncGraph* funcs) unique
}
```

Decision: dominance/postdominance may be added later as facts, but the first
required graph vocabulary is edges, defs, uses, loops.

---

## 6. LalinFlow ASDL tightening

LalinFlow owns control domains. Existing loop facts remain, but the subject type
must align with Graph loops.

Required additions/standardization:

```asdl
FlowDomainId = (string text) unique

FlowDomain = FlowDomainLoop(LalinGraph.GraphLoopId loop) unique
    | FlowDomainBlockRange(LalinCode.CodeFuncId func, LalinCode.CodeBlockId entry, LalinCode.CodeBlockId exit) unique
    | FlowDomainFunction(LalinCode.CodeFuncId func) unique

FlowTripCount = FlowTripCountExact(LalinCode.CodeValueId count, LalinMem.MemProof? proof) unique
    | FlowTripCountNonNegative(LalinCode.CodeValueId count, LalinMem.MemProof? proof) unique
    | FlowTripCountUnknown(string reason) unique
```

Decision: exact trip count is a fact. Lowering may not silently treat
non-negative as exact.

---

## 7. LalinValue / LalinAlgebra ASDL

This is the largest missing layer. It removes algebra from Kernel recognizers.

```asdl
module LalinValue {
    ValueFactId = (string text) unique
    AlgebraFactId = (string text) unique

    ValueExpr = ValueExprConst(LalinCode.CodeConst const) unique
        | ValueExprValue(LalinCode.CodeValueId value) unique
        | ValueExprAdd(LalinValue.ValueExpr a, LalinValue.ValueExpr b, LalinCode.CodeType ty, LalinCode.CodeIntSemantics? sem) unique
        | ValueExprSub(LalinValue.ValueExpr a, LalinValue.ValueExpr b, LalinCode.CodeType ty, LalinCode.CodeIntSemantics? sem) unique
        | ValueExprMul(LalinValue.ValueExpr a, LalinValue.ValueExpr b, LalinCode.CodeType ty, LalinCode.CodeIntSemantics? sem) unique
        | ValueExprDiv(LalinValue.ValueExpr a, LalinValue.ValueExpr b, LalinCode.CodeType ty, LalinCode.CodeIntSemantics? sem) unique
        | ValueExprSelect(LalinValue.ValueExpr cond, LalinValue.ValueExpr t, LalinValue.ValueExpr f) unique
        | ValueExprCmp(LalinCore.CmpOp op, LalinCode.CodeType ty, LalinValue.ValueExpr a, LalinValue.ValueExpr b) unique
        | ValueExprAffine(LalinValue.AffineExpr affine) unique

    AffineTerm = (LalinCode.CodeValueId value, string coeff) unique
    AffineExpr = (string constant, LalinValue.AffineTerm* terms, LalinCode.CodeType ty, LalinCode.CodeIntSemantics? sem) unique

    ValueRange = ValueRangeUnknown(string reason) unique
        | ValueRangeInt(LalinCode.CodeValueId value, LalinValue.ValueExpr lo, LalinValue.ValueExpr hi, bool inclusive_hi, LalinValue.AlgebraProof proof) unique

    ReductionKind = ReductionAdd | ReductionMul | ReductionMin | ReductionMax | ReductionAnd | ReductionOr | ReductionXor

    ReductionFact = (LalinValue.AlgebraFactId id,
                     LalinFlow.FlowDomain domain,
                     LalinCode.CodeValueId accumulator,
                     LalinValue.ReductionKind kind,
                     LalinValue.ValueExpr init,
                     LalinValue.ValueExpr contribution,
                     LalinCode.CodeType ty,
                     LalinCode.CodeIntSemantics? int_semantics,
                     LalinCode.CodeFloatMode? float_mode,
                     LalinValue.AlgebraProof proof) unique

    ClosedFormFact = (LalinValue.AlgebraFactId id,
                      LalinValue.ReductionFact reduction,
                      LalinValue.ValueExpr expr,
                      LalinValue.AlgebraProof proof) unique

    AlgebraProof = AlgebraProofFlow(LalinFlow.FlowDomain domain, string reason) unique
        | AlgebraProofNoWrap(LalinCode.CodeValueId value, string reason) unique
        | AlgebraProofIdentity(string reason) unique
        | AlgebraProofReduction(LalinValue.ReductionFact fact, string reason) unique
        | AlgebraProofComposite(LalinValue.AlgebraProof* proofs, string reason) unique

    ValueFact = ValueExprFact(LalinCode.CodeValueId value, LalinValue.ValueExpr expr, LalinValue.AlgebraProof proof) unique
        | ValueRangeFact(LalinValue.ValueRange range) unique
        | ValueNoWrapFact(LalinCode.CodeValueId value, LalinCode.CodeIntSemantics sem, LalinValue.AlgebraProof proof) unique
        | ValueFloatModeFact(LalinCode.CodeValueId value, LalinCode.CodeFloatMode mode, LalinValue.AlgebraProof proof) unique

    ValueFactSet = (LalinCode.CodeModuleId module,
                    LalinValue.ValueFact* values,
                    LalinValue.ReductionFact* reductions,
                    LalinValue.ClosedFormFact* closed_forms) unique
}
```

Decisions:

- arithmetic-series closed forms are `ClosedFormFact`, not Kernel-local logic.
- affine expressions are general value facts, not loop recognizer internals.
- no-wrap/fast-math must cite proof facts.

---

## 8. LalinMem additions

LalinMem already exists. The missing concrete decisions are lease grants, object
relations, and backend-consumable metadata.

Required additions:

```asdl
MemLeaseId = (string text) unique

MemLeaseGrant = (LalinMem.MemLeaseId id,
                 LalinFlow.FlowDomain? domain,
                 LalinCode.CodeValueId lease_value,
                 LalinCode.CodeValueId? handle,
                 LalinMem.MemObjectId object,
                 LalinMem.MemBase base,
                 LalinMem.MemObjectExtent extent,
                 LalinMem.MemObjectStride stride,
                 LalinMem.MemProof proof) unique

MemObjectRelation = MemObjectsSameLen(LalinMem.MemObjectId a, LalinMem.MemObjectId b, LalinMem.MemProof proof) unique
    | MemObjectWindowOf(LalinMem.MemObjectId window, LalinMem.MemObjectId parent, LalinCode.CodeValueId start, LalinCode.CodeValueId len, LalinMem.MemProof proof) unique
    | MemObjectSliceOf(LalinMem.MemObjectId slice, LalinMem.MemObjectId parent, LalinCode.CodeValueId start, LalinCode.CodeValueId len, LalinMem.MemProof proof) unique
    | MemObjectSameStore(LalinMem.MemObjectId a, LalinMem.MemObjectId b, LalinMem.MemProof proof) unique

MemBackendAccessInfo = (LalinMem.MemAccessId access,
                        LalinMem.MemTrap trap,
                        LalinMem.MemAlignment alignment,
                        LalinMem.MemBounds bounds,
                        number? deref_bytes,
                        bool movable,
                        LalinMem.MemProof* proofs) unique
```

Decision: `MemBackendAccessInfo` is the canonical bridge from Mem facts to Back
load/store metadata. Back lowering consumes this, not raw `MemAccessFact` alone.

Decision: raw pointer params produce unknown extent unless a contract, view,
lease, or trusted boundary fact creates an object.

---

## 9. LalinEffect ASDL

Effects are not optional. Without them, real programs cannot move, vectorize, or
protect leases correctly.

```asdl
module LalinEffect {
    EffectId = (string text) unique

    EffectObject = EffectObjectMem(LalinMem.MemObjectId object) unique
        | EffectObjectStore(LalinCode.CodeValueId store_value) unique
        | EffectObjectUnknown(string reason) unique

    OpEffect = EffectRead(LalinEffect.EffectObject object, LalinMem.MemProof? proof) unique
        | EffectWrite(LalinEffect.EffectObject object, LalinMem.MemProof? proof) unique
        | EffectInvalidate(LalinEffect.EffectObject object, string reason) unique
        | EffectRetain(LalinCode.CodeValueId value, string reason) unique
        | EffectNoEscape(LalinCode.CodeValueId value, string reason) unique
        | EffectMayTrap(string reason) unique
        | EffectNoTrap(string reason) unique
        | EffectVolatile(string reason) unique
        | EffectAtomic(string ordering) unique
        | EffectUnknown(string reason) unique

    CallSummary = (LalinCode.CodeFuncId? callee,
                   string? extern_name,
                   LalinEffect.OpEffect* effects) unique

    InstEffect = (LalinCode.CodeInstId inst, LalinEffect.OpEffect* effects) unique
    TermEffect = (LalinCode.CodeBlockId block, LalinEffect.OpEffect* effects) unique

    EffectFactSet = (LalinCode.CodeModuleId module,
                     LalinEffect.CallSummary* calls,
                     LalinEffect.InstEffect* insts,
                     LalinEffect.TermEffect* terms) unique
}
```

Decisions:

- `readonly`, `writeonly`, `noescape`, `invalidate` lower into Effect facts.
- Lease checking consumes Effect facts.
- Calls with unknown effects block motion/vectorization unless isolated outside
  the fragment.

---

## 10. LalinKernel ASDL rewrite

Kernel no longer contains schedules. Kernel no longer implies function
replacement.

```asdl
module LalinKernel {
    KernelId = (string text) unique

    KernelSubject = KernelSubjectFunction(LalinCode.CodeFuncId func) unique
        | KernelSubjectLoop(LalinGraph.GraphLoopId loop) unique
        | KernelSubjectDomain(LalinFlow.FlowDomain domain) unique
        | KernelSubjectFragment(LalinCode.CodeFuncId func, LalinCode.CodeBlockId entry, LalinCode.CodeBlockId exit) unique

    KernelDomain = KernelDomainFlow(LalinFlow.FlowDomain domain,
                                    LalinFlow.FlowTripCount trip_count,
                                    LalinCode.CodeValueId? counter) unique

    KernelLane = (LalinKernel.KernelLaneId id,
                    LalinMem.MemObjectId object,
                    LalinMem.MemAccessId* accesses,
                    LalinMem.MemBase base,
                    LalinCode.CodeType elem_ty,
                    LalinMem.MemAccessPattern pattern,
                    LalinMem.MemBackendAccessInfo* backend_info) unique

    KernelExpr = KernelExprValue(LalinCode.CodeValueId value) unique
        | KernelExprAlgebra(LalinValue.ValueExpr expr) unique
        | KernelExprLaneLoad(LalinKernel.KernelLane lane, LalinValue.ValueExpr index) unique
        | KernelExprKernelValue(LalinKernel.KernelValueId value) unique

    KernelBinding = (LalinKernel.KernelValueId id, LalinCode.CodeType ty, LalinKernel.KernelExpr expr) unique

    KernelEffect = KernelEffectStore(LalinKernel.KernelLane dst, LalinValue.ValueExpr index, LalinKernel.KernelExpr value) unique
        | KernelEffectScan(LalinKernel.KernelLane dst, LalinValue.ValueExpr index, LalinValue.ReductionFact reduction, LalinStencil.StencilScanMode mode) unique
        | KernelEffectPartition(LalinKernel.KernelLane dst, LalinKernel.KernelExpr src, LalinStencil.StencilPredicate pred, LalinStencil.StencilPartitionSemantics semantics) unique
        | KernelEffectCopy(LalinKernel.KernelLane dst, LalinKernel.KernelExpr src, LalinStencil.StencilCopySemantics semantics) unique
        | KernelEffectFold(LalinValue.ReductionFact reduction) unique
        | KernelEffectCall(LalinEffect.CallSummary call) unique

    KernelResult = KernelResultVoid
        | KernelResultValue(LalinKernel.KernelExpr expr) unique
        | KernelResultFind(LalinKernel.KernelExpr src, LalinStencil.StencilPredicate pred, LalinValue.ValueExpr not_found) unique
        | KernelResultReduction(LalinValue.ReductionFact reduction) unique
        | KernelResultClosedForm(LalinValue.ClosedFormFact closed_form) unique
        | KernelResultOriginalControl(string reason) unique

    KernelEquivalence = KernelEquivalenceProof(LalinKernel.KernelProof* proofs) unique
        | KernelEquivalenceRejected(LalinKernel.KernelReject* rejects) unique

    KernelBody = (LalinKernel.KernelDomain domain,
                  LalinKernel.KernelLane* lanes,
                  LalinKernel.KernelBinding* bindings,
                  LalinKernel.KernelEffect* effects,
                  LalinKernel.KernelResult result,
                  LalinKernel.KernelEquivalence equivalence) unique

    KernelPlan = KernelNoPlan(LalinKernel.KernelSubject subject, LalinKernel.KernelReject* rejects) unique
        | KernelPlanned(LalinKernel.KernelId id, LalinKernel.KernelSubject subject, LalinKernel.KernelBody body) unique

    KernelModulePlan = (LalinCode.CodeModuleId module,
                        LalinFlow.FlowFactSet flow,
                        LalinValue.ValueFactSet value,
                        LalinMem.MemSemanticFactSet mem,
                        LalinEffect.EffectFactSet effect,
                        LalinKernel.KernelPlan* plans) unique
}
```

Decisions:

- `KernelEffectScan`, `KernelEffectPartition`, `KernelEffectCopy`, and
  `KernelResultFind` are first-class array skeleton semantics. They are not
  encoded as callback names or stencil strings; stencil descriptor planning is
  one backend consumer of those meanings.
- The counted-loop kernel planner rewrites ordinary prefix-scan and primary
  index copy loops into `KernelEffectScan` and `KernelEffectCopy`. That keeps
  copy and scan ownership in the kernel semantic layer, not in a backend store
  recognizer. Copy uses `StencilCopyNoOverlap` when dependence facts prove
  independence and `StencilCopyMemMove` when source/destination overlap remains
  unresolved.
- Early-exit primary-index searches are `KernelResultFind`.
- Stable partition is represented as a function-level two-pass semantic
  fragment with `KernelEffectPartition`, because it is not a single-loop store.
- `KernelResultClosedForm` cites `LalinValue.ClosedFormFact`.
- Kernel has equivalence proof/rejects, not only safety.
- Kernel plans are many-per-module and many-per-function.
- Kernel plan selection is a Llisle relation. `code_kernel_plan` builds the
  candidate facts and final LalinKernel values; `code_kernel_plan_rules` owns
  no-plan rejection priority, result priority, and the proof bit for
  closed-form plans whose Flow trip count is unknown.
- Stencil descriptor planning is split into Llisle plan and selector relations.
  `plan_store_stencil` / `plan_reduce_stencil` own readiness gates over planned
  kernels, counted loops, return shape, single-store or reduction shape, and
  enriched class availability. `select_store_stencil` / `select_reduce_stencil`
  own concrete stencil vocabulary, op, provider info, and argument ordering.
  Stencil constructors declare their `info`/`args`/`op`/`selection` product
  contracts in Llisle, so the stencil vocabulary is inspectable metadata rather
  than an undocumented Lua table convention.

---

## 11. LalinSchedule ASDL

Schedule is target-specific and separate.

```asdl
module LalinSchedule {
    ScheduleId = (string text) unique

    ScheduleTarget = (LalinBack.BackTargetModel target) unique

    LaneShape = LaneScalar
        | LaneVector(LalinCode.CodeType elem_ty, number lanes) unique

    TailPlan = TailNone
        | TailScalar
        | TailMasked
        | TailPeel(number elems) unique

    ScheduleKind = ScheduleScalarIndex
        | ScheduleScalarPointer
        | ScheduleVector(LalinSchedule.LaneShape lanes, number unroll, number interleave, LalinSchedule.TailPlan tail) unique
        | ScheduleClosedForm

    ScheduleProof = ScheduleProofTarget(string reason) unique
        | ScheduleProofMemory(LalinMem.MemProof proof) unique
        | ScheduleProofAlgebra(LalinValue.AlgebraProof proof) unique
        | ScheduleProofProfit(string reason) unique

    ScheduleReject = ScheduleRejectTarget(string reason) unique
        | ScheduleRejectMemory(string reason) unique
        | ScheduleRejectAlgebra(string reason) unique
        | ScheduleRejectProfit(string reason) unique

    KernelSchedule = ScheduleNoPlan(LalinKernel.KernelId kernel, LalinSchedule.ScheduleReject* rejects) unique
        | SchedulePlanned(LalinSchedule.ScheduleId id,
                          LalinKernel.KernelId kernel,
                          LalinSchedule.ScheduleKind kind,
                          LalinSchedule.ScheduleProof* proofs,
                          LalinSchedule.ScheduleReject* rejected_alternatives) unique

    ScheduleModulePlan = (LalinCode.CodeModuleId module,
                          LalinSchedule.ScheduleTarget target,
                          LalinSchedule.KernelSchedule* schedules) unique
}
```

Decisions:

- target model is part of schedule input and schedule output.
- unroll/interleave/tail are explicit choices with proofs/rejects.
- profitability is a proof/reject fact, even when primitive.
- Schedule selection is a Llisle relation. `code_schedule_plan` builds schedule
  candidates and final LalinSchedule values; `code_schedule_plan_rules` owns
  vector-first priority, scalar/closed-form fallback, rejected vector
  alternatives, and no-plan rejection.

---

## 12. LalinLower ASDL replacement

This replaces coarse `LowerFuncCode` / `LowerFuncKernel`.

```asdl
module LalinLower {
    LowerFragmentId = (string text) unique

    LowerTarget = LowerTargetBack
        | LowerTargetC

    LowerCover = LowerCoverFunction(LalinCode.CodeFuncId func) unique
        | LowerCoverLoop(LalinGraph.GraphLoopId loop) unique
        | LowerCoverBlock(LalinCode.CodeFuncId func, LalinCode.CodeBlockId block) unique
        | LowerCoverBlockRange(LalinCode.CodeFuncId func, LalinCode.CodeBlockId entry, LalinCode.CodeBlockId exit) unique

    LowerStrategy = LowerStrategyCode(string reason) unique
        | LowerStrategyKernel(LalinKernel.KernelId kernel, LalinSchedule.ScheduleId schedule) unique
        | LowerStrategyClosedForm(LalinKernel.KernelId kernel, LalinValue.ClosedFormFact fact) unique

    LowerFragment = (LalinLower.LowerFragmentId id,
                     LalinLower.LowerCover cover,
                     LalinLower.LowerStrategy strategy,
                     LalinLower.LowerProof* proofs,
                     LalinLower.LowerIssue* issues) unique

    LowerFuncPlan = (LalinCode.CodeFuncId func,
                     LalinLower.LowerFragment* fragments) unique

    LowerProof = LowerProofCoverage(string reason) unique
        | LowerProofKernel(LalinKernel.KernelId kernel, string reason) unique
        | LowerProofSchedule(LalinSchedule.ScheduleId schedule, string reason) unique
        | LowerProofFallback(string reason) unique

    LowerIssue = LowerIssueOverlap(LalinLower.LowerFragmentId a, LalinLower.LowerFragmentId b) unique
        | LowerIssueGap(LalinCode.CodeFuncId func, string reason) unique
        | LowerIssueFallback(LalinLower.LowerCover cover, string reason) unique

    LowerModule = (LalinCode.CodeModuleId module,
                   LalinLower.LowerTarget target,
                   LalinKernel.KernelModulePlan kernels,
                   LalinSchedule.ScheduleModulePlan schedules,
                   LalinLower.LowerFuncPlan* funcs,
                   LalinLower.LowerIssue* issues) unique
}
```

Coverage rules:

- Every function has a `LowerFuncPlan`.
- Fragments must not overlap unless one is a parent cover marked as delegated.
- Every Code block is covered by exactly one executable strategy.
- A loop kernel fragment covers its loop body; preheader/exit blocks remain Code
  fragments unless the whole function is covered.

Decision: `LowerStrategyCode` still consumes facts. It is not "unoptimized".

---

## 13. Executable backend boundary rules

Executable backend ASDL is not a place to park semantic facts that active
backends cannot consume.

### 13.1 Executable metadata

The backend-consumed metadata set is deliberately finite:

```text
memory:
  notrap
  aligned / alignment bytes when the selected materializer consumes it
  can_move
  readonly

integer:
  wrap / no-signed-wrap / no-unsigned-wrap / exact when representable

float:
  strict / reassoc / fast where backend flags can implement it

target:
  vector lane shape used by emitted commands
```

If a semantic fact is not in this executable set, it must be consumed before the
backend boundary. For example, alias/dependence facts may choose a schedule,
permit motion, or reject a kernel; they do not become no-op backend commands.

### 13.2 Alias facts are not decorative metadata

Decision: alias facts only cross a backend boundary when the selected
materializer consumes them as real executable metadata. Otherwise they remain in
Mem/Lower/Schedule where they shape decisions.

This prevents decorative ASDL without adding report machinery or wire-level
failure paths.

---

## 14. Lowering algorithm

Executable lowering walks the Lower plan, not raw Code alone.

Pseudo-code:

```lua
for func_plan in lower.funcs do
  begin BackFunc
  for fragment in ordered_fragments(func_plan) do
    if fragment.strategy == LowerStrategyCode then
      emit_code_fragment(fragment.cover, facts)
    elseif fragment.strategy == LowerStrategyKernel then
      emit_kernel_fragment(kernel, schedule, facts)
    elseif fragment.strategy == LowerStrategyClosedForm then
      emit_closed_form_return_or_value(kernel, closed_form, facts)
    end
  end
  end BackFunc
end
```

`emit_code_fragment` takes facts:

```lua
emit_code_fragment(code, graph, flow, value, mem, effect, cover)
```

It must query:

- `MemBackendAccessInfo` for every load/store
- `ValueFactSet` for int/float semantics and simple expression lowering
- `EffectFactSet` before moving operations across calls/blocks
- `FlowFactSet` for branch/loop lowering hints

Decision: ordinary Code lowering is fact-aware by construction.

---

## 15. What is forbidden after this rewrite

1. `replacement_funcs`-style bridges.
2. Whole-function-only kernel architecture.
3. Hidden view decomposition tables in Back lowering.
4. Semantic-only facts in executable Back.
5. Planner-local contract shortcuts that bypass normalized Mem facts.
6. Kernel-local algebra recognizers that do not emit `LalinValue` facts.
7. Target assumptions not represented in Schedule facts.
8. Fallback without `LowerIssueFallback` or equivalent diagnostic.
9. Unknown alias/dependence silently treated as safe.
10. Source Tree recursion in C/native backends.

---

## 16. Migration order

This is the concrete implementation order.

### Step 1: Add Graph phase

- Add `schema/graph.lua`.
- Implement `code_graph.lua`.
- Port Flow/Mem to use Graph IDs where relevant.

### Step 2: Make views explicit in CodeToBack

- Eliminate hidden backend view tables.
- Ensure view data/len/stride are Code values or explicit Code instructions.
- Update tests for view lowering.

### Step 3: Remove executable no-op facts

- Delete unsupported semantic-only Back commands.
- Keep alias/dependence facts in Mem/Lower/Schedule until the backend has a real
  consumer.
- The wire encoder should only see executable commands.

### Step 4: Add Value/Algebra phase

- Add `schema/value.lua`.
- Move closed-form reduction facts out of Kernel planner.
- Kernel consumes `ClosedFormFact`.

### Step 5: Add Effect phase

- Add `schema/effect.lua`.
- Normalize readonly/writeonly/noescape/invalidate/call effects.
- Lease checks consume Effect facts.

### Step 6: Rewrite Kernel ASDL without schedule

- Kernel plans many subjects per module.
- Kernel result closed forms cite Value facts.
- Kernel equivalence proof is explicit.

### Step 7: Add Schedule phase

- Add `schema/schedule.lua`.
- Move target vector/unroll/tail decisions out of Kernel.
- Schedule rejection reasons are facts.

### Step 8: Replace Lower ASDL with fragment coverage

- Implement coverage validator.
- First implementation may produce only full-function Code fragments plus known
  loop Kernel fragments.
- Mixed lowering becomes legal immediately.

### Step 9: Make Code lowering fact-aware

- Ordinary load/store uses `MemBackendAccessInfo`.
- Ordinary int/float ops use `ValueFactSet` semantics.
- Calls use `EffectFactSet`.

### Step 10: Convert to PVM phases

- Register each stage as a PVM phase.
- Add reuse visibility for phase outputs. Do not add a separate backend report
  layer unless a real consumer needs it.

---

## 17. Success tests

The rewrite is not complete until these are true.

1. A function with two loops can lower one loop as vector Kernel and the other
   as Code.
2. A function with prologue/epilogue around a loop can still lower the loop as
   Kernel.
3. A load in ordinary Code lowering receives nontrap/alignment/movable metadata
   from Mem facts.
4. A closed-form reduction is represented as `LalinValue.ClosedFormFact` before
   Kernel sees it.
5. Removing a bounds contract changes the Mem facts and causes the relevant
   schedule/lowering choice to be rejected or fall back explicitly.
6. A view lowered to Back does not rely on hidden Lua side tables for data/len/
   stride.
7. `back_encode` only receives executable Back commands; unsupported semantic
   facts are absent from Back.
8. PVM reuse visibility shows which fact phase changed after editing a loop
   bound, a contract, or a store effect.

---

## 18. Final shape

The architecture is:

```text
LalinCode is meaning.
Graph indexes meaning.
Flow describes control domains.
Value describes algebra.
Mem describes objects and access.
Effect describes calls and invalidation.
Kernel describes semantic subprograms.
Schedule describes target execution choices.
Lower covers functions with compositional strategies.
Back emits machine commands with only consumable metadata.
Unsupported semantic facts never enter executable Back.
```

That is the tree. Hidden choices are bugs.
