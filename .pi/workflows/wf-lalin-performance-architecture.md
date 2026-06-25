# Lalin semantic performance architecture review 
Architecture-wide investigation of why Lalin's semantic ASDL/PVM/lowering stack is not yet producing consistently excellent native code, without benchmark-specific recognizers.
**Workflow ID**: wf-lalin-performance-architecture
**Started**: 2026-06-16 07:24:00
---

## Scout Output — 2026-06-16 07:30:05

## Files Retrieved

1. `COMPILER_PATTERN.md` (lines 1-1189) - Architectural framing: ASDL is the architecture; phase boundaries consume decisions; classify fields as code-shaping/payload/dead; final execution should consume flat facts, not rediscover source semantics.
2. `PVM_GUIDE.md` (lines 1-1821) - PVM framing: `pvm.phase` as the one memoized boundary, layers where vocabulary changes, flatten-early, uniform command product, diagnostics/reuse as architecture quality metric.
3. `lua/lalin/frontend_pipeline.lua` (lines 1-260) - Main hosted/native pipeline: parse → open expand → typecheck → layout resolve → tree_to_code → flow/mem facts → kernel plan → lower plan → LowerToBack → validate.
4. `lua/lalin/schema/back.asdl` (lines 1-420) - Back command vocabulary, target model, memory/provenance facts, vector commands, validation/inspection facts.
5. `lua/lalin/schema/code.asdl` (lines 1-233) - Mid-level Code IR: Code types, memory access, integer/float semantics, contracts, aggregate/view/variant/closure/atomic instructions.
6. `lua/lalin/schema/flow.asdl` (lines 1-78) - CFG/loop fact vocabulary and semantic loop facts.
7. `lua/lalin/schema/mem.asdl` (lines 1-133) - Memory object/access/alias/dependence/safety/effect/relation semantic facts.
8. `lua/lalin/schema/kernel.asdl` (lines 1-113) - Kernel plan vocabulary: streams, expressions, reductions, closed forms, schedules.
9. `lua/lalin/schema/lower.asdl` (lines 1-17) - Lowering plan vocabulary selecting Code vs Kernel per function.
10. `lua/lalin/tree_to_code.lua` (lines 1-1643) - Imperative Tree → Code lowering; emits Code IR, contracts, control regions, views, aggregates.
11. `lua/lalin/code_to_back.lua` (lines 1-497) - General Code → Back projection; limited supported Code instructions and semantics projection.
12. `lua/lalin/code_flow_facts.lua` (lines 1-471) - Derives CFG edges, counted-loop facts, simple induction ranges, flow semantic facts.
13. `lua/lalin/code_mem_facts.lua` (lines 1-830) - Derives access facts, conservative aliases/dependences, semantic memory objects/safety/effects/relations.
14. `lua/lalin/code_kernel_plan.lua` (lines 1-673) - Builds kernel plans from flow/mem facts; chooses vector/scalar schedules.
15. `lua/lalin/code_lower_plan.lua` (lines 1-50) - Chooses `LowerFuncKernel` only for whole-function kernel subjects.
16. `lua/lalin/lower_to_back.lua` (lines 1-651) - Projects selected kernel plans or falls back to CodeToBack; manually emits scalar/vector kernel Back commands.
17. `lua/lalin/back_target_model.lua` (lines 1-73) - Static native target model and supported vector shapes/op classes.
18. `lua/lalin/back_command_binary.lua` (lines 1-759) - BackProgram binary encoder; maps Back commands to Flatline wire tags and drops some facts.
19. `src/decode.rs` (lines 1-711) - Rust Cranelift wire decoder; consumes only flat tags, basic MemFlags, Cranelift ops.
20. `src/lib.rs` (lines 1-220) - Cranelift JIT/object setup and ISA flags.

## Key Code

### Pipeline derives semantic facts, then immediately lowers through a narrow path

