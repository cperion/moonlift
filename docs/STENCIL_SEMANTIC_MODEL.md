# Stencil Semantic Model

This document defines the semantic model for Lalin stencils.

The current implementation has two intentionally different surfaces:

```text
1. A readable vocabulary used by rules, diagnostics, docs, and benchmarks.
2. A normalized semantic model used to keep lowering generic and orthogonal.
```

The readable vocabulary is valuable, but it is not the architecture. The
architecture is:

```text
Stencil =
  domain
  + access roles
  + access topology
  + element operator or reducer
  + skeleton form
  + memory/control semantics
  + target/backend selection facts
```

This is what keeps the family reduced: the compiler should not grow one
unrelated implementation for every nice name. The nice names classify a smaller
set of reusable semantic shapes.

## Current Vocabulary

The LuaJIT stencil vocabulary currently validated by
`benchmarks/bench_luajit_lower_stencil_matrix.lua` is:

```text
copy
copy_memmove
fill
map
zip_map
cast
compare
zip_compare
gather
scatter
in_place_map
scan
find
partition
reduce
count
map_reduce
zip_reduce
```

The lower benchmark covers all of them:

```sh
luajit benchmarks/bench_luajit_lower_stencil_matrix.lua full
```

Expected coverage line:

```text
lowered vocabulary cells 18/18
```

The raw stencil vocabulary is separately measured against direct GCC loops:

```sh
luajit benchmarks/bench_luajit_stencil_matrix.lua full
```

The same descriptor vocabulary also has a LuaTrace materializer:

```text
StencilDescriptor
  -> StencilProviderC
     -> C source
     -> binary stencil bank
     -> copy-patch FFI callable

StencilDescriptor
  -> StencilProviderLuaTrace
     -> LuaJIT trace function
     -> emitted Lua source artifact
     -> direct Lua stencil symbol
```

The provider choice is below stencil semantics. `StencilProviderC` and
`StencilProviderLuaTrace` must consume the same descriptor, schedule, topology,
operator, reducer, skeleton, and memory facts.

## Layering

The stencil path is deliberately split into layers.

```text
LalinCode loops/fragments
  -> graph/flow/value/memory/effect facts
  -> LalinKernel semantic skeletons
  -> Llisle stencil selection
  -> stencil_artifact_plan descriptor-backed artifact
  -> provider materialization
       StencilProviderC        -> stencil_c source realization
       StencilProviderLuaTrace -> stencil_luajit trace/source realization
  -> LuaJIT machine call/effect
```

The key rule:

```text
Backend stencils consume semantic facts.
They do not discover major program meaning from raw CFG by themselves.
```

For example:

```text
prefix sum with output array -> KernelEffectScan
early-exit search            -> KernelResultFind
two-pass stable partition    -> KernelEffectPartition
overlap-aware copy           -> KernelEffectCopy + StencilCopyMemMove
```

LuaJIT lowering consumes those kernel facts. It should not contain a second,
competing implementation of scan, find, partition, or copy semantics.

## Normalized Model

The readable names are classifications over normalized semantic parts.

```text
Domain       which logical points are visited
Access       operand role over the domain
Topology     how a domain point maps to storage or a scalar
Operator     per-element computation
Reducer      accumulator update
Skeleton     whole-domain semantic form
Memory       alias, overlap, bounds, trap, and conflict semantics
Control      return, exit, and multi-pass fragment semantics
```

The current backend is array/range1d-focused, but the model is not array-only.
The same semantic pieces can grow toward:

```text
strided views
slices
indexed domains
2D image tiles
matrix rows/columns
struct field projections
byte spans
generated ranges
segmented domains
masked domains
```

## Family Expansion Choice

The current array stencil backend is treated as one completed projection of the
normalized model, not as the whole stencil family.

```text
array stencils =
  range1d domain
  + contiguous/indexed/in-place array topology
  + current apply/reduce/scan/copy/find/partition skeletons
```

New stencil families must extend the normalized axes first. They should not add
parallel vocabulary for the same semantics just because the storage container
changes.

For example:

```text
views/slices       = range1d domain + descriptor-backed strided topology
byte spans         = range1d domain + byte-addressed topology + cast/reinterpret operator
2D tiles/images    = tile2d domain + row/column/tiled topology
AoS field arrays   = range1d domain + field-projection topology
SoA record arrays   = range1d domain + synchronized component-buffer topology
segmented data     = segmented domain + existing apply/reduce/scan skeletons
masked data        = masked domain + existing access roles and predicates
```

The rule is:

```text
grow domains, topologies, operators, skeletons, and memory semantics;
do not grow duplicate language families for reducible cases.
```

