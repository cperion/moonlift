# Moonlift fact-rich backend refactor

Status: corrected design target and implementation checklist.

This document defines the breaking backend refactor for Moonlift after removal
of the legacy `MoonliftBack` bridge.  Moonlift is still a greenfield
compiler/runtime, so this plan deliberately removes compatibility command shapes
when they obscure facts needed for correctness, legality, scheduling, or native
code quality.

The goal is not to clone LLVM IR.  The goal is to make Moonlift's own facts
survive from source contracts and vector decisions down to the executable
Cranelift boundary.

Non-negotiable rule:

```text
If a fact changes legality, schedule, codegen, memory motion, or trap behavior,
it must be represented as an ASDL value.
```

---

## 1. Thesis

LLVM/Terra beating Moonlift at runtime usually means one or more of these are
true:

```text
A. LLVM has optimization/legalization facts Moonlift does not represent.
B. Moonlift has facts in Tree/Vec but drops them before Back.
C. Moonlift preserves facts in Back but Rust lowering ignores them.
D. Cranelift lacks an LLVM middle-end transform, so Moonlift must pre-schedule.
E. Moonlift chose a worse target schedule.
```

In PVM terms, this is a fact/modeling/schedule gap, not a reason to add hidden
backend helper tricks.

Correct Moonlift response:

```text
source contracts / view semantics / typed control
  -> explicit Tree/Sem/Vec facts, proofs, rejects, decisions
  -> explicit target model and vector schedule
  -> fact-rich Moon2Back flat executable commands
  -> direct Rust/Cranelift lowering
```

Wrong response:

```text
kernel-name special cases
opaque backend option tables
compatibility command variants
hidden Rust-side optimizer IR
legacy bridge layers
Cranelift-as-LLVM-middle-end assumptions
```

Cranelift should be treated as:

```text
instruction selector + legalizer + register allocator + native code emitter
```

not as:

```text
source-level optimizer / alias analyzer / auto-vectorizer / loop scheduler
```

---

## 2. Current state, fact-checked

The current active executable path is:

```text
Moon2Tree.Module
  -> tree_typecheck.lua
  -> Moon2Tree.Module(ModuleTyped)
  -> vector/contract/control phases where applicable
  -> tree_to_back.lua / vec_kernel_to_back.lua
  -> Moon2Back.BackProgram
  -> back_validate.lua
  -> back_jit.lua
  -> Rust / Cranelift
```

The legacy path has been removed from the active compiler:

```text
Moon2Back.BackProgram
  -> MoonliftBack.BackProgram
  -> legacy jit.lua
```

`lua/moonlift/back_jit.lua` directly replays `Moon2Back.BackProgram` into the
retained Rust Cranelift command builder.  That cleanup is correct, but it
exposes the next design problem:

```text
Moon2Vec has rich facts.
Moon2Back cannot carry most of them.
Rust therefore emits conservative Cranelift IR.
```

---

## 3. Current ASDL audit

### 3.1 `Moon2Back` today

The pre-refactor `Moon2Back.Cmd` had flat executable commands such as:

```asdl
CmdLoad(dst, shape, addr)
CmdStore(shape, addr, value)
CmdBinary(dst, op, shape, lhs, rhs)
CmdCompare(dst, op, shape, lhs, rhs)
CmdVecSplat(...)
CmdVecCompare(...)
CmdVecSelect(...)
CmdVecMask(...)
CmdMemcpy(...)
CmdMemset(...)
```

The active backend has now removed the generic executable `CmdLoad`,
`CmdStore`, `CmdBinary`, and `BackBinaryOp` layer.  Memory execution goes
through `CmdLoadInfo` / `CmdStoreInfo`; pointer address formation goes through
`CmdPtrOffset`; scalar arithmetic is split into int/bit/shift/rotate/float
command families; vector arithmetic is split into `CmdVecBinary`.

The original flat-command shape was good because:

- the backend program is flat;
- validation is straightforward;
- commands are easy to replay;
- scalar/vector command categories are explicit enough for the current backend.

It is not good enough for performance/correctness work because these commands
cannot express:

- address provenance;
- pointer byte-offset formation vs ordinary integer addition;
- memory alignment;
- dereferenceability and access size;
- in-bounds/nontrapping proof;
- trap/motion semantics (`notrap` is not the same as `can_move`);
- alias relationships among accesses;
- access mode (`read`, `write`, `readwrite`);
- readonly/writeonly/noalias facts with proof scope;
- integer overflow/exactness semantics;
- float strict/reassociate/fast-math semantics;
- branch/cold-path hints if Moonlift later uses them for block layout;
- executable target capability facts;
- explicit vector unroll/interleave/accumulator schedule;
- masked tails, masked memory, gather/scatter.

Most important current smell:

```asdl
CmdBinary(... BackIadd ... BackPtr ...)
```

is used for pointer address arithmetic.  That erases the distinction between:

```text
integer addition
pointer byte offset
in-bounds address formation
```

If later lowering cares about that distinction, it must be explicit in ASDL.

### 3.2 `Moon2Vec` today

`Moon2Vec` already has many of the right fact families:

