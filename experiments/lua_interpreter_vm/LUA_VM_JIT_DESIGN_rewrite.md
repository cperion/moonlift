# Moonlift Lua VM JIT — Full Design Specification

Status: full redesign draft  
Scope: `experiments/lua_interpreter_vm` only  
Non-scope: copy-and-patch as a general Moonlift compiler backend  
Primary mechanism: copy-and-patch runtime materialization over a layered stencil library  
Runtime optimization model: staged `StencilPlan` refinement where runtime generations mirror offline stencil-library layers

---

## 0. Thesis

The Moonlift Lua VM JIT is a **copy-and-patch StencilPlan refinement machine**.

It is not a traditional tower of compiler tiers. It has one runtime code-generation backend:

```text
StencilPlan -> layout -> copy -> stamp -> payload -> fixup -> publish -> link
```

The JIT runtime never invokes Cranelift. It never encodes arbitrary machine instructions. It never mutates `Proto.code`. It never synthesizes new stencil kinds while executing user Lua code.

All expensive code-shape discovery happens offline. The offline pipeline builds a layered stencil library:

```text
L0 = primitive opcode/fact stencils
L1 = bounded-arity closure over L0
L2 = bounded-arity closure over L0..L1
L3 = bounded-arity closure over L0..L2
L4 = bounded-arity closure over L0..L3       -- default speed-max target
L5 = trace-region experimental layer        -- explicit experiment
```

At runtime, a compiled unit carries a `max_layer`. The initial compiled plan uses only `L0`. Each hot refinement pass may raise `max_layer` by one and replan the same anchor using stronger profile/trace facts. Thus runtime tiering is emergent:

```text
unit generation 0 -> selector may use L0
unit generation 1 -> selector may use L0..L1
unit generation 2 -> selector may use L0..L2
unit generation 3 -> selector may use L0..L3
unit generation 4 -> selector may use L0..L4
unit generation 5 -> selector may use L0..L5, trace-region only
```

A unit becomes more optimized by selecting larger and more specialized existing stencil products. The backend remains the same.

The interpreter remains the semantic source of truth. `Proto.code` remains immutable. Effects select projections. Edge cells link and repair compiled control flow.

---

## 1. Design doctrine

### 1.1 The JIT is an explicit-programming system

The JIT is a data tree and a control tree.

Every correctness-relevant distinction must appear as one of:

```text
a typed product
a fact
a dependency
a declared effect
a projection requirement
a continuation outcome
a named region
a materialization artifact
```

If a rule exists only in a comment, convention, callback side effect, raw pointer trick, backend-only relocation, or implicit global table, it is not part of the design yet.

### 1.2 Lua semantics come from the interpreter

The interpreter defines Lua semantics as Moonlift regions and runtime helper regions.

The JIT may specialize, fuse, skip, or redirect work only when it has explicit facts proving that doing so preserves the interpreter-observable behavior.

A `CodeStencil` or `RewriteStencil` is valid only if it implements an interpreter-derived contract:

```text
input state shape
output state shape
effects
exits
projections
dependencies
ABI
clobbers
continuation shape
```

Handwritten stencils may exist during bootstrapping. They are allowed only as implementations of those contracts. They are never semantic authorities.

### 1.3 `Proto.code` is immutable

`Proto.code` is the semantic program.

The JIT does not mutate it:

```text
no quickened Proto.code
no inserted deopt opcodes
no rewritten bytecode stream
no semantic bytecode mutation
```

All adaptive state lives beside the bytecode:

```text
ExecImage
EntryCell
EdgeCell
PlanVersion
ExecutableUnit
UnitProfile
ExitProfile
TraceAnchor
TraceRecord
DependencyIndex
InlineCacheRecord
CodeArena
```

### 1.4 Runtime compilation is materialization

Runtime compilation is:

```text
compute facts
select existing stencil products
layout selected nodes
copy bytes
stamp holes
write payloads
resolve fixups
publish executable memory
link cells
```

Runtime compilation is not:

```text
Cranelift lowering
register allocation over arbitrary IR
general optimization
instruction encoding
full stencil-universe search
runtime stencil generation
```

### 1.5 The refinement ladder mirrors the library ladder

The offline library is built in layers. Runtime plan refinement climbs those same layers.

The runtime does not ask for the best possible shape immediately. A hot unit moves through staged refinements:

```text
PlanVersion 0: L0 only
PlanVersion 1: L0..L1
PlanVersion 2: L0..L2
PlanVersion 3: L0..L3
PlanVersion 4: L0..L4
PlanVersion 5: L0..L5, trace-region experiment
```

The layer is the tier.

---

## 2. Naming and Moonlift notation

This document uses Moonlift-style declarations. Some names are final architectural products; exact field widths may be adjusted in implementation.

Conventions:

```text
ptr(T)      pointer to T
view(T)     length-carrying view of T
index       machine-sized non-negative index
u8/u16/u32/u64 unsigned integers
i32/i64     signed integers
bool        boolean
```

Moonlift control signatures follow this form:

```moonlift
region name(args...;
    success: cont(...),
    failure: cont(...),
    oom: cont())
```

A `region` may have multiple named outcomes. Every caller must bind every continuation. This is used throughout the JIT to make outcomes explicit.

---

## 3. Top-level data products

### 3.1 Primitive aliases

```moonlift
type ByteOffset = u32
type CodeOffset = u32
type SlotIndex = u16
type ConstIndex = u32
type UpvalueIndex = u16
type ProtoIndex = u32
type Pc = u32
type NativePc = u64
type ValueId = u32
type FactId = u32
type DependencyId = u32
type StencilId = u32
type RewriteId = u32
type PlanNodeId = u32
type UnitId = u64
type Generation = u8
type LayerId = u8
type ExitId = u32
type TraceId = u64
type AnchorId = u64
type ProfileCounter = u32
type ShapeEpoch = u64
type CodeSize = u32
```

### 3.2 JIT constants

```moonlift
const MAX_RUNTIME_LAYER: LayerId = 4
const MAX_EXPERIMENTAL_LAYER: LayerId = 5
const STENCIL_CLOSURE_ARITY: u8 = 4
const DEFAULT_HOT_ENTRY_THRESHOLD: ProfileCounter = 64
const DEFAULT_HOT_EXIT_THRESHOLD: ProfileCounter = 16
const MAX_FAILED_REFINEMENTS: u8 = 4
const MAX_PLAN_GENERATION: Generation = 5
```

Meaning:

```text
L0 primitive layer
L1..L4 default speed-max closure layers
L5 trace-region experimental layer
arity 4 means each offline closure step combines up to four current stencil nodes
```

### 3.3 Build mode

```moonlift
union JitBuildMode
    debug()
    dev_fast()
    speed_max()
    size_aware()
    trace_region_lab()
end
```

Meaning:

```text
debug             keep diagnostics, validation, slower paths
dev_fast          generate small subset for fast iteration
speed_max         generate full contract-valid universe through L4
size_aware        ship pruned subset chosen by measured speed/size tradeoff
trace_region_lab  enable L5 trace-region experiments
```

### 3.4 Runtime mode

```moonlift
union ExecutionMode
    interpreter()
    compiled(unit: ptr(ExecutableUnit))
end
```

There is no distinct runtime mode for baseline versus trace. Both are materialized `ExecutableUnit`s. Their difference is in `PlanVersion.source` and `PlanVersion.max_layer`.

### 3.5 Plan source

```moonlift
union PlanSource
    baseline_range(range: SemanticRange)
    trace_record(trace: ptr(TraceRecord))
    side_exit(parent: UnitId, exit_id: ExitId)
    replan(previous: ptr(PlanVersion), reason: RefinementReason)
end
```

---

## 4. Semantic address products

### 4.1 SemanticAddr

A semantic address names a point in the Lua bytecode program.

```moonlift
struct SemanticAddr
    proto: ptr(Proto)
    pc: Pc
end
```

### 4.2 SemanticRange

A semantic range names a bytecode interval within one proto.

```moonlift
struct SemanticRange
    proto: ptr(Proto)
    start_pc: Pc
    end_pc: Pc        -- exclusive
end
```

Invariants:

```text
start_pc <= end_pc
all pcs are within proto.code
range does not cross proto boundary
```

### 4.3 SemanticWindow

A window is a candidate region for stencil matching.

```moonlift
struct SemanticWindow
    range: SemanticRange
    first_pc: Pc
    pc_count: u16
    opcodes: ptr(u16)
    words: ptr(u32)
    flags: u32
end
```

Flags:

```text
straight_line
contains_branch
contains_backedge
contains_call
contains_boundary
contains_side_exit
trace_derived
corpus_observed
```

### 4.4 BytecodeOperand

```moonlift
union BytecodeOperand
    none()
    slot(index: SlotIndex)
    constant(index: ConstIndex)
    upvalue(index: UpvalueIndex)
    immediate_i32(value: i32)
    immediate_i64(value: i64)
    signed_offset(delta: i32)
    proto_index(index: ProtoIndex)
end
```

### 4.5 DecodedInstr

```moonlift
struct DecodedInstr
    addr: SemanticAddr
    word: u32
    opcode: u16
    format: BytecodeFormat
    a: BytecodeOperand
    b: BytecodeOperand
    c: BytecodeOperand
    bx: BytecodeOperand
    sbx: BytecodeOperand
    ax: BytecodeOperand
    effect_hint: Effect
end
```

### 4.6 BytecodeFormat

```moonlift
union BytecodeFormat
    iABC()
    iABx()
    iAsBx()
    iAx()
    iExtraArg()
    internal()
end
```

---

## 5. Lua VM state products

These products reference existing VM structures. Field names here describe the JIT-visible contract, not necessarily the final memory layout.

### 5.1 VmFrameView