`lua/lalin/frontend_pipeline.lua`:
```lua
local code_module, code_contracts = TreeToCode.module_with_contracts(...)
local flow_facts = CodeFlowFacts.facts(code_module)
local flow_semantics = CodeFlowFacts.semantic_facts(code_module, flow_facts)
local mem_facts = CodeMemFacts.facts(code_module, flow_facts)
local mem_semantics = CodeMemFacts.semantic_facts(code_module, flow_facts, flow_semantics, code_contracts)
local kernel_plan = CodeKernelPlan.plan(...)
local lower_plan = CodeLowerPlan.plan(...)
local program = LowerToBack.module(code_module, lower_plan, { validate = false })
```
(lines 103-114)

This is architecturally good in shape, but most stages are plain whole-module functions, not `pvm.phase` boundaries, and much semantic vocabulary is only partially consumed.

### Code/Back schemas have semantic vocabulary that lowering largely erases

`lua/lalin/schema/back.asdl`:
```asdl
BackMemoryInfo = (... alignment, dereference, trap, motion, mode) unique
BackAliasFact = BackAliasUnknown | BackMayAlias | BackNoAlias | ...
BackIntSemantics = (BackIntOverflow overflow, BackIntExact exact) unique
BackFloatSemantics = BackFloatStrict | BackFloatReassoc | BackFloatFastMath
...
CmdIntBinary(... BackIntSemantics semantics, ...)
CmdFloatBinary(... BackFloatSemantics semantics, ...)
CmdAliasFact(LalinBack.BackAliasFact fact) unique
```
(lines 117-154, 273-279)

But `lua/lalin/code_to_back.lua` collapses Code semantics:
```lua
local function int_semantics(k)
    return Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose)
end

local function float_semantics(k)
    return Back.BackFloatStrict
end
```
(lines 145-151)

And `tree_to_code.lua` defaults source arithmetic to wrapping/strict:
```lua
return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)
...
return Code.CodeFloatStrict
```
(lines 315-320)

### Memory/alias facts are derived, but not generally projected to Cranelift

`lua/lalin/code_mem_facts.lua` derives conservative base facts:
```lua
Mem.MemAliasUnknown(..., "code_mem_facts foundation is conservative")
Mem.MemDependenceUnknown(..., "dependence analysis deferred")
```
(lines 561, 576)

It also derives richer semantic facts:
```lua
Mem.MemAccessMovable(...)
Mem.MemObjectReadonly(...)
Mem.MemObjectsSameLen(...)
```
(lines 701, 761, 786)

But `back_command_binary.lua` skips alias facts and target model commands:
```lua
elseif k == "CmdTargetModel" or k == "CmdAliasFact" then
    -- skip, no-op in Rust decoder
```
(lines 593-594)

The Rust decoder only receives a 3-bit memory flag:
```rust
fn mf(bits: u32) -> MemFlags {
    if bits & 1 != 0 { f.set_notrap(); }
    if bits & 2 != 0 { f.set_aligned(); }
    if bits & 4 != 0 { f.set_can_move(); }
}
```
`src/decode.rs` (lines 50-56)

### Kernel planning is narrow and function-replacement oriented

`code_lower_plan.lua` only selects kernels if the plan subject is the entire function:
```lua
if plan ~= nil and pvm.classof(plan) == Kernel.KernelPlanned
    and pvm.classof(plan.subject) == Kernel.KernelSubjectFunc
    and plan.subject.func == func.id then
    return Lower.LowerFuncKernel(plan)
end
return Lower.LowerFuncCode(func.id)
```
(lines 22-28)

`lower_to_back.lua` also rejects non-function kernel subjects:
```lua
if pvm.classof(plan.subject) ~= Kernel.KernelSubjectFunc then return nil end
```
(line 174)

`code_kernel_plan.lua` only stores the first loop plan per function:
```lua
if func ~= nil and plan_by_func[func.id.text] == nil then
    plan_by_func[func.id.text] = plan_loop(...)
end
```
(lines 649-654)

### Target model/scheduling are static and shallow

