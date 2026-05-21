# Moonlift Lua Interpreter VM — Final Type-First Design

Status: architectural design document.  
Scope: a complete Moonlift-native design for a PUC-Lua-compatible register-bytecode interpreter VM.  
Audience: implementers who know Lua, Moonlift regions, and explicit-programming discipline.  
Primary inputs: PUC Lua 5.1 / LuaJIT `host/minilua.c`, `explicit_programming.md`, `rewriting_c_to_idiomatic_moonlift.md`.

This document is self-contained. It does not specify a temporary subset of Lua. It specifies the complete VM architecture. Implementation may be staged, but the design here is the final target shape.

---

## 0. Design thesis

PUC Lua is a compact register VM written in C. Its canonical runtime shape is:

```text
source -> compiler -> Proto
Proto.code[] + Proto.constants[]
LuaThread stack[] + CallInfo frames[]
luaV_execute: fetch/decode/switch/execute
```

That shape is good. The C encoding of that shape is not the final shape we want in Moonlift.

C hides the machine in:

- integer status returns
- `setjmp` / `longjmp`
- out-parameters
- macros for bytecode decoding and value access
- helper functions that may allocate, call metamethods, yield, or raise
- implicit GC barriers in setters
- call stack recursion between `luaV_execute`, `luaD_precall`, and C functions
- repeated tag switches with local conventions

Moonlift should keep Lua's semantic machine and rewrite the C conventions as explicit structure:

```text
Products      storage that exists together
Protocols     choices consumed immediately as control
Regions       machines with typed exits
Blocks        VM states with named live values
Jumps         explicit transitions
Functions     sealed external boundaries only
Lua           generator of opcode families, constants, and monomorphic handlers
```

The final interpreter is therefore:

> A PUC-like register VM whose hot loop is a Moonlift region graph. Storage is compact products. Semantics are consumed through continuation protocols. Dynamic Lua control is represented explicitly in frames. External APIs are sealed functions.

---

## 1. Non-negotiable design rules

### 1.1 Storage tags are not semantic design

`Value.tag`, `Instr.op`, `Frame.resume_mode`, and table node state are storage encodings. They are necessary, compact, and hot. But semantic consumers must be named regions.

Wrong shape:

```moonlift
if v.tag == TAG_TABLE then ... end
```

Correct shape:

```moonlift
emit value_as_table(v; table = have_table, not_table = slow_path)
```

Storage can be tag-based. Meaning is consumed through protocols.

### 1.2 Every C status convention becomes a continuation protocol

PUC shape:

```c
luaD_precall(...) -> 0 Lua call, 1 C call returned, 2 yielded
```

Moonlift shape:

```moonlift
region prepare_call(...;
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(fn: ptr(NativeFunc)),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

### 1.3 Errors are control, not `longjmp`

Lua errors unwind to protected boundaries. In C this is `longjmp`. In Moonlift it is an explicit region:

```moonlift
region raise_error(L: ptr(LuaThread), err: Value;
    caught: cont(frame: ptr(Frame), handler: ptr(ProtectedFrame)),
    uncaught: cont(code: i32))
```

### 1.4 Safepoints are explicit

The interpreter keeps hot state in block parameters:

```text
frame, pc, base, top
```

It commits that state to `LuaThread` and `Frame` only before operations that may re-enter the VM, allocate, yield, call native code, invoke hooks, or raise errors.

### 1.5 Static VM control is regions; dynamic Lua control is frame data

Moonlift regions handle the interpreter's static structure: opcode dispatch, table access, call preparation, return handling, GC, errors.

Lua programs create dynamic continuations at runtime: a metamethod call must return into the middle of `GETTABLE`; `pcall` must catch a future error; coroutine yield must resume later. Those dynamic continuations are represented as frame products:

```text
Frame.resume_mode + Frame.resume payload fields
```

This is the correct boundary between typed static control and dynamic script control.

---

## 2. Top-level architecture

```text
                  +-----------------------+
                  | source/compiler layer |
                  | produces Proto        |
                  +-----------+-----------+
                              |
                              v
+-------------------------------------------------------------+
|                       VM runtime                            |
|                                                             |
|  Products: Value, Table, Proto, Closure, UpVal, Frame, Heap |
|  Protocols: table_get, call, return, raise, gc, metamethod  |
|  Region graph: vm_loop + opcode handlers + slow engines     |
|                                                             |
+-------------------------------------------------------------+
                              |
                              v
                  +-----------------------+
                  | sealed API functions  |
                  | C/Lua compatible      |
                  +-----------------------+