```moonlift
struct VmFrameView
    L: ptr(LuaThread)
    frame: ptr(CallFrame)
    closure: ptr(LClosure)
    proto: ptr(Proto)
    base: ptr(Value)
    top: ptr(Value)
    pc: Pc
end
```

### 5.2 VmPinnedState

Values that compiled code commonly receives or keeps in pinned registers.

```moonlift
struct VmPinnedState
    L: ptr(LuaThread)
    frame: ptr(CallFrame)
    base: ptr(Value)
    top: ptr(Value)
    proto: ptr(Proto)
    constants: ptr(Value)
    code: ptr(u32)
    runtime: ptr(JitRuntime)
end
```

### 5.3 VmObservableState

The state that must be visible to the interpreter, debugger, GC, or error machinery at a boundary.

```moonlift
struct VmObservableState
    L: ptr(LuaThread)
    frame: ptr(CallFrame)
    base: ptr(Value)
    top: ptr(Value)
    pc: Pc
    status: u8
end
```

---

## 6. Value and fact products

### 6.1 ValueKind

```moonlift
union ValueKind
    unknown()
    nil_value()
    false_value()
    true_value()
    boolean()
    integer()
    float()
    number()
    short_string()
    long_string()
    table()
    lclosure()
    cclosure()
    userdata()
    thread()
    lightuserdata()
end
```

### 6.2 ValueLocation

```moonlift
union ValueLocation
    unknown()
    stack(slot: SlotIndex)
    constant(index: ConstIndex)
    immediate_i64(value: i64)
    immediate_f64_bits(bits: u64)
    pinned_reg(reg: NativeReg)
    scratch_reg(reg: NativeReg)
    payload(offset: ByteOffset)
end
```

### 6.3 NativeReg

```moonlift
union NativeReg
    none()
    gpr(index: u8)
    fpr(index: u8)
    flags()
end
```

### 6.4 TypedValue

```moonlift
struct TypedValue
    id: ValueId
    kind: ValueKind
    location: ValueLocation
    defining_node: PlanNodeId
    version: u32
    payload0: u64
    payload1: u64
end
```

Meaning:

```text
id             SSA-like identity inside StencilPlan selection
kind           best known Lua value kind
location       where the value currently lives for selection purposes
defining_node  plan node that produced it, if any
version        increments when a slot receives a new ValueId
payload0/1     optional constant, shape, target, or literal payload
```

### 6.5 Fact

```moonlift
union Fact
    value_kind(value: ValueId, kind: ValueKind)
    value_location(value: ValueId, loc: ValueLocation)
    slot_value(slot: SlotIndex, value: ValueId)
    constant_value(index: ConstIndex, value: ValueId)
    table_shape(value: ValueId, shape: ShapeEpoch)
    table_array_hit(value: ValueId)
    table_string_slot(value: ValueId, key: ptr(TString), slot_offset: i32)
    metatable_absent(value: ValueId)
    metatable_no_index(value: ValueId)
    metatable_no_newindex(value: ValueId)
    closure_target(value: ValueId, closure: ptr(Closure))
    cfunction_target(value: ValueId, fn: ptr(void))
    lclosure_proto(value: ValueId, proto: ptr(Proto))
    global_slot(env: ValueId, key: ptr(TString), slot_offset: i32)
    guard_success(guard: GuardId)
    branch_taken(addr: SemanticAddr, target: SemanticAddr)
    loop_induction_i64(slot: SlotIndex)
    value_live(value: ValueId)
    value_dead(value: ValueId)
    no_debug_hook()
    no_gc_between(start: PlanNodeId, finish: PlanNodeId)
end
```

### 6.6 FactSet

```moonlift
struct FactSet
    facts: ptr(Fact)
    count: index
    hash: u64
    generation: u32
end
```

### 6.6.1 FactSet as the optimizer center

The primary runtime/JIT design problem is the fact vocabulary.
Arity exploration does not invent semantic knowledge; it exploits knowledge that
is represented in `FactSet` and preserved in the selector key.

```text
rich facts
  -> more legal candidate stencils
  -> arity/closure exploration discovers useful forms
  -> measurement selects survivors
  -> runtime selector climbs library layers
```

A LuaJIT-class rewrite falls out automatically only when all legality conditions
are visible as facts. Examples:

```text
DCE                  requires liveness + Effect == PURE
redundant guard      requires fact dominance / guard_success
raw table access     requires table shape + metatable absence + dependency
known call           requires callee target + arg/ret shape + boundary projection
allocation sinking   requires virtual object + escape fact + materialization projection
loop specialization  requires loop-carried induction/accumulator facts
```

Thus:

```text
No fact, no discovery.
Wrong fact, wrong code.
Rich fact, large optimization space.
```

Every promoted fact must carry its dependency, invalidation, and projection
obligations. For example, `table_shape(value, epoch)` is not just a hint; it
requires a dependency on the table/metatable epoch and a side-exit projection if
the guard fails.

### 6.6.2 Peephole as fact-backed shape selection

Peephole optimization is not a blind pass over emitted native instructions. In
this VM it must happen before codegen, while opcode operands, liveness, and VM
continuation shape are visible.

```text
peephole candidate = small PatternWindow × FactSet × ShapeKind × Lowering
```

Examples:

```text
MOVE|MOVE @ move_def;move_uses_previous_def
  -> shape_kind=pure_rewrite
  -> lowering=move_move_forward

LOADI|MOVE @ load_def;move_uses_previous_def
  -> shape_kind=pure_rewrite
  -> lowering=load_move_final_dst

ADDI|RETURN1 @ i64;returns_previous_def
  -> shape_kind=terminal_return
  -> lowering=op_return1
```

The retained rewrite view/layer is therefore a legalization and lowering-shape
classification pass over normal candidates. It is not a later optional peephole
cleanup. Object compilation proves that the Moonlift source is compilable; shape
legalization proves that the candidate has the right VM continuation/effect
contract.

Each candidate records:

```text
shape_kind
lowering
continuation
effect_context
legalization_source
```

### 6.6.3 Selection before layer climbing

The runtime library and higher layers must be built from selected winners, not
from all discovered candidates. Layer closure is cumulative: L3 is built from
L0, selected L1, and selected L2 atoms together. Selection requires both
semantic legality and profitability evidence:

```text
candidate generated
  -> shape verified
  -> kernel emitted
  -> object compiled
  -> profitability benchmarked
  -> selected or rejected
```

The current offline benchmark is `profitability_model_v1`. It scores candidates
with observed frequency, baseline opcode cost, candidate shape/lowering, native
artifact size, guard/side-exit risk, and whether the candidate has a concrete
lowering path. Boundary-only candidates are kept for legality/debugging but are
not profitable L2 atoms.

Facts must pass through a lowering-plan step before codegen. Missing lowerings
are fail-closed: the candidate is unsupported, not emitted as a side-exit stub.
For L2+, selected lower atoms are already native artifacts; opcode lists are
matching/profile metadata only. Higher-layer composition uses native artifact
budgets rather than re-lowering flattened opcode sequences.

### 6.7 CanonicalFactKey

The runtime selector does not inspect arbitrary `FactSet`s directly. Facts are canonicalized into a compact key.

```moonlift
struct CanonicalFactKey
    pattern_id: u32
    layer_limit: LayerId
    value_mask: u64
    location_mask: u64
    effect_mask: u64
    liveness_mask: u64
    shape_hash: u64
    control_shape: u32
end
```

---

## 7. Virtual state products

### 7.1 VirtualState

`VirtualState` is the JIT planner's view of VM state. It is not a runtime heap object required by generated code.

```moonlift
struct VirtualState
    addr: SemanticAddr
    frame_id: u32
    base_slot: SlotIndex
    top_slot: SlotIndex
    slots: ptr(ValueId)          -- slot index -> ValueId
    slot_count: index
    values: ptr(TypedValue)
    value_count: index
    facts: FactSet
    deps: DependencySet
    live: LiveSet
    projection_policy: ProjectionPolicy
end
```

### 7.2 StateShape

A compact shape used by stencil contracts.

```moonlift
struct StateShape
    slot_kinds: ptr(ValueKind)
    slot_count: index
    live_slots: LiveSet
    value_locations: ptr(ValueLocation)
    value_count: index
    required_facts: FactSet
    produced_facts: FactSet
    top_slot: SlotIndex
end
```

### 7.3 LiveSet

```moonlift
struct LiveSet
    bits: ptr(u64)
    bit_count: index
end
```

### 7.4 LivenessInfo

```moonlift
struct LivenessInfo
    range: SemanticRange
    live_in: ptr(LiveSet)
    live_out: ptr(LiveSet)
    per_pc_live: ptr(LiveSet)
    count: index
end
```

---

## 8. Effects, boundaries, and projections

### 8.1 Effect

```moonlift
struct Effect
    flags: u64
end
```

Effect flag constants:

```moonlift
const EFFECT_PURE: u64                = 0x0000000000000001
const EFFECT_MAY_BRANCH: u64          = 0x0000000000000002
const EFFECT_MAY_THROW: u64           = 0x0000000000000004
const EFFECT_MAY_ALLOC: u64           = 0x0000000000000008
const EFFECT_MAY_GC: u64              = 0x0000000000000010
const EFFECT_MAY_CALL_LUA: u64        = 0x0000000000000020
const EFFECT_MAY_CALL_C: u64          = 0x0000000000000040
const EFFECT_MAY_YIELD: u64           = 0x0000000000000080
const EFFECT_MAY_RUN_HOOK: u64        = 0x0000000000000100
const EFFECT_MAY_CALL_METAMETHOD: u64 = 0x0000000000000200
const EFFECT_MAY_OBSERVE_STACK: u64   = 0x0000000000000400
const EFFECT_MAY_READ_HEAP: u64       = 0x0000000000000800
const EFFECT_MAY_WRITE_HEAP: u64      = 0x0000000000001000
const EFFECT_MAY_NEED_BARRIER: u64    = 0x0000000000002000
const EFFECT_MAY_INVALIDATE_DEPS: u64 = 0x0000000000004000
const EFFECT_MAY_EXIT: u64            = 0x0000000000008000
```