`back_target_model.lua`:
```lua
-- TODO: add BackFeatureAVX2 + 8/4-lane shapes when Cranelift x64
-- backend supports >128-bit vectors...
BackTargetSupportsShape(shape_vec(Back.BackI32, 4)),
...
BackTargetPrefersUnroll(shape_vec(Back.BackI32, 4), 1, 50),
```
(lines 23-50)

`code_kernel_plan.lua` schedule:
```lua
if vector_ok then
    local vec, pref = target_vector_choice(...)
    if vec ~= nil then
        return Kernel.KernelScheduleVector(..., pref.unroll or 1, 1, Kernel.KernelTailScalar, proofs)
    end
end
return Kernel.KernelScheduleScalarIndex(proofs)
```
(lines 326-341)

## Relationships

- Source/tree semantics are checked and resolved into `LalinTree`.
- `tree_to_code.lua` lowers `LalinTree` into `LalinCode.CodeModule` and `CodeContractFactSet`.
- `code_flow_facts.lua` derives `FlowFactSet` and `FlowSemanticFactSet`.
- `code_mem_facts.lua` derives `MemFactSet` and `MemSemanticFactSet`.
- `code_kernel_plan.lua` consumes flow/mem facts to produce `KernelModulePlan`.
- `code_lower_plan.lua` chooses whole-function kernel replacement only when a `KernelSubjectFunc` plan exists.
- `lower_to_back.lua` either emits a handcrafted kernel Back program or falls back to `code_to_back.lua`.
- `back_command_binary.lua` serializes Back commands to Flatline.
- `src/decode.rs` maps Flatline tags directly to Cranelift builder calls.

Critical loss points:
1. `Tree → Code`: semantic intent becomes imperative Code instructions; some source facts become contracts, but many decisions become side tables or plain offsets.
2. `Code → Back`: arithmetic, alias/provenance, aggregate/view/variant semantics are narrowed or unsupported.
3. `Back → wire/Rust`: most Back semantic facts are either converted to three MemFlags or skipped.

## Observations

### Priority 0 — Semantic facts exist but are not consumed deeply enough

- `FlowSemanticFactSet` has normalized counted loops, trip counts, induction no-wrap/ranges, but consumers use only a narrow subset.
- `MemSemanticFactSet` carries objects, intervals, safety, effects, relations, proofs. Kernel planning mainly consumes inbounds/nontrap/align/movable/no-dependence. Readonly/writeonly/same_len/window relations are mostly not used for general backend optimization.
- `BackAliasFact` and `CmdAliasFact` exist but are skipped by the binary encoder, so Cranelift never sees alias scopes/noalias.
- Back provenance/bounds exist in `BackAddress`/`CmdPtrOffset`, but the wire path emits only address arithmetic and MemFlags.

### Priority 0 — Kernel path is tactical, not yet a general semantic lowering strategy

- Only the first loop per function is planned.
- Only whole-function kernel subjects are used for replacement.
- General loop kernels inside larger functions fall back to ordinary Code lowering.
- Kernel expressions/schedules are much richer in schema than in implementation. The implementation supports a small expression subset and handcrafted scalar/vector loops.
- Vector lowering assumes start=`0`, step=`1`, contiguous streams, scalar tail, no masked tail, unroll/interleave effectively fixed.

### Priority 1 — General Code → Back projection is incomplete

`Code` supports aggregates, arrays, views, closures, variants, atomics, and variant switches. `code_to_back.lua` supports only a subset. Notable gaps:
- `CodePlaceLocal` is not generally projected to stack slots.
- `CodeInstAggregate`, `CodeInstArray`, `CodeInstClosure`, `CodeInstVariant*`, many atomics, and `CodeTermVariantSwitch` are not handled in the general path.
- Views are carried via `ctx.view_values` side tables in `code_to_back.lua`, not as first-class backend values.

This means Lalin can typecheck and semantically represent constructs that the native projection cannot optimize—or sometimes cannot lower.

### Priority 1 — Arithmetic semantics are too weak

