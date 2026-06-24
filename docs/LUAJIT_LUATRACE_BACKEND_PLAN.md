# LuaTrace Backend Completion Plan

This plan describes the hard-yank path for making LuaTrace a complete,
fact-consuming MoonStencil backend.

LuaTrace is not a convenience source printer. It is a backend materializer for
scheduled `MoonStencil.StencilArtifact` values. It must consume descriptor
semantics, schedules, vectorization facts, and memory/control facts directly,
then emit LuaJIT-shaped code.

The copy-patch backend remains the steady-state performance reference. LuaTrace
has a different purpose:

```text
low materialization latency
inspectable generated Lua
good trace shape for monomorphic kernels
shared stencil semantics with copy-patch
```

## Current State

Current LuaTrace already consumes:

```text
StencilDescriptor vocabulary
access topologies for address expressions
dynamic stride ABI params
explicit StencilScheduleVector
explicit StencilScheduleUnrolled
StencilScheduleAutoVector unit-stride facts
stencil kind for AutoVector grouping caps
```

Current gaps:

```text
no separate access plan
no separate loop plan
no primitive copy/fill plan
no alias/noalias policy
no alignment policy
no trip-count/tail policy
no reduction dependency-chain policy
limited predicate kernel policy
scatter conflict facts ignored
copy overlap facts only partially consumed
```

## Non-Negotiable Invariants

LuaTrace must obey these rules:

```text
1. Do not rediscover major semantics from MoonCode.
2. Consume selected StencilArtifact values only.
3. Preserve explicit schedules.
4. Treat AutoVector as provider-local trace-shaping input, not SIMD.
5. Keep descriptor equivalence with copy-patch.
6. Measure every policy against copy-patch and previous LuaTrace.
7. Do not keep a policy that only sounds plausible.
```

Explicit schedules are semantic selection results:

```text
StencilScheduleVector   -> preserve lanes * unroll * interleave as trace group
StencilScheduleUnrolled -> preserve factor as trace group
```

AutoVector is provider-local:

```text
StencilScheduleAutoVector + facts -> LuaTrace chooses trace group
```

## Backend Architecture

The completed backend should lower in stages:

```text
StencilArtifact
  -> LuaTraceArtifactPlan
  -> LuaTraceAccessPlan[]
  -> LuaTraceLoopPlan
  -> LuaTraceKernelPlan
  -> LuaTraceSourcePlan
  -> generated Lua source
```

The first implementation can use local Lua records. If the plans become part of
public inspection, LSP, diagnostics, or artifact serialization, promote them to
`MoonLuaJIT` ASDL records.

### LuaTraceArtifactPlan

Fields:

```text
artifact
descriptor
shape
schedule
facts
access_plans
loop_plan
kernel_plan
source_name
debug_metadata
```

Purpose:

```text
single source of truth for one emitted Lua function
```

### LuaTraceAccessPlan

One plan per non-scalar access.

Fields:

```text
name
role
type
topology
base_arg
index_expr_kind
offset_expr_kind
dynamic_stride_arg
stride_const
readonly
readwrite
alias_fact
alignment_fact
unit_stride
element_bytes
field_name
field_offset
component_index
can_pointer_bump
can_bulk_copy
can_bulk_fill
```

Access plan kinds:

```text
contiguous:
  base[i]

indexed:
  base[idx[i]]

in_place:
  base[i] with readwrite role

field_projection:
  base[i].field

soa_component:
  component_base[i]

slice_descriptor:
  data[i]

byte_span_descriptor:
  data[i]

view_descriptor_const_stride:
  data[i * stride_const]

view_descriptor_dynamic_stride:
  data[i * stride_arg]
```

Optimization choices:

```text
unit stride + plain topology:
  regular indexed loads/stores

dynamic stride + grouped loop:
  compute per-lane offset from a hoisted base when measured profitable

field projection:
  preserve cdata field access, but expose field_offset for diagnostics/plans

byte span:
  enable ffi.copy/ffi.fill byte counts when copy/fill semantics allow it
```

