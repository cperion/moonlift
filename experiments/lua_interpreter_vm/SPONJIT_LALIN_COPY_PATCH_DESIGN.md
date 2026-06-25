# SpongeJIT Lalin Copy-and-Patch Executor Design

## Purpose

Design the Lalin-native runtime that selects, materializes, patches, and
publishes SpongeJIT fast-path stencils generated from explicit ASDL semantics.

The executor is part of the retained copy-and-patch goal. It is not a descriptor
compatibility ABI, and it is not a Lua interpreter. It is a typed Lalin system
whose data types and control protocols are the design.

This document follows the explicit-programming discipline:

- first define the data tree: every value and every alternative is a Lalin
  `struct` or `union`;
- then define the control tree: every operation is a Lalin `region` with
  named typed continuations;
- no strings, booleans, integer tags, hidden state, or helper calls carry
  behaviorally meaningful distinctions;
- compose with regions, seal with functions only when an operation has one
  settled outcome.

---

## One-sentence architecture

The runtime observes typed VM facts, canonicalizes them into a tile key, selects
an ASDL-derived stencil template, copies its native bytes, patches typed holes,
applies typed relocations, protects the memory as executable, and publishes a
callable native fast path.

```text
Runtime VM state
  -> FactCollector regions
  -> FactSignature + PatchSet
  -> TileKey
  -> Bank lookup
  -> StencilTemplate
  -> copy / patch / relocate / protect
  -> MaterializedCode
```

The executor never executes Lua semantics. Lua semantics are consumed earlier:

```text
LuaSrc + LuaFact
  -> LuaRT/LuaExec
  -> CompileContract
  -> LalinCFG ASDL
  -> Lalin/Cranelift native code
  -> StencilTemplate metadata
```

---

## Layer responsibilities

| Layer | Medium | Responsibility |
|---|---|---|
| Lua semantic source | ASDL | Lua meaning, generic operations, typed continuations, contracts |
| LalinCFG | ASDL | executable semantic CFG shape derived from Lua semantics |
| Stencil artifact | ASDL + serialized bank image | code blobs, patch holes, relocs, variant keys |
| Runtime fact collector | Lalin | read VM state and produce typed fact signatures/patch values |
| Runtime selector | Lalin | choose the matching stencil from a bank |
| Runtime materializer | Lalin | copy bytes, patch holes, apply relocs, publish executable memory |

The ASDL side is the semantic source of truth. The Lalin runtime side is the
materialization implementation. The two meet through generated bank data whose
layout is described by Lalin types.

---

# Data tree

The runtime data tree is the set of Lalin types below. These types describe
runtime materialization state only. They do not encode Lua opcode semantics.

## Scalar handles

```lalin
struct WindowId
    hash: u64
end

struct FactSetId
    hash: u64
end

struct ContractId
    hash: u64
end

struct CfgShapeId
    hash: u64
end

struct TargetId
    hash: u64
end

struct TemplateId
    index: u32
end

struct SymbolId
    index: u32
end
```

These are typed handles. They are not string keys and not raw integers in the
logic of the design.

## Tile key

A tile key is the runtime selector's input. It combines the current bytecode
window identity, observed facts, semantic contract/CFG identity, and target
layout.

```lalin
struct TileKey
    window: WindowId
    facts: FactSetId
    contract: ContractId
    cfg: CfgShapeId
    target: TargetId
end
```

Allowed meaning:

- `window`: which source tile/window was considered;
- `facts`: which canonical runtime facts were observed;
- `contract`: which invalidation/projection obligations the stencil assumes;
- `cfg`: which ASDL LalinCFG shape was compiled;
- `target`: which ABI/layout/codegen target produced the bytes.

Forbidden meaning:

- opcode handler names;
- protocol exit names;
- descriptor compatibility labels;
- strings like `GETTABLE_FASTPATH`;
- hidden fallback classes.

## Runtime fact vocabulary

Facts are not Lua semantics. Facts are observations about the current runtime
state that select a specialized semantic CFG already generated offline.

Every fact alternative is a sum variant.

```lalin
union FactSubject
    stack_slot(slot: u32)
  | const_slot(slot: u32)
  | upvalue_slot(slot: u32)
  | table_object(id: u64)
  | global_state()
end

union RuntimeFact
    is_nil(subject: FactSubject)
  | is_bool(subject: FactSubject)
  | is_i64(subject: FactSubject)
  | is_f64(subject: FactSubject)
  | is_string(subject: FactSubject)
  | is_table(subject: FactSubject)
  | is_closure(subject: FactSubject)
  | shape_eq(subject: FactSubject, shape: u64)
  | metatable_absent(subject: FactSubject)
  | metatable_eq(subject: FactSubject, metatable: u64)
  | array_bounds_ok(subject: FactSubject, index_slot: u32)
  | array_len(subject: FactSubject, len: u64)
  | field_present(subject: FactSubject, key: u64, offset: u32)
  | barrier_clean(subject: FactSubject)
  | epoch(subject: FactSubject, value: u64)
end
```

