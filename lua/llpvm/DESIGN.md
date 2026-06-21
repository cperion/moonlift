# LLPVM Design

Status: official Moonlift API design for `lua/llpvm`.

LLPVM means:

```text
Low-Level PVM
```

It is the Moonlift-native substrate for building small, typed, cacheable
interpreters and lowerers. PVM means PicoVM: a precise small machine that
transforms one operation world into another:

```text
source world ops
    -> typed machine
target world ops
```

LLPVM exists because Moonlift systems keep rediscovering the same shape:

```text
ASDL products
lazy streams
phase boundaries
memoized results
diagnostics
bytecode-like compact storage
Lua no-parens authoring
native Moonlift execution
```

LLPVM turns that shape into an official Moonlift standard-library API surface.

## Doctrine

```text
ASDL defines meaning.
LLPVM stores and runs meaning.
Lua authors VM families.
Moonlift executes VM instances.
Phases are cache and recording boundaries.
Streams are pull-based machines.
Buffers are materialized facts.
Diagnostics are values.
No Lua callback is the canonical hot path.
```

Raw execution tricks are allowed inside implementation files. They are not the
design. The public design is worlds, ops, streams, machines, phases, recordings,
and reports.

## Position In Moonlift

LLPVM sits below high-level systems such as compiler phases, MLUI, LuaBridge,
and future language work:

```text
Lua no-parens API
    -> PVM-style typed operation authoring
    -> direct LLPV bytecode image
    -> native Moonlift VM regions
    -> handles / streams / buffers / diagnostics / C ABI
```

It must not depend on `lua/ui`, MLUI, or the current Lua-hosted PVM triplet
model. It may learn from them, but it owns its own operation-world authoring
surface and bytecode boundary.

## PVM-Style Type Authoring

Free-form Moonlift remains valid and preferred for bespoke kernels, low-level
stores, and system internals. LLPVM is the standard-library solution for a
specific recurring job:

```text
define a typed instruction language
define worlds over that language
construct op streams with PVM-like builders
load a borrowed image into a native VM
apply phases and materialize buffers incrementally
```

The first design artifact is the operation-world schema, not helper code.

Suggested Lua module:

```text
lua/llpvm/asdl.lua
```

Top-level ASDL families:

```text
LlPvm.Symbol
LlPvm.Type
LlPvm.Abi
LlPvm.World
LlPvm.OpSchema
LlPvm.Op
LlPvm.Arg
LlPvm.Stream
LlPvm.Machine
LlPvm.Phase
LlPvm.Cache
LlPvm.Report
LlPvm.Diagnostic
```

The normal Lua facade writes the LLPV image directly. ASDL literals and
FastBuilders remain available for schema design, tests, and debug tooling, but
they are not the hot runtime boundary. Literals are constructors when the
language has the information required to construct the product directly. Do not
invent parallel constructor APIs when the literal form is already the idiomatic
Moonlift form.

## Core Products

### Symbols

No durable semantic identity is a Lua string at runtime.

```moonlift
struct LlSymbol
    hash: u64
    bytes_off: index
    bytes_len: index
end

handle LlSymbolRef : u32 invalid 0
    target LlSymbol
end
```

Symbols are interned in the kernel store. Lua strings are accepted at the Lua API
boundary and immediately interned.

### Diagnostics

```moonlift
struct LlDiagnostic
    code: i32
    primary_pos: index
    secondary_pos: index
    message: LlSymbolRef
end

handle LlDiagnosticRef : u32 invalid 0
    target LlDiagnostic
end
```

No `error()` for protocol outcomes. ABI functions may return status codes, but
inside Moonlift a failure is a typed continuation carrying diagnostics.

### ABI

An ABI defines an operation language.

```moonlift
struct LlAbi
    name: LlSymbolRef
    version: u32
    op_schema: LlOpSchemaRef
    resource_schema: LlTypeRef
    generation: u64
end

handle LlAbiRef : u32 invalid 0
    target LlAbi
end
```

The ABI says what kinds of ops exist, what payload each op has, and what
resources those ops may reference.

### World

A world is a semantic layer using one ABI.

```moonlift
struct LlWorld
    name: LlSymbolRef
    abi: LlAbiRef
    generation: u64
end

handle LlWorldRef : u32 invalid 0
    target LlWorld
end
```

