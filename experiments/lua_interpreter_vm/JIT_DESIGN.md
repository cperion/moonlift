# Moonlift Lua Interpreter VM — Copy-and-Patch JIT Design

Scope: a Moonlift-native JIT architecture for `experiments/lua_interpreter_vm`.

This design has one top-level idea:

> The JIT is a copy-and-patch compiler whose stencil library is derived from the interpreter.

Everything else exists to support that idea.

```text
Interpreter regions define semantics.
Partial evaluation derives stencils.
Runtime JIT builds a StencilPlan.
StencilPlan materializes to code by copy/stamp/payload/fixup/publish/link.
VirtualState selects variants.
Effects select boundary/projection stencils.
EdgeCells link compiled units.
Proto.code remains immutable semantic bytecode.
```

---

# 1. The whole JIT as copy-and-patch

Runtime code generation is not instruction encoding. Runtime code generation is stencil
materialization.

The runtime pipeline:

```text
select stencils
layout stencil graph
copy stencil bytes
stamp holes
write payloads
resolve fixups
publish code
link edge cells
```

This applies to the whole JIT:

```text
opcode bodies       -> stencils
supernodes          -> stencils
guards              -> stencils
side exits          -> stencils
projections         -> stencils
runtime boundaries  -> stencils
entry/exit adapters -> stencils
```

So the design is not:

```text
copy-and-patch for tier 1, encoder for the real JIT
```

It is:

```text
copy-and-patch is the JIT backend
```

A direct machine-code encoder may exist as an engineering escape hatch, but it is not part of the
architecture. If a code shape matters, add a stencil or supernode for it.

---

# 2. First principles

## 2.1 The interpreter is the semantic source

The current VM already defines Lua semantics in Moonlift regions:

```text
vm_loop
  -> dispatch_instruction
  -> opcode handlers
  -> runtime/helper regions
```

The JIT should not re-author these semantics by hand. The stencil library is derived from the
interpreter or checked against interpreter-derived contracts.

## 2.2 `Proto.code` is immutable

The bytecode remains the semantic program.

```text
no quickened bytecode
no inserted deopt opcodes
no semantic bytecode mutation
```

All optimization state lives beside it:

```text
ExecImage
EntryCell
EdgeCell
ExecutableUnit
profiles
dependencies
```

## 2.3 Runtime compilation does not run Cranelift

Cranelift may compile stencil generators ahead of time.

At runtime the JIT only performs:

```text
selection
layout
copy
stamp
payload
fixup
publish
link
```

## 2.4 Copy-and-patch is rich, not dumb templates

The stencil library contains variants:

```text
stack/register/immediate operand forms
output-to-stack/output-to-register forms
pass-through register forms
branch/fallthrough forms
projection/boundary forms
supernode forms
```

Register allocation and local optimization happen by selecting stencil variants, not by encoding
arbitrary instructions at runtime.

---

# 3. Where stencils come from

The preferred derivation path:

```text
Moonlift interpreter region
  -> specialization context
  -> partial evaluation / context specialization
  -> bytecode-erased specialized region
  -> AOT Cranelift object code
  -> CodeStencil bytes + holes + relocations + payload metadata
```

A stencil is valid only if it has a semantic contract:

```text
input state shape
output state shape
effect flags
projection requirements
dependencies
ABI assumptions
```

Hand-written stencils may exist only as implementations of such contracts. They are not semantic
authorities.

## 3.1 SpecializationContext

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

Conceptually, a specialization context contains:

```text
known opcode
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
continuations -> relocations / EdgeCells
```

---

# 4. Runtime selection state: VirtualState

`VirtualState` is not a heavyweight runtime object. It is the selection/recording state that tells
the runtime compiler which stencils are legal and profitable.

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
slot R0 currently has ValueId v0
v0 is proven Int
slot R2 can be represented in a register
this guard depends on table shape epoch
this branch path is selected
```

So `VirtualState` is the input to stencil selection:

```text
VirtualState + opcode/effect/profile
  -> StencilConfig
  -> CodeStencil