This keeps the Lalin family reduced. A new concrete stencil name is allowed
only when it classifies a genuinely new combination of normalized semantics or a
backend-relevant specialization of one. It is not allowed just to spell product
and sum semantics twice.

## Family Implementation Checklist

Use this checklist bottom-up. A family is not done when one example lowers; it
is done when its descriptor semantics, lowerer selection, artifact generation,
diagnostics, and measurement gate all agree.

```text
[x] range1d arrays
    domain:      range1d
    topology:    contiguous, indexed, in_place, scalar
    skeletons:   apply, copy, reduce, scan, find, partition
    vocabulary:  18/18 LuaJIT C stencil cells
    gate:        bench_luajit_lower_stencil_matrix.lua full

[x] descriptor-backed views
    domain:      range1d
    topology:    strided descriptor data/len/stride
    skeletons:   apply, copy, reduce, scan, find, partition
    first proof:  same skeletons as arrays with non-unit stride and view bounds
    gate:        code_ir view copy proves dynamic runtime stride lowering;
                 stencil_artifact_plan all-shapes constructs array +
                 dynamic-view variants; stencil_c compiles those artifacts
                 for the full 18-cell vocabulary without symbol collisions;
                 array quick matrix remains 18/18 measured.
    status:      view descriptor topology is typed and carried through
                 Llisle selection into descriptors; CodeInstViewMake emits
                 MemObjectSameStore for its backing data; dynamic stride
                 is part of artifact ABI and C address generation.

[x] descriptor-backed slices
    domain:      range1d
    topology:    descriptor data/len
    skeletons:   same as views where contiguous slice access is legal
    first proof:  first-class Code IR slice projection, not reuse of view
    gate:        code_ir slice copy proves CodeInstSliceMake +
                 CodeInstSliceData lowering into StencilTopologySliceDescriptor;
                 stencil_artifact_plan all-shapes constructs array +
                 dynamic-view + dynamic-slice variants; stencil_c compiles
                 those artifacts for the full 18-cell vocabulary without
                 symbol collisions.
    status:      slice descriptors are typed as data,len across LuaJIT
                 physical types and Back ABI components; CodeInstSliceMake
                 emits MemObjectSameStore for its backing data.

[x] byte spans
    domain:      range1d
    topology:    byte-addressed span
    operators:   copy, memmove, fill, find/search, compare, count
    first proof:  memcpy/memmove/fill/search over u8-compatible spans
    gate:        code_ir byte span copy proves CodeInstByteSpanMake +
                 CodeInstByteSpanData lowering into
                 StencilTopologyByteSpanDescriptor; stencil_artifact_plan
                 constructs byte-span artifacts; stencil_c compiles and
                 executes copy, memmove, fill, find, compare, and count over
                 u8-compatible spans.
    status:      byte spans are explicit Code/Mem/Stencil descriptors,
                 not slice[u8] aliases; Back and LuaJIT ABI lower them as
                 data,len components, while memory facts keep the element
                 type fixed to u8 and the descriptor length as byte length.

[x] AoS / struct-field projections
    domain:      range1d
    topology:    field projection over contiguous records, composed over parent
                 topology
    skeletons:   apply, reduce, find, compare, fill at the C vocabulary layer;
                 map/reduce from LalinCode facts through LuaJIT lowering
    first proof:  map/reduce one field without materializing SoA
    gate:        schema constructs StencilTopologyFieldProjection;
                 stencil_artifact_plan constructs field-projected artifacts;
                 stencil_c compiles and executes reduce/map/find/compare/fill
                 over Demo_Pair.right; Code IR lowering recognizes xs[i].right
                 as a field-projected lane and executes lowered reduce/map.
    status:      field projections are modeled as topology, not as a second
                 product implementation; memory facts emit derived field
                 objects with same-store parent relations so parent disjoint
                 contracts prove projected-field loop independence.

[x] SoA / multi-buffer records
    domain:      range1d
    topology:    named component buffer over a parent topology
    skeletons:   zip_map and zip_reduce from real DSL lowering; zip_compare and
                 partition at the artifact vocabulary layer
    first proof:  record-like zip semantics without inventing a second product model
    gate:        schema constructs StencilTopologySoAComponent; tree contracts
                 typecheck `soa_component(base, Record, field, index)` into
                 CodeContractSoAComponent; LuaJIT lowering wraps lane
                 topology from those Code facts; stencil_artifact_plan
                 constructs SoA component artifacts; stencil_c compiles and
                 executes zip_map, zip_reduce, zip_compare, and partition over
                 component buffers; real DSL source emits and executes a
                 LuaJIT copy-patch artifact for SoA zip_map and zip_reduce;
                 bench_luajit_stencil_soa.lua quick compares that lowered
                 artifact against direct GCC loops.
    status:      SoA is topology plus typed contracts, not a second product
                 implementation. Component pointers keep their scalar ABI,
                 while descriptors carry the logical record type, field name,
                 component index, and parent storage topology. Vectorized
                 copy-patch objects can carry local constant-pool and jump-table
                 sections such as .rodata.cst16 and .rodata; the stencil bank
                 materializes those sections into the installed blob, resolves
                 local rel32 relocations, and promotes local absolute32
                 relocations to the low32 install policy.

[ ] 2D row-major surfaces
    domain:      tile2d or range2d
    topology:    row stride, width, height, element size
    skeletons:   apply, copy, reduce, find
    first proof:  image-style map/copy/reduce over row-strided storage
    gate:        compare tiled/row loops against hand-written C

[ ] tiled domains
    domain:      tile2d / blocked range_nd
    topology:    tile-local contiguous or row-major storage
    skeletons:   apply, reduce, scan where legal
    first proof:  same semantics as range2d with explicit tile traversal order
    gate:        compare tile sizes against direct C and keep best selection facts

[ ] segmented domains
    domain:      segmented range
    topology:    segment offsets + contiguous/indexed payload
    skeletons:   segmented reduce, segmented scan, segmented map
    first proof:  segment boundaries are domain semantics, not predicates in loops
    gate:        compare against direct segmented C kernels

[ ] masked domains
    domain:      range1d + mask or explicit masked domain
    topology:    mask lane plus payload topology
    skeletons:   apply, reduce, count, find, partition
    first proof:  mask is traversal/domain semantics, not a duplicate predicate op
    gate:        compare mask density cases against direct C

[ ] generated ranges
    domain:      generated/virtual range
    topology:    scalar or generated value, no required payload load
    skeletons:   apply, reduce, scan
    first proof:  reductions over generated affine/range values
    gate:        compare closed-form, generated-loop, and C loop paths

[ ] windows / stencils in the numeric sense
    domain:      range1d/range2d with neighborhood
    topology:    windowed access around each domain point
    skeletons:   apply, reduce-local, convolution-like map
    first proof:  neighborhood semantics live in topology, not custom loop names
    gate:        compare direct C window loops and boundary modes

[ ] sparse indexed data
    domain:      index lane or compressed segment domain
    topology:    gather/scatter over index/value buffers
    skeletons:   apply, reduce, scatter with conflict semantics
    first proof:  conflicts and ordering are memory semantics
    gate:        compare CSR/COO-shaped C kernels where applicable
```

