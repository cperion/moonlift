# Designing Software with Moonlift

## A Type-First Methodology for Explicit Machines

**Status:** draft paper  
**Audience:** Moonlift users, systems programmers, compiler-minded application designers  
**Thesis:** Moonlift is not only an implementation language. It is a design language for executable machines. Its native type system is expressive enough to replace a separate ASDL/modeling layer: structs, unions, regions, continuations, blocks, jumps, functions, and Lua factories together form a complete methodology for designing software.

---

## Abstract

Most software design methods split a system into separate artifacts: diagrams, schemas, code, runtime conventions, callback graphs, build scripts, and documentation. These artifacts drift. The real system becomes the behavior of a running program, while the design lives elsewhere.

Moonlift offers another approach. Design is written in the same typed language that implements the system. Products are `struct`s. Stored alternatives are `union`s. Immediate behavioral alternatives are continuation protocols. States are blocks with typed parameters. Transitions are jumps. Compositions are emits. Stable boundaries are functions. Families of repeated machines are Lua factories that emit monomorphic Moonlift declarations.

This paper describes a complete methodology for designing software with Moonlift in the unified type-system view. In this view, ASDL is not a required external modeling layer. ASDL is the historical antecedent: it taught the discipline of explicit products, sums, named variants, and phase boundaries. Moonlift internalizes that discipline. The Moonlift declaration graph is the schema; the region graph is the control design; Lua is the generator; Cranelift is the backend; the C ABI is the boundary with the world.

The method is called **Typed Machine Design**. Its central rule is:

> Design the data tree and the control tree first.  
> Relate them with regions.  
> Compose internally with `emit`.  
> Seal externally with `func`.  
> Generate families with Lua.

---

## Table of Contents

