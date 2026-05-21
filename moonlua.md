Yes. Now we’re talking.

The PUC Lua interpreter’s canonical shape is:

```text
source
  → lexer/parser/codegen, mostly one pass
  → Proto {
        code: Instruction[]
        k: TValue[]
        p: Proto[]
        maxstacksize
        nups
    }
  → lua_State {
        TValue stack[]
        CallInfo frames[]
        openupval list
        global_State*
    }
  → luaV_execute()
        for (;;) {
            i = *pc++
            switch opcode(i) { ... }
        }
```

But that shape is shaped by **C constraints**:

- status codes instead of protocols
- `longjmp` instead of typed error exits
- macros instead of generated typed handlers
- C recursion / `luaD_precall` / `luaD_poscall` for Lua calls
- hidden slow paths in `luaV_gettable`, `luaV_settable`, `Arith`, metamethod helpers
- GC barriers hidden in setters
- tags consumed by ad hoc `if/switch` sites everywhere

In Moonlift we should not port that. We should recover the hidden machine and rewrite it as **products + protocols + regions**.

The design I would build is this:

---

# Moonlift Lua Interpreter Design

## 0. Core thesis

Keep Lua’s *semantic* machine:

```text
TValue stack
register bytecode VM
Proto/Closure/UpVal/Table
metatables
pcall/xpcall
coroutines
GC
```

But change the *implementation boundary*:

```text
C shape:
    opcode switch calls helper functions returning ints / longjmp / side effects

Moonlift shape:
    opcode switch emits typed regions
    helper outcomes are continuations
    errors are explicit protected-control exits
    calls/returns are VM-frame transitions
    GC is explicit heap protocol
    quickening is Lua-generated structure
```

The interpreter becomes a **single explicit control machine**, not a pile of C functions with conventions.

---

# 1. Runtime products

## `Value`

Do not model `TValue` as a semantic union internally. For storage, use a compact product.

```moonlift
struct Value
    tag: u32
    aux: u32
    bits: u64
end
```

Tags:

```text
TAG_NIL
TAG_BOOL
TAG_NUM
TAG_STR
TAG_TABLE
TAG_LCLOSURE
TAG_CCLOSURE
TAG_USERDATA
TAG_THREAD
TAG_LIGHTUD
```

`bits` stores either:

```text
f64 bits
pointer bits
integer bits, if we later add int specialization
```

Then define consumer regions:

```moonlift
region as_number(v: Value;
    number: cont(x: f64),
    not_number: cont())

region as_table(v: Value;
    table: cont(t: ptr(Table)),
    not_table: cont())

region is_false(v: Value;
    yes: cont(),
    no: cont())
```

Important distinction:

```text
Value tag = storage encoding.
Consumer region = semantic dispatch.
```

That follows the C rewrite guide exactly: stored tags are products; meaning is consumed by protocols.

---

## Heap object header

```moonlift
struct GCHeader
    next: ptr(GCHeader)
    tt: u8
    marked: u8
end
```

All collectable objects start with this.

```moonlift
struct String
    gc: GCHeader
    hash: u32
    len: index
    bytes: ptr(u8)
end

struct Table
    gc: GCHeader
    flags: u8              -- negative metamethod cache
    array_len: index
    array: ptr(Value)
    node_mask: u32
    nodes: ptr(Node)
    lastfree: ptr(Node)
    metatable: ptr(Table)
    shape_epoch: u32       -- for quickening later
end

struct Node
    key: Value
    value: Value
    next: ptr(Node)
end

struct Proto
    code: ptr(Instr)
    code_len: index
    constants: ptr(Value)
    protos: ptr(ptr(Proto))
    upvalue_names: ptr(ptr(String))
    maxstack: u16
    numparams: u8
    is_vararg: u8
    nups: u8
end

struct LClosure
    gc: GCHeader
    env: ptr(Table)
    proto: ptr(Proto)
    upvals: ptr(ptr(UpVal))
end

struct CClosure
    gc: GCHeader
    env: ptr(Table)
    fn: ptr(NativeFunc)
    upvals: ptr(Value)
    nupvals: u8
end

struct UpVal
    gc: GCHeader
    v: ptr(Value)          -- points into stack if open
    closed: Value          -- owns value if closed
    next_open: ptr(UpVal)
end
```