```

The VM consumes a `Proto` and a `LuaThread`. It does not require the parser/compiler to have any particular implementation. Source parsing and code generation are separate compiler layers; the VM begins at executable `Proto` values.

---

# Part I — Data type tree

The data tree is the complete set of storage products and delayed-control records.

Moonlift syntax below is intentionally header-like. Names and field widths are design commitments; exact module paths can be chosen during implementation.

---

## 3. Scalar aliases and constants

```moonlift
-- Scalar aliases by convention
-- ValueTag, OpCode, TMEvent, FrameMode, ThreadStatus, ErrorCode,
-- GCColor, GCState are stored as integer scalars.
```

### 3.1 Value tags

```text
TAG_NIL
TAG_FALSE
TAG_TRUE
TAG_LIGHTUD
TAG_NUM
TAG_STR
TAG_TABLE
TAG_LCLOSURE
TAG_CCLOSURE
TAG_USERDATA
TAG_THREAD
TAG_PROTO        -- internal/debug/compiler object if exposed
```

Boolean is split into `TAG_FALSE` and `TAG_TRUE` instead of `TAG_BOOL + payload`, so falsiness is one tag compare for `nil/false` and truthiness is all others.

### 3.2 Metamethod events

PUC-compatible events:

```text
TM_INDEX
TM_NEWINDEX
TM_GC
TM_MODE
TM_EQ
TM_ADD
TM_SUB
TM_MUL
TM_DIV
TM_MOD
TM_POW
TM_UNM
TM_LEN
TM_LT
TM_LE
TM_CONCAT
TM_CALL
TM_N
```

### 3.3 Thread statuses

```text
THREAD_OK
THREAD_YIELDED
THREAD_RUNTIME_ERROR
THREAD_OOM
THREAD_DEAD
```

### 3.4 Frame resume modes

These encode dynamic Lua continuation points.

```text
RESUME_NORMAL              -- ordinary call returns to caller's next pc
RESUME_TAILCALL            -- tailcall frame replacement
RESUME_PCALL               -- protected call result shaping
RESUME_XPCALL              -- error handler call shaping
RESUME_GETTABLE_MM         -- __index result goes to destination register
RESUME_SETTABLE_MM         -- __newindex completed
RESUME_BINOP_MM            -- binary metamethod result goes to destination register
RESUME_UNOP_MM             -- unary metamethod result goes to destination register
RESUME_LEN_MM              -- __len result goes to destination register
RESUME_CONCAT_MM           -- __concat result resumes concat state
RESUME_EQ_MM               -- __eq result resumes comparison branch
RESUME_LT_MM               -- __lt result resumes comparison branch
RESUME_LE_MM               -- __le / fallback __lt result resumes branch
RESUME_CALL_MM             -- __call produced call result
RESUME_TFORLOOP_CALL       -- iterator call result resumes TFORLOOP
RESUME_NATIVE_CONT         -- native continuation / coroutine boundary
```

### 3.5 Error codes

Errors carry a `Value` payload when crossing Lua-visible boundaries and a compact code for sealed C-like boundaries.

```text
ERR_NONE
ERR_RUNTIME
ERR_SYNTAX
ERR_MEMORY
ERR_HANDLER
ERR_YIELD
ERR_BAD_OPCODE
ERR_STACK_OVERFLOW
ERR_C_STACK_OVERFLOW
ERR_TYPE
ERR_ARITH
ERR_COMPARE
ERR_CONCAT
ERR_INDEX
ERR_CALL
ERR_LOOP
ERR_API
```

---

## 4. Core value representation

### 4.1 `Value`

```moonlift
struct Value
    tag: u32
    aux: u32
    bits: u64
end
```

Encoding:

```text
nil                  tag = TAG_NIL, bits ignored
false                tag = TAG_FALSE
true                 tag = TAG_TRUE
number               tag = TAG_NUM, bits = f64 bits
collectable pointer  tag = object kind, bits = ptr bits
light userdata       tag = TAG_LIGHTUD, bits = ptr bits
```

`aux` is reserved for specialization and ABI convenience. It may store short integer payloads, cached subtype data, or remain zero. It is not semantic state.

### 4.2 Value invariants

- `TAG_NIL` and `TAG_FALSE` are false; every other tag is true.
- Collectable tags always point to objects whose header `tt` matches the tag.
- A `Value` is copyable by value.
- Every write of a collectable `Value` into a collectable container must pass through a barrier region unless the container is known white/new.

---

## 5. Heap object products

### 5.1 Common header

```moonlift
struct GCHeader
    next: ptr(GCHeader)
    tt: u8
    marked: u8
end
```

Every collectable object begins with `GCHeader`.

### 5.2 Strings

```moonlift
struct String
    gc: GCHeader
    reserved: u8        -- lexer/reserved word marker
    hash: u32
    len: index
    bytes: ptr(u8)
end
```

Strings are interned. Equality is pointer equality after interning.

### 5.3 Userdata

```moonlift
struct UserData
    gc: GCHeader
    metatable: ptr(Table)
    env: ptr(Table)
    len: index
    data: ptr(u8)
end
```

### 5.4 Tables

```moonlift
struct Node
    key: Value
    value: Value
    next: ptr(Node)
end

struct Table
    gc: GCHeader
    flags: u32              -- negative metamethod cache bits
    array_len: index
    array: ptr(Value)
    node_mask: u32          -- hash size - 1
    nodes: ptr(Node)
    lastfree: ptr(Node)
    metatable: ptr(Table)
    shape_epoch: u32        -- increments on structural/metatable changes
end
```

Table invariants:

- Integer keys in `[1, array_len]` prefer array part.
- Hash part uses chained nodes compatible with Lua semantics.
- A nil value in a node means absent.
- `flags` caches missing metamethods; any metatable mutation clears affected flags.
- `shape_epoch` changes on resize, metatable replacement, and shape-changing insert/delete. It supports quickening.

### 5.5 Prototypes and instructions

```moonlift
struct Instr
    op: u16
    a: u16
    b: u16
    c: u16
    bx: u32
    sbx: i32