Every stream, buffer, machine input, machine output, phase input, and phase
output has a world. A cache key includes world generation.

### Ops

LLPVM has a compact runtime op record, but op meaning comes from ASDL/schema.

```moonlift
struct LlOp
    world: LlWorldRef
    kind: u16
    payload: u32
end

handle LlOpRef : u32 invalid 0
    target LlOp
end
```

`kind` is an encoding discriminant. It is not the architecture. For each ABI,
Lua generates a typed visitor region:

```moonlift
region ll_visit_example_op(vm: ptr(LlVm), op: LlOpRef;
    const_i64(value: i64)
  | add_i64
  | load_local(slot: index)
  | invalid(op: LlOpRef, code: i32))
end
```

Machine bodies use these visitors instead of open-coded payload decoding.

### Buffers

A buffer is a materialized fact.

```moonlift
struct LlBuffer
    world: LlWorldRef
    ops: ptr(LlOpRef)
    len: index
    cap: index
    bytes: index
end

handle LlBufferRef : u32 invalid 0
    target LlBuffer
end
```

Buffers are immutable once published. A builder or recording may mutate a private
buffer until it is sealed.

### Streams

A stream is a lazy pull machine.

```moonlift
struct LlStream
    world: LlWorldRef
    kind: u8
    payload: u32
end

handle LlStreamRef : u32 invalid 0
    target LlStream
end
```

Canonical stream kinds:

```text
empty
once
seq
concat
recording
phase_map
generated
```

There are no public triplets. The stream handle is the protocol object.

### Args

Arguments are interned products and part of cache identity.

```moonlift
struct LlArgValue
    kind: u8
    payload_u64: u64
    payload_ref: u32
end

struct LlArgs
    hash: u64
    values: ptr(LlArgValue)
    len: index
end

handle LlArgsRef : u32 invalid 0
    target LlArgs
end
```

No recursive Lua table cache trie is allowed in the runtime.

### Machines

A machine is executable Moonlift behavior.

```moonlift
struct LlMachine
    kind: u8
    name: LlSymbolRef
    input_world: LlWorldRef
    output_world: LlWorldRef
    entry_symbol: LlSymbolRef
    payload: u32
end

handle LlMachineRef : u32 invalid 0
    target LlMachine
end
```

Canonical machine kinds:

```text
region
function
specialized_interpreter
fused_stream_graph
native_intrinsic
```

There is no canonical `lua_handler` machine kind. Lua generates Moonlift
machines; it is not the normal execution engine.

### Phases

A phase is a named machine boundary with a cache policy.

```moonlift
struct LlCachePolicy
    mode: u8
    args_mode: u8
    commit_mode: u8
    retain_mode: u8
end

struct LlPhaseStats
    calls: u64
    hits: u64
    shared_misses: u64
    misses: u64
    commits: u64
    partial_discards: u64
    evictions: u64
end

struct LlPhase
    name: LlSymbolRef
    input_world: LlWorldRef
    output_world: LlWorldRef
    machine: LlMachineRef
    cache_policy: LlCachePolicy
    generation: u64
    stats: LlPhaseStats
end

handle LlPhaseRef : u32 invalid 0
    target LlPhase
end
```

The phase is the semantic memoization boundary.

### Cache Keys

```moonlift
struct LlPhaseKey
    phase: LlPhaseRef
    input_identity: u64
    args: LlArgsRef
    input_world_generation: u64
    phase_generation: u64
end
```

Pointer identity alone is not a semantic key.

### Recordings

```moonlift
struct LlRecording
    key: LlPhaseKey
    source: LlStreamRef
    buffer: LlBufferRef
    produced: index
    readers: index
    state: u8
    commit_allowed: bool
end

handle LlRecordingRef : u32 invalid 0
    target LlRecording
end
```

Shared misses share a recording. Partial drain never silently commits. Full drain
commits only through the recording lifecycle.

### Cache Entries

```moonlift
struct LlCacheEntry
    key: LlPhaseKey
    buffer: LlBufferRef
    complete: bool
    bytes: index
    generation: u64
end

handle LlCacheEntryRef : u32 invalid 0
    target LlCacheEntry
end
```

Cache entries are explicit products. They are budgeted, reported, and evicted by
regions, not by weak-table behavior.