```asdl
VecTargetModel
VecTargetFact
VecRangeFact
VecDomain
VecInduction
VecAccessPattern
VecAlignment
VecBounds
VecMemoryFact
VecAliasFact
VecDependenceFact
VecReassoc
VecReductionFact
VecProof
VecAssumption
VecKernelSafety
VecKernelBounds
VecKernelAlias
VecLoopShape
VecLoopDecision
VecKernelPlan
```

These represent real compiler facts:

- target shape support;
- loop domains;
- induction variables;
- memory access patterns;
- alignment;
- bounds;
- aliasing;
- dependences;
- reassociation legality;
- reduction shape;
- vector legality and safety.

The first refactor slice now prevents the most important facts from dying
before executable backend lowering: `vec_kernel_to_back.lua` emits
`CmdLoadInfo` / `CmdStoreInfo`, split scalar command families, and
`CmdVecBinary`.  Proven/assumed vector-kernel safety is preserved in
`BackDereference` / `BackTrap`, and lower-level `VecCmdLoad` / `VecCmdStore`
carry `VecMemoryFact` access IDs, alignment, and bounds into `BackMemoryInfo`.
Remaining work is to preserve richer alias/dependence/schedule facts all the
way into `Moon2Back`.

Current split:

```text
Moon2Vec: rich proofs and decisions
Moon2Back: thin executable commands
```

Target split:

```text
Moon2Vec: recognition, legality, proof, schedule choice
Moon2Back: lowest executable fact language preserving the chosen facts
```

### 3.3 Specialized vector kernel variants

Current schema still contains generic kernel forms plus historical/specialized
forms:

```asdl
VecKernelReduce
VecKernelMap
VecKernelI32Reduce
VecKernelI32Map
VecKernelI32Sum
VecKernelI32Dot
VecKernelI32Fill
VecKernelReductionI32Add
```

In a greenfield compiler this is confusing.  `i32 sum` is not a special semantic
kind.  It is an instance of a generic reduction:

```text
elem = i32
op = add
identity = 0
```

Target: delete all specialized i32 plan/reduction variants and keep generic
plans only.

---

## 4. Cranelift 0.130.1 capability audit

The Rust backend uses Cranelift 0.130.1 and native ISA configuration:

```rust
cranelift_native::builder()
flag_builder.set("opt_level", "speed")
```

Current Rust lowering supports:

- scalar integer and floating ops;
- integer and floating compares;
- casts/conversions;
- direct / extern / indirect calls;
- blocks and block params;
- stack slots;
- data objects with size/alignment;
- vector types via `elem_ty.by(lanes)`;
- fact-rich scalar/vector loads/stores carrying `BackMemoryInfo`;
- vector arithmetic/bitwise ops;
- vector integer compares;
- lane insert/extract;
- memcpy/memset through `FunctionBuilder::call_memcpy` / `call_memset`;
- fma through `builder.ins().fma`;
- native JIT symbols.

Current fact-rich load/store lowering builds Cranelift `MemFlags` from
`BackMemoryInfo` conservatively:

```rust
BackTrap::NonTrapping -> MemFlags::notrap
BackTrap::Checked     -> MemFlags::checked
BackMotion::CanMove   -> MemFlags::can_move
BackAlignment >= natural access alignment -> MemFlags::aligned
BackDereference covering the access -> MemFlags::notrap only when no stronger trap fact was present
```

`MemFlags::new()` is not literally semantically empty.  It carries the default
trap code.  It remains the fallback for memory operations that do not yet have a
Moonlift fact carrier such as memcpy/memset internals.  The old Rust `Load`,
`Store`, `VecLoad`, and `VecStore` command variants are removed from the active
backend; scalar/vector memory execution now uses `LoadInfo`, `StoreInfo`,
`VecLoadInfo`, and `VecStoreInfo`.

Current vector select is manually lowered as integer bit operations:

```rust
masked_then = band(mask, then_value)
not_mask    = bnot(mask)
masked_else = band(not_mask, else_value)
out         = bor(masked_then, masked_else)
```

This is only a clean strategy for integer-vector payloads with all-ones masks.
Before float vectors are enabled, `CmdVecSelect` must lower to Cranelift select
or an explicitly valid blend strategy for the element type.

### 4.1 Exact Cranelift `MemFlags` facts in 0.130.1

Relevant Cranelift 0.130.1 memory flags:

| Cranelift flag | Meaning / caution |
|---|---|
| `aligned` | Natural alignment for the access type. Not arbitrary `align >= N`. Adding it is UB if the effective address may be misaligned. |
| `readonly` | Memory read by the load does not change for the function duration. This is stronger than many source `readonly` contracts. |
| endian | Explicit little/big-endian override; otherwise target-native. |
| `checked` | PCC/proof-carrying-code framework bit; not a general Moonlift bounds-check flag. |
| alias region | Only Cranelift regions `Heap`, `Table`, `Vmctx`; not a general noalias mechanism. |
| `notrap` | Access is accessible/nontrapping at this instruction. Does not imply movable across guards. |
| `can_move` | Operation may be moved as long as data dependencies are respected. Stronger than `notrap` for guard-dependent accesses. |

Therefore the Rust mapping must be conservative:

