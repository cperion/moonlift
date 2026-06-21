# The Complete Guide to LLPVM

> **LLPVM** is the low-level PVM: a portable native VM substrate for systems
> that want PVM's phase/caching/stream discipline without making Lua callbacks
> the hot runtime path.
>
> PVM is the rich Lua-hosted compiler machine. LLPVM is the bytecode-fed C blob
> and Moonlift VM shape beneath compiler-shaped systems.

---

# Preface: What This Guide Is For

Use this guide when a system has outgrown "Lua objects plus PVM triplets" as its
runtime boundary, but still wants the Moonlift/PVM design doctrine:

```text
typed worlds
explicit semantic ops
lazy streams
phase boundaries
cacheable recordings
diagnostics as values
portable C/WASM/embedded artifact
thin language-specific APIs
```

LLPVM is not a replacement for ASDL or PVM. It is the lower execution contract:

```text
compiler-shaped Lua API
    -> direct borrowed bytecode image
    -> native VM / C blob
    -> handles, streams, buffers, reports
```

That split is the point. Lua remains the metaprogramming and authoring layer.
The C blob owns the runtime semantics.

---

# Part I - Doctrine

## Chapter 1: What LLPVM Is

LLPVM means:

```text
Low-Level PVM
```

It standardizes the common shape that keeps appearing in Moonlift systems:

```text
ASDL-like meaning
operation worlds
lazy streams
phase maps
recordings
cache entries
native diagnostics
bytecode images
borrowed image loading
portable C ABI
```

The public design is not "a pile of externs" and not "Lua callbacks, but faster."
The public design is:

```text
Worlds define where ops live.
Ops define semantic facts.
Streams define pullable computation.
Phases define memoization boundaries.
Recordings define shared misses and cache commits.
Buffers define materialized facts.
Reports define observable runtime behavior.
Bytecode images define the host/native boundary.
```

The central rule:

```text
Lua may author and compile.
The native VM must execute.
```

## Chapter 2: All Programs Are VM Stacks

The extra LLPVM insight is this:

```text
All serious programs become stacks of virtual machines.
```

Not necessarily one giant VM with one universal bytecode. A stack:

```text
source language VM
    consumes source-shaped bytecode/IR
    produces semantic bytecode/IR

middle compiler VM
    consumes semantic bytecode/IR
    produces lowered bytecode/IR

runtime VM
    consumes lowered bytecode/IR
    produces commands, buffers, reports, events, or machine code
```

Once you see this, many design problems simplify. A compiler is a VM consuming
one bytecode language and producing another. A UI toolkit is a VM consuming
authored UI bytecode and producing layout/render/input bytecode. A Lua bridge is
a VM boundary between dynamic host values and semantic handles. A renderer is a
VM consuming view ops. A parser is a VM consuming bytes and producing syntax
ops. Even "ordinary application logic" becomes clearer when you ask which small
instruction language each layer consumes and which one it emits.

This does not mean "make everything an interpreter" in the slow sense. It means:

```text
name the instruction language
make the stack explicit
make each stage consume a dense stream
make each stage produce a dense stream
make ownership and cache boundaries visible
compile hot stages to native code
```

The VM vocabulary is powerful because it forces the right questions:

```text
What is the bytecode of this layer?
What validates it?
Who owns the bytes?
Can it be borrowed?
What is the instruction pointer / cursor?
What is the stack or environment product?
What are the input and output worlds?
Where are the phase/cache boundaries?
What diagnostics can this VM produce?
Can this stage run without Lua?
```

PVM already had the idea in lazy triplets and cached phases. LLPVM makes the
machine boundary concrete:

```text
bytecode in
stream/phase machine
bytecode or buffer out
```

That is why the same thinking keeps working for JSON, compiler lowering, MLUI,
LuaBridge, render ops, and embedded runtimes. Each one becomes a small VM with a
precise instruction language instead of a bag of callbacks and helper objects.

Design law:

```text
If a subsystem has phases, retained state, diagnostics, and repeated execution,
look for its bytecode language.
```

Do not jump straight to public methods. First find the VM stack.

## Chapter 3: Why LLPVM Exists Beside PVM

PVM is excellent for compiler construction:

```text
ASDL products
structural identity
lazy triplets
handler tables
automatic cache boundaries
Lua expressiveness
```

But the hosted PVM path has costs and contracts that should not leak into every
runtime:

```text
Lua handler dispatch
triplet conventions
GC object identity
weak tables
Lua stack/error behavior at host boundaries
```

LLPVM keeps the conceptual model while changing the runtime artifact:

```text
PVM:
    Lua ASDL values -> Lua phase handlers -> triplets -> Lua arrays

LLPVM:
    compiler API -> borrowed bytecode image -> native VM -> stream/buffer handles
```

Use PVM when you are designing a compiler, experimenting with phase boundaries,
or relying on Lua as the evaluator. Use LLPVM when you need a portable runtime
artifact: C, object files, shared libraries, WASM, embedded targets, or a stable
ABI consumed by non-Lua hosts.

## Chapter 4: The Design Bible Applied

Moonlift design always has two checked structures:

```text
TYPE FOREST    what exists
CONTROL GRAPH  what can happen
```

LLPVM preserves that split.

More precisely, LLPVM is the Bible's VM-stack lens made operational. The Bible
gives the method; LLPVM gives the standard native substrate for systems whose
VM layer must be portable, incremental, and bytecode-fed.

```text
Design Bible law                 LLPVM rule
-----------------------------------------------------------------------
Facts are products.              ABI, World, Op, Stream, Buffer, Report.
Choices are protocols.           load/drain/apply/cache exits are regions.
Regions join the two.            VM behavior is typed region machinery.
Blocks are state products.       stream cursors, recordings, cache walks.
Emits compose.                   VM internals compose with regions.
Seal with functions.             C ABI exports are sealed status functions.
Stores own bytes.                LlVm owns stores, buffers, cache, reports.
Handles may escape.              Ll*Ref values cross ABI boundaries.
Leases may not.                  resolver regions grant temporary access.
Bytecode is a boundary product.  LLPV image is caller-owned immutable bytes.
Serious systems are VM stacks.   LLPVM consumes one IR and emits another fact.
```

This mapping is not documentation sugar. It is a design constraint. If a new
LLPVM subsystem cannot be placed in this table, it is probably smuggling a
convention instead of declaring a product, protocol, or VM boundary.

The type forest:

```text
LlAbi
LlWorld
LlOp
LlStream
LlBuffer
LlArgs
LlMachine
LlPhase
LlRecording
LlCacheEntry
LlDiagnostic
LlReport
```

The control graph:

```text
ll_load_image
ll_stream_drain
ll_apply_phase
ll_begin_recording
ll_finish_recording
ll_lookup_cache
ll_report_vm
```

Do not hide important control in flags, callbacks, tables, or "status plus
maybe output" conventions inside the VM. Inside Moonlift, outcomes are typed
continuations. At the ABI edge, they are sealed into status products because C
requires a product-to-product call shape.

```moonlift
region ll_load_image(vm: ptr(LlVm), bytes: ptr(u8), len: index;
    loaded(root: LlStreamRef)
  | malformed(at: index)
  | unsupported(tag: u8, at: index)
  | oom(needed: index))
end
```

The C function is the seal:

```c
llpvm_status llpvm_load_program(llpvm_vm_ref vm,
                                const uint8_t *bytes,
                                size_t len,
                                llpvm_stream_ref *out);
```

---

# Part II - The Runtime Model

## Chapter 5: PVM-Style Type Authoring

Free-form Moonlift source remains the base language. You can always write
`struct`, `handle`, `region`, and `func` declarations directly when that is the
clearest expression of a machine.

LLPVM is the standard library answer for a narrower task:

```text
author a typed instruction language
define worlds over that language
feed the result to a bytecode VM
retain/cache/incrementally re-run phases
```

For that task, type authoring should feel like PVM:

```text
declare a small world vocabulary
declare variants/op kinds with payload products
construct values through named builders/literals
compose streams and phases over those worlds
```

PVM does this with an ASDL context:

```lua
local T = pvm.context():Define [[
    module Expr {
        Node = Int(number value) unique
             | Add(Expr.Node left, Expr.Node right) unique
    }
]]
```

LLPVM does the same job for native bytecode-fed machines:

```lua
local Expr = vm.abi "Expr" {
    Int = { value = ll.i64 },
    Add = { left = ll.node, right = ll.node },
}
```

The surface is different because the artifact is different. PVM authors
interned Lua ASDL values consumed by Lua-hosted phases. LLPVM authors a dense
instruction language and emits a borrowed image for the native VM. The design
move is the same: author meaning as typed products first, then run machines over
that meaning.

Use free-form Moonlift for bespoke kernels and system internals. Use LLPVM when
the thing you are designing is itself an operation language, compiler layer, or
incremental VM stack.

## Chapter 6: Worlds And ABIs

An ABI is an operation language. A world is one semantic layer using an ABI.

Example:

```lua
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
```

The world is not decoration. Every stream, buffer, phase input, phase output,
and cache key is world-aware. A phase from `ExprWorld` to `BackWorld` cannot
silently consume a stream from another world.

Design law:

```text
If two streams cannot be mixed without a semantic conversion, they are different worlds.
```

## Chapter 7: Ops

An op is a semantic row in a world:

```text
world
kind
payload
```

The runtime may store it compactly, but the kind number is not the design. The
design is the ABI schema and the typed visitor generated from it.

Lua authoring should feel idiomatic:

```lua
local input = vm.seq(ExprWorld) {
    Expr.Int { value = 1 },
    Expr.Int { value = 2 },
    Expr.Add {},
}
```

Native machine code should never have to parse arbitrary Lua tables. It should
receive bytecode records or already-imported handles.

## Chapter 8: Streams

A stream is a lazy pull machine represented by a handle.

Canonical kinds:

```text
empty
once
seq
concat
generated
phase_map
recording
```

There are no public triplets in LLPVM. The triplet idea becomes a native stream
handle plus typed drain/apply protocols.

```moonlift
region ll_drain_stream(vm: ptr(LlVm), stream: LlStreamRef;
    drained(buffer: LlBufferRef)
  | empty
  | invalid_stream(stream: LlStreamRef)
  | wrong_world(expected: LlWorldRef, got: LlWorldRef)
  | memory_exhausted(needed: index))
end
```

A buffer is the materialized fact produced by a full drain. Buffers are immutable
once published.

## Chapter 9: Phases, Recordings, And Cache

A phase is the memoization boundary:

```text
phase = name + input world + output world + machine + cache policy
```

Applying a phase does not have to run it immediately. It creates a stream:

```text
phase(input, args) -> output stream
```

The stream is pulled later. On a miss, a recording owns the in-progress output.
On full exhaustion, that recording may commit into the cache. On partial drain,
it must not silently become a complete cache entry.

Doctrine:

```text
No weak-table magic.
No hidden pending table.
No partial result pretending to be complete.
Recordings and cache entries are explicit products.
```

Shared misses are explicit too: if two consumers request the same phase key
while the first recording is live, they share the recording instead of launching
duplicate work.

## Chapter 10: Diagnostics

Diagnostics are values, not host exceptions.

Inside Moonlift:

```moonlift
failed(diag: LlDiagnosticRef)
```

At C ABI:

```c
typedef struct llpvm_status {
    int32_t code;
    int32_t detail;
    size_t at;
    size_t needed;
} llpvm_status;
```

Use `error()` only for Lua authoring misuse or test assertions. Runtime failure
inside the VM must be observable as a status/diagnostic product.

---

# Part III - Bytecode Boundary

## Chapter 11: The Direct Borrowed Image

The normal host boundary is:

```text
Lua/compiler API
    -> direct bytecode builder
    -> immutable byte string
    -> caller-owned byte buffer
    -> llpvm_load_program(vm, bytes, len)
```

LLPVM does not require the normal Lua API to build an ASDL `Program` object and
then walk it again. The current Lua facade writes the LLPV image directly.

```lua
local program = vm.program { input }
local bytes = program:bytecode()
local image, len = ll.bytebuffer(bytes)
local status, root = runtime_vm:load_program_buffer(image, len)
status:assert("llpvm_load_program")
```

Ownership law:

```text
Lua/host owns image bytes.
LLPVM borrows image bytes.
Derived streams may reference the image.
The caller must keep the image alive while derived handles are live.
```

