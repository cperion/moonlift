# The Moonlift Platform

*A buildless, machine-oriented software stack built from LuaJIT, Moonlift, the C ABI, and Cranelift.*

---

## 1. Executive summary

Moonlift is not just a language. It is a platform shape.

The platform is built on four ideas:

```text
LuaJIT      = the host, metaprogramming layer, runtime policy layer, and build system
Moonlift    = the typed machine/control language
C ABI       = the world boundary
Cranelift   = the native code backend
```

The result is a stack where the developer can write high-performance native code, generate specialized machines, call the operating system or C libraries directly, and package the result without inheriting a giant runtime ontology.

Moonlift's core thesis is:

> Programs are machines.  
> A good systems language should let the programmer write machines directly, but with types.

Most languages abstract the machine away and then lower back into blocks, branches, memory operations, calls, and state transitions. Moonlift starts close to that truth. It exposes the control graph as source-level structure: typed blocks, typed jumps, typed regions, typed continuations, and explicit `emit` composition.

LuaJIT supplies the missing human layer: abstraction, code generation, platform selection, runtime policy, capability probing, dynamic loading, FFI, packaging, and beautiful APIs.

The platform is general-purpose because it is **machine-general**. It does not need to include every language feature as a primitive. Many features can be implemented as libraries that generate Moonlift machines.

---

## 2. The core stack

### 2.1 LuaJIT: the mechanism layer

LuaJIT is the host language of the platform.

It is used for:

- code generation
- module assembly
- platform selection
- feature detection
- foreign library loading
- LuaJIT FFI declarations
- specialization
- type-indexed factories
- runtime configuration
- user-facing ergonomic APIs
- packaging and application orchestration

LuaJIT is also the build system.

This is not a slogan. It is an architectural constraint. If a build decision can be expressed in Lua, it does not need a separate build language, macro processor, configure script, CMake layer, or code-generation binary.

Platform selection looks like ordinary Lua:

```lua
local ffi = require("ffi")

if ffi.os == "Windows" then
    return require("runtime.windows").make()
else
    return require("runtime.posix").make()
end
```

Feature detection looks like ordinary Lua:

```lua
local ok = pcall(function()
    ffi.cdef[[
    typedef struct uv_loop_s uv_loop_t;
    uv_loop_t *uv_default_loop(void);
    int uv_run(uv_loop_t *loop, int mode);
    ]]
    assert(ffi.C.uv_default_loop ~= nil)
end)

local backend = ok and require("backend.uv") or require("backend.fallback")
return backend.make()
```

The build graph can be a Lua table. The platform backend can be a Lua function. A code generator can be a Lua closure. A library feature can be a Lua module that returns a specialized Moonlift function, region, or module.

LuaJIT's job is not to be a static type system. LuaJIT's job is to be the flexible mechanism layer that authors typed machine code.

---

### 2.2 Moonlift: the typed machine layer

Moonlift is the compiled object language.

It is not "Lua with strings" and not a generic source language. Lua is where genericity lives. Moonlift receives concrete, monomorphic code.

Moonlift object code is made of:

- scalar values
- pointers
- views
- structs
- tagged unions
- functions
- extern calls
- blocks
- jumps
- switches
- regions
- continuations
- emits
- yields
- returns

The important idea is that Moonlift gives a type system to both:

```text
the type forest    = what data exists
the control graph  = what happens
```

A region is the central unit of control composition:

```moonlift
region scan_until(p: ptr(u8), n: i32, target: i32;
                  hit: cont(pos: i32),
                  miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
```

The part before the semicolon is data input. The part after the semicolon is the control protocol.

This is not a function pretending to return an enum. This is control flow as control flow.

---

### 2.3 The C ABI: the treaty with reality

The C ABI is the platform boundary.

Moonlift can call outward through `extern` declarations:

```moonlift
extern write(fd: i32, buf: ptr(u8), count: index): index end
```

LuaJIT can call outward through FFI:

```lua
local ffi = require("ffi")

ffi.cdef[[
int write(int fd, const void *buf, size_t count);
]]
```

The platform does not need to wrap libc or every system API. If Lua needs a C symbol, LuaJIT FFI can declare it. If Moonlift needs a C symbol, Moonlift can declare an extern. If the extern resolver can use LuaJIT's FFI-visible world, Lua becomes the foreign capability layer:

```text
LuaJIT FFI:
  declares, loads, probes, and selects foreign symbols

Moonlift extern:
  describes the typed machine call edge

Lua staging:
  chooses which externs exist in the generated program
```

This means platform fallback logic can be real executable Lua rather than build-system folklore.

---

### 2.4 Cranelift: the native code hammer

Cranelift is the backend that turns Moonlift's machine-shaped IR into native code.

The backend can support:

```text
JIT function pointers
relocatable object files
shared libraries
eventual packed executables
```

This creates a powerful adoption path.

A developer can write a fast function in Moonlift:

```moonlift
func parse_packet(p: ptr(u8), n: index): i32
    ...
end
```

Then emit an object file or shared library that looks like ordinary C ABI code to consumers:

```c
int32_t parse_packet(uint8_t *p, intptr_t n);
```

The consumer does not need to know that the implementation was written in Moonlift. They call a symbol. They link an object. The language disappears behind the ABI.

This is one of Moonlift's strongest practical properties:

> Write machine-shaped code in Moonlift.  
> Ship C ABI artifacts.

---

## 3. The platform philosophy

### 3.1 Provide mechanisms, not commandments

Moonlift should not bake every possible abstraction into the core language.

Instead:

```text
blocks + jumps       = primitive control mechanism
regions + emits      = typed control composition
functions            = sealed ABI/call boundaries
Lua factories        = abstraction and specialization
libraries            = language features as generated machines
```

Many features that other languages make primitive can be libraries:

| Traditional language feature | Moonlift platform implementation |
|---|---|
| generics | Lua functions returning monomorphic Moonlift code |
| parser combinators | Lua combinators returning region fragments |
| exceptions | typed continuation exits |
| defer | Lua scope/resource helper |
| slices | Moonlift views + Lua-owned borrowed buffers |
| arenas | LuaJIT-rooted arena library |
| channels | generated state machines over queues |
| goroutines | scheduler library + OS-thread or fiber machines |
| async runtime | Lua/libuv orchestration + Moonlift hot paths |
| build system | LuaJIT itself |
| platform cfg | Lua feature detection and generation |
| FFI bindings | LuaJIT FFI + Moonlift externs |

The platform should not hide the machine. It should make the machine pleasant to author.

---

### 3.2 Lua owns abstraction; Moonlift owns execution

The clean split is:

```text
Lua:
  abstraction
  iteration
  generation
  specialization
  naming
  platform policy
  runtime policy
  foreign discovery
  packaging

Moonlift:
  concrete typed data
  concrete typed control
  explicit memory
  explicit extern calls
  native code emission
  ABI-facing functions
```

This prevents Moonlift from becoming a giant language.

Moonlift does not need source-level generics because Lua can generate specialized code. It does not need a macro language because Lua is the macro language. It does not need a build system because Lua is the build system. It does not need a huge runtime because LuaJIT and the C ABI already expose reality.

---

### 3.3 C is optional, not absent

The platform is not anti-C.

It is anti-unnecessary-C.

If a library exists in C, LuaJIT FFI can call it and Moonlift externs can call it. If an operating-system API exists, Lua can declare it or load it. If a platform requires different externs, Lua can generate the correct backend.

But the platform should not require writing C glue merely to make platform selection or runtime features possible.

The principle is:

> C is a world you can touch.  
> It is not a language you must write.

---

### 3.4 The compiler pipeline is a programmable runtime asset

The Moonlift compiler can itself be packaged with the application.

A development mode might look like:

```text
.mlua source
LuaJIT host execution
Moonlift compile/JIT
call function pointers
```

A release mode might look like:

```text
.mlua source
LuaJIT staging
Moonlift object emission
link object files
pack runtime
ship one executable
```

A library mode might look like:

```text
.mlua source
Moonlift object/shared emission
header or binding generation
consumer links as ordinary C ABI artifact
```

A Luvi-style packaging mode could provide:

```text
LuaJIT runtime
embedded Moonlift compiler/runtime
embedded .mlua modules
libuv/event APIs if desired
native Moonlift artifacts
single executable shell
```

This gives Go-like deployment simplicity without Go's fixed runtime ontology.

---

## 4. Moonlift as pleasant IR

Moonlift is secretly close to an IR. That is a virtue.

