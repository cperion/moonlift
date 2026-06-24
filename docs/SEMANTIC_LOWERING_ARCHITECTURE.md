# Moonlift Semantic Lowering Architecture

Status: design decision. This document is intentionally concrete. It names the
ASDL modules, the phase tree, the lowering contracts, the metadata that may cross
the backend boundary, and the things we explicitly will not do.

The previous tower proved the direction but left too many choices implicit. This
version removes those hidden choices.

---

## 0. The decision in one page

Moonlift native performance will not be built from recognizers.

The compiler will lower through this fixed tree:

```text
MoonTree
  -> MoonCode
  -> MoonGraph
  -> MoonFlow
  -> MoonValue
  -> MoonMem
  -> MoonEffect
  -> MoonKernel
  -> MoonSchedule
  -> MoonLower
  -> MoonBack
  -> wire bytes
  -> Rust/Cranelift
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
Kernel. Ordinary loads/stores/ops/calls in Code -> Back consume the same facts.
If a fact cannot be consumed by executable Back, it stays in the planning layers
and does not exist in Back.

---

## 1. Non-negotiable rules

1. **MoonCode is the executable meaning boundary.** Backends do not recurse into
   MoonTree for semantics.
2. **No hidden compiler state as architecture.** Lua maps may be caches, but any
   meaning needed by another phase must be an ASDL value.
3. **No whole-function performance cliff.** Whole-function kernel lowering is a
   special case of fragment lowering, not the model.
4. **No decorative backend ASDL.** A Back fact is executable and consumed by
   Rust/Cranelift, or it does not exist in Back.
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
lua/moonlift/schema/code.lua       existing; canonical Code, extended for leases/views
lua/moonlift/schema/graph.lua      new; Code graph indices
lua/moonlift/schema/flow.lua       existing; loop/control facts, tightened
lua/moonlift/schema/value.lua      new; symbolic values, affine/reduction/algebra facts
lua/moonlift/schema/mem.lua        existing; memory objects/access/safety/lease facts
lua/moonlift/schema/effect.lua     new; calls, invalidation, noescape, trap/effect summaries
lua/moonlift/schema/kernel.lua     existing; semantic kernels only, no schedules
lua/moonlift/schema/schedule.lua   new; target-specific schedules/profitability
lua/moonlift/schema/lower.lua      replace; compositional function fragment plan
lua/moonlift/schema/back.lua       existing; executable Back only, no decorative facts
```

Implementation modules mirror the schema tree:

```text
lua/moonlift/tree_to_code.lua
lua/moonlift/code_graph.lua
lua/moonlift/code_flow_facts.lua
lua/moonlift/code_value_facts.lua
lua/moonlift/code_mem_facts.lua
lua/moonlift/code_effect_facts.lua
lua/moonlift/code_kernel_plan.lua
lua/moonlift/code_kernel_plan_rules.lua
lua/moonlift/code_schedule_plan.lua
lua/moonlift/code_schedule_plan_rules.lua
lua/moonlift/code_lower_plan.lua
lua/moonlift/lower_to_back.lua
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

## 4. MoonCode commitments

MoonCode remains the canonical executable IR. It must explicitly represent the
values that later phases need.

### 4.1 Views are explicit Code values

Backend lowering must not reconstruct views from hidden Lua state.

Add or standardize these Code operations if not already present in this exact
meaning:

```asdl
CodeInst = ...
    | CodeInstViewMake(MoonCode.CodeValueId dst,
                       MoonCode.CodeType elem_ty,
                       MoonCode.CodeValueId data,
                       MoonCode.CodeValueId len,
                       MoonCode.CodeValueId stride,
                       MoonCode.CodeOrigin origin) unique
    | CodeInstViewData(MoonCode.CodeValueId dst, MoonCode.CodeValueId view, MoonCode.CodeOrigin origin) unique
    | CodeInstViewLen(MoonCode.CodeValueId dst, MoonCode.CodeValueId view, MoonCode.CodeOrigin origin) unique
    | CodeInstViewStride(MoonCode.CodeValueId dst, MoonCode.CodeValueId view, MoonCode.CodeOrigin origin) unique