### 8.2 BoundaryRequirement

```moonlift
struct BoundaryRequirement
    flags: u64
end
```

Boundary flag constants:

```moonlift
const BOUNDARY_NONE: u64        = 0
const BOUNDARY_INTERPRETER: u64 = 0x0001
const BOUNDARY_ROOTS: u64       = 0x0002
const BOUNDARY_RESUME: u64      = 0x0004
const BOUNDARY_DEBUG: u64       = 0x0008
const BOUNDARY_ERROR: u64       = 0x0010
const BOUNDARY_BARRIER: u64     = 0x0020
const BOUNDARY_DEP_CHECK: u64   = 0x0040
```

### 8.3 ProjectionKind

```moonlift
union ProjectionKind
    interpreter()
    roots()
    resume()
    debug()
    error()
    side_exit()
    barrier()
end
```

### 8.4 ProjectedSlot

```moonlift
struct ProjectedSlot
    slot: SlotIndex
    value: ValueId
    kind: ValueKind
    source: ValueLocation
    must_write: bool
end
```

### 8.5 ResumeProjection

```moonlift
struct ResumeProjection
    resume_pc: Pc
    resume_top: SlotIndex
    call_status: u8
    yield_status: u8
    pending_results_slot: SlotIndex
    pending_result_count: u16
end
```

### 8.6 ErrorProjection

```moonlift
struct ErrorProjection
    error_pc: Pc
    error_value: ValueId
    error_slot: SlotIndex
    error_code: u32
end
```

### 8.7 DebugProjection

```moonlift
struct DebugProjection
    hook_pc: Pc
    line: u32
    frame_visible: bool
    stack_visible: bool
end
```

### 8.8 Projection

```moonlift
struct Projection
    id: u32
    kind: ProjectionKind
    addr: SemanticAddr
    frame_id: u32
    base_slot: SlotIndex
    top_slot: SlotIndex
    slots: ptr(ProjectedSlot)
    slot_count: index
    root_values: ptr(ValueId)
    root_count: index
    resume: ResumeProjection
    error: ErrorProjection
    debug: DebugProjection
end
```

### 8.9 ProjectionPolicy

```moonlift
struct ProjectionPolicy
    allow_lazy_slots: bool
    require_precise_pc: bool
    require_debug_visible_stack: bool
    require_roots_before_helper: bool
    require_resume_state: bool
end
```

---

## 9. Dependency products

### 9.1 DependencyKind

```moonlift
union DependencyKind
    table_shape(table: ValueId, epoch: ShapeEpoch)
    metatable_absent(table: ValueId)
    metatable_epoch(table: ValueId, epoch: ShapeEpoch)
    global_slot(env: ValueId, key: ptr(TString), epoch: ShapeEpoch)
    closure_target(slot: SlotIndex, closure: ptr(Closure))
    cfunction_target(slot: SlotIndex, fn: ptr(void))
    debug_hook_absent()
    gc_barrier_protocol(version: u32)
end
```

### 9.2 DependencyKey

```moonlift
struct DependencyKey
    id: DependencyId
    kind: DependencyKind
    hash: u64
end
```

### 9.3 DependencySet

```moonlift
struct DependencySet
    keys: ptr(DependencyKey)
    count: index
    hash: u64
end
```

### 9.4 DependencyIndex

```moonlift
struct DependencyIndex
    buckets: ptr(ptr(DependencyWatchList))
    bucket_count: index
    generation: u64
end
```

### 9.5 DependencyWatchList

```moonlift
struct DependencyWatchList
    key: DependencyKey
    units: ptr(ptr(ExecutableUnit))
    unit_count: index
end
```

---

## 10. Stencil products

### 10.1 StencilLayer

```moonlift
struct StencilLayer
    id: LayerId
    name: ptr(u8)
    max_absorbed_bytecodes: u32
    experimental: bool
end
```

Layer meanings:

```text
L0: primitive opcode/fact stencils, max absorbed bytecodes ~= 1 or more for larger primitives
L1: closure over L0, max absorbed bytecodes ~= 4
L2: closure over L0..L1, max absorbed bytecodes ~= 16
L3: closure over L0..L2, max absorbed bytecodes ~= 64
L4: speed-max default, max absorbed bytecodes ~= 256
L5: trace-region experiment, max absorbed bytecodes ~= 1024
```

### 10.2 StencilDomain

```moonlift
union StencilDomain
    abi()
    entry()
    exit()
    state()
    value()
    guard()
    arithmetic()
    comparison()
    branch()
    loop()
    table()
    call()
    closure()
    barrier()
    projection()
    edge()
    inline_cache()
    supernode()
    trace_region()
    rewrite()
end
```

### 10.3 StencilPattern

```moonlift
struct StencilPattern
    id: u32
    domain: StencilDomain
    semantic_range_kind: PatternRangeKind
    opcode_count: u16
    opcodes: ptr(u16)
    operand_shape_hash: u64
    effect: Effect
    control_shape: ControlShape
end
```

### 10.4 PatternRangeKind

```moonlift
union PatternRangeKind
    single_opcode()
    bytecode_window()
    stencil_sequence()
    projection_bundle()
    boundary_bundle()
    trace_region()
end
```

### 10.5 ControlShape

```moonlift
union ControlShape
    fallthrough()
    direct_branch(true_target: SemanticAddr, false_target: SemanticAddr)
    loop_backedge(target: SemanticAddr)
    side_exit(exit_id: ExitId)
    return_to_vm()
    call_boundary()
    yield_boundary()
    error_boundary()
    edge_indirect(edge: ptr(EdgeCell))
end
```

### 10.6 StencilHoleKind

```moonlift
union StencilHoleKind
    slot_disp(slot: SlotIndex, field: ValueField)
    const_ptr(index: ConstIndex)
    proto_ptr()
    runtime_ptr()
    helper_ptr(helper: RuntimeHelperId)
    edge_cell_ptr()
    ic_record_ptr()
    projection_id()
    immediate_i32()
    immediate_i64()
    literal_payload_offset()
    dependency_index()
end
```

### 10.7 ValueField

```moonlift
union ValueField
    tag()
    aux()
    bits()
    whole_value()
end
```

### 10.8 StencilHole

```moonlift
struct StencilHole
    name: ptr(u8)
    kind: StencilHoleKind
    offset: CodeOffset
    width: u8
    addend: i64
    required: bool
end
```

### 10.9 StencilRelocKind

```moonlift
union StencilRelocKind
    branch_target()
    call_target()
    rip_relative_data()
    edge_target()
    side_exit_target()
    fallthrough_or_branch()
    helper_call()
end
```

### 10.10 StencilReloc

```moonlift
struct StencilReloc
    name: ptr(u8)
    kind: StencilRelocKind
    offset: CodeOffset
    width: u8
    addend: i64
    target_node: PlanNodeId
    target_exit: ExitId
end
```

### 10.11 StencilPayloadKind

```moonlift
union StencilPayloadKind
    literal_bytes()
    value_constant()
    projection_record()
    dependency_record()
    inline_cache_record()
    debug_record()
    root_map()
end
```

### 10.12 StencilPayload

```moonlift
struct StencilPayload
    kind: StencilPayloadKind
    size: u32
    align: u16
    data: ptr(u8)
end
```

### 10.13 StencilABI

```moonlift
struct StencilABI
    name: ptr(u8)
    arch: TargetArch
    os_abi: TargetABI
    pinned_state: VmPinnedStateShape
    clobbers: ClobberSet
    preserves_stack_alignment: bool
    may_call_out: bool
end
```

### 10.14 TargetArch

```moonlift
union TargetArch
    x86_64()
    aarch64()
end
```

### 10.15 TargetABI

```moonlift
union TargetABI
    sysv()
    win64()
    aapcs64()
end
```

### 10.16 VmPinnedStateShape

```moonlift
struct VmPinnedStateShape
    L_reg: NativeReg
    frame_reg: NativeReg
    base_reg: NativeReg
    top_reg: NativeReg
    proto_reg: NativeReg
    constants_reg: NativeReg
    runtime_reg: NativeReg
end
```

### 10.17 ClobberSet

```moonlift
struct ClobberSet
    gpr_mask: u64
    fpr_mask: u64
    flags_clobbered: bool
    memory_clobbered: bool
end
```

### 10.18 CodeStencil

A physical code product.

```moonlift
struct CodeStencil
    id: StencilId
    name: ptr(u8)
    layer: LayerId
    domain: StencilDomain
    pattern: StencilPattern
    bytes: ptr(u8)
    byte_count: CodeSize
    holes: ptr(StencilHole)
    hole_count: index
    relocs: ptr(StencilReloc)
    reloc_count: index
    payloads: ptr(StencilPayload)
    payload_count: index
    abi: StencilABI
    input_shape: StateShape
    output_shape: StateShape
    required_facts: FactSet
    produced_facts: FactSet
    effects: Effect
    exits: ptr(UnitExitTemplate)
    exit_count: index
    projections: ptr(ProjectionTemplate)
    projection_count: index
    dependencies: DependencySet
    cost: StencilCost
    verification: VerificationStatus
end
```

### 10.19 StencilCost

```moonlift
struct StencilCost
    code_size: CodeSize
    estimated_cycles: u32
    materialization_cost: u32
    branch_count: u16
    call_count: u16
    memory_loads: u16
    memory_stores: u16
    exit_count: u16
    score: i64
end
```

### 10.20 VerificationStatus

```moonlift
union VerificationStatus
    unchecked()
    candidate()
    fixture_validated()
    contract_verified()
    execution_tested()
    promoted()
    rejected(reason: VerificationFailure)
end
```