```text
BackAlignmentKnown/AtLeast
  -> MemFlags::with_aligned only when natural alignment for the access shape is proven.

BackDereference + BackTrapNonTrapping
  -> MemFlags::with_notrap only when access-size coverage is unconditional at this instruction.

BackMotionCanMove
  -> MemFlags::with_can_move only when proof is independent of control guards.

BackReadonly
  -> MemFlags::with_readonly only when function-duration immutability is proven.

BackAliasFact
  -> mostly Moonlift scheduling/validation evidence;
     only maps to Cranelift alias regions if Moonlift explicitly models Heap/Table/Vmctx-like spaces.
```

### 4.2 Integer and float semantic limits in Cranelift 0.130.1

Cranelift 0.130.1 is not LLVM IR:

- ordinary `iadd` / `isub` / `imul` do not carry generic LLVM-like `nsw` / `nuw`
  metadata;
- ordinary float ops do not carry generic LLVM-like fast-math/reassociation
  metadata;
- overflow-producing/trapping operations exist, but they are explicit operation
  choices, not metadata on every arithmetic instruction;
- `fma` is explicit and maps directly.

So:

```text
BackIntSemantics and BackFloatSemantics are primarily Moonlift legality,
scheduling, validation, and transform facts.  Rust lowering maps them only where
Cranelift exposes an explicit matching operation or flag.
```

The active Rust/FFI replay now preserves those facts in Rust command values via
split scalar arithmetic entry points (`int_binary`, `bit_binary`, `shift`,
`rotate`, `float_binary`).  Cranelift still receives ordinary arithmetic ops
where no exact metadata exists, but the semantic facts are no longer erased at
the Lua/Rust boundary.  Compare and pointer address replay likewise use explicit
`compare`, `ptr_add`, and `ptr_offset` entry points; active replay no longer has
a generic binary FFI path.

### 4.3 What Cranelift should not be expected to do

Do not rely on Cranelift for:

- source-level alias analysis;
- Moonlift view/window bounds reasoning;
- source contract interpretation;
- auto-vectorization;
- loop canonicalization from source control;
- reduction reassociation decisions;
- high-level memory op recognition;
- target-specific loop schedule selection.

Those are Moonlift/PVM responsibilities.

---

## 5. Correct target architecture

The target architecture is:

```text
Canonical BackTargetModel
  -> derived Host/Vec target facets

Tree contracts/control
  -> Vec facts/proofs/rejects
  -> Vec legality + schedule decisions

Vec/Tree lowering
  -> Moon2Back flat executable command stream
     with explicit address, memory, alias, trap/motion,
     int/float semantic, and target facts

Back validation
  -> fact consistency validation

Rust/Cranelift
  -> direct lowering of Moon2Back
  -> consumes facts where Cranelift supports them
  -> otherwise preserves them as Moonlift scheduling/validation evidence
```

In one sentence:

```text
Moonlift proves and schedules in Moon2Vec, preserves executable facts in
Moon2Back, validates those facts before execution, and uses Cranelift only as the
native code emitter for an already fact-shaped backend program.
```

`Moon2Back` remains flat.  It is not LLVM IR and not Cranelift IR.  It is the
Moonlift executable fact language.

---

## 6. Canonical target model

Target truth should have one executable home.  Use `Moon2Back` as the canonical
home because it is the lowest executable layer.  Existing `Moon2Host.HostTargetModel`
and `Moon2Vec.VecTargetModel` become derived facets/projections.

Target shape:

```asdl
BackTarget = BackTargetNative
           | BackTargetCraneliftJit
           | BackTargetNamed(string name) unique

BackEndian = BackEndianLittle | BackEndianBig

BackTargetFeature = BackFeatureSSE2
                  | BackFeatureAVX2
                  | BackFeatureAVX512F
                  | BackFeatureFMA
                  | BackFeaturePOPCNT
                  | BackFeatureBMI1
                  | BackFeatureBMI2
                  | BackFeatureUnknown(string name) unique

BackTargetFact = BackTargetPointerBits(number bits) unique
               | BackTargetIndexBits(number bits) unique
               | BackTargetEndian(Moon2Back.BackEndian endian) unique
               | BackTargetCacheLineBytes(number bytes) unique
               | BackTargetFeature(Moon2Back.BackTargetFeature feature) unique
               | BackTargetSupportsShape(Moon2Back.BackShape shape) unique
               | BackTargetSupportsVectorOp(Moon2Back.BackVec vec, string op_class) unique
               | BackTargetSupportsMaskedTail
               | BackTargetPrefersUnroll(Moon2Back.BackShape shape, number unroll, number rank) unique

BackTargetModel = (
    Moon2Back.BackTarget target,
    Moon2Back.BackTargetFact* facts
) unique
```

Rationale:

- CPU features are not enough; the executable backend may support fewer vector
  shapes than the CPU advertises.
- Current reality already proves this: Moonlift advertises executable 128-bit
  shapes after probing showed this Cranelift path rejected wider `i32x8` shapes.
- Therefore vector planning should consume executable capability facts, not raw
  hardware feature guesses.

Derived phases:

```text
BackTargetModel -> HostTargetModel(pointer_bits, index_bits, endian)
BackTargetModel -> VecTargetModel(shape/op/tail/unroll facts)
BackTargetModel -> Rust lowering capability checks
```

No semantic phase may independently hardcode 64-bit pointer/index/endian truth.

---

## 7. Backend memory and address architecture

Do not put all memory facts into “address”.  Address formation and memory access
are different facts.

Correct split:

```text
BackAddress says where.
BackMemoryInfo says whether/how this access is legal.
BackAliasFact says relationships among accesses.
```

