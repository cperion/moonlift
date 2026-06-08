# Designing Software with Moonlift

## Products, Protocols, Regions, and the Discipline of Explicit Machines

**Status:** revised methodology paper  
**Core thesis:** Moonlift software is designed with two semantic primitives: **products** and **protocols**. Products are data that exists together. Protocols are choices consumed by control. A region consumes product data and a continuation protocol, then transfers control to exactly one continuation with a product payload. A function is a sealed one-continuation region. Lua generates families of concrete machines.

---

## Abstract

Most typed languages give programmers product types and sum types, then organize computation around functions. This makes “choice” appear to be data. The programmer creates a sum value, returns it, stores it, passes it around, and eventually some consumer inspects the tag and dispatches.

Moonlift suggests a stricter design discipline.

In Moonlift, choice is not data by default. Choice is control. If a system must decide between alternatives, that decision should be represented as a continuation protocol: a set of named, typed exits that the caller must fill. If no dispatch is needed, no choice type should exist. If a choice appears to need storage, the designer should first ask whether they are merely delaying a dispatch point that should be named as a region.

This paper presents a full methodology for designing software with Moonlift under this stricter view. The design vocabulary is:

```text
Product      = data that exists together
Protocol     = named alternatives of control
Region       = product + protocol -> selected continuation payload
Function     = sealed region with one implicit continuation
Block        = named state carrying a product
Jump         = typed state transition
Emit         = graph composition by protocol filling
Lua factory  = generator of concrete products, protocols, regions, and functions
```

The result is a design method where the architecture is not a diagram, not a schema file, and not a convention. It is the Moonlift declaration graph itself.

---

## 1. Why the previous framing was wrong

A tempting first formulation of Moonlift design is:

```text
Data types:
  products = structs
  sums     = unions

Control types:
  protocols = region continuations
```

This is still too close to ordinary algebraic data type thinking.

It treats `union` as a legitimate semantic data primitive. It says there are two ways to represent alternatives:

```text
union        -> choice stored as data
continuation -> choice consumed as control
```

That framing misses the deeper point.

A union does not contain “more data.” It contains a tag plus one payload shape. Its entire purpose is that some later consumer will inspect the tag and dispatch. That means the semantic content of a union is not data. It is delayed control.

The corrected framing is:

```text
There are products.
There are protocols.
There are no semantic unions.
```

A stored tag can exist as a low-level encoding. A byte field can encode a kind. A table index can refer to one of several record arrays. A serialized stream can contain variant markers. But those are facts. They are not the semantic design.

The semantic design is the consumer:

```moonlift
region consume_expr(ast: ptr(Ast), expr: ExprRef;
    int_lit: cont(e: ptr(IntLitExpr)),
    name: cont(e: ptr(NameExpr)),
    call: cont(e: ptr(CallExpr)),
    invalid: cont(code: i32))
```

The important thing is not that some value is “one of int/name/call.” The important thing is that a machine consumes an encoded fact and routes control to one of several continuations.

This is the new rule:

> Every “or” in the design is presumed to be a protocol.  
> If there is no dispatch, there is no “or.”  
> If there is dispatch, name the consumer as a region.

---

## 2. The basic algebra

Moonlift design has two semantic type forms.

### 2.1 Product

A product is data that exists together.

Examples:

```moonlift
struct Cursor
    byte: index
    line: index
    column: index
end

struct BufferView
    data: ptr(u8)
    len: index
    stride: index
end

struct Job
    fn: ptr(u8)
    arg: ptr(u8)
    state: i32
end
```

A function parameter list is also a product:

```moonlift
func add(a: i32, b: i32): i32
```

means:

```text
input product  = (a: i32, b: i32)
output product = (result: i32)
```

A block parameter list is also a product:

```moonlift
block loop(i: index, acc: i32)
```

means:

```text
state product = (i: index, acc: i32)
```

Products are the semantic data structure in the design method. Data can be nested, referenced, indexed, viewed, and encoded, but it remains product-shaped: fields that exist together.

### 2.2 Protocol

A protocol is a set of named possible continuations.

```moonlift
region parse_number(
    p: ptr(u8),
    n: index,
    i: index;

    ok: cont(value: f64, next: index),
    err: cont(pos: index, code: i32))
```

The input before the semicolon is a product:

```text
(p, n, i)
```

The protocol after the semicolon is a control interface:

```text
ok(value, next)
err(pos, code)
```