end

struct LocVar
    name: ptr(String)
    startpc: index
    endpc: index
end

struct UpValDesc
    name: ptr(String)
    instack: u8
    index: u16
end

struct Proto
    gc: GCHeader
    code: ptr(Instr)
    code_len: index
    constants: ptr(Value)
    constants_len: index
    children: ptr(ptr(Proto))
    children_len: index
    lineinfo: ptr(i32)
    lineinfo_len: index
    locvars: ptr(LocVar)
    locvars_len: index
    upvals: ptr(UpValDesc)
    upvals_len: index
    source: ptr(String)
    linedefined: i32
    lastlinedefined: i32
    numparams: u8
    is_vararg: u8
    maxstack: u16
end
```

Design choice: runtime instructions are decoded products, not packed C bitfields. A loader may read packed bytecode and decode once.

### 5.6 Closures and upvalues

```moonlift
struct UpVal
    gc: GCHeader
    v: ptr(Value)            -- open: points into stack; closed: points to closed
    closed: Value
    stack_index: index       -- valid while open
    next_open: ptr(UpVal)
end

struct LClosure
    gc: GCHeader
    env: ptr(Table)
    proto: ptr(Proto)
    upvals: ptr(ptr(UpVal))
    nupvals: u8
end

struct NativeFunc
    addr: ptr(u8)            -- ABI-specific function pointer
    flags: u32              -- yieldable, fast, continuation-capable
end

struct CClosure
    gc: GCHeader
    env: ptr(Table)
    fn: ptr(NativeFunc)
    upvals: ptr(Value)
    nupvals: u8
end
```

Native functions are sealed ABI boundaries. Internally, VM control remains region-native.

---

## 6. Thread, frame, and dynamic continuation products

### 6.1 Frame

```moonlift
struct Frame
    closure: Value           -- LClosure or CClosure
    base: index              -- first register
    top: index               -- stack limit for this frame
    pc: index                -- next instruction pc for Lua frames
    wanted: i32              -- requested result count; -1 = multret
    tailcalls: i32

    resume_mode: u16
    resume_a: u16
    resume_b: u16
    resume_c: u16
    resume_pc: index
    resume_base: index
    resume_value: Value
end
```

`resume_*` fields encode dynamic continuation payload. Examples:

```text
RESUME_GETTABLE_MM:
    resume_a = destination register
    resume_pc = instruction pc to continue after

RESUME_BINOP_MM:
    resume_a = destination register
    resume_b = metamethod event

RESUME_EQ_MM / LT / LE:
    resume_a = expected boolean / branch sense
    resume_pc = jump target or next-pc encoding

RESUME_CONCAT_MM:
    resume_a/resume_b/resume_c = concat range state
```

### 6.2 Protected frame

```moonlift
struct ProtectedFrame
    frame_index: index
    stack_top: index
    handler_slot: index
    errfunc_slot: index
    previous: ptr(ProtectedFrame)
end
```

Protected frames replace `setjmp` records.

### 6.3 Lua thread

```moonlift
struct LuaThread
    gc: GCHeader
    status: u8

    stack: ptr(Value)
    stack_size: index
    top: index

    frames: ptr(Frame)
    frame_count: index
    frame_cap: index

    open_upvals: ptr(UpVal)
    protected_top: ptr(ProtectedFrame)

    global: ptr(GlobalState)
    err_value: Value

    hookmask: u8
    allowhook: u8
    hookcount: i32
    basehookcount: i32
    hook: Value              -- Lua or native hook callable
end
```

### 6.4 Global state

```moonlift
struct StringTable
    buckets: ptr(ptr(String))
    bucket_count: index
    nuse: index
end

struct GlobalState
    allocator: ptr(Allocator)
    registry: Value
    mainthread: ptr(LuaThread)

    allgc: ptr(GCHeader)
    gray: ptr(GCHeader)
    grayagain: ptr(GCHeader)
    weak: ptr(GCHeader)
    tmudata: ptr(GCHeader)

    string_table: ptr(StringTable)
    tmname: ptr(ptr(String))

    currentwhite: u8
    gcstate: u8
    sweep_cursor: ptr(ptr(GCHeader))
    totalbytes: index
    estimate: index
    threshold: index
    gcdebt: index
    gcpause: i32
    gcstepmul: i32

    panic: Value             -- native/Lua panic handler
end
```

---

## 7. API and debug products

```moonlift
struct ApiIndex
    absolute: index
end

struct DebugInfo
    event: i32
    name: ptr(String)
    namewhat: ptr(String)
    what: ptr(String)
    source: ptr(String)
    currentline: i32
    nups: i32
    frame_index: index
end
```

The public C-like API uses sealed functions that translate stack-index conventions into typed internal products and protocols.

---

# Part II — Continuation protocols

Moonlift does not need named protocol types to express these, but the design names them to make the VM readable. Each protocol below corresponds to one or more region signatures in Part III.

---

## 8. Boundary protocols

### 8.1 VM execution result

```text
VmResult =
    ok(nres)
  | yielded(nres)
  | runtime_error(code)
  | oom()
