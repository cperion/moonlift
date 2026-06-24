# LuaTrace Stencil Backend

LuaTrace is a real MoonStencil backend. It consumes the same scheduled
`StencilArtifact` values as copy-patch, but materializes them as generated
LuaJIT loops instead of binary machine-code stencils.

The backend boundary is:

```text
MoonStencil descriptor + schedule + vector facts
  -> LuaTrace provider-local trace plan
  -> generated LuaJIT source
  -> named Lua functions in __moonlift_luajit_stencil_symbols
```

LuaTrace does not rediscover loops from MoonCode. It receives already-selected
stencil descriptors and must lower those descriptors honestly.

## Trace Plan

Each artifact gets a provider-local trace plan:

```text
domain_stride
group
reason
branch shape
```

The trace plan is not a semantic schedule. It is a LuaJIT materialization plan
derived from the semantic schedule.

```text
StencilScheduleVector
  lanes * unroll * interleave; explicit vector schedules are honored

StencilScheduleUnrolled
  factor; explicit unroll schedules are honored

StencilScheduleAutoVector
  uses StencilVectorizationFacts to decide whether grouping is profitable
```

LuaTrace grouping is scalar trace grouping. It is not SIMD and does not claim to
implement vector lanes. SIMD belongs to copy-patch/C stencils.

## Fact Consumption

LuaTrace must consume the facts that matter to LuaJIT trace shape:

```text
unit_stride:
  enables AutoVector trace grouping

dynamic stride:
  limits grouping because every lane carries extra address arithmetic

stencil kind:
  caps AutoVector-derived grouping so implicit schedules do not create oversized
  traces
```

Facts that are currently target-C-only, such as exact alignment and host vector
feature requirements, stay visible but do not imply SIMD in LuaTrace.

## Grouping Policy

LuaJIT likes small stable traces. It does not like one huge generated loop body
for every schedule.

Explicit `StencilScheduleVector` and `StencilScheduleUnrolled` values are
preserved. The current AutoVector policy is:

```text
reduce / scan:
  group up to 16

map / zip_map / copy / fill / cast:
  group up to 8

in_place / map_reduce / zip_reduce:
  group up to 8

compare / zip_compare / count:
  group up to 4

find / partition / gather / scatter:
  scalar by default
```

Dynamic-stride descriptors cap AutoVector grouping at 4. Non-unit domain stride
disables grouping.

## Branch Shape

Predicate kernels stay branch-shaped unless measurement proves a different
shape wins for a specific vocabulary. Current measurements showed that replacing
`count` with arithmetic select-shaped accumulation was slower for LuaJIT on the
current workloads, so the backend keeps the direct branch form.

## Backend Role

LuaTrace is the instant backend:

```text
low materialization latency
good generated-source inspectability
good enough for short-lived or editor-time kernels
shared descriptor semantics with copy-patch
```

Copy-patch remains the steady-state performance reference:

```text
host C compiler optimization
real SIMD/autovec
cached binary banks
```

Both backends must remain descriptor-equivalent. Performance differences belong
to provider-local materialization, not to semantic stencil selection.