```

A view may still lower to multiple machine values, but the decomposition is Code,
not a backend side table.

### 4.2 Leases are Code types until checked

Lease-ness is not a machine representation, but it is Code meaning.

```asdl
CodeType = ...
    | CodeTyLease(MoonCode.CodeType base, MoonType.Type source_ty) unique
```

Lowering may erase `CodeTyLease(base)` to `base` only after `MoonEffect` proves
no escape and no invalidating same-store operation crosses the live range.

### 4.3 Handles remain opaque Code values

```asdl
CodeType = ...
    | CodeTyHandle(MoonCode.CodeType repr, MoonType.Type source_ty) unique
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

## 5. MoonGraph ASDL

`MoonGraph` is the shared index over Code. It is deliberately non-semantic.

```asdl
module MoonGraph {
    GraphBlockId = (MoonCode.CodeFuncId func, MoonCode.CodeBlockId block) unique
    GraphInstRef = (MoonCode.CodeFuncId func, MoonCode.CodeBlockId block, MoonCode.CodeInstId inst) unique
    GraphEdge = (MoonGraph.GraphBlockId from, MoonGraph.GraphBlockId to, string kind) unique

    GraphUse = (MoonCode.CodeValueId value, MoonGraph.GraphInstRef? inst, MoonGraph.GraphBlockId? term_block, string role) unique
    GraphDef = (MoonCode.CodeValueId value, MoonGraph.GraphInstRef? inst, MoonCode.CodeParamId? param) unique

    GraphLoopId = (string text) unique
    GraphLoop = (MoonGraph.GraphLoopId id,
                 MoonCode.CodeFuncId func,
                 MoonGraph.GraphBlockId header,
                 MoonGraph.GraphBlockId* body,
                 MoonGraph.GraphEdge* latches,
                 MoonGraph.GraphEdge* exits) unique

    CodeFuncGraph = (MoonCode.CodeFuncId func,
                     MoonGraph.GraphEdge* edges,
                     MoonGraph.GraphDef* defs,
                     MoonGraph.GraphUse* uses,
                     MoonGraph.GraphLoop* loops) unique

    CodeGraph = (MoonCode.CodeModuleId module, MoonGraph.CodeFuncGraph* funcs) unique
}
```

Decision: dominance/postdominance may be added later as facts, but the first
required graph vocabulary is edges, defs, uses, loops.

---

## 6. MoonFlow ASDL tightening

MoonFlow owns control domains. Existing loop facts remain, but the subject type
must align with Graph loops.

Required additions/standardization:

```asdl
FlowDomainId = (string text) unique

FlowDomain = FlowDomainLoop(MoonGraph.GraphLoopId loop) unique
    | FlowDomainBlockRange(MoonCode.CodeFuncId func, MoonCode.CodeBlockId entry, MoonCode.CodeBlockId exit) unique
    | FlowDomainFunction(MoonCode.CodeFuncId func) unique

FlowTripCount = FlowTripCountExact(MoonCode.CodeValueId count, MoonMem.MemProof? proof) unique
    | FlowTripCountNonNegative(MoonCode.CodeValueId count, MoonMem.MemProof? proof) unique
    | FlowTripCountUnknown(string reason) unique
```

Decision: exact trip count is a fact. Lowering may not silently treat
non-negative as exact.

---

## 7. MoonValue / MoonAlgebra ASDL

This is the largest missing layer. It removes algebra from Kernel recognizers.

