# LuaJIT Copy-Patch Stencil Backend

This document specifies the Moonlift LuaJIT copy-patch stencil backend.

The design goal is not to make LuaJIT trace high-level Moonlift loops. The
design goal is to use Moonlift's typed facts and Llisle-selected stencils to
compile MoonCode into resolved native machine-code blobs, then package those
blobs inside a self-contained LuaJIT load artifact with a simple `gen / param / state` runtime ABI.

```text
MoonCode
  -> Moonlift facts
  -> Llisle stencil selection
  -> C-backend-produced stencil bank
  -> copy bytes from compiled bank entries
  -> patch/resolve selected native blobs
  -> mixed LuaJIT artifact
      Lua source control plane
      embedded resolved native stencil blobs
      gen / param / state runtime glue
```

## Doctrine

```text
Stencils are compile-time semantic native-kernel shapes.
The C backend produces the native stencil bank from portable C.
Copy-patch consumes compiled bank entries and emits resolved native blobs.
Lua source is the canonical self-contained artifact container. LuaJIT bytecode is an optional derived packaging/cache form.
gen / param / state is the runtime execution ABI.
FFI function pointers are the native call seam.
```

The backend produces a self-contained LuaJIT-loadable artifact. That artifact is
ordinary Lua source plus native machine-code byte strings that
have already been copied from the stencil bank and resolved by the Moonlift
compiler.

Runtime does not need the stencil bank and does not run a compiler. Runtime only
loads the mixed chunk, installs already-resolved embedded blobs into executable
memory, and casts them to function pointers.

## Non-goals

This backend is not:

- a general object-file emitter
- a system linker replacement
- a runtime optimizing compiler
- a LuaJIT trace-shaping trick
- a runtime dependency on a stencil-bank shared library
- a separate deployed AOT shared-library pipeline
- a replacement for Cranelift where arbitrary control lowering is needed

This backend is:

- a finite native-kernel backend for stencil-shaped MoonCode
- packaged canonically as Lua source plus resolved native blobs
- orchestrated by LuaJIT through a small runtime ABI

## Core pipeline

```text
Moonlift source / DSL
  -> MoonSyntax / MoonTree
  -> typecheck / ownership / region facts
  -> MoonCode
  -> kernel/value/memory/effect facts
  -> Llisle relation: classify stencil candidate
  -> Llisle relation: select stencil
  -> stencil descriptor
  -> ensure C-backend stencil bank for user toolchain
  -> select compiled bank entry
  -> copy entry bytes from bank
  -> patch resolution
  -> resolved native blob
  -> LuaJIT mixed artifact emission
```

The important point is that Llisle selects semantic stencil shapes before native
code is emitted. The copy-patch compiler does not discover program meaning from
Lua code. It receives a typed stencil descriptor.

## Why this is not normal AOT

Normal AOT emits a native object or shared library:

```text
compiler
  -> object file
  -> linker
  -> native artifact
  -> runtime loads/calls artifact
```

This backend emits a mixed LuaJIT artifact:

```text
compiler
  -> Lua source chunk
      + embedded resolved native blob strings
      + patch metadata for diagnostics
      + runtime install/call glue
```

That unlocks:

- one Lua source chunk as the canonical distribution/debug unit
- no per-specialization object file
- no external linker in the final deployed artifact
- no runtime dependency on the stencil bank
- direct packaging with Lua-side glue and metadata
- LuaJIT-native module loading
- FFI-based function pointer calls
- compiler-resolved native code without runtime bank access or patching

The canonical artifact is still loaded with `load(...)`, but it carries native data-plane
payloads as Lua string constants.

```lua
local mod = assert(load(lua_source_with_machine_code_blobs, "compiled.moonjit"))()
```

## Self-contained mixed load artifact

The final JIT-path artifact is canonically a single Lua source chunk loadable by LuaJIT.

```text
artifact =
  Lua source
  + embedded resolved machine-code blobs
  + blob metadata
  + FFI declarations
  + gen / param / state glue
```

The stencil bank is not part of this artifact. It is not opened, linked, or
referenced at runtime.

The JIT path is therefore just:

```lua
local artifact = read_file("compiled.moonjit")
local module = assert(load(artifact, "compiled.moonjit"))()
```

or:

```lua
local artifact = read_file("compiled.moonjitbc")
local module = assert(load(artifact, "compiled.moonjitbc"))()
```

The loaded source chunk owns its embedded native bytes. The runtime installer only
copies those bytes to executable memory and casts the resulting address.

## Control plane and data plane

The generated artifact has two planes.

```text
control plane:
  Lua source
  module exports
  parameter object construction
  gen / param / state wrappers
  lazy executable-memory installation
  diagnostics metadata

data plane:
  resolved native machine-code blobs
  ctype declarations
  blob names
  target and feature metadata
```

The control plane is LuaJIT. The data plane is native code.

## Stencil vocabulary

The stencil vocabulary is the finite semantic surface that makes copy-patch
codegen practical.

Core stencil families:

```text
fill
copy
map
zip_map
cast
compare
gather
scatter
reduce
map_reduce
zip_reduce
count
```

These are not target instructions. They are semantic kernel shapes.

Examples:

```text
map:
  one output element from one input element

zip_map:
  one output element from synchronized input elements

reduce:
  many input elements collapse to one scalar

map_reduce:
  input element is transformed before accumulation

zip_reduce:
  synchronized input elements are combined before accumulation

count:
  predicate result is accumulated as a count

gather:
  input topology is indexed/non-contiguous

scatter:
  output topology is indexed/non-contiguous
```

The stencil layer should not encode:

```text
AVX2 instruction names
unroll factors
register allocation details
object-file relocations
LuaJIT trace assumptions
```

Those are bank-entry and scheduling concerns.

## Stencil descriptor

A selected stencil is represented as a descriptor. The descriptor is explicit
enough to choose a compiled stencil bank entry and resolve patches.

Example:

```lua
{
  kind = "zip_map",
  op = "add",
  elem_ty = "i32",
  result_ty = "i32",

  inputs = {
    {
      name = "lhs",
      topology = "contiguous",
      elem_ty = "i32",
      arg = 1,
    },
    {
      name = "rhs",
      topology = "contiguous",
      elem_ty = "i32",
      arg = 2,
    },
  },

  outputs = {
    {
      name = "dst",
      topology = "contiguous",
      elem_ty = "i32",
      arg = 0,
    },
  },

  extent = {
    kind = "runtime_len",
    arg = 3,
  },

  alias = "noalias",
  tail = "scalar",
  effects = { "write:dst" },
}
```

The descriptor is compiler data. It is not the runtime ABI.

## Stencil bank model

Native stencil bytes come from a compiler-side stencil bank, not from handwritten
machine-code literals.

The bank is produced by the always-available Moonlift C backend:

```text
Moonlift stencil-bank generator
  -> portable C stencil-bank source
  -> user's C compiler
  -> native bank for user's architecture / ABI / compiler flags
  -> compiler-side bank cache
```

The bank is a native-code quarry for the Moonlift compiler. It is not a runtime
dependency.

```text
compiled stencil bank
  -> copy selected function/entry bytes
  -> resolve patches
  -> embed resolved bytes into final LuaJIT artifact
```

The final artifact does not reference the bank, the C compiler, or the bank
+cache path.

The bank entry model is:

```lua
{
  name = "zip_map_i32_add_scalar",
  source = "c_backend_stencil_bank",
  target = "detected-from-user-compiler",
  features = { "baseline" },

  stencil = {
    kind = "zip_map",
    op = "add",
    elem_ty = "i32",
    result_ty = "i32",
    topology = "contiguous",
  },

  abi = "param_ptr_v1",
  ctype = "void (*)(void*)",

  bytes = "copied from compiled bank entry",

  patches = {
    { name = "dst_off", kind = "i32", offset = 12 },
    { name = "lhs_off", kind = "i32", offset = 19 },
    { name = "rhs_off", kind = "i32", offset = 26 },
    { name = "len_off", kind = "i32", offset = 33 },
  },
}
```

Patch slots must be explicit. Hidden relocation logic is not allowed.

## Bank cache

