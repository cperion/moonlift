# Stencil Semantic Model

This document defines the semantic model for Moonlift stencils.

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

The LuaJIT C stencil vocabulary currently validated by
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

## Layering

The stencil path is deliberately split into layers.

```text
MoonCode loops/fragments
  -> graph/flow/value/memory/effect facts
  -> MoonKernel semantic skeletons
  -> Llisle stencil selection
  -> StencilC artifact
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

Predicates are currently represented by `MoonStencil.StencilPredicate`:

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

MoonKernel representation:

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

`copy` moves one source stream to one destination stream over a domain.

MoonKernel representation:

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

MoonKernel representation:

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

MoonKernel representation:

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

## MoonKernel Bridge

The current semantic bridge from compiler facts to backend stencils is
`MoonKernel`.

Important nodes:

```text
KernelStream
KernelExprLoad
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
luajit_lower
  adapts facts into candidates
  asks Llisle which lowering strategy to use
  builds the selected machine

luajit_stencil_rules
  classifies expression/access shapes
  selects concrete stencil vocabulary
  builds provider info and argument ordering
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
source and destination are same stream
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

The lower matrix is the key bottom-up gate. It proves that real MoonCode shapes
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
