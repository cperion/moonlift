# Lalin Native Loop Architecture

This note records the architecture direction for exposing stencil-shaped work
as ordinary-looking native loops in Lalin.

The design goal is not to add a new backend primitive. The design goal is to
let source programs author regular loop domains and loop-local sinks, then let
the existing `Code -> Flow -> Kernel -> Stencil` pipeline prove that the loop is
eligible for stencil materialization by the BC path, the MC bank path, or the
emitted copy+residual artifact.

## Core Decision

Native loop syntax must not lower directly to a `StencilDescriptor`.

The intended path is:

```text
surface native loop
  -> typed Code / CFG
  -> FlowDomain + FlowDomainShapeFact + FlowDomainIntentFact
  -> KernelPlan
  -> StencilDescriptor
  -> artifact selection / BC / MC / emitted bank
```

This keeps each layer's ownership intact:

| Layer | Owns |
| --- | --- |
| Surface syntax | Author intent, concise loop notation, explicit native-loop restrictions |
| `LalinCode` / CFG | Typed values, blocks, control, ordinary effects |
| `LalinFlow` | Domain identity, counted loop facts, induction facts, domain shape |
| `LalinKernel` | Stencil-purity proof, lanes, pure bindings, stores, folds, scans |
| `LalinStencil` | Producer/body/sink descriptor, ABI, schedule, proof obligations |
| Materializers | BC/MC/bank execution, fallback, rejects, realized schedule evidence |

The stencil backend should only see facts and descriptors. It should never need
to know which surface spelling produced them.

## Surface Vocabulary

The proposed user-facing vocabulary is:

```text
lln.loop   restricted native/stencil loop head
lln.range  producer/domain authoring helper
lln.fold   reduce sink authoring helper
lln.scan   scan sink authoring helper
```

Assignments inside the loop use the normal assignment primitive. In the
Lua-owned DSL that primitive is `set (place)(value)`; a future source spelling
can surface the same `StmtSet` as `place = value`.

```lua
lln.loop. i [lln.range { 0, n }] {
  set (out[i])(a[i] + b[i]),
}
```

Folds are source/kernel vocabulary:

```lua
lln.loop. i [lln.range { 0, n }] [lln.i32] {
  lln.fold. acc [lln.i32] {
    init = 0,
    by   = lln.add,
    step = a[i] * b[i],
  },
}
```

`by` accepts the reducers already modeled by `LalinValue.ReductionKind`:
`lln.add`, `lln.mul`, `lln.band`, `lln.bor`, `lln.bxor`, `lln.min`, and
`lln.max`.

Scans are source/kernel vocabulary:

```lua
lln.loop. i [lln.range { 0, n }] {
  lln.scan. acc [lln.i32] {
    init = 0,
    by   = lln.add,
    step = a[i],
    into = out[i],
  },
}
```

Multi-axis producer syntax is explicit. It is the only source-level trigger for
ND loop intent:

```lua
lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
  set (out[i * w + j])(a[i * w + j] + b[i * w + j]),
}
```

This is the source-level trigger for a multi-axis domain. It must not be
inferred from indexing arithmetic. The current executable lowering uses a flat
counted induction plus generated coordinate bindings, while preserving the
authored domain as `FlowDomainShapeRangeND` so backend selection still sees an
ND producer rather than a guessed 1D loop.

This spelling is allowed to feel like loops to the programmer. Internally, it
must remain a restricted regular-domain authoring form.

## No New Stencil Vocabulary

There should be no `StencilLoop`.

`StencilDescriptor` is already the loop-shaped backend product:

```text
StencilDescriptor = StencilProducer + StencilBody + StencilSink
```

There should also be no first-class `StencilFold` vocabulary unless a future
semantic distinction appears that cannot be represented by the current schema.

`fold` is the source/kernel word. `reduce` is the stencil/backend word:

```text
lln.fold syntax
  -> KernelEffectFold
  -> StencilSinkReduce(..., StencilReduceFold(...))
```

The public wording can be friendly without duplicating backend meaning.

## Lowering Shape

