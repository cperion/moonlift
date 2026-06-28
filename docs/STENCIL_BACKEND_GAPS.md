# Stencil Backend / Copy+Residual Completeness Gaps

This file tracks the remaining work needed before the LuaJIT stencil backend can
honestly be called complete. The active fast emitted artifact is copy+residual:
`copy_patch_mc` installs GCC-built bank stencils, and TCC compiles residual glue
that calls those bank stencils. The current backend is complete for a useful
scalar subset, but not for the full schema space.

## Current Implemented Core

- [x] Stencil type classification for the full representable `CodeType` family
  surface, with `void` rejected as a non-element type.
- [x] Scalar stencil type classification for signed/unsigned integers
  `i8/i16/i32/i64`, `u8/u16/u32/u64`, `f32`, `f64`, `index`, and `bool8`.
- [x] Non-scalar element-lane selection for copy, gather, scatter, and identity
  map across pointer, code-pointer, named, array, descriptor, handle, lease,
  closure, imported C, imported C function-pointer, and vector families.
- [x] Store-family selection for fill, copy, gather, scatter, in-place map,
  map, cast, compare, zip-map, and zip-compare across scalar element types.
- [x] Reduction-family selection for integer add/mul/and/or/xor/min/max.
- [x] Reduction-family selection for float add/mul/min/max.
- [x] Higher reduction selection for map-reduce and zip-reduce over the
  currently supported scalar reduction cells.
- [x] Descriptor/layout representation for contiguous, indexed, scalar,
  field projection, SoA component, slice descriptor, byte-span descriptor, and
  view descriptor. In-place is represented by `StencilAccessReadWrite`, not by
  a layout variant.
- [x] LuaTrace emission for the current stencil shape set: reduce, map,
  zip-map, scan, copy, fill, find, partition, cast, compare, zip-compare,
  gather, scatter, in-place map, count, map-reduce, and zip-reduce.
- [x] Embedded MC intern set for the current default scalar matrix and selected
  descriptor families.

## LalinStencil Schema Architecture Gap Register

Severity tags:

- `S`: soundness/correctness; can produce wrong machine code or wrong results.
- `T`: thesis violation; representable illegal states remain representable.
- `K`: stringly-typed/key-join structure where typed references are required.
- `C`: completeness; missing operations, cases, domains, or facts.
- `M`: minor, orphan, or cosmetic schema issue.

### Soundness Gaps

- [x] `A1` `[S]` Make aliasing relational instead of unary.
  `StencilAliasFact` is currently attached to one access through
  `StencilAccessVectorFact.alias`, but aliasing is a pairwise property. This
  cannot express partial disjointness, such as output aliasing input while both
  are disjoint from an index stream. Fix with explicit pairwise alias facts
  keyed by typed access references, or with alias classes where same-class
  accesses may alias and different classes are proven disjoint.
- [x] `A2` `[S]` Add integer and float semantics to element unary/binary ops.
  `StencilOpUnary` and `StencilOpBinary` now carry explicit
  `CodeIntSemantics` / `CodeFloatMode`. The artifact planner fills these facts
  when descriptors are built, and C/LuaTrace shapes preserve them. Integer
  unary negation now materializes wrap semantics through unsigned subtraction
  instead of signed `-x` UB.
- [x] `A3` `[S]` Give predicates explicit comparison signedness/semantics.
  The six string-of-meaning const predicate variants were replaced by
  `StencilPredCompareConst { cmp, operand_ty, value }`, sharing `CmpOp` with
  `StencilOpCompare`. Predicate lowering from kernel plans and stencil rules now
  carries the lane element type, and materializers cast through `operand_ty`.
- [x] `A4` `[S]` Add realized-vs-requested schedule evidence to artifacts.
  `StencilArtifact` now carries `realized [optional StencilRealizedSchedule]`
  and `schedule_rejects`; BC and MC materializers stamp installed/banked
  artifacts with realized scalar/unrolled/vector facts and typed mismatch
  rejects when requested and realized schedules diverge.
- [x] `A5` `[S]` Derive reducer identity from reduction and result type.
  `StencilReducer.init` was removed and replaced with
  `StencilReducer.identity`, which is derived from `(reduction, result_ty)` via
  `reduction_algebra`. Source reduction `init` remains a runtime/user seed; it
  no longer masquerades as the algebraic identity consumed by parallel/tree
  reduction descriptors.
- [x] `A6` `[S]` Define proof provenance for every unsafe vectorization license.
  `StencilVectorizationFacts` now carries typed `proof_obligations`, each with
  an obligation kind, origin, and optional `KernelProof`. The planner emits
  obligations for noalias pairs, known alignment, unit stride, trip-count
  multiples, and reducer reassociation, with origins split between
  checker-derived, boundary-contract, and author-asserted.

### Representable Illegal States

- [x] `B1` `[T]` Replace optional-bag `StencilDescriptor` with an honest
  `producer + body + sink` product. The old product permitted invalid
  combinations such as reduce skeleton without reducer, map vocab with reduce
  skeleton, or extra operators on copy. Sink/body variants now own the mandatory
  fields for their shape and make forbidden fields unrepresentable.
- [x] `B2` `[T]` Remove the unconstrained duplicate operation axis between
  `StencilVocab` and `StencilSkeleton`. `StencilSkeleton` was deleted; scan
  mode, copy semantics, find `not_found`, and partition semantics now live only
  on the sink/body variants that consume them. The remaining operation
  vocabulary is derived from sink/body shape where needed.
- [x] `B3` `[T]` Give memory semantics a single owner. Copy, partition, and
  scatter semantics now live on the sink/body shape that needs them; the
  duplicate `StencilMemorySemantics` schema product was removed.
- [x] `B4` `[T]` Remove schedule double-encoding. `StencilScheduleVector`
  no longer stores a bare lane count; requested lanes derive from
  `lane_policy`, while concrete lane counts live on `StencilRealizedVector`.
  Vector schedule unroll is now `vector_unroll`, distinct from
  `StencilScheduleUnrolled.factor`, and schedule-level alignment is named
  `required_alignment` to make its relation to per-access alignment facts
  explicit.
- [x] `B5` `[T]` Constrain compiler policy and vector compiler policy as one
  legal matrix. `StencilScheduleRejectCompilerMatrix` is now emitted by the
  artifact planner for incoherent vector schedules, including clang plus
  gcc-autovec, SystemC plus handwritten C vectors, and non-gcc copy-patch
  stencil vector schedules.

### Stringly-Typed Joins

- [x] `C1` `[K]` Replace `StencilAccessVectorFact.access_name [str]` with a
  typed access reference, access id, or nested facts inside `StencilAccess`.
  `StencilAccessVectorFact` now carries `access [StencilAccessRef]`; planners,
  proof obligations, BC, and MC materializers use that typed ref instead of a
  string join.
- [x] `C2` `[K]` Replace `StencilRejectMissingProof.reason [str]` with a typed
  proof obligation kind. `StencilRejectMissingProof` now carries
  `obligation [StencilProofObligationKind]`, so missing-proof rejects identify
  the exact required proof.
- [x] `C3` `[K]` Rework `StencilParam` as a typed parameter product or boundary
  metadata. `StencilParam` was removed instead: descriptor sink/body/access
  fields already own the typed semantic fields, and `StencilAbi` owns call ABI.
  There is no longer a name-keyed descriptor metadata bag.

### Schema Completeness Gaps

- [x] `D1` `[C]` Decide and encode binary `Div`, `Mod`, `Shl`, and `Shr`.
  Stencil binary ops now include division, modulo, left shift, logical right
  shift, and arithmetic right shift. Core lowering maps `BinDiv`, `BinRem`,
  `BinShl`, `BinLShr`, and `BinAShr`; planner/rule support constrains modulo
  and shifts to integer-like lanes. MC zip-map/zip-reduce materialization uses
  structured `llbl.c` expression nodes with trap guards for integer div/rem and
  masked shift counts; LuaTrace BC uses explicit C-truncating integer div/rem
  helpers for parity.
