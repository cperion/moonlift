# Stencil Family Implementation Guide

This guide describes how to implement a new Moonlift stencil family after the
descriptor normalization work.

The completed reference family is:

```text
range1d arrays =
  StencilDomainRange1D
  + scalar / contiguous / indexed / in_place access topology
  + apply / copy / reduce / scan / find / partition skeletons
  + 18/18 LuaJIT C stencil vocabulary cells
```

The rule for every next family is the same:

```text
schema first
facts second
Llisle selection third
artifact generation fourth
diagnostics and measurements before claiming completion
```

Do not implement a family by adding ad hoc backend cases that rediscover meaning
from raw loops. Backend stencils consume normalized descriptors selected from
Moonlift facts.

## What A Family Is

A stencil family is a coherent projection of the normalized descriptor model:

```text
Domain       logical iteration space
Access       operand role
Topology     address/storage mapping from domain point to value
Operator     pointwise computation
Reducer      accumulator update
Skeleton     whole-domain behavior
Memory       alias, overlap, conflict, bounds, and trap semantics
Control      result, exit, and multi-pass behavior
```

The current ASDL center is `MoonStencil.StencilDescriptor` in
`lua/moonlift/schema/stencil.lua`.

A new family should usually extend one of these axes, not introduce a new
parallel vocabulary:

```text
views/slices     extend topology
byte spans       extend topology/operator
2D surfaces      extend domain/topology
field projection extend topology
segmented data   extend domain
masked data      extend domain
windowed data    extend topology/domain
sparse data      extend domain/topology/memory semantics
```

## Completed Reference: Range1D Arrays

The array family is complete for the current LuaJIT C stencil backend.

Implemented vocabulary:

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

Important properties of the completed reference:

- `StencilInstance` carries `descriptor`, `schedule`, ABI, and proofs, not old
  public `vocab`, `shape`, or `params`.
- `StencilShape*` is not schema API anymore.
- The C emitter may use private Lua records as an implementation convenience,
  but the ASDL contract is the descriptor.
- `stencil_c.lua` constructs `StencilDescriptor` for every artifact.
- The selected schedule is the concrete machine-facing vectorization policy;
  descriptors stay semantic.
- Lowering coverage is measured as a whole vocabulary, not isolated examples.

Validation commands:

```sh
luajit tests/run.lua code_ir
luajit benchmarks/bench_luajit_stencil_matrix.lua full
luajit benchmarks/bench_luajit_lower_stencil_matrix.lua full
```

The lower matrix must report:

```text
lowered vocabulary cells 18/18
```

## Implementation Workflow

### 1. Define The Family Semantics

Before editing code, write the family as normalized parts.

Template:

```text
family name:
  domain:
  topology:
  access roles:
  operators:
  reducers:
  skeletons:
  memory semantics:
  control/result semantics:
  expected backend specializations:
```

If the family cannot be described with these axes, fix the semantic model first.
Do not compensate with backend flags or string tags.

### 2. Extend ASDL First

Edit `lua/moonlift/schema/stencil.lua`.

Allowed schema changes:

- Add a `StencilDomain` variant for a genuinely new iteration space.
- Add a `StencilAccessTopology` variant for a genuinely new storage mapping.
- Add a `StencilElementOperator` variant for a genuinely new pointwise operation.
- Add memory/control semantics only when they affect legality or codegen.

Avoid:

- Adding a new top-level family just because the container changed.
- Reintroducing product/sum semantics as backend-specific tables.
- Storing hidden meaning in strings, callback names, or side registries.

Schema test:

```sh
luajit tests/schema/test_schema_stencil.lua
```

The schema test should construct at least one representative descriptor for the
new family and assert its normalized axes.

### 3. Add Or Reuse Compiler Facts

A backend family must be selected from facts, not guessed from raw CFG.

Relevant layers:

```text
MoonCode
  -> graph facts
  -> flow facts
  -> value facts
  -> memory facts
  -> effect facts
  -> MoonKernel plan
```

If a family needs new facts, add them at the layer where the meaning belongs.

Examples:

```text
view bounds          memory/fact layer
row stride           topology/memory facts
field projection     memory/object layout facts
segment boundaries   domain facts
mask traversal       domain facts
scatter conflicts    memory semantics
```

Do not make LuaJIT lowering rediscover these facts by scanning instructions.

### 4. Bridge Through MoonKernel

MoonKernel is the semantic bridge from compiler facts to backend stencils.

Use existing skeletons when possible:

```text
apply
copy
reduce
scan
find
partition
```

Add a new kernel effect/result only if the skeleton itself is new. A new storage
shape usually belongs in topology, not in a new skeleton.