```asdl
module MoonValue {
    ValueFactId = (string text) unique
    AlgebraFactId = (string text) unique

    ValueExpr = ValueExprConst(MoonCode.CodeConst const) unique
        | ValueExprValue(MoonCode.CodeValueId value) unique
        | ValueExprAdd(MoonValue.ValueExpr a, MoonValue.ValueExpr b, MoonCode.CodeType ty, MoonCode.CodeIntSemantics? sem) unique
        | ValueExprSub(MoonValue.ValueExpr a, MoonValue.ValueExpr b, MoonCode.CodeType ty, MoonCode.CodeIntSemantics? sem) unique
        | ValueExprMul(MoonValue.ValueExpr a, MoonValue.ValueExpr b, MoonCode.CodeType ty, MoonCode.CodeIntSemantics? sem) unique
        | ValueExprDiv(MoonValue.ValueExpr a, MoonValue.ValueExpr b, MoonCode.CodeType ty, MoonCode.CodeIntSemantics? sem) unique
        | ValueExprSelect(MoonValue.ValueExpr cond, MoonValue.ValueExpr t, MoonValue.ValueExpr f) unique
        | ValueExprCmp(MoonCore.CmpOp op, MoonCode.CodeType ty, MoonValue.ValueExpr a, MoonValue.ValueExpr b) unique
        | ValueExprAffine(MoonValue.AffineExpr affine) unique

    AffineTerm = (MoonCode.CodeValueId value, string coeff) unique
    AffineExpr = (string constant, MoonValue.AffineTerm* terms, MoonCode.CodeType ty, MoonCode.CodeIntSemantics? sem) unique

    ValueRange = ValueRangeUnknown(string reason) unique
        | ValueRangeInt(MoonCode.CodeValueId value, MoonValue.ValueExpr lo, MoonValue.ValueExpr hi, bool inclusive_hi, MoonValue.AlgebraProof proof) unique

    ReductionKind = ReductionAdd | ReductionMul | ReductionMin | ReductionMax | ReductionAnd | ReductionOr | ReductionXor

    ReductionFact = (MoonValue.AlgebraFactId id,
                     MoonFlow.FlowDomain domain,
                     MoonCode.CodeValueId accumulator,
                     MoonValue.ReductionKind kind,
                     MoonValue.ValueExpr init,
                     MoonValue.ValueExpr contribution,
                     MoonCode.CodeType ty,
                     MoonCode.CodeIntSemantics? int_semantics,
                     MoonCode.CodeFloatMode? float_mode,
                     MoonValue.AlgebraProof proof) unique

    ClosedFormFact = (MoonValue.AlgebraFactId id,
                      MoonValue.ReductionFact reduction,
                      MoonValue.ValueExpr expr,
                      MoonValue.AlgebraProof proof) unique

    AlgebraProof = AlgebraProofFlow(MoonFlow.FlowDomain domain, string reason) unique
        | AlgebraProofNoWrap(MoonCode.CodeValueId value, string reason) unique
        | AlgebraProofIdentity(string reason) unique
        | AlgebraProofReduction(MoonValue.ReductionFact fact, string reason) unique
        | AlgebraProofComposite(MoonValue.AlgebraProof* proofs, string reason) unique

    ValueFact = ValueExprFact(MoonCode.CodeValueId value, MoonValue.ValueExpr expr, MoonValue.AlgebraProof proof) unique
        | ValueRangeFact(MoonValue.ValueRange range) unique
        | ValueNoWrapFact(MoonCode.CodeValueId value, MoonCode.CodeIntSemantics sem, MoonValue.AlgebraProof proof) unique
        | ValueFloatModeFact(MoonCode.CodeValueId value, MoonCode.CodeFloatMode mode, MoonValue.AlgebraProof proof) unique

    ValueFactSet = (MoonCode.CodeModuleId module,
                    MoonValue.ValueFact* values,
                    MoonValue.ReductionFact* reductions,
                    MoonValue.ClosedFormFact* closed_forms) unique
}
```

Decisions:

- arithmetic-series closed forms are `ClosedFormFact`, not Kernel-local logic.
- affine expressions are general value facts, not loop recognizer internals.
- no-wrap/fast-math must cite proof facts.

---

## 8. MoonMem additions

MoonMem already exists. The missing concrete decisions are lease grants, object
relations, and backend-consumable metadata.

