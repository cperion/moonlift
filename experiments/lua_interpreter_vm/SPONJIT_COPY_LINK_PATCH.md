# SponJIT Copy-Link-Patch Native Fragment ABI Specification

**Status:** draft specification; not implemented.

**Spec version:** 0.1

**Decision:** Copy-Link-Patch uses a **Native Fragment ABI with Continuation
Relocations**. C-function-shaped stencils are not linkable fragments.

The keywords **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are
normative.

---

## 1. Scope

This specification defines the ABI for SpongeJIT Copy-Link-Patch fragments.

It specifies:

- native fragment descriptors
- physical endpoint contracts
- data relocations
- control relocations
- continuation endpoints
- projection recipes
- validation rules
- image linking rules
- rejection conditions

It does not specify:

- a general machine-code assembler
- a full optimizing compiler
- a Moonlift/Cranelift backend
- payload lease policy for all future object-model facts
- final binary encoding of descriptor arrays

---

## 2. Unified tier model

There is one target stencil ABI: native fragments.

C-function-shaped tiles are an old implementation artifact, not a second target ABI.
A conforming SpongeJIT bank MUST expose native fragments for both floor coverage and
hot fused images.

### 2.1 Floor / Tier 1 image

The floor/Tier 1 image uses the same native fragment ABI as every hotter image.

Tier 1 behavior is the simplest legal linking policy:

```text
select fragment templates -> canonical slot endpoints -> copy bytes -> patch data/control relocations -> enter image
```

Tier 1 SHOULD keep boundaries frame-synchronized unless projection recipes prove a
more direct endpoint is valid.

Tier 1 MUST NOT require a C-function return boundary for normal success flow.

### 2.2 Hot fused image

A hot fused image uses the same fragment descriptors and linker, but may select
longer spans, preserve register endpoints across fragments, insert fewer bridges,
and use richer projection recipes.

Hot fused image behavior is:

```text
select native fragments -> lay out one image -> patch data/control relocations -> enter once
```

No tier MAY synthesize arbitrary machine instructions at runtime.

All tiers MAY copy, lay out, link, and patch only descriptors emitted by the foundry.

---

## 3. Terms

### Fragment

A **fragment** is a relocatable native code region with explicit entry and exit
endpoints.

A fragment is not a C function.

### Endpoint

An **endpoint** is a named control position inside a fragment:

- `ENTRY`
- `OK`
- `GUARD_FAIL`
- `RESIDUAL`
- `BOUNDARY`
- `RETURN`
- `BRANCH_TRUE`
- `BRANCH_FALSE`

### Data relocation

A **data relocation** patches a value consumed by native code: slot offset,
immediate, constant, helper address, dependency address, payload address, etc.

### Control relocation

A **control relocation** patches a control-transfer target: success continuation,
guard failure target, residual target, branch target, projection stub, return target.

### Projection

A **projection** reconstructs interpreter-visible state at a non-success exit.

### Physical ABI

A **physical ABI** defines architecture, platform calling convention, fixed register
roles, clobber rules, stack rules, and context/frame locations.

---

## 4. Non-goals and prohibitions

A Copy-Link-Patch implementation MUST NOT treat existing `exit`/`fail` metadata
holes as native branch targets unless they are retyped as control relocations.

A Copy-Link-Patch implementation MUST NOT delete a frame store across an exit unless
that exit has a complete projection recipe.

A Copy-Link-Patch implementation MUST NOT patch unsupported hole roles with dummy
values.

A Copy-Link-Patch implementation MUST NOT infer clobbers or endpoint locations by
reverse-engineering machine code.

A Copy-Link-Patch implementation MUST NOT require runtime instruction encoding for
ordinary fragment linking.

---

## 5. Descriptor model

A fragment catalog MUST provide these descriptor classes:

```text
SponPhysicalAbiDesc
SponFragmentDesc
SponEndpointDesc
SponLocationDesc
SponDataRelocDesc
SponControlRelocDesc
SponFactTransferDesc
SponEffectDesc
SponProjectionDesc
SponProjectionEntryDesc
SponDependencyDesc
```

The binary representation is implementation-defined, but the semantic fields in
this specification are mandatory unless explicitly marked optional.

---

## 6. Physical ABI descriptor

### 6.1 Required fields