### 7.1 Address formation and provenance

```asdl
BackAddressBase = BackAddrValue(Moon2Back.BackValId value) unique
                | BackAddrStack(Moon2Back.BackStackSlotId slot) unique
                | BackAddrData(Moon2Back.BackDataId data) unique

BackPointerProvenance = BackProvUnknown
                      | BackProvStack(Moon2Back.BackStackSlotId slot) unique
                      | BackProvData(Moon2Back.BackDataId data) unique
                      | BackProvArg(string name) unique
                      | BackProvView(string name) unique
                      | BackProvDerived(string reason) unique

BackPointerBounds = BackPtrBoundsUnknown
                  | BackPtrInBounds(string reason) unique
                  | BackPtrMayLeaveObject(string reason) unique

BackAddress = (
    Moon2Back.BackAddressBase base,
    Moon2Back.BackValId byte_offset,
    Moon2Back.BackPointerProvenance provenance,
    Moon2Back.BackPointerBounds formation_bounds
) unique

CmdPtrOffset(
    Moon2Back.BackValId dst,
    Moon2Back.BackAddressBase base,
    Moon2Back.BackValId index,
    number elem_size,
    number const_offset,
    Moon2Back.BackPointerProvenance provenance,
    Moon2Back.BackPointerBounds bounds
) unique
```

Pointer offset formation is no longer hidden in ordinary `CmdIntBinary`.

### 7.2 Memory access facts

```asdl
BackAccessId = (string text) unique
BackAliasScopeId = (string text) unique

BackAlignment = BackAlignUnknown
              | BackAlignKnown(number bytes) unique
              | BackAlignAtLeast(number bytes) unique
              | BackAlignAssumed(number bytes, string reason) unique

BackDereference = BackDerefUnknown
                | BackDerefBytes(number bytes, string reason) unique
                | BackDerefAssumed(number bytes, string reason) unique

BackTrap = BackMayTrap
         | BackNonTrapping(string reason) unique
         | BackChecked(string reason) unique

BackMotion = BackMayNotMove
           | BackCanMove(string reason) unique

BackAccessMode = BackAccessRead
               | BackAccessWrite
               | BackAccessReadWrite

BackMemoryInfo = (
    Moon2Back.BackAccessId access,
    Moon2Back.BackAlignment alignment,
    Moon2Back.BackDereference dereference,
    Moon2Back.BackTrap trap,
    Moon2Back.BackMotion motion,
    Moon2Back.BackAccessMode mode
) unique
```

Load/store shape:

```asdl
CmdLoad(
    Moon2Back.BackValId dst,
    Moon2Back.BackShape shape,
    Moon2Back.BackAddress addr,
    Moon2Back.BackMemoryInfo memory
) unique

CmdStore(
    Moon2Back.BackShape shape,
    Moon2Back.BackAddress addr,
    Moon2Back.BackValId value,
    Moon2Back.BackMemoryInfo memory
) unique
```

Do **not** duplicate `BackMemoryInfo` inside both `BackAddress` and `CmdLoad` /
`CmdStore`.  Address facts and access facts are separate.

### 7.3 Alias facts are relations

Alias/noalias cannot be a single enum field on one access.  It is a relation
among accesses or access groups.

```asdl
BackAliasFact = BackAliasUnknown(Moon2Back.BackAccessId a,
                                 Moon2Back.BackAccessId b,
                                 string reason) unique
              | BackMayAlias(Moon2Back.BackAccessId a,
                             Moon2Back.BackAccessId b,
                             string reason) unique
              | BackNoAlias(Moon2Back.BackAccessId a,
                            Moon2Back.BackAccessId b,
                            string reason) unique
              | BackSameBaseSameIndexSafe(Moon2Back.BackAccessId a,
                                          Moon2Back.BackAccessId b,
                                          string reason) unique
              | BackAliasScope(Moon2Back.BackAccessId access,
                               Moon2Back.BackAliasScopeId scope) unique
```

These facts are primarily used by Moonlift validation/scheduling.  They only map
to Cranelift alias regions if Moonlift deliberately models a small set of
Cranelift-like disjoint memory regions.

---

## 8. Arithmetic semantic domains

The removed generic command:

```asdl
CmdBinary(dst, op, shape, lhs, rhs)
```

mixed integer arithmetic, bitwise operations, float operations, shifts,
rotates, and vector operations.  The active backend is split by semantic
domain.

### 8.1 Integer arithmetic

```asdl
BackIntOverflow = BackIntWrap
                | BackIntNoSignedWrap(string reason) unique
                | BackIntNoUnsignedWrap(string reason) unique
                | BackIntNoWrap(string reason) unique

BackIntExact = BackIntMayLose
             | BackIntExact(string reason) unique

BackIntSemantics = (
    Moon2Back.BackIntOverflow overflow,
    Moon2Back.BackIntExact exact
) unique

BackIntOp = BackIntAdd | BackIntSub | BackIntMul
          | BackIntSDiv | BackIntUDiv
          | BackIntSRem | BackIntURem

CmdIntBinary(
    Moon2Back.BackValId dst,
    Moon2Back.BackIntOp op,
    Moon2Back.BackScalar scalar,
    Moon2Back.BackIntSemantics semantics,
    Moon2Back.BackValId lhs,
    Moon2Back.BackValId rhs
) unique
```