Examples:

```text
view map        same apply skeleton, view topology
AoS field sum   same reduce skeleton, field projection topology
masked count    count/reduce skeleton over masked domain
segmented scan  new segmented domain, scan skeleton may remain reusable
```

### 5. Select With Llisle

Llisle owns selection. The selector should classify normalized facts into a
stencil descriptor.

Selection responsibilities:

- reject unsupported domains, topologies, operators, types, or memory semantics
  with semantic reasons;
- choose the concrete vocabulary or backend specialization;
- produce ordered machine arguments;
- produce the descriptor consumed by artifact generation.

Do not route selection through a side registry that hides semantics from ASDL.

Relevant files today:

```text
lua/moonlift/luajit_stencil_rules.lua
lua/moonlift/luajit_lower.lua
lua/moonlift/code_kernel_plan.lua
lua/moonlift/code_kernel_plan_rules.lua
```

### 6. Generate Artifacts From Descriptors

Artifact generation consumes `StencilDescriptor`.

For the current C stencil backend, the main file is:

```text
lua/moonlift/stencil_c.lua
```

The implementation may derive private local records from descriptors to keep
emission code compact. That private projection must not become schema API.

Required artifact properties:

- descriptor is the source of truth;
- schedule is explicit on the `StencilInstance`;
- ABI follows from descriptor accesses and result semantics;
- symbol names are deterministic;
- rejection happens before code emission when a descriptor is unsupported;
- no runtime dependency on compiler-side selection tables.

### 7. Add Diagnostics

Diagnostics should name the normalized axis that failed.

Good rejection reasons:

```text
unsupported domain: tile2d not implemented by LuaJIT C stencil backend
unsupported topology: descriptor stride requires view descriptor lowering
unsupported memory semantics: scatter conflict mode is last_write_wins
unsupported operator/type pair: bitnot requires integer scalar
missing proof: no bounds proof for view access
```

Bad rejection reasons:

```text
unsupported shape
bad info table
cannot lower loop
unknown case
```

### 8. Measure Against Direct C

Every family needs two measurement gates:

```text
raw artifact benchmark:
  generated stencil artifact vs direct C/GCC baseline

lowered benchmark:
  MoonCode/MoonKernel/Llisle lowered path vs raw artifact path
```

The array family uses:

```sh
luajit benchmarks/bench_luajit_stencil_matrix.lua full
luajit benchmarks/bench_luajit_lower_stencil_matrix.lua full
```

A new family should add equivalent matrix coverage. The benchmark must report
coverage in terms of family cells, not just run one demo case.

## Completion Definition

A family is complete only when all of these are true:

```text
[ ] descriptor schema represents the family without ad hoc side tables
[ ] facts express the source semantics before backend lowering
[ ] MoonKernel carries the semantic skeleton
[ ] Llisle selects or rejects the family with semantic reasons
[ ] artifact generation consumes descriptors
[ ] every executable instance has an explicit schedule
[ ] generated code is compared with direct C/GCC baselines
[ ] lowered path is compared with raw artifact path
[ ] real DSL/frontend-shaped programs reach the same selected artifacts
[ ] tests cover every vocabulary cell claimed for the family
[ ] docs list the family as complete in STENCIL_SEMANTIC_MODEL.md
```

Do not mark a family complete because one happy-path program compiles.

## Recommended Order

The next families should be implemented in this order because each one reuses
the maximum amount of the completed array work:

```text
[x] descriptor-backed views
[x] descriptor-backed slices
[x] byte spans
[x] AoS / struct-field projections
[ ] SoA / multi-buffer records
[ ] 2D row-major surfaces
[ ] tiled domains
[ ] segmented domains
[ ] masked domains
[ ] generated ranges
[ ] windows / numeric stencils
[ ] sparse indexed data
```

The order is not about importance. It is about semantic dependency:

```text
views prove descriptor-backed topology
byte spans prove byte addressing and reinterpret/copy semantics
field projections prove topology can project inside records
SoA proves product-shaped synchronized access without duplicate type semantics
2D/tiled prove non-range1d domains
segmented/masked prove traversal is domain semantics
generated ranges prove payload-free domains
windows/sparse prove richer topology and memory semantics
```

## First Family To Implement: Views / Slices

Views/slices are the best next family because they reuse almost all array
skeletons.

Target shape:

```text
domain:    range1d
topology:  descriptor-backed strided access
accesses:  read/write/read_write/reduce/control_result
skeletons: apply, copy, reduce, scan, find, partition
memory:    bounds proof, stride proof, overlap/no-overlap or memmove semantics
```

Schema work:

```text
use StencilTopologyViewDescriptor for view-backed accesses
use StencilTopologySliceDescriptor only when slice data/len are explicit
represent data/len/stride source explicitly; descriptor fields are required
represent bounds/trap semantics if not already expressible
```

Fact work:

```text
view descriptor facts expose data pointer, length, stride
CodeInstViewMake records MemObjectSameStore with its backing data object
memory facts prove extent and stride legality
copy facts prove no-overlap or select memmove
```

No implicit topology:

```text
MemAccessContiguous -> StencilTopologyContiguous(1)
MemAccessStrided    -> StencilTopologyContiguous(stride_elems)
MemProvView         -> StencilTopologyViewDescriptor(view,data,len,stride)
MemAccessUnknown    -> reject before stencil selection
```

A direct `*_array_artifact` call still means the array family explicitly. The
lowering path must pass topology facts; it must not treat missing topology as
contiguous.

Dynamic view stride is part of the artifact ABI:

```text
array access, no runtime stride     -> base pointer only
view access with known stride_const -> base pointer only, stride baked into C
view access with dynamic stride     -> base pointer + access_named_stride arg
```

Artifact C symbols include descriptor topology suffixes for non-array
topologies. Array and view descriptors for the same vocabulary/type therefore
cannot collide in one compiled stencil unit.

Benchmark cells should mirror the array cells where legal:

```text
view copy
view fill
view map
view zip_map
view cast
view compare
view zip_compare
view in_place_map
view scan
view find
view partition
view reduce
view count
view map_reduce
view zip_reduce
```

Gather/scatter only belong here if the indexed topology composes with views
without inventing a separate family.

Current validated descriptor cuts:

```text
view copy, dynamic runtime stride, CodeInstViewMake + CodeInstViewData
descriptor access keeps StencilTopologyViewDescriptor
machine ABI receives the backing data pointer plus dynamic stride args
test: tests/code_ir/test_luajit_lower_stencil_views.lua
artifact matrix: tests/code_ir/test_stencil_bank_all_shapes.lua builds a
                 binary stencil bank and executes installed entries
                 array + dynamic-view variants for all 18 vocabulary cells

slice copy, CodeInstSliceMake + CodeInstSliceData
descriptor access keeps StencilTopologySliceDescriptor
machine ABI receives the backing data pointer directly; no stride arg exists
Back ABI lowers CodeTySlice as data,len components, matching LuaJIT physical type
test: tests/code_ir/test_luajit_lower_stencil_slices.lua
artifact matrix: tests/code_ir/test_stencil_bank_all_shapes.lua builds a
                 binary stencil bank and executes installed entries
                 array + dynamic-view + dynamic-slice variants for all
                 18 vocabulary cells without symbol collisions

byte span copy, CodeInstByteSpanMake + CodeInstByteSpanData
descriptor access keeps StencilTopologyByteSpanDescriptor
machine ABI receives the backing byte pointer directly; no stride arg exists
Back ABI lowers CodeTyByteSpan as data,len components, matching LuaJIT physical type
test: tests/code_ir/test_luajit_lower_stencil_byte_spans.lua
artifact subset: tests/code_ir/test_stencil_bank_byte_spans.lua builds a
                 binary stencil bank and executes copy, memmove, fill,
                 find/search, compare, and count over explicit byte-span
                 topologies

AoS field projection, CodePlaceField over indexed record access
descriptor access keeps StencilTopologyFieldProjection(parent, record_ty,
field_name, field_offset)
machine ABI receives the parent record pointer; C emission uses
records[i].field and keeps the access element type as the field type
memory facts emit derived field objects with MemObjectSameStore to the parent,
so disjoint/readonly/writeonly contracts on parent objects apply through the
projection
tests: tests/schema/test_schema_stencil.lua
       tests/code_ir/test_stencil_bank_field_projection.lua
       tests/code_ir/test_luajit_lower_stencil_fields.lua
artifact subset: reduce, map, find, compare, and fill execute over
                 Demo_Pair.right without materializing a separate SoA buffer
```

## Hard-Yank Rules

When implementing a family, prefer hard yanks over compatibility shims.

Allowed temporary state:

- private local projections inside an emitter;
- tests that pin old behavior while the new semantic contract is being wired;
- docs that explicitly mark unchecked families.

Not allowed:

- old public ASDL constructors kept as compatibility API;
- old `info` tables as the real semantic carrier;
- duplicate product/sum semantics in another language layer;
- backend-only flags that should be descriptor fields;
- claiming completion before matrix coverage.

The array yank removed `StencilShape*` from schema API and made
`StencilInstance.descriptor` plus `StencilInstance.schedule` the contract.
Future family work should follow the same standard.