### 10.21 VerificationFailure

```moonlift
union VerificationFailure
    missing_hole()
    missing_reloc()
    unsafe_abi()
    bad_clobber()
    bad_projection()
    effect_mismatch()
    dependency_mismatch()
    semantic_mismatch()
    execution_failed()
end
```

### 10.22 RewriteKind

```moonlift
union RewriteKind
    replace_sequence_with_stencil(stencil: StencilId)
    eliminate_sequence()
    redirect_output(slot: SlotIndex)
    bundle_projection(stencil: StencilId)
    collapse_branch()
    remove_redundant_guard()
    alias_to_existing(stencil: StencilId)
end
```

### 10.23 RewriteStencil

A plan-level product. It may produce no bytes directly.

```moonlift
struct RewriteStencil
    id: RewriteId
    name: ptr(u8)
    layer: LayerId
    pattern: StencilPattern
    required_facts: FactSet
    forbidden_effects: Effect
    replacement: RewriteKind
    input_shape: StateShape
    output_shape: StateShape
    effects_before: Effect
    effects_after: Effect
    projections_before: ptr(ProjectionTemplate)
    projections_after: ptr(ProjectionTemplate)
    equivalence: EquivalenceContract
    cost_delta: StencilCostDelta
end
```

### 10.24 EquivalenceContract

```moonlift
struct EquivalenceContract
    expansion: ptr(StencilId)
    expansion_count: index
    required_facts: FactSet
    observable_state_equal: bool
    effects_subset: bool
    exits_equivalent: bool
    projections_equivalent: bool
    dependencies_equivalent: bool
end
```

### 10.25 StencilCostDelta

```moonlift
struct StencilCostDelta
    code_size_delta: i32
    estimated_cycles_delta: i32
    materialization_delta: i32
    exit_count_delta: i16
    score_delta: i64
end
```

### 10.26 StencilLibrary

```moonlift
struct StencilLibrary
    version: u64
    target_arch: TargetArch
    target_abi: TargetABI
    layers: ptr(StencilLayer)
    layer_count: index
    code_stencils: ptr(CodeStencil)
    code_count: index
    rewrite_stencils: ptr(RewriteStencil)
    rewrite_count: index
    selector: StencilSelector
    metadata: StencilLibraryMetadata
end
```

### 10.27 StencilLibraryMetadata

```moonlift
struct StencilLibraryMetadata
    build_mode: JitBuildMode
    corpus_hash: u64
    generator_hash: u64
    moonlift_version_hash: u64
    lua_vm_version_hash: u64
    creation_unix_ms: u64
end
```

### 10.28 StencilSelector

The generated selector product.

```moonlift
struct StencilSelector
    table: ptr(SelectorEntry)
    count: index
    fallback_stencil: StencilId
end
```

### 10.29 SelectorEntry

```moonlift
struct SelectorEntry
    key: CanonicalFactKey
    max_layer: LayerId
    stencil: StencilId
    rewrite: RewriteId
    choice: SelectorChoice
end
```

### 10.30 SelectorChoice

```moonlift
union SelectorChoice
    code(stencil: StencilId)
    rewrite(rewrite: RewriteId)
    fallback(stencil: StencilId)
    decline(reason: DeclineReason)
end
```

### 10.31 DeclineReason

```moonlift
union DeclineReason
    unsupported_opcode()
    no_legal_projection()
    effect_not_supported()
    dependency_unstable()
    blacklisted_anchor()
    code_cache_pressure()
    internal_error()
end
```

---

## 11. StencilPlan products

### 11.1 StencilNodeKind

```moonlift
union StencilNodeKind
    code(stencil: StencilId)
    rewrite(rewrite: RewriteId)
    projection(projection: Projection)
    boundary(requirement: BoundaryRequirement)
    edge_jump(edge: ptr(EdgeCell))
    side_exit(exit_id: ExitId)
    no_op()
end
```

### 11.2 StencilNode

```moonlift
struct StencilNode
    id: PlanNodeId
    kind: StencilNodeKind
    layer: LayerId
    covered_range: SemanticRange
    input_state: StateShape
    output_state: StateShape
    required_facts: FactSet
    produced_facts: FactSet
    effects: Effect
    deps: DependencySet
    exits: ptr(UnitExit)
    exit_count: index
    projection: ptr(Projection)
    debug_name: ptr(u8)
end
```

### 11.3 StencilPlan

```moonlift
struct StencilPlan
    id: u64
    source: PlanSource
    anchor: ptr(TraceAnchor)
    range: SemanticRange
    max_layer: LayerId
    generation: Generation
    nodes: ptr(StencilNode)
    node_count: index
    entry_state: VirtualState
    exit_state: VirtualState
    projections: ptr(Projection)
    projection_count: index
    deps: DependencySet
    exits: ptr(UnitExit)
    exit_count: index
    root_map: RootMap
    code_estimate: CodeSize
    valid: bool
end
```

### 11.4 PlanVersion

```moonlift
struct PlanVersion
    id: u64
    anchor: ptr(TraceAnchor)
    previous: ptr(PlanVersion)
    source: PlanSource
    generation: Generation
    max_layer: LayerId
    plan: ptr(StencilPlan)
    facts_used: FactSet
    rewrite_applied: RewriteId
    executable: ptr(ExecutableUnit)
    profile: UnitProfile
    status: PlanVersionStatus
end
```

### 11.5 PlanVersionStatus

```moonlift
union PlanVersionStatus
    building()
    materialized()
    published()
    active()
    superseded(next: ptr(PlanVersion))
    invalidated(reason: InvalidationReason)
    reclaimed()
    failed(reason: PlanFailure)
end
```

### 11.6 PlanFailure

```moonlift
union PlanFailure
    selection_failed(reason: DeclineReason)
    layout_failed()
    materialization_failed()
    verification_failed()
    publish_failed()
    code_cache_full()
    oom()
end
```

### 11.7 RefinementReason

```moonlift
union RefinementReason
    hot_entry()
    hot_loop()
    hot_exit(exit_id: ExitId)
    stable_trace(trace: TraceId)
    exit_rate_too_high(exit_id: ExitId)
    layer_advance()
    manual_request()
end
```

---

## 12. Runtime code products

### 12.1 ExecutableUnit

```moonlift
struct ExecutableUnit
    id: UnitId
    plan_version: ptr(PlanVersion)
    range: SemanticRange
    entry_addr: ptr(void)
    code: CompiledCode
    exits: ptr(UnitExit)
    exit_count: index
    deps: DependencySet
    root_map: RootMap
    profile: UnitProfile
    status: UnitStatus
    generation: Generation
    max_layer: LayerId
end
```

### 12.2 UnitStatus

```moonlift
union UnitStatus
    allocated()
    published()
    active()
    invalidated(reason: InvalidationReason)
    retired()
    reclaimable()
    reclaimed()
end
```

### 12.3 InvalidationReason

```moonlift
union InvalidationReason
    dependency_changed(dep: DependencyKey)
    code_cache_eviction()
    debug_mode_changed()
    gc_protocol_changed()
    manual_flush()
    too_many_side_exits()
end
```

### 12.4 CompiledCode

```moonlift
struct CompiledCode
    slab: ptr(CodeSlab)
    start: ptr(u8)
    size: CodeSize
    align: u16
    writable_start: ptr(u8)
    executable_start: ptr(u8)
end
```

### 12.5 CodeSlab

```moonlift
struct CodeSlab
    arena: ptr(CodeArena)
    start: ptr(u8)
    size: CodeSize
    used: CodeSize
    executable: bool
    sealed: bool
end
```

### 12.6 CodeArena

```moonlift
struct CodeArena
    slabs: ptr(ptr(CodeSlab))
    slab_count: index
    total_size: u64
    used_size: u64
    generation: u64
end
```

### 12.7 UnitExit

```moonlift
struct UnitExit
    id: ExitId
    kind: UnitExitKind
    source_node: PlanNodeId
    source_addr: SemanticAddr
    target_addr: SemanticAddr
    edge: ptr(EdgeCell)
    projection: Projection
    profile: ExitProfile
end
```

### 12.8 UnitExitKind

```moonlift
union UnitExitKind
    fallthrough()
    side_exit()
    interpreter_exit()
    loop_exit()
    error_exit()
    yield_exit()
    call_boundary_exit()
    dependency_exit()
end
```

### 12.9 UnitExitTemplate

```moonlift
struct UnitExitTemplate
    kind: UnitExitKind
    projection_required: BoundaryRequirement
    target_semantic_delta: i32
end
```

### 12.10 ProjectionTemplate

```moonlift
struct ProjectionTemplate
    kind: ProjectionKind
    live_policy: ProjectionLivePolicy
    requires_precise_pc: bool
    requires_top: bool
    requires_roots: bool
end
```

### 12.11 ProjectionLivePolicy

```moonlift
union ProjectionLivePolicy
    live_slots_only()
    all_slots_to_top()
    roots_only()
    explicit_list(slots: ptr(SlotIndex), count: index)
end
```

### 12.12 RootMap

```moonlift
struct RootMap
    entries: ptr(RootMapEntry)
    count: index
end
```

### 12.13 RootMapEntry

```moonlift
struct RootMapEntry
    native_offset: CodeOffset
    roots: ptr(ValueLocation)
    root_count: index
end
```

### 12.14 JitOutcome

```moonlift
union JitOutcome
    returned(value_count: u16)
    continue_interpreter(addr: SemanticAddr)
    side_exit(exit: ptr(UnitExit))
    yielded()
    threw(error_value: ValueId)
    invalidated()
    call_boundary(boundary: ptr(BoundaryFrame))
    oom()
end
```

---

## 13. Cells and profiles

### 13.1 EntryCell

An entry cell names the current best entry for a semantic anchor.