1. [The Problem: Design Drift](#1-the-problem-design-drift)
2. [The Unified Moonlift View](#2-the-unified-moonlift-view)
3. [The Two Type Systems](#3-the-two-type-systems)
4. [Products, Sums, Protocols, and States](#4-products-sums-protocols-and-states)
5. [The Dual Tree](#5-the-dual-tree)
6. [Regions as Relations Between Data and Control](#6-regions-as-relations-between-data-and-control)
7. [Unions and Protocols: Stored Choice vs Immediate Choice](#7-unions-and-protocols-stored-choice-vs-immediate-choice)
8. [Functions as Sealed Regions](#8-functions-as-sealed-regions)
9. [Lua as the Design-Time Abstraction Layer](#9-lua-as-the-design-time-abstraction-layer)
10. [The Full Design Procedure](#10-the-full-design-procedure)
11. [Phase Design Without a Separate ASDL Layer](#11-phase-design-without-a-separate-asdl-layer)
12. [Memory and Resources in the Methodology](#12-memory-and-resources-in-the-methodology)
13. [Foreign Capabilities and Platform Design](#13-foreign-capabilities-and-platform-design)
14. [Worked Example I: JSON Parsing](#14-worked-example-i-json-parsing)
15. [Worked Example II: HTTP Request Lifecycle](#15-worked-example-ii-http-request-lifecycle)
16. [Worked Example III: Text Editor Core](#16-worked-example-iii-text-editor-core)
17. [Worked Example IV: Scheduler and Channels](#17-worked-example-iv-scheduler-and-channels)
18. [Review Method](#18-review-method)
19. [Testing Method](#19-testing-method)
20. [Tooling Implications](#20-tooling-implications)
21. [Anti-Patterns](#21-anti-patterns)
22. [Design Checklist](#22-design-checklist)
23. [What This Means for Software Architecture](#23-what-this-means-for-software-architecture)
24. [Conclusion](#24-conclusion)

---

## 1. The Problem: Design Drift

Traditional software design usually separates the design from the executable artifact.

A system may have:

```text
UML diagrams
database schemas
protocol documents
callback conventions
runtime registries
interface definitions
build scripts
implementation code
documentation
```

The problem is not that these artifacts are useless. The problem is that they are separate. They can disagree. They can go stale. They can describe intentions that the compiler cannot check.

A diagram can say that an operation has four outcomes. The implementation can return a boolean. A schema can say a value has three variants. The code can use strings. A design document can say a resource must be closed. The implementation can forget. A callback graph can exist only as runtime registration side effects. A build script can select a platform backend whose capabilities are not visible in the source.

This creates **design drift**:

```text
what the design says
    diverges from
what the code says
    diverges from
what the running program does
```

The Moonlift methodology attacks design drift by refusing to separate design from typed structure.

The design of a Moonlift system is the Moonlift declaration graph:

```text
structs
unions
externs
regions
continuations
blocks
functions
contracts
Lua-generated declarations
```

These are not comments and not diagrams. They are source-level artifacts that the compiler can typecheck, lower, validate, emit, and expose to tooling.

The goal is not to eliminate documentation. The goal is to make the primary design artifact executable and checkable.

---

## 2. The Unified Moonlift View

Moonlift inherits an important lesson from ASDL: good system design is made of explicit products, explicit sums, named fields, named variants, and no hidden structure.

But in the unified Moonlift view, ASDL is no longer the primary modeling language. It is the historical antecedent and an optional interchange format.

The primary modeling language is Moonlift itself.

```text
ASDL product      -> Moonlift struct
ASDL sum          -> Moonlift union
ASDL tree         -> Moonlift declaration graph
ASDL phase facts  -> Moonlift fact structs/unions/protocols
Control outcomes -> Moonlift continuation protocols
State machines    -> Moonlift regions, blocks, jumps
```

This is the crucial collapse:

> The Moonlift source language is the schema.

A system's persistent model, events, phase facts, intermediate records, handles, result variants, and control protocols can all be expressed with Moonlift declarations. There is no need to design a separate ASDL schema and then implement it in Moonlift.

The unified view has three consequences.

### 2.1 The design language and implementation language are the same

A design declaration is already an implementation declaration.

```moonlift
struct Document
    blocks: view(Block)
    selection: Selection
    revision: u64
end

union EditorEvent
    insert_text(pos: Cursor, bytes: view(u8))
    delete_range(range: Range)
    move_cursor(pos: Cursor)
    save()
end

region apply_event(
    doc: ptr(Document),
    event: ptr(EditorEvent);

    changed: cont(new_revision: u64),
    unchanged: cont(),
    invalid: cont(code: i32))
```

This is not a sketch. It is the system's schema and protocol.

### 2.2 Tooling can inspect the actual design

Because the design is in the source, an IDE can answer real architectural queries:

```text
Which regions can exit through `invalid`?
Which blocks fill `closed`?
Which structs are reachable from `Document`?
Which regions consume `EditorEvent`?
Which functions seal `parse_value`?
Which continuations carry `ptr(Buffer)`?
```

The design is not hidden in a diagram. It is queryable structure.

### 2.3 Design review can happen before body review

A reviewer can read only type declarations and region signatures and still understand the architecture.

Bodies matter, but the most expensive mistakes are usually not inside bodies. They are in the choice of types and protocols. Moonlift makes those choices explicit early.

---

## 3. The Two Type Systems

Every system has two structures:

1. **The data structure** — what exists.
2. **The control structure** — what can happen.

Most languages type the first structure and leave the second one informal. They offer good tools for values, records, enums, and generics, but they treat control flow as a mixture of function calls, returns, exceptions, callbacks, loops, hidden state machines, and conventions.

Moonlift types both structures.

### 3.1 The data type system

The data type system contains:

```text
scalars
pointers
views
structs
unions
function types
extern-facing values
```

It answers:

```text
What shape does this value have?
What fields exist?
Which variant is this?
What memory does this pointer/view describe?
What type flows through this operation?
```

### 3.2 The control type system

The control type system contains:

```text
regions
continuations
blocks
jumps
emits
switches
yields
returns
```

It answers:

```text
What can happen next?
Where can execution go?
What state does the transition carry?
Which exits must the caller handle?
Which blocks are valid targets?
Which paths terminate?
```

The control type system is not a metaphor. It is a real type system:

```text
A region declares its continuation protocol.
An emit site must fill every continuation.
A jump must target a block that exists.
A jump must provide the target block's parameters.
A block parameter has a concrete type.
Every control path must terminate explicitly.
```

This is the central advantage of Moonlift as a design medium.

---

## 4. Products, Sums, Protocols, and States

Moonlift's design algebra has four primary forms.

### 4.1 Data products: `struct`

A `struct` is a product of named fields.

```moonlift
struct User
    id: u64
    age: i32
    active: bool
end
```

Use structs when several facts exist together.

Design question:

```text
What things must be present at the same time?
```

### 4.2 Data sums: `union`

A `union` is a stored alternative.

```moonlift
union AuthState
    unauthenticated()
    authenticated(user_id: u64)
    expired(last_seen: i64)
end
```

Use unions when a value must be one of several alternatives and that alternative must exist as data.

Design question:

```text
What possible shapes can this value take?
```

### 4.3 Control sums: continuation protocols

A region's continuation set is a control sum.

```moonlift
region authenticate(
    creds: ptr(Credentials),
    store: ptr(SessionStore);

    success: cont(user_id: u64, token: ptr(u8)),
    invalid_credentials: cont(),
    account_locked: cont(unlock_at: i64),
    rate_limited: cont(retry_after_seconds: i32))
```

Use continuation protocols when the caller should branch immediately on the outcome.

Design question:

```text
What can happen next, and what does each outcome carry?
```

### 4.4 Control states: blocks with typed parameters

A block is a named state. Its parameters are the state payload.

```moonlift
block scan(i: index, acc: i32)
    ...
    jump scan(i = i + 1, acc = acc + 1)
end
```

Use blocks when a machine has internal states.

Design question:

```text
What named states does this operation pass through?
What data is carried by each state?
```

### 4.5 Transitions: jumps

A jump is a typed transition between states.

```moonlift
jump scan(i = next_i, acc = next_acc)
```

Use jumps when control moves from one state to another.

Design question:

```text
What state do we enter next, and with what payload?
```

### 4.6 Composition: emit

An emit composes control graphs.

```moonlift
emit parse_number(p, n, i;
    ok = got_number,
    err = bad_number)
```

Use emit when one control machine should be inserted into another.

Design question:

```text
How do this region's exits map into my local states?
```

---

## 5. The Dual Tree

The result of designing a Moonlift system is a **dual tree**.

It has two halves:

```text
Data tree     = structs, unions, views, handles, stored facts
Control tree  = regions, continuations, blocks, jumps, emits
```

The two halves are not independent. Region parameters come from the data tree. Continuation payloads come from the data tree. Blocks carry data-tree values. Regions transform, inspect, and route data-tree values.

The design of a system is the relationship between the two trees.

### 5.1 Data tree

The data tree contains everything the system can hold.

Examples:

```text
persistent state
events
configuration
resources
buffers
handles
phase facts
intermediate records
output commands
diagnostics
```

### 5.2 Control tree

The control tree contains everything the system can do.

Examples:

```text
parse value
apply event
schedule job
receive message
render frame
open file
close connection
allocate resource
recover from error
```

Each operation is described first by its protocol, not by its body.

### 5.3 The dual-tree invariant

A design is incomplete if some meaningful distinction appears in neither tree.

If a behavior matters, it must be:

```text
a field
a variant
a continuation
a block
a jump
a contract
a phase fact
a Lua generation choice
```

If it is only a convention, string, callback name, side table, comment, or undocumented runtime path, the design is not yet explicit.

---

## 6. Regions as Relations Between Data and Control

A region is the bridge between the data tree and the control tree.

```moonlift
region read_line(
    buffer: ptr(u8),
    buffer_len: index,
    start: index;

    found: cont(start: index, len: index, terminator: u8, next: index),
    eof: cont(start: index, len: index),
    invalid: cont(pos: index, code: i32))
```

Before the semicolon:

```text
data entering the machine
```

After the semicolon:

```text
control leaving the machine
```

The body relates them.

A region signature is therefore a design statement:

```text
Given this data,
this operation can exit in exactly these ways,
carrying exactly these values.
```

This is why region signatures should be designed before bodies.

If the protocol is wrong, the implementation will fight you. If the protocol is right, the implementation tends to become mechanical.

### 6.1 Region signatures as architecture

A body tells you how an operation works.

A region signature tells you what the operation is.

Example:

```moonlift
region recv(
    ch: ptr(Channel);

    got: cont(value: i32),
    parked: cont(waiter: ptr(Waiter)),
    closed: cont(),
    would_block: cont())
```

This signature says more than a function returning `i32` or `bool` ever could. It exposes the control design:

```text
receive may produce a value
receive may park the task
receive may observe a closed channel
receive may fail immediately in nonblocking mode
```

### 6.2 Region composition

Because emits fill continuations, region composition is checked.

```moonlift
emit recv(ch;
    got = handle_value,
    parked = suspend_current_task,
    closed = finish_closed,
    would_block = retry_later)
```

The caller must decide what every outcome means. No outcome leaks implicitly.

This is how Moonlift replaces many ad hoc patterns:

```text
exceptions
callbacks
Result enums
status codes
virtual dispatch
async hidden state machines
```

Not because those patterns are impossible, but because their useful parts are more directly expressed as typed control protocols.

---

## 7. Unions and Protocols: Stored Choice vs Immediate Choice

A union and a continuation protocol have the same algebraic shape:

```text
one of several named alternatives,
each carrying typed payloads
```

But they differ in consumption mode.

### 7.1 Union: choice stored as data

```moonlift
union ParseResult
    ok(value: i32, next: index)
    err(pos: index, code: i32)
end
```

Use a union when the result must be:

```text
stored
returned across a function boundary
queued
serialized
logged
inspected later
matched in multiple places
passed to another subsystem
```

### 7.2 Protocol: choice consumed as control

```moonlift
region parse_i32(
    p: ptr(u8),
    n: index,
    i: index;

    ok: cont(value: i32, next: index),
    err: cont(pos: index, code: i32))
```

Use a continuation protocol when the caller will branch immediately.

The caller's blocks are the match arms:

```moonlift
emit parse_i32(p, n, i;
    ok = got_number,
    err = bad_number)
```

### 7.3 The rule

The central design rule:

```text
If the outcome must live, make it a union.
If the outcome should route control now, make it a protocol.
```

Sometimes both are correct. A region may construct a union and return through one continuation:

```moonlift
region parse_result(...;
    done: cont(result: ParseResult))
```

But internally, immediate control protocols are usually more direct and more efficient.

### 7.4 Why this matters

In many languages, the designer is forced to encode control as data because functions have only one return path.

Moonlift does not force this.

This avoids the pattern:

```text
operation returns Result
caller immediately matches Result
branches into local states
```

Moonlift can express the branch directly:

```text
operation exits through continuation
caller fills continuation with local block
```

This removes temporary values, reduces ceremony, and makes control explicit.

---

## 8. Functions as Sealed Regions

A function is a sealed control boundary.

It has:

```text
one entry
one return path
a stable callable symbol or function pointer
an ABI-facing shape when exported
```

Use functions when the control protocol is settled.

Good uses of functions:

```text
C ABI exports
JIT call targets
library entry points
stable internal APIs
operations that genuinely have one return protocol
places where separate compilation matters
```

Bad uses of functions:

```text
internal parser fragments with many outcomes
scheduler transitions
channel send/recv
operations with retry/park/cancel/closed outcomes
error-heavy local composition
```

For those, use regions.

The design law:

> Compose with regions.  
> Seal with functions.

### 8.1 Sealing example

Internal design:

```moonlift
region parse_value(
    L: ptr(lua_State),
    p: ptr(u8),
    n: index,
    i: index;

    ok: cont(next: index),
    err: cont(pos: index, code: i32))
```

Exported API:

```moonlift
func decode_json(L: ptr(lua_State), p: ptr(u8), n: index) -> i32
    return region -> i32
    entry start()
        emit parse_value(L, p, n, 0; ok = parsed, err = failed)
    end

    block parsed(next: index)
        return 1
    end

    block failed(pos: index, code: i32)
        return 0 - code
    end
    end
end
```

The internal parser is a continuation machine. The exported decoder is a function.

---

## 9. Lua as the Design-Time Abstraction Layer

Moonlift source has no source-level generics. This is not a lack. It is a design choice.

Lua is where genericity lives.

Use Lua for:

```text
specialization
families of regions
families of structs/unions
platform selection
constant computation
layout computation
dispatch table construction
switch arm generation
parser grammar compilation
runtime policy selection
extern availability probing
object/shared emission
packaging
```

Moonlift receives only concrete monomorphic declarations.

### 9.1 Why this is cleaner

Many languages overload one type system with too many jobs:

```text
runtime data
compile-time computation
generic abstraction
dispatch
effect tracking
module configuration
platform selection
build logic
FFI
optimization facts
```

Moonlift separates the roles:

```text
Lua:
  abstraction and generation

Moonlift:
  concrete typed machine

C ABI:
  world boundary

Cranelift:
  code generation
```

This keeps Moonlift small.

### 9.2 Factories

A Lua factory returns Moonlift declarations.

```lua
local function make_expect_byte(name, byte, err_code)
    return region @{name}(
        p: ptr(u8),
        n: index,
        i: index;

        ok: cont(next: index),
        err: cont(pos: index, code: i32))
    entry start()
        if i >= n then jump err(pos = i, code = @{err_code}) end
        if p[i] == @{byte} then jump ok(next = i + 1) end
        jump err(pos = i, code = @{err_code})
    end
    end
end
```

The generated result is concrete. There is no runtime generic dispatch.

### 9.3 When to abstract

Do not start with a factory.

Start with one concrete machine. Then abstract repeated structure.

The procedure:

```text
write one concrete region
write a second similar region
identify what varies
move variation to Lua parameters
return a concrete region
```

This prevents premature metaprogramming.

---

## 10. The Full Design Procedure

This section gives the complete methodology.

### Step 1 — Name the machine

Write one sentence:

```text
This system is a machine that consumes _____ and produces _____ by repeatedly _____.
```

Examples:

```text
A JSON decoder consumes bytes and produces Lua stack values by repeatedly parsing values and filling continuations.

A text editor consumes input events and produces render facts by applying events to a document and compiling the document to display operations.

A scheduler consumes submitted jobs and wakeups and produces worker execution by repeatedly claiming, running, parking, and completing tasks.
```

If this sentence is vague, the design is not ready.

### Step 2 — Identify the world boundary

List what the system touches outside itself:

```text
files
sockets
libuv
threads
Lua stack
C library
GPU
terminal
GUI
allocator
clock
```

Each boundary becomes one of:

```text
extern
LuaJIT FFI capability
resource handle
function export
C ABI artifact
```

Do not hide the boundary.

### Step 3 — Build the data tree

List nouns.

Then classify:

```text
product       -> struct
stored choice -> union
sequence      -> view or buffer
external thing -> handle/pointer/resource wrapper
temporary fact -> phase output type
input action  -> event union
```

Ask:

```text
What must be stored?
What survives save/load?
What is derived?
What is temporary?
What is a handle to external reality?
What is a view into memory?
```

### Step 4 — Build the control tree

List verbs and outcomes.

Then classify:

```text
operation -> region
possible immediate outcome -> continuation
internal state -> block
transition -> jump
composition -> emit
stable boundary -> function
```

Ask:

```text
What can happen next?
What must the caller handle?
What outcomes are impossible?
What state is carried between states?
Where can execution park, retry, fail, close, or complete?
```

### Step 5 — Write region signatures first

Do not start with bodies.

For each operation, write:

```moonlift
region operation(data_in...;
    outcome_a: cont(...),
    outcome_b: cont(...),
    outcome_c: cont(...))
```

Review only these signatures.

Questions:

```text
Are all outcomes named?
Are there too many outcomes?
Are different outcomes collapsed into one?
Are payloads minimal?
Are payloads typed correctly?
Should this be a union instead?
Should this be a function instead?
```

### Step 6 — Decide union vs protocol

For each outcome:

```text
stored later?      -> union
routed now?        -> continuation
crosses ABI?       -> function return / struct / union
hot internal path? -> continuation
```

### Step 7 — Design blocks as states

Inside each region, write the block list.

Before filling code, name states:

```moonlift
entry start()
block scan(i: index)
block got_digit(i: index, value: i32)
block finish(value: i32, next: index)
block fail(pos: index, code: i32)
```

This is the local state machine.

### Step 8 — Fill transitions

Only now write comparisons, loads, stores, calls, jumps, and emits.

The body should feel like connecting a state machine already designed.

### Step 9 — Compose regions

Use `emit` to compose machines.

Each emit must map the callee's protocol into local states.

Design question:

```text
What does this callee outcome mean in this caller?
```

### Step 10 — Seal with functions

Only after internal control is stable, create function boundaries.

Questions:

```text
Does this need to be called from Lua?
Does this need a C ABI symbol?
Does this need object/shared emission?
Does this need a simple return code?
```

### Step 11 — Lift repetition into Lua

Find repeated shapes:

```text
same protocol, different payload type
same parser fragment, different byte
same scheduler machine, different job type
same switch dispatch, different table
same platform behavior, different extern set
```

Generate them with Lua.

### Step 12 — Define phase boundaries if the system is interactive or compiler-like

Ask what knowledge must be resolved when:

```text
parse
resolve names
typecheck
layout
schedule
validate
emit facts
draw
run
```

Each phase consumes typed Moonlift values and produces typed Moonlift values or protocols.

No separate ASDL layer is required.

### Step 13 — Write the review checklist

For the finished design, answer:

```text
What are the data types?
What are the control protocols?
What are the state blocks?
What are the sealed functions?
What does Lua generate?
What crosses the C ABI?
What owns memory?
What facts does the final loop consume?
```

If any answer is "it is implicit," the design is incomplete.

---

## 11. Phase Design Without a Separate ASDL Layer

The compiler pattern remains essential, but in the unified view its nouns are Moonlift nouns.

Old view:

```text
Source ASDL
Event ASDL
Apply
Phase
Facts
Loop
```

Unified Moonlift view:

```text
Source types
Event unions
Apply regions/functions
Phase functions/regions
Fact structs/unions/protocols
Loop blocks/functions/host loops
```

### 11.1 Source types

Source types are the authored model.

```moonlift
struct Document
    blocks: view(Block)
    selection: Selection
    revision: u64
end
```

This is the saveable, undoable state.

Derived data does not belong here.

### 11.2 Event unions

Events are input language.

```moonlift
union EditorEvent
    insert_text(pos: Cursor, bytes: view(u8))
    delete_range(range: Range)
    move_cursor(pos: Cursor)
    save()
end
```

This turns callbacks into data.

### 11.3 Apply

Apply is the state transition from source and event to next source or outcome.

```moonlift
region apply_event(
    doc: ptr(Document),
    event: ptr(EditorEvent);

    changed: cont(new_revision: u64),
    unchanged: cont(),
    invalid: cont(code: i32))
```

Apply may be pure at the architecture level even if implemented with mutation under controlled ownership.

### 11.4 Phase facts

A phase answers a named knowledge question.

```text
layout_blocks
resolve_styles
shape_text
emit_render_facts
schedule_jobs
lower_regions
validate_control
```

A phase output is just another Moonlift type:

```moonlift
union RenderFact
    clear(color: u32)
    rect(x: i32, y: i32, w: i32, h: i32, color: u32)
    text(x: i32, y: i32, bytes: view(u8))
end
```

Or a control protocol:

```moonlift
region emit_render_facts(
    doc: ptr(Document);

    fact: cont(f: RenderFact),
    done: cont(),
    invalid: cont(code: i32))
```

### 11.5 The loop

The loop is the consumer.

It can be Lua:

```lua
for _, fact in render(doc) do
    draw(fact)
end
```

Or Moonlift:

```moonlift
block loop(i: index)
    if i >= n then return end
    ...
    jump loop(i = i + 1)
end
```

The important rule is:

> The loop consumes facts.  
> Phases produce facts.  
> Source and events are typed Moonlift values.  
> No separate modeling language is required.

---

## 12. Memory and Resources in the Methodology

Moonlift should not make memory ownership implicit.

The methodology treats memory as part of the design.

### 12.1 Classify memory

For every pointer/view, answer:

```text
Who owns the memory?
How long is it valid?
Can Moonlift store the pointer?
Can Moonlift mutate it?
Can it alias another pointer?
Does it cross a thread boundary?
```

### 12.2 Common ownership modes

```text
LuaJIT-owned temporary memory
LuaJIT-owned long-lived buffer
arena-owned temporary allocation
C-owned malloc/resource
caller-owned pointer
foreign library-owned handle
```

### 12.3 Borrowing rule

A pointer passed to Moonlift is usually a borrow.

Design rule:

```text
The owner must remain reachable for the entire dynamic extent of the borrow.
The pointer may escape only if the owner escapes with it.
```

### 12.4 Arena rule

Arena allocations are valid until:

```text
arena reset
arena rewind before allocation
scope exit
arena close
```

This can be represented by Lua library discipline, not by adding ownership syntax to Moonlift.

### 12.5 Resource rule

Scarce resources should have explicit close/defer discipline.

```text
file descriptors
thread handles
sockets
libuv handles
mutexes
mmap regions
```

`__gc` or `ffi.gc` may be backup cleanup, not primary control flow.

### 12.6 Why this belongs in the methodology

Memory is not an implementation detail. It is part of the type/control design.

A region that receives `ptr(Buffer)` should make the contract visible:

```moonlift
region fill_buffer(
    writeonly noalias dst: ptr(u8),
    n: index,
    byte: u8;

    done: cont(),
    invalid: cont(code: i32))
```

The type says what flows. The modifiers/contracts say what memory facts are assumed. The Lua scope/arena/resource layer says who owns the memory.

---

## 13. Foreign Capabilities and Platform Design

Moonlift uses the C ABI as the world boundary, but LuaJIT is the capability layer.

The methodology:

```text
Lua probes the world.
Lua chooses a backend.
Lua generates the Moonlift externs.
Moonlift calls only selected externs.
```

### 13.1 Example

```lua
local ffi = require("ffi")

local have_uv = pcall(function()
    ffi.cdef[[
    typedef struct uv_loop_s uv_loop_t;
    uv_loop_t *uv_default_loop(void);
    int uv_run(uv_loop_t *loop, int mode);
    ]]
    assert(ffi.C.uv_default_loop ~= nil)
end)

local backend = have_uv
    and require("runtime.uv")
    or require("runtime.fallback")

return backend.make()
```

The selected backend emits the correct Moonlift externs.

### 13.2 Why this matters

No separate build system is needed for ordinary platform selection.

```text
configure scripts -> Lua
platform macros   -> Lua
feature probing   -> Lua
backend selection -> Lua
extern generation -> Lua
```

Moonlift compiles the answer.

### 13.3 Design rule

Do not wrap C access unless the wrapper adds an invariant.

Good wrappers:

```text
scope
arena
resource
thread pool protocol
channel machine
parser generator
```

Bad wrappers:

```text
libc functions copied into a parallel namespace without new guarantees
```

---

## 14. Worked Example I: JSON Parsing

JSON parsing demonstrates the methodology well because it is branch-heavy, recursive, and full of immediate outcomes.

### 14.1 Name the machine

```text
The JSON decoder consumes bytes and produces Lua stack values by parsing a value grammar and exiting through typed parse outcomes.
```

### 14.2 Data tree

```moonlift
union JsonError
    unexpected_eof(pos: index)
    unexpected_byte(pos: index, byte: u8)
    invalid_number(pos: index)
    invalid_escape(pos: index)
    stack_error(code: i32)
end
```

If the decoder reports errors as codes, this union may stay design-level or be used in tests. If the hot path only needs immediate branching, errors become continuations.

### 14.3 Control protocols

```moonlift
region parse_value(
    L: ptr(lua_State),
    p: ptr(u8),
    n: index,
    i: index;

    ok: cont(next: index),
    err: cont(pos: index, code: i32))
```

Specialized fragments:

```moonlift
region parse_string(...;
    ok: cont(next: index),
    err: cont(pos: index, code: i32))

region parse_number(...;
    ok: cont(next: index),
    err: cont(pos: index, code: i32))

region parse_array(...;
    ok: cont(next: index),
    err: cont(pos: index, code: i32))

region parse_object(...;
    ok: cont(next: index),
    err: cont(pos: index, code: i32))
```

### 14.4 Lua factory axis

Literal arms are data-driven:

```lua
local literal_arms = {
    make_literal("true",  push_true),
    make_literal("false", push_false),
    make_literal("null",  push_null),
}
```

Lua generates switch arms. Moonlift compiles the chosen machine.

### 14.5 Sealed function

```moonlift
func decode_json(L: ptr(lua_State), p: ptr(u8), n: index) -> i32
    return region -> i32
    entry start()
        emit parse_value(L, p, n, 0; ok = parsed, err = failed)
    end

    block parsed(next: index)
        return 1
    end

    block failed(pos: index, code: i32)
        return 0 - code
    end
    end
end
```

The internal parser is a continuation machine. The exported decoder is a function.

---

## 15. Worked Example II: HTTP Request Lifecycle

### 15.1 Name the machine

```text
The HTTP server consumes socket events and bytes, parses requests, routes them, and emits response writes or connection transitions.
```

### 15.2 Data tree

```moonlift
struct Connection
    fd: i32
    input: view(u8)
    output: view(u8)
    state: ConnectionState
end

union ConnectionState
    reading_headers()
    reading_body(expected: index, received: index)
    ready()
    writing()
    closed()
end

struct Request
    method: Method
    path: view(u8)
    headers: view(Header)
    body: view(u8)
end

union Method
    get()
    post()
    put()
    delete()
    other(bytes: view(u8))
end
```

### 15.3 Event union

```moonlift
union ServerEvent
    readable(conn: ptr(Connection))
    writable(conn: ptr(Connection))
    timeout(conn: ptr(Connection))
    accepted(fd: i32)
    shutdown()
end
```

### 15.4 Control protocols

```moonlift
region parse_request(
    conn: ptr(Connection);

    complete: cont(req: ptr(Request)),
    need_more: cont(),
    bad_request: cont(code: i32),
    close: cont())

region route_request(
    req: ptr(Request);

    response: cont(status: i32, body: view(u8)),
    not_found: cont(),
    internal_error: cont(code: i32))

region write_response(
    conn: ptr(Connection),
    status: i32,
    body: view(u8);

    done: cont(),
    partial: cont(written: index),
    closed: cont(),
    error: cont(code: i32))
```

### 15.5 Composition

```moonlift
emit parse_request(conn;
    complete = route,
    need_more = wait_read,
    bad_request = send_400,
    close = close_conn)
```

Each outcome is explicit. There is no hidden exception or callback.

### 15.6 Function boundary

The event-loop integration may be Lua/libuv. The hot transitions are Moonlift regions. The sealed function may be:

```moonlift
func handle_event(ev: ptr(ServerEvent)) -> i32
    ...
end
```

---

## 16. Worked Example III: Text Editor Core

A text editor is a strong test because it is not just a kernel. It is a whole interactive system.

### 16.1 Name the machine

```text
The editor consumes user events and file events, applies them to a document model, compiles the document to render facts, and sends those facts to a terminal or GUI loop.
```

### 16.2 Source types

```moonlift
struct Document
    pieces: view(Piece)
    selection: Selection
    revision: u64
end

struct Piece
    source: PieceSource
    start: index
    len: index
end

union PieceSource
    original()
    add_buffer()
end

struct Selection
    anchor: Cursor
    focus: Cursor
end

struct Cursor
    byte: index
    line: index
    column: index
end
```

### 16.3 Event union

```moonlift
union EditorEvent
    insert_text(bytes: view(u8))
    delete_selection()
    move_left()
    move_right()
    move_to(pos: Cursor)
    save()
    open_file(path: view(u8))
end
```

### 16.4 Apply protocol

```moonlift
region apply_event(
    doc: ptr(Document),
    ev: ptr(EditorEvent);

    changed: cont(revision: u64),
    unchanged: cont(),
    invalid: cont(code: i32),
    needs_io: cont(kind: i32))
```

### 16.5 Phase facts

```moonlift
union RenderFact
    clear()
    cursor(line: i32, col: i32)
    text(line: i32, col: i32, bytes: view(u8), style: u32)
    rect(x: i32, y: i32, w: i32, h: i32, color: u32)
end
```

### 16.6 Render protocol

```moonlift
region render_document(
    doc: ptr(Document),
    viewport: Viewport;

    fact: cont(f: RenderFact),
    done: cont(),
    invalid: cont(code: i32))
```

This is the compiler pattern in Moonlift form:

```text
Document + EditorEvent
  -> apply_event
  -> Document'
  -> render_document
  -> RenderFact stream
  -> draw loop
```

No separate ASDL is necessary. The source model, events, apply protocol, render facts, and final loop are all typed Moonlift design artifacts.

---

## 17. Worked Example IV: Scheduler and Channels

### 17.1 Name the machine

```text
The scheduler consumes submitted jobs, wakeups, timers, and channel operations, and repeatedly transitions tasks between runnable, parked, running, and completed states.
```

### 17.2 Data tree

```moonlift
struct Task
    id: u64
    state: TaskState
    stack: ptr(u8)
    stack_len: index
    next: ptr(Task)
end

union TaskState
    new()
    runnable()
    running(worker: i32)
    parked(reason: ParkReason)
    done(code: i32)
end

union ParkReason
    channel_send(ch: ptr(Channel))
    channel_recv(ch: ptr(Channel))
    timer(deadline: i64)
    io(handle: ptr(u8))
end

struct Channel
    buffer: ptr(u8)
    cap: index
    head: index
    tail: index
    closed: bool
    send_waiters: ptr(Task)
    recv_waiters: ptr(Task)
end
```

### 17.3 Channel protocols

```moonlift
region send_i32(
    ch: ptr(Channel),
    value: i32;

    sent: cont(),
    parked: cont(task: ptr(Task)),
    closed: cont(),
    would_block: cont())

region recv_i32(
    ch: ptr(Channel);

    got: cont(value: i32),
    parked: cont(task: ptr(Task)),
    closed: cont(),
    would_block: cont())
```

### 17.4 Scheduler protocols

```moonlift
region claim_task(
    sched: ptr(Scheduler);

    got: cont(task: ptr(Task)),
    empty: cont(),
    shutdown: cont())

region run_task(
    task: ptr(Task);

    yielded: cont(task: ptr(Task)),
    parked: cont(task: ptr(Task), reason: ParkReason),
    completed: cont(task: ptr(Task), code: i32),
    faulted: cont(task: ptr(Task), code: i32))
```

### 17.5 Lua factory axis

Channels are generated by type:

```lua
local I32Chan = make_channel("I32Chan", moon.i32)
local JobChan = make_channel("JobChan", Job)
```

Each channel is monomorphic. No runtime type erasure is needed.

### 17.6 Platform axis

Threading backends are selected by Lua:

```lua
if ffi.os == "Windows" then
    return require("sched.windows").make()
else
    return require("sched.pthread").make()
end
```

The selected backend generates the correct externs. The scheduler machines remain Moonlift.

---

## 18. Review Method

Moonlift changes code review.

Review should happen in layers.

### 18.1 Review the data tree

Questions:

```text
Are the nouns correct?
Are products represented as structs?
Are stored choices represented as unions?
Is derived data excluded from persistent state?
Are views/pointers clear about ownership?
Are handles explicit?
```

### 18.2 Review the control tree

Questions:

```text
Are operations represented as regions?
Are all outcomes explicit?
Are continuation names precise?
Are payloads minimal and sufficient?
Are any booleans hiding protocols?
Are any status codes hiding variants?
```

### 18.3 Review region relationships

Questions:

```text
Which regions emit which?
Are exits forwarded intentionally?
Are local blocks named as states?
Are any functions used prematurely?
```

### 18.4 Review sealing

Questions:

```text
Which functions are ABI boundaries?
Which functions are merely internal convenience?
Could internal functions be regions?
Does each exported function hide a clean internal protocol?
```

### 18.5 Review Lua generation

Questions:

```text
What does Lua generate?
Are generated names stable?
Are generated variants monomorphic?
Are platform choices explicit?
Are externs selected after capability probing?
```

### 18.6 Review memory/resource ownership

Questions:

```text
Who owns each pointer?
How long is each view valid?
Can the pointer escape?
Is cleanup explicit?
Are scarce resources closed deterministically?
```

---

## 19. Testing Method

Moonlift testing should follow the dual-tree structure.

### 19.1 Type/protocol tests

These test that invalid designs are rejected:

```text
missing continuation fill
wrong continuation payload type
jump missing block parameter
duplicate case
unreachable control path
invalid conversion
```

### 19.2 Region behavior tests

Each region can be tested by filling its continuations with test blocks.

```text
parse_i32 exits ok for "123"
parse_i32 exits err for "-"
recv exits closed when channel is closed
send exits would_block when nonblocking and full
```

### 19.3 Lua oracle tests

Lua is ideal for reference behavior.

```text
generate random input
run Lua reference
run Moonlift compiled function
compare outputs / continuations / side effects
```

### 19.4 Phase tests

For compiler-like or interactive systems:

```text
source + event -> expected source'
source -> expected facts
changed subtree -> only affected phase recomputes
invalid source -> diagnostic facts
```

### 19.5 ABI tests

If emitting object/shared artifacts:

```text
C caller can call symbol
struct layout matches
view ABI matches
extern calls resolve
error codes stable
```

---

## 20. Tooling Implications

Because the design is in the Moonlift declaration graph, tools can be architectural.

Possible queries:

```text
Find all emit sites of region R.
Find all blocks that fill continuation C.
Find all regions with protocol P.
Find all continuations carrying type T.
Find all functions sealing region R.
Find all Lua factories generating region family F.
Find all structs reachable from root type T.
Find all protocols that can exit through `err`.
Find all callbacks replaced by continuation protocols.
```

This is more powerful than ordinary "find references" because the design concepts are first-class.

### 20.1 Design browser

A Moonlift IDE can show:

```text
Data tree
Control tree
Region graph
Emit graph
Continuation fill graph
Function seal graph
Lua factory outputs
C ABI boundary map
```

This is the replacement for stale architecture diagrams.

### 20.2 Refactoring

Renaming a continuation should update every fill.

Changing a continuation payload should reveal every affected block.

Changing a union variant should reveal every stored-consumption site.

Changing a struct field should reveal every data dependency.

The design is refactorable because it is typed.

---

## 21. Anti-Patterns

### 21.1 Boolean return where a protocol belongs

Bad:

```moonlift
func send(ch: ptr(Channel), value: i32) -> bool
```

Good:

```moonlift
region send(
    ch: ptr(Channel),
    value: i32;

    sent: cont(),
    closed: cont(),
    would_block: cont(),
    parked: cont(task: ptr(Task)))
```

### 21.2 Status code soup

Bad:

```moonlift
return -7
```

Better at boundaries:

```moonlift
return ERROR_TIMEOUT
```

Better internally:

```moonlift
timeout: cont(deadline: i64)
```

### 21.3 Stringly exits

Bad:

```text
status = "closed"
```

Good:

```moonlift
closed: cont()
```

### 21.4 Callback registry as architecture

Bad:

```lua
handlers["closed"] = function(...) ... end
```

Good:

```moonlift
region operation(...;
    closed: cont(),
    error: cont(code: i32))
```

Callbacks can exist at boundaries, but the internal protocol should be typed.

### 21.5 Premature functions

Bad:

```moonlift
func parse_string(...) -> ParseResult
```

Good internally:

```moonlift
region parse_string(...;
    ok: cont(next: index),
    err: cont(pos: index, code: i32))
```

Seal later if needed.

### 21.6 Overusing unions for immediate control

Bad:

```text
region result stored only so caller can immediately switch on it
```

Good:

```text
make it a continuation protocol
```

### 21.7 Overusing protocols for stored results

Bad:

```text
continuation protocol used where result must be queued/logged/stored
```

Good:

```text
make it a union
```

### 21.8 Derived data in source

Bad:

```text
Document stores both text and rendered glyph positions
```

Good:

```text
Document stores authored text.
Layout/render phases produce glyph/render facts.
```

### 21.9 Moonlift generics

Bad:

```text
Trying to add type parameters to Moonlift source.
```

Good:

```lua
local Vec_i32 = make_vec("Vec_i32", moon.i32)
```

Lua is the generator.

### 21.10 Parallel type universes

Bad:

```text
A memory library recreates mem.i32, mem.struct, mem.ptr.
```

Good:

```text
Moonlift owns types.
Libraries own patterns: scope, arena, resource, parser, scheduler.
```

---

## 22. Design Checklist

Use this before implementing a subsystem.

### 22.1 Machine statement

```text
This system consumes:
This system produces:
The main loop is:
```

### 22.2 Data tree

```text
Persistent source types:
Event unions:
Fact types:
Resource/handle types:
Temporary/intermediate types:
Stored result unions:
```

### 22.3 Control tree

```text
Regions:
Continuations:
Blocks/states:
Jumps/transitions:
Emits/compositions:
```

### 22.4 Union vs protocol decisions

```text
Outcome:
Stored or immediate?
Union or continuation?
Reason:
```

### 22.5 Phase tower

```text
Phase:
Question answered:
Input type:
Output type/protocol:
Consumer:
```

### 22.6 Sealed boundaries

```text
Function:
Internal region sealed:
ABI/API consumer:
Return convention:
```

### 22.7 Lua generation

```text
Factory:
Parameters:
Generated declarations:
Monomorphic variants:
Naming rule:
```

### 22.8 Foreign/world boundary

```text
Extern:
Capability probe:
Fallback:
Ownership:
Cleanup:
```

### 22.9 Memory

```text
Pointer/view:
Owner:
Lifetime:
Can escape?
Mutable?
Alias facts:
```

### 22.10 Review result

```text
All meaningful distinctions are represented as:
  field / variant / continuation / block / jump / phase fact / contract / Lua choice

No meaningful distinction is hidden in:
  string / callback / side table / convention / undocumented status code
```

---

## 23. What This Means for Software Architecture

Moonlift architecture is not object-oriented, functional, or MVC in the usual sense.

It is **typed machine architecture**.

A system is designed as:

```text
data tree
control tree
phase tower
memory/resource discipline
foreign boundary
Lua generation layer
sealed function/API boundary
```

This creates a new kind of architecture document: the source declarations themselves.

### 23.1 More precise than UML

UML can show relationships, but it usually cannot type the execution paths.

Moonlift can:

```text
this operation exits through exactly these continuations
this exit carries exactly these values
this emit fills exactly these exits
this block receives exactly these parameters
```

### 23.2 Less premature than full bodies

A region signature is not a full implementation, but it is more precise than a diagram.

It is the design sweet spot:

```text
not vague documentation
not full algorithm yet
typed enough to review
executable enough to implement directly
```

### 23.3 Better for onboarding

A new engineer can read the declaration graph:

```text
types tell what exists
unions tell stored alternatives
regions tell operations
continuations tell outcomes
blocks tell states
functions tell boundaries
Lua factories tell generated families
```

This is the system's map.

### 23.4 Better for performance

When the source describes the machine directly, the compiler removes less semantic fog.

Moonlift avoids:

```text
hidden allocation
control encoded as data when not needed
callback dispatch for local control
runtime generic dispatch
function boundaries where control splicing is better
```

The design method is also a performance method.

---

## 24. Conclusion

Designing software with Moonlift means designing explicit machines.

The old view needed a separate modeling language:

```text
ASDL schema -> compiler/framework -> implementation
```

The unified Moonlift view collapses this:

```text
Moonlift declaration graph = schema
Moonlift region graph      = control design
Moonlift functions         = sealed boundaries
Lua factories              = abstraction/generation
C ABI                      = world boundary
Cranelift                  = native code
```

The methodology is:

```text
1. Name the machine.
2. Build the data tree.
3. Build the control tree.
4. Relate them with regions.
5. Choose union for stored choice, continuation for immediate choice.
6. Design blocks as states and jumps as transitions.
7. Compose with emit.
8. Seal with functions.
9. Generate families with Lua.
10. Keep memory/resource/world boundaries explicit.
```

This is a complete design discipline.

It gives the programmer a way to move from an idea to a typed system without leaving the implementation language. It makes the architecture reviewable before bodies exist. It lets the compiler check the design. It lets tools browse the real structure. It lets Lua generate repeated machines without polluting Moonlift with source generics. It lets functions remain simple C ABI surfaces while the internal system keeps rich typed control.

The final doctrine:

> The design is the Moonlift type graph.  
> The behavior is the Moonlift control graph.  
> The relation between them is the region graph.  
> The implementation is the same artifact lowered to native code.

Moonlift is therefore not merely a language for writing programs. It is a language for designing executable machines.