Required additions:

```asdl
MemLeaseId = (string text) unique

MemLeaseGrant = (MoonMem.MemLeaseId id,
                 MoonFlow.FlowDomain? domain,
                 MoonCode.CodeValueId lease_value,
                 MoonCode.CodeValueId? handle,
                 MoonMem.MemObjectId object,
                 MoonMem.MemBase base,
                 MoonMem.MemObjectExtent extent,
                 MoonMem.MemObjectStride stride,
                 MoonMem.MemProof proof) unique

MemObjectRelation = MemObjectsSameLen(MoonMem.MemObjectId a, MoonMem.MemObjectId b, MoonMem.MemProof proof) unique
    | MemObjectWindowOf(MoonMem.MemObjectId window, MoonMem.MemObjectId parent, MoonCode.CodeValueId start, MoonCode.CodeValueId len, MoonMem.MemProof proof) unique
    | MemObjectSliceOf(MoonMem.MemObjectId slice, MoonMem.MemObjectId parent, MoonCode.CodeValueId start, MoonCode.CodeValueId len, MoonMem.MemProof proof) unique
    | MemObjectSameStore(MoonMem.MemObjectId a, MoonMem.MemObjectId b, MoonMem.MemProof proof) unique

MemBackendAccessInfo = (MoonMem.MemAccessId access,
                        MoonMem.MemTrap trap,
                        MoonMem.MemAlignment alignment,
                        MoonMem.MemBounds bounds,
                        number? deref_bytes,
                        bool movable,
                        MoonMem.MemProof* proofs) unique
```

Decision: `MemBackendAccessInfo` is the canonical bridge from Mem facts to Back
load/store metadata. Back lowering consumes this, not raw `MemAccessFact` alone.

Decision: raw pointer params produce unknown extent unless a contract, view,
lease, or trusted boundary fact creates an object.

---

## 9. MoonEffect ASDL

Effects are not optional. Without them, real programs cannot move, vectorize, or
protect leases correctly.

```asdl
module MoonEffect {
    EffectId = (string text) unique

    EffectObject = EffectObjectMem(MoonMem.MemObjectId object) unique
        | EffectObjectStore(MoonCode.CodeValueId store_value) unique
        | EffectObjectUnknown(string reason) unique

    OpEffect = EffectRead(MoonEffect.EffectObject object, MoonMem.MemProof? proof) unique
        | EffectWrite(MoonEffect.EffectObject object, MoonMem.MemProof? proof) unique
        | EffectInvalidate(MoonEffect.EffectObject object, string reason) unique
        | EffectRetain(MoonCode.CodeValueId value, string reason) unique
        | EffectNoEscape(MoonCode.CodeValueId value, string reason) unique
        | EffectMayTrap(string reason) unique
        | EffectNoTrap(string reason) unique
        | EffectVolatile(string reason) unique
        | EffectAtomic(string ordering) unique
        | EffectUnknown(string reason) unique

    CallSummary = (MoonCode.CodeFuncId? callee,
                   string? extern_name,
                   MoonEffect.OpEffect* effects) unique

    InstEffect = (MoonCode.CodeInstId inst, MoonEffect.OpEffect* effects) unique
    TermEffect = (MoonCode.CodeBlockId block, MoonEffect.OpEffect* effects) unique

    EffectFactSet = (MoonCode.CodeModuleId module,
                     MoonEffect.CallSummary* calls,
                     MoonEffect.InstEffect* insts,
                     MoonEffect.TermEffect* terms) unique
}
```

Decisions:

- `readonly`, `writeonly`, `noescape`, `invalidate` lower into Effect facts.
- Lease checking consumes Effect facts.
- Calls with unknown effects block motion/vectorization unless isolated outside
  the fragment.

---

## 10. MoonKernel ASDL rewrite

Kernel no longer contains schedules. Kernel no longer implies function
replacement.