- [x] `D2` `[C]` Add a select/blend element operator for masked vector bodies,
  branchless partition, and predicate-controlled transforms. `StencilSelect`
  is now a first-class vocab/descriptor with `dst`, `cond`, `then_xs`, and
  `else_xs` accesses, plus `StencilOpSelect` in the element-operator surface.
  Artifact planning, support-matrix coverage, LuaTrace BC, and MC emission all
  materialize predicate-controlled select/blend arrays.
- [x] `D3` `[C]` Complete the represented producer/unfold shape layer beyond
  1D. `StencilProducerShape` now represents and shape-validates `Range1D`,
  `RangeND`, `WindowND`, and `TiledND`; the support matrix marks the shape
  layer as covered. `copy_patch_mc` now materializes forward `RangeND`,
  center-domain `WindowND`, and forward `TiledND` producers for generic
  `ApplyN`, domain/axis `ReduceN`, and axis-aware `ScanN` through LLBL.C
  producer loops. The LuaTrace bytecode path materializes positive forward
  `Range1D` and forward `RangeND` for generic `ApplyN`, domain/axis `ReduceN`,
  axis-aware `ScanN`, `FindN`, and sequential/unique `ScatterReduceN`, while
  still rejecting `WindowND` and `TiledND` with typed producer facts.
- [x] `D4` `[C]` Add range, compound, and float-class predicates, or document
  their rejection. `StencilPredicate` now includes typed range predicates,
  compound `and`/`or`/`not`, and float `isnan`/`isinf`/`isfinite` predicates.
  Artifact planning validates them recursively, the support matrix tracks every
  predicate constructor, and both BC and MC materializers emit them.
- [x] `D5` `[C]` Add exact static trip-count facts. `StencilTripCountExact`
  is now a schedule fact, artifact planning accepts `exact_trip_count` /
  explicit trip-count facts, proof obligations are emitted for exact counts,
  and LuaTrace consumes exact counts as no-tail evidence when divisible by the
  selected loop group.
- [x] `D6` `[C]` Add schedule-level rejects. `StencilScheduleReject` now has
  typed variants for unsupported features, illegal lane counts, unprovable
  tails/alignment, compiler matrix failures, and requested/realized mismatch;
  artifacts carry those rejects next to realized schedule evidence.
- [x] `D7` `[C]` Record schedule candidates, costs, and winner provenance.
  `StencilSelection` now carries `StencilScheduleSelectionProvenance` with a
  winner name, selection origin, candidate list, candidate status, estimated
  cost, schedule rejects, and reason text. The LuaJIT backend populates selected
  stencil entries with the chosen schedule plus viable scalar fallback where
  applicable.
- [x] `D8` `[C]` Add artifact build-input fingerprints. `StencilArtifact` now
  carries a typed `StencilArtifactFingerprint` computed from generator version,
  descriptor/instance identity, schedule, compiler policy/flags/target,
  provider, symbol, and C signature. Realizing an artifact under a different
  provider recomputes the fingerprint, so BC and MC cache identities diverge.
- [x] `D9` `[C]` Capture compiler diagnostics and vectorization remarks on the
  artifact so "did it vectorize, and why not" is queryable from schema facts.
  `StencilArtifact` now carries typed diagnostics with severity/source/message;
  artifact realization lifts construction evidence, compiler remarks, and
  disassembly classifications into diagnostics, and BC/MC tests assert those
  facts are present.

### Orphans And Minor Schema Issues

- [x] `E1` `[M]` Delete or wire `StencilId`. The unused `StencilId` product was
  deleted; descriptor/artifact identity remains on `StencilInstanceId`,
  `StencilSymbolId`, and `StencilArtifactFingerprint`.
- [x] `E2` `[M]` State or unify the relationship between `StencilDescriptor`
  params and `StencilAbi.params`. Descriptor params were deleted; ABI params
  remain the sole call-boundary representation.
- [x] `E3` `[M]` Make `StencilArtifact.c_signature` provider-dependent or
  document that every provider seals through a C ABI. Decision: every current
  stencil artifact provider seals through the same C-callable ABI surface, so
  `c_signature` remains mandatory for both `copy_patch_bc` and `copy_patch_mc`.
- [x] `E4` `[M]` Decide whether producer step is compile-time only. Producer
  step is intentionally a positive compile-time constant for currently
  materialized 1D range producers; runtime stride belongs to
  `StencilLayoutViewDescriptor`, not `StencilProducerShape`. Backward and
  nonpositive 1D producers are represented but rejected with typed
  unsupported-producer reasons, and copy overlap direction remains owned by
  `StencilCopySemantics`.
- [x] `E5` `[M]` Add an index access role. `StencilAccessIndex` now separates
  gather/scatter index streams from ordinary data reads, the planner marks
  those accesses readonly for vector facts, and support-matrix tests assert
  gather/scatter descriptors carry the index role.

### Schema Closure Priority

- [x] First close `A1`: alias must be relational, not unary.
- [x] Then close `B1`: descriptor must become a skeleton-keyed sum.
- [x] Then close `A4` and `D6`: realized schedule evidence and schedule rejects.
- [x] Then close `A6`: proof provenance and proof obligations.
- [x] Then close `A2` and `A3`: arithmetic and comparison semantics.
- [x] Then close `C1` and `C2`: remove string joins from access facts and proof
  rejects.

Open gate question:

- [x] Decide whether `KernelProof`s are always discharged by checker/contract
  layers, or whether schedules may carry author-asserted proofs. If hand
  assertions are allowed, vector schedules must be marked as an explicit trust
  boundary. Current schema makes the trust boundary explicit through
  `StencilProofOrigin`: checker-derived, boundary-contract, or
  author-asserted.

## Type Family Gaps

- [x] Decide the intended stencil element universe: the compiler classifies the
  whole representable `CodeType` surface except `void`.
- [x] Add first-class test coverage that non-scalar types select only the
  type-generic stencil operations that are meaningful today.
- [x] Support `CodeTyVector` as an element family for copy/gather/scatter and
  identity-map selection.
- [x] Support `CodeTyNamed` record elements as whole-record copy/gather/scatter
  and identity-map elements.
- [x] Support `CodeTyArray` elements as whole-array copy/gather/scatter and
  identity-map elements.
- [x] Support `CodeTyDataPtr` elements for pointer-array copy/gather/scatter and
  identity-map use cases.
- [x] Support descriptor-valued elements for copy/gather/scatter and
  identity-map: slices, views, byte spans, and closures.
- [x] Add BC runtime materialization coverage for representative non-scalar
  copy/gather/scatter and identity-map cells: pointer, fixed-array, and
  descriptor-valued elements.
- [x] Add MC runtime materialization coverage for pointer-valued
  copy/gather/scatter and identity-map cells.
- [x] Add MC runtime materialization coverage for named aggregate, imported C
  aggregate, and descriptor-valued copy/identity cells.
- [x] Add MC runtime materialization coverage for fixed-array, closure, imported
  C function-pointer, and vector element cells.
- [ ] Add widening reductions, or document that reductions require
  `elem_ty == result_ty`.
- [ ] Add widening map-reduce and zip-reduce, or document that mapped/result
  types must match through the current reduction contract.
- [ ] Add mixed-type zip-map, or document that lhs/rhs/result types must match.
- [ ] Add mixed-type zip-compare where lhs/rhs differ but comparison is legal.
- [ ] Audit all cast stencil combinations against `MachineCastOp`; current tests
  cover identity and selected numeric casts, not the full cast matrix.
- [ ] Add explicit bool semantics for map/reduce/count beyond the currently
  selected bool8 cells.

## Stencil Vocab Gaps

- [x] Treat "fold" as an architecture decision. Decision:
  `fold` is source/kernel vocabulary for loop-local accumulation, lowering
  through `KernelEffectFold` to `StencilSinkReduce(..., StencilReduceFold(...))`.
  Do not add a first-class `StencilFold` vocab unless a future semantic
  distinction cannot be represented by the current reduce sink. See
  `docs/LALIN_NATIVE_LOOP_ARCHITECTURE.md`.
