# Moonlift Lua Interpreter VM 
Implement a complete PUC-Lua-compatible register-bytecode interpreter VM in Moonlift, following the final type-first design in experiments/lua_interpreter_vm/README.md
**Started**: 2026-05-21 21:13:37
---

## Documenter Output — 2026-05-21 21:15:02

Now I have the complete README and sufficient context. Let me produce the architectural artifact.

---

# Moonlift Lua Interpreter VM — Architectural Decision Record

**Status**: Final — approved for implementation  
**Workflow**: Phase 1 complete (scout → knowledge-builder → approach-proposer → critique → decision)  
**Decision by**: User review, approving the full design from `experiments/lua_interpreter_vm/README.md`  
**Implementation target**: `experiments/lua_interpreter_vm/src/`  

---

## Goal

Implement a complete PUC-Lua-compatible register-bytecode interpreter VM in Moonlift, following the type-first design specified in `experiments/lua_interpreter_vm/README.md`. The VM consumes validated `Proto` values and produces Lua 5.1–equivalent execution semantics through Moonlift's explicit region-graph control model. Every meaningful runtime outcome is a named continuation; every persistent shape is a typed product; every dynamic script continuation is explicit frame data. No C conventions (integer status returns, `longjmp`, out-parameters, hidden allocation paths) survive into the Moonlift implementation.

---

## Incentives

The Moonlift project currently has only a Cranelift backend (JIT + object emission). There is no interpreted fallback. This creates several concrete problems:

1. **No embedded or sandboxed execution**: LuaJIT's FFI-based compilation pipeline cannot run in environments that forbid `mmap(PROT_EXEC)` — embedded systems, iOS, WebAssembly, or restricted sandboxes. An interpreter removes this constraint.

2. **No incremental compilation during execution**: The Cranelift pipeline compiles whole `Proto` values to native code. There is no facility to run partially-compiled or small scripts without the full compilation overhead.

3. **No self-hosted bootstrapping path**: Moonlift's metaprogramming layer runs on LuaJIT. To eventually run Moonlift's own compiler on Moonlift, an interpreter is the necessary first step — native code generation from Moonlift to Moonlift requires an intermediate runtime that is itself Moonlift code.

4. **Pedagogical and tooling gap**: The explicit region-graph style is Moonlift's core architectural claim. A complete interpreter written in Moonlift (not C, not Lua with hybrid state) is the best possible demonstration of the pattern and the strongest test case for the compiler's region/block/jump/emit lowering.

The VM removes the LuaJIT runtime dependency for interpreted execution, provides a target for Moonlift-to-Moonlift compilation, and serves as the canonical reference implementation of the explicit-control architecture.

---

## Current State

The design exists as `experiments/lua_interpreter_vm/README.md` — a self-contained, 2003-line architectural specification. No implementation code exists yet.

### What the README specifies

The document defines a complete register-bytecode VM in eleven parts:

| Part | Content |
|------|---------|
| I | Data type tree — all storage products: Value, GCHeader, String, Table, Proto, Instr, UpVal, LClosure, CClosure, Frame, ProtectedFrame, LuaThread, GlobalState, StringTable, InlineCache, DebugInfo, ApiIndex |
| II | Continuation protocols — VmResult, ProtectedResult, AllocResult, ValueAsNumber/Table/Func, Truth, TableGet/Set/RawSlot/Next, PrepareCall, ReturnDispatch, MetamethodLookup, BinopDispatch, Error/Raise/Barrier protocols |
| III | Region signatures — all 60+ region signatures with typed continuation lists: vm_resume, vm_loop, commit_vm_state, dispatch_instruction, value_truth, value_as_number, value_to_number, value_as_string, value_as_table, value_as_function, value_raw_equal, value_equal, value_less_than, value_less_equal, stack_check, frame_push, frame_pop, adjust_results, adjust_varargs, prepare_call, try_call_metamethod, call_native, return_from_lua, handle_return_mode, find_upvalue, close_upvalues, make_lclosure, table_raw_get, table_raw_set, table_get, table_set, table_next, table_resize, get_metamethod, get_table_metamethod, binop_dispatch, unop_dispatch, prepare_metamethod_call, string_hash, string_intern, string_concat_range, build_error_object, raise_error, enter_protected, leave_protected, protected_call, coroutine_resume, coroutine_yield, alloc_object, gc_check, gc_step, mark_value, mark_object, propagate_gray, sweep_step, write_barrier, write_barrier_back, api_index_to_addr, validate_proto, maybe_call_hook, probe_gettable_cache, quicken_instruction, deopt_instruction |
| IV | Opcode family — 31 Lua 5.1 opcodes with generated region signatures per opcode, including representative signatures for GETTABLE, SETTABLE, arithmetic, CALL, RETURN, CLOSURE |
| V | Quickening and specialization — InlineCache struct, QuickInstr struct, 15 quickened opcode families, quickening protocols (probe_gettable_cache, quicken_instruction, deopt_instruction), structural epoch-based invalidation |
| VI | Composition map — the control tree showing how regions nest (vm_resume → vm_loop → dispatch_instruction → op_gettable → table_get → table_raw_get / get_metamethod → prepare_metamethod_call → prepare_call) |
| VII | Invariants — 6 categories (stack, frame, table, GC, error, API) with specific, testable assertions |
| VIII | Lua generation layer — opcode specification tables, metamethod factories, resume-mode factories |
| IX | Compiler/loader boundary — validate_proto trust boundary |
| X | External boundaries — native function ABI (return ≥ 0 / YIELD / ERROR / OOM), allocator ABI, hooks and panic |
| XI | Implementation ordering — 11 steps (products → value/stack → frame/call/return → opcode generator → tables/strings → upvalues/closures → metamethods → protected calls/coroutines → GC → API sealing → quickening) |

### Design decisions embedded in the current state

- **Value is a flat 16-byte product** (tag + aux + bits), not a union. Collectable objects carry pointer bits; the GCHeader at the pointed-to object has a matching `tt` field.
- **Boolean is two tags** (TAG_FALSE, TAG_TRUE) instead of TAG_BOOL + payload, so falsiness is one tag compare.
- **Frame carries resume payload** inline — resume_mode + resume_a/b/c/pc/base/value — rather than a separate continuation stack. This keeps the frame as the single dynamic continuation record.
- **Opcode instructions are decoded products** (Instr with named fields), not packed C bitfields. A loader may read packed bytecode and decode once.
- **All errors go through raise_error** — no longjmp, no C stack unwinding. ProtectedFrame replaces setjmp records.
- **Quickening uses structural epochs** — table.shape_epoch increments on resize/metatable change. Quickened opcodes guard on epoch. No invalidation list, no global version counter.
- **The control tree is grep-inspectable** — every region, block, jump, and emit is a first-class Moonlift construct.

### Limitations and design tensions in the current state

- The `handle_return_mode` region has 12+ continuations. This is correct (each dynamic return target is a real VM state) but imposes a wide signature on the call/return engine.
- The `dispatch_instruction` region has 8 continuations (next, jump, enter_lua, enter_native, returned, yielded, error, oom). Generated opcode handlers expose only the subset they actually use.
- Partition between "VM internal" and "sealed API" is strict. The API functions (`lua_type_api`, `lua_settop_api`, etc.) are the only places C conventions are allowed.
- GC is incremental (states: pause → propagate → sweep), but allocation can force a full step. The `alloc_object` region exits through `step_required` when GC debt is exceeded.
- Coroutine yield is an explicit VM exit, not an exception. `coroutine_yield` does not go through `raise_error`.

---

## Chosen Target

### Approach

The **full design** from the README is adopted in its entirety. No reduced design, no temporary subset, no "implement the interpreter body only" scope limitation. The decision is to implement all 11 parts in the specified order, producing a complete Moonlift VM that is:

- **PUC-Lua-compatible** at the bytecode level (Lua 5.1 instruction set)
- **Moonlift-native** in control structure (regions, blocks, jumps, emits)
- **API-sealed** at the external boundary (C-like compatible functions wrap internal regions)
- **GC-integrated** (incremental mark-sweep, write barriers, barrier protocols)
- **Quickening-ready** (InlineCache, structural epochs, deopt protocol — even if quickened opcodes ship later)

The approach was chosen because:

1. **The design is already complete**. The README specifies every struct, enum, region signature, protocol, invariant, and composition edge. There is no ambiguity that requires a reduced prototype.
2. **Staging without compromise**. Part XI's implementation order builds the VM layer by layer, but each layer produces final-shape code for its domain. Products built in step 1 are the same products used in step 11. No intermediate designs are discarded.
3. **Moonlift generation handles the boilerplate**. The opcode dispatch switch, handler declarations, instruction mode tables, constant exports, and disassembler metadata are Lua-generated tables. The human writes ~30 hand-tuned opcode region bodies; Lua writes the switch and type declarations.
4. **The critique validated the approach**: The design's explicit protocol boundaries, the frame-as-continuation-record model, the GC as explicit region calls rather than implicit barriers, and the clear separation between interpreter static control (Moonlift regions) and dynamic Lua control (frame resume fields) were all confirmed as sound. The CRC-critique-like analysis found no structural flaws that would require a reduced design.

### Architecture

#### Module organization

The VM source lives at `experiments/lua_interpreter_vm/src/`, organized into the following modules:

```
experiments/lua_interpreter_vm/src/
├── init.lua                  -- Loads all submodules, returns vm table
├── products.lua              -- Part I: Data type tree
├── constants.lua             -- Part I §3: Tags, opcodes, events, modes, statuses
├── regions_value.lua         -- Part III §17: Value protocol regions
├── regions_stack.lua         -- Part III §18: Stack and frame regions
├── regions_call.lua          -- Part III §19: Call/return engine
├── regions_upvalue.lua       -- Part III §20: Upvalue regions
├── regions_table.lua         -- Part III §21: Table access regions
├── regions_metamethod.lua    -- Part III §22: Metamethod regions
├── regions_string.lua        -- Part III §23: String interning/concat regions
├── regions_error.lua         -- Part III §24: Error and protected-call regions
├── regions_coroutine.lua     -- Part III §25: Coroutine yield/resume regions
├── regions_gc.lua            -- Part III §26: GC and allocation regions
├── regions_api.lua           -- Part III §27: API decoding + sealed functions
├── opcodes.lua               -- Part IV: Opcode definitions (Lua generation layer)
├── opcodes_gen.lua           -- Part IV: Generated Lua output (opcode constants, switch, handler decls)
├── op_handlers.lua           -- Part IV: Hand-written opcode handler region bodies
├── vm_loop.lua               -- Part III §16: vm_resume, vm_loop, dispatch_instruction
├── quickening.lua            -- Part V: Quickened opcodes, caches, deopt
├── gc_impl.lua               -- Part VI: GC algorithm implementation (mark, sweep, barrier)
├── validate.lua              -- Part IX: validate_proto trust boundary
└── api.lua                   -- Part X: Sealed C-compatible API functions
```

#### Type tree — complete products

**Value and constants** (`constants.lua`, `products.lua`)

```moonlift
-- ValueTag constants (u32):
--   TAG_NIL, TAG_FALSE, TAG_TRUE, TAG_LIGHTUD, TAG_NUM, TAG_STR,
--   TAG_TABLE, TAG_LCLOSURE, TAG_CCLOSURE, TAG_USERDATA, TAG_THREAD, TAG_PROTO

-- OpCode constants (u16):
--   OP_MOVE, OP_LOADK, OP_LOADBOOL, OP_LOADNIL, OP_GETUPVAL, OP_GETGLOBAL,
--   OP_GETTABLE, OP_SETGLOBAL, OP_SETUPVAL, OP_SETTABLE, OP_NEWTABLE,
--   OP_SELF, OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_POW, OP_UNM,
--   OP_NOT, OP_LEN, OP_CONCAT, OP_JMP, OP_EQ, OP_LT, OP_LE, OP_TEST,
--   OP_TESTSET, OP_CALL, OP_TAILCALL, OP_RETURN, OP_FORLOOP, OP_FORPREP,
--   OP_TFORLOOP, OP_SETLIST, OP_CLOSE, OP_CLOSURE, OP_VARARG

-- TMEvent constants (u8):
--   TM_INDEX .. TM_CALL .. TM_N (numbered 0..TM_N-1)

-- FrameMode constants (u16):
--   RESUME_NORMAL, RESUME_TAILCALL, RESUME_PCALL, RESUME_XPCALL,
--   RESUME_GETTABLE_MM, RESUME_SETTABLE_MM, RESUME_BINOP_MM,
--   RESUME_UNOP_MM, RESUME_LEN_MM, RESUME_CONCAT_MM, RESUME_EQ_MM,
--   RESUME_LT_MM, RESUME_LE_MM, RESUME_CALL_MM, RESUME_TFORLOOP_CALL,
--   RESUME_NATIVE_CONT

-- ThreadStatus constants (u8):
--   THREAD_OK, THREAD_YIELDED, THREAD_RUNTIME_ERROR, THREAD_OOM, THREAD_DEAD

-- ErrorCode constants (i32):
--   ERR_NONE .. ERR_API

-- GCColor, GCState (u8):
--   COLOR_WHITE0, COLOR_WHITE1, COLOR_GRAY, COLOR_BLACK
--   GCSTATE_PAUSE, GCSTATE_PROPAGATE, GCSTATE_SWEEP, GCSTATE_FINALIZE
```