```text
SponPhysicalAbiDesc:
  abi_id:              u16
  arch:                enum
  platform_abi:        enum
  pointer_width:        u8
  endian:              enum
  ctx_location:         Location
  frame_location:       Location
  scratch_locations:    LocationSet
  preserved_locations:  LocationSet
  flag_clobber_policy:  enum
  stack_alignment:      u16
  red_zone_policy:      enum
```

### 6.2 Rules

Each fragment MUST reference exactly one `SponPhysicalAbiDesc`.

The linker MUST reject a fragment whose `abi_id` is unsupported by the current
runtime.

The linker MUST verify that all linked fragments in one fused image use compatible
physical ABIs.

`ctx_location` and `frame_location` MUST be valid at every fragment entry.

A fragment MUST declare all clobbered physical locations that may be observed by
successor fragments or projection stubs.

---

## 7. Location model

### 7.1 Location kinds

```text
LOC_NONE
LOC_FRAME_SLOT
LOC_CANON_SLOT
LOC_GPR
LOC_XMM
LOC_FLAGS
LOC_IMM32
LOC_IMM64
LOC_CONST_POOL
LOC_CTX
LOC_FRAME_BASE
LOC_HELPER
```

### 7.2 Location descriptor

```text
SponLocationDesc:
  kind:      LocationKind
  index:     u16
  type:      ValueType
  flags:     LocationFlags
```

### 7.3 Value types

```text
VAL_UNKNOWN
VAL_TVALUE
VAL_BOOL
VAL_I64
VAL_F64
VAL_PTR
VAL_TABLE
VAL_SHAPE
VAL_CONTINUATION
VAL_VOID
```

### 7.4 Rules

A physical register location MUST name a concrete register class/member under the
fragment's `physical_abi_id`.

A fragment output location MUST NOT be assumed live after a successor fragment
clobbers it.

A `LOC_CANON_SLOT` is a template-local canonical slot class.

A `LOC_FRAME_SLOT` is an actual runtime frame slot.

The linker MUST resolve canonical slots to actual frame slots before patching native
code.

---

## 8. Fragment descriptor

### 8.1 Required fields

```text
SponFragmentDesc:
  fragment_id:          u32
  physical_abi_id:      u16

  text_offset:          u64
  text_size:            u32
  entry_offset:         u32

  source_start_pc:      u32
  source_len:           u16
  semantic_class:       u32

  endpoint_start:       u32
  endpoint_count:       u16

  input_start:          u32
  input_count:          u16
  output_start:         u32
  output_count:         u16
  clobber_start:        u32
  clobber_count:        u16

  data_reloc_start:     u32
  data_reloc_count:     u16
  ctrl_reloc_start:     u32
  ctrl_reloc_count:     u16

  fact_transfer_id:     u32
  effect_id:            u32

  projection_start:     u32
  projection_count:     u16

  dependency_start:     u32
  dependency_count:     u16

  flags:                u32
```

### 8.2 Rules

`entry_offset` MUST be within `[0, text_size)`.

Every endpoint offset MUST be within `[0, text_size)` unless the endpoint is
represented purely by a control relocation site.

A fragment MUST declare at least one `ENTRY` endpoint.

A fragment that can continue on the hot path MUST declare one `OK` endpoint or one
success control relocation.

A fragment that can fail a guard MUST declare a `GUARD_FAIL` endpoint or guard-fail
control relocation.

A fragment that may return to the VM MUST declare `RETURN` or `BOUNDARY` semantics.

A fragment MUST declare all data and control relocations required for materialization.

A fragment MUST NOT require implicit fallthrough unless the descriptor marks the
`OK` endpoint as layout-adjacent fallthrough-capable.

---

## 9. Endpoint descriptor

```text
SponEndpointDesc:
  fragment_id:      u32
  kind:             EndpointKind
  offset:           u32
  input_start:      u32
  input_count:      u16
  output_start:     u32
  output_count:     u16
  fact_require_id:  u32
  fact_produce_id:  u32
  projection_id:    u32    // zero if not applicable
  flags:            u32
```

Endpoint kinds:

```text
ENDPOINT_ENTRY
ENDPOINT_OK
ENDPOINT_GUARD_FAIL
ENDPOINT_RESIDUAL
ENDPOINT_BOUNDARY
ENDPOINT_RETURN
ENDPOINT_BRANCH_TRUE
ENDPOINT_BRANCH_FALSE
```