- Source arithmetic defaults to wrapping integer semantics and strict float semantics.
- Flow analysis can recognize no-wrap only if `CodeIntAssumeNoOverflow` exists, but Tree lowering does not produce it.
- Back commands can represent `BackIntNoSignedWrap`, `BackIntNoUnsignedWrap`, `BackFloatReassoc`, `BackFloatFastMath`, but CodeToBack currently discards that information.
- Cranelift receives ordinary integer/float ops without higher-level semantic flags beyond the chosen opcode.

### Priority 1 — PVM phase-boundary architecture is not applied consistently in the lowering stack

The docs emphasize named phase boundaries that consume decisions and expose cache/reuse diagnostics. Current performance-critical lowering after typecheck is mostly plain whole-module functions:
- `TreeToCode.module_with_contracts`
- `CodeFlowFacts.facts`
- `CodeMemFacts.facts`
- `CodeKernelPlan.plan`
- `LowerToBack.module`

These are semantic stages, but not PVM memoized boundaries. That limits incremental recompilation diagnostics and makes derived facts less composable/reusable.

### Priority 2 — Validation does not prove semantic preservation

- `CodeValidate` checks many reference/type invariants but not deep operation-domain/cost/scheduling properties.
- `KernelValidate` checks references and rejects unsafe volatile/atomic/may-trap plans, but does not prove kernel replacement is equivalent to the original Code function.
- `BackValidate` checks command references/shapes/memory metadata consistency, but target shape checks depend on `CmdTargetModel`, which the normal encoder skips and the pipeline does not appear to emit.

### Priority 2 — Target model is underpowered

- Default target model is static and conservative, not derived from actual Cranelift ISA features.
- Vector op classes are strings (`"int_binary"`, `"bit_binary"`, `"compare_select"`), not a typed op vocabulary.
- No AVX2/AVX512 shapes; unroll preference is hard-coded to 1.
- Scheduling lacks a general cost model, cache/memory bandwidth model, latency model, register pressure model, or tail strategy selection.

### Priority 3 — Missing semantic vocabulary for generally excellent native code

Likely missing or underdeveloped vocabularies:
- Affine expressions / symbolic ranges beyond simple primary induction.
- Def-use expression DAG facts independent of kernel recognition.
- General loop-nest representation and nested-loop schedules.
- Alias scopes and memory object relations projected all the way to backend.
- Call effects and escape summaries.
- Stack/local allocation facts and scalar replacement facts.
- Vector pack/tail/mask semantics as first-class facts.
- Fast-math/no-wrap/precondition vocabulary connected to source contracts.

## Priority Summary for Next Work

1. **Make semantic facts consumable end-to-end**: alias/provenance/bounds/no-wrap/fast-math should survive to Back/wire/Cranelift where possible.
2. **Generalize lowering from whole-function kernel replacement to compositional loop/block lowering**.
3. **Complete Code → Back projection for Code IR constructs already represented semantically.**
4. **Turn flow/mem/kernel/lower stages into proper PVM phase boundaries with diagnostics.**
5. **Strengthen target model and scheduling vocabulary beyond static vector-shape selection.**
6. **Add validation that kernel/lower plans preserve Code semantics, not just reference consistency.**

## Knowledge-builder Output — 2026-06-16 07:43:26

### What Matters Most for This Problem

- **Semantic survivability end-to-end**: whether source/type/contract/flow/memory facts still affect final native code after Code → Back → wire → Cranelift.
- **Which facts are code-shaping vs decorative**: facts that do not change lowering decisions, command shape, flags, or schedule are effectively dead.
- **Compositional lowering**: excellent performance cannot depend on whole-function kernel replacement.
- **Phase-boundary discipline**: PVM phases should consume decisions at vocabulary boundaries; current lowering stack mostly computes whole-module side products.
- **Semantic cliffs**: small changes should not cause a fall from “planned vector kernel” to “generic unoptimized CodeToBack.”
- **Schema/backend truthfulness**: ASDL vocabulary that is skipped by the wire path creates an illusion of architecture without backend effect.