### LuaTraceLoopPlan

Fields:

```text
domain_stride
trip_count_fact
group
tail_strategy
loop_shape
index_shape
reason
```

Loop shapes:

```text
scalar_for:
  for i = start, stop - 1, stride do

grouped_while:
  while __ml_i < __ml_stop_group do

small_static_straightline:
  no loop when trip-count facts prove a tiny fixed count

bulk_primitive:
  ffi.copy / ffi.fill / equivalent primitive
```

Tail strategies:

```text
generic_tail_loop:
  default

no_tail:
  trip count multiple-of group

scalar_tail:
  explicit tail loop

single_exit_tail:
  only for early-exit shapes when measured profitable
```

Fact consumption:

```text
StencilTripCountMultipleOf(group):
  skip tail loop

StencilTripCountDynamic:
  generic tail loop

non-unit domain stride:
  disable grouping unless explicit schedule demands otherwise and tests pass
```

### LuaTraceKernelPlan

One plan per stencil vocabulary cell.

Fields:

```text
kind
operation_plan
branch_plan
reduction_plan
primitive_plan
result_plan
```

Kernel-specific policies:

```text
reduce:
  single accumulator by default
  multi-accumulator only when reassociable and measured faster

map / zip_map / cast:
  grouped loop when access plan is trace-friendly

scan:
  preserve dependency chain; grouping only when it does not change semantics

copy:
  primitive path when legal; loop path otherwise

fill:
  primitive path for byte fill; loop path for typed non-byte values

find:
  early-exit branch shape; do not force grouping until measured

partition:
  two-pass stable branch shape; keep explicit because semantics are branch-like

compare / zip_compare:
  benchmark branch, select, and byte-store variants

count:
  benchmark branch, select, and multi-counter variants

gather / scatter:
  consume conflict/index facts when available; default arbitrary indirect shape

map_reduce / zip_reduce:
  combine map plan and reduction plan; reassociation controls multi-accumulator
```

## Fact Consumption Matrix

LuaTrace must consume every fact that can change emitted Lua shape.

| Semantic Input | LuaTrace Use |
|---|---|
| `StencilAccessRole` | readonly/write/readwrite plan and mutation legality |
| `StencilAliasNoAlias` | enables stronger grouping/bulk primitive choices |
| `StencilAliasMayAlias` | blocks unsafe primitive or aggressive grouping |
| `StencilAliasUnknown` | conservative default |
| `StencilAlignmentKnown` | recorded; may enable primitive path assertions later |
| `readonly` access fact | load-only access plan; can share source values safely |
| `unit_stride` access fact | AutoVector grouping eligibility |
| `StencilTripCountMultipleOf` | no-tail grouped loop |
| `StencilTripCountDynamic` | generic tail loop |
| `reduction_reassociable` | permits multi-accumulator reductions |
| strict float mode | forbids reassociation |
| int semantics | controls `bit.tobit` placement and wrap behavior |
| copy no-overlap | permits forward bulk/loop copy |
| copy memmove | preserves overlap behavior |
| scatter unique indices | enables no-conflict assumptions |
| partition stable | keeps two-pass stable order |
| dynamic view stride | dynamic stride args and grouping cap |
| const view stride | constant offset expression |
| field projection | cdata field access |
| SoA component | separate component buffer access |
| byte span | byte primitive eligibility |

## Primitive Paths

Primitive paths are provider-local materializations. They are legal only when
descriptor semantics prove the shape.

### Copy

Candidates:

```text
typed Lua loop
ffi.copy byte count
manual small unroll loop
```

Legal `ffi.copy` shape:

```text
unit stride
plain contiguous/slice/byte-span access
no field projection
no indexed topology
no dynamic stride
copy semantics allow bytewise copy
overlap behavior matches ffi.copy/memmove requirements
```