The collector may read VM state to construct these facts. It must not perform
Lua operations such as table lookup with metamethods, CALL, CLOSE, or opcode
execution.

## Fact signature

A fact signature is the canonical runtime representation used for bank lookup.

```lalin
struct FactSignature
    id: FactSetId
    facts: view(RuntimeFact)
end
```

The `id.hash` is derived from the canonical ordered facts. The facts view is
available for equality verification and debugging. The selector can use a hash
first, but equality must be defined over typed facts, not opaque strings.

## Patch values

Patch values are materialization inputs derived from runtime state and the
selected stencil contract. They are typed values used to fill holes.

```lalin
union PatchValue
    u8_value(value: u8)
  | u16_value(value: u16)
  | u32_value(value: u32)
  | u64_value(value: u64)
  | i32_value(value: i32)
  | i64_value(value: i64)
  | ptr_value(value: ptr(u8))
  | symbol_value(symbol: SymbolId)
  | template_value(template: TemplateId)
end

struct PatchSet
    values: view(PatchValue)
end
```

A patch value may be a stack offset, a constant address, a table shape pointer,
a branch target, or a symbol. Its role is determined by the `PatchHole` that
consumes it.

## Bank image

```lalin
struct CodeBlob
    bytes: view(u8)
    align_log2: u8
end

union TemplateKind
    kernel()
  | region()
  | block()
  | branch()
  | call_site()
  | guard_site()
end

struct StencilTemplate
    id: TemplateId
    kind: TemplateKind
    key: TileKey
    code: CodeBlob
    holes: view(PatchHole)
    relocs: view(Reloc)
    symbols: view(Symbol)
    frame_bytes: u32
    entry_offset: u32
end

struct BankIndexEntry
    key: TileKey
    template_id: TemplateId
end

struct BankImage
    entries: view(BankIndexEntry)
    templates: view(StencilTemplate)
    symbols: view(Symbol)
end
```

A bank image is a typed data structure. It is allowed to be memory-mapped,
serialized, or generated, but once loaded it must obey these types.

## Patch holes

```lalin
union PatchKind
    abs64()
  | rel32()
  | imm32()
  | imm64()
  | stack_offset32()
  | const_pool_offset32()
  | symbol_addr64()
  | template_entry_rel32()
end

struct PatchHole
    kind: PatchKind
    code_offset: u32
    width_bytes: u8
    align_log2: u8
    source_index: u32
end
```

A patch hole says how to mutate bytes. It does not say why the mutation is
semantically needed.

Allowed:

- patch a 32-bit immediate;
- patch a 64-bit address;
- patch a relative branch target;
- patch a stack/frame offset;
- patch a symbol/template address.

Forbidden:

- patch means “run GETTABLE”;
- patch means “resume CALL”;
- patch means “execute opcode”;
- patch means “fallback interpreter.”

## Relocations

```lalin
union RelocKind
    internal_branch_rel32()
  | external_symbol_abs64()
  | template_call_rel32()
end

struct Reloc
    kind: RelocKind
    code_offset: u32
    target_index: u32
    addend: i64
end

struct Symbol
    id: SymbolId
    address: ptr(u8)
end
```

Relocations are backend/linkage facts only.

## Materialized code

```lalin
struct MaterializedCode
    base: ptr(u8)
    len: index
    entry: ptr(u8)
    template_id: TemplateId
end
```

---

# Control tree

The control tree is the set of Lalin regions. Each operation has named typed
outcomes. There are no boolean success returns where variants belong.

## Fact collection regions

Fact collection is a first-class subsystem. It is separate from materialization.
It reads VM state and emits facts/patch values.

```lalin
region collect_tile_facts(
    vm: ptr(LuaVmState),
    window: WindowId,
    out_facts: ptr(RuntimeFact),
    out_patch_values: ptr(PatchValue),
    cap: index;

    collected(signature: FactSignature, patches: PatchSet),
    capacity_exceeded(required: index),
    invalid_window)
```

`collect_tile_facts` may inspect:

- bytecode window identity;
- stack slot tags and payloads;
- table shape/metatable/epoch fields;
- array length and bounds metadata;
- const/upvalue identities;
- frame top/vararg metadata;
- GC/barrier state.

It may not execute Lua operations.

The collector decomposes into smaller regions:

```lalin
region observe_slot(vm: ptr(LuaVmState), slot: u32, out: ptr(RuntimeFact), cap: index;
    observed(count: index),
    capacity_exceeded(required: index))

region observe_table_shape(vm: ptr(LuaVmState), slot: u32, out: ptr(RuntimeFact), cap: index;
    observed(count: index),
    not_table,
    capacity_exceeded(required: index))

region observe_array_bounds(vm: ptr(LuaVmState), table_slot: u32, index_slot: u32, out: ptr(RuntimeFact), cap: index;
    bounds_ok(count: index),
    bounds_not_known(count: index),
    not_applicable)

region derive_patch_values(vm: ptr(LuaVmState), signature: FactSignature, out: ptr(PatchValue), cap: index;
    derived(patches: PatchSet),
    capacity_exceeded(required: index),
    unavailable)
```

Each outcome is explicit. A missing fact is not a silent fallback; it produces a
different signature that may or may not have a matching stencil.

## Key construction

```lalin
region build_tile_key(
    window: WindowId,
    facts: FactSignature,
    contract: ContractId,
    cfg: CfgShapeId,
    target: TargetId;

    built(key: TileKey))
```

This is a settled operation with one outcome. It can later be sealed as a
`func`, but as a design region it states the data flow explicitly.

## Bank lookup

```lalin
region lookup_template(bank: ptr(BankImage), key: TileKey;
    found(template: ptr(StencilTemplate)),
    not_found)
```

Lookup is not Lua semantics. `not_found` means the bank does not contain a
compiled artifact for this window/fact/contract/cfg/target combination.

## Allocation

```lalin
region allocate_writable_exec(len: index, align_log2: u8;
    allocated(mem: ptr(u8), len: index),
    alloc_failed(code: i32))
```

This region wraps platform externs such as `mmap`.

## Copying

```lalin
region copy_code_blob(dst: ptr(u8), blob: CodeBlob;
    copied,
    copy_failed(code: i32))
```

Copying is a byte operation.

## Patching

```lalin
region apply_patch_holes(dst: ptr(u8), template: ptr(StencilTemplate), patches: PatchSet;
    patched,
    missing_value(hole_index: index, source_index: u32),
    kind_mismatch(hole_index: index),
    out_of_bounds(hole_index: index))
```

Patch failure outcomes name exactly what failed.

## Relocation

```lalin
region apply_relocs(dst: ptr(u8), template: ptr(StencilTemplate), bank: ptr(BankImage);
    relocated,
    missing_symbol(reloc_index: index, symbol: SymbolId),
    unsupported_reloc(reloc_index: index),
    out_of_bounds(reloc_index: index))
```

## Protection and publishing

```lalin
region protect_executable(mem: ptr(u8), len: index;
    protected,
    protect_failed(code: i32))

region publish_code(mem: ptr(u8), len: index, entry_offset: u32, template: TemplateId;
    published(code: MaterializedCode),
    publish_failed(code: i32))
```

Publishing may include instruction-cache flushes or memory fences where required
by the platform.

## Full materialization protocol

```lalin
region materialize_template(
    bank: ptr(BankImage),
    template: ptr(StencilTemplate),
    patches: PatchSet;

    materialized(code: MaterializedCode),
    alloc_failed(code: i32),
    copy_failed(code: i32),
    patch_failed(hole_index: index),
    reloc_failed(reloc_index: index),
    protect_failed(code: i32),
    publish_failed(code: i32))
```

This region composes allocation, copy, patch, relocation, protection, and
publishing. It forwards failures directly.

## Full selection + materialization protocol

```lalin
region select_and_materialize(
    vm: ptr(LuaVmState),
    bank: ptr(BankImage),
    window: WindowId,
    contract: ContractId,
    cfg: CfgShapeId,
    target: TargetId,
    fact_buf: ptr(RuntimeFact),
    patch_buf: ptr(PatchValue),
    buf_cap: index;

    ready(code: MaterializedCode),
    no_matching_tile(key: TileKey),
    fact_capacity_exceeded(required: index),
    invalid_window,
    materialization_failed(code: i32))
```

This is the runtime root operation. It has no generic “error bool” and no hidden
state. Each possible outcome is a continuation.

---

# Externs

Lalin can call libc/syscalls directly. Platform operations are explicit
externs. They are not Lua semantic helpers.

```lalin
extern mmap(addr: ptr(u8), len: index, prot: i32, flags: i32, fd: i32, off: i64) -> ptr(u8) end
extern mprotect(addr: ptr(u8), len: index, prot: i32) -> i32 end
extern munmap(addr: ptr(u8), len: index) -> i32 end
extern memcpy(dst: ptr(u8), src: ptr(u8), n: index) -> ptr(u8) end
extern memcmp(a: ptr(u8), b: ptr(u8), n: index) -> i32 end
```

The design should wrap these externs in regions with typed continuations rather
than exposing raw integer conventions throughout the executor.

---

# Runtime fact acquisition

Fact acquisition is where the previous design was incomplete. The executor does
not “gather facts” as a side effect of copying. A separate fact collector reads
VM state and produces typed facts and patch values.