Each continuation payload is itself a product.

The protocol is not returned. It is not allocated. It is not a runtime object. It is a set of control obligations. An emit site must fill it:

```moonlift
emit parse_number(p, n, i;
    ok = got_number,
    err = bad_number)
```

The caller says where each possible exit goes.

### 2.3 Region

A region relates products to protocols.

A precise but readable formulation:

```text
region R(input_product; protocol)
    consumes the input product
    executes a control machine
    chooses exactly one continuation in the protocol
    passes that continuation a product payload
```

So a region is not:

```text
Product -> Union
```

A region is:

```text
Product + Protocol -> selected continuation with Product payload
```

The protocol is supplied by the caller. The region consumes it by jumping into one of its continuations.

### 2.4 Function

A function is a sealed region with one implicit continuation.

```moonlift
func f(a: i32, b: i32): i32
```

is equivalent in spirit to:

```moonlift
region f_region(a: i32, b: i32;
    return: cont(result: i32))
```

The difference is that the continuation is sealed into an ABI/call boundary. A function has one entry and one return convention. It is useful when the machine must be callable from Lua, C, another function, or an external consumer.

The design law:

> Compose with regions.  
> Seal with functions.

---

## 3. Why union disappears as a design primitive

A union appears to be a data sum:

```moonlift
union ParseResult
    ok(value: f64, next: index)
    err(pos: index, code: i32)
end
```

But why does this value exist?

If the next operation is:

```moonlift
switch result.tag do
case ok then ...
case err then ...
end
```

then the union was only a boxed branch. The correct Moonlift form is the protocol:

```moonlift
region parse_number(...;
    ok: cont(value: f64, next: index),
    err: cont(pos: index, code: i32))
```

The union adds:

```text
tag storage
payload storage
construction
later destruction
switch
indirection
```

The region protocol gives:

```text
named exits
typed payloads
caller-filled destinations
direct jumps
no box
```

The union therefore hides a control edge inside data.

### 3.1 “But what if I need to store it?”

Then the question is not “which union should I store?”

The question is:

> What concrete fact am I storing, and which region consumes that fact later?

For example, an AST node does not need to be a semantic union. It can be encoded as product facts:

```moonlift
struct ExprRef
    kind: u8
    index: u32
end

struct IntLitExpr
    value: i64
end

struct NameExpr
    symbol: u32
end

struct CallExpr
    fn: ExprRef
    args_data: ptr(ExprRef)
    args_len: index
end
```

Then dispatch is a consuming region:

```moonlift
region visit_expr(
    ast: ptr(Ast),
    expr: ExprRef;

    int_lit: cont(e: ptr(IntLitExpr)),
    name: cont(e: ptr(NameExpr)),
    call: cont(e: ptr(CallExpr)),
    invalid: cont(code: i32))
```

The stored thing is not a semantic sum. It is an encoded fact. The protocol is where meaning happens.

### 3.2 “But what if many consumers inspect it?”

Then each consumer is a region, or a shared visitor protocol is generated by Lua.

```lua
local ExprProtocol = make_expr_protocol({
    "int_lit",
    "name",
    "call",
})
```

The repeated dispatch shape is real, but it is still a protocol shape. Lua can generate the dispatch regions, the encoded storage helpers, and the continuation lists. The semantic object is the consumer protocol, not the stored union.

### 3.3 “But what about events?”

Events are often modeled as unions:

```text
KeyPressed | MouseMoved | SaveRequested
```

In the stricter Moonlift design, that is not the semantic model. The semantic model is the event consumer:

```moonlift
region consume_event(
    ev: RawEvent;

    key_pressed: cont(code: i32, mods: i32),
    mouse_moved: cont(x: i32, y: i32),
    save_requested: cont(),
    invalid: cont(code: i32))
```

The event queue may store bytes, tags, payload indexes, or platform records. Those are products. The meaning is realized when `consume_event` dispatches to the protocol.

### 3.4 The hard rule

The methodology therefore uses this rule:

```text
If I need to dispatch:
    design a region protocol.

If I do not need to dispatch:
    design only products.

If I think I need a union:
    I have probably found a delayed dispatch.
    Name the consumer region.
```

---

## 4. Products are real data

This doctrine does not mean “everything is control.” It means choice is control.

Products remain real data.

A product is any group of facts that coexist:

```moonlift
struct Window
    x: i32
    y: i32
    w: i32
    h: i32
end

struct ThreadHandle
    raw: ptr(u8)
end

struct SourceSpan
    file_id: u32
    start: index
    len: index
end

struct DiagnosticPayload
    code: i32
    span: SourceSpan
    arg0: u64
    arg1: u64
end
```

A product does not ask the consumer to choose. It simply exists.

The product test:

```text
Do all fields exist at the same time?
Can the consumer use the fields without first choosing a semantic branch?
Is this a concrete memory shape?
```

If yes, it is product data.

---

## 5. Protocols are real choice

A protocol is any meaningful choice that a machine must consume.

Examples:

```moonlift
region authenticate(
    creds: ptr(Credentials);

    success: cont(user_id: u64),
    invalid: cont(),
    locked: cont(unlock_at: i64),
    rate_limited: cont(retry_after: i32))
```

```moonlift
region recv_i32(
    ch: ptr(Channel);

    got: cont(value: i32),
    empty: cont(),
    closed: cont(),
    parked: cont(waiter: ptr(Waiter)))
```

```moonlift
region resolve_name(
    ctx: ptr(Context),
    symbol: u32;

    local: cont(binding: u32),
    global: cont(item: u32),
    missing: cont(),
    ambiguous: cont(a: u32, b: u32))
```

The protocol test:

```text
Will some consumer branch on this?
Does the branch carry different payloads?
Would a boolean/status code/result object hide what can happen?
```

If yes, it is a protocol.

---

## 6. Regions consume protocols

The wording matters.

A region does not “return” one of several alternatives. It consumes a protocol. The caller gives the region a continuation environment:

```moonlift
emit recv_i32(ch;
    got = handle_value,
    empty = try_other_work,
    closed = stop_worker,
    parked = suspend_task)
```

From the caller's perspective, this is not a result to inspect. It is a wiring operation.

The region says:

```text
I may exit by `got`, `empty`, `closed`, or `parked`.
```

The caller says:

```text
Here is what each exit means in my local machine.
```

This is more precise than return values because every exit is wired at the composition site.

---

## 7. Blocks are product states

A block is a state point with a product payload.

```moonlift
block scan(i: index, acc: i32)
```

This means:

```text
state name = scan
state data = (i, acc)
```

A jump constructs the next state product:

```moonlift
jump scan(i = i + 1, acc = acc + value)
```

A loop is therefore just a self-transition:

```moonlift
block loop(i: index, acc: i32)
    if i >= n then jump done(total = acc) end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

No `for`, `while`, `break`, or `continue` is needed as a semantic primitive. Those are surface conveniences over state transitions.

The block design rule:

> Name the state.  
> Name the state product.  
> Make every transition explicit.

---

## 8. Functions are product-to-product only

Because a function has one implicit continuation, its shape is product-to-product.

```text
function : Product -> Product
```

This is why functions are excellent at boundaries:

```text
C ABI export
Lua callable native function
object-file symbol
stable library entry point
foreign callback
```

But functions are poor as the universal internal composition primitive. A function with many possible outcomes must either:

```text
return a status code
return a union/result
throw an exception
call callbacks
mutate side tables
```

All of these are ways to smuggle protocols through a product-only interface.

Moonlift gives the internal protocol directly. Therefore:

```text
Internal multi-outcome operation -> region
External sealed callable unit    -> function
```

---

## 9. The design methodology

The design procedure is now simpler than the earlier dual-tree version.

You do not search for products and sums. You search for products and protocols.

### Step 1 — State the machine

Write:

```text
This system consumes _____ and produces _____ by repeatedly _____.
```

Examples:

```text
The parser consumes bytes and produces Lua stack values by dispatching grammar states.

The editor consumes input events and produces render commands by applying edits and compiling the document view.

The scheduler consumes jobs and wakeups and produces worker execution by moving tasks through explicit states.
```

If this sentence is unclear, do not code yet.

### Step 2 — List the products

Find all concrete facts that exist together.

Ask:

```text
What is stored?
What is passed?
What is pointed to?
What is viewed?
What is owned?
What is a handle?
What is a byte-level encoding?
What is a phase fact?
```

Write structs and views for these.

Examples:

```moonlift
struct Token
    kind: u16
    start: index
    len: index
end

struct Task
    id: u64
    state: i32
    stack: ptr(u8)
    stack_len: index
end

struct EventRecord
    kind: u16
    payload_index: u32