---

### Non-Obvious Observations

#### 1. The main failure is not absence of semantic facts; it is that facts are not in the lowering control path

Lalin already derives many meaningful facts: counted loops, induction ranges, memory objects, bounds, nontrap, movable accesses, readonly/writeonly, same length, no-dependence, etc.

But most of these facts live as **parallel side tables keyed by IDs**, while the actual Back emission still primarily walks `CodeInst` imperatively.

That means the pipeline often asks:

> “Can I recognize a whole function as a kernel?”

instead of:

> “Given these facts, what should each memory op, arithmetic op, loop, block, and call lower into?”

So semantic facts are currently used more as **admission criteria** than as **code-shaping facts**.

#### 2. Kernel planning is an all-or-nothing performance island

`KernelSubjectLoop` exists in the schema, but `code_lower_plan.lua` and `lower_to_back.lua` only accept whole-function kernel replacement.

That creates a sharp cliff:

- whole function matches narrow kernel shape → custom scalar/vector lowering
- anything else → generic `CodeToBack`
- generic path mostly drops semantic memory/arithmetic facts

So performance is not emerging generally from Lalin semantics. It emerges when the whole function happens to fit a handcrafted replacement path.

This explains inconsistent native performance better than any single missed optimization.

#### 3. The Back schema says semantics are first-class, but the wire/backend path treats many as dead

`BackAliasFact`, `BackTargetModel`, richer pointer provenance, bounds, integer semantics, and float semantics exist in ASDL. But:

- `CmdAliasFact` and `CmdTargetModel` are skipped by `back_command_binary.lua`
- Rust receives only basic Cranelift ops and 3 memory flag bits
- integer and float semantics are usually collapsed before encoding

This creates a conceptual mismatch: the ASDL appears performance-aware, but the final consumer cannot observe most of that awareness.

In PVM terms, many fields have been misclassified: they look like payload, but are actually dead at the current boundary.

#### 4. The generic Code → Back path is the semantic sinkhole

The kernel path partially consumes memory semantics. The generic path mostly does not.

`code_to_back.lua` emits `BackMemoryInfo` from local `CodeMemoryAccess`, not from `MemSemanticFactSet`. It also hardcodes:

- integer ops as wrapping/may-lose
- floats as strict
- pointer bounds/provenance as mostly unknown/derived
- views through a Lua side table

So once lowering falls back to `CodeToBack`, much of Lalin’s semantic architecture has already lost influence.

This is deeper than “CodeToBack is incomplete”; it means the normal path cannot currently be the foundation for consistently excellent code.

#### 5. Source-level arithmetic semantics are too weak to prove important loop facts

Flow analysis can notice no-wrap only when `CodeIntAssumeNoOverflow` exists, but Tree → Code defaults source integer arithmetic to wrapping semantics.

So the architecture has a no-wrap vocabulary, but the frontend almost never creates the preconditions needed to use it.

That blocks downstream reasoning about:

- induction ranges
- trip counts
- vectorizable recurrences
- strength reduction
- bounds elimination
- reassociation

The same problem exists for floats: `BackFloatReassoc` and `BackFloatFastMath` exist, but source lowering defaults to strict and generic lowering discards mode anyway.

#### 6. Memory facts are promising but too detached from address generation

`MemObjectFact`, intervals, readonly/writeonly, same-length, and no-dependence facts are exactly the kind of facts Lalin should exploit.

But final Back commands mostly see already-lowered addresses and generic `MemFlags`.

The deeper issue: object-level memory knowledge is not integrated into the address/value vocabulary that CodeToBack emits. By the time Cranelift sees a load, the relationship to “this view has this length, this base is noalias, this window is bounded” has mostly become opaque pointer arithmetic.

Cranelift cannot rediscover Lalin view/contract semantics from flat pointer math.

#### 7. Views violate the “ASDL is the architecture” principle in the backend path

`CodeInstView` is handled in `code_to_back.lua` via `ctx.view_values`, a Lua side table. That is a hidden compiler state channel.