---

## Thread / VM state

```moonlift
struct LuaThread
    gc: GCHeader
    stack: ptr(Value)
    stack_size: index
    top: index

    frames: ptr(Frame)
    frame_count: index
    frame_cap: index

    open_upvals: ptr(UpVal)
    global: ptr(GlobalState)

    status: u8
    err_value: Value
end

struct Frame
    closure: Value         -- LClosure or CClosure
    base: index
    top: index
    pc: index
    wanted: i32

    return_mode: u16       -- normal, pcall, metamethod continuation, etc.
    return_a: u16
    return_b: u16
    return_c: u16
end

struct GlobalState
    registry: Value
    mainthread: ptr(LuaThread)
    string_table: ptr(StringTable)
    allgc: ptr(GCHeader)

    currentwhite: u8
    gcstate: u8
    totalbytes: index
    threshold: index

    tmname: ptr(ptr(String))   -- "__index", "__newindex", "__add", ...
end
```

The key is `return_mode`.

In C, a helper may call a metamethod and then return to the middle of an opcode handler. That is hidden by C call stack recursion. In Moonlift, dynamic Lua calls must survive arbitrary execution/yield/error, so the continuation becomes **explicit data**.

Examples:

```text
RET_NORMAL              -- ordinary Lua CALL returns to next pc
RET_GETTABLE_MM         -- __index result must be placed into ra
RET_SETTABLE_MM         -- __newindex completed; continue
RET_BINOP_MM            -- arithmetic metamethod result into ra
RET_PCALL               -- protected call boundary
```

This is not a violation of explicit programming. This is exactly the point where control must become data: dynamic Lua program control is not statically known.

---

# 2. Instruction format

PUC stores packed 32-bit instructions and decodes with macros.

In Moonlift I would load/compile to a decoded product:

```moonlift
struct Instr
    op: u16
    a: u16
    b: u16
    c: u16
    bx: u32
    sbx: i32
end
```

This is larger than PUC bytecode, but better for the interpreter:

- no bitfield macros
- Cranelift sees normal field loads
- Lua can generate opcode metadata
- quickening can add extra opcodes cleanly

If bytecode compatibility is needed, keep raw packed instructions on disk and decode once into `Instr[]` at load time.

---

# 3. VM protocol surface

The sealed public boundary:

```moonlift
func lua_resume_vm(L: ptr(LuaThread), nargs: i32) -> i32
    return region -> i32
    entry start()
        emit vm_resume(L, nargs;
            ok = ok,
            yielded = yielded,
            runtime_error = runtime_error,
            oom = oom)
    end

    block ok(nres: i32)
        return 0
    end

    block yielded(nres: i32)
        return 1
    end

    block runtime_error(code: i32)
        return 2
    end

    block oom()
        return 4
    end
    end
end
```

Internal protocol:

```moonlift
region vm_resume(
    L: ptr(LuaThread),
    nargs: i32;

    ok: cont(nres: i32),
    yielded: cont(nres: i32),
    runtime_error: cont(code: i32),
    oom: cont())
```

Everything inside is protocols. The C-ish integer return exists only at the sealed boundary.

---

# 4. Main interpreter loop

Shape:

```moonlift
region vm_loop(
    L: ptr(LuaThread);

    finished: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())

entry load_frame()
    let f: ptr(Frame) = current_frame(L)
    jump dispatch(
        frame = f,
        pc = f.pc,
        base = f.base,
        top = L.top)
end

block dispatch(
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index)

    let proto: ptr(Proto) = frame_proto(frame)
    let ins: Instr = proto.code[pc]

    switch ins.op do
    case OP_MOVE then
        emit op_move(L, frame, pc, base, top, ins; next = next)

    case OP_LOADK then
        emit op_loadk(L, frame, pc, base, top, ins; next = next)

    case OP_GETTABLE then
        emit op_gettable(L, frame, pc, base, top, ins;
            next = next,
            call = enter_call,
            error = error,
            oom = oom)

    case OP_CALL then
        emit op_call(L, frame, pc, base, top, ins;
            lua_call = enter_lua_call,
            native_call = enter_native_call,
            returned = next,
            yielded = yielded,
            error = error,
            oom = oom)

    case OP_RETURN then
        emit op_return(L, frame, pc, base, top, ins;
            resume_parent = resume_parent,
            finished = finished,
            error = error)

    default then
        jump error(code = ERR_BAD_OPCODE)
    end
end

block next(
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index)
    jump dispatch(frame = frame, pc = pc + 1, base = base, top = top)
end
end
```

