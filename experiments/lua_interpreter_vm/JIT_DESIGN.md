# Moonlift Lua Interpreter VM — Copy-and-Patch JIT Design

Scope: Moonlift-native JIT architecture for `experiments/lua_interpreter_vm`.

This rewrite collapses the previous multi-tier story into one backend and two possible plan
frontends:

```text
Interpreter regions define semantics.
The stencil library is derived from those regions or checked against their contracts.
A baseline bytecode-range planner builds StencilPlans now.
A future trace recorder may build better StencilPlans later.
Every executable unit is materialized by copy/stamp/payload/fixup/publish/link.
VirtualState selects legal stencil variants.
Effects select boundary/projection stencils.
EdgeCells link compiled units.
Proto.code remains immutable semantic bytecode.
```

The important simplification:

```text
There are not many JIT backends.
There is one JIT backend: copy-and-patch stencil materialization.

There are not many tiers to implement now.
There is the interpreter and a baseline stencil planner.

Tracing is not a second backend.
A trace recorder, if added later, is only another StencilPlan producer.
```

---

# 1. Design doctrine

## 1.1 The JIT is a Moonlift explicit-programming system

The JIT is not a bag of runtime tricks hidden behind mutable side tables. It is a Moonlift system
whose data tree and control tree are explicit.

Data products:

```text
SpecializationContext
VirtualState
TypedValue
FactSet
Effect
Projection
CodeStencil
StencilPlan
ExecImage
ExecutableUnit
EntryCell
EdgeCell
TraceRecord
```

Control products:

```text
SelectPlan
MaterializePlan
PublishUnit
ExecuteJitOutcome
ProjectToInterpreter
EnterBoundary
ResolveEdge
InvalidateDependency
RecordTrace
```

Every distinction that matters to correctness or code generation must appear as a product, a fact,
a continuation, or a declared protocol. If a fact only lives in a comment, callback convention,
magic number, backend-only pass, or mutable global map, it is not part of the design yet.

## 1.2 The interpreter is the semantic source

The interpreter already encodes Lua semantics as Moonlift regions:

```text
vm_resume
  -> vm_loop
      -> dispatch_instruction
          -> opcode handlers
          -> runtime/helper regions
```

The JIT must not re-author Lua semantics by hand. It may compile, specialize, or mine code shapes
from interpreter regions, but the semantic authority remains the region graph.

A stencil is valid only if it implements an interpreter-derived contract:

```text
input state shape
output state shape
effect flags
projection requirements
dependency requirements
ABI assumptions
continuation shape
```

Hand-written stencils are allowed during bootstrapping, but only as implementations of such
contracts. They are never semantic authorities.

## 1.3 `Proto.code` is immutable

`Proto.code` is the semantic program.

```text
no quickened bytecode
no inserted deopt opcodes
no semantic bytecode mutation
```

All mutable execution state lives beside the bytecode:

```text
ExecImage
EntryCell
EdgeCell
ExecutableUnit
UnitProfile
ExitProfile
DependencyIndex
InlineCacheRecord
TraceAnchor
```

This keeps the interpreter simple, keeps debug/error/recovery semantics grounded, and lets compiled
code be discarded without repairing bytecode.

## 1.4 Runtime compilation does not run a general compiler

Cranelift may compile stencil generators ahead of time.
Moonlift/Lua may generate monomorphic stencil candidate regions ahead of time.
The runtime JIT does not invoke Cranelift and does not encode arbitrary instructions.

At runtime the JIT performs:

```text
select
layout
copy
stamp
payload
fixup
publish
link
```

If a runtime code shape matters, the architectural answer is:

```text
add a stencil variant
add a supernode
improve stencil selection
or decline compilation
```

A direct encoder may exist as a debugging or emergency tool. It is not the architecture.

---

# 2. Execution model

## 2.1 Modes, not a tower of tiers

The VM has three execution modes. Only the first two are required for the first implementation.

```moonlift
union ExecutionMode
    interpreter()
    baseline(unit: ptr(ExecutableUnit))
    trace(unit: ptr(ExecutableUnit))
end
```

Meaning:

| Mode | Purpose | Required now? |
|---|---|---|
| `interpreter` | semantic scheduler and fallback | yes |
| `baseline` | copy-and-patch compiled bytecode range | yes |
| `trace` | future hot-path StencilPlan producer | no |

`baseline` and `trace` do not imply different machine-code backends. Both point to an
`ExecutableUnit` materialized from a `StencilPlan`.

## 2.2 Baseline first

The first compiler frontend is a bytecode-range planner:

```text
SemanticRange + profile + liveness
  -> VirtualState
  -> StencilPlan
  -> ExecutableUnit
```

A baseline plan usually starts from generic opcode-family stencils:

```text
MOVE_generic
LOADK_generic
ADD_generic
GETTABLE_generic
CALL_generic
RETURN_generic
```

As facts appear, the same planner chooses specialized variants:

```text
ADD_int_guarded
ADD_int_known
ADDI_int_guarded
GETTABLE_array_i64_ic1
GETTABLE_string_shape_ic1
CALL_known_lclosure
FORLOOP_i64
```

This is still baseline. Specialization does not create a new tier.

## 2.3 Tracing later

Tracing is an optional future frontend:

```text
hot loop / hot side exit
  -> record executed path
  -> collect guards and snapshots
  -> build TraceRecord
  -> lower TraceRecord to StencilPlan
  -> materialize ExecutableUnit
```

The trace recorder is allowed to produce better plans because it has path facts that the baseline
planner does not:

```text
this branch direction was taken
this slot stayed integer
this table shape stayed stable
this call target stayed monomorphic
this side exit is frequent enough to link
```

But tracing must reuse the same backend:

```text
CodeStencil
Projection
Boundary
DependencySet
EdgeCell
CodeArena
MaterializeStencil
PublishUnit
```

A trace is a plan shape, not a different compiler.

---

# 3. Stencil families

## 3.1 Generic opcode-family roots

The first stencil family for a bytecode opcode is a dispatch-erased version of the interpreter
handler.

It is not the whole interpreter loop. It is:

```text
interpreter opcode handler semantics
minus fetch/decode/switch dispatch
plus holes for operands/continuations/helpers
plus explicit effects and projections
```

Example root family:

```text
OP_ADD
  st_add_generic_stack
```

Then facts grow the family:

```text
OP_ADD
  st_add_generic_stack
  st_add_int_guarded_stack
  st_add_int_known_stack
  st_add_float_guarded_stack
  st_addi_int_guarded_stack
  st_add_reg_reg_to_reg
```

So the rule is:

```text
one generic stencil root per supported opcode/opcode family
many specialized variants as facts justify them
```

Not every Lua opcode must have a stencil before the first JIT runs. Unsupported opcodes terminate
the compiled range and return to the interpreter.

## 3.2 Supernodes are stencil variants

A supernode is a larger physical stencil for a frequent local pattern:

```text
LOADK + ADD
MOVE + CALL
GETTABUP + CALL
FORLOOP + ADD
projection bundle
runtime boundary prelude + root projection bundle
```

A supernode is not a semantic opcode and not a JIT tier. It is a stencil whose contract is equal to
the expanded sequence of smaller state operations.

Promotion rule:

```text
promote a supernode only if it preserves the expanded semantic contract
and reduces hot bytes, hot branches, or materialization overhead enough to justify library size
```

## 3.3 Stencil naming

Stencil names encode semantic shape, not backend trivia.

```text
<domain>.<operation>.<input_shape>.<output_shape>.<continuation_shape>
```

Examples:

```text
value.load_i64.imm_to_sA.fall
value.move.sB_to_sA.fall
guard.int.sA.next_or_exit
arith.add_i64.sB_sC_to_sA.fall
arith.add_i64_guarded.sB_sC_to_sA.next_or_exit
branch.truthy.sA.true_or_false
table.get_array_i64.ic1.sT_sK_to_sA.next_or_slow
call.known_lclosure.sF_args.enter_lua
projection.interpreter.live_slots
edge.jump_indirect.target
```

Names like `OP_ADD_1` or `FAST_GETTABLE_2` are not stable design names.

---

# 4. Where stencils come from

The stencil library grows from evidence.

## 4.1 Derivation path

Preferred path:

```text
Moonlift interpreter region
  -> SpecializationContext
  -> partial evaluation / context specialization
  -> bytecode-erased specialized region
  -> AOT Cranelift object code
  -> CandidateFunction
  -> StencilFixture
  -> CodeStencil
```

A candidate is not a stencil yet.

```text
CandidateFunction = compiled symbol from Moonlift/Cranelift
StencilFixture   = classified useful byte range with holes/relocs/ABI/clobbers
CodeStencil      = fixture promoted to library product with semantic contract and tests
```

## 4.2 Stencil mining

The mining loop:

```text
run representative Lua VM programs
observe hot opcode/pattern distributions
generate Moonlift candidate kernels
dump AOT machine code
classify recurring instruction byte ranges
turn stable byte ranges into StencilFixture records
promote verified fixtures to CodeStencil records
promote frequent adjacent patterns to supernodes
```

Initial evidence sources:

```text
opcode histograms
opcode pair/triple histograms
bounded dynamic traces keyed by (proto, pc, opcode)
loop/motif spectra
interpreter handler bodies
partial-evaluated block candidates
future recorded traces
side-exit profiles
boundary/effect profiles
```

## 4.3 Promotion gate

A candidate may enter the real stencil library only after it has:

```text
name
semantic contract
input StateShape
output StateShape
Effect
BoundaryRequirement if any
ProjectionRequirement if any
StencilConfig axes
body byte range
holes
relocs
payloads
ABI metadata
clobber metadata
negative tests
materialization test
execution test
```

Promotion must be ruthless. The library is executable specification, not a dump folder.

---

# 5. Semantic addressing and ranges

```moonlift
struct SemanticAddr
    proto: ptr(Proto)
    pc: index
    frame: u32
end

struct SemanticRange
    proto: ptr(Proto)
    start_pc: index
    end_pc: index
    shape: u8
end
```

Range shapes:

```text
BLOCK       single-entry bytecode range with explicit exits
LOOP        loop-header anchored range
TRACE       recorded hot path range
CALL_ENTRY  child-frame entry range
RESUME      resume-parent pc range
```

`TRACE` is a range shape. It is not a backend.

---

# 6. SpecializationContext

```moonlift
struct SpecializationContext
    proto: ptr(Proto)
    pc: index
    opcode: u16
    word: u32
    range: SemanticRange
    shape: u8
    flags: u32
end
```

A specialization context contains:

```text
known opcode
known raw instruction word
known decoded operands
known continuation shape
known effect class
known local state interface
holes for runtime-known values
```

Context specialization erases interpreter dispatch:

```text
switch opcode -> selected opcode body
bytecode operands -> constants or holes
continuations -> labels / relocs / EdgeCells
```

For the first baseline compiler, `SpecializationContext` may be built directly from bytecode decode
instead of from full partial evaluation. The contract remains the same.

---

# 7. VirtualState

`VirtualState` is the planner's current knowledge of semantic VM state. It is not a heavyweight VM
runtime object.

```moonlift
struct VirtualState
    addr: SemanticAddr
    frame: u32
    base: index
    top: index
    slot_values: ptr(u32)      -- slot -> ValueId
    slot_count: index
    values: ptr(TypedValue)
    value_count: index
    facts: FactSet
    deps: DependencySet
end
```

It tracks:

```text
slot R0 contains ValueId v0
v0 is proven Int
v1 is loaded in a pass-through register
this guard depends on table shape epoch
this inline cache depends on global table generation
this path selected the true branch
```

Selection rule:

```text
VirtualState + opcode + profile + effect requirement
  -> legal StencilConfig choices
  -> cheapest profitable CodeStencil
```

## 7.1 TypedValue

```moonlift
struct TypedValue
    id: u32
    kind: u8
    type_tag: u32
    payload0: u64
    payload1: u64
    op: u16
    lhs: u32
    rhs: u32
end
```

Examples:

```text
add_wrap_i64(Int, Int) -> Int
add_wrap_i64(Unknown, Int) -> no known-int stencil
load_const(K42) -> ConstInt(42)
guard_int(v0) success -> Fact(v0 is Int)
```