```moonlift
struct Value
    tag: u32
    aux: u32
    bits: u64
end

struct GCHeader
    next: ptr(GCHeader)
    tt: u8
    marked: u8
end

struct String
    gc: GCHeader
    reserved: u8
    hash: u32
    len: index
    bytes: ptr(u8)
end

struct Node
    key: Value
    value: Value
    next: ptr(Node)
end

struct Table
    gc: GCHeader
    flags: u32
    array_len: index
    array: ptr(Value)
    node_mask: u32
    nodes: ptr(Node)
    lastfree: ptr(Node)
    metatable: ptr(Table)
    shape_epoch: u32
end

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

struct UpVal
    gc: GCHeader
    v: ptr(Value)          -- open: points into stack; closed: points to &closed
    closed: Value
    stack_index: index
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
    addr: ptr(u8)
    flags: u32
end

struct CClosure
    gc: GCHeader
    env: ptr(Table)
    fn: ptr(NativeFunc)
    upvals: ptr(Value)
    nupvals: u8
end

struct Frame
    closure: Value            -- LClosure or CClosure
    base: index
    top: index
    pc: index
    wanted: i32               -- -1 = multret
    tailcalls: i32
    resume_mode: u16
    resume_a: u16
    resume_b: u16
    resume_c: u16
    resume_pc: index
    resume_base: index
    resume_value: Value
end

struct ProtectedFrame
    frame_index: index
    stack_top: index
    handler_slot: index
    errfunc_slot: index
    previous: ptr(ProtectedFrame)
end

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
    hook: Value
end

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
    panic: Value
end

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

#### Control flow — region graph

The VM loop is the following region graph. Every edge is an `emit` or `jump`.

```
vm_resume(L, nargs)
  → prepare initial frame and argument state
  → vm_loop(L)

vm_loop(L)
  block loop(frame, pc, base, top)
    → commit_vm_state(L, frame, pc, top)
    → dispatch_instruction(L, frame, pc, base, top)
        → [opcode handler] — each is a region emitting one of:
            next(frame, pc, base, top)
            jump(frame, pc, base, top)
            enter_lua(child_frame)
            enter_native(cl)
            returned(nres)
            yielded(nres)
            error(code)
            oom()

dispatch_instruction in turn:
    → value_of(Instr at pc) → switch(op)
        MOVE:   op_move(L, frame, pc, base, top, a, b; next, ...)
        LOADK:  op_loadk(...)
        GETTABLE: op_gettable(...)
                  → table_get(...) → table_raw_get or get_metamethod
                  → prepare_metamethod_call or prepare_call
        SETTABLE: op_settable(...)
                  → table_set(...) → write_barrier
                  → prepare_metamethod_call
        ADD:     op_add(...) → binop_dispatch(...) → prepare_metamethod_call
        CALL:    op_call(...)
                 → prepare_call(...)
                     → try_call_metamethod
                     → frame_push
                     → call_native
                     → vm_loop (for Lua calls via enter_lua)
        RETURN:  op_return(...)
                 → close_upvalues
                 → return_from_lua
                     → handle_return_mode
                         → (12+ continuations for dynamic return targets)
        CLOSURE: op_closure(...)
                 → make_lclosure(...)
                 → find_upvalue (for each upvalue)
        VARARG:  op_vararg(...)
                 → adjust_varargs
        FORPREP: op_forprep(...) → value_to_number
        FORLOOP: op_forloop(...) → value_to_number
        TFORLOOP: op_tforloop(...) → prepare_call(RESUME_TFORLOOP_CALL)
        ...
```

#### Value protocol implementations

```moonlift
-- value_truth: tag-based dispatch
emit value_truth(v;
    truthy = when_tag,
    falsey = when_nil_or_false)

-- value_as_number: check TAG_NUM
emit value_as_number(v;
    number = have_number,
    not_number = not_a_number)

-- value_to_number: check TAG_NUM, otherwise try string→number coercion
emit value_to_string(L, v;
    string = have_string,
    error = coercion_failed,
    oom = out_of_memory)

-- value_as_table: check TAG_TABLE
emit value_as_table(v;
    table = have_table,
    not_table = not_a_table)

-- value_as_function: check TAG_LCLOSURE or TAG_CCLOSURE
emit value_as_function(v;
    lua = have_lclosure,
    native = have_cclosure,
    not_function = not_a_function)

-- value_raw_equal: pointer comparison for strings, bits comparison for numbers,
-- tag+bits comparison for nil/bool/lightud
emit value_raw_equal(a, b;
    equal = are_equal,
    not_equal = different)

-- value_equal: raw_equal, then fallback to __eq metamethod
emit value_equal(L, a, b;
    result = have_result(bool),
    call_mm = need_eq_mm(mm),
    error = runtime_error,
    oom = out_of_memory)
```

#### Frame/call/return engine

```moonlift
-- stack_check: extends stack if needed_top > stack_size
emit stack_check(L, needed_top;
    ok = have_room,
    grown = did_grow,
    overflow = stack_overflow,
    oom = out_of_memory)

-- frame_push: allocates a new Frame in the frame array
emit frame_push(L, closure, base, top, wanted, resume_mode;
    ok = got_frame(frame),
    overflow = too_many_frames,
    oom = out_of_memory)

-- frame_pop: returns to parent frame context
emit frame_pop(L;
    parent = have_parent(frame),
    empty = no_more_frames)

-- prepare_call: the central call dispatcher
--   Evaluates the function at func_slot
--   Dispatches: LClosure → enter_lua, CClosure → enter_native,
--   Otherwise → try_call_metamethod
emit prepare_call(L, func_slot, nargs, wanted, resume_mode;
    enter_lua = lua_call(child_frame),
    enter_native = native_call(cl),
    returned = call_returned(nres),
    yielded = call_yielded(nres),
    error = call_error(code),
    oom = out_of_memory)

-- return_from_lua: closes upvalues, pops frame, dispatches return
emit return_from_lua(L, frame, first_result, nres;
    resume_parent = have_parent(parent, pc, base, top),
    finished = all_done(nres),
    yielded = yield_occurred(nres),
    error = runtime_error(code),
    oom = out_of_memory)

-- handle_return_mode: the large continuation switch
--   Reads parent.resume_mode and dispatches to the correct resume handler
emit handle_return_mode(L, parent, first_result, nres;
    normal = cont(parent, pc, base, top),
    resume_gettable_mm = cont(parent, pc, base, top),
    resume_settable_mm = cont(parent, pc, base, top),
    resume_binop_mm = cont(parent, pc, base, top),
    resume_unop_mm = cont(parent, pc, base, top),
    resume_compare_mm = cont(parent, pc, base, top),
    resume_concat_mm = cont(parent, pc, base, top),
    resume_tforloop = cont(parent, pc, base, top),
    pcall_success = cont(parent, pc, base, top),
    pcall_failure = cont(parent, pc, base, top),
    finished = cont(nres),
    yielded = cont(nres),
    error = cont(code),
    oom = cont())
```

#### Table access chains

```moonlift
-- table_raw_get: direct array or hash lookup
--   If key is integer in [1, array_len], probe array part
--   Else hash the key and probe the node chain
emit table_raw_get(t, key;
    hit = have_value(value),
    miss = not_found)

-- table_raw_set: direct array or hash store
--   Updates the key or allocates a new node
--   Returns resized if the table needed to grow
emit table_raw_set(L, t, key, value;
    stored = did_store,
    resized = resized_table,
    error = runtime_error,
    oom = out_of_memory)

-- table_get: raw_get → miss → get_metamethod(TM_INDEX)
emit table_get(L, obj, key;
    value = have_value(v),
    call_mm = need_index_mm(mm, self, key),
    type_error = not_a_table,
    loop_error = metamethod_loop,
    oom = out_of_memory)

-- table_set: raw_set → miss → get_metamethod(TM_NEWINDEX)
emit table_set(L, obj, key, value;
    stored = did_store,
    call_mm = need_newindex_mm(mm, self, key, value),
    type_error = not_a_table,
    loop_error = metamethod_loop,
    oom = out_of_memory)
```

#### Error engine

```moonlift
-- raise_error: error dispatch
--   Unwind frames looking for a ProtectedFrame
--   If found: jump to handler with caught continuation
--   If not found: exit through uncaught
emit raise_error(L, err;
    caught = have_handler(frame, pf),
    uncaught = fatal_error(code))

-- protected_call: the pcall/xpcall implementation
--   push a ProtectedFrame with handler/errfunc slots
--   call prepare_call
--   on error: raise_error → caught → adjust results for protection
emit protected_call(L, func_slot, nargs, wanted, errfunc_slot;
    success = call_succeeded(nres),
    failure = call_failed(err),
    oom = out_of_memory)
```

#### GC protocol chain

```moonlift
-- alloc_object: attempt allocation
--   If current GC debt exceeds threshold, exit through step_required
--   Otherwise allocate and link into allgc
emit alloc_object(G, size, tt;
    ok = have_object(obj),
    step_required = need_to_gc,
    oom = out_of_memory)

-- When step_required is returned, the caller loops through gc_step:
emit gc_step(L;
    done = gc_completed,
    oom = out_of_memory)

-- gc_step does one atomic step of:
--   GCSTATE_PAUSE: mark all roots → enter propagate
--   GCSTATE_PROPAGATE: pop from gray list, mark children → propagate_gray
--   GCSTATE_SWEEP: sweep objects → sweep_step
--   GCSTATE_FINALIZE: finalize userdata

-- write_barrier: called after every collectable write into a black container
emit write_barrier(G, parent, child;
    clean = no_action_needed,
    barriered = pushed_to_gray)