### 8.2 Bitwise and shifts

```asdl
BackBitOp = BackBitAnd | BackBitOr | BackBitXor
BackShiftOp = BackShiftLeft | BackShiftLogicalRight | BackShiftArithmeticRight

CmdBitBinary(...)
CmdBitNot(...)
CmdShift(...)
```

Bitwise operations are not integer arithmetic and should not carry overflow
semantics.

### 8.3 Float arithmetic

```asdl
BackFloatSemantics = BackFloatStrict
                   | BackFloatReassoc(string reason) unique
                   | BackFloatFastMath(string reason) unique

BackFloatOp = BackFloatAdd | BackFloatSub | BackFloatMul | BackFloatDiv

CmdFloatBinary(
    Moon2Back.BackValId dst,
    Moon2Back.BackFloatOp op,
    Moon2Back.BackScalar scalar,
    Moon2Back.BackFloatSemantics semantics,
    Moon2Back.BackValId lhs,
    Moon2Back.BackValId rhs
) unique

CmdFma(
    Moon2Back.BackValId dst,
    Moon2Back.BackScalar scalar,
    Moon2Back.BackFloatSemantics semantics,
    Moon2Back.BackValId a,
    Moon2Back.BackValId b,
    Moon2Back.BackValId c
) unique
```

Integer reductions and float reductions have different legality rules.
`VecReassoc` must lower into explicit backend semantics instead of vanishing.

---

## 9. Vector legality and schedule

`Moon2Vec` owns recognition, legality, proof, rejection, and schedule choice.
`Moon2Back` owns execution of the chosen schedule.

Target vector shape:

```asdl
VecLegality = VecLegal(Moon2Vec.VecProof* proofs) unique
            | VecIllegal(Moon2Vec.VecReject* rejects) unique

VecReductionSchedule = VecReductionSchedule(
    Moon2Vec.VecBinOp op,
    number accumulators,
    Moon2Vec.VecProof* proofs
) unique

VecSchedule = VecScheduleScalar(Moon2Vec.VecReject* rejects) unique
            | VecScheduleVector(
                Moon2Vec.VecShape shape,
                number unroll,
                number interleave,
                Moon2Vec.VecTail tail,
                number accumulators,
                Moon2Vec.VecReductionSchedule* reductions,
                Moon2Vec.VecProof* proofs
              ) unique

VecLoopDecision = VecLoopDecision(
    Moon2Vec.VecLoopFacts facts,
    Moon2Vec.VecLegality legality,
    Moon2Vec.VecSchedule schedule,
    Moon2Vec.VecLoopShape chosen,
    Moon2Vec.VecShapeScore* considered
) unique
```

Then `vec_kernel_to_back.lua` expands the schedule into explicit commands:

```text
schedule: shape=i32x4, unroll=4, accumulators=4, scalar tail
  -> four vector loads per body
  -> four independent accumulators
  -> explicit horizontal combine
  -> explicit scalar tail loop
```

Cranelift should not be expected to invent this schedule.

Vector select target:

```text
CmdVecSelect must lower to Cranelift select/blend semantics where possible.
Permanent integer bitmask lowering is not valid as the general vector-select
strategy, especially for future float vectors.
```

Masked tails, masked memory, gather, and scatter require explicit ASDL facts and
commands before enabling them.

---

## 10. Source contracts to Back facts

Existing source contracts remain source/Tree facts:

```text
bounds(base, len)
window_bounds(base, base_len, start, len)
disjoint(a, b)
same_len(a, b)
noalias(base)
readonly(base)
writeonly(base)
```

They lower through explicit phase boundaries:

```text
Moon2Tree.ContractFact
  -> Vec memory/proof/safety facts
  -> VecKernelSafetyDecision
  -> BackAddress / BackMemoryInfo / BackAliasFact
```

`back_jit.lua` must never inspect source contracts directly.

Correct boundary examples:

```text
VecProofKernelSafety("same_len contract proves range")
  -> BackDerefBytes(bytes, "same_len contract proves range")
  -> BackNonTrapping(reason) only if dereference coverage is unconditional

VecAlignmentAssumed(16, proof)
  -> BackAlignAssumed(16, "view ABI alignment assumption")
  -> Cranelift aligned only if it proves natural alignment for the access shape

VecAccessNoAlias(a, b, reason)
  -> BackNoAlias(access_a, access_b, reason)

VecReassocExact
  -> BackIntNoWrap/BackIntExact or BackFloatReassoc, depending on domain
```

`Moon2Back` receives executable guarantees and reasons, not high-level proof
objects that would invert layer dependencies.

---

## 11. Backend validation target

`back_validate.lua` must grow from structural validation to fact consistency
validation.

It should validate:

- every load/store has `BackMemoryInfo`;
- access mode matches command (`Read` for load, `Write` for store unless a
  deliberate read/write command uses `ReadWrite`);
- access ids are known and consistently referenced;
- alias facts reference known access ids;
- alignment bytes are powers of two where required;
- natural-alignment claims are only mapped to Cranelift `aligned` when access
  shape supports the claim;
- dereferenceable byte count covers the load/store access size;
- `BackNonTrapping` is backed by dereference/bounds evidence;
- `BackCanMove` is not claimed for guard-dependent accesses;
- address base/offset values are defined;
- pointer arithmetic uses `CmdPtrOffset` / `BackAddress`, not generic integer
  add;