The stencil bank is cached for the compiler, not for runtime.

Possible cache locations:

```text
~/.cache/moonlift/stencil-bank/<key>/
.moonlift/cache/stencil-bank/<key>/
```

Cache key:

```text
Moonlift version
stencil bank source hash
C compiler path
C compiler version
CFLAGS / target flags
reported target triple
CPU feature mode
LuaJIT ABI mode
param ABI version
bank ABI version
```

A cache hit lets the compiler copy native stencil entries without rebuilding the
bank. The deployed artifact is still self-contained.

## Patch resolution

Patch resolution happens during Moonlift compilation.

```text
compiled bank entry bytes
  + stencil descriptor
  + ABI layout
  + target model
  -> resolved native bytes
```

The emitted LuaJIT artifact receives resolved bytes, not a reference to the
stencil bank.

Allowed patch kinds:

```text
u8
u16
u32
u64
i8
i16
i32
i64
rel32
abs64
```

Patch resolution must produce diagnostics metadata:

```lua
{
  blob = "zip_add_i32_0",
  bank_entry = "zip_map_i32_add_scalar",
  patches = {
    { name = "dst_off", kind = "i32", offset = 12, value = 0 },
    { name = "lhs_off", kind = "i32", offset = 19, value = 8 },
    { name = "rhs_off", kind = "i32", offset = 26, value = 16 },
    { name = "len_off", kind = "i32", offset = 33, value = 24 },
  },
}
```

This metadata is for explanation, debugging, tests, and LSP/tooling. It is not
needed by the hot path.

## Runtime ABI: gen / param / state

The generated module uses `gen / param / state` as its execution ABI.

```text
gen:
  stable callable executor

param:
  stable cdata/table containing buffers, constants, lengths, and native fn ptrs

state:
  progress cursor; nil terminates
```

For a single-shot native stencil:

```lua
local function gen(param, state)
  if state ~= 0 then return nil end
  param.fn(param.native_param)
  return nil
end
```

For a streaming executor:

```lua
local function gen(param, state)
  local next_state, value = param.source_gen(param.source_param, state)
  if next_state == nil then return nil end
  return next_state, value
end
```

The same runtime shape can host:

- native blob stencils
- Lua fallback stencils
- debug/interpreter stepping
- process-style execution
- future fused stream paths

The native stencil does not have to expose a Lua iterator. It only has to fit
the same executor boundary.

## Native function ABI

Native blobs should use a small finite ABI.

Preferred native ABI:

```c
void stencil_fn(void* param);
```

The parameter pointer points to a generated cdata struct.

Example:

```c
typedef struct {
  int32_t* dst;
  const int32_t* lhs;
  const int32_t* rhs;
  intptr_t n;
} ML_ZipMapI32Param;
```

The generated LuaJIT module owns the FFI declarations:

```lua
ffi.cdef[[
typedef struct {
  int32_t* dst;
  const int32_t* lhs;
  const int32_t* rhs;
  intptr_t n;
} ML_ZipMapI32Param;

typedef void (*ML_StencilFn)(void*);
]]
```

Reasons for the `void* param` ABI:

- one stable function pointer shape
- fewer FFI ctype variants
- simple bank-entry assumptions
- easy parameter layout patching
- easy extension with new fields

## Generated module shape

The generated artifact should look like ordinary LuaJIT-compatible Lua source plus embedded
blobs. Source is the canonical form. It may be compiled to LuaJIT bytecode as an
optional derived cache/package; in both cases the machine-code blobs are Lua
constants inside the chunk.