Every unchecked family must land by extending normalized schema first. The
minimum completion gate for each family is:

```text
1. ASDL descriptor shape exists.
2. Kernel/LalinCode facts can express the family without backend guessing.
3. Llisle selector classifies the family from facts.
4. stencil_artifact_plan or copy-patch artifact generation consumes the descriptor.
5. Diagnostics explain rejection in terms of the normalized axes.
6. Benchmarks compare lowered output against direct C/GCC baselines.
```

The step-by-step workflow for implementing these families lives in
`docs/STENCIL_FAMILY_IMPLEMENTATION_GUIDE.md`.

## Domain

A domain is the logical iteration space.

It answers:

```text
which logical points are visited?
in what canonical order?
what is the extent?
can the domain be split?
can the domain be vectorized?
does the domain have tails?
```

The currently implemented stencil path uses counted `range1d` domains derived
from `FlowLoopFacts`:

```text
start
stop
step
exclusive stop
primary induction
```

Conceptual descriptor:

```lua
domain = {
  kind = "range1d",
  start = 0,
  stop = n,
  step = 1,
}
```

The domain does not say how operands are addressed. Addressing belongs to
topology.

Future domains:

```text
tile2d
range_nd
product
masked
segmented
windowed
```

## Access Roles

An access is the role an operand plays over a domain.

Initial roles:

```text
read
write
read_write
reduce
control_result
```

Examples:

```text
copy          read src, write dst
in_place_map  read_write dst
reduce        read src, reduce accumulator
find          read src, control_result index
partition     read src, write dst, control_result split
```

Access roles are separate from topology. This is why gather and scatter are not
fundamental computation kinds:

```text
gather  = apply/copy with indexed read topology
scatter = apply/copy with indexed write topology
```

## Topology

Topology defines how a domain point maps to storage or a scalar.

Current practical topologies:

```text
scalar
contiguous
indexed
in_place
```