```

### Tradeoffs acknowledged

1. **Wide `handle_return_mode` continuation list (12+ exits) vs. a single "dispatch to mode handler" protocol**: The design chooses the wide list because each return mode is a real VM state with different slot adjustment semantics. A single continuation would require a second internal dispatch loop, hiding the control flow that Moonlift's region model is designed to make explicit. The cost is verbosity in the return-matching code; the compensating benefit is that every return path is grep-inspectable and individually testable.

2. **Inline resume payload in Frame vs. separate continuation stack**: Frame carries 7 resume fields (mode, a, b, c, pc, base, value). This adds ~56 bytes per frame compared to a linked-list continuation chain. The tradeoff is accepted because: (a) typical nesting depth is <20 frames, so total memory is <2KB, (b) inline payload avoids an indirection for every metamethod return, and (c) frame allocation is a single contiguous allocation.

3. **Tag-based Value vs. NaN-boxing**: The 16-byte Value (tag+aux+bits) is larger than LuaJIT's NaN-boxed 8-byte representation. The design accepts this because: (a) Moonlift's pointer size is the architecture's native pointer size (no NaN-tagging trick), (b) the explicit tag simplifies value dispatch in region bodies (no bit manipulation), and (c) the aux field provides room for future specialization hints without protocol change.

4. **Monomorphic generated handlers vs. one generic handler with runtime parameters**: Arithmetic opcodes (ADD, SUB, etc.) each get a generated handler with a constant TM event. This duplicates handler bodies (~6 lines each for the fast-number path). The tradeoff — ~30 lines of excess code vs. a runtime "event" parameter in a shared handler — favors monomorphic handlers because: (a) the fast path for ADD only checks whether both operands are numbers, which is tag dispatch irrespective of event, (b) the metamethod event constant removes a branch from the slow path, and (c) Lua generation produces the handlers from a table, so maintenance cost is zero.

5. **Heavy products file vs. split by domain**: The README specifies ~25 struct definitions in one product tree. The implementation may split across modules (`products.lua`, `types_value.lua`, `types_heap.lua`) at the implementer's discretion as long as no cyclic product dependencies arise. The product tree is acyclic (Value → Table → Frame → LuaThread → GlobalState).

### Risks acknowledged

1. **GC complexity in Moonlift is untested**: The README specifies full incremental mark-sweep with barriers, gray lists, sweep cursors, and finalization. No Moonlift codebase has implemented GC at this scale. The risk is that Moonlift's region/block/jump model handles GC's multi-state loop poorly — specifically the sweep phase, which iterates over a linked list and conditionally frees. Mitigation: the GC is the last implementation step (step 9), so the interpreter is functional before GC is tested. If GC regions prove awkward, a simplified stop-the-world GC can be substituted without changing any other module's interfaces (the `alloc_object`, `gc_step`, and barrier regions form a stable protocol boundary).

2. **Coroutine yield/resume through the region graph may expose continuation-representation limits**: A coroutine yield saves the full thread state (stack, frames, open upvals). The region graph's block-state representation (`frame, pc, base, top`) is designed for the fast loop, not for serialization. If yield/resume requires saving the region-graph internal state (which block we're in, which continuation we're returning to), the `LuaThread` status + `Frame.resume_mode` model already handles it — but the interaction between `coroutine_yield` and `call_native` is untested and may require the native function to declare yieldability via `NativeFunc.flags`.

3. **The 12-continuation `handle_return_mode` may stress Moonlift's region generation**: Each continuation is a separate region output, meaning the handle_return_mode region has 12 named outputs. If Moonlift's region lowering or code generation has limits on continuation count, this region will be the first to find them. Mitigation: the design is faithful to Moonlift's stated capabilities; if a practical limit exists, handle_return_mode can be decomposed into a tree of 2–3 continuation regions.

4. **Quickening with epoch-based invalidation requires thread safety if LuaThreads share Protos**: The README assumes single-threaded access within a LuaThread. If multiple threads share a `Proto` and one quickens an instruction, the other thread may read stale cache. This is deferred — the initial implementation is single-threaded, and quickening (step 11) is the last implementation step. Thread safety for quickened code will be addressed when coroutines or multiple LuaThreads are exercised in production.

5. **API sealing may need additional C ABI glue for LuaJIT interop**: The sealed API functions (`lua_type_api`, `lua_pcall_api`, etc.) are Moonlift functions that match C calling conventions. If the VM is loaded from LuaJIT FFI, these functions must be exposed as C ABI exports with the correct argument passing conventions (C struct pointers, etc.). The initial implementation can test from a Moonlift-native harness; LuaJIT FFI integration is a deployment concern.

---

## Implementation plan summary

Per Part XI (section 42), the 11-step implementation order:

| Step | Modules | Delivers |
|------|---------|----------|
| 1 | `products.lua`, `constants.lua` | All products, enums, value tag constants, opcode constants, GC color/state constants |
| 2 | `regions_value.lua`, `regions_stack.lua` | Value protocol regions (truth, as_number, to_number, as_string, as_table, as_function, raw_equal, equal, lt, le); Stack regions (stack_check, frame_push, frame_pop, adjust_results, adjust_varargs) |
| 3 | `regions_call.lua` | Call engine regions (prepare_call, try_call_metamethod, call_native, return_from_lua, handle_return_mode) |
| 4 | `opcodes.lua`, `opcodes_gen.lua`, `op_handlers.lua`, `vm_loop.lua` | Lua generation tables; generated opcode constants and dispatch switch; hand-written handler bodies for all 31 opcodes; vm_resume and vm_loop entry points. Interpreter runs simple scripts without GC, metamethods, or coroutines |
| 5 | `regions_table.lua`, `regions_string.lua` | Table get/set/next/resize; string intern/concat/hash. Tables work for basic operations without metamethods |
| 6 | `regions_upvalue.lua` | find_upvalue, close_upvalues, make_lclosure. Closures work, upvalues close correctly on scope exit |
| 7 | `regions_metamethod.lua` | get_metamethod, get_table_metamethod, binop_dispatch, unop_dispatch, prepare_metamethod_call. All metamethod events dispatched correctly |
| 8 | `regions_error.lua`, `regions_coroutine.lua` | Protected frames, raise_error, protected_call, coroutine_resume, coroutine_yield. pcall/xpcall work; coroutine yield/resume works |
| 9 | `gc_impl.lua` | alloc_object, gc_step, mark_value/object, propagate_gray, sweep_step, write_barrier. Full incremental GC with all collector states |
| 10 | `regions_api.lua`, `api.lua` | api_index_to_addr; sealed C-compatible API functions (lua_type, lua_settop, lua_pushvalue, lua_gettable, lua_settable, lua_call, lua_pcall, etc.) |
| 11 | `quicking.lua` | Quickened opcode families (GETTAB_ARRAY, GETTAB_STR_SLOT, etc.), probe_gettable_cache, quicken_instruction, deopt_instruction, structural epoch validation |

Each step produces final-shape code for its domain. No step writes code that must be rewritten later. The VM is partially functional after step 4 (runs simple scripts without tables, closures, or GC) and fully functional (minus quickening) after step 9.

## Edit-planner Output — 2026-05-21 21:20:56

Now I have comprehensive understanding of the Moonlift syntax, the README specification, and the project conventions. Let me produce the implementation plan.

---

# Moonlift Lua Interpreter VM — Complete Implementation Plan

## Precondition Checks

Before any edits begin, verify:
1. `experiments/lua_interpreter_vm/src/` directory exists (create if not)
2. Confirm Moonlift hosted-island parsing works in `.mlua` files at `experiments/` level (the LSP/test harness path setup includes `./experiments/?/?.lua` etc.)
3. Check that `extern` type declarations are supported for `Allocator` (an opaque pointer type used in `GlobalState`)
4. Verify no conflicting `struct Value` or `struct Proto` declarations exist elsewhere in the experiments directory

---

## Files to Modify (create)

### Order of creation: the 11-step sequence from the architectural decision, plus file-level details.

---

### Step 1: Products & Constants

#### `experiments/lua_interpreter_vm/src/constants.mlua`

**Goal**: Define all scalar constants (value tags, opcodes, TM events, frame modes, thread statuses, error codes, GC colors/states) as Lua `local` values that are spliced into Moonlift source.

**Edit blocks**:
1. **Lines 1-5**: Module header
   - `-- SPDX-License-Identifier: MIT` comment
   - `-- Lua constants for the VM. Spliced into Moonlift source via @{} splices.`

2. **Lines 7-60**: Value tag constants
   ```lua
   -- Value tags (u32)
   local TAG_NIL = 0
   local TAG_FALSE = 1
   local TAG_TRUE = 2
   local TAG_LIGHTUD = 3
   local TAG_NUM = 4
   local TAG_STR = 5
   local TAG_TABLE = 6
   local TAG_LCLOSURE = 7
   local TAG_CCLOSURE = 8
   local TAG_USERDATA = 9
   local TAG_THREAD = 10
   local TAG_PROTO = 11
   ```

3. **Lines 62-100**: Opcode constants (u16, values matching Lua 5.1 opcode numbering)
   ```lua
   -- OpCodes (u16) — Lua 5.1 opcode numbering
   local OP_MOVE = 0
   local OP_LOADK = 1
   ...
   local OP_VARARG = 38
   ```
   Full list from README §3.2. Ordering: MOVE(0) through VARARG(38), exactly 39 opcodes.

4. **Lines 102-122**: TM event constants (u8)
   ```lua
   -- TM events for metamethod dispatch
   local TM_INDEX = 0
   local TM_NEWINDEX = 1
   local TM_GC = 2
   ...
   local TM_CALL = 16
   local TM_N = 17   -- count of TM events
   ```

5. **Lines 124-145**: Frame mode constants (u16)
   ```lua
   -- Frame resume modes (u16)
   local RESUME_NORMAL = 0
   local RESUME_TAILCALL = 1
   local RESUME_PCALL = 2
   ...
   local RESUME_NATIVE_CONT = 15
   ```

6. **Lines 147-157**: Thread status constants (u8)
   ```lua
   -- Thread statuses (u8)
   local THREAD_OK = 0
   local THREAD_YIELDED = 1
   local THREAD_RUNTIME_ERROR = 2
   local THREAD_OOM = 3
   local THREAD_DEAD = 4
   ```

7. **Lines 159-175**: Error code constants (i32)
   ```lua
   -- Error codes (i32)
   local ERR_NONE = 0
   local ERR_RUNTIME = 1
   local ERR_SYNTAX = 2
   local ERR_MEMORY = 3
   ...
   local ERR_API = 16
   ```

8. **Lines 177-190**: GC color/state constants (u8)
   ```lua
   -- GC colors
   local COLOR_WHITE0 = 0
   local COLOR_WHITE1 = 1
   local COLOR_GRAY = 2
   local COLOR_BLACK = 3

   -- GC states
   local GCSTATE_PAUSE = 0
   local GCSTATE_PROPAGATE = 1
   local GCSTATE_SWEEP = 2
   local GCSTATE_FINALIZE = 3
   ```

9. **Lines 192-195**: Return statement exporting all constants
   ```lua
   return {
       Tag = { NIL=TAG_NIL, FALSE=TAG_FALSE, TRUE=TAG_TRUE, LIGHTUD=TAG_LIGHTUD,
               NUM=TAG_NUM, STR=TAG_STR, TABLE=TAG_TABLE, LCLOSURE=TAG_LCLOSURE,
               CCLOSURE=TAG_CCLOSURE, USERDATA=TAG_USERDATA, THREAD=TAG_THREAD,
               PROTO=TAG_PROTO },
       Op = { MOVE=OP_MOVE, LOADK=OP_LOADK, ... },
       TM = { INDEX=TM_INDEX, NEWINDEX=TM_NEWINDEX, ... },
       Resume = { NORMAL=RESUME_NORMAL, TAILCALL=RESUME_TAILCALL, ... },
       ...
   }
   ```

**Total**: ~210 lines

**Quirks**:
- All constants must match Lua 5.1 opcode numbering exactly (0-38). Verify against PUC Lua 5.1 source.
- Tag numbering order: nil(0), false(1), true(2), lightud(3), num(4), str(5), table(6), lclosure(7), cclosure(8), userdata(9), thread(10), proto(11)
- GC color values: white0=0, white1=1, gray=2, black=3 — these are paired with `currentwhite` in GlobalState for the sweepphase toggle

---

#### `experiments/lua_interpreter_vm/src/products.mlua`

**Goal**: Define all Moonlift struct types for the VM data type tree, in dependency order (no forward references).

**Edit blocks**:

1. **Lines 1-10**: Module header and imports from constants
   ```lua
   -- Data type tree: all storage products for the Lua VM
   local const = require("experiments.lua_interpreter_vm.src.constants")
   ```

2. **Lines 12-25**: `Value` struct
   ```moonlift
   struct Value
       tag: u32
       aux: u32
       bits: u64
   end
   ```
   Note: `Value` is a flat 16-byte product. Tag dispatch determines interpretation of `bits`.

3. **Lines 27-35**: `GCHeader` struct
   ```moonlift
   struct GCHeader
       next: ptr(GCHeader)
       tt: u8
       marked: u8
   end
   ```
   `tt` matches the Value tag for the object type. `marked` encodes GC color + other flags.

4. **Lines 37-50**: `Node` struct (table hash chain node)
   ```moonlift
   struct Node
       key: Value
       value: Value
       next: ptr(Node)
   end
   ```

5. **Lines 52-70**: `String` struct
   ```moonlift
   struct String
       gc: GCHeader
       reserved: u8
       hash: u32
       len: index
       bytes: ptr(u8)
   end
   ```
   `bytes` points to the string data allocated adjacent or separately. String interning ensures pointer equality.

6. **Lines 72-88**: `Table` struct
   ```moonlift
   struct Table
       gc: GCHeader
       flags: u32
       array_len: index
       array: ptr(Value)
       node_mask: u32
       nodes: ptr(Node)
       lastfree: ptr(Node)
       metatable: ptr(Table)
       shape_epoch: u32
   end
   ```
   `node_mask` is `2^hash_power - 1`. `lastfree` is the free chain pointer for the Lua hash collision resolution.

7. **Lines 90-110**: `Instr` struct
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
   Decoded instruction. A loader must decode packed bytecode into this shape once.

8. **Lines 112-125**: `LocVar` struct
   ```moonlift
   struct LocVar
       name: ptr(String)
       startpc: index
       endpc: index
   end
   ```

9. **Lines 127-140**: `UpValDesc` struct
   ```moonlift
   struct UpValDesc
       name: ptr(String)
       instack: u8
       index: u16
   end
   ```

10. **Lines 142-175**: `Proto` struct
    ```moonlift
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
    `children` is an array of `ptr(Proto)` — child function prototypes for CLOSURE opcodes.