```moonlift
struct EntryCell
    anchor: AnchorId
    addr: SemanticAddr
    target: ptr(ExecutableUnit)
    generation: Generation
    max_layer: LayerId
    state: CellState
    profile: EntryProfile
end
```

### 13.2 EdgeCell

An edge cell names a linkable control edge.

```moonlift
struct EdgeCell
    id: u64
    source_unit: ptr(ExecutableUnit)
    source_exit: ExitId
    target_unit: ptr(ExecutableUnit)
    target_addr: SemanticAddr
    fallback_addr: SemanticAddr
    generation: Generation
    state: CellState
    profile: ExitProfile
end
```

### 13.3 CellState

```moonlift
union CellState
    interpreter()
    compiling()
    linked()
    invalidated()
    blacklisted(reason: BlacklistReason)
end
```

### 13.4 BlacklistReason

```moonlift
union BlacklistReason
    too_many_failures()
    unstable_facts()
    unsupported_effect()
    code_cache_pressure()
    debug_mode()
    manual()
end
```

### 13.5 EntryProfile

```moonlift
struct EntryProfile
    hits: ProfileCounter
    interpreted_hits: ProfileCounter
    compiled_hits: ProfileCounter
    failed_compile_count: u16
    last_generation: Generation
end
```

### 13.6 UnitProfile

```moonlift
struct UnitProfile
    entry_count: ProfileCounter
    side_exit_count: ProfileCounter
    boundary_count: ProfileCounter
    invalidation_count: ProfileCounter
    refinement_count: ProfileCounter
    last_hot_reason: RefinementReason
end
```

### 13.7 ExitProfile

```moonlift
struct ExitProfile
    taken_count: ProfileCounter
    hot_count: ProfileCounter
    last_taken_generation: Generation
    linked: bool
end
```

### 13.8 InlineCacheRecord

```moonlift
struct InlineCacheRecord
    id: u64
    kind: InlineCacheKind
    state: InlineCacheState
    hits: ProfileCounter
    misses: ProfileCounter
    deps: DependencySet
    payload: InlineCachePayload
end
```

### 13.9 InlineCacheKind

```moonlift
union InlineCacheKind
    table_array_i64()
    table_string_shape()
    global_string_slot()
    call_lclosure()
    call_cfunction()
    method_self_shape()
end
```

### 13.10 InlineCacheState

```moonlift
union InlineCacheState
    empty()
    monomorphic()
    polymorphic(count: u8)
    megamorphic()
    disabled(reason: BlacklistReason)
end
```

### 13.11 InlineCachePayload

```moonlift
struct InlineCachePayload
    table_shape: ShapeEpoch
    metatable_epoch: ShapeEpoch
    key_string: ptr(TString)
    slot_offset: i32
    closure: ptr(Closure)
    cfunction: ptr(void)
end
```

---

## 14. Trace products

### 14.1 TraceAnchorKind

```moonlift
union TraceAnchorKind
    entry(addr: SemanticAddr)
    loop_header(addr: SemanticAddr)
    side_exit(unit: UnitId, exit_id: ExitId)
    call_edge(addr: SemanticAddr)
end
```

### 14.2 TraceAnchor

```moonlift
struct TraceAnchor
    id: AnchorId
    kind: TraceAnchorKind
    addr: SemanticAddr
    entry_cell: ptr(EntryCell)
    status: TraceAnchorStatus
    hot_counter: ProfileCounter
    failed_refinements: u8
    active_plan: ptr(PlanVersion)
end
```

### 14.3 TraceAnchorStatus

```moonlift
union TraceAnchorStatus
    cold()
    warming()
    compiled()
    recording()
    refining()
    blacklisted(reason: BlacklistReason)
end
```

### 14.4 TraceRecord

```moonlift
struct TraceRecord
    id: TraceId
    anchor: ptr(TraceAnchor)
    source_unit: ptr(ExecutableUnit)
    steps: ptr(TraceStep)
    step_count: index
    guards: ptr(TraceGuard)
    guard_count: index
    snapshots: ptr(TraceSnapshot)
    snapshot_count: index
    exits: ptr(TraceExit)
    exit_count: index
    facts: FactSet
    deps: DependencySet
    side_exit_rate: u32
    stable: bool
end
```

### 14.5 TraceStep

```moonlift
struct TraceStep
    addr: SemanticAddr
    opcode: u16
    word: u32
    input_state: StateShape
    output_state: StateShape
    observed_facts: FactSet
    effect: Effect
end
```

### 14.6 TraceGuard

```moonlift
struct TraceGuard
    id: GuardId
    addr: SemanticAddr
    fact: Fact
    snapshot: u32
    exit: ExitId
end
```

### 14.7 GuardId

```moonlift
type GuardId = u32
```

### 14.8 TraceSnapshot

```moonlift
struct TraceSnapshot
    id: u32
    addr: SemanticAddr
    state: VirtualState
    projection: Projection
    live: LiveSet
end
```

### 14.9 TraceExit

```moonlift
struct TraceExit
    id: ExitId
    kind: UnitExitKind
    source_step: u32
    target_addr: SemanticAddr
    snapshot: u32
    edge: ptr(EdgeCell)
    taken_count: ProfileCounter
end
```

---

## 15. Offline library construction products

### 15.1 LuaCorpus

```moonlift
struct LuaCorpus
    sources: ptr(CorpusSource)
    source_count: index
    files: ptr(CorpusFile)
    file_count: index
    hash: u64
end
```

### 15.2 CorpusSource

```moonlift
struct CorpusSource
    name: ptr(u8)
    origin_url: ptr(u8)
    license: ptr(u8)
    commit: ptr(u8)
    category: CorpusCategory
end
```

### 15.3 CorpusCategory

```moonlift
union CorpusCategory
    luarocks_package()
    github_repository()
    openresty_library()
    neovim_plugin()
    game_script()
    benchmark()
    local_project()
end
```

### 15.4 CorpusFile

```moonlift
struct CorpusFile
    source: ptr(CorpusSource)
    path: ptr(u8)
    content_hash: u64
    byte_len: u64
    accepted: bool
end
```

### 15.5 CorpusProfile

```moonlift
struct CorpusProfile
    opcode_counts: ptr(OpcodeCount)
    opcode_count: index
    window_counts: ptr(WindowCount)
    window_count: index
    operand_shapes: ptr(OperandShapeCount)
    operand_shape_count: index
    loop_shapes: ptr(LoopShapeCount)
    loop_shape_count: index
    call_shapes: ptr(CallShapeCount)
    call_shape_count: index
    trace_motifs: ptr(TraceMotifCount)
    trace_motif_count: index
end
```

### 15.6 OpcodeCount

```moonlift
struct OpcodeCount
    opcode: u16
    count: u64
end
```

### 15.7 WindowCount

```moonlift
struct WindowCount
    opcode_count: u16
    opcodes: ptr(u16)
    operand_shape_hash: u64
    count: u64
end
```

### 15.8 OperandShapeCount

```moonlift
struct OperandShapeCount
    opcode: u16
    shape_hash: u64
    count: u64
end
```

### 15.9 LoopShapeCount

```moonlift
struct LoopShapeCount
    shape_hash: u64
    backedge_opcode: u16
    body_opcode_count: u16
    count: u64
end
```

### 15.10 CallShapeCount

```moonlift
struct CallShapeCount
    shape_hash: u64
    callee_shape: u32
    arg_count: u16
    result_count: u16
    count: u64
end
```

### 15.11 TraceMotifCount

```moonlift
struct TraceMotifCount
    motif_hash: u64
    max_layer_hint: LayerId
    observed_count: u64
    hot_count: u64
end
```

### 15.12 CandidateFunction

```moonlift
struct CandidateFunction
    name: ptr(u8)
    pattern: StencilPattern
    facts: FactSet
    source_path: ptr(u8)
    symbol_name: ptr(u8)
    object_path: ptr(u8)
end
```

### 15.13 CandidateBody

```moonlift
struct CandidateBody
    function: ptr(CandidateFunction)
    body_offset: CodeOffset
    body_size: CodeSize
    bytes: ptr(u8)
    has_ret: bool
    has_stack_frame: bool
    has_unclassified_call: bool
end
```

### 15.14 StencilFixture

```moonlift
struct StencilFixture
    candidate: ptr(CandidateFunction)
    body: CandidateBody
    holes: ptr(StencilHole)
    hole_count: index
    relocs: ptr(StencilReloc)
    reloc_count: index
    abi: StencilABI
    clobbers: ClobberSet
    contract: StencilContract
    status: VerificationStatus
end
```

### 15.15 StencilContract

```moonlift
struct StencilContract
    pattern: StencilPattern
    required_facts: FactSet
    input_shape: StateShape
    output_shape: StateShape
    effects: Effect
    projections: ptr(ProjectionTemplate)
    projection_count: index
    deps: DependencySet
    exits: ptr(UnitExitTemplate)
    exit_count: index
end
```

### 15.16 StencilUniverse

```moonlift
struct StencilUniverse
    build_mode: JitBuildMode
    max_layer: LayerId
    max_arity: u8
    candidates: ptr(CandidateFunction)
    candidate_count: index
    fixtures: ptr(StencilFixture)
    fixture_count: index
    promoted: ptr(CodeStencil)
    promoted_count: index
    rewrites: ptr(RewriteStencil)
    rewrite_count: index
end
```

---

## 16. Runtime root product

### 16.1 JitRuntime

```moonlift
struct JitRuntime
    library: ptr(StencilLibrary)
    code_arena: ptr(CodeArena)
    dependency_index: ptr(DependencyIndex)
    entry_cells: ptr(EntryCellTable)
    edge_cells: ptr(EdgeCellTable)
    profiles: ptr(ProfileStore)
    trace_store: ptr(TraceStore)
    policy: JitPolicy
    stats: JitStats
end
```

### 16.2 EntryCellTable

```moonlift
struct EntryCellTable
    cells: ptr(EntryCell)
    count: index
    capacity: index
end
```