## Allowed collector behavior

- read stack slot tags;
- read stack slot payloads;
- read table shape identifiers;
- read metatable pointer/null state;
- read table epochs/version counters;
- read array length;
- compare array bounds using already-available numeric values;
- read const/upvalue/proto identities;
- read frame top and vararg layout metadata;
- read GC/barrier state needed for fact signatures.

## Forbidden collector behavior

- execute bytecode;
- perform Lua table access semantics;
- call metamethods;
- run CALL/RETURN/CLOSE semantics;
- allocate Lua values except collector output buffers;
- choose fallback semantics;
- call an interpreter helper.

The collector produces observations. It does not perform language operations.

---

# Relation to facts and Lua semantics

Facts are not the semantics of Lua. They are specialization evidence.

Example:

```text
Lua semantics of GETTABLE:
  table raw access, miss behavior, metatable lookup, __index chain/call,
  error/yield/control outcomes.

Facts for one specialized case:
  R2 is_table,
  R2 shape == S,
  R2 metatable_absent,
  key K has field offset O,
  table epoch E.
```

The semantic compiler uses those facts to choose a LalinCFG branch/region. The
runtime collector later checks whether the current VM state still matches a
fact signature with a generated stencil.

If no generated fact signature matches, the selector returns `no_matching_tile`.
That is not semantic fallback; it is a materialization outcome. Another tier
may decide what to do, but this executor does not execute Lua semantics.

---

# Tile generation model

For arity <= 4 and up to 32 fact combinations, the foundry can generate a finite
bank of tiles.

```text
for each bytecode window shape up to arity 4:
  for each fact combination up to 32:
    LuaSrc + LuaFact
      -> LuaRT/LuaExec
      -> CompileContract
      -> LalinCFG
      -> native code blob
      -> StencilTemplate
      -> BankIndexEntry
```

Runtime selection is therefore lookup over pre-generated semantic variants, not
interpretation.

---

# Efficient lookup

Initial bank lookup can be a sorted `BankIndexEntry` array:

```lalin
region lookup_template(bank: ptr(BankImage), key: TileKey;
    found(template: ptr(StencilTemplate)),
    not_found)
entry search(lo: index = 0, hi: index = len(bank.entries))
    -- binary search or generated perfect hash dispatch
end
end
```

A future generated perfect hash or trie is allowed, but it must still dispatch
on typed `TileKey`, not on opcode semantics.

---

# Memory lifecycle

Materialization sequence:

```text
allocate RW memory
copy code bytes
apply patch holes
apply relocations
protect RX
publish entry pointer
```

Unmaterialization sequence:

```text
unpublish entry pointer
munmap executable memory
invalidate metadata
```

These are runtime memory operations, not Lua operations.

---

# Testing policy

Main tests must be positive intended behavior tests.

Allowed main tests:

- valid facts produce a `FactSignature`;
- a known key finds a template;
- a template materializes into executable memory;
- patch holes mutate bytes correctly;
- relocs resolve correctly;
- no opcode/protocol fields appear in stencil keys;
- the executor does not call semantic helpers;
- generated stencils execute expected native behavior.

Do not write main tests where compiler/runtime rejection is success for valid
Lua behavior. Invalid bank image validation can have separate validator tests,
but those tests must be explicitly about malformed materialization data, not
about completing Lua semantics.

---

# Non-negotiable guardrails

1. The executor is semantics-blind.
2. Fact collection is explicit and typed.
3. Facts select generated semantic variants; facts do not replace semantics.
4. No opcode dispatch in materializer, selector, patcher, or stencil metadata.
5. No protocol `out_tag` accepted execution path.
6. No interpreter/helper stencils.
7. Patch holes are backend materialization sites only.
8. Stencil keys derive from ASDL semantic CFG + facts + contract + target.
9. Lalin structs/unions define runtime bank layout.
10. Lalin regions define executor control protocols.
11. Platform externs are OS/libc operations only.
12. Every meaningful alternative is a union variant or continuation.
13. Every persistent runtime state object is an explicit struct parameter.
14. No hidden globals except platform-provided process facilities wrapped by
    typed regions.

---

# What changed from the previous draft

The previous draft focused on bank lookup and copy/patch materialization. It was
incomplete because it did not design fact acquisition.

This rewrite adds the missing first-class subsystem:

```text
FactCollector
  -> FactSignature + PatchSet
Selector
  -> StencilTemplate
Materializer
  -> MaterializedCode
```

All three are Lalin control-tree nodes with typed continuations.

---

# Short answer

Yes, raw Lua semantics belong in ASDL. The runtime copy-and-patch executor is
Lalin code over Lalin types. The executor gathers no semantics; it gathers
facts through explicit fact-collector regions, selects a pre-generated
ASDL-derived stencil, and mechanically copies/patches/publishes native code.