Important: `pc`, `base`, and `top` are hot block parameters. We do **not** write them back to `LuaThread` on every opcode.

We commit only at safepoints:

```text
before allocation
before metamethod call
before native call
before yielding
before error handling
before GC
```

Region:

```moonlift
region commit_state(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    top: index;

    done: cont())
```

This is one of the biggest speed wins: PUC mutates `L->savedpc`, `L->base`, `L->top` defensively around slow paths. In Moonlift, we make the safepoints explicit.

---

# 5. Opcode handlers as regions

Example: `MOVE`

```moonlift
region op_move(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index,
    ins: Instr;

    next: cont(frame: ptr(Frame), pc: index, base: index, top: index))

entry start()
    stack_set(L, base + ins.a, stack_get(L, base + ins.b))
    jump next(frame = frame, pc = pc, base = base, top = top)
end
end
```

Example: `ADD`

```moonlift
region op_add(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index,
    ins: Instr;

    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    call: cont(),
    error: cont(code: i32),
    oom: cont())

entry start()
    let lhs: Value = rk_value(L, frame, base, ins.b)
    let rhs: Value = rk_value(L, frame, base, ins.c)

    emit number_binop(lhs, rhs, OP_ADD;
        number = fast_number,
        metamethod = slow_meta,
        type_error = type_error)
end

block fast_number(x: f64, y: f64)
    stack_set(L, base + ins.a, value_number(x + y))
    jump next(frame = frame, pc = pc, base = base, top = top)
end

block slow_meta()
    emit prepare_binop_metamethod_call(L, frame, pc, base, top, ins, TM_ADD;
        prepared = call,
        error = error,
        oom = oom)
end

block type_error()
    jump error(code = ERR_ARITH)
end
end
```

This is where Moonlift shines: the helper `number_binop` is not a function returning a status. It is a protocol:

```moonlift
region number_binop(lhs: Value, rhs: Value, op: i32;
    number: cont(x: f64, y: f64),
    metamethod: cont(),
    type_error: cont())
```

---

# 6. Table access

PUC hides a lot in `luaV_gettable`.

Moonlift should split it:

```moonlift
region table_get_fast(
    t: ptr(Table),
    key: Value;

    hit: cont(value: Value),
    miss_no_meta: cont(),
    metamethod: cont(mm: Value),
    error: cont(code: i32))
```

`GETTABLE` becomes:

```moonlift
region op_gettable(...;
    next: cont(...),
    call: cont(),
    error: cont(code: i32),
    oom: cont())

entry start()
    let obj: Value = stack_get(L, base + ins.b)
    let key: Value = rk_value(L, frame, base, ins.c)

    emit as_table(obj;
        table = have_table,
        not_table = non_table_index)
end

block have_table(t: ptr(Table))
    emit table_get_fast(t, key;
        hit = got,
        miss_no_meta = got_nil,
        metamethod = call_index_mm,
        error = error)
end

block got(value: Value)
    stack_set(L, base + ins.a, value)
    jump next(frame = frame, pc = pc, base = base, top = top)
end

block got_nil()
    stack_set(L, base + ins.a, value_nil())
    jump next(frame = frame, pc = pc, base = base, top = top)
end

block call_index_mm(mm: Value)
    emit prepare_index_metamethod_call(L, frame, pc, base, top, ins, mm;
        prepared = call,
        error = error,
        oom = oom)
end

block non_table_index()
    emit get_non_table_index_metamethod(L, obj;
        found = call_index_mm,
        missing = type_error)
end

block type_error()
    jump error(code = ERR_INDEX)
end
end
```

The slow path that C hides behind “maybe call `__index` recursively up to MAXTAGLOOP” becomes visible:

```moonlift
region resolve_index(
    L: ptr(LuaThread),
    obj: Value,
    key: Value;

    value: cont(v: Value),
    call_metamethod: cont(fn: Value, self: Value, key: Value),
    type_error: cont(),
    loop_error: cont())
```