### Reports

```moonlift
struct LlPhaseReport
    phase: LlPhaseRef
    calls: u64
    hits: u64
    shared_misses: u64
    misses: u64
    commits: u64
    partial_discards: u64
    evictions: u64
    bytes_cached: index
end

struct LlVmReport
    abis: index
    worlds: index
    ops: index
    buffers: index
    streams: index
    machines: index
    phases: index
    recordings: index
    cache_entries: index
    cache_bytes: index
end
```

### VM Owner

```moonlift
struct LlVm
    memory: LlMemoryPool
    symbols: LlSymbolStore
    diagnostics: LlDiagnosticStore
    abis: LlAbiStore
    worlds: LlWorldStore
    ops: LlOpStore
    buffers: LlBufferStore
    args: LlArgsStore
    streams: LlStreamStore
    machines: LlMachineStore
    phases: LlPhaseStore
    recordings: LlRecordingStore
    cache: LlCacheStore
    reports: LlReportStore
end
```

`LlVm` owns registry tables, buffers, recordings, caches, and reports. Handles
are durable identity. Leases are temporary access facts. Owned handles are
discharge obligations.

```moonlift
handle LlVmRef : u32 invalid 0
    target LlVm
end
```

## Region Tree

The header declares the complete machine surface before implementations exist.

Suggested header:

```text
lua/llpvm/native/llpvm_header.mlua
```

### VM Lifecycle

```moonlift
region ll_vm_open(config: LlVmConfig;
    opened(vm: LlVmRef)
  | invalid_config
  | memory_exhausted(needed: index))
end

region ll_vm_close(vm: LlVmRef;
    closed
  | live_leases(count: index)
  | live_recordings(count: index))
end

This is the C-facing trusted close boundary. A future purely Moonlift-internal
owned close protocol must preserve ownership on `live_leases` and
`live_recordings` continuations, for example:

```moonlift
region ll_vm_close_owned(vm: owned LlVmRef;
    closed
  | live_leases(vm: owned LlVmRef, count: index)
  | live_recordings(vm: owned LlVmRef, count: index))
end
```

The plain-handle C boundary is allowed because C owns the external handle
obligation outside Moonlift's type system. Internal Moonlift code should prefer
the owned-preserving protocol once implemented.

region ll_borrow_vm(vm: LlVmRef;
    borrowed(vm: lease ptr(LlVm))
  | stale(vm: LlVmRef)
  | missing(vm: LlVmRef))
end
```

### Symbols And Diagnostics

```moonlift
region ll_intern_symbol(vm: ptr(LlVm), bytes: readonly view(u8);
    symbol(symbol: LlSymbolRef)
  | memory_exhausted(needed: index))
end

region ll_make_diagnostic(vm: ptr(LlVm), code: i32, message: LlSymbolRef;
    diagnostic(diag: LlDiagnosticRef)
  | memory_exhausted(needed: index))
end
```

### ABI And World Definition

```moonlift
region ll_define_abi(
    vm: ptr(LlVm),
    name: LlSymbolRef,
    version: u32,
    op_schema: LlOpSchemaRef,
    resource_schema: LlTypeRef;
    abi(abi: LlAbiRef)
  | duplicate_abi(name: LlSymbolRef)
  | invalid_schema(schema: LlOpSchemaRef)
  | memory_exhausted(needed: index))
end

region ll_define_world(
    vm: ptr(LlVm),
    name: LlSymbolRef,
    abi: LlAbiRef;
    world(world: LlWorldRef)
  | duplicate_world(name: LlSymbolRef)
  | invalid_abi(abi: LlAbiRef)
  | memory_exhausted(needed: index))
end
```

### Op Construction

```moonlift
region ll_make_op(
    vm: ptr(LlVm),
    world: LlWorldRef,
    kind: u16,
    payload: u32;
    op(op: LlOpRef)
  | invalid_world(world: LlWorldRef)
  | invalid_kind(kind: u16)
  | invalid_payload(kind: u16)
  | memory_exhausted(needed: index))
end
```

ABI-specific Lua factories should generate typed construction regions above this
primitive. Public code should not hand-assemble `kind` and `payload`.

### Buffer Lifecycle