Most languages start from high-level constructs and then spend compiler effort recovering the control-flow graph. Moonlift exposes the real substrate:

```text
values
blocks
branches
switches
loads
stores
calls
externs
typed signatures
typed memory
typed control exits
```

But it is still human-writable. It has names, declarations, types, regions, and Lua-powered generation.

The target is not raw assembly. The target is **pleasant IR**:

```text
assembly-like enough to map cleanly to machines
typed enough to be checked
composable enough to write large systems
hosted enough to avoid boilerplate
```

This is why Moonlift can feel both low-level and expressive.

---

## 5. Control flow as a typed graph

### 5.1 Blocks are states

A block with parameters is a state declaration:

```moonlift
block loop(i: index, acc: i32)
    ...
end
```

This says:

```text
I am in state loop.
The state carries i and acc.
```

A jump is a typed state transition:

```moonlift
jump loop(i = i + 1, acc = acc + xs[i])
```

This is more general than a `for` or `while` loop. Loops are only a common pattern over blocks and jumps.

The primitive is not "loop." The primitive is "state transition."

---

### 5.2 Regions are control components

Functions are useful when the control interface is sealed. Regions are better when control is still being composed.

A parser fragment, scheduler fragment, channel operation, protocol phase, or bytecode dispatch arm often has multiple meaningful exits. Encoding those exits as return values creates ceremony and overhead. Regions declare them directly:

```moonlift
region recv(ch: ptr(Channel);
            got: cont(value: i32),
            parked: cont(node: ptr(WaitNode)),
            closed: cont(),
            would_block: cont())
    ...
end
```

At the call site, `emit` maps those exits to local blocks:

```moonlift
emit recv(ch;
    got = handle_value,
    parked = suspend_task,
    closed = finish,
    would_block = retry_later)
```

This is the main abstraction:

> Control flow should compose as control flow, not as encoded data.

---

### 5.3 `emit` is not a call

`emit` splices a region's control graph into the surrounding graph. It does not create a runtime stack frame. It does not return. It does not hide exits behind an enum. The caller fills the continuation slots.

This gives the platform one of its central laws:

> Compose with regions. Seal with functions.

Functions remain valuable for ABI boundaries, exported APIs, stable entry points, recursion, and separately callable units. But they should not be the only composition mechanism.

---

## 6. Memory model at the platform level

Moonlift itself should not own memory by default.

The platform memory split is:

```text
LuaJIT:
  owns allocation, cdata, GC roots, finalizers, wrapper objects

Moonlift:
  receives borrowed pointers/views
  computes over memory
  calls externs explicitly when asked

C ABI:
  provides malloc/free/syscalls/platform resources when wanted

Library layer:
  provides scopes, arenas, resources, and ergonomic borrows
```

The core rule:

> A raw pointer passed to Moonlift is valid for a dynamic extent if its owner object is strongly reachable for that whole extent.

This turns much of memory lifetime into scope discipline.

---

### 6.1 Scope-rooted memory

A scope is a dynamic rooting extent:

```lua
sar.scope(function(S)
    local owner = ffi.new("uint8_t[?]", 4096)
    S:pin(owner)

    moon_func(owner, 4096)
end)
```

The owner remains reachable until the scope exits. Moonlift receives only a pointer and a length.

This is not a borrow checker. It is a small runtime discipline:

```text
owner object lives in Lua
borrowed pointer goes to Moonlift
scope keeps owner reachable
Moonlift does not free it
```

---

### 6.2 Arenas

Arenas are an ideal platform library because they are just machines over memory.

An arena is:

```text
rooted backing buffer
current offset
alignment rule
mark/rewind/reset operations
```

Example:

```lua
sar.scope(function(S)
    local A = sar.arena(S, "1mb")

    local bytes = A:bytes("64kb")
    local nodes = A:array("Node", 1024)

    parse(nodes.ptr, nodes.len, bytes.ptr, bytes.len)

    A:temp(function(T)
        local scratch = T:bytes("8kb")
        normalize(scratch.ptr, scratch.len)
    end)
end)
```

The memory contract is simple:

```text
arena allocation is valid until:
  the arena is reset
  the arena rewinds before it
  the scope exits
```

No Moonlift allocation feature is required.

---

### 6.3 Resources