11. **Lines 177-190**: `UpVal` struct
    ```moonlift
    struct UpVal
        gc: GCHeader
        v: ptr(Value)
        closed: Value
        stack_index: index
        next_open: ptr(UpVal)
    end
    ```
    `v` points into the Lua stack when open, or to `&closed` when closed.

12. **Lines 192-205**: `LClosure` struct
    ```moonlift
    struct LClosure
        gc: GCHeader
        env: ptr(Table)
        proto: ptr(Proto)
        upvals: ptr(ptr(UpVal))
        nupvals: u8
    end
    ```
    `upvals` is an array of `ptr(UpVal)` pointers.

13. **Lines 207-218**: `NativeFunc` struct (opaque ABI function descriptor)
    ```moonlift
    struct NativeFunc
        addr: ptr(u8)
        flags: u32
    end
    ```
    `addr` is the function pointer. `flags` encodes yieldability, fast-call capability.

14. **Lines 220-233**: `CClosure` struct
    ```moonlift
    struct CClosure
        gc: GCHeader
        env: ptr(Table)
        fn: ptr(NativeFunc)
        upvals: ptr(Value)
        nupvals: u8
    end
    ```

15. **Lines 235-255**: `UserData` struct
    ```moonlift
    struct UserData
        gc: GCHeader
        metatable: ptr(Table)
        env: ptr(Table)
        len: index
        data: ptr(u8)
    end
    ```

16. **Lines 257-280**: `Frame` struct
    ```moonlift
    struct Frame
        closure: Value
        base: index
        top: index
        pc: index
        wanted: i32
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
    The 7 `resume_*` fields encode the dynamic Lua continuation payload.

17. **Lines 282-295**: `ProtectedFrame` struct
    ```moonlift
    struct ProtectedFrame
        frame_index: index
        stack_top: index
        handler_slot: index
        errfunc_slot: index
        previous: ptr(ProtectedFrame)
    end
    ```
    Linked list (via `previous`) replacing C `setjmp` chain.

18. **Lines 297-325**: `LuaThread` struct
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
        hook: Value
    end
    ```
    Note: `global` is `ptr(GlobalState)` — a forward reference to GlobalState declared below. This is OK as long as GlobalState appears later in the same file or module.

19. **Lines 327-340**: `StringTable` struct
    ```moonlift
    struct StringTable
        buckets: ptr(ptr(String))
        bucket_count: index
        nuse: index
    end
    ```

20. **Lines 342-375**: `GlobalState` struct
    ```moonlift
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
        panic: Value
    end
    ```
    `allocator` is `ptr(Allocator)` — an opaque extern type. Define `Allocator` as an empty struct or extern type.

21. **Lines 377-390**: `InlineCache` struct
    ```moonlift
    struct InlineCache
        epoch: u32
        aux0: u32
        aux1: u32
        key: Value
        value: Value
    end
    ```

22. **Lines 392-405**: `QuickInstr` struct
    ```moonlift
    struct QuickInstr
        instr: Instr
        cache: InlineCache
    end
    ```

23. **Lines 407-420**: `DebugInfo` struct
    ```moonlift
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

24. **Lines 422-430**: `Allocator` extern type wrapper
    ```moonlift
    -- Allocator is defined in the C runtime. It's a function pointer table.
    -- In Moonlift, we treat it as an opaque extern struct through which allocation
    -- functions are called.
    ```
    Since Moonlift doesn't have opaque extern types directly, define:
    ```moonlift
    struct Allocator
        -- Opaque: actual layout is in C. Moonlift accesses via extern calls.
    end
    ```
    Or just reference `Allocator` as an extern name. **Danger zone**: The compiler must accept a struct with no fields. If not supported, define a single dummy field:
    ```moonlift
    struct Allocator
        _opaque: ptr(u8)
    end
    ```

25. **Lines 432-435**: Return table
    ```lua
    return {
        Value = Value,
        GCHeader = GCHeader,
        String = String,
        ...
    }
    ```
    This is Lua code outside the Moonlift hosted island.

**Total**: ~440 lines

**Danger zones**:
- The `ptr(ptr(Proto))` and `ptr(ptr(String))` types must be verified as valid in Moonlift (pointer-to-pointer). Check Moonlift's pointer-to-pointer support.
- `Frame` must appear before `LuaThread` which must appear before `GlobalState` (circular via `global` pointer). Since the structs are defined in one file, Moonlift must handle forward references to later structs via pointer types. If Moonlift requires topo-order, reorder: Value, GCHeader, Node, String, Table, Instr, LocVar, UpValDesc, Proto, UpVal, LClosure, NativeFunc, CClosure, UserData, InlineCache, QuickInstr, DebugInfo, ProtectedFrame, Allocator, Frame, GlobalState, StringTable, LuaThread. `LuaThread.global` is `ptr(GlobalState)` — this works if GlobalState is defined before LuaThread in source order.
- **Correct order** (from leaf to root): Value, GCHeader, Node, String, Table, Instr, LocVar, UpValDesc, Proto, UpVal, LClosure, NativeFunc, CClosure, UserData, InlineCache, QuickInstr, DebugInfo, Allocator, ProtectedFrame, Frame, StringTable, GlobalState, LuaThread. This avoids all forward references.

---

### Step 2: Value Regions + Stack Regions

#### `experiments/lua_interpreter_vm/src/regions_value.mlua`

**Goal**: Define all value protocol regions — truth, type checks, comparisons, equality.

**Edit blocks**:

1. **Lines 1-20**: `value_truth` region
   ```moonlift
   region value_truth(v: Value;
       truthy: cont(),
       falsey: cont())
   entry start()
       if v.tag == @{TAG_NIL} or v.tag == @{TAG_FALSE} then
           jump falsey()
       end
       jump truthy()
   end
   end
   ```
   Key: Boolean is two tags so falsiness is exactly two tag comparisons.

2. **Lines 22-40**: `value_as_number` region
   ```moonlift
   region value_as_number(v: Value;
       number: cont(x: f64),
       not_number: cont())
   entry start()
       if v.tag == @{TAG_NUM} then
           jump number(x = as(f64, v.bits))
       end
       jump not_number()
   end
   end
   ```

3. **Lines 42-65**: `value_to_number` region (with string→number coercion)
   ```moonlift
   region value_to_number(
       L: ptr(LuaThread),
       v: Value;
       number: cont(x: f64),
       not_number: cont(),
       oom: cont())
   entry start()
       if v.tag == @{TAG_NUM} then
           jump number(x = as(f64, v.bits))
       end
       -- Try string→number coercion (deferred to string module)
       emit value_as_string(v; string = try_coerce, not_string = fail)
   end
   block try_coerce(s: ptr(String))
       -- Attempt numeric parse from string bytes
       -- If parse succeeds: jump number(x = parsed)
       -- If parse fails: jump not_number()
       -- For initial implementation: always not_number()
       jump not_number()
   end
   block fail()
       jump not_number()
   end
   end
   ```

4. **Lines 67-82**: `value_as_string` region
   ```moonlift
   region value_as_string(v: Value;
       string: cont(s: ptr(String)),
       not_string: cont())
   entry start()
       if v.tag == @{TAG_STR} then
           jump string(s = as(ptr(String), v.bits))
       end
       jump not_string()
   end
   end
   ```

5. **Lines 84-105**: `value_to_string` region (with coercion)
   ```moonlift
   region value_to_string(
       L: ptr(LuaThread),
       v: Value;
       string: cont(s: ptr(String)),
       error: cont(code: i32),
       oom: cont())
   entry start()
       if v.tag == @{TAG_STR} then
           jump string(s = as(ptr(String), v.bits))
       end
       if v.tag == @{TAG_NUM} then
           -- Format number to string (deferred)
           -- For initial: convert via internal buffer
           -- Temporarily: error
           jump error(code = @{ERR_RUNTIME})
       end
       jump error(code = @{ERR_RUNTIME})
   end
   end
   ```

6. **Lines 107-122**: `value_as_table` region
   ```moonlift
   region value_as_table(v: Value;
       table: cont(t: ptr(Table)),
       not_table: cont())
   entry start()
       if v.tag == @{TAG_TABLE} then
           jump table(t = as(ptr(Table), v.bits))
       end
       jump not_table()
   end
   end
   ```

7. **Lines 124-142**: `value_as_function` region
   ```moonlift
   region value_as_function(v: Value;
       lua: cont(cl: ptr(LClosure)),
       native: cont(cl: ptr(CClosure)),
       not_function: cont())
   entry start()
       if v.tag == @{TAG_LCLOSURE} then
           jump lua(cl = as(ptr(LClosure), v.bits))
       end
       if v.tag == @{TAG_CCLOSURE} then
           jump native(cl = as(ptr(CClosure), v.bits))
       end
       jump not_function()
   end
   end
   ```

8. **Lines 144-175**: `value_raw_equal` region
   ```moonlift
   region value_raw_equal(
       a: Value,
       b: Value;
       equal: cont(),
       not_equal: cont())
   entry start()
       -- Fast path: same tag required
       if a.tag != b.tag then jump not_equal() end
       -- Dispatch by tag
       switch a.tag
           case @{TAG_NIL} then jump equal()
           case @{TAG_FALSE} then jump equal()
           case @{TAG_TRUE} then jump equal()
           case @{TAG_NUM} then
               if as(f64, a.bits) == as(f64, b.bits) then
                   jump equal()
               end
               jump not_equal()
           case @{TAG_STR} then
               -- String equality is pointer equality (interning)
               if a.bits == b.bits then jump equal() end
               jump not_equal()
           case @{TAG_LIGHTUD} then
               if a.bits == b.bits then jump equal() end
               jump not_equal()
           default then
               -- Collectable objects: pointer equality
               if a.bits == b.bits then jump equal() end
               jump not_equal()
           end
       end
   end
   end
   ```

9. **Lines 177-215**: `value_equal` region (with __eq metamethod)
   ```moonlift
   region value_equal(
       L: ptr(LuaThread),
       a: Value,
       b: Value;
       result: cont(is_equal: bool),
       call_mm: cont(mm: Value),
       error: cont(code: i32),
       oom: cont())
   entry try_raw()
       emit value_raw_equal(a, b; equal = yes, not_equal = check_meta)
   end
   block yes()
       jump result(is_equal = true)
   end
   block check_meta()
       -- Check if either value has __eq metamethod
       -- For tables: check metatable flags; for userdata: check metatable
       -- Deferred to metamethod module
       jump result(is_equal = false)
   end
   end
   ```

10. **Lines 217-255**: `value_less_than` region
    ```moonlift
    region value_less_than(
        L: ptr(LuaThread),
        a: Value,
        b: Value;
        result: cont(is_lt: bool),
        call_mm: cont(mm: Value),
        error: cont(code: i32),
        oom: cont())
    entry start()
        -- Number path
        if a.tag == @{TAG_NUM} and b.tag == @{TAG_NUM} then
            jump result(is_lt = as(f64, a.bits) < as(f64, b.bits))
        end
        -- String path
        if a.tag == @{TAG_STR} and b.tag == @{TAG_STR} then
            -- String comparison: lexicographic
            -- Deferred: compare bytes
            -- For initial: error
            jump error(code = @{ERR_COMPARE})
        end
        -- Metamethod dispatch (deferred)
        jump error(code = @{ERR_COMPARE})
    end
    end
    ```

11. **Lines 257-295**: `value_less_equal` region
    ```moonlift
    region value_less_equal(
        L: ptr(LuaThread),
        a: Value,
        b: Value;
        result: cont(is_le: bool),
        call_mm: cont(mm: Value, fallback_lt: bool),
        error: cont(code: i32),
        oom: cont())
    entry start()
        -- Number path
        if a.tag == @{TAG_NUM} and b.tag == @{TAG_NUM} then
            jump result(is_le = as(f64, a.bits) <= as(f64, b.bits))
        end
        -- String path
        if a.tag == @{TAG_STR} and b.tag == @{TAG_STR} then
            -- String comparison
            jump error(code = @{ERR_COMPARE})
        end
        -- Metamethod dispatch (deferred): try __le first, fall back to __lt
        jump error(code = @{ERR_COMPARE})
    end
    end
    ```

**Total**: ~300 lines

**Interesting patterns**:
- `as(f64, v.bits)` converts `u64` bits to `f64` — confirm Moonlift supports this bitcast conversion
- Tag constants are `@{TAG_NIL}` Lua splices from the constants module
- Switch statements must have a `default` arm per Moonlift rules
- Each block path must terminate with `jump` — no fallthrough

---

#### `experiments/lua_interpreter_vm/src/regions_stack.mlua`

**Goal**: Define stack manipulation and frame management regions.

**Edit blocks**:

1. **Lines 1-30**: `stack_check` region
   ```moonlift
   region stack_check(
       L: ptr(LuaThread),
       needed_top: index;
       ok: cont(),
       grown: cont(),
       overflow: cont(),
       oom: cont())
   entry start()
       if needed_top <= L.stack_size then
           jump ok()
       end
       -- Attempt to grow stack
       -- For initial: overflow after checking size limit
       if needed_top > @{MAX_STACK_SIZE} then
           jump overflow()
       end
       -- Reallocate stack (deferred: requires allocator)
       -- For initial stub: jump overflow()
       jump overflow()
   end
   end
   ```

2. **Lines 32-65**: `frame_push` region
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
   entry start()
       if L.frame_count >= L.frame_cap then
           -- Grow frame array
           -- For initial: overflow
           jump overflow()
       end
       -- Allocate new frame at frames[frame_count]
       let idx: index = L.frame_count
       L.frame_count = idx + 1
       let f: ptr(Frame) = L.frames + idx
       f.closure = closure
       f.base = base
       f.top = top
       f.pc = 0
       f.wanted = wanted
       f.tailcalls = 0
       f.resume_mode = resume_mode
       f.resume_a = 0
       f.resume_b = 0
       f.resume_c = 0
       f.resume_pc = 0
       f.resume_base = 0
       f.resume_value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
       jump ok(frame = f)
   end
   end
   ```
   **Key**: Write to `L.frames + idx` (pointer arithmetic) to get frame pointer. Confirm Moonlift supports `ptr + index` arithmetic.