- [ ] Add complete tests for every `StencilVocab` constructor in
  `schema/stencil.lua` against selection, artifact planning, LuaTrace emission,
  and MC materialization.
- [ ] Add reduce tests for every supported type/reduction pair at artifact
  emission level, not only rule-selection level.
- [ ] Add scan tests for every supported reduction pair; current scan coverage is
  much thinner than reduce.
- [ ] Add exclusive scan coverage in end-to-end lowering and materialization.
- [ ] Add count coverage for every predicate kind, not only nonzero/selected
  const predicates.
- [ ] Add find coverage for every predicate kind and every supported scalar type.
- [ ] Add partition coverage for every predicate kind and for stable/unstable
  semantics.
- [ ] Implement and test unstable partition semantics if it should differ from
  stable partition.
- [ ] Implement and test all copy semantics:
  no-overlap, may-overlap-forward, may-overlap-backward, memmove.
- [ ] Implement and test all scatter conflict semantics:
  unique-indices, last-write-wins, conflict-undefined.
- [ ] Decide whether gather/scatter should support non-i32 index element types
  beyond the current selected cases.
- [ ] Add gather/scatter runtime tests for all allowed index types.
- [ ] Add map-reduce and zip-reduce coverage for min/max and bitwise reductions,
  not only add-oriented default interned stencils.
- [ ] Add map/zip-map coverage for all unary/binary operators:
  identity, neg, bitnot, boolnot, add, sub, mul, and/or/xor, min, max.
- [ ] Add compare/zip-compare coverage for all `CmpOp` values.
- [ ] Add predicate coverage for all predicate constructors:
  nonzero, eq/ne/lt/le/gt/ge const.

## Descriptor And Layout Gaps

- [x] Build a vocab-by-layout matrix and decide which cells are supported,
  rejected, or intentionally unreachable. The matrix is now basis-shaped:
  `ApplyN`, `ReduceN`, and `ScanN` are the supported generated consumers;
  old fixed vocab names are frontend/optimization rewrites, not materializer
  shapes.
- [x] Complete contiguous layout coverage for every supported generated basis
  consumer.
- [x] Complete indexed layout coverage for every supported generated basis
  consumer. Indexed layouts now carry a typed `StencilAccessRef` to the index
  stream instead of a string-side-table convention.
- [x] Remove in-place as a layout axis. In-place behavior is represented by
  `StencilAccessReadWrite`; layouts describe address formation only.
- [x] Complete view descriptor coverage for every supported generated basis
  consumer.
- [x] Complete slice descriptor coverage for every supported generated basis
  consumer.
- [x] Complete byte-span descriptor coverage for every supported generated
  basis consumer.
- [x] Complete field-projection coverage for every supported generated basis
  consumer through record-pointer ABI projection.
- [x] Complete SoA component coverage for every supported generated basis
  consumer through component-buffer ABI projection.
- [x] Add nested layout coverage for every supported generated basis consumer:
  field projection over view/slice, SoA over view/slice, and indexed read/write
  over view/slice/byte-span descriptor parents.
- [ ] Add dynamic-stride runtime tests for every vocab that accepts view
  descriptors.
- [ ] Add constant-stride view runtime tests for every vocab that accepts view
  descriptors.
- [ ] Add zero-length descriptor tests for slice/view/byte-span.
- [x] Add negative-stride or backward-domain decision: backward Range1D is
  represented as positive descriptor step plus backward producer order and is
  materialized for primary-index store/copy, fold, and scan loops. Reverse-affine
  1D destination indexes are represented as explicit affine access layouts.
- [ ] Add descriptor aliasing tests for copy, map, in-place map, partition, and
  scatter.
- [ ] Add tests that descriptor lengths dominate loop bounds where applicable.
- [ ] Add tests that descriptor data/len/stride extraction survives frontend
  lowering into stencil layout facts.

## Producer And Scheduling Gaps

Producer-shape completion is the current gate before returning to the other
open backend checkboxes. The goal is not "a 1D backend"; the materialization
paths remain `copy_patch_bc`, `copy_patch_mc`, and emitted copy+residual
artifacts. The gate is
to make every represented producer shape either fully executable across the
appropriate materializers or rejected with typed, stable facts at the exact
unsupported boundary.

Gate closure means: `Range1D`, `RangeND`, `TiledND`, and `WindowND` are all
represented, lowered or explicitly rejected per materializer, covered by focused
runtime tests, reflected in the support matrix, considered by the bank generator,
and benchmarked where they produce executable MC code.

### Producer Shape Completion Gate

- [x] Replace the old domain axis with `StencilProducer` /
  `StencilProducerShape` in the schema.
- [x] Rename the remaining array/topology-biased ASDL surface:
  `StencilSinkEmitArray` became `StencilSinkStore`,
  `StencilApplyMode` became `StencilStoreMode`, and
  `StencilAccessTopology` became `StencilAccessLayout` with the access field
  renamed from `topology` to `layout`. Arrays are now one layout/ABI case, not
  the descriptor's default meaning.
- [x] Represent `Range1D`, `RangeND`, `WindowND`, and `TiledND` as first-class
  producer shapes.
- [x] Split shape validation from materializer support:
  `producer_shape_supported` answers whether the shape is well-formed, while
  `producer_materialized` answers whether a materializer can execute it.
- [x] Validate producer axes, positive steps, window counts, window extents, and
  tile sizes before materialization.
- [x] Preserve typed unsupported-producer facts instead of falling back to an
  accidental stride-1 loop.
- [x] Keep forward `Range1D` working across existing BC, MC, and bank paths;
  backward `Range1D` now works in the LuaJIT MC/native artifact path for
  primary-index store/copy, fold, and scan materialization, plus reverse-affine
  1D store/copy and scan destination layouts.
- [x] Materialize forward `RangeND` in `copy_patch_mc` and LuaTrace BC for
  generic `ApplyN`, domain/axis `ReduceN`, and axis-aware `ScanN` through
  nested producer loops.
- [x] Add generic `ScanN` as the third SOAC-basis materializer. `ScanN` carries
  a typed axis; MC and BC both materialize `Range1D` axis 1 and forward
  `RangeND` rank-N axis scans.
- [x] Guard `copy_patch_bc` so unsupported producer plans cannot silently
  execute as linear `start/stop` loops.
- [x] Add a shared producer execution-plan object to artifact shapes so every
  generic materializer consumes `producer`, not a loose `stride` field.
- [x] Remove/demote fixed `copy_patch_mc` stencil shapes as semantic
  materializers. `map`, `zip_map`, `select`, `compare`, `zip_compare`, `cast`,
  `copy`, `fill`, `gather`, `scatter`, `in_place_map`, `count`, `find`,
  `partition`, and plain `reduce` must become generated `ApplyN`/`ReduceN`/
  `ScanN` cells or explicit optimization rewrites after the generic descriptor
  exists. The MC intern bank is now generated-only; `artifact_shape` projects
  descriptor bodies to `apply_n`, `reduce_n`, or `scan_n`
  instead of selecting fixed materializer shapes.
- [x] Close the represented sink modes in the generic MC materializer.
  `StoreElementwise`, `StoreCopy`, `StoreScatter`, and read/write in-place
  stores lower through `apply_n`; `ReduceFold` lowers through `reduce_n`;
  `ReduceCount` lowers through `reduce_n` with an internal zero identity;
  `ReduceFind` lowers through `find_n`; `StorePartition` lowers through
  `partition_n`; and `Scan` lowers through `scan_n`.
- [x] Remove legacy string-concat C emitters from `stencil_c.lua`. C stencil
  materialization is now authored through the `llbl.c` dialect nodes for
  functions, params, loops, branches, expressions, and statements.
- [x] Add forward `RangeND` runtime tests for every currently materialized
  basis-backed shape that can be expressed over row-major linear storage:
  `ApplyN`, domain-scope `ReduceN`, axis `ReduceN`, and axis `ScanN`.