Resources are not only memory. They include:

```text
file descriptors
sockets
thread handles
mutexes
libuv handles
mmap handles
GPU handles
OS-specific objects
```

For scarce resources, finalizers should be backup cleanup, not the primary control path.

A scope/defer/resource helper is enough:

```lua
sar.scope(function(S)
    local fd = open_file_somehow()
    S:owned(fd, function(fd) C.close(fd) end)

    ...
end)
```

The pattern is:

```text
explicit close/defer for scarce resources
GC/finalizer as fallback
Moonlift only sees the raw handle when needed
```

---

### 6.4 The SAR bundle

The minimal memory support library should be Scope/Arena/Resource, not a parallel Moonlift type universe.

It should not recreate:

```text
mem.i32
mem.struct
mem.ptr
mem.view
libc wrappers
```

Moonlift already owns its primitives. LuaJIT FFI already exposes C. The SAR bundle only provides mechanisms:

```text
scope     dynamic rooting + defer stack
arena     bump allocation over rooted LuaJIT cdata
resource  explicit close/defer discipline
borrow    callable ptr/len lending objects
```

The ergonomic convention is:

```lua
object(fn, ...)
```

Meaning:

> Lend this object's machine representation to `fn`.

For example:

```lua
local b = A:bytes("4kb")

-- raw path
parse(b.ptr, b.len)

-- smooth path
b(parse)
```

And if another borrowed object is passed:

```lua
tokens(lex, source)
```

it lowers to:

```lua
lex(tokens.ptr, tokens.len, source.ptr, source.len)
```

This is a library feature, not a language feature.

---

## 7. Foreign access and capability probing

The platform should avoid static assumptions about the foreign world.

LuaJIT can probe the process and choose what to generate.

Example:

```lua
local ffi = require("ffi")

local have_pthread = pcall(function()
    ffi.cdef[[
    typedef unsigned long pthread_t;
    int pthread_create(pthread_t *thread, const void *attr,
                       void *(*start_routine)(void *), void *arg);
    int pthread_join(pthread_t thread, void **retval);
    ]]
    assert(ffi.C.pthread_create ~= nil)
end)

local runtime = have_pthread
    and require("thread.pthread")
    or require("thread.fallback")

return runtime.make()
```

This means:

```text
Lua detects what exists.
Lua chooses the backend.
Lua generates the extern declarations.
Moonlift compiles the selected machine.
```

The compiler does not need to pretend all platforms are the same.

---

## 8. Threading as generated machines

Threading should not be a primitive language religion.

Threading is a collection of machines:

```text
thread lifecycle:
  new -> running -> joined
  new -> running -> detached
  running -> exited

job lifecycle:
  empty -> submitted -> claimed -> running -> done

queue lifecycle:
  push-ready
  pop-ready
  empty-wait
  full-wait
  closed

worker lifecycle:
  idle -> claim job -> run job -> publish result -> idle
  idle -> sleep -> wake
  idle -> shutdown
```

This is exactly the kind of thing Moonlift can express well.

The correct split is:

```text
LuaJIT:
  platform selection
  FFI declarations
  allocation/rooting
  runtime API
  worker pool configuration

Moonlift:
  queue machines
  worker loops
  atomic state transitions
  scheduler state machines
  channel send/recv machines

C ABI:
  OS thread creation
  waits
  handles
  futexes/condition variables/platform primitives
```

A C shim is optional, not fundamental. Lua can generate the platform-specific Moonlift implementation and extern set directly.

On POSIX-like systems, the backend can call pthreads. On Windows, it can generate the Win32/CRT version. The public Lua API can stay the same.

---

## 9. Runtime features as libraries

A central platform claim is:

> Language features can be libraries when the base language exposes the right mechanisms.

Examples:

### 9.1 Channels

A Go-like channel is a set of state machines:

```text
send:
  sent
  parked
  closed
  would_block

recv:
  got(value)
  parked
  closed
  would_block
```

In Moonlift, this maps naturally to continuation exits:

```moonlift
region recv(ch: ptr(Channel);
            got: cont(value: i32),
            parked: cont(node: ptr(WaitNode)),
            closed: cont(),
            would_block: cont())
    ...
end
```

Lua can generate the monomorphic channel for `i32`, `Token`, `Job`, etc.

No source generics are needed.