Rules:

An `ENTRY` endpoint MUST define required input locations.

An `OK` endpoint MUST define produced output locations and fact transfer.

Non-success endpoints that can resume outside the fused image MUST reference a valid
projection recipe or explicitly declare `SYNCED_FRAME` projection.

---

## 10. Relocation descriptors

## 10.1 Data relocation kinds

```text
DATA_RELOC_SLOT_OFFSET
DATA_RELOC_SLOT_STORE_OFFSET
DATA_RELOC_IMM32
DATA_RELOC_IMM64
DATA_RELOC_CONST
DATA_RELOC_BOOL
DATA_RELOC_SHAPE_ID
DATA_RELOC_FIELD_OFFSET
DATA_RELOC_ARRAY_BASE_OFFSET
DATA_RELOC_CALL_TARGET
DATA_RELOC_BARRIER_CELL
DATA_RELOC_DEPENDENCY_CELL
DATA_RELOC_HELPER_ADDR
```

### 10.2 Control relocation kinds

```text
CTRL_RELOC_OK
CTRL_RELOC_GUARD_FAIL
CTRL_RELOC_RESIDUAL
CTRL_RELOC_BOUNDARY
CTRL_RELOC_RETURN
CTRL_RELOC_BRANCH_TRUE
CTRL_RELOC_BRANCH_FALSE
CTRL_RELOC_PROJECTION_STUB
CTRL_RELOC_FALLBACK_STUB
```

### 10.3 Data relocation descriptor

```text
SponDataRelocDesc:
  fragment_id:      u32
  code_offset:      u32
  reloc_encoding:   RelocEncoding
  kind:             DataRelocKind
  op_idx:           u16
  arg:              i32
  width:            u8
  flags:            u32
```

### 10.4 Control relocation descriptor

```text
SponControlRelocDesc:
  fragment_id:      u32
  code_offset:      u32
  reloc_encoding:   RelocEncoding
  kind:             ControlRelocKind
  source_endpoint:  EndpointKind
  target_policy:    TargetPolicy
  op_idx:           u16
  flags:            u32
```

### 10.5 Relocation encodings

At minimum, an implementation SHOULD support:

```text
RELOC_ABS64
RELOC_REL32
RELOC_IMM32
RELOC_IMM64
```

Rules:

A relocation write MUST fit the declared width and encoding.

A control relocation target MUST be resolved after final layout.

A data relocation target MUST be resolved before executable permission is installed.

Unsupported relocation kinds MUST reject the fragment image.

---

## 11. Fact transfer descriptor

```text
SponFactTransferDesc:
  selector_sig:  u64
  required_sig:  u64
  checked_sig:   u64
  produced_sig:  u64
  killed_sig:    u64
```

Rules:

Before linking a fragment at a span, the linker MUST verify:

```text
(required_sig & ~available_facts) == 0
```

After a fragment succeeds, the linker/runtime fact model MUST apply:

```text
facts_out = (facts_in & ~killed_sig) | produced_sig | checked_sig
```

Payload facts not represented in the 64-bit signature MUST be represented by
separate dependency/payload descriptors before materialization.

A fragment requiring an unavailable payload MUST be rejected.

---

## 12. Effect descriptor

```text
SponEffectDesc:
  may_frame_read:       bool
  may_frame_write:      bool
  may_heap_read:        bool
  may_heap_write:       bool
  may_call:             bool
  may_gc:               bool
  may_throw:            bool
  may_yield:            bool
  may_barrier:          bool
  may_debug_observe:    bool
  is_branch:            bool
  is_return:            bool
  is_residual:          bool
```

Rules:

The linker MUST NOT reorder fragments across effects unless the relevant effect
ordering is proven safe by metadata.

For initial Copy-Link-Patch validation, the linker SHOULD reject fragments with
`may_call`, `may_gc`, `may_throw`, or `may_yield` unless fallback/projection behavior
is fully specified.

---

## 13. Projection descriptor

### 13.1 Projection classes

```text
PROJ_SYNCED_FRAME
PROJ_REGISTER
PROJ_VIRTUAL
```

### 13.2 Projection descriptor