- scalar/vector shape requirements are valid;
- integer semantics are attached only to integer arithmetic;
- float semantics are attached only to float arithmetic;
- bitwise/shift commands are not mixed with arithmetic commands;
- target-dependent vector shapes are advertised by `BackTargetModel`;
- no removed generic backend command variants remain.

This validation is not optional.  Without it, “fact-rich” becomes
“fact-decorated but unchecked”.

---

## 12. Rust lowering target

`back_jit.lua` and Rust FFI should be refactored to accept the new command
shapes.  Do not keep old command APIs for compatibility.

Rust lowering maps facts conservatively:

```text
BackTargetModel
  -> pointer/index/endian checks and CLIF type construction

BackAddress / CmdPtrOffset
  -> pointer arithmetic in CLIF, with provenance/facts validated before lowering

BackMemoryInfo
  -> Cranelift MemFlags only where exact semantics match

BackAlignment
  -> MemFlags::aligned only for natural alignment proof

BackDereference + BackTrap
  -> MemFlags::notrap only for unconditional access-size coverage

BackMotion
  -> MemFlags::can_move only with explicit proof

BackAliasFact
  -> mostly validation/scheduling evidence, rarely CLIF alias region

BackIntSemantics
  -> scheduling/validation evidence; explicit checked/trapping ops only where chosen

BackFloatSemantics
  -> scheduling/validation evidence; FMA maps directly

VecSchedule
  -> already expanded into commands before Rust
```

Cranelift lowering must not contain hidden Moonlift semantics.  Helper structs in
Rust may cache ids/values during replay, but they are not a second semantic IR.

---

## 13. Lua/Rust communication target

The current direct `back_jit.lua` boundary performs many FFI calls:

```text
one Lua -> Rust call per backend command
```

That is acceptable while the ASDL shape is being corrected.  The later transport
performance target is a packed command tape:

```text
Moon2Back.BackProgram
  -> BackCommandTape encoding
  -> one/few FFI calls
  -> Rust decodes and builds Cranelift IR
```

Important rule:

```text
The tape is an encoding of Moon2Back, not a hidden IR.
```

Do this only after the semantic command/fact shape is clean.  Transport speed
must not dictate semantic design.

---

## 14. Diagnostics and investigation loop

For every important kernel, diagnostics should print:

```text
Target:
- pointer bits
- index bits
- endian
- executable vector shapes
- executable vector ops
- relevant CPU/backend features

Vec:
- domain
- induction
- memory facts
- alias/dependence facts
- legality
- schedule: lanes/unroll/interleave/tail/accumulators

Back:
- command counts by kind
- explicit address commands
- load/store memory info
- alias relation facts
- int/float semantics
- trap/motion facts

Cranelift:
- generated CLIF when practical
- generated disassembly
```

Runtime gaps against LLVM/Terra become classifiable:

```text
A. fact absent from ASDL
B. fact exists in Vec but does not lower to Back
C. fact exists in Back but Rust ignores it
D. Cranelift lacks the LLVM transform, so Moonlift must pre-schedule
E. target model/scheduler chose a worse plan
```

---

## 15. Implementation plan checklist

This checklist is intentionally breaking.  Do not preserve old command variants
unless they remain the clean final design.

### 0. Baseline / audit

- [ ] Capture current benchmark numbers for `sum_i32`, `dot_i32`, `add_i32`, `scale_i32`.
- [ ] Capture current `profile_compile.lua` phase timing.
- [ ] Capture current Cranelift disassembly for benchmark kernels.
- [ ] Capture Terra/LLVM disassembly or LLVM IR for the same kernels where available.
- [ ] Record current Moon2Back command counts by kind for each kernel.
- [ ] Record current vector decisions and selected lanes/unroll/tail for each kernel.

### 1. Canonical target model

- [x] Add `BackTarget`, `BackEndian`, `BackTargetFeature`, `BackTargetFact`, `BackTargetModel`.
- [x] Include pointer bits, index bits, endian, cache line, CPU features, executable shapes, executable vector op facts.
- [x] Add a host/default target-model phase.
- [x] Derive `Moon2Host.HostTargetModel` from `BackTargetModel`.
- [x] Derive `Moon2Vec.VecTargetModel` from `BackTargetModel`.
- [ ] Remove or quarantine duplicate target truth construction.
- [ ] Update target/vector decision tests.

### 2. Rewrite `Moon2Back` memory/address schema

- [x] Add `BackAddressBase`.
- [x] Add `BackPointerProvenance`.
- [x] Add `BackPointerBounds`.
- [x] Add `BackAddress`.
- [x] Add `CmdPtrOffset` or equivalent explicit pointer-offset command.
- [x] Add `BackAccessId` and `BackAliasScopeId`.
- [x] Add `BackAlignment`, `BackDereference`, `BackTrap`, `BackMotion`, `BackAccessMode`, `BackMemoryInfo`.
- [x] Add relational `BackAliasFact` values.
- [x] Replace `CmdLoad(dst, shape, addr)` with fact-rich load.
- [x] Replace `CmdStore(shape, addr, value)` with fact-rich store.
- [x] Ensure memory info is not duplicated in `BackAddress` and load/store.
- [x] Update schema smoke tests.