The frontend lowers a native loop into ordinary typed code plus explicit domain
facts. The important products are already present:

- `LalinFlow.FlowDomainShapeRange1D`
- `LalinFlow.FlowDomainShapeRangeND`
- `LalinFlow.FlowDomainShapeWindowND`
- `LalinFlow.FlowDomainShapeTiledND`
- `LalinFlow.FlowDomainShapeFact`
- `LalinFlow.FlowDomainIntentFact`
- `LalinKernel.KernelEffectStore`
- `LalinKernel.KernelEffectFold`
- `LalinKernel.KernelEffectScan`

The existing LuaJIT lowering boundary already projects
`FlowDomainShapeFact` into `StencilProducerFact`, and stencil descriptors
already contain:

- `StencilProducer`
- `StencilBodyApply`
- `StencilSinkStore`
- `StencilSinkReduce`
- `StencilSinkScan`

So the implementation should extend the frontend and kernel planner rather than
add a parallel stencil-loop path.

## Purity Boundary

`lln.loop` is not a general control-flow construct. It is a native regular loop
head whose body must be accepted by the kernel planner as stencil-pure.

Initially, the body should admit:

- Pure scalar expressions over loop-invariant values and lane loads.
- Local pure bindings that become `KernelBinding`s.
- Positional stores that become `KernelEffectStore`.
- One fold sink that becomes `KernelEffectFold`.
- One scan sink that becomes `KernelEffectScan`.

The body should reject:

- Unknown calls.
- Arbitrary mutation.
- Control effects that cannot be represented as a pure body plus closed sink.
- Multiple incompatible sink families in one loop.
- Memory effects without clear lane/layout ownership.

The diagnostic should name the failed proof, not the backend:

```text
native loop body must be stencil-pure;
unknown call `weird_dynamic_condition` is not allowed in a native loop
```

If the source loop is valid Lalin but not stencil-pure, the compiler may still
choose a generic lowering path. If the user explicitly requested `lln.loop`,
the rejection should be typed and stable.

## Sink Classification

The kernel planner owns sink classification.

```text
assignment to positional lane  -> KernelEffectStore  -> StencilSinkStore
lln.fold                       -> KernelEffectFold   -> StencilSinkReduce
lln.scan                       -> KernelEffectScan   -> StencilSinkScan
```

The stencil selector should not rediscover source syntax. It should consume the
kernel body's effects and result.

This preserves the current backend thesis: the closed sink axis is store,
reduce, and scan. Other operations remain rewrites, compositions, or specialized
reduce/store modes:

- count: reduce predicate
- find: reduce/find mode
- copy/fill/cast/compare/select: store/apply modes or body expressions
- partition: store/partition mode
- gather/scatter: access layout and store mode

## Domain Facts

`lln.range` is an authoring helper for `FlowDomainShape`.

The frontend should create Flow-owned domain facts with explicit provenance:

```text
FlowDomainShapeFact(
  domain = FlowDomain...,
  shape = FlowDomainShapeRange1D(...),
  proofs = ...,
  origin = FlowFactFrontendFact(...)
)

FlowDomainIntentFact(
  domain = FlowDomain...,
  intent = FlowDomainIntentNativeLoop(...),
  proofs = ...,
  origin = FlowFactFrontendFact(...)
)
```

Checker-derived facts can later replace or strengthen frontend-authored facts.
The stencil boundary should continue projecting these facts through
`StencilProducerFact`, preserving provenance.

This makes ND, tiled, and windowed native loops an extension of the same fact
path, not a separate syntax-to-materializer path.

## Implemented Range1D Surface

The implemented Lua-owned DSL surface covers the Range1D assignment, fold, and
scan families, including positive and negative constant steps:

```lua
lln.loop. i [lln.range { 0, n }] {
  set (out[i])(a[i] + b[i]),
}

lln.loop. i [lln.range { 0, n }] [lln.i32] {
  lln.fold. acc [lln.i32] {
    init = 0,
    by   = lln.add,
    step = a[i] * b[i],
  },
}

lln.loop. i [lln.range { 0, n }] {
  lln.scan. acc [lln.i32] {
    init = 0,
    by   = lln.add,
    step = a[i],
    into = out[i],
  },
}
```