```

### 8.2 Protected execution

```text
ProtectedResult =
    success(nres)
  | failure(err)
  | oom()
```

### 8.3 Allocation

```text
AllocResult =
    ok(ptr)
  | step_required()
  | oom()
```

---

## 9. Value protocols

```text
ValueAsNumber = number(x) | not_number()
ValueAsString = string(s) | not_string()
ValueAsTable  = table(t)  | not_table()
ValueAsFunc   = lua(cl) | native(cl) | not_function()
Truth         = truthy() | falsey()
ComparableEq = primitive(result) | metamethod(mm) | not_comparable()
ComparableOrd = primitive(result) | metamethod(mm) | type_error()
```

---

## 10. Table protocols

```text
TableGet =
    hit(value)
  | miss_no_meta()
  | metamethod(mm)
  | error(code)

TableSet =
    stored()
  | metamethod(mm)
  | error(code)
  | oom()

RawSlot =
    found(slot)
  | empty(slot)
  | absent()
  | resize_required()

NextResult =
    pair(key, value)
  | done()
  | invalid_key()
```

---

## 11. Call protocols

```text
PrepareCall =
    enter_lua(child_frame)
  | enter_native(native_closure)
  | returned(nres)
  | yielded(nres)
  | error(code)
  | oom()

ReturnDispatch =
    resume_parent(parent_frame, pc, base, top)
  | finished(nres)
  | yielded(nres)
  | error(code)
  | oom()

NativeCall =
    returned(nres)
  | yielded(nres)
  | error(code)
  | oom()
```

---

## 12. Metamethod protocols

```text
MetamethodLookup = found(mm) | missing()
BinopDispatch = fast_number(x, y) | call_mm(mm) | type_error()
UnopDispatch = fast_number(x) | call_mm(mm) | type_error()
IndexDispatch = value(v) | call_mm(mm, self, key) | type_error() | loop_error()
NewIndexDispatch = stored() | call_mm(mm, self, key, value) | type_error() | loop_error() | oom()
CallDispatch = callable(func) | call_mm(mm) | type_error()
```

---

## 13. Error protocols

```text
RaiseError =
    caught(frame, protected_frame)
  | uncaught(code)

ErrorObject =
    built(err)
  | oom()
```

---

## 14. GC protocols

```text
BarrierResult = clean() | barriered()
MarkResult = done() | pushed_gray() | oom()
SweepResult = kept(obj) | freed() | done()
GCStepResult = done() | oom()
```

---

## 15. Opcode protocol

All opcode handlers share a canonical continuation shape, specialized by Lua generation.

```text
OpcodeResult =
    next(frame, pc, base, top)
  | jump(frame, pc, base, top)
  | enter_lua(child_frame)
  | enter_native(native_closure)
  | returned(nres)
  | yielded(nres)
  | error(code)
  | oom()
```

Handlers only expose continuations they can actually use. Generated signatures should remain specific, not one giant universal protocol.

---

# Part III — Region signatures

This section is the VM map. Bodies are intentionally omitted. Given these products and signatures, the complete system shape is known.

---

## 16. VM entry and loop regions

```moonlift
region vm_resume(
    L: ptr(LuaThread),
    nargs: i32;

    ok: cont(nres: i32),
    yielded: cont(nres: i32),
    runtime_error: cont(code: i32),
    oom: cont())