```asdl
module MoonKernel {
    KernelId = (string text) unique

    KernelSubject = KernelSubjectFunction(MoonCode.CodeFuncId func) unique
        | KernelSubjectLoop(MoonGraph.GraphLoopId loop) unique
        | KernelSubjectDomain(MoonFlow.FlowDomain domain) unique
        | KernelSubjectFragment(MoonCode.CodeFuncId func, MoonCode.CodeBlockId entry, MoonCode.CodeBlockId exit) unique

    KernelDomain = KernelDomainFlow(MoonFlow.FlowDomain domain,
                                    MoonFlow.FlowTripCount trip_count,
                                    MoonCode.CodeValueId? counter) unique

    KernelStream = (MoonKernel.KernelStreamId id,
                    MoonMem.MemObjectId object,
                    MoonMem.MemAccessId* accesses,
                    MoonMem.MemBase base,
                    MoonCode.CodeType elem_ty,
                    MoonMem.MemAccessPattern pattern,
                    MoonMem.MemBackendAccessInfo* backend_info) unique

    KernelExpr = KernelExprValue(MoonCode.CodeValueId value) unique
        | KernelExprAlgebra(MoonValue.ValueExpr expr) unique
        | KernelExprLoad(MoonKernel.KernelStream stream, MoonValue.ValueExpr index) unique
        | KernelExprKernelValue(MoonKernel.KernelValueId value) unique

    KernelBinding = (MoonKernel.KernelValueId id, MoonCode.CodeType ty, MoonKernel.KernelExpr expr) unique

    KernelEffect = KernelEffectStore(MoonKernel.KernelStream dst, MoonValue.ValueExpr index, MoonKernel.KernelExpr value) unique
        | KernelEffectScan(MoonKernel.KernelStream dst, MoonValue.ValueExpr index, MoonValue.ReductionFact reduction, MoonStencil.StencilScanMode mode) unique
        | KernelEffectPartition(MoonKernel.KernelStream dst, MoonKernel.KernelExpr src, MoonStencil.StencilPredicate pred, MoonStencil.StencilPartitionSemantics semantics) unique
        | KernelEffectCopy(MoonKernel.KernelStream dst, MoonKernel.KernelExpr src, MoonStencil.StencilCopySemantics semantics) unique
        | KernelEffectFold(MoonValue.ReductionFact reduction) unique
        | KernelEffectCall(MoonEffect.CallSummary call) unique

    KernelResult = KernelResultVoid
        | KernelResultValue(MoonKernel.KernelExpr expr) unique
        | KernelResultFind(MoonKernel.KernelExpr src, MoonStencil.StencilPredicate pred, MoonValue.ValueExpr not_found) unique
        | KernelResultReduction(MoonValue.ReductionFact reduction) unique
        | KernelResultClosedForm(MoonValue.ClosedFormFact closed_form) unique
        | KernelResultOriginalControl(string reason) unique

    KernelEquivalence = KernelEquivalenceProof(MoonKernel.KernelProof* proofs) unique
        | KernelEquivalenceRejected(MoonKernel.KernelReject* rejects) unique

    KernelBody = (MoonKernel.KernelDomain domain,
                  MoonKernel.KernelStream* streams,
                  MoonKernel.KernelBinding* bindings,
                  MoonKernel.KernelEffect* effects,
                  MoonKernel.KernelResult result,
                  MoonKernel.KernelEquivalence equivalence) unique

    KernelPlan = KernelNoPlan(MoonKernel.KernelSubject subject, MoonKernel.KernelReject* rejects) unique
        | KernelPlanned(MoonKernel.KernelId id, MoonKernel.KernelSubject subject, MoonKernel.KernelBody body) unique

    KernelModulePlan = (MoonCode.CodeModuleId module,
                        MoonFlow.FlowFactSet flow,
                        MoonValue.ValueFactSet value,
                        MoonMem.MemSemanticFactSet mem,
                        MoonEffect.EffectFactSet effect,
                        MoonKernel.KernelPlan* plans) unique
}
```