Current behavior:

- The DSL lowers `lln.loop` to an ordinary typed control region with
  entry/header/body/done blocks.
- `CodeFlowFacts` recognizes the generated native-loop labels after graph loop
  discovery and attaches `FlowDomainShapeFact` plus
  `FlowDomainIntentNativeLoop`.
- LuaJIT stencil lowering projects `FlowDomainShapeFact` to
  `StencilProducerFact` and reuses the existing kernel-to-stencil paths.
- Assignment loops become `KernelEffectStore` and `StencilSinkStore`.
- Fold loops generate a loop-carried accumulator recurrence, which becomes
  `KernelEffectFold` and `StencilSinkReduce`.
- Scan loops generate a loop-carried accumulator plus prefix store, which
  becomes `KernelEffectScan` and `StencilSinkScan`.
- The implemented range form is Range1D. Positive ranges default to `index`.
  Negative-step ranges default to `i32`, preserve `FlowDomainBackward`, and use
  the absolute step in the authored producer shape. Explicit `ty = ...` remains
  accepted as a type override.
- Reducer sugar covers `add`, `mul`, `band`, `bor`, `bxor`, `min`, and `max`,
  matching the current `ReductionKind` vocabulary.

Still future work:

- Assignment sugar in the Lua-owned DSL. Lua table constructors cannot carry
  `out[i] = expr` as a value, so the current Lua DSL uses `set (out[i])(expr)`.
- `range_nd` executable lowering covers zero-based forward RangeND loops and
  normalizes the exact 2D row-major `i * w + j` index form to the generated flat
  induction for native store stencils.
- Tiled/window authoring sugar.
- General ND affine index recognition beyond the current zero-based row-major
  normalization.
- Backward Range1D support is implemented for primary-index native store/copy,
  fold, and scan materialization. Reverse-affine 1D destination indexes such as
  `dst[(n - 1) - i]` are represented explicitly as `StencilLayoutAffine1D`.

## Rejection Ownership

Rejections should occur at the first layer that owns the failed claim:

| Failure | Owner |
| --- | --- |
| malformed native loop syntax | frontend |
| invalid typed expression | typechecker / `LalinCode` |
| non-counted or malformed domain | `LalinFlow` |
| impure body or unsupported effect | `LalinKernel` |
| unsupported producer/body/sink cell | `LalinStencil` selection/support matrix |
| unavailable BC/MC/bank artifact | materializer / bank |
| requested schedule cannot be proved | schedule/proof layer |

This prevents stencil materialization from becoming a grab bag of source
diagnostics.

## Implementation Order

The architecture suggests this order:

1. Define the source native-loop AST/sugar so it lowers to ordinary typed code.
2. Emit `FlowDomainShapeFact` for explicit `lln.range` domains.
3. Extend kernel planning/purity checks to accept source-authored native loops.
4. Preserve `KernelEffectStore`, `KernelEffectFold`, and `KernelEffectScan` as
   the only initial loop sinks.
5. Reuse the existing `KernelPlan -> StencilDescriptor` projection.
6. Add typed rejects for failed native-loop proofs before expanding syntax.
7. Only after the path is stable, add tiled/window authoring sugar.

The first milestone is architectural, not performance-oriented: a source loop
must produce the same facts and descriptors as a hand-built kernel plan.

## Non-Goals

- Do not add source-level generics.
- Do not add angle-bracket type arguments.
- Do not make `lln.loop` a general `for` or `while`.
- Do not add `StencilLoop`.
- Do not add `StencilFold` as an alias for reduce.
- Do not bypass `Flow` and `Kernel` to reach stencil materialization faster.
- Do not put source syntax names into artifact fingerprints except through the
  structural facts they author.

## Architectural Invariant

The invariant for this feature is:

```text
Native loop syntax authors facts.
Kernel planning proves regular stencil-pure meaning.
Stencil descriptors remain backend products.
Copy-patch materializes only proved descriptors.
```

If a proposed implementation violates that path, it is probably putting meaning
in the wrong layer.