3. **Lines 67-85**: `frame_pop` region
   ```moonlift
   region frame_pop(
       L: ptr(LuaThread);
       parent: cont(frame: ptr(Frame)),
       empty: cont())
   entry start()
       if L.frame_count == 0 then
           jump empty()
       end
       L.frame_count = L.frame_count - 1
       -- Predecessor frame is at frame_count - 1
       -- But we need to access the new top frame
       -- The parent is the frame at the new frame_count - 1
       if L.frame_count == 0 then
           -- No more frames after pop — but we still have a parent
           -- This handles the outermost frame
           jump parent(frame = L.frames)
       end
       let pf: ptr(Frame) = L.frames + (L.frame_count - 1)
       jump parent(frame = pf)
   end
   end
   ```

4. **Lines 87-120**: `adjust_results` region
   ```moonlift
   region adjust_results(
       L: ptr(LuaThread),
       first_result: index,
       nactual: i32,
       wanted: i32,
       dst: index;
       done: cont(nplaced: i32),
       oom: cont())
   entry start()
       if wanted >= 0 then
           -- Fixed number of results
           let n: i32 = nactual
           if n > wanted then n = wanted end
           -- Move results from first_result to dst
           -- Copy n values
           -- For initial: we'll assume n <= wanted
           -- Fill remainder with nil
           var i: i32 = 0
           block copy_loop()
               if i >= n then jump fill_remainder() end
               L.stack[dst + as(index, i)] = L.stack[first_result + as(index, i)]
               i = i + 1
               jump copy_loop()
           end
           block fill_remainder()
               if i >= wanted then jump done(nplaced = wanted) end
               L.stack[dst + as(index, i)].tag = @{TAG_NIL}
               i = i + 1
               jump fill_remainder()
           end
       else
           -- wanted == -1: multret, keep all results
           jump done(nplaced = nactual)
       end
   end
   end
   ```

5. **Lines 122-155**: `adjust_varargs` region
   ```moonlift
   region adjust_varargs(
       L: ptr(LuaThread),
       cl: ptr(LClosure),
       func_slot: index,
       nargs: i32;
       ok: cont(base: index),
       oom: cont())
   entry start()
       let np: i32 = as(i32, cl.proto.numparams)
       let fixargs: index = as(index, np)
       let vararg_count: i32
       if nargs > np then
           vararg_count = nargs - np
       else
           vararg_count = 0
       end
       -- Fixed parameters are at func_slot + 1 .. func_slot + np
       -- Vararg parameters (if cl.proto.is_vararg) are pushed after
       -- For initial: just return base = func_slot + 1
       jump ok(base = func_slot + 1)
   end
   end
   ```

**Total**: ~160 lines

**Danger zones**:
- Pointer arithmetic on `L.frames + idx` requires Moonlift to support `ptr(T) + index`. If not, use `L.frames[idx]` array-index syntax if Moonlift supports it. **Verify this compiles.**
- `L.stack[dst + as(index, i)]` — confirm indexing into `ptr(Value)` via `[]` syntax.
- The `block` loops `copy_loop` and `fill_remainder` use `var` mutable bindings — this is correct Moonlift for stack-backed mutables.

---

### Step 3: Call/Return Engine

#### `experiments/lua_interpreter_vm/src/regions_call.mlua`

**Goal**: Define the call dispatch, native call, return handling, and resume-mode dispatch regions.

**Edit blocks**:

1. **Lines 1-50**: `prepare_call` region (the central call dispatcher)
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
   entry start()
       let func_val: Value = L.stack[func_slot]
       -- Check if it's a Lua closure
       if func_val.tag == @{TAG_LCLOSURE} then
           let cl: ptr(LClosure) = as(ptr(LClosure), func_val.bits)
           let proto: ptr(Proto) = cl.proto
           let base: index = func_slot + 1
           emit stack_check(L, base + as(index, proto.maxstack);
               ok = do_push,
               grown = do_push,
               overflow = stack_err,
               oom = out_of_mem)
       end
       block do_push()
           let cl: ptr(LClosure) = as(ptr(LClosure), func_val.bits)
           let proto: ptr(Proto) = cl.proto
           let base: index = func_slot + 1
           -- Close previous frame's registers for tailcall
           -- Push new frame
           emit frame_push(L, func_val, base, base + as(index, nargs),
                           wanted, resume_mode;
               ok = got_frame,
               overflow = stack_err,
               oom = out_of_mem)
       end
       block got_frame(child: ptr(Frame))
           -- Set up the frame's pc for Lua call
           child.pc = 0
           jump enter_lua(child = child)
       end
       -- Check if native closure
       -- ...
       block stack_err()
           jump error(code = @{ERR_STACK_OVERFLOW})
       end
       block out_of_mem()
           jump oom()
       end
   end
   end
   ```

2. **Lines 52-80**: `try_call_metamethod` region
   ```moonlift
   region try_call_metamethod(
       L: ptr(LuaThread),
       func_slot: index;
       replaced: cont(),
       not_callable: cont(),
       error: cont(code: i32),
       oom: cont())
   entry start()
       -- Check if the value at func_slot has __call metamethod
       -- If found: replace func_slot with metamethod, set up resume mode
       -- If not: not_callable
       -- Stub: not_callable
       jump not_callable()
   end
   end
   ```

3. **Lines 82-120**: `call_native` region
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
   entry start()
       -- The native function ABI:
       --   return >= 0: returned with n results
       --   return YIELD: yielded
       --   return ERROR: error object on stack
       --   return OOM: oom
       -- For initial stub: return 0
       jump returned(nres = 0)
   end
   end
   ```

4. **Lines 122-175**: `return_from_lua` region
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
   entry start()
       -- Close upvalues for this frame
       emit close_upvalues(L, frame.base;
           done = pop_it,
           oom = out_of_mem)
   end
   block pop_it()
       -- Pop the current frame
       emit frame_pop(L;
           parent = do_return,
           empty = all_done)
   end
   block do_return(parent: ptr(Frame))
       -- Dispatch to handle_return_mode
       emit handle_return_mode(L, parent, first_result, nres;
           normal = cont_normal,
           resume_gettable_mm = cont_gettable,
           resume_settable_mm = cont_settable,
           -- ... all 12+ continuations
           finished = all_done)
   end
   block cont_normal(parent: ptr(Frame), pc: index, base: index, top: index)
       jump resume_parent(parent = parent, pc = pc, base = base, top = top)
   end
   block cont_gettable(parent: ptr(Frame), pc: index, base: index, top: index)
       jump resume_parent(parent = parent, pc = pc, base = base, top = top)
   end
   -- ... more blocks for each resume mode
   block all_done(nres: i32)
       jump finished(nres = nres)
   end
   block out_of_mem()
       jump oom()
   end
   end
   ```

5. **Lines 177-230**: `handle_return_mode` region (the 12+ continuation switch)
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
   entry start()
       switch parent.resume_mode
           case @{RESUME_NORMAL} then
               emit adjust_results(L, first_result, nres, parent.wanted, parent.base;
                   done = adj_done_normal,
                   oom = out_of_mem)
           case @{RESUME_GETTABLE_MM} then
               -- Place result into resume_a register
               jump normal(parent = parent,
                   pc = parent.resume_pc,
                   base = parent.resume_base,
                   top = parent.top)
           -- ... more cases
           default then
               jump finished(nres = nres)
           end
   end
   block adj_done_normal(nplaced: i32)
       jump normal(parent = parent,
           pc = parent.pc + 1,
           base = parent.base,
           top = parent.top)
   end
   block out_of_mem()
       jump oom()
   end
   end
   ```

**Total**: ~240 lines

**Danger zone**: The 12+ continuation signature is the most complex region in the entire VM. Each continuation must have exactly the parameter types expected by the consumers. A mistake here propagates to every call site.

**Pattern**: For the initial implementation, not all resume modes need full bodies. The `default` arm can handle unrecognized modes gracefully.

---

### Step 4: Opcodes + VM Loop

#### `experiments/lua_interpreter_vm/src/opcodes.lua`

**Goal**: Pure Lua file containing opcode specification tables that generate `opcodes_gen.mlua`.

**Edit blocks**:

1. **Lines 1-5**: Module setup
   ```lua
   -- Lua generation layer for opcode definitions.
   -- Produces opcodes_gen.lua (or a Lua table that gets written to opcodes_gen.mlua).
   local const = require("experiments.lua_interpreter_vm.src.constants")
   ```