---

# 7. Calls and returns

PUC has:

```c
luaD_precall() returns:
    0 = Lua function, enter luaV_execute
    1 = C function returned
    2 = yielded
```

Moonlift:

```moonlift
region prepare_call(
    L: ptr(LuaThread),
    func_slot: index,
    nargs: i32,
    wanted: i32,
    return_mode: u16;

    enter_lua: cont(frame: ptr(Frame)),
    enter_native: cont(fn: ptr(NativeFunc)),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

`OP_CALL` wires it:

```moonlift
emit prepare_call(...;
    enter_lua = enter_lua_call,
    enter_native = enter_native_call,
    returned = call_returned,
    yielded = yielded,
    error = error,
    oom = oom)
```

Entering Lua call:

```moonlift
block enter_lua_call(child: ptr(Frame))
    jump dispatch(
        frame = child,
        pc = 0,
        base = child.base,
        top = child.top)
end
```

Returning:

```moonlift
region op_return(...;
    resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    finished: cont(nres: i32),
    error: cont(code: i32))
```

Return handling examines the parent frame’s `return_mode`.

```moonlift
region handle_return_mode(
    L: ptr(LuaThread),
    parent: ptr(Frame),
    first_result: index,
    nres: i32;

    normal: cont(parent: ptr(Frame)),
    resume_gettable_mm: cont(parent: ptr(Frame), dst: index),
    resume_binop_mm: cont(parent: ptr(Frame), dst: index),
    pcall_success: cont(parent: ptr(Frame)),
    finished: cont(nres: i32),
    error: cont(code: i32))
```

This is the essential interpreter insight:

> Static interpreter control is Moonlift regions.  
> Dynamic Lua control is explicit frame data.

That boundary is clean.

---

# 8. Errors and protected calls

PUC uses `setjmp/longjmp`.

Moonlift should not.

Represent protected calls as frames with handler metadata:

```moonlift
struct ProtectedFrame
    frame_index: index
    stack_top: index
    handler_slot: index
    previous: ptr(ProtectedFrame)
end
```

Error protocol:

```moonlift
region raise_error(
    L: ptr(LuaThread),
    err: Value;

    caught: cont(frame: ptr(Frame), handler_pc: index),
    uncaught: cont(code: i32))
```

`pcall` is not magic. It installs a protected frame, calls the function, and receives either:

```text
success → push true + results
error   → restore stack, push false + error object
```

As protocol:

```moonlift
region protected_call(
    L: ptr(LuaThread),
    func_slot: index,
    nargs: i32,
    wanted: i32;

    success: cont(nres: i32),
    failure: cont(err: Value),
    oom: cont())
```

The sealed external C-like status code exists only at API edge.

---

# 9. GC as explicit heap protocol

Moonlift has no ambient GC. Lua’s GC becomes an explicit subsystem.

Allocation:

```moonlift
region alloc_table(
    G: ptr(GlobalState),
    narr: index,
    nrec: index;

    ok: cont(t: ptr(Table)),
    step_required: cont(),
    oom: cont())
```

Write barrier:

```moonlift
region write_barrier(
    G: ptr(GlobalState),
    parent: ptr(GCHeader),
    child: Value;

    clean: cont(),
    barriered: cont())
```

Table set wires barrier explicitly:

```moonlift
region table_set(
    L: ptr(LuaThread),
    t: ptr(Table),
    key: Value,
    value: Value;

    stored: cont(),
    metamethod: cont(mm: Value),
    error: cont(code: i32),
    oom: cont())
```

Hot path:

```text
find slot
store value
if parent black and child white → emit write_barrier
else continue
```

GC roots are explicit:

```text
thread stacks
frames
open upvalues
registry
global table
string table
metatables
temporary safepoint roots
```

The collector can be PUC-like incremental tri-color first. Generational later.

---

# 10. Metamethods

Metamethods are where C Lua gets messy.

In Moonlift, every metamethod path should be a region protocol.

```moonlift
region get_metamethod(
    G: ptr(GlobalState),
    obj: Value,
    event: u8;

    found: cont(mm: Value),
    missing: cont())