```lua
local ffi = require("ffi")
local rt = require("moonlift.luajit_blob_rt")

ffi.cdef[[
typedef struct {
  int32_t* dst;
  const int32_t* lhs;
  const int32_t* rhs;
  intptr_t n;
} ML_ZipMapI32Param;

typedef void (*ML_StencilFn)(void*);
]]

local blobs = {
  zip_add_i32_0 = "\x48\x8b\x07...",
}

local blob_meta = {
  zip_add_i32_0 = {
    bank_entry = "zip_map_i32_add_scalar",
    target = "x64_sysv",
    features = { "baseline" },
  },
}

local fns = {}

local function install(name)
  local fn = fns[name]
  if fn ~= nil then return fn end
  fn = rt.install(blobs[name], "ML_StencilFn")
  fns[name] = fn
  return fn
end

local function gen_zip_add_i32(param, state)
  if state ~= 0 then return nil end
  install("zip_add_i32_0")(param.native)
  return nil
end

local function zip_add_i32(dst, lhs, rhs, n)
  local native = ffi.new("ML_ZipMapI32Param")
  native.dst = dst
  native.lhs = lhs
  native.rhs = rhs
  native.n = n

  return gen_zip_add_i32({ native = native }, 0)
end

return {
  zip_add_i32 = zip_add_i32,
}
```

The exact generated source is the primary artifact. It can later be
bytecode-compiled with LuaJIT as an optional packaging optimization. The JIT load
path remains simple:

```lua
local mod = assert(load(source_plus_blobs, "compiled.moonjit"))()
```

or:

```lua
local mod = assert(load(bytecode_plus_blobs, "compiled.moonjitbc"))()
```

## Blob runtime

Unsafe executable-memory operations must be isolated in one runtime module.

Runtime module:

```lua
moonlift.luajit_blob_rt
```

Required API:

```lua
rt.page_size()
rt.alloc_exec(size)
rt.copy_blob(dst, bytes, size)
rt.protect_rx(ptr, size)
rt.flush_icache(ptr, size)
rt.install(bytes, ctype)
rt.free(ptr, size)
```

Generated modules should not call `mmap`, `VirtualAlloc`, `mprotect`, or platform
cache-flush APIs directly. They call `rt.install`.

`rt.install(bytes, ctype)` returns:

```lua
ffi.cast(ctype, executable_ptr)
```

The runtime owns:

- page alignment
- write/execute policy
- platform-specific allocation
- instruction-cache flushing
- lifetime management
- debug memory poisoning if needed

## Module load and installation policy

Resolved native bytes are embedded in the LuaJIT artifact.

Installation can be:

```text
eager:
  install all blobs at module load

lazy:
  install each blob on first call
```

Default policy should be lazy.

Lazy install is not runtime compilation. It is executable-memory materialization
of already-resolved code.

```text
compile time:
  ensure stencil bank
  select stencil
  copy compiled bank entry bytes
  patch final bytes
  embed final bytes in LuaJIT artifact

runtime:
  load mixed LuaJIT chunk
  copy embedded final bytes to executable memory
  cast pointer
```

## Cache model

Compile-time blob/cache key:

```text
target
target ABI
CPU feature set
stencil kind
op
input/output types
topology
tail policy
alias facts
bank source version
bank ABI version
param ABI version
```

Runtime cache key:

```text
blob name
ctype
```

Since runtime receives embedded resolved blobs, runtime caching is intentionally
simple and never depends on the stencil bank cache.

## Llisle role

Llisle owns stencil selection.

Example relation shape:

```lua
llisle {
  relation. select_store_stencil {
    input { ctx [StoreStencilFact] },
    output { selection [StoreStencilSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  constructor. store_zip_map [build_store_zip_map],

  rule. store_zip_map {
    llisle.select_store_stencil { ctx = P. ctx },
    when {
      (P. ctx.class.kind :eq (zip_map))
        * (P. ctx.store_ready :eq (true)),
    },
    run {
      ret {
        selection = store_zip_map {
          dst = P. ctx.dst,
          lhs = P. ctx.class.lhs,
          rhs = P. ctx.class.rhs,
          op = P. ctx.class.op,
        },
      },
    },
  },
}
```

The selected value becomes a stencil descriptor for the copy-patch compiler.

## Relationship to LuaJIT tracing

LuaJIT remains important, but not because it must trace through high-level
Moonlift computation.

LuaJIT provides:

- module loading
- source artifact container, with optional bytecode cache
- FFI
- cdata structs
- function pointer calls
- fast Lua orchestration
- `gen / param / state` runtime shape

Native stencil blobs provide:

- hot numeric/memory loops
- predictable machine code
- bank-entry-controlled low-level performance