end
```

Notice: `kind` fields are allowed. A tag as a concrete fact is fine. The semantic mistake is treating the tag as if it were the design. The design is the consumer region that interprets it.

### Step 3 — List the protocols

Find every meaningful dispatch.

Ask:

```text
What can happen next?
Where does control branch?
What outcomes must the caller handle?
What errors are actually distinct paths?
What waits, parks, retries, closes, or succeeds?
```

Write region protocols.

```moonlift
region consume_token(
    tokens: ptr(Token),
    i: index;

    identifier: cont(start: index, len: index),
    number: cont(start: index, len: index),
    punctuation: cont(byte: u8),
    eof: cont(),
    invalid: cont(code: i32))
```

### Step 4 — Delete fake choices

For every proposed union/result/status object, ask:

```text
Who consumes this?
```

If the answer is “the next piece of code,” delete the union and make a region protocol.

If the answer is “some later phase,” name that later phase as a region and store only the concrete facts needed for it.

If the answer is “nobody,” delete the distinction.

### Step 5 — Design regions as product/protocol machines

Each region should have:

```text
input product
continuation protocol
internal block states
explicit jumps
emits to subregions
```

Write signatures before bodies.

```moonlift
region parse_value(
    L: ptr(lua_State),
    p: ptr(u8),
    n: index,
    i: index;

    string: cont(next: index),
    number: cont(next: index),
    array: cont(next: index),
    object: cont(next: index),
    literal: cont(next: index),
    err: cont(pos: index, code: i32))
```

Maybe this protocol is too fine-grained for the caller. If the caller does not need to know which kind of value was parsed, collapse it:

```moonlift
region parse_value(
    L: ptr(lua_State),
    p: ptr(u8),
    n: index,
    i: index;

    ok: cont(next: index),
    err: cont(pos: index, code: i32))
```

The protocol belongs to the consumer. Do not expose distinctions the consumer does not need.

### Step 6 — Compose with emit

Composition is protocol filling.

```moonlift
emit parse_value(L, p, n, i;
    ok = after_value,
    err = bad_json)
```

This is the point where design becomes executable. Every outcome must be handled.

### Step 7 — Seal with functions

Only when a machine must become a callable unit:

```moonlift
func decode_json(L: ptr(lua_State), p: ptr(u8), n: index): i32
    return region: i32
    entry start()
        emit parse_value(L, p, n, 0; ok = done, err = failed)
    end

    block done(next: index)
        return 1
    end

    block failed(pos: index, code: i32)
        return 0 - code
    end
    end
end
```

The function returns a product. The region inside handles protocol-rich control.

### Step 8 — Generate repeated machines with Lua

Lua owns abstraction.

If many protocols have the same shape, generate them.

If many encoded tags dispatch similarly, generate the switch arms.

If many types need the same channel/scheduler/parser machine, generate monomorphic variants.

```lua
local function make_channel(name, T)
    -- returns concrete structs and regions:
    -- send_T, recv_T, close_T, etc.
end
```

Moonlift receives only concrete products, protocols, regions, and functions.

---

## 10. Worked example: compiler AST without semantic unions

A normal compiler design starts with a sum type:

```text
Expr = IntLit | Name | Call | Binary
```

Moonlift's stricter design starts with storage facts and a consumer protocol.

### 10.1 Products

```moonlift
struct ExprRef
    kind: u8
    index: u32
end

struct IntLitExpr
    value: i64
end

struct NameExpr
    symbol: u32
end

struct CallExpr
    fn: ExprRef
    args_data: ptr(ExprRef)
    args_len: index
end

struct BinaryExpr
    op: u8
    lhs: ExprRef
    rhs: ExprRef
end

struct Ast
    int_lits: ptr(IntLitExpr)
    names: ptr(NameExpr)
    calls: ptr(CallExpr)
    binaries: ptr(BinaryExpr)
end
```

This is concrete data. No polymorphism. No semantic union.

### 10.2 Protocol

```moonlift
region visit_expr(
    ast: ptr(Ast),
    expr: ExprRef;

    int_lit: cont(e: ptr(IntLitExpr)),
    name: cont(e: ptr(NameExpr)),
    call: cont(e: ptr(CallExpr)),
    binary: cont(e: ptr(BinaryExpr)),
    invalid: cont(code: i32))