There is no copy API by default. If the caller wants copied bytes, the caller
can copy them before calling load. The VM boundary remains borrow-only.

## Chapter 12: LLPV Image Shape

The current image starts:

```text
u8[4]   magic = "LLPV"
u32     version = 2
u32     root_stream_id
u32     root_op_count
u32     root_op_table_offset
u32[]   root_op_ids
record* tagged little-endian records
```

Records are image-local facts:

```text
u8      tag
u32     payload_bytes
u8[]    payload
```

The aligned root op table exists because generated stream drain is a hot path.
Native drain can copy `LlOpRef` entries directly instead of byte-decoding each
op id during every drain.

The image is not a dump of C structs. It is a portable little-endian bytecode
contract. C structs may be used inside the runtime after validation/import.

## Chapter 13: Why Direct Builder Matters

The ASDL-first path is excellent for design and debugging, but expensive for a
runtime API:

```text
Lua objects
ASDL interning
program tree
second traversal
bytecode encode
native import
```

The direct builder collapses the normal path:

```text
Lua API call
    -> intern symbol/type/op id
    -> append bytecode record
    -> final root table
```

This does not make the language less rich. It places richness in the compiler
API and keeps the runtime artifact dense.

---

# Part IV - Lua API

## Chapter 14: No-Parens Authoring

LLPVM Lua authoring follows Moonlift's Lua-side taste:

```lua
local ll = require "llpvm"

local vm = ll.vm {}

local Expr = vm.abi "Expr" {
    Int = { value = ll.i64 },
    Add = { left = ll.node, right = ll.node },
}

local world = Expr:world()

local input = vm.seq(world) {
    Expr.Int { value = 1 },
    Expr.Int { value = 2 },
    Expr.Add {},
}

local program = vm.program { input }
```

Builders are syntax, not runtime semantics. The semantics are the bytecode image
and native VM behavior.

## Chapter 15: Runtime FFI Boundary

The runtime FFI wrapper must stay thin:

```lua
local Runtime = require "llpvm.runtime_ffi"
local rt = Runtime.build {}
local native = rt:open {}

local image, len = ll.bytebuffer(program:bytecode())
local st, root = native:load_program_buffer(image, len)
st:assert("load")

local drain_st, buffer = native:drain(root)
drain_st:assert("drain")
```

The wrapper must reject authored Lua proxies where native handles are expected.
An authored stream is not a `LlStreamRef`. Only loading a program image creates
native handles.

```text
Authored Lua proxy != native handle
Bytecode image load = handle creation boundary
```

---

# Part V - C Blob And ABI

## Chapter 16: The C Blob Is The Runtime Product

The target artifact is a small, portable C blob and header:

```text
llpvm.c
llpvm.h
```

The C ABI should expose stable product-to-product calls:

```c
llpvm_status llpvm_open(const llpvm_config *config, llpvm_vm_ref *out);
llpvm_status llpvm_close(llpvm_vm_ref vm);
llpvm_status llpvm_load_program(llpvm_vm_ref vm,
                                const void *bytes,
                                size_t len,
                                llpvm_stream_ref *out);
llpvm_status llpvm_apply_phase(llpvm_vm_ref vm,
                               llpvm_phase_ref phase,
                               llpvm_stream_ref input,
                               llpvm_args_ref args,
                               llpvm_stream_ref *out);
llpvm_status llpvm_drain(llpvm_vm_ref vm,
                         llpvm_stream_ref stream,
                         llpvm_buffer_ref *out);
llpvm_status llpvm_report(llpvm_vm_ref vm, llpvm_report *out);
```

The C API should not expose Lua, PVM triplets, ASDL objects, or implementation
stores as public architecture. Handles are opaque integers with validation.

## Chapter 17: Ownership At The ABI

Ownership laws:

```text
VM handle              owned by caller until close
bytecode image bytes   owned by caller, borrowed by VM
stream/buffer handles  owned by VM, opaque to caller
report/output pointers borrowed until next reset/close, unless copied by caller
diagnostics            values or VM-owned handles depending API shape
```

Do not add a copy API because it feels convenient. If callers want copied memory,
they can allocate/copy before load. The VM API remains honest:

```text
load_program borrows bytes
```