```

Binary operation:

```moonlift
region binop_dispatch(
    L: ptr(LuaThread),
    lhs: Value,
    rhs: Value,
    event: u8;

    fast_number: cont(x: f64, y: f64),
    call_mm: cont(mm: Value),
    type_error: cont())
```

Preparing a metamethod call:

```moonlift
region prepare_binop_metamethod_call(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index,
    ins: Instr,
    event: u8;

    prepared: cont(),
    error: cont(code: i32),
    oom: cont())
```

This region:

1. commits `pc/base/top`
2. writes call arguments
3. pushes a new frame
4. sets parent `return_mode = RET_BINOP_MM`
5. jumps to call engine

Then after the metamethod returns, `handle_return_mode` places the result into `ra`.

No C stack magic. No hidden continuation.

---

# 11. Lua metaprogramming layer

Use Lua to generate:

## Opcode table

```lua
local opcodes = {
  { name = "MOVE",     mode = "ABC",  handler = op_move },
  { name = "LOADK",    mode = "ABx",  handler = op_loadk },
  { name = "GETTABLE", mode = "ABC",  handler = op_gettable },
  ...
}
```

Generate:

- opcode constants
- instruction decoder
- switch arms
- debug names
- quickened opcode families
- disassembler
- validation table

This replaces PUC macro machinery.

## RK operand helpers

Generate specialized forms:

```text
rk_b_const
rk_b_reg
rk_c_const
rk_c_reg
```

For quickened instructions, avoid repeated `ISK()` checks.

---

# 12. Quickening layer

Baseline interpreter first. Then quicken.

Generic PUC opcodes:

```text
GETTABLE
SETTABLE
ADD
CALL
RETURN
FORLOOP
```

Quickened opcodes:

```text
GETTAB_ARRAY
GETTAB_STR_SLOT
GETTAB_HASH_SLOT
GETTAB_META
SETTAB_ARRAY
ADD_NUM
ADD_META
CALL_LUA_FIXED
CALL_NATIVE_FIXED
RETURN_FIXED
```

Products:

```moonlift
struct InlineCache
    shape_epoch: u32
    key: Value
    slot: index
    aux: u32
end

struct QuickInstr
    instr: Instr
    cache: InlineCache
end
```

Protocol:

```moonlift
region probe_gettable_cache(
    t: ptr(Table),
    key: Value,
    cache: ptr(InlineCache);

    hit: cont(slot: index),
    stale: cont(),
    miss: cont())
```

On miss:

```moonlift
region quicken_gettable(
    proto: ptr(Proto),
    pc: index,
    observed: ptr(Table),
    key: Value;

    patched: cont(),
    keep_generic: cont())
```

Metatable mutation bumps `shape_epoch`, so stale caches fail safely.

This is where Moonlift can beat a naïve C interpreter: not because the VM loop is magical, but because Lua generates a family of concrete handlers that C would encode with macro hell.

---

# 13. Frontend design

PUC fuses parser and codegen because C wants minimal memory and one pass.

Moonlift does not need to copy that constraint.

I would build:

```text
source bytes
  → lexer region/token stream
  → parser to AST or direct syntax ASDL
  → resolver/codegen phase
  → Proto
  → VM
```

But keep an escape hatch: for bootstrapping, compile source to `Proto` with a direct parser/codegen region.

Long term, use explicit compiler phases because:

- diagnostics improve
- syntax structure becomes inspectable
- LSP can reuse it
- bytecode validation is separate
- source-to-Proto lowering can be tested independently

Runtime speed is unaffected.

---

# 14. File/module sketch

```text
lua_vm/
  value.mlua              -- Value, tags, predicates, conversions
  heap.mlua               -- GCHeader, allocator, collector protocols
  table.mlua              -- Table, hash/array, get/set regions
  string.mlua             -- intern table, hashing
  proto.mlua              -- Proto, Instr, decoder
  closure.mlua            -- Closure, UpVal, open/close upvals
  frame.mlua              -- LuaThread, Frame, protected frames
  metamethod.mlua         -- get/call metamethod protocols
  call.mlua               -- prepare_call, return, native call
  errors.mlua             -- raise_error, protected_call
  opcodes.lua             -- Lua opcode specification/generator
  vm_loop.mlua            -- generated dispatch region
  api.mlua                -- sealed C/Lua API boundaries