```text
SponProjectionDesc:
  projection_id:     u32
  class:             ProjectionClass
  resume_pc:         u32
  resume_op_idx:     u16
  entry_start:       u32
  entry_count:       u16
  flags:             u32
```

### 13.3 Projection entry descriptor

```text
SponProjectionEntryDesc:
  projection_id:     u32
  dst_slot:          u16
  kind:              ProjectionEntryKind
  src0:              Location
  src1:              Location
  aux:               i64
  type:              ValueType
```

Projection entry kinds:

```text
PROJ_ENTRY_FROM_SLOT
PROJ_ENTRY_FROM_REGISTER
PROJ_ENTRY_CONST
PROJ_ENTRY_BOX_I64
PROJ_ENTRY_UNBOX_I64
PROJ_ENTRY_ADD_I64
PROJ_ENTRY_COPY_TVALUE
```

### 13.4 Rules

Every non-success endpoint that can leave the fused image MUST have a projection
descriptor.

A projection descriptor MUST reconstruct every interpreter-visible slot required at
`resume_pc`.

`PROJ_VIRTUAL` entries MUST be bounded pure expressions.

Projection expressions MUST NOT read heap state unless the projection descriptor
explicitly declares and validates the dependency.

If any source location required by a projection is clobbered before the endpoint,
the image MUST be rejected.

If `resume_pc` or `resume_op_idx` cannot be mapped to the interpreter/floor resume
protocol, the image MUST be rejected.

---

## 14. Dependency descriptor

```text
SponDependencyDesc:
  dependency_id:     u32
  kind:              DependencyKind
  payload_location:  Location
  epoch_location:    Location
  invalidation_mode: enum
  flags:             u32
```

Dependency kinds:

```text
DEP_SHAPE
DEP_METATABLE_ABSENT
DEP_FIELD_OFFSET
DEP_ARRAY_BOUNDS
DEP_CALL_TARGET
DEP_BARRIER_STATE
```

Rules:

A fragment requiring a dependency MUST provide enough metadata for the runtime to
validate the dependency before image publication.

If the runtime cannot validate a dependency kind, the image MUST be rejected.

Dependency invalidation MUST transfer control to a valid lower/floor image or the
interpreter; it MUST NOT continue executing stale fragment code.

---

## 15. Image descriptor

A linked image is not a bank artifact. It is a runtime product.

```text
SponFragmentImage:
  pc_start:             u32
  pc_end:               u32
  physical_abi_id:      u16
  entry_addr:           pointer
  text_addr:            pointer
  text_size:            u32
  instance_count:       u16
  projection_count:     u16
  observed_sig:         u64
  entry_sig:            u64
  flags:                u32
```

Rules:

An image MUST contain one executable allocation for the hot linked body and its cold
stubs, unless platform constraints require a documented split.

An image MUST NOT be published until all relocations are patched and executable
memory permissions are installed.

On platforms requiring instruction-cache maintenance, the runtime MUST perform it
before publication.

---

## 16. Linker algorithm

The linker MUST perform these phases in order or prove an equivalent ordering:

```text
1. Select candidate fragment instances.
2. Verify physical ABI compatibility.
3. Resolve canonical slots to actual frame slots.
4. Validate required facts and payload dependencies.
5. Validate endpoint input/output compatibility.
6. Insert bridge fragments where required and available.
7. Validate clobbers against live endpoint/projection values.
8. Validate projection completeness for all non-success exits.
9. Assign final layout offsets.
10. Resolve control targets.
11. Allocate writable image memory.
12. Copy fragment text.
13. Apply data relocations.
14. Apply control relocations.
15. Install projection/fallback stubs.
16. Change memory permissions to executable.
17. Publish image atomically.
```

At any failed validation step, the linker MUST reject the candidate image and leave
the currently active valid image unchanged.

---

## 17. Endpoint compatibility

An edge from producer endpoint `P` to consumer endpoint `C` is compatible iff:

```text
P.output_count satisfies C.input_count
for each required C input:
  there exists a live P output or prior live value with same ValueType and Location
required facts of C are available after P fact transfer
P clobbers do not destroy values needed by C or by exit projections
```

If not compatible, the linker MAY insert bridge fragments.

A bridge fragment MUST itself satisfy this specification.

If no legal bridge sequence exists within runtime budget, the image MUST be rejected.

---