```moonlift
region ll_buffer_open(vm: ptr(LlVm), world: LlWorldRef, capacity: index;
    buffer(buffer: LlBufferRef)
  | invalid_world(world: LlWorldRef)
  | memory_exhausted(needed: index))
end

region ll_buffer_push(vm: ptr(LlVm), buffer: LlBufferRef, op: LlOpRef;
    pushed
  | sealed(buffer: LlBufferRef)
  | wrong_world(expected: LlWorldRef, got: LlWorldRef)
  | memory_exhausted(needed: index))
end

region ll_buffer_publish(vm: ptr(LlVm), buffer: LlBufferRef;
    published(buffer: LlBufferRef)
  | already_published(buffer: LlBufferRef)
  | invalid_buffer(buffer: LlBufferRef))
end
```

### Stream Construction

```moonlift
region ll_stream_empty(vm: ptr(LlVm), world: LlWorldRef;
    stream(stream: LlStreamRef)
  | invalid_world(world: LlWorldRef))
end

region ll_stream_once(vm: ptr(LlVm), op: LlOpRef;
    stream(stream: LlStreamRef)
  | invalid_op(op: LlOpRef)
  | memory_exhausted(needed: index))
end

region ll_stream_seq(vm: ptr(LlVm), buffer: LlBufferRef;
    stream(stream: LlStreamRef)
  | invalid_buffer(buffer: LlBufferRef))
end

region ll_stream_concat(vm: ptr(LlVm), parts: readonly view(LlStreamRef);
    stream(stream: LlStreamRef)
  | empty
  | world_mismatch(expected: LlWorldRef, got: LlWorldRef)
  | memory_exhausted(needed: index))
end
```

### Pull Protocol

```moonlift
region ll_next_op(vm: ptr(LlVm), stream: LlStreamRef;
    op(op: LlOpRef)
  | done
  | blocked
  | failed(diag: LlDiagnosticRef))
end

region ll_drain_stream(vm: ptr(LlVm), stream: LlStreamRef;
    drained(buffer: LlBufferRef)
  | empty
  | failed(diag: LlDiagnosticRef)
  | memory_exhausted(needed: index))
end

region ll_one_op(vm: ptr(LlVm), stream: LlStreamRef;
    one(op: LlOpRef)
  | empty
  | more_than_one
  | failed(diag: LlDiagnosticRef))
end
```

This is the core architecture: consumers pull what they need. Pulling drives
recording, phase execution, cache commits, and diagnostics.

### Args

```moonlift
region ll_intern_args(vm: ptr(LlVm), values: readonly view(LlArgValue);
    args(args: LlArgsRef)
  | unsupported_arg(kind: u8)
  | too_many_args(n: index)
  | memory_exhausted(needed: index))
end
```

### Machine And Phase Definition

```moonlift
region ll_define_region_machine(
    vm: ptr(LlVm),
    name: LlSymbolRef,
    input: LlWorldRef,
    output: LlWorldRef,
    entry_symbol: LlSymbolRef;
    machine(machine: LlMachineRef)
  | missing_region(entry_symbol: LlSymbolRef)
  | signature_mismatch(entry_symbol: LlSymbolRef)
  | world_mismatch
  | memory_exhausted(needed: index))
end

region ll_define_phase(
    vm: ptr(LlVm),
    name: LlSymbolRef,
    input: LlWorldRef,
    output: LlWorldRef,
    machine: LlMachineRef,
    cache_policy: LlCachePolicy;
    phase(phase: LlPhaseRef)
  | duplicate_phase(name: LlSymbolRef)
  | machine_world_mismatch(machine: LlMachineRef)
  | invalid_cache_policy
  | memory_exhausted(needed: index))
end
```

### Phase Application

```moonlift
region ll_open_phase(
    vm: ptr(LlVm),
    phase: LlPhaseRef,
    input: LlStreamRef,
    args: LlArgsRef;
    hit(stream: LlStreamRef)
  | shared(stream: LlStreamRef, recording: LlRecordingRef)
  | miss(stream: LlStreamRef, recording: LlRecordingRef)
  | uncached(stream: LlStreamRef)
  | wrong_input_world(expected: LlWorldRef, got: LlWorldRef)
  | machine_failed(diag: LlDiagnosticRef)
  | memory_exhausted(needed: index))
end

region ll_run_machine(
    vm: ptr(LlVm),
    machine: LlMachineRef,
    input: LlStreamRef,
    args: LlArgsRef;
    output(stream: LlStreamRef)
  | wrong_input_world(expected: LlWorldRef, got: LlWorldRef)
  | unsupported_machine(machine: LlMachineRef)
  | failed(diag: LlDiagnosticRef)
  | memory_exhausted(needed: index))
end
```

