# SpongeJIT / Moonlift Lua VM Garbage Collection Design

## Purpose

Design garbage collection as a first-class Moonlift subsystem for the
Moonlift-native Lua VM, SpongeJIT semantic lowering, FFI cdata/finalizers, fact
collection, and copy-and-patch stencils.

GC is not an allocator detail. Allocation, barriers, finalization, weak tables,
object colors, epochs, and invalidation are Lua VM semantics and must be typed
explicitly.

This document follows explicit programming:

- data types first: every object, color, phase, barrier, root, finalizer, and
  allocation result is a struct or union;
- control types second: allocation, marking, sweeping, barriers, finalization,
  and collection steps are regions with typed continuations;
- no hidden global collector state except explicit `GCState` passed through
  regions;
- no boolean success returns where typed outcomes belong.

---

## One-sentence architecture

The Lua VM owns a Moonlift GC whose typed allocation and barrier protocols are
part of LuaExec/MoonCFG semantics; SpongeJIT facts and stencil contracts depend
on GC epochs/barrier state; FFI finalizers and cdata ownership enter the same GC
finalization protocol.

```text
Lua allocation / mutation / FFI ownership
  -> GC allocation and barrier regions
  -> object graph + epochs + finalizer queues
  -> LuaExec/MoonCFG semantic regions
  -> stencil contracts/facts
  -> runtime invalidation when GC/layout/epoch facts change
```

---

# Data tree

## Object headers

Every collectable object begins with a typed header.

```moonlift
union GCColor
    white0()
  | white1()
  | gray()
  | black()
  | fixed()
  | dead()
end

union GCObjectKind
    string()
  | table()
  | closure()
  | proto()
  | thread()
  | userdata()
  | cdata()
  | upvalue()
end

struct GCHeader
    next: ptr(GCHeader)
    kind: GCObjectKind
    color: GCColor
    flags: u32
    epoch: u64
end
```

`kind` and `color` are unions conceptually. If lowered to compact integer tags,
the mapping is generated from the union, not hand-commented magic numbers.

## GC state

```moonlift
union GCPhase
    pause()
  | propagate()
  | atomic()
  | sweep_string()
  | sweep_objects()
  | call_finalizers()
end

struct GCLimits
    pause_debt: i64
    step_multiplier: i32
    emergency_threshold: u64
end

struct GCLists
    all: ptr(GCHeader)
    gray: ptr(GCHeader)
    gray_again: ptr(GCHeader)
    weak_tables: ptr(GCHeader)
    ephemeron_tables: ptr(GCHeader)
    finalizable: ptr(GCHeader)
    to_finalize: ptr(GCHeader)
end

struct GCState
    phase: GCPhase
    current_white: GCColor
    lists: GCLists
    total_bytes: u64
    debt: i64
    limits: GCLimits
    global_epoch: u64
    barrier_epoch: u64
    allocator: Allocator
end
```

`GCState` is passed explicitly to regions that allocate, mutate collectable
references, step the collector, or run finalizers.

## Allocator

```moonlift
struct Allocator
    ctx: ptr(u8)
    alloc_fn: func(ptr(u8), u64, u32) -> ptr(u8)
    realloc_fn: func(ptr(u8), ptr(u8), u64, u64, u32) -> ptr(u8)
    free_fn: func(ptr(u8), ptr(u8), u64, u32) -> void
end
```

Allocator behavior is explicit. Raw libc allocation can be wrapped behind this
interface but is not hidden in allocation sites.

## Collectable object sketches

```moonlift
struct TString
    gc: GCHeader
    hash: u64
    len: u64
    bytes: ptr(u8)
end

struct Table
    gc: GCHeader
    shape: u64
    metatable: ptr(Table)
    array: ptr(TValue)
    array_len: u64
    hash_part: ptr(TableNode)
    hash_len: u64
    table_epoch: u64
    shape_epoch: u64
end

struct LClosure
    gc: GCHeader
    proto: ptr(Proto)
    upvalues: ptr(ptr(Upvalue))
    nupvalues: u32
end

struct Userdata
    gc: GCHeader
    metatable: ptr(Table)
    data: ptr(u8)
    len: u64
    finalizer: FinalizerRef
end

struct CDataObject
    gc: GCHeader
    ctype: CTypeId
    storage: CStorage
    finalizer: CFinalizerId
end
```