---

### 9.2 Parser combinators

Parser combinators do not need to be runtime objects. They can be Lua factories that produce Moonlift regions.

```lua
local P = parser.new()

local digit = P:range("digit", string.byte("0"), string.byte("9"))
local sign = P:optional(P:byte("-"))
local integer = P:seq("integer", { sign, P:plus(digit) })
```

The output is native control flow:

```text
Lua combinator graph
  -> generated Moonlift regions
  -> typed CFG
  -> Cranelift native code
```

This is why a compact JSON decoder can be both pleasant and fast: the source describes a parser machine, and the backend sees a parser machine.

---

### 9.3 Schedulers

A scheduler is not magic. It is a machine over tasks, queues, timers, waits, and wakeups.

Moonlift can express the hot path:

```text
claim job
run job
publish result
park task
unpark task
steal work
close queue
shutdown pool
```

Lua can expose the pleasant API:

```lua
local pool = sched.pool(4)
pool:submit(job_fn, job_arg)
pool:join()
```

The runtime policy is a library. The machine is Moonlift.

---

### 9.4 Memory management

Memory management can be a library when the ownership boundary is clear.

```text
LuaJIT owns memory.
Scope roots owners.
Arena gives temporary allocation.
Moonlift borrows pointers/views.
```

This gives a strong default without forcing a language-level ownership calculus.

---

## 10. API style principles

Lua is powerful enough to make APIs feel like language features. This must be used with discipline.

The platform API grammar should be consistent:

```text
noun(...)        create or own something
object(fn, ...)  lend machine representation to a callable
object:verb(...) explicit method/action
object.field     raw machine fact / escape hatch
```

Examples:

```lua
sar.scope(function(S)
    local A = sar.arena(S, "1mb")
    local src = A:bytes("64kb")
    local toks = A:array("Token", 1024)

    -- smooth path
    toks(lex, src)

    -- raw path
    lex(toks.ptr, toks.len, src.ptr, src.len)
end)
```

The raw path must always remain visible. The ergonomic path must not lie.

Callable tables should have one meaning:

> Calling a memory object lends its machine representation to a function.

No cleverness beyond that.

---

## 11. Buildless development

The platform has no separate build system by default because LuaJIT is already programmable enough.

Traditional systems often require:

```text
build files
configure scripts
code generators
platform macros
header generation
linker scripts
package metadata
runtime config
```

In the Moonlift platform, many of these become Lua code:

```lua
local target = require("target").detect()
local runtime = require("runtime").select(target)
local module = require("app").generate(runtime)

return moon.emit_object(module.source, "build/app.o", "app")
```

This is not because build systems are useless. It is because a separate build language should not exist unless it adds a real invariant.

The default should be:

> LuaJIT first. Add extra tooling only when it earns its place.

---

## 12. Packaging model

The platform can support multiple packaging modes.

### 12.1 Development mode

```text
load .mlua
run Lua staging
JIT Moonlift code
call function pointers
iterate quickly
```

### 12.2 Library mode

```text
load .mlua
emit .o / .so / .dylib
ship C ABI symbol
consumer links normally
```

### 12.3 Packed app mode

```text
embed LuaJIT
embed Moonlift compiler/runtime
embed .mlua modules or precompiled chunks
embed or generate native artifacts
ship one executable
```

Luvi-style packaging is attractive because it can provide a LuaJIT executable shell and practical event/runtime APIs while still leaving Moonlift as the hot native machine layer.

The key point:

> A packed Moonlift app can feel Go-like in deployment, but remain Lua/Moonlift-like in ontology.

---

## 13. Relationship to Go

Moonlift can feel Go-like in the good sense:

```text
simple stack
fast iteration
native artifacts
practical deployment
small number of core concepts
```

But it differs from Go at the deepest layer.

Go says:

```text
one language
one toolchain
one runtime
one scheduler
one GC
one standard way
```

Moonlift says:

```text
LuaJIT host
Moonlift machine language
C ABI world boundary
Cranelift backend
runtime policies as libraries
packaging later
```

Go gives primitives. Moonlift gives mechanisms.

Go bakes in goroutines, channels, GC, and a scheduler. Moonlift can build schedulers, channels, memory scopes, arenas, parsers, runtimes, and codecs as libraries that generate or call native machines.