- [x] Keep `TiledND` and `WindowND` producers as typed BC rejects with focused
  tests until their BC loops/window-relative bodies are implemented.
- [x] Add non-unit positive producer-step tests for `RangeND` generic shapes.
- [x] Decide backward producer semantics: `Range1D` backward producers execute
  the authored descending interval (`start > stop`) with positive descriptor
  step and `StencilProducerBackward` order. Backward ND/window/tiled axes remain
  represented but rejected at materializer boundaries.
- [x] Design and implement `TiledND` execution semantics for generic MC:
  tile-major outer loops, clipped edge tiles, row-major linearization inside the
  compact logical iteration space, and scalar/vector schedule preservation at
  the body level.
- [x] Materialize `TiledND` in `copy_patch_mc` for generic `ApplyN` and
  domain-scope `ReduceN`.
- [x] Remove fixed `copy_patch_mc` shapes from the producer gate; fixed shape
  names are no longer semantic materializers.
- [x] Keep `TiledND` as a typed BC reject with tests.
- [x] Define current `WindowND` execution semantics: it is an executable
  center-domain producer with validated window metadata and boundary tags.
  Neighbor/window operands remain a future body-expression extension, not a
  producer-shape gap.
- [x] Materialize `WindowND` in `copy_patch_mc` for the generic expression path.
- [x] Add `WindowND` tests for every boundary policy and zero/edge-only window
  extents.
- [x] Keep `WindowND` as a typed BC reject with tests.
- [x] Update `copy_patch_mc_intern_set` so the bank generator intentionally
  includes `Range1D`, `RangeND`, `TiledND`, and `WindowND` producer-shape cells.
- [x] Add emitted-bank tests proving `RangeND`, `TiledND`, and `WindowND`
  producer cells compile into the generated MC bank.
- [x] Update the support matrix so producer rows distinguish shape support,
  BC materialization, MC materialization, and emitted-bank coverage.
- [x] Make reduce and scan sinks rank/scope explicit. `StencilSinkReduce` now
  carries a typed `StencilReduceScope`, and `StencilSinkScan` now carries a typed
  `StencilAxisRef`; rank-N scan is no longer silently treated as a flattened
  stream.
- [x] Define reduce sink scope semantics explicitly in the schema:
  `StencilReduceScopeDomain` is a scalar/control-result full collapse,
  `StencilReduceScopeAxes` is rank-lowering partial reduction with a destination
  access, and `StencilReduceScopeWindow` is window-local pooling with a
  destination access.
- [x] Add typed rejects for unsupported sink scopes/axis sets. Invalid axis
  sets and unsupported materializer/provider combinations now reject through
  `StencilRejectUnsupportedSink` / constructor checks instead of flattening the
  producer.
- [x] Add represented `WindowND` body-relative access semantics.
  `StencilApplyWindowInput` plus `StencilWindowOffset` now names neighbor
  access explicitly; MC materializes boundary-aware neighbor addressing for
  clamp, wrap, zero, and reject policies.
- [x] Materialize rank/scope/window consumers in MC: axis/partial reduce,
  window-local reduce/pooling, rank-N axis scan, and boundary-aware
  window-relative input access.
- [x] Extend BC and emitted-bank coverage for the new rank/scope/window
  consumers. BC now materializes `RangeND` axis reduce and axis scan while
  preserving typed rejects for `WindowND` window consumers and `TiledND`; the
  emitted bank includes deliberate axis-reduce, window-reduce, and
  window-neighbor apply cells in addition to generic producer cells.
- [x] Feed producer shapes from the frontend/lowering pipeline instead of only
  hand-built test descriptors. Lowering now turns counted loops into explicit
  `StencilProducer(StencilProduceRange1D)` descriptors with preserved loop
  bounds; named array helpers and generic N-ary artifact builders both carry
  that producer into descriptor construction.
- [x] Add a typed domain-scoped frontend/lowering producer fact.
  `FlowDomainShape` is the neutral shape vocabulary and
  `FlowDomainShapeFact` is the frontend/lowering fact keyed by `FlowDomain`,
  with proofs and provenance. LuaJIT lowering projects those facts
  into backend-owned `StencilProducerFactSet` values at the stencil boundary.
  Lowering derives machine-call producer arguments from the descriptor shape, so
  named array helpers and generic N-ary helpers share the same producer ABI.
  Surface DSL sugar for authoring domain-shape facts is now a language
  ergonomics task, not a producer backend gap.
- [x] Move producer performance benchmarking out of the shape-completeness gate
  and into the materializer-quality pass: compare `Range1D`, `RangeND`, and
  `TiledND` MC materialization against handwritten C + `gcc -O3` after the
  executable shape surface is stable.
- [x] Producer-shape gate is closed; resume the remaining
  layout, scheduling, bank, metastencil, frontend, and benchmark checkboxes
  below.

- [ ] Add schedule coverage for scalar, unrolled, autovector, and fixed-vector
  schedules across every supported vocab.
- [ ] Add masked-tail vs scalar-tail runtime tests.
- [ ] Add trip-count-multiple facts tests for no-tail lowering.
- [ ] Add vectorization facts tests for alias, alignment, unit stride, and
  reduction reassociation.
- [ ] Decide whether strict float reductions should always reject vector/multi
  accumulator plans or only lower to ordered scalar plans.
- [ ] Add coverage for schedule rejection reasons so failed stencil selection is
  diagnosable and stable.

## Copy-Patch BC/MC Materialization Gaps

- [x] Make the MC intern set generated from an explicit matrix table instead of
  ad hoc hand-enumerated artifact construction. `copy_patch_mc_intern_set` now
  declares explicit vocab/layout cells and generates artifacts from those
  rows.
- [x] Add a test that compares the declared support matrix against the embedded
  MC intern set. `test_copy_patch_mc_intern_set` checks every intern row against
  supported matrix vocab/layout entries and verifies the built bank symbols
  exactly match the intern matrix.
- [x] Add a test that every artifact selected by the default lowering path can
  be found in the embedded MC bank, or is deliberately routed to BC fallback.
  `test_luajit_embedded_mc_coverage` lowers representative default-path
  artifacts and checks embedded-bank symbol/fingerprint coverage; this forced
  scheduled `_v4` intern rows and reusable fingerprint normalization for
  frontend-local `CodeValueId`s.
- [x] Add sharded MC bank generation so larger intern sets are a build
  bottleneck. `tools/gen_lalin_mc_bank.lua` now builds the fixed 1x1 intern set,
  shards it with `LALIN_MC_BANK_JOBS`, and honors `LALIN_MC_BANK_CFLAGS`; the
  parent process builds shards in parallel, emits one C translation unit per
  shard plus a small index C file, and links the same embedded-bank C ABI. The
  old SOAC-order/input-count/target-byte generator knobs were hard-yanked:
  default bank shape is an architectural choice, not a build-time search.
- [x] Decide whether BC and MC banks must have identical logical coverage or
  whether BC is the semantic superset and MC is the fast subset. They must not
  have identical compiled-bank coverage: `copy_patch_bc` is the semantic
  coverage probe and must either materialize a supported schema cell or expose
  the exact typed unsupported cell; `copy_patch_mc` is the fast subset and falls
  back to BC only through an explicit fallback path when a legal cell has no
  fast compiled artifact; the emitted bank is the deployment subset with
  explicit missing/stale-entry diagnostics. The support matrix now encodes those
  roles and makes current BC semantic producer gaps visible instead of implying
  parity.
- [x] Add artifact-shape hashing/versioning so stale bank entries cannot
  silently satisfy changed descriptors. `StencilArtifactFingerprint` now hashes
  structural descriptor/schedule/ABI/proof inputs, and BC/MC realization rejects
  same-symbol bank entries whose stored artifact fingerprint differs from the
  requested artifact.
- [ ] Add coverage for local relocations in every vectorized MC shape, not only
  selected SoA zip-map/zip-reduce cases.
- [ ] Add tests for MC bank generation with view/slice/byte-span dynamic
  descriptors in the single-binary path.