Exact object layout belongs to the VM layout design, but every layout must start
from explicit typed fields like these.

## TValue and GC references

```moonlift
union TValueTag
    nil()
  | bool()
  | i64()
  | f64()
  | string()
  | table()
  | closure()
  | userdata()
  | cdata()
  | thread()
  | lightuserdata()
end

struct TValue
    tag: TValueTag
    payload: u64
end

union GCRef
    none()
  | object(ptr(GCHeader))
end
```

`TValue` contains references to collectable objects through its tag/payload
contract. GC traversal must use typed projection helpers, not ad-hoc tag tests
scattered everywhere.

## Roots

```moonlift
union RootKind
    stack_slot(thread: ptr(LuaThread), slot: u32)
  | registry()
  | global_table()
  | metatable_cache()
  | open_upvalue(ptr(Upvalue))
  | c_callback(CCallbackId)
  | jit_materialized_code(TemplateId)
end

struct GCRoot
    kind: RootKind
    value: GCRef
end

struct RootSet
    roots: view(GCRoot)
end
```

JIT/materialized code can be a root if it holds object references or callback
thunks. If code only holds patch addresses, those patch values still need typed
root/invalidation representation.

## Barriers

```moonlift
union BarrierKind
    object_to_object(parent: ptr(GCHeader), child: ptr(GCHeader))
  | table_slot(table: ptr(Table), value: TValue)
  | upvalue_write(upvalue: ptr(Upvalue), value: TValue)
  | cdata_ref(owner: ptr(CDataObject), child: ptr(GCHeader))
end

union BarrierAction
    no_action()
  | mark_child(child: ptr(GCHeader))
  | regray_parent(parent: ptr(GCHeader))
  | enqueue_gray_again(parent: ptr(GCHeader))
end
```

Barriers are semantic write obligations. A table write is incomplete if its GC
barrier behavior is not represented.

## Finalizers

```moonlift
union FinalizerKind
    lua_gc_metamethod(method: TValue)
  | ffi_c_finalizer(symbol: CSymbolId)
  | ffi_lua_finalizer(ref: u64)
  | userdata_finalizer(method: TValue)
end

struct FinalizerRef
    kind: FinalizerKind
    attached: bool
end

union FinalizerResult
    completed()
  | yielded()
  | error(code: u32)
end
```

FFI `ffi.gc` and Lua `__gc` enter the same finalization control surface.

## GC facts for JIT/stencil selection

```moonlift
union GCFact
    barrier_clean(subject: FactSubject)
  | object_epoch(object: ptr(GCHeader), epoch: u64)
  | table_epoch(table: ptr(Table), epoch: u64)
  | shape_epoch(shape: u64, epoch: u64)
  | gc_phase(phase: GCPhase)
  | no_finalizer(object: ptr(GCHeader))
  | finalizer_attached(object: ptr(GCHeader))
end
```

These facts are selection/invalidation facts, not substitutes for barrier or
finalizer semantics.

---

# Control tree

## Allocation

Allocation is a typed region with GC interaction.

```moonlift
region gc_alloc(
    gc: ptr(GCState),
    kind: GCObjectKind,
    size: u64,
    align: u32;

    allocated: cont(object: ptr(GCHeader)),
    step_required: cont(debt: i64),
    out_of_memory: cont(size: u64),
    emergency_collect_required: cont())
```

A caller that receives `step_required` must either perform a GC step or forward
that continuation. It cannot silently allocate through raw libc.

## Collector stepping

```moonlift
region gc_step(gc: ptr(GCState), budget: u64;
    progressed: cont(remaining_budget: u64),
    completed_cycle: cont(),
    finalizers_pending: cont(count: u64),
    out_of_memory: cont())
```