```

This is where the choice lives.

### 10.3 Typechecking as protocol composition

```moonlift
region typecheck_expr(
    ctx: ptr(TypeContext),
    ast: ptr(Ast),
    expr: ExprRef;

    ok: cont(typed: TypedExprRef, ty: TypeId),
    missing_symbol: cont(symbol: u32),
    type_mismatch: cont(found: TypeId, expected: TypeId),
    invalid_expr: cont(code: i32))
entry start()
    emit visit_expr(ast, expr;
        int_lit = tc_int_lit,
        name = tc_name,
        call = tc_call,
        binary = tc_binary,
        invalid = invalid_expr)
end

block tc_int_lit(e: ptr(IntLitExpr))
    jump ok(typed = ..., ty = ...)
end

block tc_name(e: ptr(NameExpr))
    ...
end
end
```

The AST is stored as products. The semantic alternatives are consumed as a protocol.

### 10.4 Diagnostics

Diagnostics are often modeled as unions. Under this discipline, diagnostics can be encoded as products plus render/consume protocols.

```moonlift
struct DiagnosticRecord
    code: i32
    span_start: index
    span_len: index
    arg0: u64
    arg1: u64
end

region render_diagnostic(
    diag: ptr(DiagnosticRecord);

    missing_symbol: cont(symbol: u32, span_start: index, span_len: index),
    type_mismatch: cont(found: TypeId, expected: TypeId, span_start: index, span_len: index),
    invalid: cont(code: i32))
```

The stored diagnostic record is a compact fact. The semantic meaning is the rendering/consuming protocol.

---

## 11. Worked example: editor events without event unions

A typical editor might model events as a union. In the strict Moonlift method, the event queue stores encoded facts, and a consumer region dispatches.

### 11.1 Products

```moonlift
struct RawEvent
    kind: u16
    payload_index: u32
end

struct KeyPayload
    code: i32
    mods: i32
end

struct MousePayload
    x: i32
    y: i32
    button: i32
end

struct EventStore
    keys: ptr(KeyPayload)
    mice: ptr(MousePayload)
    raws: ptr(RawEvent)
end
```

### 11.2 Protocol

```moonlift
region consume_event(
    store: ptr(EventStore),
    ev: RawEvent;

    key: cont(p: ptr(KeyPayload)),
    mouse: cont(p: ptr(MousePayload)),
    save: cont(),
    quit: cont(),
    invalid: cont(code: i32))
```

### 11.3 Apply as protocol consumer

```moonlift
region apply_event(
    doc: ptr(Document),
    store: ptr(EventStore),
    ev: RawEvent;

    changed: cont(new_revision: u64),
    unchanged: cont(),
    needs_io: cont(code: i32),
    invalid: cont(code: i32))
entry start()
    emit consume_event(store, ev;
        key = handle_key,
        mouse = handle_mouse,
        save = save_doc,
        quit = unchanged,
        invalid = invalid)
end
...
end
```

The design says exactly where dispatch happens. The stored event is just a fact.

---

## 12. Worked example: scheduler

A scheduler is naturally product/protocol shaped.

### 12.1 Products

```moonlift
struct Task
    id: u64
    state: i32
    stack: ptr(u8)
    stack_len: index
    next: ptr(Task)
end

struct Queue
    head: ptr(Task)
    tail: ptr(Task)
    closed: bool
end

struct Scheduler
    runnable: Queue
    parked: Queue
    shutting_down: bool
end
```

### 12.2 Protocols

```moonlift
region claim_task(
    sched: ptr(Scheduler);

    got: cont(task: ptr(Task)),
    empty: cont(),
    shutdown: cont())

region run_task(
    task: ptr(Task);

    yielded: cont(task: ptr(Task)),
    parked: cont(task: ptr(Task), reason: i32),
    completed: cont(task: ptr(Task), code: i32),
    faulted: cont(task: ptr(Task), code: i32))
```

No `TaskState` union is required as the semantic design. A `state: i32` may exist as an encoded fact. The scheduler regions consume that fact and route control.

### 12.3 Channel protocols

```moonlift
region send_i32(
    ch: ptr(Channel),
    value: i32;

    sent: cont(),
    closed: cont(),
    would_block: cont(),
    parked: cont(task: ptr(Task)))

region recv_i32(
    ch: ptr(Channel);

    got: cont(value: i32),
    closed: cont(),
    would_block: cont(),
    parked: cont(task: ptr(Task)))