## 18. Layout rules

The layout SHOULD place hot success paths contiguously.

The layout SHOULD place guard/residual/projection/fallback stubs out of line.

If an `OK` edge is fallthrough-capable and the successor `ENTRY` is placed
immediately after the producer body, the linker MAY omit or neutralize the `OK`
control relocation, if the fragment descriptor permits this.

The linker MUST NOT assume fallthrough unless the descriptor marks the endpoint as
fallthrough-capable.

---

## 19. Runtime exit protocol

A non-success endpoint MUST transfer to one of:

```text
projection stub
fallback stub
lower-image resume trampoline
floor/interpreter resume trampoline
VM return trampoline
```

The exit protocol MUST provide:

```text
exit kind
resume pc
resume op index when applicable
projected frame state
fact delta or contradicted fact when applicable
```

The exit protocol MUST be compatible with lower-image, floor, or interpreter
resumption.

---

## 20. Current implementation mapping

The current C-function tile ABI is non-conforming and maps only partially:

```text
Current SponTileDesc       -> not sufficient for SponFragmentDesc
Current SponHoleReloc      -> data holes only, not full control relocations
Current exit/fail holes    -> resume metadata, not branch targets
Current slotmaps           -> canonical slot mapping, not liveness/projection
Current fact signatures    -> usable for simple slot facts, not payload leases
Current projection summary -> counts/reasons only, not recipes
```

Therefore, current C-function stencils MUST NOT be treated as conforming native
fragments. The target architecture replaces them with native fragments rather than
maintaining a dual ABI.

---

## 21. Initial conformance surface

The first conforming fragment set SHOULD be limited to:

```text
i64 slot loads
i64 slot stores
i64 guards
i64 add/sub/mul-like arithmetic
immediates/constants
simple success continuations
guard failure exits with synced-frame or register projection
```

The first conforming fragment set SHOULD NOT include:

```text
shape payloads
field payloads
array payloads
call target payloads
barrier/dependency cells
may_call/may_gc/may_yield fragments
```

This is not a reduced ABI. It is the first conformance surface for validating the
full ABI rules without unresolved payload machinery.

---

## 22. Required validation experiments

### 22.1 Metadata sufficiency

For each candidate fragment class, verify that descriptors can name:

```text
entry endpoint
success endpoint
failure endpoints
inputs
outputs
clobbers
data relocations
control relocations
fact transfer
effects
projection recipes
dependencies
```

### 22.2 Linkability

Given representative i64 fragment sequences, verify:

```text
endpoint matches
bridge insertions
spill insertions
control target resolution
fallthrough eligibility
rejection reasons
```

### 22.3 Projection correctness

For every non-success endpoint, verify:

```text
resume pc correctness
resume op index correctness
all required slots reconstructed
projection source values live
projection expressions bounded and pure
```

### 22.4 Execution equivalence

For every executable linked image, compare against:

```text
PUC interpreter behavior
floor/native-fragment image behavior
expected frame state
expected exit state
expected resume pc/op index
```

---

## 23. Conformance checklist

A fragment catalog conforms to this specification iff:

```text
[ ] every fragment has a valid physical ABI descriptor
[ ] every fragment has explicit entry metadata
[ ] every control transfer target is represented by endpoint/control-reloc metadata
[ ] every data patch site is represented by data-reloc metadata
[ ] every fragment declares inputs, outputs, and clobbers
[ ] every fragment declares fact transfer
[ ] every fragment declares effects
[ ] every non-success exit has a projection descriptor
[ ] every dependency is explicit and runtime-validatable
[ ] unsupported holes/dependencies reject image construction
[ ] no C-function return boundary is required for hot success flow
```

A runtime linker conforms iff:

```text
[ ] it validates physical ABI compatibility
[ ] it validates facts and dependencies
[ ] it resolves canonical slots
[ ] it validates endpoint compatibility
[ ] it validates clobbers against live values/projections
[ ] it validates projection completeness
[ ] it patches data relocations
[ ] it patches control relocations
[ ] it publishes only fully patched executable images
[ ] it leaves the current valid image active on rejection
```

---

## 24. One-line rule

```text
A function stencil is a sealed callable tile.
A native fragment stencil is a linkable region with explicit continuations.
```

Copy-Link-Patch requires native fragment stencils.