### 16.3 EdgeCellTable

```moonlift
struct EdgeCellTable
    cells: ptr(EdgeCell)
    count: index
    capacity: index
end
```

### 16.4 ProfileStore

```moonlift
struct ProfileStore
    entries: ptr(EntryProfile)
    units: ptr(UnitProfile)
    exits: ptr(ExitProfile)
    entry_count: index
    unit_count: index
    exit_count: index
end
```

### 16.5 TraceStore

```moonlift
struct TraceStore
    anchors: ptr(TraceAnchor)
    anchor_count: index
    records: ptr(TraceRecord)
    record_count: index
end
```

### 16.6 JitPolicy

```moonlift
struct JitPolicy
    enabled: bool
    max_runtime_layer: LayerId
    allow_layer5: bool
    hot_entry_threshold: ProfileCounter
    hot_loop_threshold: ProfileCounter
    hot_exit_threshold: ProfileCounter
    max_failed_refinements: u8
    max_generation: Generation
    max_code_bytes: u64
    verify_after_materialization: bool
    collect_trace_facts: bool
end
```

### 16.7 JitStats

```moonlift
struct JitStats
    compile_attempts: u64
    compile_successes: u64
    refinement_attempts: u64
    refinement_successes: u64
    side_exits: u64
    invalidations: u64
    code_bytes: u64
end
```

---

## 17. Offline library construction regions

This section declares the full control surface for building the stencil library. These regions are not called by the runtime JIT.

### 17.1 build_stencil_library

```moonlift
region build_stencil_library(
    config: ptr(StencilBuildConfig),
    corpus: ptr(LuaCorpus);

    built: cont(library: ptr(StencilLibrary), report: ptr(StencilBuildReport)),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.2 StencilBuildConfig

```moonlift
struct StencilBuildConfig
    mode: JitBuildMode
    target_arch: TargetArch
    target_abi: TargetABI
    max_layer: LayerId
    max_arity: u8
    include_trace_region_layer: bool
    output_dir: ptr(u8)
end
```

### 17.3 StencilBuildReport

```moonlift
struct StencilBuildReport
    universe: ptr(StencilUniverse)
    corpus_profile: ptr(CorpusProfile)
    generated_count: u64
    compiled_count: u64
    promoted_count: u64
    rejected_count: u64
    runtime_selector_count: u64
end
```

### 17.4 BuildFailure

```moonlift
union BuildFailure
    corpus_failed()
    profile_failed()
    generation_failed()
    compile_failed()
    extraction_failed()
    verification_failed()
    selector_failed()
    io_failed()
end
```

### 17.5 collect_lua_corpus

```moonlift
region collect_lua_corpus(
    config: ptr(CorpusConfig);

    collected: cont(corpus: ptr(LuaCorpus)),
    failed: cont(reason: CorpusFailure),
    oom: cont())
```

### 17.6 CorpusConfig

```moonlift
struct CorpusConfig
    include_luarocks: bool
    include_github_dataset: bool
    include_openresty: bool
    include_neovim_plugins: bool
    include_local: bool
    local_path: ptr(u8)
    max_files: u64
    store_source: bool
end
```

### 17.7 CorpusFailure

```moonlift
union CorpusFailure
    source_unavailable()
    license_rejected()
    io_error()
    parse_error()
end
```

### 17.8 profile_lua_corpus

```moonlift
region profile_lua_corpus(
    corpus: ptr(LuaCorpus),
    vm: ptr(LuaCompilerFrontend);

    profiled: cont(profile: ptr(CorpusProfile)),
    failed: cont(reason: ProfileFailure),
    oom: cont())
```

### 17.9 ProfileFailure

```moonlift
union ProfileFailure
    compile_error()
    unsupported_lua_version()
    malformed_bytecode()
    profile_io_error()