A concise positioning:

> Moonlift is Go's simplicity instinct applied one layer lower.

---

## 14. Relationship to C and C++

Moonlift is close to C in what it can touch:

```text
pointers
structs
scalars
views
externs
C ABI
object files
shared libraries
manual memory protocols
```

But Moonlift improves on C by making the control graph typed and explicit.

C exposes the machine but leaves much of the control structure as untyped convention. C++ adds powerful abstraction, but often by creating a large semantic universe: templates, overloads, RAII, exceptions, virtual dispatch, traits, allocators, and library complexity.

Moonlift takes another route:

```text
Lua handles abstraction and generation.
Moonlift handles concrete typed machines.
C ABI handles interop.
```

This can replace many C/C++ use cases where the real task is:

```text
write a parser
write a codec
write a scheduler
write a runtime
write a kernel
write a library
write an interpreter
write a protocol engine
write a VM dispatch loop
```

These are machines. Moonlift is for writing machines.

---

## 15. Performance thesis

Moonlift's performance thesis is not merely "native code is fast."

The deeper performance thesis is:

```text
if the program is a machine,
and the source directly describes the machine,
the compiler has less semantic fog to remove.
```

Moonlift avoids several common sources of overhead:

- encoding control flow as data
- callback dispatch for local control
- hidden allocation from high-level constructs
- generic runtime dispatch in hot paths
- source-level polymorphism in object code
- parser-combinator runtime objects when generated regions suffice
- function-call boundaries where region splicing is appropriate

Lua staging happens before the hot path. Moonlift receives a concrete machine. Cranelift compiles it.

This is why a small Moonlift JSON decoder that directly builds Lua stack values can be a meaningful flagship benchmark. It is not "script beats script." It is a generated native control machine beating an established C-extension baseline in a domain where branches and state transitions dominate.

---

## 16. The platform standard library should be small

The platform does not need a large standard library that wraps everything.

LuaJIT already provides:

```text
tables
strings
closures
coroutines
modules
metatables
cdata
FFI
JITed host code
```

The C ABI already provides access to:

```text
libc
OS APIs
third-party C libraries
custom shared libraries
platform facilities
```

Moonlift provides:

```text
typed native code
extern calls
object/shared emission
machine-shaped control
```

Therefore the standard library should focus on coherence libraries, not wrapper empires.

Good core libraries:

```text
moonlift.sar       scope / arena / resource
moonlift.pack      packaging
moonlift.test      Lua oracle vs Moonlift native testing
moonlift.parser    region combinators
moonlift.thread    generated threading/scheduler machines
moonlift.cabi      optional declaration coherence helpers
```

Bad core libraries:

```text
libc wrappers that add no invariant
parallel Moonlift type namespaces
abstraction-heavy runtime frameworks
```

Rule:

> Do not wrap access. Wrap patterns.

---

## 17. What belongs in Moonlift core

Moonlift core should remain small and machine-shaped.

Belongs in core:

```text
scalars
pointers
views
structs
unions
functions
externs
blocks
jumps
regions
emits
switches
semantic conversions
memory operations
atomics/fences when concurrency requires them
object/shared emission
ASDL-explicit semantics
```

Does not necessarily belong in core:

```text
threads
goroutines
channels
async/await
exceptions
defer
allocators
classes
source generics
large module framework
package manager
platform cfg syntax
libc wrappers
```

Those can be libraries until proven otherwise.

---

## 18. What belongs in Lua

Lua should own anything that is policy, generation, or environment-dependent:

```text
which backend to generate
which externs exist
which parser grammar to compile
which type specialization to emit
which runtime policy to choose
which resources to root
which artifacts to pack
which fallback to use
```

Lua is where the system asks questions.

Moonlift is where the selected answer becomes native code.

---

## 19. What belongs in libraries

Libraries should provide coherent mechanisms:

```text
scope:
  dynamic lifetime extent

arena:
  temporary allocation machine

resource:
  close/defer/finalizer discipline

parser:
  grammar-to-region generation

thread:
  OS-thread + queue + scheduler machines

channel:
  send/recv/select machines

test:
  compare Lua reference behavior with Moonlift compiled behavior

pack:
  single-binary bundling
```

A Moonlift library should feel like a language feature, but remain inspectable as Lua and Moonlift code.

---