```

## 4.1 TypedValue

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

Typed values make illegal stencil selection impossible:

```text
add_wrap_i64(Int, Int) -> Int
add_wrap_i64(Unknown, Int) -> no legal stencil
```

Lua integer arithmetic wraps. There is no overflow-exit stencil for ordinary integer `+`, `-`, or
`*`.

---

# 5. Effects choose boundary stencils

Every stencil has an effect contract.

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

Effects select required boundary/projection stencils:

```text
MAY_GC             -> root projection stencil
MAY_ALLOC          -> root projection stencil
MAY_CALL_LUA       -> root + resume projection stencils
MAY_YIELD          -> resume projection stencil
MAY_RUN_HOOK       -> debug + resume + root projection stencils
MAY_OBSERVE_STACK  -> interpreter projection stencil
MAY_THROW          -> error projection stencil
MAY_NEED_BARRIER   -> barrier stencil
side exit          -> target/interpreter projection stencil
```

This eliminates informal safepoint lists. Allocation cannot be forgotten as a GC boundary because
allocator stencils/helpers carry `MAY_ALLOC | MAY_GC`.

---

# 6. Projections are recovery stencils

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

A projection does not mention physical registers. It says:

```text
slot R2 must contain ValueId v17
ValueId v9 must be visible as a GC root
frame.resume_pc must be pc 42
```

Projection lowering selects recovery stencils:

```text
write Value slot
write frame.pc
write frame.top
write L.top
write root area slot
write resume field
write error field
call barrier
reload pinned state
```

Thus deopt, GC roots, debug visibility, error state, and resume state are all copy-and-patchable
recovery code.

---

# 7. Stencil products

## 7.1 CodeStencil

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

A stencil is precompiled bytes plus metadata.

Holes:

```text
slot displacement
immediate
constant index
Value tag
EdgeCell pointer
runtime helper pointer
projection id
boundary id
```

Relocations:

```text
fallthrough continuation
branch target
boundary stub
runtime helper call
edge-cell load site
```

Payloads:

```text
literal bytes
literal Value
side table record
projection/boundary metadata
```

## 7.2 StencilConfig

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

Configuration axes:

```text
operation kind
value type
lhs/rhs locations
output location
pass-through register mask
supernode pattern
boundary/projection form
```

This is the lightweight register-allocation protocol.

## 7.3 StencilPlan

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

The runtime compiler builds a `StencilPlan`, then materializes it.

---

# 8. Materialization pipeline

The engineering names are precise:

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
fixup  = resolve code-layout-dependent addresses before publication
link   = mutate EdgeCells after publication
patch  = reserved for post-publication mutable updates
```

Machines:

```text
SelectStencilPlan
AllocateCodeBuffer
MaterializeStencil
FinalizeCodeBuffer
PatchEdgeCell
RevertEdgeCell
```

`MaterializeStencil` handles copy/stamp/payload/fixup for one stencil instance. `PatchEdgeCell`
links or repairs published edges.

---

# 9. CPS and fallthrough

Stencils compose through continuation-passing style.

A stencil node has continuations:

```text
next
alt / branch
boundary
runtime helper
edge exit
```

During layout, adjacent continuations can fall through. Unnecessary jumps between consecutive
stencil nodes are elided.

This is how copy-and-patch becomes more than concatenating tiny fragments:

```text
CPS stencil graph -> layout -> fallthrough-optimized code
```

---

# 10. Executable image

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

---

# 11. Edge cells

Edge cells are mutable data edges.

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

Baseline inter-unit transfer:

```asm
jmp qword ptr [edge.target]
```

So hot control repair is a data update:

```text
edge.target = target_unit.code.entry
edge.target_unit = target_unit
```

No `Proto.code` mutation. No required instruction-stream patching.

---

# 12. ExecutableUnit

```moonlift
struct ExecutableUnit
    id: u32
    tier: u8
    version: u32
    status: u8
    range: SemanticRange
    shape: u8
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
    entries: ptr(ptr(EdgeCell))
    entry_count: index
    exits: ptr(UnitExit)
    exit_count: index
    profile: UnitProfile
    deps: DependencySet
end
```

An executable unit is a published stencil plan plus semantic side tables.

Unit shapes:

```text
BLOCK
TRACE
REGION
```

These are not different backends. All are copy-and-patch units with different stencil-plan shapes.

---