- [x] Add tests that generated embedded MC bank count matches an explicit
  targeted 3x3 intern matrix. `test_lalin_mc_bank_generator` exercises the sharded
  generator, checks the generated C/header shape, and syntax-checks the emitted
  C when `cc` is available. It also checks that an explicit compiled-payload
  target bounds the generated MC payload reported by the generator.
- [ ] Add tests that generated embedded MC bank descriptor/fingerprint sets
  match the intended intern matrix, not only the count and default-path symbols.
- [ ] Add tests that static binary startup rejects or reports missing MC bank
  entries cleanly when a selected fast artifact is absent.

## Copy+Residual Metastencil / Fusion Track

This is a tracked architecture tangent, not a reason to stop the current
materializer fact-consumption pass. The core choice is to build fused
MC bank artifacts as C/LLB.C source-level metastencils and let GCC see the
combined body, not to concatenate already compiled machine-code bytes. Cross-op
optimization only happens if the compiler receives the fused source. The emitted
copy+residual artifact can still use TCC glue around the resulting bank entry.

- [x] Record the primitive-basis decision: the production hand-coded stencil
  family collapses to four primitives: `Apply`, `Reduce`, `Scan`, and
  `ScatterReduce`. Plain `Scatter` remains `Apply` with indexed write layout
  and conflict semantics; `ScatterReduce` owns collision-combine / histogram /
  reduce-by-index semantics.
- [x] Record the derivation rule: non-basis vocabulary is generated from the
  primitive basis, not maintained as independent handwritten production
  lowerings. `Map`, `ZipMap`, `InPlaceMap`, `Copy`, `Fill`, `Cast`, `Compare`,
  `ZipCompare`, `Gather`, and plain `Scatter` are `Apply` configurations;
  `Count`, `Find`, `MapReduce`, and `ZipReduce` are `Apply + Reduce`;
  `Filter` and `Partition` are `Apply + Scan + Scatter`; histogram and
  reduce-by-index families are `ScatterReduce`.
- [x] Refactor the descriptor/support-matrix vocabulary so the real physical
  shape is `producer + body + sink`, and the old operation names become derived
  plan labels or aliases with no separate skeleton authority.
  `StencilDescriptor` is now one structural product: `StencilProducer`
  plus typed accesses, a `StencilBody`, and a `StencilSink`. `Apply`, `Reduce`,
  and `Scan` are recovered from sink/body combinations rather than descriptor
  variants, while the support matrix tracks primitive vocabs separately from
  derived plans.
- [x] Make the hidden unfold explicit. `StencilProducer` owns the physical
  iteration/control generator and carries optional `FlowDomain` provenance only
  as a proof/source anchor; compiled bank identity remains structural through
  descriptor fingerprints, not a separate producer id. The shape layer accepts
  `Range1D`, `RangeND`, `WindowND`, and `TiledND`; `copy_patch_mc` generic
  `ApplyN`, domain/axis `ReduceN`, and axis-aware `ScanN` now consume forward
  `RangeND`, center-domain `WindowND`, and forward `TiledND`, while LuaTrace
  consumes `RangeND` for the same generic rank/scope cases and rejects the
  remaining unsupported producer shapes with typed facts.
- [ ] Replace handwritten non-basis metastencils in production paths with
  generated metastencils from the primitive fragments; keep handwritten versions
  only as benchmarks, regression fixtures, or temporary scaffolding until the
  generated artifacts match or beat them.
- [x] Add expression-backed `ApplyN` descriptors/materializers with input-count
  capped at 4. The current `StencilApplyExpr` tree covers const/input/unary/binary/
  cast/predicate/compare/select expressions, and `apply_n` is tested on
  input counts 0 through 4 through both BC and MC.
- [x] Generate MC bank candidates by SOAC order, not by the old scalar
  depth/input-arity grid. Order `1` emits primitive `Apply`, `Reduce`, and
  `Scan`; order `2` emits `Apply -> Apply`, `Apply -> Reduce`, and
  `Apply -> Scan`; order `3` extends the Apply chain one stage before either
  array output or sink. Input count is a separate coverage axis.
- [x] Stream the actual `StencilApplyExpr` grammar in constructor order, not by
  hand-picked templates.
  The stream covers input, const, unary, binary, predicate, compare, cast, and
  select expressions over the currently consumable scalar surface. Explicit
  compiled-payload targets remain available only as caller-selected probes.
- [x] Let `ScatterReduce` consume a generic `ApplyN` contribution body instead
  of only a single lane-load contribution. The frontend regression now covers
  `dst[idx[i]] += src[i] + rhs[i]`, proving the scatter-reduce sink receives a
  typed binary `StencilApplyExpr` with two read accesses.
- [x] Set the generated MC bank shape to the fixed saturated 1x1 surface. There
  is no default growth generator anymore: SOAC order is 1, input width is 1, and
  wider/fused banks are deferred architecture work rather than hidden build
  knobs. The current fixed profile reports 129,219 entries after
  `ScatterReduce` saturation. The last full vectorized 1x1 run before that
  saturation completed with 16 worker shards: 129,156 embedded entries,
  86,844,681 compiled payload bytes with GCC vectorization enabled, and 0
  patches. A fresh measured payload should be recorded after the next full-bank
  build.
- [x] Replace the old linear-producer-only embedded bank shape with the
  represented producer/body/sink bank. The current bounded default includes
  `Range1D`, `RangeND`, `TiledND`, and `WindowND` producer cells over the
  available scalar Apply/Reduce/Scan/ScatterReduce surface. `ScatterReduce` is
  now generated as a real SOAC sink family over indexed-write destination
  layouts, with scalar ordered schedules only until atomic/privatized lowering
  is implemented.
- [x] Add typed metastencil descriptors and selection facts. A metastencil is now
  a typed DAG of artifact nodes, external/node ports, wires, fusion legality
  facts/rejects, ABI, fingerprint, cover candidates, and deterministic longest
  legal cover selection.
- [x] Add a local selector benchmark:
  `benchmarks/bench_luajit_metastencil_selection.lua` precomputes typed cover
  candidates and measures cover ranking throughput.
- [x] Consume selected metastencil covers in the BC, MC, and emitted-bank
  materializer boundary as typed bank facts. `LJBCStencilBank` and
  `LJMCStencilBank` now own `metastencil_covers`, and the materializers accept
  selected covers/candidates/descriptors as inputs. For the current bounded
  bank family, selected `Apply -> Reduce` covers lower to one fused artifact and
  preserve the selected cover metadata through realization.
- [x] Lower selected `Apply -> Reduce` metastencil covers to one fused executable
  artifact. The selected cover now becomes a single `reduce_n` artifact
  whose body is emitted through `llbl.c` nodes, so GCC sees the composed
  expression and reduction in one function.
- [x] Add a focused materializer benchmark against handwritten C:
  `benchmarks/bench_luajit_metastencil_fused_reduce.lua` builds a width-4
  typed `Apply -> Reduce` cover, verifies it materializes as one fused
  `reduce_n` MC entry, compares it with direct `reduce_n`, and
  compiles the handwritten baseline from `llbl.c`. Quick probe on 2026-06-25:
  `mc fused Apply->Reduce` median 0.069 ms, `mc direct reduce_n` median
  0.064 ms, handwritten `gcc -O3` median 0.066 ms for 120k elements.
- [ ] Optional future budget expansion: extend fused-cover materialization beyond
  the current bounded `Apply -> Reduce` bank family to `Apply -> Apply`,
  `Apply -> Scan`, `Apply -> Scan -> Scatter`, and composed
  `Apply -> ScatterReduce` families when bank size/compile budget can carry
  them.
- [x] Remove the default compiled-payload frontier and the eager-enumerator
  guards. A real unbounded SOAC order-3/input-count-3 profile run was attempted
  and failed before producing a count: LuaJIT reported `not enough memory` after
  80.82 seconds with maximum resident set size around 11.99 GiB.