## 20. The no-bloat doctrine

The platform rejects bloat by refusing unnecessary layers.

Avoid stacking:

```text
separate build language
separate macro language
separate FFI generator
separate runtime ontology
frameworks around libc
hidden allocation rules
parallel type universes
opaque scheduler magic
```

Prefer:

```text
Lua code
Moonlift code
C ABI declarations
Cranelift output
small libraries with clear invariants
```

The platform should remain comprehensible enough that one person can understand the whole stack.

---

## 21. Slogans

These capture the design:

> LuaJIT is the build system.

> Moonlift is the generated machine.

> C is an ABI, not a required implementation language.

> Cranelift is the codegen hammer.

> Runtime features are libraries, not commandments.

> Compose with regions. Seal with functions.

> Lua probes the world. Moonlift compiles the answer.

> Memory is owner-rooted, scope-borrowed, arena-friendly, and ABI-honest.

> The safe path should be the short path, and the raw path should stay visible.

> Moonlift is Go's simplicity instinct applied one layer lower.

> Moonlift is a language for writing machines that compile into machines.

---

## 22. Example: generated platform backend

A platform-specific threading backend can be selected without a C shim:

```lua
local ffi = require("ffi")

local function have_pthread()
    return pcall(function()
        ffi.cdef[[
        typedef unsigned long pthread_t;
        int pthread_create(pthread_t *thread, const void *attr,
                           void *(*start_routine)(void *), void *arg);
        int pthread_join(pthread_t thread, void **retval);
        ]]
        assert(ffi.C.pthread_create ~= nil)
    end)
end

local backend

if ffi.os == "Windows" then
    backend = require("thread.windows")
elseif have_pthread() then
    backend = require("thread.pthread")
else
    backend = require("thread.single")
end

return backend.make()
```

Each backend returns the same Lua-facing API but generates different Moonlift externs and implementations.

This is the build system, the feature detector, and the code generator in one language.

---

## 23. Example: SAR-style memory API

```lua
local sar = require("moonlift.sar")

sar.scope(function(S)
    local A = sar.arena(S, "1mb")

    local source = A:bytes("64kb")
    local tokens = A:array("Token", 1024)

    -- Smooth path:
    tokens(lex_json, source)

    -- Equivalent raw path:
    lex_json(tokens.ptr, tokens.len, source.ptr, source.len)

    A:temp(function(T)
        local scratch = T:bytes("8kb")
        scratch(normalize_tokens, tokens)
    end)

    -- source, tokens, scratch are all backed by rooted arena memory.
    -- scratch is invalid after temp rewinds.
    -- arena memory is invalid after scope exit.
end)
```

This is not a new type system. It is just a LuaJIT lifetime mechanism around Moonlift borrows.

---

## 24. Example: C ABI library forge

A Moonlift module can emit a C-callable artifact:

```lua
local moon = require("moonlift")

local source = [[
func add_i32(a: i32, b: i32): i32
    return a + b
end
]]

local obj = moon.emit_object(source, "add.o", "add")
```

A C consumer can see only:

```c
int32_t add_i32(int32_t a, int32_t b);
```

The implementation language disappears. This lets Moonlift enter existing ecosystems as a better way to author native libraries, not as a demand that everyone adopt a new runtime.

---

## 25. Platform identity

Moonlift is not trying to be a high-level language in the usual sense.

It is trying to be the right level above the machine:

```text
higher than assembly
lower than C++ abstraction soup
more explicit than Go
more programmable than C
more typed than raw IR
more packageable than a compiler experiment
```

The platform is:

```text
LuaJIT for humans and generation
Moonlift for typed machines
C ABI for the world
Cranelift for native code
small libraries for coherence
```

That is the identity.

---

## 26. Final thesis

Moonlift is general-purpose because machines are general-purpose.

A parser is a machine.  
A scheduler is a machine.  
A channel is a machine.  
A protocol is a machine.  
A VM is a machine.  
A database kernel is a machine.  
A graphics pipeline stage is a machine.  
A file format codec is a machine.  
A runtime is a machine.

Moonlift gives those machines a typed, explicit, composable source form.

LuaJIT makes those machines easy to generate, configure, package, and call.

The C ABI lets those machines live in the real world.

Cranelift turns them into native code.

That is the Moonlift platform.