The C stencil artifacts also carry `step_num`, so range stride is represented
even where full view-stride topology is not yet first-class.

Conceptual examples:

```lua
{ kind = "scalar", value = c }
{ kind = "contiguous", base = src }
{ kind = "indexed", base = src, index = idx }
{ kind = "in_place", base = dst }
```

Future topologies:

```text
strided
field
row_major_2d
column_major_2d
tiled
packed_bits
soa_field
aos_field
```

## Operators

Element operators describe pointwise computation.

Current operator families:

```text
identity
fill
unary
binary
cast
compare
predicate
```

Examples:

```lua
{ kind = "identity", arg = "src", result = "dst" }
{ kind = "fill", value = "c", result = "dst" }
{ kind = "unary", op = "neg", arg = "src", result = "dst" }
{ kind = "binary", op = "add", args = { "lhs", "rhs" }, result = "dst" }
{ kind = "cast", from = "i32", to = "f64", arg = "src", result = "dst" }
{ kind = "compare", pred = "gt", args = { "src", 0 }, result = "dst" }
```

Predicates are currently represented by `LalinStencil.StencilPredicate`:

```text
StencilPredNonZero
StencilPredEqConst
StencilPredNeConst
StencilPredLtConst
StencilPredLeConst
StencilPredGtConst
StencilPredGeConst
```

## Reducers

Reduction operators update an accumulator over the domain.

Current reducer kinds:

```text
add
mul
min
max
and
or
xor
count_add
```

`count_add` is the semantic classification of predicate-to-integer additive
reduction. In the ASDL layer this is still represented through ordinary
reduction and expression facts.

## Skeleton Forms

The normalized primitive stencil forms are no longer only `apply` and `reduce`.
The current semantic forms are:

```text
apply
reduce
scan
find
partition
copy
```

`copy` could be seen as an `apply identity`, but it deserves an explicit
skeleton because overlap semantics are part of its meaning. Treating overlap as
just another store spelling is wrong.

### `apply`

`apply` produces one write result per domain point.

Derived classifications:

```text
fill
copy no-overlap
map
zip_map
cast
compare
zip_compare
gather
scatter
in_place_map
```

Descriptor shape:

```lua
{
  kind = "apply",
  domain = ...,
  reads = ...,
  writes = ...,
  op = ...,
}
```

### `reduce`

`reduce` collapses domain points into an accumulator.

Derived classifications:

```text
reduce
map_reduce
zip_reduce
count
```

Descriptor shape:

```lua
{
  kind = "reduce",
  domain = ...,
  reads = ...,
  map = ...,
  reducer = ...,
  init = ...,
  result = ...,
}
```

### `scan`

`scan` stores the prefix values of a recurrence and returns the final
accumulator.

LalinKernel representation:

```text
KernelEffectScan(dst, index, reduction, mode)
KernelEffectFold(reduction)
KernelResultReduction(reduction)
```

Current mode:

```text
StencilScanInclusive
```

Derived classification:

```text
scan_array
```

### `copy`

`copy` moves one source lane to one destination lane over a domain.

LalinKernel representation:

```text
KernelEffectCopy(dst, src, semantics)
KernelResultVoid
```

Current copy semantics:

```text
StencilCopyNoOverlap
StencilCopyMemMove
```

`StencilCopyNoOverlap` is selected when memory facts prove source/destination
independence. `StencilCopyMemMove` is selected when source/destination overlap
is not disproven but the operation is still semantically a copy.

### `find`

`find` searches the domain and returns the first matching index, or a not-found
sentinel.

LalinKernel representation:

```text
KernelResultFind(src, pred, not_found)
```

Current lowered shape:

```text
primary-index load
predicate branch out of the loop
hit returns primary induction
miss returns -1
```

Derived classification:

```text
find_array
```

### `partition`

`partition` writes matching elements first and non-matching elements second,
returning the split index.

LalinKernel representation:

```text
KernelEffectPartition(dst, src, pred, semantics)
KernelResultValue(split)
```

Current semantics:

```text
StencilPartitionStable
```

Important: stable partition is not a single-loop store. It is a function-level
two-pass fragment:

```text
pass 1: copy matching elements, advancing output
pass 2: copy non-matching elements, advancing output
return split
```

That is why the kernel subject is function-level while the body domain still
cites the counted loop domain used for stencil arguments.

## LalinKernel Bridge

The current semantic bridge from compiler facts to backend stencils is
`LalinKernel`.

Important nodes:

```text
KernelLane
KernelExprLaneLoad
KernelExprAlgebra
KernelBinding

KernelEffectStore
KernelEffectScan
KernelEffectCopy
KernelEffectPartition
KernelEffectFold

KernelResultVoid
KernelResultValue
KernelResultFind
KernelResultReduction
KernelResultClosedForm
KernelResultOriginalControl
```

Plain store/reduction kernels remain useful, but once a stronger semantic
skeleton is recognized, the plan should carry that stronger meaning.

Examples:

```text
store of reduction update             -> KernelEffectScan
primary-index load/store              -> KernelEffectCopy
early-exit predicate search            -> KernelResultFind
two-pass predicate-preserving fragment -> KernelEffectPartition
```

## Llisle Selection

Llisle owns stencil selection decisions.

The split is:

```text
stencil_rules
  classifies expression/access shapes
  selects concrete stencil vocabulary
  builds provider info and argument ordering

luajit_lower
  consumes preplanned stencil machines
  projects planned machines or scalar Code blocks into LalinLuaJIT
```

This keeps the decision matrix inspectable as family data instead of hiding it
inside procedural Lua trial ladders.

Current selection relations include:

```text
select_kernel_lowering
select_store_stencil
select_reduce_stencil
select_scan_stencil
select_find_stencil
select_partition_stencil
```

## Derived Classification Rules

The nice names are derived from normalized descriptors.

### `fill`

```text
skeleton = apply
op = fill
writes = one
reads = scalar value source
```

### `copy`

```text
skeleton = copy
reads = one contiguous source
writes = one contiguous destination
semantics = no-overlap or memmove
```

### `map`

```text
skeleton = apply
op = unary
reads = one
writes = one
```

### `zip_map`

```text
skeleton = apply
op = binary
reads = two synchronized reads
writes = one
```

### `cast`

```text
skeleton = apply
op = cast
reads = one
writes = one
```

### `compare`

```text
skeleton = apply
op = compare
reads = one
writes bool-like result
```

### `zip_compare`

```text
skeleton = apply
op = compare
reads = two synchronized reads
writes bool-like result
```

### `gather`

```text
skeleton = apply
read topology = indexed
write topology = contiguous
op often identity
```

### `scatter`

```text
skeleton = apply
read topology = contiguous
write topology = indexed
op often identity
```

### `in_place_map`

```text
skeleton = apply
access = read_write
op = unary
source and destination are same lane
```

### `reduce`

```text
skeleton = reduce
map = identity
reads = one
```

### `map_reduce`

```text
skeleton = reduce
map = unary/cast/compare/fill-like transform
reads = one
```

### `zip_reduce`

```text
skeleton = reduce
map = binary
reads = two synchronized reads
```

### `count`

```text
skeleton = reduce
map = predicate or bool-to-int
reducer = add
```

### `scan`

```text
skeleton = scan
reduction = loop-carried recurrence
write = prefix values
result = final accumulator
```

### `find`

```text
skeleton = find
read = primary-index source
predicate = compare/load predicate
result = first matching index or -1
```

### `partition`

```text
skeleton = partition
read = primary-index source
write = compacted destination
predicate = compare/load predicate
result = split index
semantics = stable
```

## Current Implementation Boundaries

The current complete path is:

```text
range1d + scalar/contiguous/indexed/in-place array topologies
```

It is complete for the current LuaJIT C stencil vocabulary, not for every future
domain or topology.

Current validation:

```sh
luajit tests/run.lua code_ir
luajit tests/run.lua llisle
luajit benchmarks/bench_luajit_stencil_matrix.lua full
luajit benchmarks/bench_luajit_lower_stencil_matrix.lua full
```

The lower matrix is the key bottom-up gate. It proves that real LalinCode shapes
select the expected stencil vocabulary and run against the raw artifact path.

## Template/Bank Selection Key

The backend should eventually select compiled stencil entries from normalized
descriptors, not from ad hoc names.

Key shape:

```text
skeleton form
domain kind
read roles and topologies
write roles and topologies
operator or reducer kind
predicate
input/output types
alias and overlap facts
control/result semantics
schedule facts
target ABI
target features
bank ABI version
```

Example compact keys:

```text
apply/range1d/read_contig_i32/write_contig_i32/unary_neg/x64_baseline
reduce/range1d/read_contig_i32/add_i32/init0/x64_baseline
copy/range1d/read_contig_i32/write_contig_i32/memmove/x64_baseline
find/range1d/read_contig_i32/pred_gt_0/not_found_-1/x64_baseline
partition/range1d/read_contig_i32/write_contig_i32/pred_gt_0/stable/x64_baseline
```

This is the path toward copy-patch stencil banks and broader non-array stencil
targets without multiplying implementation concepts.