- [x] Remove the stage-list cache from the grammar profile path so unbounded
  3x3 counting no longer needs to retain every previous stage. Follow-up
  unbounded profile run with a 120-second timeout did not complete a count; it
  was killed by timeout at 120.56 seconds with maximum resident set size around
  7.56 GiB.
- [x] Probe unbounded SOAC order-2/input-count-3. The streaming profile
  completed in 12.49 seconds with 482 MiB max RSS and reported 6,699,539 cells
  with an estimated 1.42 GB compiled payload. Actual unbounded bank generation
  with one worker still failed before compile output: LuaJIT reported `not
  enough memory` after 114.67 seconds with maximum resident set size around
  11.99 GiB.
- [x] Probe unbounded SOAC order-1. Order-1/input-count-1 profiles at 4,955
  cells with an estimated 615,270-byte payload. Order-1/input-count-3 profiles
  at 24,761 cells with an estimated 4,044,000-byte payload and actual bank
	  generation completed in 15.38 seconds with 16 jobs: 24,761 entries,
	  2,178,242 payload bytes, and 256 MiB max RSS. MC banks are now no-hole
	  artifacts, so patch counts are no longer tracked.
- [ ] Replace the recursive eager expression-construction profile with a true
  lazy metastencil enumerator if unbounded SOAC order-3/input-count-3 must
  complete without a caller-provided payload target.
- [ ] Extend grammar-stream saturation beyond the current consumable scalar
  surface: all supported type families, layout/fact/schedule variants,
  gather/scatter/indexed expression forms, and realized-materializer coverage
  checks for every generated constructor family.
- [x] Record the design direction: metastencils are composed source artifacts
  that lower through the normal `copy_patch_mc` bank path after GCC has had a
  chance to optimize across primitive operations.
- [ ] Add a typed metastencil descriptor for small op sequences or DAGs,
  including primitive descriptors, typed wire map, control/loop composition,
  result ABI, and structural identity.
- [ ] Add fusion legality facts for composed aliasing, layout, trip count,
  alignment, integer/float semantics, reduction legality, and proof
  obligations.
- [ ] Extend the support matrix with fusion cells:
  `(producer op, consumer op, type/layout/schedule/facts) ->
  supported/rejected/future`.
- [ ] Add a fusion materializer that emits one LLB.C/GCC source unit from
  primitive descriptor fragments, then interns the compiled machine-code
  artifact as a normal `copy_patch_mc` entry.
- [ ] Add selector support for the longest legal cover over a kernel plan, with
  fallback to primitive stencils and then `copy_patch_bc`.
- [ ] Add metastencil fingerprints that include primitive descriptors,
  wire/control map, legality facts, schedule, compiler target, and compiler
  flags.
- [ ] Add benchmarks against the unfused primitive sequence and handwritten C
  compiled with `gcc -O3`. Current bounded `Apply -> Reduce` has a focused
  direct-materializer benchmark; this remains open for the broader family and
  source-level frontend path.
- [ ] Reuse lessons from the SpongeJIT experiment: typed variant keys, no
  opcode/string descriptor leakage, bank selection by structural key, and
  usefulness/coverage tests.

## LuaTrace Emission Gaps

- [ ] Replace unsupported-expression errors in LuaTrace constant lowering with
  structured rejects.
- [x] Add runtime tests for all supported unary operators in LuaTrace output.
  `test_stencil_apply_n` now realizes BC `ApplyN` artifacts for identity,
  negation, bit-not, and bool-not.
- [x] Add runtime tests for all supported binary operators in LuaTrace output.
  `test_stencil_apply_n` now realizes BC `ApplyN` artifacts for add, sub, mul,
  div, mod, bit-and/or/xor, left/logical-right/arithmetic-right shift, min, and
  max.
- [x] Add runtime tests for all supported reductions in LuaTrace output.
  `test_stencil_apply_n` now realizes BC `ReduceN` artifacts for add, mul,
  bit-and/or/xor, min, and max.
- [x] Add runtime tests for all supported predicates and comparisons in LuaTrace
  output. `test_stencil_predicates_d4` now realizes BC predicate artifacts for
  nonzero, compare-const, range, compound and/or/not, float isnan/isinf/isfinite,
  and all six zip-compare operators.
- [x] Add byte-exact tests for byte-span copy/fill/count/find/compare.
  `test_copy_patch_luatrace` now realizes byte-span layout artifacts for all
  five shapes and checks the exact `uint8_t` results.
- [x] Add tests for dynamic stride parameter ordering in emitted LuaTrace
  functions. `test_copy_patch_luatrace` now checks the generated multi-access
  dynamic-stride ABI order and executes a strided zip-map with distinct
  dst/lhs/rhs stride parameters.
- [x] Add tests for field-projection source and destination access in LuaTrace.
  `test_copy_patch_luatrace` now realizes an AoS field-projection map that
  reads `src[i].left` and writes `dst[i].sum`.
- [x] Add tests for SoA component source and destination access in LuaTrace.
  `test_copy_patch_luatrace` now realizes a SoA zip-map that reads two component
  buffers and writes the destination component buffer.
- [x] Add tests for primitive plans: `ffi.copy`, `ffi.fill`, branch predicates,
  numeric predicate fast paths, scatter plans, and reduction plans.
  `test_copy_patch_luatrace` asserts the inspectable LuaTrace plans for copy,
  fill, count, numeric compare, scatter conflict modes, and ordered reductions.
- [ ] Add tests for grouped/unrolled loops with tails for every supported shape.

## Frontend-To-Stencil Lowering Gaps

- [ ] Implement the full native-loop architecture from
  `docs/LALIN_NATIVE_LOOP_ARCHITECTURE.md`: source native loops author typed
  `Code`/`Flow`/`Kernel` facts, and stencil descriptors are produced only by the
  existing kernel-to-stencil projection.
  - [x] Assignment/apply milestone: `lln.loop` + positive Range1D `lln.range`
    lowers to ordinary typed CFG, authors `FlowDomainShapeFact` and
    `FlowDomainIntentNativeLoop`, and reuses the existing store stencil path.
  - [x] Add source syntax and typed lowering for `lln.fold`.
  - [x] Add source syntax and typed lowering for `lln.scan`.
  - [x] Add negative-step Range1D authoring and materialization; Flow records
    `FlowDomainBackward`, descriptors preserve `StencilProducerBackward`, and
    primary-index store/copy, fold, and scan loops emit backward Range1D
    artifacts. Reverse-affine 1D destination indexes such as
    `dst[(n - 1) - i]` emit through `StencilLayoutAffine1D`.
  - [x] Support the current reducer vocabulary in `lln.fold`/`lln.scan`:
    add, mul, bit-and, bit-or, bit-xor, min, and max.
  - [x] Add `lln.range_nd` parsing as the explicit multi-axis syntax trigger.
  - [x] Add executable `lln.range_nd` lowering for zero-based forward domains:
    the CFG uses a flat induction with generated coordinate bindings, Flow
    records `FlowDomainShapeRangeND`, and the exact 2D row-major `i * w + j`
    form normalizes to the primary induction for store and full-domain fold
    stencil selection.
  - [x] Add explicit `lln.scan` axis syntax for `lln.range_nd`; missing axes
    reject at the frontend, and generated scan loop headers feed a typed
    `StencilAxisRef` through `KernelEffectScan` into `StencilSinkScan`.
  - [x] Generalize zero-based, unit-step ND primary-index recognition beyond the
    old 2D-only row-major normalization. Source `lln.range_nd` now recognizes
    compact row-major expressions at rank 1 and higher, so rank-3 forms like
    `((i * b + j) * c) + k` feed the primary producer path.
  - [ ] Generalize ND affine index recognition for non-zero starts, non-unit
    producer steps, and non-row-major layout expressions.
  - [x] Add tiled and windowed multi-index authoring sugar. `lln.tiled_nd` and
    `lln.window_nd` are public producer heads; lowering records typed
    `FlowDomainShapeTiledND` / `FlowDomainShapeWindowND` facts and projects them
    into stencil producers.