Decisions:

- `KernelEffectScan`, `KernelEffectPartition`, `KernelEffectCopy`, and
  `KernelResultFind` are first-class array skeleton semantics. They are not
  encoded as callback names or stencil strings; LuaJIT stencil lowering is one
  backend consumer of those meanings.
- The counted-loop kernel planner rewrites ordinary prefix-scan and primary
  index copy loops into `KernelEffectScan` and `KernelEffectCopy`. That keeps
  copy and scan ownership in the kernel semantic layer, not in a backend store
  recognizer. Copy uses `StencilCopyNoOverlap` when dependence facts prove
  independence and `StencilCopyMemMove` when source/destination overlap remains
  unresolved.
- Early-exit primary-index searches are `KernelResultFind`.
- Stable partition is represented as a function-level two-pass semantic
  fragment with `KernelEffectPartition`, because it is not a single-loop store.
- `KernelResultClosedForm` cites `MoonValue.ClosedFormFact`.
- Kernel has equivalence proof/rejects, not only safety.
- Kernel plans are many-per-module and many-per-function.
- Kernel plan selection is a Llisle relation. `code_kernel_plan` builds the
  candidate facts and final MoonKernel values; `code_kernel_plan_rules` owns
  no-plan rejection priority, result priority, and the proof bit for
  closed-form plans whose Flow trip count is unknown.
- LuaJIT stencil lowering is split into Llisle plan and selector relations.
  `plan_store_stencil` / `plan_reduce_stencil` own readiness gates over planned
  kernels, counted loops, return shape, single-store or reduction shape, and
  enriched class availability. `select_store_stencil` / `select_reduce_stencil`
  own concrete stencil vocabulary, op, provider info, and argument ordering.
  Stencil constructors declare their `info`/`args`/`op`/`selection` product
  contracts in Llisle, so the stencil vocabulary is inspectable metadata rather
  than an undocumented Lua table convention.

---

## 11. MoonSchedule ASDL

Schedule is target-specific and separate.

```asdl
module MoonSchedule {
    ScheduleId = (string text) unique

    ScheduleTarget = (MoonBack.BackTargetModel target) unique

    LaneShape = LaneScalar
        | LaneVector(MoonCode.CodeType elem_ty, number lanes) unique

    TailPlan = TailNone
        | TailScalar
        | TailMasked
        | TailPeel(number elems) unique

    ScheduleKind = ScheduleScalarIndex
        | ScheduleScalarPointer
        | ScheduleVector(MoonSchedule.LaneShape lanes, number unroll, number interleave, MoonSchedule.TailPlan tail) unique
        | ScheduleClosedForm

    ScheduleProof = ScheduleProofTarget(string reason) unique
        | ScheduleProofMemory(MoonMem.MemProof proof) unique
        | ScheduleProofAlgebra(MoonValue.AlgebraProof proof) unique
        | ScheduleProofProfit(string reason) unique

    ScheduleReject = ScheduleRejectTarget(string reason) unique
        | ScheduleRejectMemory(string reason) unique
        | ScheduleRejectAlgebra(string reason) unique
        | ScheduleRejectProfit(string reason) unique

    KernelSchedule = ScheduleNoPlan(MoonKernel.KernelId kernel, MoonSchedule.ScheduleReject* rejects) unique
        | SchedulePlanned(MoonSchedule.ScheduleId id,
                          MoonKernel.KernelId kernel,
                          MoonSchedule.ScheduleKind kind,
                          MoonSchedule.ScheduleProof* proofs,
                          MoonSchedule.ScheduleReject* rejected_alternatives) unique

    ScheduleModulePlan = (MoonCode.CodeModuleId module,
                          MoonSchedule.ScheduleTarget target,
                          MoonSchedule.KernelSchedule* schedules) unique
}
```

Decisions:

- target model is part of schedule input and schedule output.
- unroll/interleave/tail are explicit choices with proofs/rejects.
- profitability is a proof/reject fact, even when primitive.
- Schedule selection is a Llisle relation. `code_schedule_plan` builds schedule
  candidates and final MoonSchedule values; `code_schedule_plan_rules` owns
  vector-first priority, scalar/closed-form fallback, rejected vector
  alternatives, and no-plan rejection.

---

## 12. MoonLower ASDL replacement

This replaces coarse `LowerFuncCode` / `LowerFuncKernel`.

```asdl
module MoonLower {
    LowerFragmentId = (string text) unique

    LowerTarget = LowerTargetBack
        | LowerTargetC

    LowerCover = LowerCoverFunction(MoonCode.CodeFuncId func) unique
        | LowerCoverLoop(MoonGraph.GraphLoopId loop) unique
        | LowerCoverBlock(MoonCode.CodeFuncId func, MoonCode.CodeBlockId block) unique
        | LowerCoverBlockRange(MoonCode.CodeFuncId func, MoonCode.CodeBlockId entry, MoonCode.CodeBlockId exit) unique

    LowerStrategy = LowerStrategyCode(string reason) unique
        | LowerStrategyKernel(MoonKernel.KernelId kernel, MoonSchedule.ScheduleId schedule) unique
        | LowerStrategyClosedForm(MoonKernel.KernelId kernel, MoonValue.ClosedFormFact fact) unique

    LowerFragment = (MoonLower.LowerFragmentId id,
                     MoonLower.LowerCover cover,
                     MoonLower.LowerStrategy strategy,
                     MoonLower.LowerProof* proofs,
                     MoonLower.LowerIssue* issues) unique

    LowerFuncPlan = (MoonCode.CodeFuncId func,
                     MoonLower.LowerFragment* fragments) unique

    LowerProof = LowerProofCoverage(string reason) unique
        | LowerProofKernel(MoonKernel.KernelId kernel, string reason) unique
        | LowerProofSchedule(MoonSchedule.ScheduleId schedule, string reason) unique
        | LowerProofFallback(string reason) unique

    LowerIssue = LowerIssueOverlap(MoonLower.LowerFragmentId a, MoonLower.LowerFragmentId b) unique
        | LowerIssueGap(MoonCode.CodeFuncId func, string reason) unique
        | LowerIssueFallback(MoonLower.LowerCover cover, string reason) unique

    LowerModule = (MoonCode.CodeModuleId module,
                   MoonLower.LowerTarget target,
                   MoonKernel.KernelModulePlan kernels,
                   MoonSchedule.ScheduleModulePlan schedules,
                   MoonLower.LowerFuncPlan* funcs,
                   MoonLower.LowerIssue* issues) unique
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

## 13. Back boundary rules

Back ASDL is executable backend input. It is not a place to park semantic facts
that Rust cannot consume.

### 13.1 Executable Back metadata

The backend-consumed metadata set is deliberately finite:

```text
memory:
  notrap
  aligned / alignment bytes when Cranelift supports it
  can_move
  readonly

integer:
  wrap / no-signed-wrap / no-unsigned-wrap / exact when representable

float:
  strict / reassoc / fast where backend flags can implement it

target:
  vector lane shape used by emitted commands
```

If a semantic fact is not in this executable set, it must be consumed before
Back. For example, alias/dependence facts may choose a schedule, permit motion,
or reject a kernel; they do not become no-op Back commands.

### 13.2 Alias facts are not executable Back metadata

Decision: until the Rust/Cranelift backend consumes Moonlift alias/noalias facts
as real metadata, alias facts do not exist in Back at all. They remain in
Mem/Lower/Schedule where they shape decisions.

This prevents decorative ASDL without adding report machinery or wire-level
failure paths.

---

## 14. Lowering algorithm

`lower_to_back` walks the Lower plan, not raw Code alone.

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
6. Kernel-local algebra recognizers that do not emit `MoonValue` facts.
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
4. A closed-form reduction is represented as `MoonValue.ClosedFormFact` before
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
MoonCode is meaning.
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