The design does not depend on LuaJIT discovering and optimizing high-level
iterator chains. The compiler already selected and emitted the native kernel.

## Relationship to luafun-style gen / param / state

`luafun` demonstrates that `gen / param / state` is a LuaJIT-friendly execution
shape.

Moonlift reuses the shape as a runtime ABI, but stencils replace runtime
combinator discovery with compile-time classification.

```text
luafun:
  runtime iterator algebra
  LuaJIT traces stable combinators

Moonlift stencil backend:
  compile-time stencil algebra
  copy-patch copies compiled bank entries and emits resolved native kernels
  LuaJIT orchestrates through gen / param / state
```

The result is:

```text
same LuaJIT-friendly executor physics
more explicit compiler semantics
predictable native hot path
```

## Diagnostics and inspection

Every emitted blob should be explainable.

Required diagnostic facts:

```lua
{
  mooncode_node = "...",
  relation = "select_store_stencil",
  rule = "store_zip_map",
  alt = nil,
  stencil = {
    kind = "zip_map",
    op = "add",
    elem_ty = "i32",
  },
  bank_entry = "zip_map_i32_add_scalar",
  target = "x64_sysv",
  patches = {
    { name = "dst_off", offset = 12, value = 0 },
    { name = "lhs_off", offset = 19, value = 8 },
    { name = "rhs_off", offset = 26, value = 16 },
    { name = "len_off", offset = 33, value = 24 },
  },
}
```

Tools should be able to answer:

- why this stencil was selected
- why another stencil was rejected
- which stencil bank entry was copied
- which patch values were applied
- which runtime ABI struct is expected
- whether the blob is scalar/vector/fallback

## Fallback policy

When no native bank entry matches a selected stencil, the backend must choose one
explicit fallback path.

Possible fallback kinds:

```text
Lua gen / param / state executor
C backend helper
Cranelift backend
diagnostic hard failure
```

Silent fallback is not allowed.

The selected fallback must be represented in diagnostics:

```text
selected fallback Lua executor
because no x64 AVX2 bank entry matched gather_i32_index64
```

## Safety model

This backend emits and executes native machine code. Safety rules are strict.

Required checks:

- stencil bank target must match runtime target
- stencil bank feature requirements must be satisfied
- copied blob size must match bank metadata
- patch offsets must be in bounds
- executable memory must not be writable after install
- instruction cache must be flushed where required
- function pointer ctype must match blob ABI
- parameter struct layout must match patch assumptions

Generated modules must not hand-roll executable-memory handling. They use the
runtime module.

## Bootstrap relevance

This backend is useful for bootstrap because the artifact remains LuaJIT-native.

```text
Moonlift compiler
  emits LuaJIT mixed artifact
  artifact carries resolved native stencil blobs
  LuaJIT loads source
  native blobs execute hot kernels
```

That avoids requiring every stencil specialization to become a linked native
object during bootstrap.

It also keeps the compiler architecture explicit:

```text
Moonlift semantics
  -> Llisle choices
  -> stencil descriptors
  -> C-backend stencil bank
  -> copy-patch blobs
  -> LuaJIT mixed artifact
```

## Open design constraints

The following choices must remain explicit in implementation:

- target ABI names
- parameter ABI versions
- CPU feature detection boundary
- executable memory lifetime
- blob ownership and freeing
- scalar vs vector bank entry selection
- tail policy representation
- debug/disassembly hooks
- diagnostics retention in source artifacts and optional bytecode packages

These are not optional details; they define whether the backend is reproducible
and inspectable.

## Summary

The LuaJIT copy-patch stencil backend is a mixed-artifact backend.

```text
Compile-time:
  MoonCode facts
  -> Llisle stencil selection
  -> C-backend stencil bank for user toolchain
  -> copy-patch resolved native blobs
  -> LuaJIT mixed artifact emission

Runtime:
  LuaJIT loads source chunk
  installs embedded resolved blobs
  calls native code through FFI
  orchestrates via gen / param / state
```

This gives Moonlift a fast, compact, LuaJIT-native backend path for
stencil-shaped code without turning every specialization into a deployed external AOT object or a
runtime stencil-bank dependency.