The phase-specific steps are regions:

```moonlift
region gc_mark_roots(gc: ptr(GCState), roots: RootSet;
    marked: cont(),
    root_error: cont(root: RootKind))

region gc_propagate_one(gc: ptr(GCState);
    propagated: cont(),
    gray_empty: cont())

region gc_atomic(gc: ptr(GCState), roots: RootSet;
    done: cont(),
    finalizers_found: cont(count: u64))

region gc_sweep_step(gc: ptr(GCState), budget: u64;
    swept: cont(remaining_budget: u64),
    sweep_done: cont())
```

## Mark traversal

```moonlift
region mark_value(gc: ptr(GCState), value: TValue;
    marked: cont(),
    non_collectable: cont())

region mark_object(gc: ptr(GCState), object: ptr(GCHeader);
    already_marked: cont(),
    enqueued_gray: cont(),
    fixed_object: cont())

region traverse_object(gc: ptr(GCState), object: ptr(GCHeader);
    traversed: cont(),
    weak_table: cont(table: ptr(Table)),
    finalizable: cont(object: ptr(GCHeader)),
    malformed: cont(code: u32))
```

Object-kind dispatch is a typed branch over `GCObjectKind`, not an opaque helper.

## Write barriers

```moonlift
region gc_write_barrier(
    gc: ptr(GCState),
    barrier: BarrierKind;

    clean: cont(),
    child_marked: cont(child: ptr(GCHeader)),
    parent_regrayed: cont(parent: ptr(GCHeader)),
    barrier_error: cont(code: u32))
```

All Lua table/upvalue/userdata/cdata reference writes emit this region or a
specialized region with the same protocol.

Specialized forms:

```moonlift
region table_write_barrier(gc: ptr(GCState), table: ptr(Table), value: TValue;
    clean: cont(),
    regrayed: cont(table: ptr(Table)),
    error: cont(code: u32))

region upvalue_write_barrier(gc: ptr(GCState), upvalue: ptr(Upvalue), value: TValue;
    clean: cont(),
    regrayed: cont(upvalue: ptr(Upvalue)),
    error: cont(code: u32))
```

## Finalization

```moonlift
region enqueue_finalizer(gc: ptr(GCState), object: ptr(GCHeader), finalizer: FinalizerRef;
    enqueued: cont(),
    no_finalizer: cont(),
    invalid_finalizer: cont())

region run_one_finalizer(gc: ptr(GCState);
    completed: cont(),
    yielded: cont(object: ptr(GCHeader)),
    error: cont(object: ptr(GCHeader), code: u32),
    none_pending: cont())

region run_finalizers(gc: ptr(GCState), budget: u64;
    done: cont(),
    yielded: cont(object: ptr(GCHeader)),
    error: cont(object: ptr(GCHeader), code: u32),
    budget_exhausted: cont())
```

If finalizers can yield in the Lua version being targeted, yield is a typed
continuation. If they cannot, yielding is an explicit error continuation. It is
never hidden.

## Weak tables / ephemerons

```moonlift
region process_weak_table(gc: ptr(GCState), table: ptr(Table);
    processed: cont(),
    resurrected: cont(count: u64),
    malformed: cont(code: u32))

region process_ephemeron_table(gc: ptr(GCState), table: ptr(Table);
    stable: cont(),
    marked_more: cont(count: u64),
    malformed: cont(code: u32))
```

Weakness mode is a typed table/metatable fact, not a hidden string mode.

---

# Integration with Lua semantics

## Allocation-producing Lua operations

These must call/emit GC allocation regions:

- string creation / concat;
- table creation;
- closure creation;
- userdata/cdata creation;
- vararg/multivalue storage that allocates;
- callback/thunk objects;
- any boxed heap value.

Their LuaExec/MoonCFG semantics must include allocation outcomes:

```text
ok / step_required / out_of_memory / error / yield if applicable
```

## Reference writes

These must include GC barriers:

- table raw set;
- table `__newindex` paths that eventually write;
- upvalue writes;
- environment/global writes;
- cdata/userdata reference field writes;
- closure/upvalue initialization if it crosses color invariants.

A fast path can use a `barrier_clean` fact, but the fact must be tied to a
contract/invalidation epoch. The generic path must contain the barrier region.

## Close/finalization interaction

`__close`, `__gc`, FFI finalizers, and error unwinding are separate protocols but
interact. The design must not collapse them into one “run cleanup” helper.

---

# Integration with facts and stencils

GC facts can specialize stencils, but cannot hide GC semantics.

Allowed stencil facts:

- object/table/shape epochs;
- barrier-clean proof;
- GC phase if a fast path requires a phase invariant;
- no-finalizer/finalizer-attached facts;
- allocator layout/version hash.

Stencil contracts must invalidate when:

- shape/table/metatable epoch changes;
- GC barrier protocol version changes;
- object layout changes;
- finalizer state relevant to the stencil changes;
- allocator/VM ABI epoch changes.

Patch holes may include:

- GC state pointer;
- allocator function pointer;
- object layout offsets;
- write barrier region entry address;
- finalizer queue pointer;
- epoch address/expected value.

Patch holes may not mean “skip GC semantics.”

---

# Integration with FFI

FFI cdata participates in GC through explicit ownership/finalizer state.

Required interactions:

- cdata object allocation uses `gc_alloc`;
- `ffi.gc` attaches a typed `FinalizerRef`;
- callbacks are roots while live;
- cdata fields containing GC references require barriers;
- finalizer execution has typed `completed/yielded/error` outcomes;
- C-owned external memory is not traced unless represented by an explicit owner
  object with trace/finalizer protocol.

---

# Fact collector implications

The runtime fact collector may read GC state:

- object kind/color if relevant;
- table/shape/metatable epochs;
- barrier-clean state;
- finalizer presence;
- object layout/version;
- GC phase if required by a tile.

It must not perform collection steps or barriers as part of fact observation.
Fact collection observes; GC regions mutate.

---

# Testing policy

Positive intended behavior tests:

- allocating table/string/cdata produces typed collectable object;
- table write invokes or specializes write barrier correctly;
- GC step moves through typed phases;
- object graph marking reaches expected objects;
- weak table processing follows typed weak-mode semantics;
- finalizer queue runs finalizers with typed outcomes;
- FFI `ffi.gc` finalizer participates in GC;
- stencil fast path with `barrier_clean` fact invalidates when epoch changes;
- materialized code containing GC refs is rooted or invalidated explicitly.

Do not count “rejects allocation” or “missing barrier fact” as completion for
valid Lua behavior.

---

# Forbidden patterns

- raw allocation in Lua semantic paths;
- hidden global GC state accessed outside typed regions;
- write barriers as optional comments or side tables;
- finalizers as untyped callbacks;
- weak table mode as a string checked in random code;
- stencils that skip barriers without a contract fact;
- fact collector mutating GC state;
- GC helper that performs opaque Lua cleanup semantics;
- using FFI finalizers outside GC protocol.

---

# Open design decisions

- Exact collector algorithm: incremental tri-color, generational, or hybrid.
- Exact Lua version semantics for finalizer yield/error behavior.
- Weak table and ephemeron ordering details.
- Object layout finalization for strings/tables/closures/cdata.
- Write barrier variant: forward, backward, or both.
- Emergency collection behavior under allocation failure.
- Per-thread vs global GC state for coroutines/threads.
- Interaction with materialized code cache lifetime.
- Whether some stencil banks are invalidated on every GC cycle or only on
  relevant epoch changes.

---

# Summary

GC is a semantic subsystem, not a backend detail. The design must include a
Moonlift data tree for object headers, collector state, barriers, roots, and
finalizers, plus a control tree for allocation, marking, sweeping, barriers,
weak processing, and finalization. Facts and stencils may specialize GC-related
paths, but they never replace GC semantics.
