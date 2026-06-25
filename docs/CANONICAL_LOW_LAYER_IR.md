# Canonical Low-Layer IR Shape

The low layers of a compiler family should converge on one canonical shape:

```text
source language
  -> typed kernel facts
  -> semantic descriptor
  -> target schedule
  -> concrete realization
  -> callable artifact
```

The key rule is:

```text
Descriptor is semantics.
Schedule is execution strategy.
Realization is materialization.
```

Vectorization belongs in the schedule. It must not create a new semantic
vocabulary.

This shape is not Lalin-specific. It is a reusable compiler architecture for
any language, DSL, or runtime that can expose typed kernels. Lalin is one
producer of this stack. LLB languages, LLPVM machines, query DSLs, tensor/image
kernels, bytecode runtimes, and embedded data-processing libraries can use the
same shape if they can describe:

```text
what is iterated
what is read
what is written
what is accumulated
what algebra is valid
what memory facts are known
```

That is why this layer should not be named after C, LuaJIT bytecode, native banks, or even
Lalin. It is a small descriptor/schedule/realization algebra.

## Descriptor

A descriptor says what a kernel means.

It is independent of the backend, target ISA, unrolling choice, vector width,
or artifact format.

Canonical descriptor fields:

```text
domain
accesses
access topologies
element operator
reducer
skeleton
memory semantics
result type
params
```

Example:

```lua
descriptor. reduce {
  domain = range1d(index, step = 1),

  accesses = {
    xs  = read   i32 contiguous(1),
    acc = reduce i32 scalar(0),
  },

  reducer = add(i32, wrap),
  skeleton = reduce,
  result = i32,
}
```

The descriptor operation vocabulary should stay small:

```text
copy
fill
map
zip_map
reduce
map_reduce
zip_reduce
scan
find
count
partition
gather
scatter
in_place_map
```

These are semantic operation families, not backend variants. A descriptor may
also carry a skeleton field for control shape such as apply, reduce, scan,
copy, find, or partition. Operation family and skeleton are related, but they
are not the same axis.

## Schedule

A schedule says how a backend executes a descriptor on a target.

Vectorization is modeled here:

```lua
schedule. vector {
  lanes = fixed(4),
  unroll = 2,
  interleave = 1,
  feature = sse2,
  alignment = unaligned,
  tail = scalar_tail,
  reduction = horizontal,
  compiler = copy_patch_stencil,
}
```

Canonical schedule choices:

```text
scalar_index
scalar_pointer
unrolled
vector
blocked
tiled
parallel
closed_form
```

The schedule carries explicit facts:

```text
feature requirements
lane policy
alignment policy
tail policy
reduction strategy
compiler policy
profit/rank
proofs
rejects
```

The generic rule is:

```text
ReduceDescriptor + VectorSchedule
not VectorReduceDescriptor
```

Likewise:

```text
ZipMapDescriptor + VectorSchedule
not VectorZipMapDescriptor
```

This keeps the descriptor algebra reduced and lets scalar, unrolled, vector,
blocked, tiled, and parallel executions compete as backend choices.

## Realization

A realization says what concrete implementation materializes a scheduled
descriptor.

Possible providers:

```text
C stencil
binary copy-patch stencil
Lua trace residual
external runtime symbol
```

Example:

```lua
realization. binary_stencil {
  descriptor = reduce_descriptor,
  schedule = vector_schedule,
  symbol = "ml_stencil_reduce_array_i32_add_to_i32_s1_v4_u2",
  abi = {
    params = { ptr(i32), i32, i32, i32 },
    result = i32,
  },
}
```

This layer owns:

```text
symbol names
ABI
binary bank entries
relocations
constant pools
runtime patch values
target guards
artifact embedding
```

## Artifact ABI

The final boundary should be boring and stable:

```text
typed function pointer
plain C ABI
explicit params
explicit result
no hidden Lua state
no semantic side channels
```

Example:

```c
int32_t (*sum_stencil)(const int32_t *xs, int32_t start, int32_t stop, int32_t init);
```

LuaJIT artifacts call this through FFI. C output can emit the same body or call
the same artifact. Native backend experiments can either call the artifact or
lower the same scheduled descriptor directly.

## Generic Stack

```text
source language
  -> typed kernel facts
  -> semantic descriptor
  -> target schedule
  -> concrete realization
  -> callable artifact
```

The descriptor vocabulary may grow per domain, but the architectural split
should not change:

```text
semantics in descriptor
execution choice in schedule
machine artifact in realization
```

This is the part worth standardizing.

## Lalin Projection

```text
Lalin DSL
  -> LalinSyntax
  -> LalinTree
  -> typed Code CFG

typed Code CFG
  -> graph facts
  -> flow facts
  -> value facts
  -> memory facts
  -> effect facts

facts
  -> KernelPlan

KernelPlan
  -> StencilDescriptor

TargetModel + KernelPlan + Descriptor
  -> SchedulePlan

Descriptor + Schedule
  -> Realization

Realization
  -> C source
  -> object section
  -> binary stencil bank
  -> embedded Lua artifact
  -> runtime function pointer
```

Lalin implements the generic layers with concrete ASDL families:

```text
typed kernel facts
  = LalinCode plus graph/flow/value/memory/effect facts

semantic descriptor
  = LalinKernel plans and LalinStencil.StencilDescriptor

target schedule
  = LalinSchedule plans and LalinStencil.StencilSchedule

concrete realization
  = LalinStencil.StencilArtifact, LalinExec fragments, LJStencilMachinePlan,
    backend projections

artifact planning
  = lua/lalin/stencil_artifact_plan.lua constructs descriptor-backed
    StencilArtifact records with ABI, symbol, schedule, and proofs

source realization
  = lua/lalin/stencil_c.lua turns planned artifacts into C source

callable artifact
  = LuaJIT bytecode artifact, C object, native bank entry, or link artifact
```

The implementation-specific spelling is:

```text
LalinStencil.StencilReduce + LalinStencil.StencilScheduleVector
not LalinStencil.StencilReduceVector
```

and:

```text
LalinStencil.StencilZipMap + LalinStencil.StencilScheduleVector
not LalinStencil.StencilZipMapVector
```

## Doctrine

The canonical low-layer IR is not C, LuaJIT bytecode, native machine code, backend
commands, or a Lalin-only internal form.

It is:

```text
typed stream descriptor
  + explicit schedule
  + realization ABI
```

Map, reduce, zip, scan, gather, scatter, and partition are semantic operation
families.

Vectorize, unroll, tile, block, parallelize, mask tail, scalar-tail, and choose
a compiler strategy are schedules.

C, binary copy-patch, Lua trace residuals, and native bank entries are realizers.

## Generic Use Cases

This model applies wherever a program can be reduced to typed kernel facts.

Examples:

```text
Lalin native functions
  typed CFG -> stream descriptors -> schedules -> native artifacts

LLPVM machines
  bytecode records -> process/kernel descriptors -> schedules -> fast dispatch

LLB languages
  parserless DSL values -> semantic descriptors -> schedules -> generated APIs

query engines
  query plan fragments -> map/filter/reduce/join descriptors -> target schedules

image pipelines
  pixel domains -> stencil/window descriptors -> tile/vector/parallel schedules

tensor kernels
  index domains -> contraction/reduction descriptors -> tile/vector schedules

bytecode runtimes
  opcode traces -> linear descriptors -> copy-patch or threaded-code realization
```