2. **Lines 7-60**: Opcode specification table
   ```lua
   local opcodes = {
       { name = "MOVE",     mode = "ABC",  handler = "op_move",     effects = {"next"} },
       { name = "LOADK",    mode = "ABx",  handler = "op_loadk",    effects = {"next"} },
       { name = "LOADBOOL", mode = "ABC",  handler = "op_loadbool", effects = {"next"} },
       { name = "LOADNIL",  mode = "ABC",  handler = "op_loadnil",  effects = {"next"} },
       { name = "GETUPVAL", mode = "ABC",  handler = "op_getupval", effects = {"next"} },
       { name = "GETGLOBAL",mode = "ABx",  handler = "op_getglobal",effects = {"next", "error"} },
       { name = "GETTABLE", mode = "ABC",  handler = "op_gettable", effects = {"next", "call", "error", "oom"} },
       { name = "SETGLOBAL",mode = "ABx",  handler = "op_setglobal",effects = {"next", "error", "oom"} },
       { name = "SETUPVAL", mode = "ABC",  handler = "op_setupval", effects = {"next"} },
       { name = "SETTABLE", mode = "ABC",  handler = "op_settable", effects = {"next", "call", "error", "oom"} },
       { name = "NEWTABLE", mode = "ABC",  handler = "op_newtable", effects = {"next", "oom"} },
       { name = "SELF",     mode = "ABC",  handler = "op_self",     effects = {"next", "call", "error", "oom"} },
       { name = "ADD",      mode = "ABC",  handler = "op_add",      effects = {"next", "call", "error"} },
       { name = "SUB",      mode = "ABC",  handler = "op_sub",      effects = {"next", "call", "error"} },
       { name = "MUL",      mode = "ABC",  handler = "op_mul",      effects = {"next", "call", "error"} },
       { name = "DIV",      mode = "ABC",  handler = "op_div",      effects = {"next", "call", "error"} },
       { name = "MOD",      mode = "ABC",  handler = "op_mod",      effects = {"next", "call", "error"} },
       { name = "POW",      mode = "ABC",  handler = "op_pow",      effects = {"next", "call", "error"} },
       { name = "UNM",      mode = "ABC",  handler = "op_unm",      effects = {"next", "call", "error"} },
       { name = "NOT",      mode = "ABC",  handler = "op_not",      effects = {"next"} },
       { name = "LEN",      mode = "ABC",  handler = "op_len",      effects = {"next", "call", "error", "oom"} },
       { name = "CONCAT",   mode = "ABC",  handler = "op_concat",   effects = {"next", "call", "error", "oom"} },
       { name = "JMP",      mode = "AsBx", handler = "op_jmp",      effects = {"jump"} },
       { name = "EQ",       mode = "ABC",  handler = "op_eq",       effects = {"next", "jump", "call", "error"} },
       { name = "LT",       mode = "ABC",  handler = "op_lt",       effects = {"next", "jump", "call", "error"} },
       { name = "LE",       mode = "ABC",  handler = "op_le",       effects = {"next", "jump", "call", "error"} },
       { name = "TEST",     mode = "ABC",  handler = "op_test",     effects = {"next", "jump"} },
       { name = "TESTSET",  mode = "ABC",  handler = "op_testset",  effects = {"next", "jump"} },
       { name = "CALL",     mode = "ABC",  handler = "op_call",     effects = {"next", "call", "yield", "error", "oom"} },
       { name = "TAILCALL", mode = "ABC",  handler = "op_tailcall", effects = {"next", "call", "yield", "error", "oom"} },
       { name = "RETURN",   mode = "ABC",  handler = "op_return",   effects = {"return", "finished", "error", "oom"} },
       { name = "FORLOOP",  mode = "AsBx", handler = "op_forloop",  effects = {"next", "jump", "error"} },
       { name = "FORPREP",  mode = "AsBx", handler = "op_forprep",  effects = {"jump", "error"} },
       { name = "TFORLOOP", mode = "ABC",  handler = "op_tforloop", effects = {"next", "jump", "call", "error", "oom"} },
       { name = "SETLIST",  mode = "ABC",  handler = "op_setlist",  effects = {"next", "oom"} },
       { name = "CLOSE",    mode = "A",    handler = "op_close",    effects = {"next"} },
       { name = "CLOSURE",  mode = "ABx",  handler = "op_closure",  effects = {"next", "oom"} },
       { name = "VARARG",   mode = "ABC",  handler = "op_vararg",   effects = {"next", "oom"} },
   }
   ```

3. **Lines 62-100**: Generation functions
   ```lua
   -- Generate opcode constant names
   local function generate_constants(opcodes)
       local lines = {}
       for i, op in ipairs(opcodes) do
           lines[#lines + 1] = string.format("local OP_%s = %d", op.name, i - 1)
       end
       return table.concat(lines, "\n")
   end

   -- Generate dispatch switch arms
   local function generate_switch(opcodes)
       local lines = {}
       for _, op in ipairs(opcodes) do
           local args = "L, frame, pc, base, top, a, b, c, bx, sbx"
           lines[#lines + 1] = string.format("    case OP_%s then\n        emit %s(%s;\n            next = do_next,\n            jump = do_jump,\n            enter_lua = do_lua,\n            enter_native = do_native,\n            returned = do_returned,\n            yielded = do_yielded,\n            error = do_error,\n            oom = do_oom)",
               op.name, op.handler, args)
       end
       return table.concat(lines, "\n")
   end
   ```

4. **Lines 102-150**: Handler declaration generators
   Generate region signatures for each opcode, specializing continuations based on `effects`.
   ```lua
   -- Generate handler region declaration
   local function generate_handler(op, const)
       local effects = op.effects
       local conts = {}
       for _, e in ipairs(effects) do
           if e == "next" then
               conts[#conts + 1] = "next: cont(frame: ptr(Frame), pc: index, base: index, top: index)"
           elseif e == "jump" then
               conts[#conts + 1] = "jump: cont(frame: ptr(Frame), pc: index, base: index, top: index)"
           elseif e == "call" then
               conts[#conts + 1] = "enter_lua: cont(child: ptr(Frame))"
               conts[#conts + 1] = "enter_native: cont(cl: ptr(CClosure))"
           elseif e == "yield" then
               conts[#conts + 1] = "yielded: cont(nres: i32)"
           elseif e == "return" then
               conts[#conts + 1] = "resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index)"
           elseif e == "finished" then
               conts[#conts + 1] = "finished: cont(nres: i32)"
           elseif e == "error" then
               conts[#conts + 1] = "error: cont(code: i32)"
           elseif e == "oom" then
               conts[#conts + 1] = "oom: cont()"
           end
       end
       -- ...
   end
   ```

5. **Lines 152-160**: Return generated code
   ```lua
   return {
       opcodes = opcodes,
       generate_constants = generate_constants,
       generate_switch = generate_switch,
       generate_handlers = generate_handlers,
   }
   ```

**Total**: ~170 lines

**Danger zone**: The effects list must be accurate for each opcode. An opcode that can trigger GC (most of them) should list "oom". An opcode that reads from global environment should list "error".

---

#### `experiments/lua_interpreter_vm/src/opcodes_gen.mlua` (GENERATED)

This file is **generated** by running `opcodes.lua`. It contains:
1. All opcode constant values (e.g., `local OP_MOVE = 0`)
2. The `dispatch_instruction` region with a switch on opcode
3. Handler declarations for each opcode with correct continuations

The file should be regenerated whenever `opcodes.lua` changes. The worker agent should run `luajit opcodes.lua > opcodes_gen.mlua` as part of the build.

**Edit blocks** (illustrative — actual content comes from generation):

- **Lines 1-50**: Generated opcode constants
- **Lines 52-200**: `dispatch_instruction` region with switch on `op`
- **Lines 202-end**: Handler region declarations (stubs/signatures only, actual bodies in `op_handlers.mlua`)

**Total**: ~500 lines (generated)

---

#### `experiments/lua_interpreter_vm/src/op_handlers.mlua`

**Goal**: Hand-written region bodies for all 39 opcodes.

**Edit blocks** (representative — each opcode handler is a region):

1. **Lines 1-25**: `op_move` — copy register value
   ```moonlift
   region op_move(
       L: ptr(LuaThread),
       frame: ptr(Frame),
       pc: index,
       base: index,
       top: index,
       a: u16,
       b: u16,
       c: u16,
       bx: u32,
       sbx: i32;
       next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
   entry start()
       let dst: index = base + as(index, a)
       let src: index = base + as(index, b)
       L.stack[dst] = L.stack[src]
       jump next(frame = frame, pc = pc + 1, base = base, top = top)
   end
   end
   ```

2. **Lines 27-45**: `op_loadk` — load constant
   ```moonlift
   region op_loadk(
       L: ptr(LuaThread),
       frame: ptr(Frame),
       pc: index,
       base: index,
       top: index,
       a: u16,
       b: u16,
       c: u16,
       bx: u32,
       sbx: i32;
       next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
   entry start()
       let dst: index = base + as(index, a)
       let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
       -- bx indexes into the constant table
       L.stack[dst] = cl.proto.constants[bx]
       jump next(frame = frame, pc = pc + 1, base = base, top = top)
   end
   end
   ```

3. **Lines 47-140**: Representative handlers for each opcode class
   - `op_loadbool`, `op_loadnil` (lines 47-65)
   - `op_getupval` (lines 67-85) — read from upvalue
   - `op_getglobal` (lines 87-110) — read from global table
   - `op_gettable` (lines 112-145) — table access, may call metamethod
   - `op_setglobal`, `op_setupval`, `op_settable` (lines 147-195)
   - `op_newtable` (lines 197-215)
   - `op_self` (lines 217-240)
   - `op_add` through `op_pow` (lines 242-290) — arithmetic with binop_dispatch
   - `op_unm`, `op_not`, `op_len` (lines 292-330)
   - `op_concat` (lines 332-360)
   - `op_jmp` (lines 362-375)
   - `op_eq`, `op_lt`, `op_le` (lines 377-420)
   - `op_test`, `op_testset` (lines 422-450)
   - `op_call` (lines 452-480) — the critical call opcode
   - `op_tailcall` (lines 482-510)
   - `op_return` (lines 512-540)
   - `op_forloop`, `op_forprep` (lines 542-575)
   - `op_tforloop` (lines 577-600)
   - `op_setlist` (lines 602-630)
   - `op_close` (lines 632-645)
   - `op_closure` (lines 647-680)
   - `op_vararg` (lines 682-710)

**Representative handler: `op_gettable`**:
```moonlift
region op_gettable(
    L: ptr(LuaThread),
    frame: ptr(Frame),
    pc: index,
    base: index,
    top: index,
    a: u16,
    b: u16,
    c: u16,
    bx: u32,
    sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    error: cont(code: i32),
    oom: cont())
entry start()
    let tbl: Value = L.stack[base + as(index, b)]
    let key: Value = L.stack[base + as(index, c)]
    -- Commit state for possible re-entry
    frame.pc = pc
    L.top = top
    emit table_get(L, tbl, key;
        value = got_value,
        call_mm = do_mm,
        type_error = type_err,
        loop_error = loop_err,
        oom = out_of_mem)
end
block got_value(v: Value)
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block do_mm(mm: Value, self: Value, key: Value)
    -- Prepare __index metamethod call
    L.stack[base] = mm
    L.stack[base + 1] = self
    L.stack[base + 2] = key
    emit prepare_call(L, base, 2, 1, @{RESUME_GETTABLE_MM};
        enter_lua = do_lua,
        enter_native = do_native,
        returned = mm_returned,
        yielded = mm_yielded,
        error = call_err,
        oom = out_of_mem)
end
block do_lua(child: ptr(Frame))
    child.resume_a = as(u16, a)
    child.resume_pc = pc
    jump enter_lua(child = child)
end
block do_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
end
block mm_returned(nres: i32)
    -- Get result from stack at base
    let v: Value = L.stack[base]
    L.stack[base + as(index, a)] = v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block mm_yielded(nres: i32)
    jump enter_lua(child = ???) -- Hmm, yielded doesn't return through enter_lua
end
block type_err()
    jump error(code = @{ERR_INDEX})
end
block loop_err()
    jump error(code = @{ERR_LOOP})
end
block call_err(code: i32)
    jump error(code = code)
end
block out_of_mem()
    jump oom()
end
end
```

**Total**: ~720 lines

**Danger zones**:
- The `mm_yielded` block: when a metamethod call yields, control returns through the thread's resume mechanism, not through `enter_lua`. This requires `yielded` continuation — the handler must be able to exit through `yielded`, which the `op_gettable` signature above doesn't show. **Add `yielded: cont(nres: i32)` to op_gettable and all handlers that can call metamethods**.
- Every opcode that modifies the stack must ensure stack bounds are checked (via `stack_check` or preconditions).
- `op_call` must handle the `nres = 0` case (all returns discarded) and `nres = -1` (multret).
- `op_return` must handle `b = 0` (return top of stack) and `b = 1` (return nothing).