Honest borrowing forces the lifetime issue into the API instead of hiding it in
allocator policy.

## Chapter 18: WASM And Embedded

The borrowed bytecode model maps well to WASM and embedded targets:

```text
host writes bytes into linear memory
VM borrows pointer + len
VM returns handles and output ranges
host reads typed output ranges / ArrayBuffers
```

The same C blob can serve:

```text
LuaJIT FFI
C programs
WASM via emcc
embedded firmware with local C compiler
tests/benchmarks through shared objects
```

No runtime Lua dependency belongs in the blob.

---

# Part VI - Designing Systems On LLPVM

## Chapter 19: Compiler-Shaped Frontends

A system such as MLUI is not "just a layer over LLPVM." It is a compiler:

```text
rich authoring ASDL
style/token compiler
compose expansion
resource tables
layout/scene/render/input phases
native VM import
```

LLPVM's lesson for such systems is not to flatten the frontend. The lesson is
to make the compiler output boundary a direct borrowed bytecode image:

```text
MLUI compiler API
    -> MLUI bytecode image
    -> mlui_load_image(kernel, bytes, len)
    -> native MLUI VM
```

Keep richness above the boundary. Keep the boundary dense and borrow-only.

## Chapter 20: When To Use LLPVM Directly

Use LLPVM directly when your domain can be modeled as streams of ops:

```text
compiler lowering
bytecode translation
small interpreters
asset pipelines
query plans
UI compiler outputs
audio graph transforms
document layout command streams
```

Do not force LLPVM onto a domain whose core shape is not stream/phase/cache.
Moonlift regions and ordinary C ABIs are enough for many kernels.

## Chapter 21: Designing A New LLPVM Family

Procedure:

1. Name the semantic worlds.
2. Define the ABI for each world.
3. Define op payloads as products.
4. Define phase boundaries between worlds.
5. Decide which streams are authored, generated, cached, or recording-backed.
6. Define bytecode records before writing runtime imports.
7. Define borrow/ownership laws for every byte range and handle.
8. Define diagnostics as products.
9. Implement Lua no-parens authoring as a direct image builder.
10. Implement native import/validate as Moonlift regions.
11. Seal C ABI functions only at the outer boundary.
12. Benchmark real scenarios, not only tiny fixed loops.

If this list feels too heavy, the system probably still belongs in hosted PVM
until its runtime boundary is clearer.

---

# Part VII - Anti-Patterns

## Chapter 22: Red Flags

Avoid these:

```text
Lua callbacks in the hot native execution path
raw C struct dumps as portable bytecode
status codes inside Moonlift region internals
copy-vs-borrow duplicate APIs without a real ownership distinction
native handles smuggled as Lua authored proxies
weak tables as cache ownership
partial drains silently committed as complete cache entries
world-less streams
payload parsing duplicated in every machine
"temporary" legacy image formats
```

The hardest red flag is a convenient compatibility path. If the architecture is
wrong, remove it. Compatibility is a product decision, not a design excuse.

## Chapter 23: Review Checklist

Before accepting an LLPVM change, check:

```text
Does the bytecode boundary remain direct and borrow-only?
Does every native handle come from import/open/runtime protocols?
Are authored Lua proxies rejected at runtime ABI calls?
Are worlds checked before stream/buffer mixing?
Are diagnostics values, not random host exceptions?
Are cache entries and recordings explicit products?
Are partial drains handled honestly?
Is the FFI wrapper thin?
Can the C blob be used without Lua?
Can the same image be loaded from LuaJIT, C, WASM, or embedded code?
Does the benchmark measure real load/apply/drain work?
```

---

# Final Doctrine Card

```text
The Bible gives the method; LLPVM is its native VM substrate.
PVM is the hosted compiler machine.
LLPVM is the native bytecode-fed VM substrate.
ASDL defines meaning; bytecode carries meaning.
Lua authors and compiles; the C blob executes.
The normal boundary is a borrowed immutable image.
Authored proxies are not native handles.
Worlds type streams.
Phases type memoization.
Recordings type shared misses.
Buffers type materialized facts.
Diagnostics are values.
Status codes exist only at ABI seals.
No Lua callback is the canonical hot path.
No legacy path without a current product reason.
```