### 3. Rewrite arithmetic command schema

- [x] Add `BackIntOverflow`, `BackIntExact`, `BackIntSemantics`.
- [x] Add `BackIntOp` and `CmdIntBinary`.
- [x] Add `BackBitOp` and bitwise commands.
- [x] Add `BackShiftOp` and shift commands.
- [x] Add `BackFloatSemantics`, `BackFloatOp`, `CmdFloatBinary`.
- [x] Update `CmdFma` to carry `BackFloatSemantics`.
- [x] Replace generic scalar `CmdBinary` in active lowering/tests with split scalar commands.
- [x] Add first split vector binary command (`CmdVecBinary`) for vector arithmetic/bitwise ops previously hidden in generic `CmdBinary`.
- [x] Keep vector commands only where they remain clean and fact-carrying for the current executable slice.
- [x] Remove obsolete generic executable command variants `CmdBinary`, `CmdLoad`, and `CmdStore` from `Moon2Back.Cmd`.
- [x] Update schema smoke tests.

### 4. Rewrite backend validation

- [x] Update `back_validate.lua` to new command variants.
- [x] Validate target facts and target-dependent shapes for commands when `CmdTargetModel` advertises supported shapes.
- [x] Validate memory info presence and consistency for the new `CmdLoadInfo` / `CmdStoreInfo` slice.
- [x] Validate access mode vs command for the new `CmdLoadInfo` / `CmdStoreInfo` slice.
- [x] Validate alignment values for the new memory-info slice.
- [x] Validate dereference bytes cover access size for the new memory-info slice.
- [x] Validate `BackNonTrapping` and `BackCanMove` evidence shape for the active memory-info slice.
- [x] Validate address base/offset value definitions for the new address slice.
- [x] Validate alias facts reference known accesses.
- [x] Validate integer semantics/scalar domain per op for the active split command slice.
- [x] Validate float semantics/scalar domain per op for the active split command slice.
- [x] Validate bitwise/shift separation for the active split command slice.
- [x] Delete validation paths for removed commands.
- [x] Update backend validation tests.

### 5. Refactor scalar/tree lowering

- [x] Update `tree_to_back.lua` to emit fact-rich backend commands for scalar/tree arithmetic and memory accesses.
- [x] Lower ordinary unknown source memory to explicit unknown memory facts.
- [x] Lower pointer indexing through `CmdPtrOffset` / `BackAddress`, not generic integer add.
- [x] Lower scalar integer arithmetic with explicit `BackIntWrap` unless proven otherwise.
- [x] Lower float operations with `BackFloatStrict` unless source facts allow more.
- [x] Lower field/view/window address formation with provenance facts.
- [x] Update tree-to-back tests for the fact-rich command slice.
- [x] Ensure non-vector code still compiles and runs through `back_jit`.

### 6. Refactor `Moon2Vec` plan/schedule shape

- [x] Replace `VecLoopShape` / old `VecLoopDecision` fields with explicit legality + schedule while retaining `chosen` as a compatibility spine facet.
- [x] Add `VecLegality`.
- [x] Add `VecSchedule`.
- [x] Add `VecReductionSchedule` if accumulator count must be explicit.
- [x] Delete `VecKernelI32Reduce`.
- [x] Delete `VecKernelI32Map`.
- [x] Delete `VecKernelI32Sum`.
- [x] Delete `VecKernelI32Dot`.
- [x] Delete `VecKernelI32Fill`.
- [x] Delete `VecKernelReductionI32Add`.
- [x] Represent all existing i32/u32/i64/u64 kernels with generic reduce/map plans.
- [x] Update `vec_kernel_plan.lua`.
- [x] Update `vec_loop_decide.lua`.
- [x] Update vector planning tests.

### 7. Lower Vec facts into Back facts

- [x] Update `vec_kernel_to_back.lua` to consume `VecSchedule` directly for lanes/unroll/interleave/accumulator policy, rejecting unsupported non-1 unroll/interleave schedules instead of rediscovering policy.
- [x] Lower vector-kernel alignment facts to `BackAlignment` (`VecKernelAlignment` -> `BackAlignKnown` / `BackAlignAssumed`) for active kernel memory accesses.
- [x] Lower `VecBounds` / `VecKernelBounds` to `BackDereference` / `BackTrap` facts for the active low-level `VecCmdLoad` / `VecCmdStore` path and vector-kernel safety decisions.
- [x] Lower `VecKernelAlias` to relational/scope `BackAliasFact` for vector-kernel accesses; broader raw `VecAliasFact` stream lowering remains a future non-kernel slice.
- [x] Lower the active vector-kernel arithmetic/reduction slice to explicit `BackIntSemantics` / `BackFloatSemantics` defaults by domain; richer reassociation proof mapping remains future schedule work.
- [x] Emit explicit access ids for vector-kernel loads/stores.
- [x] Emit explicit `BackAddress` values for vector-kernel loads/stores instead of pointer-add + old load/store commands.
- [x] Emit explicit vector binary commands for vector-kernel arithmetic/bitwise ops instead of generic vector-shaped `CmdBinary`.
- [x] Emit explicit unroll/interleave command schedules as `VecSchedule` facts; active map/reduce lowering now executes positive integer unroll/interleave schedules by expanding explicit vector groups.
- [x] Emit multiple reduction accumulators when target-preferred schedule facts request them for the active vector-reduce lowering slice.
- [x] Update vector-to-back tests for fact-rich Back memory/arithmetic; disassembly checks remain in diagnostics/benchmark work.