### Recording Lifecycle

```moonlift
region ll_start_recording(
    vm: ptr(LlVm),
    key: LlPhaseKey,
    source: LlStreamRef;
    recording(recording: LlRecordingRef)
  | already_pending(recording: LlRecordingRef)
  | memory_exhausted(needed: index))
end

region ll_advance_recording(
    vm: ptr(LlVm),
    recording: LlRecordingRef;
    op(op: LlOpRef)
  | exhausted_commit(cache_entry: LlCacheEntryRef)
  | exhausted_no_commit
  | failed(diag: LlDiagnosticRef))
end

region ll_finish_recording(
    vm: ptr(LlVm),
    recording: LlRecordingRef;
    committed(cache_entry: LlCacheEntryRef)
  | discarded_partial(produced: index)
  | not_cacheable
  | failed(diag: LlDiagnosticRef))
end
```

### Cache

```moonlift
region ll_lookup_cache(vm: ptr(LlVm), key: LlPhaseKey;
    hit(cache_entry: LlCacheEntryRef)
  | miss
  | stale(cache_entry: LlCacheEntryRef))
end

region ll_lookup_pending(vm: ptr(LlVm), key: LlPhaseKey;
    pending(recording: LlRecordingRef)
  | none)
end

region ll_evict_phase(vm: ptr(LlVm), phase: LlPhaseRef;
    evicted(count: index)
  | live_recordings(count: index)
  | missing_phase(phase: LlPhaseRef))
end
```

### Reports

```moonlift
region ll_report_phase(vm: ptr(LlVm), phase: LlPhaseRef;
    report(report: LlPhaseReport)
  | missing_phase(phase: LlPhaseRef))
end

region ll_report_vm(vm: ptr(LlVm);
    report(report: LlVmReport))
end
```

Reports are part of the architecture. Bad reuse numbers mean the semantic phase
boundary is wrong.

## C ABI

LLPVM should be usable as a single compiled C blob when emitted by the C backend.
The C ABI is a status-code shell over typed regions.

The simple C include is the target, but the runtime support layer must be a
real product, not accidental extern pins. Allocation and VM-handle resolution
belong to a named support ABI with explicit ownership:

```text
LlRuntimeSupport =
    allocator callbacks
    VM handle table
    handle generation policy
    table capacity
    thread model
    failure policy
```

`default_malloc`, `default_realloc`, `default_free`, and process-global slot
tables are acceptable only as a bootstrap support implementation. They are not
the architecture.

Suggested public functions:

```c
llpvm_status llpvm_open(const llpvm_config *config, llpvm_vm_ref *out);
llpvm_status llpvm_close(llpvm_vm_ref vm);
llpvm_status llpvm_load_program(llpvm_vm_ref vm, const void *bytes,
                                size_t len, llpvm_stream_ref *out_root);
llpvm_status llpvm_apply_phase(llpvm_vm_ref vm, llpvm_phase_ref phase,
                               llpvm_stream_ref input, llpvm_args_ref args,
                               llpvm_stream_ref *out);
llpvm_status llpvm_drain(llpvm_vm_ref vm, llpvm_stream_ref stream,
                         llpvm_buffer_ref *out);
llpvm_status llpvm_report(llpvm_vm_ref vm, llpvm_vm_report *out);
```

The ABI must not expose internal pointers as durable identity. Handles are opaque
integers with store validation and generation checks.

## Bytecode Image Boundary

LLPVM is a real VM. Lua does not feed it objects one call at a time. The normal
Lua facade writes a dense LLPV image directly and the native VM imports that
image in one bulk operation:

```text
Lua no-parens facade
    -> direct LLPV image builder
    -> LLPV bytecode image
    -> llpvm_load_program(vm, image)
    -> native handles
    -> apply/drain/report
```

This is the architecture. FFI calls are only ABI control points. They are not
the execution loop.