# 13. Code memory

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
publish through architecture boundary
reclaim only at quiescence
```

---

# 14. VM integration

The current VM loop remains the semantic scheduler.

JIT entry gates:

```text
function entry
loop header/backedge
branch target
call-entry child frame
resume-parent pc
hot side-exit target
```

Cold exits return a `JitOutcome`:

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

`ExecuteJitOutcome` maps this to existing VM continuations:

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

---

# 15. Unit shapes as stencil-plan policies

## 15.1 Block

```text
short range
low compile latency
mostly opcode/supernode stencils
frequent/simple projections
compiled landing pads
```

## 15.2 Trace

```text
linear hot path
pass-through register variants
supernode stencils
side-exit projection stencils
fallthrough-optimized CPS layout
```

## 15.3 Region

```text
multi-block stencil graph
internal labels and fixups
join/phi-like state handling via VirtualState
projection stencils at effect boundaries
```

---

# 16. Verification

Verification checks the plan, not a hand-written second semantics.

Checks:

```text
selected stencils satisfy typed inputs
stencil effect covers StateOp/effect contract
boundary effects have projection stencils
projection stencils cover live slots/roots/resume/debug/error needs
supernode contract equals expanded StateOp contract
holes are all stamped
payloads are all written
fixups are all resolved
edge cells have fallbacks
dependencies cover speculative facts
```

---

# 17. Performance contract

Hot runtime code contains no JIT architecture interpreter.

Runtime compile cost:

```text
select + layout + memcpy + stamp + fixup + publish + link
```

Execution cost:

```text
hot raw stencil code + exit_rate * projection_stencil_cost
```

Compile threshold:

```text
compile_latency < expected_iterations * per_iteration_savings
```

Copy-and-patch attacks compile latency. Variants, pass-throughs, and supernodes attack emitted-code
quality.

---

# 18. Machines

Build/AOT machines:

```text
DeriveOpcodeContracts
SpecializeInterpreterRegion
BuildStencilLibrary
ExtractCodeStencils
ValidateStencilContracts
```

Runtime machines:

```text
DiscoverBlocks
AnalyzeLiveness
RecordStateProgram
BuildProjection
VerifyUnit
SelectStencilPlan
AllocateCodeBuffer
MaterializeStencil
FinalizeCodeBuffer
PublishUnit
TryEnterJit
ExecuteJitOutcome
ExecuteBoundary
ResolveAddr
PatchEdgeCell
RevertEdgeCell
InvalidateDependency
ReclaimCode
ProjectToVmState
ProjectRoots
RecordHotEntry
MarkJitRoots
```

---

# 19. Direct encoder status

A direct x64 encoder is not part of the core architecture.

If runtime code generation needs a shape, the architectural answer is:

```text
add a stencil variant
add a supernode
improve stencil selection
fall back if not worth compiling
```

A direct encoder may exist as a debugging tool or emergency implementation detail, but it is not
the JIT's primary or defining backend.

---

# 20. Why this covers the hard cases

| Hard case | Structural answer |
|---|---|
| JIT/interpreter semantic drift | Stencils derive from interpreter regions or interpreter-derived contracts. |
| Slow runtime encoding | Runtime emits by select/copy/stamp/payload/fixup/link. |
| Register allocation cost | Variant selection + pass-through masks encode lightweight allocation. |
| Stack ceremony | VirtualState lifts stack slots; stencils carry selected values physically. |
| GC missing roots | Effects demand RootProjection; root projection materializes via stencils. |
| Allocation hidden safepoint | Allocator/helper stencils carry MAY_ALLOC/MAY_GC. |
| Yield/call/debug observation | Effects demand resume/debug/interpreter projection stencils. |
| Snapshot incompleteness | Projection is built from VirtualState + liveness + requirement. |
| Type unsoundness | No stencil is selectable without required TypedValue inputs. |
| Regalloc/materialization mismatch | Projection is semantic; stencil lowering is physical. |
| Edge invalidation | EdgeCells link/revert compiled units without bytecode mutation. |
| Code reclamation | Code freed only at quiescence. |
| Unstable traces | Profiles blacklist shapes/anchors. |

---

# 21. Complete product list

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
```

Runtime products:

```text
ExecImage
ExecutableUnit
UnitABI
StateShape
StateOp
Boundary
UnitExit
EntryCell
EdgeCell
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

---

# 22. Final statement

The Moonlift Lua VM JIT is a copy-and-patch compiler.

Its stencil library is derived from interpreter regions by specialization/partial evaluation. Its
runtime compiler builds stencil plans from `VirtualState`, profiles, and effect contracts. It emits
code by copy/stamp/payload/fixup/publish/link. Effects select projection stencils so the VM, GC,
resume, debug, error, and interpreter views are exact at every boundary. Edge cells link and repair
compiled control flow without mutating `Proto.code`.

The whole architecture is:

```text
derive stencils from interpreter semantics
select stencil plans from VirtualState
materialize by copy-and-patch
recover VM state by projection stencils
link hot control with EdgeCells
```