### 8. Refactor Lua/Rust backend boundary

- [x] Update `back_jit.lua` for the first new `Moon2Back.Cmd` variants (`CmdLoadInfo`, `CmdStoreInfo`, split scalar arithmetic, `CmdVecBinary`, `CmdPtrOffset`, `CmdAliasFact`, `CmdTargetModel`).
- [x] Remove old Lua FFI replay handlers corresponding to deleted generic `CmdBinary`, `CmdLoad`, and `CmdStore` ASDL commands.
- [x] Update `src/ffi.rs` command API.
- [x] Update `src/lib.rs` `BackCmd` enum.
- [x] Add Rust representations for memory and int/float semantic facts used by active execution; target/address/alias fact structs remain future direct-ownership work beyond current replay needs.
- [x] Map `BackMemoryInfo` to Cranelift `MemFlags` only where exact semantics match.
- [x] Map stack/data/load/store alignment facts where applicable through `BackMemoryInfo -> MemFlags::aligned` when the fact proves natural access alignment; vector-kernel lowering now supplies natural alignment facts.
- [x] Map vector select to valid per-type lowering for active integer vectors and reject future float-vector selects until an explicit float-vector select/blend command exists.
- [x] Keep facts as validation/scheduling evidence where Cranelift cannot consume them directly.
- [x] Ensure all active JIT tests use direct `Moon2Back` execution.

### 9. Delete obsolete compatibility material

- [x] Ensure no active file requires `moonlift_legacy.asdl`.
- [x] Ensure no active file requires `moonlift_legacy.jit`.
- [x] Ensure no active file requires `moonlift.back_to_moonlift`.
- [x] Ensure no active ASDL references `MoonliftBack`.
- [x] Delete/archive bridge-only tests if any remain active.
- [x] Remove old documentation references to bridge execution.

### 10. Diagnostics and inspection

- [x] Add backend command count reporting by command kind.
- [x] Add target model reporting.
- [x] Add vector schedule reporting.
- [x] Add address/provenance reporting.
- [x] Add memory-info reporting for loads/stores.
- [x] Add alias relation reporting.
- [x] Add int/float semantic reporting.
- [x] Add optional CLIF/disassembly dump for benchmark kernels through `back_diagnostics.lua` / artifact disassembly hooks.
- [x] Add comparison notes against Terra output in `BENCHMARK_RESULTS.md`; direct LLVM/CLIF deeper comparison remains future tuning detail.

### 11. Packed command tape, after semantics are clean

- [x] Design `BackCommandTape` as an encoding of `Moon2Back`, not a hidden IR.
- [x] Pack strings/numbers/opcodes/fact references into deterministic command-tape payloads.
- [x] Replace active per-command Lua→Rust FFI replay with a single `moonlift_jit_compile_tape` call.
- [x] Keep the ASDL command stream as the semantic source of truth.

### 12. Benchmark and tune

- [x] Re-run compile-time benchmark against Terra.
- [x] Re-run runtime benchmark against Terra.
- [x] Compare `sum_i32` schedule and disassembly.
- [x] Compare `dot_i32` schedule and disassembly.
- [x] Compare `add_i32` schedule and disassembly.
- [x] Compare `scale_i32` schedule and disassembly.
- [x] Classify each remaining runtime gap as A/B/C/D/E from section 14 in `BENCHMARK_RESULTS.md`.
- [ ] Only then add further ASDL facts or schedule decisions.

---

## 16. Success criteria

This refactor is successful when:

- `Moon2Back` is the single executable backend ASDL.
- Target truth has one canonical executable home.
- `HostTargetModel` and `VecTargetModel` are derived facets, not independent truths.
- No active path uses `MoonliftBack` or `back_to_moonlift`.
- Pointer address formation is not hidden as generic integer addition.
- Load/store commands carry explicit memory facts.
- Alias facts are explicit relations among accesses.
- Trap and motion semantics are explicit and separately validated.
- Integer/float commands carry explicit semantic facts.
- Vector schedule is explicit and consumed by lowering.
- Specialized i32 vector kernel variants are gone, including `VecKernelReductionI32Add`.
- Rust lowering uses facts where Cranelift 0.130.1 supports them.
- Facts that Cranelift cannot consume still explain Moonlift legality/schedule.
- Runtime benchmarking can classify differences as missing facts, dropped facts,
  ignored facts, Cranelift transform limits, or bad schedule choices.

The final architecture should make optimization work feel like extending a
language of facts, not patching a backend with helpers.

---

## 17. Short version

Current problem:

```text
Moon2Vec has facts.
Moon2Back cannot carry them.
Rust emits conservative Cranelift IR.
```

Correct target:

```text
Moon2Vec proves and schedules.
Moon2Back preserves executable facts in flat commands.
back_validate checks fact consistency.
Rust/Cranelift lowers an already-good backend program.
```

Design rule:

```text
No compatibility variants.
No hidden helper optimizer.
No legacy bridge.
No duplicated target truth.
No pretending Cranelift is LLVM.
```

If a runtime-relevant fact matters, it becomes ASDL.