---

#### `experiments/lua_interpreter_vm/src/vm_loop.mlua`

**Goal**: Define `vm_resume`, `vm_loop`, `commit_vm_state`, and `dispatch_instruction`.

**Edit blocks**:

1. **Lines 1-40**: `vm_resume` — entry point from API or coroutine resume
   ```moonlift
   region vm_resume(
       L: ptr(LuaThread),
       nargs: i32;
       ok: cont(nres: i32),
       yielded: cont(nres: i32),
       runtime_error: cont(code: i32),
       oom: cont())
   entry start()
       -- Ensure we have at least one frame (the initial call frame)
       if L.frame_count == 0 then
           jump runtime_error(code = @{ERR_RUNTIME})
       end
       L.status = @{THREAD_OK}
       emit vm_loop(L;
           finished = do_finish,
           yielded = do_yield,
           error = do_error,
           oom = out_of_mem)
   end
   block do_finish(nres: i32)
       L.status = @{THREAD_DEAD}
       jump ok(nres = nres)
   end
   block do_yield(nres: i32)
       L.status = @{THREAD_YIELDED}
       jump yielded(nres = nres)
   end
   block do_error(code: i32)
       L.status = @{THREAD_RUNTIME_ERROR}
       jump runtime_error(code = code)
   end
   block out_of_mem()
       L.status = @{THREAD_OOM}
       jump oom()
   end
   end
   ```

2. **Lines 42-100**: `vm_loop` — the main interpreter loop
   ```moonlift
   region vm_loop(
       L: ptr(LuaThread);
       finished: cont(nres: i32),
       yielded: cont(nres: i32),
       error: cont(code: i32),
       oom: cont())
   entry start()
       -- Get top frame
       if L.frame_count == 0 then
           jump finished(nres = 0)
       end
       let frame: ptr(Frame) = L.frames + (L.frame_count - 1)
       let pc: index = frame.pc
       let base: index = frame.base
       let top: index = frame.top
       jump loop(frame = frame, pc = pc, base = base, top = top)
   end
   block loop(frame: ptr(Frame), pc: index, base: index, top: index)
       -- Commit VM state before dispatch
       emit commit_vm_state(L, frame, pc, top;
           done = dispatch)
   end
   block dispatch()
       emit dispatch_instruction(L, frame, pc, base, top;
           next = cont_loop,
           jump = cont_jump,
           enter_lua = do_lua,
           enter_native = do_native,
           returned = do_returned,
           yielded = do_yielded,
           error = do_error,
           oom = out_of_mem)
   end
   block cont_loop(frame: ptr(Frame), pc: index, base: index, top: index)
       jump loop(frame = frame, pc = pc, base = base, top = top)
   end
   block cont_jump(frame: ptr(Frame), pc: index, base: index, top: index)
       jump loop(frame = frame, pc = pc, base = base, top = top)
   end
   block do_lua(child: ptr(Frame))
       jump loop(frame = child, pc = child.pc, base = child.base, top = child.top)
   end
   block do_native(cl: ptr(CClosure))
       -- Get current frame for return context
       let frame: ptr(Frame) = L.frames + (L.frame_count - 1)
       let nargs: i32 = as(i32, frame.top - frame.base)
       emit call_native(L, cl, nargs, frame.wanted;
           returned = native_return,
           yielded = do_yielded,
           error = do_error,
           oom = out_of_mem)
   end
   block native_return(nres: i32)
       -- Pop frame and handle return
       -- ...
       jump do_error(code = @{ERR_RUNTIME})
   end
   block do_returned(nres: i32)
       jump finished(nres = nres)
   end
   block do_yielded(nres: i32)
       jump yielded(nres = nres)
   end
   block do_error(code: i32)
       jump error(code = code)
   end
   block out_of_mem()
       jump oom()
   end
   end
   ```

3. **Lines 102-115**: `commit_vm_state` region
   ```moonlift
   region commit_vm_state(
       L: ptr(LuaThread),
       frame: ptr(Frame),
       pc: index,
       top: index;
       done: cont())
   entry start()
       -- Write hot state back to frame/LuaThread
       frame.pc = pc
       frame.top = top
       L.top = top
       jump done()
   end
   end
   ```