Because LuaJIT `ffi.copy` behaves like `memcpy`, not a full explicit
bidirectional loop API, memmove semantics require either proof that overlap is
safe in the chosen direction or a loop fallback.

### Fill

Candidates:

```text
typed Lua loop
ffi.fill byte count
manual small unroll loop
```

Legal `ffi.fill` shape:

```text
byte span or u8/bool8 contiguous fill
unit stride
value is byte-compatible
```

Typed i32/f64 fill should remain loop-shaped unless we add a typed repeated
store primitive.

## Reduction Plans

Reduction policy must be measured per type and reduction kind.

Candidates:

```text
single accumulator
2 accumulators
4 accumulators
grouped lane accumulator
explicit schedule group body
```

Legality:

```text
integer wrap add/mul/and/or/xor:
  reassociation legal

min/max:
  reassociation legal when comparison semantics are stable

strict float:
  reassociation illegal

relaxed float:
  reassociation allowed only when float_mode says so
```

Do not assume multi-accumulator is faster. LuaJIT may prefer the single chain for
some traces.

## Predicate Plans

Predicate kernels are the largest current LuaTrace gap.

Measured variants required:

```text
count_branch:
  if pred then n = n + 1 end

count_select:
  n = n + (pred and 1 or 0)

count_multi_counter:
  n0/n1/n2/n3 then combine

compare_branch_select:
  dst[i] = pred and 1 or 0

compare_if_store:
  if pred then dst[i] = 1 else dst[i] = 0 end

zip_compare equivalents
```

The current benchmark showed naive `count_select` slower than the branch form.
That result must be preserved in the plan history; do not reintroduce it as a
default without better measurements.

## Gather/Scatter Plans

Current descriptors can distinguish scatter conflict semantics, but LuaTrace
does not use them yet.

Plan:

```text
arbitrary indirect:
  default

unique indices:
  no write conflicts; may permit grouped stores

monotonic/permutation/bounded:
  add facts first if needed; do not infer from data at runtime
```

Do not invent index facts inside LuaTrace. Add facts in the kernel/fact layer,
then consume them here.

## Measurement Matrix

Every plan change must run these:

```sh
luajit tests/code_ir/test_stencil_luajit_provider.lua
luajit tests/code_ir/test_luajit_backend_luatrace.lua
luajit tests/code_ir/test_stencil_bank_all_shapes.lua
luajit tests/run.lua code_ir
cargo check -q
```

Performance gates:

```sh
luajit benchmarks/bench_luajit_materializations.lua full
luajit benchmarks/bench_luajit_cfg_luatrace_vs_cranelift.lua full
```

When adding a policy variant, add a targeted benchmark cell that reports:

```text
previous LuaTrace
new LuaTrace
copy-patch reference
trace starts/stops/aborts/root/side counts
result checksum
```

A policy is accepted only if it improves or preserves the relevant class without
large regressions elsewhere.

## Implementation Order

### 1. Plan Records Only

Refactor `stencil_luajit.lua` so it first builds explicit local plans and emits
from those plans.

Done when:

```text
generated source is equivalent
tests pass
full benchmark is within noise
```

No performance policy changes in this step.

Status: done. `stencil_luajit.lua` now builds inspectable local
`LuaTraceArtifactPlan` records and exposes `StencilLuaJIT.plan_artifact`.

### 2. AccessPlan

Build access plans for every descriptor access and route all load/store
rendering through them.

Done when all topology tests still pass:

```text
contiguous
indexed
in_place
field projection
SoA component
slice descriptor
byte span descriptor
view descriptor dynamic stride
view descriptor const stride
```

Status: done for current descriptor topologies. All load/store rendering now
routes through `LuaTraceAccessPlan`; policy-specific fields such as
`can_bulk_copy` and `can_bulk_fill` are present but not yet used.