Lua integer arithmetic wraps. There is no overflow exit for ordinary integer `+`, `-`, or `*`.
Operations that can fail for semantic reasons, such as division by zero, metamethod dispatch, or
conversion failure, must encode that possibility in effects/continuations.

---

# 8. Facts and dependencies

Facts describe what the planner may assume.
Dependencies describe what can invalidate those assumptions.

```moonlift
struct Fact
    kind: u16
    value: u32
    aux0: u64
    aux1: u64
end

struct DependencyKey
    kind: u16
    ptr0: ptr(u8)
    aux0: u64
    generation: u64
end
```

Fact examples:

```text
ValueId v0 is TAG_INTEGER
ValueId v1 is TAG_TABLE
slot R3 aliases ValueId v3
table T has shape_epoch E
metatable of T is absent
call target is closure C
branch condition is true on this path
```

Dependency examples:

```text
table shape epoch
metatable epoch
global table generation
closure/proto generation
native function identity
```

No speculative stencil may be selected without recording the dependency that makes its fact valid.

---

# 9. Effects choose boundaries

Every stencil carries an `Effect`.

```moonlift
struct Effect
    flags: u64
end

struct BoundaryRequirement
    flags: u64
end
```

Effect flags:

```text
PURE
MAY_BRANCH
MAY_THROW
MAY_ALLOC
MAY_GC
MAY_CALL_LUA
MAY_YIELD
MAY_RUN_HOOK
MAY_CALL_METAMETHOD
MAY_OBSERVE_STACK
MAY_READ_MUTABLE_HEAP
MAY_WRITE_HEAP
MAY_NEED_BARRIER
MAY_INVALIDATE_DEPS
```

Boundary selection:

```text
MAY_GC             -> ROOTS projection
MAY_ALLOC          -> ROOTS projection
MAY_CALL_LUA       -> ROOTS + RESUME projections
MAY_YIELD          -> RESUME projection
MAY_RUN_HOOK       -> DEBUG + RESUME + ROOTS projections
MAY_OBSERVE_STACK  -> INTERPRETER projection
MAY_THROW          -> ERROR projection
MAY_NEED_BARRIER   -> BARRIER projection/stencil
side exit          -> TARGET or INTERPRETER projection
```

This is the safepoint system. There is no informal list of safepoints elsewhere.

---

# 10. Projections

A projection is a semantic contract for making VM state visible.

```moonlift
struct Projection
    id: u32
    kind: u8
    addr: SemanticAddr
    frame: u32
    base: index
    top: index
    slots: ptr(ProjectedSlot)
    slot_count: index
    roots: ptr(u32)
    root_count: index
    resume: ResumeProjection
    error: ErrorProjection
    debug: DebugProjection
end
```

Projection kinds:

```text
INTERPRETER
ROOTS
RESUME
DEBUG
ERROR
BARRIER
TARGET
```

A projection speaks in semantic values, not physical registers:

```text
slot R2 must contain ValueId v17
ValueId v9 must be visible as a GC root
frame.pc must be pc 42
frame.resume_pc must be pc 43
L.top must equal top
```

Projection lowering selects recovery stencils:

```text
project.write_slot_value
project.write_frame_pc
project.write_frame_top
project.write_thread_top
project.write_root_value
project.write_resume_mode
project.write_resume_payload
project.write_error_value
project.call_barrier
project.reload_pinned_state
```

Deoptimization, GC roots, debug visibility, error state, and resume state are all copy-and-patchable
recovery code.

---

# 11. Stencil products

## 11.1 CodeStencil

```moonlift
struct StencilHole
    offset: index
    kind: u8
    width: u8
    aux: u32
end

struct StencilReloc
    offset: index
    kind: u8
    target: u32
    width: u8
end

struct StencilPayload
    offset: index
    kind: u8
    size: index
    aux0: u64
    aux1: u64
end

struct CodeStencil
    kind: u8
    op: u16
    effect: Effect
    bytes: ptr(u8)
    size: index
    holes: ptr(StencilHole)
    hole_count: index
    relocs: ptr(StencilReloc)
    reloc_count: index
    payloads: ptr(StencilPayload)
    payload_count: index
    abi: u8
end
```

Hole kinds:

```text
slot displacement
constant address
immediate integer/float bits
Value tag/aux/bits
EdgeCell pointer
InlineCacheRecord pointer
runtime helper pointer
projection id
boundary id
literal-pool offset
```

Relocation kinds:

```text
fallthrough continuation
branch target
side exit
boundary stub
runtime helper call
edge-cell load site
trace-link target
```

Payload kinds:

```text
literal bytes
literal Value
inline-cache metadata
side-exit metadata
projection metadata
boundary metadata
debug metadata
```

## 11.2 StencilConfig

```moonlift
struct StencilConfig
    kind: u16
    op: u16
    value_type: u16
    lhs_loc: u8
    rhs_loc: u8
    out_loc: u8
    passthrough_mask: u64
    pattern_id: u32
end
```

Axes:

```text
operation kind
value type
lhs/rhs location
output location
continuation form
pass-through register mask
projection form
boundary form
supernode pattern
```

This is the lightweight register-allocation protocol. The runtime planner chooses variants; it does
not solve a full global register-allocation problem.

## 11.3 StencilPlan

```moonlift
struct StencilNode
    stencil: ptr(CodeStencil)
    config: StencilConfig
    next: u32
    alt: u32
    label: u32
    boundary_id: u32
    projection_id: u32
end

struct CodeFixup
    site_offset: index
    target_label: u32
    kind: u8
    aux: u32
end

struct StencilPlan
    nodes: ptr(StencilNode)
    node_count: index
    fixups: ptr(CodeFixup)
    fixup_count: index
    estimated_size: index
end
```

The planner builds a `StencilPlan`. The materializer turns it into bytes.

---

# 12. Materialization pipeline

The names are precise:

```text
select    choose stencil variants
layout    assign labels and offsets
copy      copy precompiled bytes
stamp     fill local holes/immediates/displacements
payload   write literal pools or side data
fixup     resolve layout-dependent branch/call/rip-relative sites
publish   make bytes executable / synchronize icache
link      update mutable EdgeCells after publication
```

Terminology:

```text
stamp  = fill stencil holes during materialization
fixup  = resolve layout-dependent addresses before publication
link   = mutate EdgeCells after publication
patch  = reserved for post-publication instruction-stream mutation
```

Core machines:

```text
SelectStencilPlan
LayoutStencilPlan
AllocateCodeBuffer
MaterializeStencil
FinalizeCodeBuffer
PublishUnit
PatchEdgeCell
RevertEdgeCell
```

The v1 rule:

```text
Post-publication mutation is data mutation only: EdgeCells and IC records.
Instruction-stream patching is not required for v1.
```

---

# 13. CPS and fallthrough

Stencils compose through continuation-passing structure.

A `StencilNode` may have:

```text
next
alt / branch
boundary
runtime helper
side exit
edge exit
```

During layout, adjacent continuations may fall through. Unnecessary jumps between consecutive
stencil nodes are elided.

This is the critical difference between copy-and-patch as toy concatenation and copy-and-patch as a
real backend:

```text
CPS stencil graph -> layout -> fallthrough-optimized native code
```

---

# 14. Executable image

```moonlift
struct ExecImage
    proto: ptr(Proto)
    generation: u64
    blocks: ptr(BlockInfo)
    block_count: index
    liveness: ptr(LivenessInfo)
    entries: ptr(EntryCell)
    entry_count: index
    units: ptr(ptr(ExecutableUnit))
    unit_count: index
    deps: ptr(DependencyIndex)
    stencils: ptr(StencilLibrary)
    code_arena: ptr(CodeArena)
end
```

`ExecImage` is the mutable executable overlay for one immutable `Proto`.

It owns:

```text
entry cells
edge cells
published units
profiles
liveness summaries
dependency index
code arena
```

It does not own or mutate semantic bytecode.

---

# 15. EntryCells and EdgeCells

## 15.1 EntryCell

```moonlift
struct EntryCell
    addr: SemanticAddr
    target: ptr(u8)
    fallback: ptr(u8)
    unit: ptr(ExecutableUnit)
    counter: u32
    status: u8
    generation: u64
end
```

An entry cell is the mutable gate from interpreter scheduling into compiled code.

Entry gates:

```text
function entry
loop header/backedge
branch target
call-entry child frame
resume-parent pc
hot side-exit target
```

## 15.2 EdgeCell

```moonlift
struct EdgeCell
    target: ptr(u8)
    fallback: ptr(u8)
    target_unit: ptr(ExecutableUnit)
    kind: u8
    status: u8
    generation: u64
end
```

Baseline transfer form:

```asm
jmp qword ptr [edge.target]
```

Hot control repair is a data update:

```text
edge.target = target_unit.code.entry
edge.target_unit = target_unit
```

No `Proto.code` mutation. No required instruction-stream patching.

---

# 16. ExecutableUnit

```moonlift
struct ExecutableUnit
    id: u32
    mode: u8              -- baseline or trace
    version: u32
    status: u8
    range: SemanticRange
    abi: UnitABI
    input_state: StateShape
    output_state: StateShape
    ops: ptr(StateOp)
    op_count: index
    boundaries: ptr(Boundary)
    boundary_count: index
    projections: ptr(Projection)
    projection_count: index
    lowerings: ptr(ProjectionLowering)
    lowering_count: index
    code: ptr(CompiledCode)
    entries: ptr(ptr(EntryCell))
    entry_count: index
    edges: ptr(ptr(EdgeCell))
    edge_count: index
    exits: ptr(UnitExit)
    exit_count: index
    profile: UnitProfile
    deps: DependencySet
end
```

A unit is a published `StencilPlan` plus semantic side tables.

Modes:

```text
BASELINE  generated from bytecode range planner
TRACE     generated from trace recorder/planner
```

Again: modes are planner provenance, not backend tiers.

---

# 17. VM integration

The interpreter loop remains the semantic scheduler.

Compiled code may return a `JitOutcome`:

```moonlift
struct JitOutcome
    status: u8
    frame: ptr(Frame)
    pc: index
    base: index
    top: index
    code: ptr(Instr)
    constants: ptr(Value)
    nres: i32
    err: i32
    target_unit: ptr(ExecutableUnit)
    native_closure: ptr(CClosure)
    lua_frame: ptr(Frame)
end
```

`ExecuteJitOutcome` maps the outcome back into existing VM continuations:

```text
next
do_jump
resume_parent
enter_lua
enter_native
returned
yielded
error
oom
```

The JIT is therefore a participant in the existing control tree. It is not a separate control
universe.

---

# 18. Baseline planner

The baseline planner compiles validated bytecode ranges.

Input:

```text
Proto
SemanticRange
UnitProfile
LivenessInfo
StencilLibrary
```

Output:

```text
StencilPlan
Projection list
Boundary list
DependencySet
UnitProfile hooks
```

Algorithm:

```text
initialize VirtualState at range entry
for each bytecode pc in range:
    decode word
    build SpecializationContext
    choose generic or specialized stencil family
    update VirtualState from stencil output contract
    add projections at boundaries and side exits
    terminate range when unsupported effect/opcode appears
verify plan
materialize unit
link entry cell
```

First supported opcode families:

```text
MOVE
LOADI / LOADF / LOADK / LOADNIL / LOADTRUE / LOADFALSE
ADD / SUB / MUL integer guarded/known
EQ / LT / LE integer guarded
TEST / truthiness branch
JMP
FORPREP / FORLOOP i64
RETURN0 / RETURN1
projection/interpreter-exit
edge jump
```

Unsupported bytecodes end the compiled range or exit to the interpreter.

---

# 19. Trace planner, future

Tracing is optional. When it exists, it records path facts and snapshots, then emits a `StencilPlan`.

```moonlift
struct TraceAnchor
    addr: SemanticAddr
    kind: u8
    counter: u32
    blacklist: u32
end

struct TraceRecord
    anchor: TraceAnchor
    ops: ptr(StateOp)
    op_count: index
    guards: ptr(Guard)
    guard_count: index
    snapshots: ptr(Projection)
    snapshot_count: index
    deps: DependencySet
end
```

Trace recording sources:

```text
loop header hot count
side exit hot count
branch target hot count
call target hot count
```

Trace plan lowering:

```text
TraceRecord + VirtualState + StencilLibrary
  -> specialized StencilPlan
  -> ExecutableUnit(mode = TRACE)
```

Trace aborts return to the interpreter and may blacklist the anchor.

Trace rules:

```text
No trace has authority over semantics.
Every guard has a projection snapshot.
Every speculative fact has a dependency.
Every side exit has a target/interpreter projection.
Trace linking uses EdgeCells first.
Instruction-stream patching is optional later.
```

---

# 20. Inline caches

Inline caches are mutable data first.

```moonlift
struct InlineCacheRecord
    kind: u16
    status: u8
    hit_count: u32
    miss_count: u32
    key0: u64
    key1: u64
    value0: u64
    value1: u64
    dep: DependencyKey
    fallback: ptr(u8)
end
```

Fast IC stencils read an `InlineCacheRecord*` and branch to a slow boundary on miss.

Examples:

```text
table.get_array_i64.ic1
table.get_string_shape.ic1
table.set_string_shape.ic1
global.get_string.ic1
call.known_lclosure.ic1
call.known_cclosure.ic1
```

Mutation policy:

```text
v1: update IC records only
later: optional inline slabs or instruction-stream patching
```

This keeps v1 coherent with the EdgeCell data-linking model.

---

# 21. Code memory

```moonlift
struct CodeSlab
    rw_base: ptr(u8)
    rx_base: ptr(u8)
    size: index
    used: index
    flags: u32
end

struct CodeArena
    slabs: ptr(ptr(CodeSlab))
    slab_count: index
    current: ptr(CodeSlab)
    flags: u32
end
```

Policy:

```text
allocate by slabs
prefer RW/RX dual mapping
avoid per-unit mprotect
publish through architecture icache boundary
reclaim only at quiescence
```

Compiled code must be reclaimable without changing `Proto.code`.

---

# 22. Verification

Verification checks plans and products, not a second hand-written semantics.

Checks:

```text
selected stencils satisfy typed inputs
stencil output contract updates VirtualState correctly
stencil effects cover StateOp/effect contract
boundary effects have required projection stencils
projection stencils cover live slots/roots/resume/debug/error needs
supernode contract equals expanded StateOp contract
holes are all stamped
payloads are all written
fixups are all resolved
edge cells have fallbacks
dependencies cover speculative facts
trace guards have snapshots
published unit has valid entry and exit ABI
```

If a plan cannot be verified, it is not compiled.

---

# 23. Performance contract

Hot runtime compile cost:

```text
select + layout + memcpy + stamp + payload + fixup + publish + link
```

Hot execution cost:

```text
raw stencil code + exit_rate * projection_stencil_cost
```

Compile threshold:

```text
compile_latency < expected_iterations * per_iteration_savings
```

Copy-and-patch attacks compile latency.
Stencil variants, pass-through forms, inline caches, and supernodes attack emitted-code quality.
Tracing, if added, attacks path quality by producing better facts for the same materializer.

---

# 24. Machines

AOT/build machines:

```text
DeriveOpcodeContracts
GenerateOpcodeStencilCandidates
SpecializeInterpreterRegion
BuildStencilLibrary
ExtractStencilFixtures
ValidateStencilContracts
```

Runtime machines:

```text
DiscoverHotEntries
AnalyzeRangeLiveness
BuildVirtualState
BuildProjection
SelectStencilPlan
VerifyUnit
AllocateCodeBuffer
MaterializeStencil
FinalizeCodeBuffer
PublishUnit
TryEnterJit
ExecuteJitOutcome
ExecuteBoundary
ResolveEdge
PatchEdgeCell
RevertEdgeCell
InvalidateDependency
ReclaimCode
ProjectToVmState
ProjectRoots
RecordHotEntry
MarkJitRoots
```

Future trace machines:

```text
RecordTrace
AbortTrace
BuildTraceSnapshots
LowerTraceToStencilPlan
LinkTraceExit
BlacklistTraceAnchor
```

---

# 25. MVP slice

The first executable milestone should be small.

Compile this shape:

```lua
local s = 0
for i = 1, n do
  s = s + i
end
return s
```

Required products:

```text
CodeStencil fixtures for load/move/add/branch/return/projection
StencilPlan layout
CodeArena allocation
hole stamping
branch fixups
publish boundary
EntryCell link
JitOutcome return/interpreter exit
```

Required stencils:

```text
abi.unit_entry_interpreter_state
abi.unit_leave_to_vm
value.load_i64.imm_to_sA.fall
value.move.sB_to_sA.fall
guard.int.sA.next_or_exit
arith.add_i64.sB_sC_to_sA.fall
arith.add_i64_guarded.sB_sC_to_sA.next_or_exit
branch.jump.pc_relative
branch.truthy.sA.true_or_false
loop.forprep_i64.sA.next_or_exit
loop.forloop_i64.sA.loop_or_exit
projection.interpreter.live_slots
edge.jump_indirect.target
return.one.sA
```

Everything else exits or declines compilation.

---

# 26. Why this covers the hard cases

| Hard case | Structural answer |
|---|---|
| JIT/interpreter semantic drift | Stencils derive from interpreter regions or interpreter-derived contracts. |
| Runtime encoder complexity | Runtime emits by select/copy/stamp/payload/fixup/link. |
| Too many tiers | Baseline and trace are StencilPlan producers, not separate backends. |
| Register allocation cost | Variant selection + pass-through masks encode lightweight allocation. |
| Stack ceremony | VirtualState lifts stack slots; stencils carry selected values physically. |
| GC missing roots | Effects demand ROOTS projection; root projection materializes via stencils. |
| Allocation hidden safepoint | Allocator/helper stencils carry MAY_ALLOC/MAY_GC. |
| Yield/call/debug observation | Effects demand RESUME/DEBUG/INTERPRETER projections. |
| Snapshot incompleteness | Projection is built from VirtualState + liveness + requirement. |
| Type unsoundness | No stencil is selectable without required TypedValue inputs. |
| Regalloc/materialization mismatch | Projection is semantic; stencil lowering is physical. |
| Edge invalidation | EdgeCells link/revert compiled units without bytecode mutation. |
| Code reclamation | Code freed only at quiescence. |
| Unstable traces | Trace anchors can abort and blacklist; interpreter remains source of truth. |

---

# 27. Complete product list

Semantic products:

```text
SemanticAddr
SemanticRange
SpecializationContext
VirtualState
TypedValue
Fact
FactSet
Guard
Effect
BoundaryRequirement
Projection
ProjectedSlot
ResumeProjection
ErrorProjection
DebugProjection
DependencyKey
DependencySet
DependencyIndex
TraceAnchor
TraceRecord
```

Stencil products:

```text
StencilHole
StencilReloc
StencilPayload
CodeStencil
StencilLibrary
StencilConfig
StencilNode
StencilPlan
CodeFixup
StencilFixture
```

Runtime products:

```text
ExecImage
ExecutableUnit
ExecutionMode
UnitABI
StateShape
StateOp
Boundary
UnitExit
EntryCell
EdgeCell
InlineCacheRecord
JitOutcome
JitRootArea
JitRuntime
BlockInfo
LiveSet
LivenessInfo
CompiledCode
CodeSlab
CodeArena
UnitProfile
ExitProfile
```

Machines:

```text
SelectStencilPlan
LayoutStencilPlan
MaterializeStencil
PublishUnit
PatchEdgeCell
ProjectToVmState
ExecuteJitOutcome
RecordTrace
LowerTraceToStencilPlan
```

---

# 28. Final statement

The Moonlift Lua VM JIT is a copy-and-patch compiler.

The interpreter is the semantic source. The stencil library is derived from interpreter regions or
checked against interpreter-derived contracts. The first compiler frontend is a baseline bytecode
range planner. A future trace recorder may produce more specialized plans, but it reuses the same
`CodeStencil` library, `Projection` system, `EdgeCell` linking, dependency tracking, code arena, and
materializer.

The architecture is:

```text
derive stencils from Moonlift region semantics
mine and promote stencil fixtures from evidence
select baseline StencilPlans from VirtualState
optionally select trace StencilPlans from recorded path facts
materialize every unit by copy/stamp/payload/fixup/publish/link
recover VM state through projection stencils
link hot control with EdgeCells and data ICs
keep Proto.code immutable forever
```