```

```moonlift
region vm_loop(
    L: ptr(LuaThread);

    finished: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region commit_vm_state(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    top: index;

    done: cont())
```

```moonlift
region dispatch_instruction(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index;

    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

`dispatch_instruction` is generated from the opcode table. It loads `Instr`, switches on `op`, and emits the corresponding opcode region.

---

## 17. Value regions

```moonlift
region value_truth(v: Value;
    truthy: cont(),
    falsey: cont())
```

```moonlift
region value_as_number(v: Value;
    number: cont(x: f64),
    not_number: cont())
```

```moonlift
region value_to_number(v: Value;
    number: cont(x: f64),
    not_number: cont())
```

`value_as_number` accepts only actual number values. `value_to_number` implements Lua coercion from numeric strings where the selected Lua version requires it.

```moonlift
region value_as_string(v: Value;
    string: cont(s: ptr(String)),
    not_string: cont())
```

```moonlift
region value_to_string(
    L: ptr(LuaThread),
    v: Value;

    string: cont(s: ptr(String)),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region value_as_table(v: Value;
    table: cont(t: ptr(Table)),
    not_table: cont())
```

```moonlift
region value_as_function(v: Value;
    lua: cont(cl: ptr(LClosure)),
    native: cont(cl: ptr(CClosure)),
    not_function: cont())
```

```moonlift
region value_raw_equal(
    a: Value,
    b: Value;

    equal: cont(),
    not_equal: cont())
```

```moonlift
region value_equal(
    L: ptr(LuaThread),
    a: Value,
    b: Value;

    result: cont(is_equal: bool),
    call_mm: cont(mm: Value),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region value_less_than(
    L: ptr(LuaThread),
    a: Value,
    b: Value;

    result: cont(is_lt: bool),
    call_mm: cont(mm: Value),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region value_less_equal(
    L: ptr(LuaThread),
    a: Value,
    b: Value;

    result: cont(is_le: bool),
    call_mm: cont(mm: Value, fallback_lt: bool),
    error: cont(code: i32),
    oom: cont())
```

---

## 18. Stack and frame regions

```moonlift
region stack_check(
    L: ptr(LuaThread),
    needed_top: index;

    ok: cont(),
    grown: cont(),
    overflow: cont(),
    oom: cont())
```

```moonlift
region frame_push(
    L: ptr(LuaThread),
    closure: Value,
    base: index,
    top: index,
    wanted: i32,
    resume_mode: u16;

    ok: cont(frame: ptr(Frame)),
    overflow: cont(),
    oom: cont())
```

```moonlift
region frame_pop(
    L: ptr(LuaThread);

    parent: cont(frame: ptr(Frame)),
    empty: cont())
```

```moonlift
region adjust_results(
    L: ptr(LuaThread),
    first_result: index,
    nactual: i32,
    wanted: i32,
    dst: index;

    done: cont(nplaced: i32),
    oom: cont())
```

```moonlift
region adjust_varargs(
    L: ptr(LuaThread),
    cl: ptr(LClosure),
    func_slot: index,
    nargs: i32;

    ok: cont(base: index),
    oom: cont())
```

---

## 19. Call and return regions

```moonlift
region prepare_call(
    L: ptr(LuaThread),
    func_slot: index,
    nargs: i32,
    wanted: i32,
    resume_mode: u16;

    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region try_call_metamethod(
    L: ptr(LuaThread),
    func_slot: index;

    replaced: cont(),
    not_callable: cont(),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region call_native(
    L: ptr(LuaThread),
    cl: ptr(CClosure),
    nargs: i32,
    wanted: i32;

    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region return_from_lua(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    first_result: index,
    nres: i32;

    resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    finished: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region handle_return_mode(
    L: ptr(LuaThread),
    parent: ptr(Frame),
    first_result: index,
    nres: i32;

    normal: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    resume_gettable_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    resume_settable_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    resume_binop_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    resume_unop_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    resume_compare_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    resume_concat_mm: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    resume_tforloop: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    pcall_success: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    pcall_failure: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    finished: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

The many continuations are intentional. Each dynamic return target is a real VM state.

---

## 20. Upvalue regions

```moonlift
region find_upvalue(
    L: ptr(LuaThread),
    stack_index: index;

    found: cont(uv: ptr(UpVal)),
    created: cont(uv: ptr(UpVal)),
    oom: cont())
```

```moonlift
region close_upvalues(
    L: ptr(LuaThread),
    from_stack_index: index;

    done: cont(),
    oom: cont())
```

```moonlift
region make_lclosure(
    L: ptr(LuaThread),
    proto: ptr(Proto),
    env: ptr(Table),
    parent: ptr(LClosure),
    base: index;

    ok: cont(cl: ptr(LClosure)),
    oom: cont())
```

---

## 21. Table regions

```moonlift
region table_raw_get(
    t: ptr(Table),
    key: Value;

    hit: cont(value: Value),
    miss: cont())
```

```moonlift
region table_raw_set(
    L: ptr(LuaThread),
    t: ptr(Table),
    key: Value,
    value: Value;

    stored: cont(),
    resized: cont(),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region table_get(
    L: ptr(LuaThread),
    obj: Value,
    key: Value;

    value: cont(v: Value),
    call_mm: cont(mm: Value, self: Value, key: Value),
    type_error: cont(),
    loop_error: cont(),
    oom: cont())
```

```moonlift
region table_set(
    L: ptr(LuaThread),
    obj: Value,
    key: Value,
    value: Value;

    stored: cont(),
    call_mm: cont(mm: Value, self: Value, key: Value, value: Value),
    type_error: cont(),
    loop_error: cont(),
    oom: cont())
```

```moonlift
region table_next(
    L: ptr(LuaThread),
    t: ptr(Table),
    key: Value;

    pair: cont(key: Value, value: Value),
    done: cont(),
    invalid_key: cont())
```

```moonlift
region table_resize(
    L: ptr(LuaThread),
    t: ptr(Table),
    new_array_len: index,
    new_hash_power: u32;

    done: cont(),
    oom: cont())
```

---

## 22. Metamethod regions

```moonlift
region get_metamethod(
    G: ptr(GlobalState),
    obj: Value,
    event: u8;

    found: cont(mm: Value),
    missing: cont())
```

```moonlift
region get_table_metamethod(
    G: ptr(GlobalState),
    t: ptr(Table),
    event: u8;

    found: cont(mm: Value),
    missing: cont())
```

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

```moonlift
region unop_dispatch(
    L: ptr(LuaThread),
    v: Value,
    event: u8;

    fast_number: cont(x: f64),
    call_mm: cont(mm: Value),
    type_error: cont())
```

```moonlift
region prepare_metamethod_call(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index,
    mm: Value,
    nargs: i32,
    wanted: i32,
    resume_mode: u16;

    prepared: cont(),
    error: cont(code: i32),
    oom: cont())
```

This one region handles `__index`, `__newindex`, arithmetic, comparisons, `__call`, `__len`, and `__concat` by varying `resume_mode` and stack argument preparation.

---

## 23. String regions

```moonlift
region string_hash(
    bytes: ptr(u8),
    len: index,
    seed: u32;

    done: cont(hash: u32))
```

```moonlift
region string_intern(
    L: ptr(LuaThread),
    bytes: ptr(u8),
    len: index;

    found: cont(s: ptr(String)),
    created: cont(s: ptr(String)),
    oom: cont())
```

```moonlift
region string_concat_range(
    L: ptr(LuaThread),
    first: index,
    last: index;

    done: cont(s: ptr(String)),
    call_mm: cont(mm: Value),
    error: cont(code: i32),
    oom: cont())
```

---

## 24. Error and protected-call regions

```moonlift
region build_error_object(
    L: ptr(LuaThread),
    code: i32,
    culprit: Value;

    built: cont(err: Value),
    oom: cont())
```

```moonlift
region raise_error(
    L: ptr(LuaThread),
    err: Value;

    caught: cont(frame: ptr(Frame), handler: ptr(ProtectedFrame)),
    uncaught: cont(code: i32))
```

```moonlift
region enter_protected(
    L: ptr(LuaThread),
    frame_index: index,
    stack_top: index,
    handler_slot: index,
    errfunc_slot: index;

    done: cont(pf: ptr(ProtectedFrame)),
    oom: cont())
```

```moonlift
region leave_protected(
    L: ptr(LuaThread),
    pf: ptr(ProtectedFrame);

    done: cont())
```

```moonlift
region protected_call(
    L: ptr(LuaThread),
    func_slot: index,
    nargs: i32,
    wanted: i32,
    errfunc_slot: index;

    success: cont(nres: i32),
    failure: cont(err: Value),
    oom: cont())
```

---

## 25. Coroutine regions

```moonlift
region coroutine_resume(
    caller: ptr(LuaThread),
    target: ptr(LuaThread),
    nargs: i32;

    ok: cont(nres: i32),
    yielded: cont(nres: i32),
    dead: cont(),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region coroutine_yield(
    L: ptr(LuaThread),
    nres: i32;

    yielded: cont(nres: i32),
    not_yieldable: cont(),
    error: cont(code: i32))
```

Coroutine yield is not an exception. It is a named VM exit.

---

## 26. GC and allocation regions

```moonlift
region alloc_object(
    G: ptr(GlobalState),
    size: index,
    tt: u8;

    ok: cont(obj: ptr(GCHeader)),
    step_required: cont(),
    oom: cont())
```

```moonlift
region gc_check(
    L: ptr(LuaThread);

    ok: cont(),
    step: cont(),
    oom: cont())
```

```moonlift
region gc_step(
    L: ptr(LuaThread);

    done: cont(),
    oom: cont())
```

```moonlift
region mark_value(
    G: ptr(GlobalState),
    v: Value;

    done: cont(),
    pushed_gray: cont(),
    oom: cont())
```

```moonlift
region mark_object(
    G: ptr(GlobalState),
    obj: ptr(GCHeader);

    done: cont(),
    pushed_gray: cont(),
    oom: cont())
```

```moonlift
region propagate_gray(
    G: ptr(GlobalState);

    done: cont(),
    empty: cont(),
    oom: cont())
```

```moonlift
region sweep_step(
    G: ptr(GlobalState),
    limit: index;

    done: cont(),
    more: cont(),
    oom: cont())
```

```moonlift
region write_barrier(
    G: ptr(GlobalState),
    parent: ptr(GCHeader),
    child: Value;

    clean: cont(),
    barriered: cont())
```

```moonlift
region write_barrier_back(
    G: ptr(GlobalState),
    parent: ptr(GCHeader);

    done: cont())
```

---

## 27. API boundary regions and sealed functions

Internal stack-index decoding:

```moonlift
region api_index_to_addr(
    L: ptr(LuaThread),
    idx: i32;

    valid: cont(slot: index),
    pseudo_global: cont(),
    pseudo_registry: cont(),
    pseudo_upvalue: cont(n: i32),
    invalid: cont())
```

Sealed functions expose compatibility:

```moonlift
func lua_type_api(L: ptr(LuaThread), idx: i32) -> i32
func lua_settop_api(L: ptr(LuaThread), idx: i32) -> void
func lua_pushvalue_api(L: ptr(LuaThread), idx: i32) -> void
func lua_tolstring_api(L: ptr(LuaThread), idx: i32, len_out: ptr(index)) -> ptr(u8)
func lua_gettable_api(L: ptr(LuaThread), idx: i32) -> i32
func lua_settable_api(L: ptr(LuaThread), idx: i32) -> void
func lua_call_api(L: ptr(LuaThread), nargs: i32, nresults: i32) -> void
func lua_pcall_api(L: ptr(LuaThread), nargs: i32, nresults: i32, errfunc: i32) -> i32
```

The API functions are the only place where Lua C API conventions are allowed. Internals use regions.

---

# Part IV — Opcode family

The opcode set follows Lua 5.1 semantics.

```text
MOVE
LOADK
LOADBOOL
LOADNIL
GETUPVAL
GETGLOBAL
GETTABLE
SETGLOBAL
SETUPVAL
SETTABLE
NEWTABLE
SELF
ADD
SUB
MUL
DIV
MOD
POW
UNM
NOT
LEN
CONCAT
JMP
EQ
LT
LE
TEST
TESTSET
CALL
TAILCALL
RETURN
FORLOOP
FORPREP
TFORLOOP
SETLIST
CLOSE
CLOSURE
VARARG
```

Each opcode has a generated region. Representative signatures:

```moonlift
region op_move(...; next: cont(...))
region op_loadk(...; next: cont(...))
region op_loadbool(...; next: cont(...))
region op_loadnil(...; next: cont(...))
```

```moonlift
region op_gettable(...;
    next: cont(...),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region op_settable(...;
    next: cont(...),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region op_arith(...;
    next: cont(...),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    error: cont(code: i32),
    oom: cont())
```

`op_arith` is generated once per arithmetic event or generated as distinct concrete handlers:

```text
op_add, op_sub, op_mul, op_div, op_mod, op_pow
```

Concrete generated handlers are preferred because the metamethod event becomes a constant.

```moonlift
region op_call(...;
    next: cont(...),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region op_return(...;
    resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    finished: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

```moonlift
region op_closure(...;
    next: cont(...),
    error: cont(code: i32),
    oom: cont())
```

Lua generation supplies the repeated boilerplate and keeps handlers monomorphic.

---

# Part V — Quickening and specialization

Quickening is part of the final design, not an afterthought. The baseline opcode set remains semantically complete. Quickened opcodes are cache-bearing refinements with explicit invalidation protocols.

## 28. Quickened products

```moonlift
struct InlineCache
    epoch: u32
    aux0: u32
    aux1: u32
    key: Value
    value: Value
end

struct QuickInstr
    instr: Instr
    cache: InlineCache
end
```

`Proto.code` may point to `Instr[]` or `QuickInstr[]` depending on build configuration. The VM design supports both by generating the fetch/decode layer.

## 29. Quickened opcode families

```text
GETTAB_ARRAY
GETTAB_STR_SLOT
GETTAB_HASH_SLOT
GETTAB_META_KNOWN
SETTAB_ARRAY
SETTAB_STR_SLOT
ADD_NUM
SUB_NUM
MUL_NUM
DIV_NUM
EQ_RAW
CALL_LUA_FIXED
CALL_NATIVE_FIXED
RETURN_FIXED
JMP_SHORT
LOADK_FAST
```

Each quickened handler has explicit exits:

```text
hit -> next
stale -> deopt_or_repatch
miss -> generic_handler
error -> error
oom -> oom
```

## 30. Quickening protocols

```moonlift
region probe_gettable_cache(
    t: ptr(Table),
    key: Value,
    cache: ptr(InlineCache);

    hit: cont(slot: index),
    stale: cont(),
    miss: cont())
```

```moonlift
region quicken_instruction(
    L: ptr(LuaThread),
    proto: ptr(Proto),
    pc: index,
    observation_kind: u32,
    obj: Value,
    key: Value;

    patched: cont(),
    keep_generic: cont(),
    oom: cont())
```

```moonlift
region deopt_instruction(
    proto: ptr(Proto),
    pc: index;

    done: cont())
```

Invalidation is structural:

- table resize increments `shape_epoch`
- metatable replacement increments `shape_epoch`
- metamethod mutation clears negative cache flags and increments relevant epochs
- string interning preserves pointer identity

Quickened assumptions are never implicit. Every assumption has an epoch or guard.

---

# Part VI — Composition map

The following control tree is the VM architecture.

```text
vm_resume
  -> prepare initial frame / argument state
  -> vm_loop
      -> dispatch_instruction
          -> op_move / op_loadk / ...
          -> op_gettable
              -> table_get
                  -> table_raw_get
                  -> get_metamethod
              -> prepare_metamethod_call
              -> prepare_call
          -> op_settable
              -> table_set
              -> write_barrier
              -> prepare_metamethod_call
          -> op_arith
              -> binop_dispatch
              -> prepare_metamethod_call
          -> op_call
              -> prepare_call
                  -> try_call_metamethod
                  -> frame_push
                  -> call_native
          -> op_return
              -> close_upvalues
              -> return_from_lua
                  -> handle_return_mode
          -> op_closure
              -> make_lclosure
              -> find_upvalue
          -> op_forprep / op_forloop
              -> value_to_number
          -> op_tforloop
              -> prepare_call with RESUME_TFORLOOP_CALL
      -> raise_error
          -> unwind frames
          -> protected boundary or uncaught
      -> gc_check / gc_step at safepoints
```

This map should be inspectable in source with grep:

```bash
rg '^region ' lua_vm
rg '\bemit ' lua_vm
rg '^block ' lua_vm
rg '\bjump ' lua_vm
```

The control graph is the documentation.

---

# Part VII — Invariants

## 31. Stack invariants

- `L.top <= L.stack_size`.
- Every active frame has `base <= top <= frame.top`.
- Open upvalues point to stack indices in active or closing frames.
- Closing a frame closes every upvalue with `stack_index >= frame.base` when required by `RETURN`, `CLOSE`, or scope exit.

## 32. Frame invariants

- `frame.pc` is committed before any operation that can re-enter, yield, call native code, allocate with GC, or raise.
- A frame with `resume_mode != RESUME_NORMAL` has valid `resume_*` payload according to its mode.
- `wanted == -1` means multret; otherwise exact result adjustment occurs at return dispatch.

## 33. Table invariants

- Nil keys are rejected.
- NaN numeric keys are rejected.
- Nil values delete entries semantically.
- Array and hash parts may be resized only through `table_resize`.
- Any structural mutation updates `shape_epoch`.
- Any write of a collectable value into a black table emits a barrier.

## 34. GC invariants

- All collectable objects are linked in `GlobalState.allgc` or a generation-specific equivalent.
- No black object points to a white object after a barriered write.
- Threads, stacks, frames, open upvalues, registry, globals, metatables, and temporary safepoint roots are marked.
- Native calls expose roots before entering foreign code.

## 35. Error invariants

- Every runtime error goes through `raise_error`.
- Protected calls are represented by `ProtectedFrame`, not host stack unwinding.
- Uncaught errors set `L.err_value` and exit through `runtime_error`.

## 36. API invariants

- API functions seal Lua C conventions.
- Internal regions do not use pseudo-index conventions directly.
- API stack mutation checks stack capacity through `stack_check`.

---

# Part VIII — Lua generation layer

Lua generates repetitive monomorphic structure.

## 37. Opcode specification

A Lua table defines:

```lua
return {
  { name = "MOVE",     mode = "ABC",  handler = "op_move",     effects = {"next"} },
  { name = "LOADK",    mode = "ABx",  handler = "op_loadk",    effects = {"next"} },
  { name = "GETTABLE", mode = "ABC",  handler = "op_gettable", effects = {"next", "call", "error", "oom"} },
  -- ...
}
```

From this, Lua generates:

- opcode constants
- opcode names
- instruction mode tables
- dispatch switch arms
- handler declarations
- quickened variants
- disassembler metadata
- bytecode validator metadata

## 38. Metamethod factories

Arithmetic handlers are generated from:

```lua
local arith_ops = {
  { name = "add", op = "ADD", tm = "TM_ADD", expr = "x + y" },
  { name = "sub", op = "SUB", tm = "TM_SUB", expr = "x - y" },
  -- ...
}
```

Each generated handler is concrete. The metamethod event is not a runtime parameter in hot code.

## 39. Resume-mode factories

Return-mode dispatch is generated from the `RESUME_*` registry. Each mode declares:

```text
mode name
payload fields used
result arity requirements
resume block signature
```

This prevents `handle_return_mode` from becoming a hand-maintained status switch.

---

# Part IX — Compiler / loader boundary

The VM consumes `Proto`. The compiler layer must guarantee:

```text
Proto.code instructions are valid
register indices are within maxstack
constant indices are valid
child proto indices are valid
upvalue descriptors are valid
jumps target valid pcs
lineinfo length matches or is explicitly absent
```

Region:

```moonlift
region validate_proto(
    L: ptr(LuaThread),
    p: ptr(Proto);

    ok: cont(),
    invalid: cont(code: i32),
    oom: cont())
```

`validate_proto` is the VM trust boundary. The interpreter loop may assume validated bytecode.

---

# Part X — External boundaries

## 40. Native function ABI

A native function is called through a sealed ABI. It receives `LuaThread*` and returns a conventional status. That status is immediately translated into a protocol by `call_native`.

```text
native return >= 0      returned with n results
native return YIELD     yielded
native return ERROR     error object on stack
native return OOM       oom
```

Only `call_native` interprets this convention.

## 41. Allocator ABI

Allocator calls are external functions. Allocation policy is explicit in `Allocator` and `alloc_object`. No region allocates by calling a raw allocator directly.

## 42. Panic and hooks

Hooks and panic handlers are dynamic Lua/native calls represented with ordinary `Value` call paths. Hook invocation is a safepoint:

```moonlift
region maybe_call_hook(
    L: ptr(LuaThread),
    event: i32,
    frame: ptr(Frame),
    pc: index,
    top: index;

    done: cont(),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
```

---

# Part XI — Implementation ordering without design compromise

The design above is complete. Construction can be ordered without changing the architecture:

1. Products and constants.
2. Value and stack regions.
3. Frame/call/return engine.
4. Opcode generator and base handlers.
5. Tables and strings.
6. Upvalues and closures.
7. Metamethods.
8. Protected calls and coroutines.
9. GC.
10. API sealing.
11. Quickening.

This is an implementation order only. No step is a reduced design.

---

# 43. Summary

The final VM is a PUC-compatible Lua register interpreter re-authored in Moonlift's explicit style.

The data tree is:

```text
Value
GCHeader + heap objects
String, Table, Proto, Closure, UpVal, UserData
LuaThread, Frame, ProtectedFrame, GlobalState
Instr, InlineCache, DebugInfo
```

The control tree is:

```text
vm_resume
vm_loop
opcode handlers
table get/set
metamethod dispatch
call/return engine
upvalue close/find
protected error engine
coroutine yield/resume
GC allocation/barrier/step
API sealing
quickening/deopt
```

The deepest rule:

> The Lua machine stays a register VM. The C conventions disappear. Every meaningful outcome becomes a continuation, every persistent shape becomes a product, and every dynamic script continuation becomes explicit frame data.

That is the Moonlift Lua interpreter VM.