- [ ] Reconcile the remaining frontend-to-rich-backend gaps against the current
  backend surface:
  - [ ] ND affine indexing beyond compact row-major: non-zero starts and
    non-unit producer steps are recognized for row-major compact source indices
    like `((i - start) / step) * trip + ...`; fixed-shape column-major
    expressions such as `j * 2 + i` now lower to typed `StencilLayoutAffineND`
    and execute through MC/C. Dynamic coefficients such as `j * h + i`,
    broader affine normalization, and BC/LuaTrace coverage remain open.
  - [x] Source-level window-neighbor syntax that lowers to typed
    `StencilApplyWindowInput` instead of only testing direct descriptors.
    Inside `lln.window_nd`, ordinary 1D neighbor indexing such as `xs[i - 1]`
    is recognized as a window-relative input and materialized by MC.
  - [x] Decide and implement source semantics for `lln.scan` over `lln.tiled_nd`.
    It is an axis scan over the logical domain, with prefix state scoped by the
    non-scan axes; tile shape is a traversal/materialization policy, not a
    prefix-reset scope. `test_luajit_artifact_tiled_scan_dsl` executes the
    source path, while missing axis selection remains rejected in a focused
    test.
  - [x] Feed source-level select/blend bodies into generic `ApplyN`.
    `test_luajit_artifact_from_dsl` now lowers `select (lhs[i] :gt (0))(lhs[i])(rhs[i])`
    to a `StencilApplySelect` descriptor and executes it.
  - [x] Feed source-level bitwise/remainder/shift/min/max and deeper mixed
    expression bodies through generic `ApplyN` coverage tests.
    `ValueExprRem` now preserves remainder separately from division,
    bitwise/shift expressions flow through `ValueExprBinary`, and
    `test_luajit_artifact_from_dsl` executes authored `%`, `shl`, `band`,
    `bor`, `bxor`, `min`, and `max` loops selected as generic `ApplyN`.
  - [ ] Predicate composition from source: backend predicates support
    range/and/or/not/float-class, but source short-circuit `and`/`or` lowers as
    control flow and needs a pure-predicate normalization/design before it can
    become `StencilPredAnd`/`StencilPredOr`.
  - [x] Scatter-reduce can consume generic `ApplyN` contribution bodies from
    source for the current reducer vocabulary. Immediate RMW forms over
    `add`, `mul`, bitwise `and`/`or`/`xor`, and select-shaped `min`/`max` are
    selected and executed; `dst[idx[i]] += src[i] + rhs[i]` proves the sink
    receives a typed binary contribution body, not only a single lane load.
  - [ ] Generalize source scatter-reduce recognition beyond immediate
    lane-load-shaped destination recurrence: nested reducer wrappers,
    user-authored conflict/atomic/privatized modes, and richer index/update
    facts still need source syntax or checker inference.
  - [ ] Feed the full schedule/proof surface from source contracts: alignment,
    exact/multiple trip count, vector schedule hints, and proof-origin controls.
- [ ] Add end-to-end DSL tests for every supported vocab, not only direct
  artifact-plan tests.
- [ ] Add end-to-end DSL tests for view, slice, byte-span, field projection, and
  SoA contracts for every supported vocab.
- [ ] Add tests that rejected stencil opportunities fall back to generic code
  with a stable reject reason.
- [ ] Add tests for loops with multiple stores/reductions to ensure the selector
  does not silently choose a wrong single-stencil plan.
- [ ] Add tests for reductions returned through different control paths.
- [ ] Add tests for loops with non-primary indexing that should become gather or
  scatter.
- [ ] Add tests for read/write effects and alias contracts controlling copy,
  in-place map, scatter, and partition selection.
- [ ] Add tests for function contracts: bounds, readonly, writeonly, noalias,
  invalidate, preserve, same_len, SoA component.

## Diagnostics And Architecture Gaps

- [ ] Replace stringly reject reasons with ASDL reject facts for stencil
  selection, artifact planning, LuaTrace emission, and MC bank lookup.
- [x] Add a single support matrix file that declares supported, rejected, and
  future cells across type family, vocab, layout, schedule, and materializer.
- [x] Add a test that the support matrix and artifact planner agree.
- [x] Add a test that schema additions fail until the support matrix is updated.
- [ ] Drain every `future`/temporary `rejected` support-matrix cell: either
  implement the missing lowering/materialization/test coverage, or promote the
  rejection to a permanent typed design decision with explicit docs and tests.
- [ ] Decide whether `StencilProviderC` still represents source C stencils or
  whether the provider names should become `copy_patch_bc`/`copy_patch_mc`
  aligned.
- [ ] Rename or document `StencilArtifactPlan` if its role is now stencil bank
  artifact construction rather than generic C artifact planning.
- [ ] Decide whether descriptors are runtime ABI facts, artifact identity facts,
  or both; currently they serve both roles.
- [x] Document the fast emitted artifact as copy+residual: `copy_patch_mc`
  installs GCC-built bank stencils, TCC compiles only the residual glue, and
  `copy_patch_bc` remains the bytecode/semantic path.

## After Schema Closure Meta-Tasks

Once the `A`/`B`/`C`/`D`/`E` gap register is closed, the work splits into two
larger validation/refinement phases. These are meta-tasks and should be divided
into smaller tracked tasks as the concrete failures become visible.

### 1. Consume the schema richness in every materializer

- [ ] Audit all three materialization paths and confirm every new stencil fact,
  descriptor field, layout, predicate, operator, schedule fact, proof
  obligation, realized schedule fact, and reject fact is either consumed in the
  best available way or deliberately rejected with a typed reason.
- [x] Add a materializer fact-consumption matrix that maps every
  `LalinStencil` schema fact to `copy_patch_bc`, `copy_patch_mc`, and the
  emitted C/single-binary bank path.
- [x] Make stale bank reuse impossible: realization must compare requested
  artifact fingerprints against the bank entry artifact before loading or
  installing code. Fingerprints now include structural descriptor, schedule,
  ABI, and proof inputs instead of only coarse vocab/schedule labels.

#### Materializer Fact-Consumption Matrix

Legend: `consume` means the fact changes emitted code, install behavior, or
plan shape; `reject` means the path returns a typed unsupported cell; `record`
means the fact is preserved for audit but does not yet drive lowering.