```

A channel operation is not a return value. It is a protocol.

---

## 13. How this changes compiler design

A compiler designed this way does not primarily consist of tree unions and passes returning results.

It consists of:

```text
product storage facts
visitor/consumer protocols
phase regions
diagnostic/output protocols
sealed functions at tooling/ABI boundaries
```

### 13.1 Phase example

```moonlift
region resolve_name(
    ctx: ptr(BindContext),
    symbol: u32;

    local: cont(binding: u32),
    global: cont(item: u32),
    missing: cont(),
    ambiguous: cont(a: u32, b: u32))
```

No `ResolveResult` union.

### 13.2 Validation example

```moonlift
region validate_jump(
    r: ptr(TypedRegion),
    jump_id: u32;

    valid: cont(),
    missing_target: cont(target: u32),
    wrong_args: cont(expected: u32, found: u32),
    type_error: cont(arg: u32, expected: TypeId, found: TypeId))
```

No `ValidationResult` union.

### 13.3 Backend lowering

```moonlift
region lower_region(
    r: ptr(TypedRegion),
    out: ptr(BackBuilder);

    emitted: cont(first_cmd: index, count: index),
    invalid_control: cont(code: i32),
    unsupported: cont(feature: i32))
```

The compiler phase API is explicit. Every meaningful outcome is a continuation.

The compiler can still store facts. But stored facts are products: IDs, spans, tables, records, command arrays, diagnostic records. Their semantic interpretation is done by protocols.

---

## 14. Phase design in the product/protocol model

Interactive software and compilers both have phases. The phase model becomes:

```text
Source products
Event products
Apply protocol
Phase protocols
Fact products
Final loop
```

### 14.1 Source products

A source product is authored or persistent state.

```moonlift
struct Document
    pieces: ptr(Piece)
    piece_count: index
    revision: u64
end
```

### 14.2 Event products

Events are encoded facts, not semantic unions.

```moonlift
struct RawEvent
    kind: u16
    payload_index: u32
end
```

### 14.3 Apply protocol

```moonlift
region apply_event(
    doc: ptr(Document),
    events: ptr(EventStore),
    ev: RawEvent;

    changed: cont(revision: u64),
    unchanged: cont(),
    invalid: cont(code: i32))
```

### 14.4 Fact products

A render fact can be encoded as product data:

```moonlift
struct RenderCmd
    kind: u16
    x: i32
    y: i32
    a: u64
    b: u64
end
```

The consumer protocol interprets it:

```moonlift
region consume_render_cmd(
    cmd: RenderCmd;

    clear: cont(color: u32),
    text: cont(x: i32, y: i32, data: ptr(u8), len: index),
    rect: cont(x: i32, y: i32, w: i32, h: i32, color: u32),
    invalid: cont(code: i32))
```

Again: the stored command is a product. The semantic alternatives are protocols.

---

## 15. Memory and resource design

Memory also follows products/protocols.

A pointer is product data:

```moonlift
struct Buffer
    data: ptr(u8)
    len: index
end
```

Ownership is not hidden in the pointer. It is a design fact outside or around the pointer:

```text
LuaJIT owns this buffer.
An arena owns this allocation.
A C library owns this handle.
The caller owns this view.
```

Operations on memory are protocols when they have meaningful outcomes:

```moonlift
region reserve_bytes(
    arena: ptr(Arena),
    n: index;

    ok: cont(ptr: ptr(u8), len: index),
    oom: cont(),
    invalid: cont(code: i32))
```

Resource operations are protocols:

```moonlift
region close_handle(
    h: ptr(Handle);

    closed: cont(),
    already_closed: cont(),
    error: cont(code: i32))
```

No resource result union is needed.

---

## 16. Platform and foreign design

Lua selects capabilities. Moonlift consumes the selected externs.

The product/protocol method still applies:

```text
foreign handle       -> product
foreign operation    -> region/function
foreign outcomes     -> protocol
sealed ABI call      -> function/extern
platform variation   -> Lua factory
```

Example:

```lua
if ffi.os == "Windows" then
    return require("thread.windows").make()
else
    return require("thread.pthread").make()
end
```

Both backends generate the same conceptual protocols:

```moonlift
region start_thread(
    entry: ptr(u8),
    arg: ptr(u8);

    started: cont(handle: ptr(ThreadHandle)),
    failed: cont(code: i32))