```

---

# 15. The design rule

The interpreter has three layers:

```text
Layer 1: Storage products
    Value, Table, Proto, Frame, Closure, UpVal

Layer 2: Semantic protocols
    table_get, table_set, call_value, raise_error,
    binop_dispatch, write_barrier, alloc_object

Layer 3: VM region graph
    vm_loop + opcode handlers + call/return/error/GC composition
```

Do not let layer 1 leak semantics everywhere.

Bad:

```moonlift
if v.tag == TAG_TABLE then ...
elseif v.tag == TAG_STRING then ...
```

Good:

```moonlift
emit as_table(v;
    table = have_table,
    not_table = slow_path)
```

The tag exists as storage. The protocol owns meaning.

---

# 16. Why this can be fast

Because Moonlift changes the boundaries:

## PUC C

```text
opcode handler
  → helper function
      → maybe longjmp
      → maybe call metamethod
      → maybe GC
      → maybe update L->savedpc
  → return status
```

## Moonlift

```text
opcode handler region
  emits helper region
    exits through typed continuation
      next / call / error / oom / yield
```

The compiler sees the control graph. Fast paths inline. Slow paths are explicit. Safepoints are explicit. Calls do not recurse through C unless crossing a native boundary.

Main advantages:

1. **No hidden `longjmp` paths**
2. **No status-code cascades**
3. **No macro decoder spaghetti**
4. **No helper call tax for hot paths**
5. **Explicit safepoints**
6. **Generated opcode families**
7. **Quickening is structure, not patchy convention**
8. **GC barriers are visible and checkable**
9. **Metamethod continuation points are explicit**
10. **Call/return is one state machine, not scattered across `luaD_*`**

---

# 17. Implementation roadmap

## Phase 1 — Tiny VM

Support:

```text
nil/bool/number/string
MOVE, LOADK, LOADBOOL, LOADNIL
ADD/SUB/MUL/DIV numeric only
JMP, EQ, LT, LE
RETURN
CALL only for native builtins
```

No tables, no closures, no GC beyond arena/free-all.

Goal: prove VM loop shape.

---

## Phase 2 — Tables

Add:

```text
NEWTABLE
GETTABLE
SETTABLE
GETGLOBAL
SETGLOBAL
SELF
```

No metamethods yet. Hash table + array part.

Goal: validate table product and protocols.

---

## Phase 3 — Lua calls / closures / upvalues

Add:

```text
CLOSURE
GETUPVAL
SETUPVAL
CALL
TAILCALL
RETURN
VARARG
CLOSE
```

Goal: validate frame machine and open-upvalue list.

---

## Phase 4 — Metamethods

Add:

```text
__index
__newindex
__call
arithmetic metamethods
comparison metamethods
__len
__concat
```

Goal: validate dynamic continuation records.

---

## Phase 5 — Protected calls / coroutines

Add:

```text
pcall
xpcall
coroutine.resume
coroutine.yield
error propagation
```

Goal: replace `longjmp` semantics with explicit protected-frame protocol.

---

## Phase 6 — GC

Add:

```text
incremental mark/sweep
barriers
weak tables
finalizers
strings
userdata
```

Goal: full Lua heap semantics.

---

## Phase 7 — Quickening

Add:

```text
inline caches
specialized opcodes
superinstructions
shape epochs
negative metamethod caches
```

Goal: compete with high-quality C interpreters.

---

# Final shape

The interpreter I would design is:

```text
A native Moonlift region graph that interprets Lua register bytecode,
with PUC-like products but Moonlift-native protocols.

Storage:
    compact TValue, Table, Proto, Closure, Frame, UpVal, GC heap

Control:
    vm_loop dispatch region
    opcode handler regions
    table/metamethod/call/error/GC protocols
    explicit frame transition machine

Dynamic Lua control:
    explicit Frame + return_mode continuation records

Generation:
    Lua opcode spec generates handlers, switch arms, quickened variants

Boundary:
    external API sealed as C-like funcs
    internal VM entirely protocol-native
```

Short version:

> PUC Lua is a register VM written as C conventions.  
> Moonlift Lua should be a register VM written as an explicit control tree.  
> Keep the Lua machine. Replace the C-shaped boundaries.