end
```

### 17.10 seed_l0_stencils

```moonlift
region seed_l0_stencils(
    config: ptr(StencilBuildConfig),
    contracts: ptr(OpcodeContractTable);

    seeded: cont(layer: ptr(StencilLayer), universe: ptr(StencilUniverse)),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.11 OpcodeContractTable

```moonlift
struct OpcodeContractTable
    contracts: ptr(OpcodeContract)
    count: index
end
```

### 17.12 OpcodeContract

```moonlift
struct OpcodeContract
    opcode: u16
    name: ptr(u8)
    generic_pattern: StencilPattern
    operand_axes: ptr(FactAxis)
    axis_count: index
    base_effect: Effect
    continuation_shape: ControlShape
end
```

### 17.13 FactAxis

```moonlift
struct FactAxis
    name: ptr(u8)
    values: ptr(FactAxisValue)
    value_count: index
end
```

### 17.14 FactAxisValue

```moonlift
struct FactAxisValue
    id: u32
    fact: Fact
    valid: bool
end
```

### 17.15 enumerate_layer_closure

```moonlift
region enumerate_layer_closure(
    previous: ptr(StencilUniverse),
    target_layer: LayerId,
    max_arity: u8,
    profile: ptr(CorpusProfile);

    enumerated: cont(candidates: ptr(CandidateFunction), count: index),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.16 validate_candidate_sequence

```moonlift
region validate_candidate_sequence(
    sequence: ptr(StencilPattern),
    count: index,
    facts: FactSet;

    valid: cont(contract: StencilContract),
    invalid: cont(reason: CandidateInvalidReason),
    oom: cont())
```

### 17.17 CandidateInvalidReason

```moonlift
union CandidateInvalidReason
    state_mismatch()
    effect_mismatch()
    control_mismatch()
    projection_mismatch()
    dependency_mismatch()
    liveness_mismatch()
    unsupported_boundary()
end
```

### 17.18 emit_candidate_moonlift_kernel

```moonlift
region emit_candidate_moonlift_kernel(
    candidate: ptr(CandidateFunction),
    contract: ptr(StencilContract),
    output_dir: ptr(u8);

    emitted: cont(source_path: ptr(u8)),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.19 compile_candidate_with_cranelift

```moonlift
region compile_candidate_with_cranelift(
    source_path: ptr(u8),
    target_arch: TargetArch,
    target_abi: TargetABI;

    compiled: cont(object_path: ptr(u8), symbol_name: ptr(u8)),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.20 extract_candidate_body

```moonlift
region extract_candidate_body(
    candidate: ptr(CandidateFunction),
    object_path: ptr(u8),
    symbol_name: ptr(u8);

    extracted: cont(body: CandidateBody),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.21 mine_holes_and_relocs

```moonlift
region mine_holes_and_relocs(
    body: ptr(CandidateBody),
    contract: ptr(StencilContract);

    mined: cont(fixture: StencilFixture),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.22 verify_stencil_fixture

```moonlift
region verify_stencil_fixture(
    fixture: ptr(StencilFixture);

    verified: cont(fixture: StencilFixture),
    rejected: cont(reason: VerificationFailure),
    oom: cont())
```

### 17.23 promote_fixture_to_code_stencil

```moonlift
region promote_fixture_to_code_stencil(
    fixture: ptr(StencilFixture),
    layer: LayerId;

    promoted: cont(stencil: CodeStencil),
    rejected: cont(reason: VerificationFailure),
    oom: cont())
```

### 17.24 generate_rewrite_stencils

```moonlift
region generate_rewrite_stencils(
    universe: ptr(StencilUniverse),
    layer: LayerId;

    generated: cont(rewrites: ptr(RewriteStencil), count: index),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

### 17.25 build_runtime_selector

```moonlift
region build_runtime_selector(
    universe: ptr(StencilUniverse),
    mode: JitBuildMode;

    built: cont(selector: StencilSelector),
    failed: cont(reason: BuildFailure),
    oom: cont())
```

---

## 18. Runtime entry and hotness regions

### 18.1 try_enter_jit

```moonlift
region try_enter_jit(
    runtime: ptr(JitRuntime),
    frame: VmFrameView;

    enter_compiled: cont(unit: ptr(ExecutableUnit), pinned: VmPinnedState),
    stay_interpreter: cont(reason: DeclineReason),
    compile_requested: cont(anchor: ptr(TraceAnchor)),
    oom: cont())
```

### 18.2 get_or_create_trace_anchor

```moonlift
region get_or_create_trace_anchor(
    runtime: ptr(JitRuntime),
    addr: SemanticAddr,
    kind: TraceAnchorKind;

    found: cont(anchor: ptr(TraceAnchor)),
    created: cont(anchor: ptr(TraceAnchor)),
    oom: cont())
```

### 18.3 record_hot_entry

```moonlift
region record_hot_entry(
    runtime: ptr(JitRuntime),
    anchor: ptr(TraceAnchor);

    cold: cont(),
    hot: cont(reason: RefinementReason),
    blacklisted: cont(reason: BlacklistReason))
```

### 18.4 maybe_compile_initial_plan

```moonlift
region maybe_compile_initial_plan(
    runtime: ptr(JitRuntime),
    anchor: ptr(TraceAnchor),
    frame: VmFrameView;

    compiled: cont(version: ptr(PlanVersion), unit: ptr(ExecutableUnit)),
    declined: cont(reason: DeclineReason),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

---

## 19. Planning regions

### 19.1 build_initial_virtual_state

```moonlift
region build_initial_virtual_state(
    frame: VmFrameView,
    range: SemanticRange,
    liveness: ptr(LivenessInfo);

    built: cont(state: VirtualState),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 19.2 discover_compilable_range

```moonlift
region discover_compilable_range(
    runtime: ptr(JitRuntime),
    anchor: ptr(TraceAnchor),
    frame: VmFrameView;

    discovered: cont(range: SemanticRange),
    declined: cont(reason: DeclineReason),
    oom: cont())
```

### 19.3 analyze_liveness

```moonlift
region analyze_liveness(
    range: SemanticRange;

    analyzed: cont(info: ptr(LivenessInfo)),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 19.4 select_stencil_plan

```moonlift
region select_stencil_plan(
    runtime: ptr(JitRuntime),
    source: PlanSource,
    initial: VirtualState,
    max_layer: LayerId;

    selected: cont(plan: ptr(StencilPlan)),
    declined: cont(reason: DeclineReason),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 19.5 select_next_node

```moonlift
region select_next_node(
    library: ptr(StencilLibrary),
    window: SemanticWindow,
    state: VirtualState,
    max_layer: LayerId;

    selected: cont(node: StencilNode, next_state: VirtualState, consumed_pcs: u16),
    rewrite: cont(rewrite: RewriteStencil, next_state: VirtualState, consumed_pcs: u16),
    declined: cont(reason: DeclineReason),
    oom: cont())
```

### 19.6 canonicalize_facts

```moonlift
region canonicalize_facts(
    pattern: StencilPattern,
    state: VirtualState,
    max_layer: LayerId;

    canonical: cont(key: CanonicalFactKey),
    failed: cont(reason: DeclineReason))
```

### 19.7 append_projection_nodes

```moonlift
region append_projection_nodes(
    plan: ptr(StencilPlan),
    requirement: BoundaryRequirement,
    state: VirtualState,
    addr: SemanticAddr;

    appended: cont(plan: ptr(StencilPlan)),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 19.8 verify_plan

```moonlift
region verify_plan(
    plan: ptr(StencilPlan);

    verified: cont(),
    rejected: cont(reason: PlanFailure))
```

---

## 20. Trace recording and refinement regions

### 20.1 maybe_refine_unit

```moonlift
region maybe_refine_unit(
    runtime: ptr(JitRuntime),
    unit: ptr(ExecutableUnit),
    reason: RefinementReason;

    refined: cont(new_version: ptr(PlanVersion), new_unit: ptr(ExecutableUnit)),
    unchanged: cont(reason: DeclineReason),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 20.2 record_trace

```moonlift
region record_trace(
    runtime: ptr(JitRuntime),
    anchor: ptr(TraceAnchor),
    unit: ptr(ExecutableUnit),
    max_steps: u32;

    recorded: cont(trace: ptr(TraceRecord)),
    unstable: cont(reason: TraceAbortReason),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 20.3 TraceAbortReason

```moonlift
union TraceAbortReason
    unsupported_opcode()
    unsupported_effect()
    too_many_exits()
    too_many_snapshots()
    unstable_type()
    blacklisted_anchor()
    debug_mode()
    oom_abort()
end
```

### 20.4 derive_trace_facts

```moonlift
region derive_trace_facts(
    trace: ptr(TraceRecord),
    previous: ptr(PlanVersion);

    derived: cont(facts: FactSet, deps: DependencySet),
    unstable: cont(reason: TraceAbortReason),
    oom: cont())
```

### 20.5 advance_refinement_layer

```moonlift
region advance_refinement_layer(
    runtime: ptr(JitRuntime),
    previous: ptr(PlanVersion),
    facts: FactSet,
    reason: RefinementReason;

    next_layer: cont(layer: LayerId),
    no_advance: cont(reason: DeclineReason))
```

Rules:

```text
next layer = previous.max_layer + 1
never exceed runtime.policy.max_runtime_layer
only allow L5 if runtime.policy.allow_layer5 and reason is stable trace-region reason
```

### 20.6 replan_with_layer

```moonlift
region replan_with_layer(
    runtime: ptr(JitRuntime),
    previous: ptr(PlanVersion),
    facts: FactSet,
    next_layer: LayerId,
    source: PlanSource;

    planned: cont(plan: ptr(StencilPlan)),
    declined: cont(reason: DeclineReason),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 20.7 create_plan_version

```moonlift
region create_plan_version(
    runtime: ptr(JitRuntime),
    previous: ptr(PlanVersion),
    source: PlanSource,
    plan: ptr(StencilPlan),
    facts: FactSet,
    rewrite: RewriteId;

    created: cont(version: ptr(PlanVersion)),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

---

## 21. Materialization regions

### 21.1 materialize_plan

```moonlift
region materialize_plan(
    runtime: ptr(JitRuntime),
    version: ptr(PlanVersion);

    materialized: cont(unit: ptr(ExecutableUnit)),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 21.2 layout_stencil_plan

```moonlift
region layout_stencil_plan(
    plan: ptr(StencilPlan);

    laid_out: cont(layout: ptr(CodeLayout)),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 21.3 CodeLayout

```moonlift
struct CodeLayout
    nodes: ptr(CodeLayoutNode)
    node_count: index
    total_code_size: CodeSize
    payload_size: u32
    fixups: ptr(CodeFixup)
    fixup_count: index
end
```

### 21.4 CodeLayoutNode

```moonlift
struct CodeLayoutNode
    plan_node: PlanNodeId
    code_offset: CodeOffset
    payload_offset: ByteOffset
    stencil: StencilId
end
```

### 21.5 CodeFixup

```moonlift
struct CodeFixup
    offset: CodeOffset
    kind: StencilRelocKind
    target_node: PlanNodeId
    target_exit: ExitId
    addend: i64
end
```

### 21.6 allocate_code_buffer

```moonlift
region allocate_code_buffer(
    arena: ptr(CodeArena),
    layout: ptr(CodeLayout);

    allocated: cont(code: CompiledCode),
    full: cont(),
    oom: cont())
```

### 21.7 copy_stencil_bytes

```moonlift
region copy_stencil_bytes(
    library: ptr(StencilLibrary),
    plan: ptr(StencilPlan),
    layout: ptr(CodeLayout),
    code: CompiledCode;

    copied: cont(),
    failed: cont(reason: PlanFailure))
```

### 21.8 stamp_stencil_holes

```moonlift
region stamp_stencil_holes(
    runtime: ptr(JitRuntime),
    plan: ptr(StencilPlan),
    layout: ptr(CodeLayout),
    code: CompiledCode;

    stamped: cont(),
    failed: cont(reason: PlanFailure))
```

### 21.9 write_stencil_payloads

```moonlift
region write_stencil_payloads(
    runtime: ptr(JitRuntime),
    plan: ptr(StencilPlan),
    layout: ptr(CodeLayout),
    code: CompiledCode;

    written: cont(),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 21.10 resolve_code_fixups

```moonlift
region resolve_code_fixups(
    plan: ptr(StencilPlan),
    layout: ptr(CodeLayout),
    code: CompiledCode;

    resolved: cont(),
    failed: cont(reason: PlanFailure))
```

### 21.11 publish_code

```moonlift
region publish_code(
    code: CompiledCode;

    published: cont(entry: ptr(void)),
    failed: cont(reason: PlanFailure))
```

### 21.12 construct_executable_unit

```moonlift
region construct_executable_unit(
    runtime: ptr(JitRuntime),
    version: ptr(PlanVersion),
    code: CompiledCode,
    entry: ptr(void);

    constructed: cont(unit: ptr(ExecutableUnit)),
    failed: cont(reason: PlanFailure),
    oom: cont())
```

### 21.13 verify_materialized_unit

```moonlift
region verify_materialized_unit(
    unit: ptr(ExecutableUnit);

    verified: cont(),
    rejected: cont(reason: PlanFailure))
```

---

## 22. Linking and execution regions

### 22.1 publish_plan_version

```moonlift
region publish_plan_version(
    runtime: ptr(JitRuntime),
    version: ptr(PlanVersion),
    unit: ptr(ExecutableUnit);

    published: cont(),
    failed: cont(reason: PlanFailure))
```

### 22.2 link_entry_cell

```moonlift
region link_entry_cell(
    runtime: ptr(JitRuntime),
    anchor: ptr(TraceAnchor),
    unit: ptr(ExecutableUnit);

    linked: cont(),
    failed: cont(reason: PlanFailure))
```

### 22.3 link_edge_cell

```moonlift
region link_edge_cell(
    runtime: ptr(JitRuntime),
    edge: ptr(EdgeCell),
    target: ptr(ExecutableUnit);

    linked: cont(),
    failed: cont(reason: PlanFailure))
```

### 22.4 execute_compiled_unit

```moonlift
region execute_compiled_unit(
    unit: ptr(ExecutableUnit),
    pinned: VmPinnedState;

    returned: cont(outcome: JitOutcome),
    side_exit: cont(exit: ptr(UnitExit)),
    boundary: cont(boundary: ptr(BoundaryFrame)),
    invalidated: cont(),
    oom: cont())
```

### 22.5 execute_jit_outcome

```moonlift
region execute_jit_outcome(
    runtime: ptr(JitRuntime),
    outcome: JitOutcome,
    frame: VmFrameView;

    resume_interpreter: cont(addr: SemanticAddr),
    continue_compiled: cont(unit: ptr(ExecutableUnit)),
    returned_to_caller: cont(value_count: u16),
    yielded: cont(),
    threw: cont(error_value: ValueId),
    oom: cont())
```

### 22.6 project_to_vm_state

```moonlift
region project_to_vm_state(
    projection: ptr(Projection),
    pinned: VmPinnedState;

    projected: cont(state: VmObservableState),
    failed: cont(reason: PlanFailure))
```

### 22.7 execute_boundary

```moonlift
region execute_boundary(
    runtime: ptr(JitRuntime),
    boundary: ptr(BoundaryFrame),
    state: VmObservableState;

    resume_compiled: cont(unit: ptr(ExecutableUnit)),
    resume_interpreter: cont(addr: SemanticAddr),
    yielded: cont(),
    threw: cont(error_value: ValueId),
    oom: cont())
```

### 22.8 BoundaryFrame

```moonlift
struct BoundaryFrame
    requirement: BoundaryRequirement
    helper: RuntimeHelperId
    projection: Projection
    return_edge: ptr(EdgeCell)
end
```

### 22.9 RuntimeHelperId

```moonlift
union RuntimeHelperId
    lua_arith_generic()
    lua_compare_generic()
    lua_gettable_generic()
    lua_settable_generic()
    lua_call_generic()
    lua_concat_generic()
    lua_length_generic()
    gc_barrier()
    allocator()
    debug_hook()
    error_throw()
end
```

---

## 23. Invalidation and reclamation regions

### 23.1 invalidate_dependency

```moonlift
region invalidate_dependency(
    runtime: ptr(JitRuntime),
    dep: DependencyKey;

    invalidated: cont(count: u32),
    none: cont())
```

### 23.2 invalidate_unit

```moonlift
region invalidate_unit(
    runtime: ptr(JitRuntime),
    unit: ptr(ExecutableUnit),
    reason: InvalidationReason;

    invalidated: cont(),
    already_invalid: cont())
```

### 23.3 revert_edge_cell

```moonlift
region revert_edge_cell(
    edge: ptr(EdgeCell);

    reverted: cont(),
    already_interpreter: cont())
```

### 23.4 mark_jit_roots

```moonlift
region mark_jit_roots(
    runtime: ptr(JitRuntime),
    unit: ptr(ExecutableUnit);

    marked: cont(),
    failed: cont())
```

### 23.5 reclaim_code

```moonlift
region reclaim_code(
    runtime: ptr(JitRuntime);

    reclaimed: cont(bytes: u64),
    nothing: cont())
```

---

## 24. Runtime refinement policy

### 24.1 The layer is the tier

A `PlanVersion` has a `max_layer`. Runtime selection is restricted to stencils and rewrites whose `layer <= max_layer`.

The initial compiled plan:

```text
max_layer = L0
```

Each hot refinement:

```text
next_layer = previous.max_layer + 1
```

unless it exceeds policy limits.

### 24.2 Refinement from a hot entry

```text
entry becomes hot
build L0 plan
materialize unit v0
later entry/loop remains hot
record facts
replan with L1
materialize unit v1
link entry cell to v1
```

### 24.3 Refinement from a hot side exit

```text
side exit taken often
record trace from side exit
derive facts
if current max_layer < policy.max_runtime_layer:
    replan side anchor with next layer
else if L5 allowed and trace stable:
    replan with L5 trace-region layer
```

### 24.4 One refinement step is one layer advance

The runtime does not run fixed-point optimization. It does not search all layers immediately. It climbs the same ladder used to build the library.

This gives staged compilation:

```text
small cheap code first
larger stencil coverage later
trace-region shapes only for proven hot paths
```

---

## 25. Stencil closure method

### 25.1 Offline speed-max closure

The library generator operates by bounded-arity closure.

```text
L0 = primitive opcode/fact stencils
for layer in 1..4:
    enumerate all contract-valid combinations of up to 4 current stencil nodes
    generate low-level Moonlift candidate kernels
    compile through Cranelift
    mine holes/relocs/clobbers
    verify contracts
    measure
    promote fastest survivors
```

`L5` is generated only from trace-region motifs.

### 25.2 Growth despite arity cap

Each closure step combines up to four current stencil nodes. Since compound stencils become atoms for the next layer, the absorbed bytecode length grows exponentially:

```text
L0 ~= 1 original bytecode
L1 ~= 4 original bytecodes
L2 ~= 16 original bytecodes
L3 ~= 64 original bytecodes
L4 ~= 256 original bytecodes
L5 ~= 1024 original bytecodes
```

These are approximate upper bounds, not promises. Real stencils are constrained by effects, exits, dependencies, projections, and measured usefulness.

### 25.3 Speed-max mode

In speed-max builds:

```text
generate all contract-valid candidates inside the layer frontier
ignore code size as an initial pruning criterion
measure speed
select fastest survivor per fact class
```

Code size may still be recorded because it affects instruction-cache behavior. But it is not a first-order rejection reason in speed-max mode.

### 25.4 Corpus seeding

The first curated stencil frontier should be seeded from real Lua code:

```text
collect Lua corpus
compile source to VM bytecode
profile opcode windows
profile operand shapes
profile loops/calls/table accesses
use observed windows to seed L1 candidates
then run closure
```

The corpus profile is evidence. It is not a semantic authority.

---

## 26. Correctness invariants

### 26.1 Semantic equivalence

For every `CodeStencil`:

```text
StencilContract(stencil) == Contract(expanded interpreter-derived sequence)
under required facts
```

### 26.2 Rewrite equivalence

For every `RewriteStencil`:

```text
BeforePlan == AfterPlan
under required facts
for observable VM state, exits, effects, projections, and dependencies
```

### 26.3 Projection precision

Every side exit, helper boundary, yield, throw, debug hook, or GC point has a projection that reconstructs the correct VM-observable state.

### 26.4 Dependency safety

If compiled code depends on a mutable assumption, that assumption is recorded in `DependencySet` and registered in `DependencyIndex`. When the assumption changes, dependent units are invalidated or their edges are reverted.

### 26.5 Cell linking safety

Entry cells and edge cells may be updated to point to newer units. Old units remain executable until no activation can return to them.

### 26.6 Runtime no-synthesis invariant

The runtime may select and materialize existing stencils. It must not create new stencil kinds.

---

## 27. Testing regions

### 27.1 test_stencil_contract

```moonlift
region test_stencil_contract(
    stencil: ptr(CodeStencil),
    cases: ptr(StencilTestCase),
    count: index;

    passed: cont(),
    failed: cont(case_index: index, reason: VerificationFailure),
    oom: cont())
```

### 27.2 StencilTestCase

```moonlift
struct StencilTestCase
    input_state: VmObservableState
    expected_state: VmObservableState
    expected_outcome: JitOutcome
end
```

### 27.3 test_rewrite_contract

```moonlift
region test_rewrite_contract(
    rewrite: ptr(RewriteStencil),
    before: ptr(StencilPlan),
    after: ptr(StencilPlan);

    passed: cont(),
    failed: cont(reason: VerificationFailure))
```

### 27.4 differential_execute_unit

```moonlift
region differential_execute_unit(
    runtime: ptr(JitRuntime),
    unit: ptr(ExecutableUnit),
    initial: VmObservableState;

    matched: cont(),
    diverged: cont(interpreter: VmObservableState, compiled: VmObservableState),
    oom: cont())
```

### 27.5 fuzz_refinement_ladder

```moonlift
region fuzz_refinement_ladder(
    runtime: ptr(JitRuntime),
    corpus: ptr(LuaCorpus),
    max_generation: Generation;

    passed: cont(),
    failed: cont(reason: VerificationFailure),
    oom: cont())
```

---

## 28. Expected emergent stencil families

The closure process is expected to produce these families naturally:

```text
move/load/store absorption
constant + arithmetic folding
guard absorption
compare + branch fusion
numeric for-loop bodies
array table access + accumulator loops
string-key/shape table access
GETTABUP/global lookup + call
SELF/method lookup + call
projection bundles
return fusion
fallthrough/layout rewrites
trace-region loop bodies
```

Examples:

```text
LOADK + MOVE                      -> LOADK_to_final_slot
LOADK + ADD                       -> ADDK
ADD + MOVE                        -> ADD_to_final_slot
ADD + RETURN                      -> ADD_RETURN
EQ + JMP                          -> EQ_BRANCH
TEST + JMP                        -> TRUTHY_BRANCH
GETTABLE_array + ADD              -> GETARRAY_ADD
FORLOOP + GETARRAY + ADD          -> FORLOOP_GETARRAY_ADD_ACC
GETTABUP + CALL                   -> GLOBAL_CALL
SELF_shape + CALL                 -> METHOD_CALL_SHAPE
project_slot x N                  -> PROJECT_BUNDLE_N
pure dead operation               -> empty rewrite
```

---

## 29. Minimal implementation path

### 29.1 First executable slice

```text
L0 only
one hot straight-line range
MOVE / LOADK / LOADI / ADD_i64 / RETURN1
side exits project to interpreter
materializer copies and patches stencils
EntryCell links to unit
```

### 29.2 Second slice

```text
L1 local compounds
ADD+RETURN
LOADK+ADD
MOVE collapse
TEST+JMP
projection bundle 1..4
```

### 29.3 Third slice

```text
trace fact recording
generation advancement L0 -> L1 -> L2
replan same anchor with max_layer incremented
EdgeCell relink
```

### 29.4 Fourth slice

```text
corpus seeding
speed-max L4 library build
selector table generated from measured survivors
```

### 29.5 Fifth slice

```text
L5 trace-region lab
hot trace motifs only
fold table/global/method/call indirections
```

---

## 30. Final statement

The Moonlift Lua VM JIT is a copy-and-patch runtime over a layered stencil library.

The interpreter is the semantic source. The offline builder generates and measures the stencil universe. The runtime compiles by selecting existing stencil products, materializing them, and linking them through cells. A compiled unit is a `PlanVersion` materialized into an `ExecutableUnit`. Runtime optimization is layer advancement: hot units are replanned with permission to use the next stencil-library layer.

There are no separate JIT backends. There is no runtime Cranelift. There is no bytecode mutation. There is no hidden optimizer.

There is one design:

```text
explicit facts
explicit effects
explicit projections
explicit dependencies
explicit stencil products
explicit plan versions
explicit cells
explicit refinement ladder
```

That is the JIT.

---

## 31. References

This design is informed by:

- Copy-and-Patch Compilation: binary stencils, holes, and fast copy/patch runtime materialization.
- Superinstruction work: fusing VM instruction sequences into larger execution units.
- Trace-based JIT work and LuaJIT practice: hot path recording, side exits, and dynamic fact specialization.
- Deegen: generated interpreter and baseline JIT machinery for dynamic languages, including LuaJIT Remake.
- Moonlift explicit-programming documents: typed control, regions, continuations, emit composition, and explicit products.