This matters for performance because views are central to Lalin’s memory semantics. If view decomposition is not represented as first-class backend facts/values, then length, stride, provenance, aliasing, and bounds cannot reliably participate in later lowering decisions.

The side table works operationally, but it is architecturally hostile to semantic optimization.

#### 8. The current fact sets are whole-module computations, not true PVM vocabulary boundaries

The docs emphasize `pvm.phase` as the boundary where a vocabulary changes and decisions are consumed. But the performance-critical chain is mostly plain whole-module functions:

- TreeToCode
- CodeFlowFacts
- CodeMemFacts
- CodeKernelPlan
- CodeLowerPlan
- LowerToBack

This has two consequences:

1. **Weak incrementality/diagnostics**: no phase reuse report explains which semantic decisions are stable or invalidated.
2. **Weak architectural pressure**: because these are not clean phase boundaries, facts accumulate as side products instead of being consumed into narrower representations.

The issue is not just caching. It is that the architecture lacks explicit “this layer answered this question” boundaries.

#### 9. Kernel planning uses proofs mostly for safety, not for equivalence or profitability

`KernelProofFunctionEquivalence` exists, but the scout found validation mostly checks reference consistency and rejects unsafe plans. It does not deeply prove the replacement is equivalent to the Code function.

That creates a tension:

- the kernel path performs the most aggressive rewrites
- but the proof vocabulary is not yet the main driver of replacement validity

Similarly, target scheduling is shallow: vector shape support and unroll preference exist, but there is little model for profitability, register pressure, memory bandwidth, masking, or loop-tail cost.

#### 10. The arithmetic-series closed form is a symptom of missing loop algebra

The kernel planner contains a specific closed-form recognition for arithmetic series under narrow conditions.

That is not inherently wrong, but architecturally it signals a missing abstraction: there is no general loop-expression/reduction algebra rich enough for closed forms, reductions, affine domains, and schedules to emerge uniformly.

Without that, performance pressure naturally produces local recognizers. The problem statement explicitly rejects benchmark-specific recognizers, so the missing abstraction is important.

#### 11. Target modeling is split-brain

Lua has `back_target_model.lua`; Rust/Cranelift has actual ISA setup. But `CmdTargetModel` is skipped in the binary encoder.

So planning and execution do not share a single enforced target contract. The Lua planner may believe a vector shape/schedule is appropriate, while the Rust backend independently decides what the ISA supports.

That weakens both correctness and performance portability.

#### 12. “Fallback” is semantically safe but performance-silent

The architecture has many rejection facts: `KernelReject*`, `FlowReject*`, memory unknowns, unsupported constructs. But these do not currently form a strong performance diagnosis surface.

When kernel planning fails or CodeToBack drops facts, the compiler still produces code. That is good for functionality, but bad for performance architecture: the system does not loudly distinguish “compiled well” from “compiled after losing key semantic facts.”

For Lalin’s philosophy, performance fallbacks probably need to be observable facts, not hidden control flow.

---

### Deeper Design Shifts Implied

- Treat semantic facts as **lowering inputs**, not post-hoc annotations.
- Make loop/block lowering **compositional**, not whole-function-only.
- Ensure Back/wire/Rust consume the semantic vocabulary that Back ASDL advertises, or remove/reclassify dead facts.
- Move from recognizers toward reusable abstractions: affine domains, reductions, memory objects, alias scopes, call effects, view provenance, and schedule facts.
- Align PVM phase boundaries with real vocabulary changes in the lowering stack.
- Make performance loss diagnosable as first-class facts, not silent fallback.

---

### Knowledge Gaps

- How much Cranelift’s current API can actually consume alias/noalias, fast-math, no-wrap, and provenance-like facts.
- Which source-level contract syntax should imply no-wrap/fast-math/range facts.
- Whether MOM/native compiler paths share or bypass the same semantic loss points.
- Concrete emitted IR comparisons would help quantify which facts currently matter, but the architectural diagnosis is already clear.