```

Platform differences are generated by Lua. Runtime choices are protocols.

---

## 17. Design review checklist

A Moonlift design review should now ask:

### Products

```text
What concrete facts exist?
Which fields coexist?
Which values are handles, pointers, views, or encoded records?
Are any products secretly carrying a semantic choice?
```

### Protocols

```text
Where does control branch?
Are all outcomes named?
Are payload products minimal?
Does every dispatch have a named consumer region?
```

### Fake unions

```text
Is there a result object whose only purpose is later switching?
Is there a kind/tag treated as the design instead of as an encoding?
Is there a stored choice with no named future consumer?
Is there polymorphism hidden in a value?
```

### Regions

```text
Does each region have a clear input product?
Does each region have a clear protocol?
Are internal states blocks with typed products?
Are sub-machines composed with emit?
```

### Functions

```text
Is this function really a sealed boundary?
Should this internal function be a region?
Is it returning a status/result because it lacks a protocol?
```

### Lua

```text
What is generated?
What are the axes of variation?
Are generated machines monomorphic?
Is platform selection explicit?
```

---

## 18. Anti-patterns

### 18.1 Result object

Bad:

```moonlift
func parse(...): ParseResult
```

Good:

```moonlift
region parse(...;
    ok: cont(...),
    err: cont(...))
```

### 18.2 Semantic union

Bad:

```moonlift
union Expr
    int_lit(...)
    call(...)
end
```

Better:

```moonlift
struct ExprRef
    kind: u8
    index: u32
end

region visit_expr(...;
    int_lit: cont(...),
    call: cont(...),
    invalid: cont(...))
```

### 18.3 Boolean protocol

Bad:

```moonlift
func try_recv(...): bool
```

Good:

```moonlift
region recv(...;
    got: cont(...),
    empty: cont(),
    closed: cont())
```

### 18.4 Status code soup

Bad:

```moonlift
return -7
```

Good internally:

```moonlift
timeout: cont(...)
```

Acceptable at a sealed function boundary:

```moonlift
return ERROR_TIMEOUT
```

### 18.5 Callback registry

Bad:

```lua
handlers["closed"] = function() ... end
```

Good internally:

```moonlift
closed: cont()
```

### 18.6 Stored choice with no consumer

Bad:

```text
A tag field exists because maybe someone will need it later.
```

Good:

```text
Delete it until a consumer protocol exists.
```

---

## 19. Tooling implications

If Moonlift design is products and protocols, tooling should show those directly.

Useful views:

```text
Product graph
Protocol graph
Region graph
Emit/fill graph
Function seal graph
Tag-consumer graph
Lua factory output graph
Foreign capability graph
```

Important queries:

```text
Which regions consume this encoded kind?
Which products contain tag-like fields?
Which functions return status codes?
Which regions expose `err`?
Which emit sites fill `closed`?
Which internal functions should be regions?
```

A particularly useful linter:

```text
Flag every function returning a tag/status/result-like product.
Ask whether it should be a region protocol.
```

Another:

```text
Flag every product with `kind`, `tag`, or `type` field that lacks an obvious consuming region.
```

The goal is not to forbid encodings. The goal is to ensure encodings have named consumers.

---

## 20. Final doctrine

The final methodology is:

```text
1. Products are data.
2. Protocols are choice.
3. Regions consume products and protocols.
4. Functions are sealed product-to-product boundaries.
5. Blocks are product states.
6. Jumps are typed transitions.
7. Emits compose protocols.
8. Lua generates concrete machines.
9. Tags are encodings, not semantic design.
10. Unions are not a design primitive.
```

The most compact statement:

> If I need to dispatch, I need a protocol.  
> If I do not need to dispatch, I do not need a union.

Or:

> Choice is control.  
> Data is product.  
> Moonlift is the language that lets the source say that directly.

---

## 21. Conclusion

Moonlift design is not object-oriented design, not functional design, and not algebraic-data-type design in the usual sense.

It is **explicit machine design**.

The architecture is made of products and protocols. Products describe the concrete facts that exist. Protocols describe the choices that machines consume. Regions relate the two. Blocks name internal states. Jumps name state transitions. Emits compose machines. Functions seal machines at boundaries. Lua generates families of machines without adding runtime polymorphism.

This is why Moonlift can feel both lower-level and more expressive than conventional systems languages. It does not force the programmer to encode control as data. It does not require a separate modeling language. It does not hide the state machine behind functions, callbacks, exceptions, or unions.

The design is the product graph plus the protocol graph.

The implementation is the same graph lowered to native code.

That is the Moonlift method.