| Schema surface | `copy_patch_bc` | `copy_patch_mc` | emitted copy+residual artifact | Remaining work |
| --- | --- | --- | --- | --- |
| Descriptor producer/body/sink / vocab | validate all represented producer/body/sink descriptors; materialize current BC subset and typed-reject missing semantic cells | consume all shape-supported C stencil shapes; materialize current fast subset | record/intern selected shapes | [x] Generate MC intern set from the support matrix, not hand enumeration. |
| Producer | materialize forward/backward `Range1D` plus forward `RangeND`; reject represented window/tiled producers with typed facts | materialize forward/backward `Range1D`, forward `RangeND`, center-domain `WindowND`, and forward `TiledND` for generic `ApplyN`, domain/axis `ReduceN`, and axis `ScanN` | intern producer cells for generated SOAC combinations plus deliberate rank-specific probe cells for axis/window behavior | [x] Add deliberate emitted-bank cells for axis/window reduce and window-neighbor apply. |
| Sink rank/scope | materialize domain reduce, `Range1D` axis-1 scan, and `RangeND` axis reduce/scan; reject window/tiled producers | materialize domain reduce, axis/partial reduce, window-local reduce, and rank-N axis scan | bank records domain reduce, generated rank-N scan, and deliberate axis/window reduce cells | [x] Add emitted-bank coverage for axis/window reduce cells. |
| Window body offsets | represented as `StencilApplyWindowInput`; BC rejects `WindowND` producer shapes | MC consumes boundary-aware window-relative access expressions | bank includes deliberate window-neighbor apply cell | [x] Add emitted-bank cells and BC typed-reject tests for window-relative bodies. |
| Layout | consume contiguous, view, slice, byte-span, field, SoA, indexed, scalar | consume same through C access expressions | partial dynamic-descriptor coverage | [ ] Add embedded-bank tests for view/slice/byte-span/field/SoA descriptors. |
| Access roles | consume read/write/readwrite/reduce/index in access plans | consume read/write/readwrite/reduce/index in generated C signatures/accesses | record through artifacts | [ ] Add index-role bounds/alias tests for gather/scatter in both banks. |
| Alias facts | consume noalias for BC copy primitive legality | consume noalias as C `restrict` where legal | record through artifact fingerprint | [ ] Benchmark alias-driven gather/scatter/copy materialization against handwritten C. |
| Alignment facts | record in BC plan; used for fingerprint/proof obligations | consume as C alignment assumptions where emitted | record through artifact fingerprint | [ ] Add runtime/disassembly checks that alignment facts affect MC codegen. |
| Unit-stride facts | consume to enable grouped LuaTrace plans | consume through generated access shape | record through artifact fingerprint | [ ] Add negative tests where non-unit stride blocks grouping/vectorization. |
| Trip-count facts | consume multiple/exact facts for no-tail grouped lowering | record/request through schedule/proofs | record through artifact fingerprint | [ ] Add MC realized-schedule evidence for exact/multiple trip-count exploitation. |
| Predicate surface | consume range/compound/float-class predicates | consume range/compound/float-class predicates | partial intern coverage | [ ] Add embedded-bank predicate coverage for every predicate constructor. |
| Operator surface | consume scalar unary/binary/cast/select/reduction ops | consume C emission for supported ops | partial intern coverage | [ ] Add bank coverage for every supported op/type/materializer cell. |
| Schedule facts | consume scalar/unrolled/autovector/fixed-vector as trace grouping | consume scalar plus fixed-vector realization evidence | record bank entries | [ ] Compare requested vs realized MC vectorization from compiler reports/disassembly. |
| Proof obligations | record and fingerprint; consume selected facts for legality checks | record/fingerprint; consume alias/alignment when emitted | record through artifacts | [ ] Reject unsafe schedules when required proof obligations are absent. |
| Realized schedule | consume into installed artifact diagnostics/rejects | consume compiler/disassembly construction evidence | record through bank entry artifacts | [ ] Add query tests over emitted-bank realized schedule metadata. |
| Reject facts | record selection/planning rejects | record selection/planning rejects | partial startup visibility | [ ] Make single-binary startup report missing/rejected intern cells with typed facts. |
| Artifact fingerprint | consume before BC load | consume before MC install | record in bank entry artifacts | [x] Reject same-symbol stale bank entries before code load/install. |
| Metastencil descriptor | consume selected covers as typed bank facts; current bounded `Apply -> Reduce` family lowers to one fused artifact | consume selected covers as typed bank facts; current bounded `Apply -> Reduce` family lowers to one fused artifact | fingerprint selected cover on the typed bank | [ ] Optional budget expansion: extend fused-cover lowering beyond the current bank family. |

- [x] Remove the raw C preamble escape from the stencil C emitter. MC C source
  now accepts only structured `llbl.c` declaration nodes through `c_decls`;
  LuaJIT FFI declarations are a separate `ffi_preamble` boundary on the loaded
  bank record. `llbl.c` also has a first-class `c.fnptr` type so non-scalar
  stencil support structs no longer need raw C declarations.
- [ ] Treat `copy_patch_bc` as the semantic coverage probe: it should either
  materialize the full supported schema surface or expose the exact missing
  materialization cell. The support matrix now names this as the policy and
  records the current producer gaps: `WindowND` and `TiledND` are represented
  schema cells that BC still typed-rejects.
- [x] Add LuaTrace/BC materialization or a typed unsupported-cell reject for
  `scatter_reduce_n`. LuaTrace now materializes sequential/unique
  `scatter_reduce_n` for `Range1D` and forward `RangeND`, matching the MC/C
  emitter. Atomic and privatized scatter-reduce modes are represented in ASDL
  but reject before emission until real atomic RMW or private-bin merge lowering
  exists.
- [ ] Treat `copy_patch_mc` as the fast-path probe: it should exploit the new
  facts for scheduling, aliasing, alignment, vectorization, gather/scatter,
  select/blend, reductions, and descriptor-aware access patterns where doing so
  can close or beat handwritten C.
- [ ] Treat the emitted C/single-binary bank path as the deployment probe: it
  must intern the intended BC and MC banks, preserve artifact identity, and make
  missing or stale materialization visible.
- [x] Keep full embedded-bank build/link tests out of the default `code_ir`
  runner. `tests/run.lua` now skips `test_lalin_binary.lua` and
  `test_luajit_embedded_mc_coverage.lua` unless `LALIN_RUN_SLOW=1`, because
  those tests build or link the full embedded MC bank and can dominate memory
  and wall time on normal test runs.
- [ ] Update the benchmark corpus so it covers each newly expressible stencil
  family and layout, including negative/control cases where a materializer
  should reject.
- [x] Add the first focused materializer-consumption probe for the current
  bounded metastencil family: width-4 `Apply -> Reduce` fused MC versus direct
  MC versus handwritten GCC C. The probe confirmed selected-cover metadata is
  consumed by the MC bank boundary; the generated MC bank default now leaves GCC
  vectorization enabled so generated asm is a real performance signal.
- [ ] Run the benchmarks against handwritten C compiled with `gcc -O3`, record
  the results, and interpret each gap as either bad materialization, missing
  schedule information, frontend information loss, or an expected target limit.
- [ ] Feed benchmark findings back into the materializers and schedule/fact
  schema instead of treating benchmark numbers as a separate report.

### 2. Make the frontend feed the schema fully

- [ ] Audit frontend lowering to check whether source programs provide every
  fact the stencil schema can now represent: alias relations, access roles,
  layout, index streams, predicate semantics, integer/float semantics,
  reduction identity/proofs, trip-count facts, schedule hints, and boundary
  contracts.
- [ ] Add end-to-end DSL tests proving those facts survive from source program
  through typecheck/kernel facts/stencil descriptors/materializer selection.
- [ ] Identify schema facts that only direct artifact constructors can currently
  express, then add frontend syntax, contracts, inference, or checker-derived
  facts so ordinary Lalin code can feed them.
- [ ] Split frontend gaps into inference gaps, source-contract gaps, typechecker
  gaps, kernel-plan gaps, and lowering-rule gaps so fixes stay local.
- [ ] Re-run the benchmark corpus from source-level Lalin, not only direct
  artifact-plan construction, and compare against the direct-materializer
  results to find frontend information loss.

## Suggested Closure Order

- [ ] First close the `LalinStencil` schema soundness and thesis tier:
  `A1`, `B1`, `A4`/`D6`, `A6`, `A2`/`A3`, then `C1`/`C2`.
- [x] Write the explicit support matrix and make tests enforce it.
- [ ] Complete selection-rule coverage against the support matrix.
- [ ] Then complete artifact-plan construction against the same matrix.
- [ ] Then complete LuaTrace emission/runtime tests.
- [x] Then complete the first generated MC intern-bank pass from the matrix.
- [ ] Then expand the generated MC intern bank from SOAC order
  saturation into legality-driven primitive composition / metastencil DAG
  coverage.
- [x] Add typed metastencil descriptors, fusion legality facts, deterministic
  longest legal cover selection, and metastencil fingerprints.
- [x] Add a selector-level metastencil benchmark so cover-ranking changes have
  a local performance probe before full materializer benchmarks.
- [x] Feed selected metastencil covers into `copy_patch_bc`, `copy_patch_mc`,
  and emitted-bank materializers as typed bank facts instead of treating them
  only as planning facts.
- [x] Implement fused-cover materialization for `Apply -> Reduce`: one selected
  cover becomes one compiled artifact/body, not only a typed grouping of node
  artifacts.
- [ ] Optional future budget expansion: implement fused-cover materialization for
  legal cover families outside the current `Apply -> Reduce` bank shape.
- [ ] Then run the materializer consumption and benchmark meta-task above.
- [ ] Finally, make frontend lowering feed the full schema and prove the matrix
  from source program to loaded LuaJIT module.