### 3. LoopPlan

Move grouping, tail, and index-shape decisions into `LuaTraceLoopPlan`.

Done when:

```text
explicit schedules preserved
AutoVector facts consumed
tail policy represented
tests assert generated plan comments
```

Status: done for current grouping/tail representation. The plan currently
models generic tail loops and consumes `StencilTripCountMultipleOf` facts. When
the trip-count factor is a multiple of the selected group, LuaTrace emits the
grouped loop with `tail=no_tail_trip_count_multiple` and suppresses the generic
tail loop. Unknown or merely dynamic trip counts keep the generic tail.

### 4. Primitive Copy/Fill

Implement primitive candidates behind legality checks.

Status: done for legal no-overlap copy and byte-sized fill. `StencilCopyNoOverlap`
lowers to `ffi.copy` when source and destination are bulk-copyable access
plans with equal element size. Byte-sized fill lowers to `ffi.fill`. Memmove
semantics and typed non-byte fill remain loop-shaped because `ffi.copy` and
`ffi.fill` would change semantics or value representation there.

Access facts participate in primitive legality. Bulk copy requires a writable
destination and readonly source. Paired `StencilAliasNoAlias` facts on source
and destination can upgrade an overlap-shaped copy to `ffi.copy`; the plan
records that legality source as `no_overlap_source=noalias_facts`.

Done when:

```text
copy/fill benchmark cells compare loop vs primitive
memmove semantics are not weakened
byte-span and u8 cases are covered
```

### 5. Reduction Policy

Add measured reduction variants.

Status: done for the current LuaTrace lowering model. LuaTrace reductions now
expose `kernel_plan.reduction_plan` and generated comments include
`reduction=ordered_single_accumulator`.

The selected policy is ordered single-accumulator:

```text
reassociation_required=false
multi_accumulator=false
```

That policy consumes the arithmetic facts without requiring reassociation. Strict
float records `reassociable=false` and rejects multi-accumulator lowering with
`multi_accumulator_rejected=reassociation_not_legal`. Reassociable integer/float
reductions keep the ordered policy until a measured LuaTrace multi-accumulator
variant beats it; the current matrix shows copy-patch is the right backend for
wide reassociating vector reductions.

Done when:

```text
i32/u8/f64 reductions covered
strict-float rejection covered
multi-accumulator only enabled where measured faster
```

### 6. Predicate Policy

Add measured predicate variants for count/compare/zip_compare.

Status: done for the current predicate families. Predicate kernels expose an
explicit `kernel_plan.predicate_plan`:

```text
compare_array      -> predicate=numeric_store when numeric predicate is measured legal, lua_select otherwise
zip_compare_array  -> predicate=numeric_store when numeric compare is measured legal, lua_select otherwise
count_array        -> predicate=multi_counter_branch when grouped, branch otherwise
```

The measured helper-function branchless candidate removed side traces but
regressed badly:

```text
i32_compare_gt branchless candidate        484.614ms vs branch 3.502ms
i32_zip_compare_lt branchless candidate    759.467ms vs branch 4.877ms
i32_count_gt branchless candidate          376.807ms vs branch 2.945ms
u8_bytespan_compare_gt branchless candidate 331.549ms vs branch 3.751ms
u8_bytespan_count_gt branchless candidate   195.028ms vs branch 2.917ms
```

That candidate is recorded as rejected in the plan:

```text
predicate=numeric_store | lua_select | multi_counter_branch | branch
rejected=helper_branchless_measured_slower | numeric_count_measured_slower
```

The selected numeric-store policy is inline, not helper-based. It is enabled for
the measured mask-producing shapes where it helps:

```text
u8_bytespan_compare_gt  3.7ms-class -> 1.356ms
i32_zip_compare_lt      4.7ms-class -> 4.277ms and side traces 68 -> 3
soa_zip_compare_lt      4.7ms-class -> 4.243ms and side traces 68 -> 3
```