The bytecode image starts with:

```text
u8[4]   magic = "LLPV"
u32     version = 2
u32     root_stream_id
u32     root_op_count
u32     root_op_table_offset
u32[]   root_op_ids
record* tagged little-endian records
```

Each record is:

```text
u8      tag
u32     payload_bytes
u8[]    payload
```

The Lua image builder assigns dense image-local ids to every symbol, type, ABI,
world, op, stream, machine, phase, args product, and root. Records reference each
other by those ids. The native importer resolves ids into validated stores and
returns native handles. No authored Lua proxy is a native handle.

Required native import boundary:

```c
llpvm_status llpvm_load_program(
    llpvm_vm_ref vm,
    const uint8_t *bytes,
    ml_index len,
    llpvm_stream_ref *out_root);
```

After this boundary, Lua should talk in native handles:

```text
PhaseRef
StreamRef
ArgsRef
BufferRef
```

Trying to pass an authored Lua stream directly to `llpvm_drain` is a design
error. It must fail loudly until the program image has been loaded.

## Lua API

Suggested module:

```lua
local ll = require "llpvm"
```

The Lua API is no-parens and PVM-shaped, but its artifact is bytecode:

```lua
local vm = ll.vm { cache_bytes = 64 * 1024 * 1024 }

local Expr = vm.abi "Expr" {
    Int = { value = ll.i64 },
    Add = { left = ll.node, right = ll.node },
}

local Back = vm.abi "Back" {
    ConstI64 = { value = ll.i64 },
    AddI64 = {},
}

local ExprWorld = Expr:world()
local BackWorld = Back:world()

local input = vm.seq(ExprWorld) {
    Expr.Int { value = 1 },
    Expr.Int { value = 2 },
    Expr.Add(),
}

local lower = vm.phase "lower_expr" {
    from = ExprWorld,
    to = BackWorld,
    machine = make_lower_expr_machine(Expr, Back),
    cache = "full",
}

local program = vm.program { lower(input) }
local image = program:bytecode()
local image_buf = ll.bytebuffer(image)
local status, root = runtime_vm:load_program_buffer(image_buf, #image)
status:assert("llpvm_load_program")
local output = runtime_vm:drain(root)
```

With args:

```lua
local output_stream = lower {
    target = "wasm32",
    opt = 3,
} (input)
```

Lua constructs operation schemas, worlds, op constructors, streams, and machine
families. The native VM owns execution, buffers, cache, and diagnostics. Note
wasm is not planned yet its just an illustration.

### Implemented Lua Authoring Surface

The current Lua facade lives at:

```lua
local ll = require "llpvm"
```

It exposes the direct no-parens bytecode facade, plus standard ASDL constructors
for tools that need the structural vocabulary:

```lua
ll.T        -- ASDL context
ll.B        -- optional FastBuilders root
ll.B.LlPvm -- optional ASDL literals/constructors
```

Use ASDL literals only when a tool explicitly needs ASDL products:

```lua
local sym = ll.B.LlPvm.Symbol { value = "Expr" }
```

Use the facade for normal program images:

```lua
local vm = ll.vm { cache_bytes = 64 * 1024 * 1024 }

local Expr = vm.abi "Expr" {
    Int = { value = ll.i64 },
    Add = { left = ll.node, right = ll.node },
}

local ExprWorld = Expr:world()

local input = vm.seq(ExprWorld) {
    Expr.Int { value = 1 },
    Expr.Int { value = 2 },
    Expr.Add {},
}
```

Available type helpers:

```lua
ll.void ll.bool
ll.i8 ll.i16 ll.i32 ll.i64
ll.u8 ll.u16 ll.u32 ll.u64
ll.f32 ll.f64 ll.index
ll.node
ll.handle "NodeRef"
ll.ptr(ll.i32)
ll.view(ll.u8)
ll.struct "Pair" { left = ll.i32, right = ll.i32 }
```

Available low-level helpers:

```lua
ll.symbol "name"
ll.field("value", ll.i64)
ll.cache "full"      -- also "none", "off", "record"
ll.ref_payload(42)
ll.ref_arg(42)
```

VM authoring helpers:

```lua
vm.abi "Name" { ... }
vm.world "Name" { abi = Abi }
vm.empty(World)
vm.once(Op)
vm.seq(World) { Op, Op }
vm.concat { Stream, Stream }
vm.machine "name" { from = InWorld, to = OutWorld, entry = "region_symbol" }
vm.phase "name" { from = InWorld, to = OutWorld, machine = Machine, cache = "full" }
vm.program { RootStream, OtherRootStream }
```

Phase values are callable:

```lua
local output = lower(input)
local output_with_args = lower { target = "wasm32", opt = 3 } (input)
```

Stream proxies expose host-side inspection helpers for locally knowable streams:

```lua
stream:drain() -- returns materialized authored Lua op proxies when locally knowable
stream:one()   -- exactly one authored op proxy
stream:each(function(op, i) ... end)
```

These helpers are authoring/inspection conveniences. The canonical runtime
execution protocol is:

```lua
local program = vm.program { root }
local bytes = program:bytecode()
local image = ll.bytebuffer(bytes)
local status, root_stream = runtime_vm:load_program_buffer(image, #bytes)
status:assert("llpvm_load_program")
local drain_status, buffer = runtime_vm:drain(root_stream)
```

The runtime API rejects authored Lua proxies. `load_program` is the boundary that
turns caller-owned immutable bytecode image views into numeric native handles
owned by the VM. The image buffer must outlive streams derived from it.

### Retained Vs Rebuild

`vm.retain(value)` keeps a high-level Lua proxy or ASDL product across rebuilds:

```lua
local retained_input = vm.retain(input)

local next_input = vm.rebuild(function(next_vm)
    return next_vm.seq(ExprWorld) {
        retained_input:get():drain()[1],
        Expr.Int { value = 4 },
    }
end)
```

Retained values are not hidden runtime ownership. They are host authoring facts:
the retained object can seed a later ASDL rebuild, while `unwrap(retained)` still
lowers to the underlying ASDL product when another LLPVM helper consumes it.
Use retained values for stable authored subgraphs, schemas, worlds, and streams
that should not be rebuilt from scratch when only nearby Lua inputs change. Use
plain rebuilds when the value is cheap or intentionally regenerated.

## Implementation Shape

Keep the folder flat:

```text
lua/llpvm/
  init.lua
  asdl.lua
  bytecode.lua
  runtime_ffi.lua
  README_C_API.md
  IMPLEMENTATION_NOTES.md
  DESIGN.md
  native/
    llpvm_header.mlua
    llpvm_memory.mlua
    llpvm_symbol_store.mlua
    llpvm_kernel_store.mlua
    llpvm_schema.mlua
    llpvm_buffer_store.mlua
    llpvm_args.mlua
    llpvm_machine.mlua
    llpvm_cache.mlua
    llpvm_report.mlua
    llpvm_image.mlua
    llpvm_abi.mlua
    build_c.lua
```

Implementation rules:

```text
Headers declare the full type forest and region tree first.
Implementation files own one semantic machine each.
No hidden Lua table ownership at runtime.
No weak-table cache semantics.
No public triplets.
No untyped status codes except ABI shell functions.
Every store has slot/generation validation.
Every borrowed pointer is a lease.
Every owned handle is discharged by CFG.
Every stream consumer is pull-based.
```

## Backend Expectations

LLPVM must exercise Moonlift seriously:

```text
large typed headers
many region protocols
owned handle continuations
pull loops through block/jump
literal constructors
C backend emission
object emission
Cranelift execution
WASM-friendly C output
```

If the compiler hits parser, source-span, memory, duplicate-code, or backend
limits, fix the compiler architecture. Do not encode LLPVM around compiler
workarounds.

## Non-Goals

```text
No compatibility with current pvm.lua triplets.
No Lua callback hot path.
No generic runtime visitor object model.
No hidden object ownership in side tables.
No "minimal v1" framing.
No C-only design that bypasses Moonlift types.
```

## Final Card

```text
LLPVM is the low-level typed substrate for PVMs.
ASDL defines each operation language.
Worlds carry semantic layers.
Machines are Moonlift regions.
Phases are cache boundaries.
Streams are pull-based.
Buffers are facts.
Recordings make lazy work shareable.
Cache entries are explicit owned products.
Lua authors families.
Moonlift runs them.
C/WASM receives a tight ABI shell.
```