4. **Lines 117-200**: `dispatch_instruction` region (can be generated by opcodes.lua)
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
   entry decode()
       -- Fetch and decode instruction at pc
       let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
       let code_ptr: ptr(Instr) = cl.proto.code + pc
       let instr: Instr = *code_ptr
       let a: u16 = instr.a
       let b: u16 = instr.b
       let c: u16 = instr.c
       let bx: u32 = instr.bx
       let sbx: i32 = instr.sbx
       
       switch instr.op
           -- Each case emits the corresponding opcode handler
           case @{OP_MOVE} then
               emit op_move(L, frame, pc, base, top, a, b, c, bx, sbx;
                   next = do_next,
                   jump = do_jump,
                   enter_lua = do_lua,
                   enter_native = do_native,
                   returned = do_returned,
                   yielded = do_yielded,
                   error = do_error,
                   oom = do_oom)
           case @{OP_LOADK} then
               emit op_loadk(...; next = do_next, ...)
           -- ... all 39 opcodes
           default then
               jump error(code = @{ERR_BAD_OPCODE})
           end
   end
   -- Continuation blocks (wired to dispatch_instruction's signature)
   block do_next(frame: ptr(Frame), pc: index, base: index, top: index)
       jump next(frame = frame, pc = pc, base = base, top = top)
   end
   block do_jump(frame: ptr(Frame), pc: index, base: index, top: index)
       jump jump(frame = frame, pc = pc, base = base, top = top)
   end
   block do_lua(child: ptr(Frame))
       jump enter_lua(child = child)
   end
   block do_native(cl: ptr(CClosure))
       jump enter_native(cl = cl)
   end
   block do_returned(nres: i32)
       jump returned(nres = nres)
   end
   block do_yielded(nres: i32)
       jump yielded(nres = nres)
   end
   block do_error(code: i32)
       jump error(code = code)
   end
   block do_oom()
       jump oom()
   end
   end
   ```

**Total**: ~210 lines

**Danger zone**: The `vm_loop` block's `enter_native` continuation creates a problem — when a native call returns, which frame is active? The return must come back through `do_native`'s block. This requires `call_native` to return to a specific continuation that re-enters `vm_loop`. The simplest approach: have `call_native` return through a `returned` continuation that adjusts the frame, then jumps back into `loop`.

---

### Step 5: Tables & Strings

#### `experiments/lua_interpreter_vm/src/regions_table.mlua`

**Goal**: Define all table access regions (`table_raw_get`, `table_raw_set`, `table_get`, `table_set`, `table_next`, `table_resize`).

**Edit blocks**: ~300 lines

1. **Lines 1-45**: `table_raw_get` — direct array or hash lookup
2. **Lines 47-95**: `table_raw_set` — direct array or hash store
3. **Lines 97-165**: `table_get` — raw_get → miss → get_metamethod
4. **Lines 167-235**: `table_set` — raw_set → miss → get_metamethod
5. **Lines 237-270**: `table_next` — table iteration (pairs/next)
6. **Lines 272-310**: `table_resize` — resize array/hash parts

**Key patterns**:
- Hash lookup: `slot = hash(key) & node_mask`, then traverse chain via `Node.next`
- Array lookup: if `key` is integer in `[1, array_len]`, probe `array[key-1]`
- Nil values in nodes mean absent entries
- Write barrier must be called after every collectable write

---

#### `experiments/lua_interpreter_vm/src/regions_string.mlua`

**Goal**: Define string interning, hashing, and concatenation regions.

**Edit blocks**: ~180 lines

1. **Lines 1-30**: `string_hash` — compute Lua string hash
2. **Lines 32-80**: `string_intern` — find or create interned string
3. **Lines 82-140**: `string_concat_range` — concatenate a range of stack values

**Key patterns**:
- Hash function matches Lua 5.1's string hash
- Interning uses `StringTable` with bucket lists
- Concatenation checks for __concat metamethod on any operand

---

### Step 6: Upvalues & Closures

#### `experiments/lua_interpreter_vm/src/regions_upvalue.mlua`

**Goal**: Define upvalue management regions.

**Edit blocks**: ~150 lines

1. **Lines 1-50**: `find_upvalue` — locate or create open upvalue for a stack slot
2. **Lines 52-90**: `close_upvalues` — close all upvalues at or above a stack index
3. **Lines 92-150**: `make_lclosure` — create an LClosure with upvalues

**Key patterns**:
- Open upvalues point into the stack (`v = &stack[idx]`)
- Closing copies the value to `upval.closed` and points `v` to `&closed`
- `next_open` linked list chains all open upvalues per thread
- `close_upvalues` is called on RETURN, CLOSE opcode, and scope exit

---

### Step 7: Metamethods

#### `experiments/lua_interpreter_vm/src/regions_metamethod.mlua`

**Goal**: Define metamethod lookup, binary/unary dispatch, and metamethod call preparation.

**Edit blocks**: ~250 lines

1. **Lines 1-50**: `get_metamethod` — lookup metamethod from any value's metatable
2. **Lines 52-90**: `get_table_metamethod` — lookup from table's metatable (uses `flags` cache)
3. **Lines 92-150**: `binop_dispatch` — check if both operands are numbers (fast path), otherwise call metamethod
4. **Lines 152-190**: `unop_dispatch` — same for unary ops
5. **Lines 192-250**: `prepare_metamethod_call` — set up stack for metamethod invocation

**Key patterns**:
- Negative cache: `Table.flags` has bits set per TM event when the metatable lacks that event
- `get_table_metamethod` checks `flags` before accessing metatable
- `binop_dispatch` for arithmetic: if both values are numbers, take fast path; otherwise check both operands' metatables for the TM event

---

### Step 8: Protected Calls & Coroutines

#### `experiments/lua_interpreter_vm/src/regions_error.mlua`

**Goal**: Define error handling and protected call regions.

**Edit blocks**: ~200 lines

1. **Lines 1-35**: `build_error_object` — construct a Value error object
2. **Lines 37-90**: `raise_error` — unwind frames looking for ProtectedFrame
3. **Lines 92-115**: `enter_protected` — push a ProtectedFrame
4. **Lines 117-130**: `leave_protected` — pop a ProtectedFrame
5. **Lines 132-200**: `protected_call` — implement pcall/xpcall

**Key patterns**:
- `raise_error` walks the frame array top-down, checking each frame's `protected_top`
- If found, rewind state and jump to handler block
- If not found, exit through `uncaught`
- `protected_call` wraps `prepare_call` with a ProtectedFrame

---

#### `experiments/lua_interpreter_vm/src/regions_coroutine.mlua`

**Goal**: Define coroutine yield and resume regions.

**Edit blocks**: ~150 lines

1. **Lines 1-80**: `coroutine_resume` — resume a LuaThread from another LuaThread
2. **Lines 82-150**: `coroutine_yield` — yield from current coroutine

**Key patterns**:
- `coroutine_yield` saves thread state (stack, frames, open_upvals) in the thread
- Returns through `yielded` continuation
- `coroutine_resume` checks target thread status before resuming
- Yield is not an error — it's a named VM exit

---

### Step 9: GC

#### `experiments/lua_interpreter_vm/src/regions_gc.mlua`

**Goal**: Define GC protocol regions (allocation, marking, sweeping, barriers).

**Edit blocks**: ~200 lines

1. **Lines 1-35**: `alloc_object` — attempt allocation, trigger GC if debt exceeds
2. **Lines 37-55**: `gc_check` — check if GC step is needed
3. **Lines 57-75**: `gc_step` — one atomic GC step
4. **Lines 77-105`: `mark_value` — mark an object from a Value reference
5. **Lines 107-130**: `mark_object` — mark an object from a GCHeader pointer
6. **Lines 132-155**: `propagate_gray` — process gray objects
7. **Lines 157-180**: `sweep_step` — sweep one page of objects
8. **Lines 182-210**: `write_barrier` — barrier after write into black container

---

#### `experiments/lua_interpreter_vm/src/gc_impl.mlua`

**Goal**: The full incremental GC algorithm implementation.

**Edit blocks**: ~300 lines

1. **Lines 1-80**: GC state machine dispatch in `gc_step`
   - `GCSTATE_PAUSE`: mark all roots → transition to PROPAGATE
   - `GCSTATE_PROPAGATE`: `propagate_gray` → transition to SWEEP when gray list empty
   - `GCSTATE_SWEEP`: `sweep_step` → transition to PAUSE when done
   - `GCSTATE_FINALIZE`: finalize userdata

2. **Lines 82-150**: Root marking — mark registry, main thread, stacks, frames, metatables
3. **Lines 152-220**: Object scanning by type — `mark_object` dispatches on `tt`
4. **Lines 222-280**: `sweep_step` — iterates `allgc` list, frees white objects, keeps gray/black
5. **Lines 282-310**: `write_barrier` and `write_barrier_back` — barrier protocols

**Key patterns**:
- Tri-color marking: white (unmarked), gray (marked with unmarked children), black (marked with marked children)
- `currentwhite` toggles between `COLOR_WHITE0` and `COLOR_WHITE1` between sweeps
- Write barrier: if parent is black and child is white, mark child gray
- Atomic sweepphase finalizer calls

---

### Step 10: API Sealing

#### `experiments/lua_interpreter_vm/src/regions_api.mlua`

**Goal**: Internal `api_index_to_addr` decoder plus all sealed API region implementations.

**Edit blocks**: ~200 lines

1. **Lines 1-50**: `api_index_to_addr` — decode Lua C API index conventions
2. **Lines 52-90**: Internal region bodies for each API operation
   - `api_type` — return type code for value at index
   - `api_settop` — set top of stack
   - `api_pushvalue` — push value at index
   - `api_gettable` — get table[index]
   - `api_settable` — set table[index]

---

#### `experiments/lua_interpreter_vm/src/api.lua` (or `api.mlua`)

**Goal**: Sealed C-compatible API functions that wrap internal regions.

**Edit blocks**: ~250 lines

Each API function is a `func` (not a region) — it's an external boundary:

```moonlift
func lua_type_api(L: ptr(LuaThread), idx: i32) -> i32
    -- Decode idx, return type constant
    return as(i32, @{TAG_NIL})
end

func lua_settop_api(L: ptr(LuaThread), idx: i32) -> void
    -- Set stack top
    return
end

func lua_pcall_api(L: ptr(LuaThread), nargs: i32, nresults: i32, errfunc: i32) -> i32
    -- Protected call entry point
    return @{ERR_NONE}
end
```

---

### Step 11: Quickening

#### `experiments/lua_interpreter_vm/src/quickening.mlua`

**Goal**: Quickened opcode families, inline cache probing, quickening/deopt protocols.

**Edit blocks**: ~250 lines

1. **Lines 1-30**: `probe_gettable_cache` — check inline cache hit
2. **Lines 32-80**: `quicken_instruction` — patch a generic opcode to quickened form
3. **Lines 82-110**: `deopt_instruction` — revert to generic opcode
4. **Lines 112-250**: Quickened opcode handler bodies (GETTAB_ARRAY, SETTAB_STR_SLOT, etc.)

#### `experiments/lua_interpreter_vm/src/validate.mlua`

**Goal**: `validate_proto` trust boundary — verify Proto before execution.

**Edit blocks**: ~100 lines

```moonlift
region validate_proto(
    L: ptr(LuaThread),
    p: ptr(Proto);
    ok: cont(),
    invalid: cont(code: i32),
    oom: cont())
entry start()
    -- Validate code bounds, register indices, constant indices, jump targets
    -- Recurse into children
    jump ok()
end
end
```

---

### Final: `init.lua`

#### `experiments/lua_interpreter_vm/src/init.lua`

**Goal**: Load all submodules and return the VM table.

**Edit blocks**:
1. **Lines 1-15**: Path setup and module loading
   ```lua
   -- Moonlift Lua Interpreter VM — Module loader
   package.path = "./experiments/lua_interpreter_vm/src/?.lua;./experiments/lua_interpreter_vm/src/?.mlua;" .. package.path

   local vm = {}

   -- Step 1: Products and constants
   vm.const = require("experiments.lua_interpreter_vm.src.constants")
   vm.products = require("experiments.lua_interpreter_vm.src.products")

   -- Step 2: Value and stack regions
   vm.regions_value = require("experiments.lua_interpreter_vm.src.regions_value")
   vm.regions_stack = require("experiments.lua_interpreter_vm.src.regions_stack")

   -- ... and so on

   return vm
   ```

---

## New Files Summary

| # | File | Type | ~Lines | Dependencies |
|---|------|------|--------|-------------|
| 1 | `constants.mlua` | Lua+Moonlift | 210 | None |
| 2 | `products.mlua` | Moonlift structs | 440 | constants |
| 3 | `regions_value.mlua` | Moonlift regions | 300 | products, constants |
| 4 | `regions_stack.mlua` | Moonlift regions | 160 | products, constants |
| 5 | `regions_call.mlua` | Moonlift regions | 240 | regions_value, regions_stack, regions_upvalue |
| 6 | `opcodes.lua` | Lua generator | 170 | constants |
| 7 | `opcodes_gen.mlua` | Generated Moonlift | 500 | opcodes, products |
| 8 | `op_handlers.mlua` | Moonlift regions | 720 | opcodes_gen, regions_table, regions_call |
| 9 | `vm_loop.mlua` | Moonlift regions | 210 | opcodes_gen, op_handlers |
| 10 | `regions_table.mlua` | Moonlift regions | 310 | products, constants |
| 11 | `regions_string.mlua` | Moonlift regions | 180 | products, regions_table |
| 12 | `regions_upvalue.mlua` | Moonlift regions | 150 | products, regions_stack |
| 13 | `regions_metamethod.mlua` | Moonlift regions | 250 | regions_table, regions_call |
| 14 | `regions_error.mlua` | Moonlift regions | 200 | regions_call |
| 15 | `regions_coroutine.mlua` | Moonlift regions | 150 | regions_call, regions_error |
| 16 | `regions_gc.mlua` | Moonlift regions | 200 | products, constants |
| 17 | `gc_impl.mlua` | Moonlift regions | 300 | regions_gc |
| 18 | `regions_api.mlua` | Moonlift regions | 200 | products, regions_stack |
| 19 | `api.mlua` | Moonlift funcs | 250 | regions_api |
| 20 | `quickening.mlua` | Moonlift regions | 250 | products, opcodes_gen |
| 21 | `validate.mlua` | Moonlift regions | 100 | products |
| 22 | `init.lua` | Lua loader | 40 | All modules |

**Total**: ~4,600 lines of source code

---

## Order of Operations

The worker should follow this exact sequence:

### Phase A: Scaffold
1. Create `experiments/lua_interpreter_vm/src/` directory
2. Write `constants.mlua` — all constant tables
3. Write `products.mlua` — all struct definitions in topo-sorted order

### Phase B: Core regions (steps 2-3)
4. Write `regions_value.mlua` — value protocols (truth, type checks, comparisons)
5. Write `regions_stack.mlua` — stack_check, frame_push, frame_pop, adjust_results, adjust_varargs
6. Write `regions_upvalue.mlua` — find_upvalue, close_upvalues, make_lclosure (needed by call/return)
7. Write `regions_call.mlua` — prepare_call, try_call_metamethod, call_native, return_from_lua, handle_return_mode

### Phase C: Opcodes + VM loop (step 4)
8. Write `vm_loop.mlua` — vm_resume, vm_loop, commit_vm_state
9. Write `opcodes.lua` — Lua generation tables
10. **Generate**: Run `luajit opcodes.lua > opcodes_gen.mlua` to create the generated opcode file
11. Write `op_handlers.mlua` — all 39 opcode handler region bodies

### Phase D: Tables, strings, metamethods (steps 5-7)
12. Write `regions_string.mlua` — string_hash, string_intern, string_concat_range
13. Write `regions_table.mlua` — table_raw_get/set, table_get/set, table_next, table_resize
14. Write `regions_metamethod.mlua` — get_metamethod, get_table_metamethod, binop_dispatch, unop_dispatch, prepare_metamethod_call

### Phase E: Errors, coroutines, GC (steps 8-9)
15. Write `regions_error.mlua` — build_error_object, raise_error, enter/leave_protected, protected_call
16. Write `regions_coroutine.mlua` — coroutine_resume, coroutine_yield
17. Write `regions_gc.mlua` — alloc_object, gc_check, gc_step, mark_value, mark_object, propagate_gray, sweep_step, write_barrier, write_barrier_back
18. Write `gc_impl.mlua` — full GC algorithm implementation

### Phase F: API + Quickening (steps 10-11)
19. Write `regions_api.mlua` — api_index_to_addr, internal API helpers
20. Write `api.mlua` — sealed C-compatible API functions
21. Write `validate.mlua` — validate_proto trust boundary
22. Write `quickening.mlua` — inline caches, quicken/deopt protocols

### Phase G: Assembly
23. Write `init.lua` — module loader that requires all submodules

---

## Testing Strategy

### Incremental verification after each phase:

**After Phase A**: 
- Verify all struct definitions compile by loading `products.mlua` through the Moonlift compiler
- Check that `ptr(ptr(Proto))` and `ptr(ptr(String))` types are accepted
- Verify all constant values match Lua 5.1 opcode numbering

**After Phase B**:
- Test `value_truth` with TAG_NIL, TAG_FALSE, TAG_TRUE, TAG_NUM values
- Test `stack_check` with known sizes
- Test `frame_push`/`frame_pop` roundtrip

**After Phase C (first significant milestone!)**:
- Create a minimal test: load a simple Proto for `MOVE` + `RETURN`, run `vm_resume`, verify it completes with `ok(0)`
- This is the "hello world" test for the VM

**After Phase D**:
- Test `table_raw_get`/`table_raw_set` with array and hash parts
- Test `string_intern` roundtrip
- Test `op_gettable`/`op_settable` with a simple Proto

**After Phase E**:
- Test `op_call` with a Lua closure
- Test `protected_call` (pcall equivalent)
- Test `raise_error` caught by ProtectedFrame

**After Phase F**:
- Test `lua_pcall_api` as a sealed entry point
- Test `validate_proto` on valid and invalid Protos

### Test files to create alongside:

- `experiments/lua_interpreter_vm/tests/test_vm_hello.mlua` — MOVE + RETURN
- `experiments/lua_interpreter_vm/tests/test_vm_arith.mlua` — arithmetic operations
- `experiments/lua_interpreter_vm/tests/test_vm_table.mlua` — table operations
- `experiments/lua_interpreter_vm/tests/test_vm_call.mlua` — function calls
- `experiments/lua_interpreter_vm/tests/test_vm_pcall.mlua` — protected calls

---

## Pattern Memo

### Struct conventions:
- Every collectable struct begins with `gc: GCHeader`
- All struct fields use typed scalars (`u32`, `index`, `i32`, `u16`, `u8`, `f64`)
- Pointer fields use `ptr(T)` syntax
- No `union` types — use separate tags + `bits` field pattern (like `Value`)

### Region conventions:
- Regions use semicolon-separated parameter/continuation lists
- Entry block is always named `start()` unless there's a reason to name it differently
- Continuation names use snake_case matching the README
- Each block terminates with `jump` or `yield` or `return` — never fallthrough
- Switch always has `default` arm

### Emit conventions:
- `emit region(args; cont = target_block, ...)` — named continuation mapping
- Continuation names are the lowercase versions of the README protocol names

### Constants usage:
- ALL constants are Lua splices: `@{TAG_NIL}`, `@{OP_MOVE}`, `@{RESUME_NORMAL}`
- Splices are loaded from the `constants` module: `local TAG_NIL = const.Tag.NIL`

### Pointer arithmetic:
- `L.frames + idx` to index into frame array (verify Moonlift support)
- `L.stack + idx` to index into value stack
- `*ptr` to dereference

### Error propagation:
- Regions that can error expose `error: cont(code: i32)` and `oom: cont()` continuations
- Every call site must handle both — no silent error swallowing
- `raise_error` is the ONLY path for runtime errors

### GC barriers:
- Every write of a collectable value into a table/upvalue/stack slot must go through `write_barrier`
- The barrier is called AFTER the write: `write_barrier(G, parent_header, child_value)`