Count keeps the grouped multi-counter branch policy. Numeric scalar and numeric
multi-counter count variants were measured and rejected in generated LuaTrace
because they were slower than grouped branch counters.

```text
i32_count_gt          previous ~3.0ms -> 2.456ms
u8_bytespan_count_gt  previous ~3.0ms -> 2.408ms
```

Done when:

```text
branch/select/multi-counter variants are benchmarked
default policy is chosen from numbers
side-trace counts are recorded
```

### 7. Gather/Scatter Policy

Consume scatter conflict facts. Add new index facts only at the semantic layer if
needed.

Status: done for the conflict semantics currently represented by the descriptor.
LuaTrace now exposes `kernel_plan.scatter_plan`:

```text
StencilScatterUniqueIndices      -> scatter=unique_indices, grouped lowering allowed
StencilScatterLastWriteWins      -> scatter=ordered_last_write, scalar conservative lowering
StencilScatterConflictUndefined  -> scatter=conflict_undefined, scalar conservative lowering
```

Unique-index scatter is the only case allowed to use grouped trace lowering.
Ordered or undefined conflict policies remain scalar because the descriptor does
not yet carry stronger index distribution facts beyond the conflict contract.

Done when:

```text
unique-index scatter has a distinct plan
arbitrary scatter remains conservative
benchmarks cover both
```

### 8. Diagnostics And Inspection

Expose plan comments in generated source and add a debug API if needed:

```lua
StencilLuaJIT.plan_artifact(artifact)
StencilLuaJIT.emit_lua_source({ artifact }, { comments = "plan" })
```

Done when plan inspection can answer:

```text
why this group?
why no primitive?
why this predicate shape?
which facts were consumed?
which facts were ignored?
```

## Completion Definition

LuaTrace backend completion means:

```text
[x] all descriptor topologies lower through AccessPlan
[x] all loop grouping/tail decisions lower through LoopPlan
[x] explicit schedules preserved
[x] AutoVector facts consumed
[x] alias/noalias/readwrite/readonly consumed where legal
[x] trip-count facts consumed
[x] copy/fill primitive paths implemented or explicitly rejected by numbers
[x] reductions consume reassociation/float semantics
[x] predicate shapes chosen by measured policy
[x] scatter conflict semantics consumed
[x] generated source includes plan comments
[x] tests cover plan legality
[x] full descriptor benchmark reports no unmeasured regressions
[x] real CFG benchmark remains healthy
```

Only after this checklist is complete should LuaTrace be called complete.

Current measured gates:

```text
code_ir suite:
  40 passed, 0 skipped, 0 failed

real CFG benchmark, n=5,000,000:
  cranelift cfg sum_i32  median 25.041ms
  luatrace cfg sum_i32   median  7.309ms

full descriptor matrix, n=2,000,000, artifacts=36:
  luatrace emit source all       median   2.190ms
  luatrace emit+load all         median   2.163ms
  copy-patch build bank all      median 444.873ms
  copy-patch install bank all    median   1.151ms

primitive legality cells:
  lt i32_copy          median 0.781ms
  cp i32_copy          median 0.836ms
  lt u8_bytespan_copy  median 0.112ms
  cp u8_bytespan_copy  median 0.120ms
  lt u8_bytespan_fill  median 0.055ms
  cp u8_bytespan_fill  median 0.066ms
  lt i32_scatter       median 2.343ms
  cp i32_scatter       median 2.272ms

known measured policy gaps:
  i32_count_gt              lt 2.480ms vs cp 0.256ms
  i32_compare_gt            lt 3.495ms vs cp 0.354ms
  i32_zip_compare_lt        lt 4.277ms vs cp 0.818ms
  u8_bytespan_count_gt      lt 2.433ms vs cp 0.144ms
  u8_bytespan_compare_gt    lt 1.356ms vs cp 0.114ms
```
