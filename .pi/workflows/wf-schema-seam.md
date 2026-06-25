# MOM ⇔ Rust Schema Seam 
The MLBT v3 wire format schema (tag table, slot counts, per-variant encoding) is duplicated across 4 locations: Lua encoder, MOM Lalin, Rust decoder, and spec doc. Explore whether the ASDL schema can be the single source of truth, and what it would take to derive encoder/decoder slot layouts from it.
**Started**: 2026-05-18 14:19:41
---

## Scout Output — 2026-05-18 14:21:30

Now I have gathered all the key information. Let me compile the comprehensive report.

---

## Files Retrieved

### 1. Lua Encoder: `lua/lalin/back_command_binary.lua` (entire file, 644 lines)
- **Lines 15-33**: `SCALAR_TAG` table — maps `BackBool`→1 through `BackIndex`→13
- **Lines 36-72**: `CMD_TAG` table — maps all 61 command variants to numeric tags 1-61
- **Lines 75-105**: Op tag tables — `INT_OP_TAG`, `BIT_OP_TAG`, `SHIFT_OP_TAG`, `ROTATE_OP_TAG`, `FLOAT_OP_TAG`, `UNARY_OP_TAG`, `INTRINSIC_OP_TAG`, `COMPARE_OP_TAG`, `CAST_OP_TAG`, `VEC_BIN_OP_TAG`, `VEC_CMP_OP_TAG`, `VEC_MASK_OP_TAG`, `ATOMIC_RMW_OP_TAG`
- **Lines 108-258**: Helper functions for encoding (shape encoding, address base, memory info, literal encoding, call result/target, etc.)
- **Lines 261-390**: `WireBuilder` class — string pool, aux data, command stream, serialization
- **Lines 393-633**: `Encoder` class — walks a `BackProgram` ASDL and calls `encode_cmd` per variant
- **Lines 636-644**: Public API — `Define(T)` returns `{ encode = function }`

### 2. MOM Wire Format Files

#### 2a. `lua/lalin/mom/driver/wire.mlua` (entire file, ~180 lines)
- **Lines 1-5**: Low-level MLBT v3 byte writer — `MomWireBuilder` struct definition
- **Lines 7-36**: `mw_write_u32`, `mw_patch_u32`, `mw_align4` — byte-level primitives
- **Lines 38-49**: `mw_init` — writes header (magic=0x4D4C4254, version=3, placeholder counts)
- **Lines 51-55**: `mw_finish` — patches string_count and aux_count into header
- **Lines 63-81**: `mw_write_pool_string`, `mw_write_aux_i32s` — pool/aux writers
- **Lines 83-127**: `mw_write_cmd0/1/3/5/7` — command write helpers for 0, 1, 3, 5, 7 slot counts
- **NOTE**: Only supports cmd0, cmd1, cmd3, cmd5, cmd7 — commands with 2, 4, 6, 8, 14, 15, 16, 17 slots use `mw_write_cmd` with explicit slot count

#### 2b. `lua/lalin/mom/driver/lower_wire.mlua` (entire file, ~280 lines)
- **Lines 1-20**: Command tape serialization helpers for MOM
- **Lines 51-97**: Duplicates `mw_init`, `mw_finish`, `mw_write_pool_string`, `mw_write_aux_i32s`, `mw_align4` and other primitives (code duplication from wire.mlua)
- **Lines 99-170**: `mom_wire_slot_count` — **duplicated slot count table** (if-else chain, tags 1-61)
- **Lines 172-210**: `mom_schema_cmd_tag_to_wire` — **duplicated tag mapping** (schema tags to wire tags, only 14 cmd variants mapped)
- **Lines 212-214**: `mom_schema_scalar_to_wire` — scalar tag mapping (`schema_scalar - 1`)
- **Lines 216-222**: `mom_schema_lit_tag_to_wire` — literal tag mapper
- **Lines 224-226**: `mom_wire_value_pool` — `value_id + 2` pool offset
- **Lines 228-258**: `mom_write_cmd_columns_to_wire` — column-major command writer

### 3. Rust Decoder: `src/ffi.rs`
- **Lines 651-735**: `SLOT_COUNT` static array — `[usize; 64]` with slot counts per tag (tag 0 invalid, tags 1-61 defined)
- **Lines 737-1565**: `BinaryReader` struct and implementation:
  - **Lines 741-744**: Fields: `buf`, `pos`, `pool`, `aux_offsets`, `aux_counts`
  - **Lines 746-802**: `BinaryReader::new()` — parses header (magic, version, n_strings, n_aux), reads string pool, records aux offsets
  - **Lines 804-894**: Helper methods: `take_u32`, `pool_str`, `pool_val`, `pool_block`, `pool_sig`, `pool_func`, `pool_extern`, `pool_data`, `pool_slot`, `pool_access`, `read_scalar`, `read_shape`, `aux_slice`, `aux_vals`, `aux_scalars`, `decode_address_base`, `decode_address`, `decode_memory`
  - **Lines 896-1565**: `decode_commands()` — massive match on tags 1-61, producing `BackCmd` variants
- **Lines 1567-1577**: `read_scalar_code()` scalar decoder (separate copy from `read_scalar`)
- **Lines 1579-1622**: Atomic ordering/rmw op readers
- **Lines 1624-1630**: `parse_back_command_binary()` public entry point
- **Lines 1634-1680**: `lalin_jit_compile_binary` FFI entry
- **Lines 1682-1720**: `lalin_object_compile_binary` FFI entry

### 4. Rust BackCmd Enum: `src/lib.rs`
- **Lines 310-402**: `BackCmd` enum — **~100+ flat variants** (not 61 schema variants; expanded by op kind)
- **Lines 404-437**: `BackDeclCmd` enum — 12 variants (module-level only)
- **Lines 439-700**: Sub-enums: `CfgOp` (7), `AddressOp` (4), `ConstOp` (4), `ScalarUnaryOp` (4), `IntrinsicOp` (10), `IntBinaryOp` (7), `FloatBinaryOp` (4), `BitwiseOp` (3), `ShiftOp` (3), `RotateOp` (2), `CompareOp` (16), `CastOp` (10), `PtrOp` (2), `MemoryOp` (9), `CallOp` (6), `ControlOp` (6), `VecUnaryOp` (5), `VecBinaryOp` (8), `VecCompareOp` (10), `VecMemoryOp` (2), `OtherOp` (3)
- **Lines 702-707**: `BackBodyCmd` enum — wraps the sub-enums into ~90+ variant equivalent
- **Lines 820-1080**: `BackProgram::partition()` — splits flat `BackCmd` into `BackDeclCmd` + `BackBodyCmd`

### 5. ASDL Schema: `lua/lalin/mom/schema/LalinBack.mlua` (entire file)
- **Lines 123-178**: `M.Cmd = union Cmd` — declares 61 command variants (from `CmdTargetModel` through `CmdFinalizeModule`)
- **Lines 1-115**: Supporting types: `BackAddressBase`, `BackShape`, `BackScalar` (14 variants), `BackMemoryInfo`, `BackAlignment`, `BackDereference`, `BackTrap`, `BackMotion`, `BackAccessMode`, `BackLiteral`, `BackCallResult`, `BackCallTarget`, etc.
- **Lines 180-227**: `BackProgram`, `BackValidationIssue` (35+ issue types), inspection types
- Total: lines 1-233 of the schema file

### 6. Spec Doc: `BACK_WIRE_FORMAT.md` (entire file)
- **Lines 182-183**: "Tags are assigned in declaration order from the `LalinBack.Cmd` ASDL union"
- **Lines 191-328**: Command tag table with slot counts for all 61 tags
- **Lines 330-331**: Scalar tag table (13 scalars)
- **Lines 436-478**: Slot count table (Appendix A, for decoder convenience)
- **Lines 480-500**: Validation checklist (Appendix B, 11 checks)

### 7. MOM Schema Tags: `lua/lalin/mom/back/back_tags.lua`
- **Lines 40-50**: Derives all `BackCmd` tags from `LalinBack.mlua` schema via `protocol_variants`
- **Lines 42-49**: `derive()` function: `variants` = union's protocol_variants; `tag = i - 1` (self-variant at index 1 is tag 0, unused)
- Derives tags for: `Cmd`, `BackScalar`, all op unions, `LalinCore` scalars/ops, etc.
- Lines 51-101+: MachineCastOp tags, binary class tags, SurfaceCastOp tags

### 8. MOM Generated Tags: `lua/lalin/mom/tags/mom_tags.lua`
- Generated by `tags_gen.lua` from ASDL schema
- Cmd tag constants: `CmdTargetModel=6`, `CmdCreateSig=7`, etc. — these are **schema variant array indices** (not wire tags)

### 9. Tests

#### 9a. `tests/test_back_command_binary.lua` (47 lines)
- Constructs `BackProgram` via ASDL, encodes with `back_command_binary.lua`, compiles via `back_jit`, runs native function
- End-to-end: Lua ASDL → binary encoder → JIT compile → execute

#### 9b. `tests/test_mom_wire.lua` (99 lines)
- Constructs MLBT v3 buffer directly using MOM `wire.mlua` primitives
- Tests: CmdCreateSig, CmdDeclareFunc, CmdBeginFunc, CmdCreateBlock, CmdSwitchToBlock, CmdConst, CmdReturnValue, CmdFinishFunc, CmdFinalizeModule
- **Full MOM → Rust path**: MOM wire builder → `mom_backend_compile_binary()` → artifact → getpointer → execute
- Tests `ret7()` returns 7

#### 9c. `tests/test_mom_source_to_binary.lua` (29 lines)
- Full source-to-binary pipeline: `lalin.native_loadstring()` → `<native>.get("ret7")` → execute
- Also tests `lalin.host_mom.wire()` produces valid wire bytes

---

## Key Code Excerpts

### Tag Duplication Surface

The **61 command tags** are independently defined in **5 locations**:

| Location | Lines | Representation |
|----------|-------|----------------|
| `BACK_WIRE_FORMAT.md` §7 | 191-328 | Text table + Appendix A slot count |
| `back_command_binary.lua` | 36-72 | Lua `CMD_TAG` table literal |
| `lower_wire.mlua` `mom_schema_cmd_tag_to_wire` | 172-210 | If-else chain (only 14 variants) |
| `lower_wire.mlua` `mom_wire_slot_count` | 99-170 | If-else chain (all 61 variants) |
| `src/ffi.rs` `SLOT_COUNT` | 651-735 | Rust static array |

The **slot counts per tag** are independently defined in **4 locations**:

| Location | Lines | Notes |
|----------|-------|-------|
| `BACK_WIRE_FORMAT.md` Appendix A | 436-478 | Reference table |
| `lower_wire.mlua` `mom_wire_slot_count` | 99-170 | MOM encoder uses this |
| `src/ffi.rs` `SLOT_COUNT` | 651-735 | Rust decoder uses this |
| Implicitly in `back_command_binary.lua` `Encoder:encode_cmd()` | 393-633 | Slots per variant are implicit in how many args are passed to `wb:cmd(tag, {...})` |

### Op Tag Duplication

The **operator tag tables** (INT_OP_TAG, COMPARE_OP_TAG, CAST_OP_TAG, etc.) are duplicated in:

1. `BACK_WIRE_FORMAT.md` §8.13-§8.24 (16 op tag tables in text)
2. `back_command_binary.lua` lines 75-105 (13 Lua tables)
3. `src/ffi.rs` decode_commands() (op match arms inside each tag handler)
4. `lower_wire.mlua` (only a few — limited MOM coverage currently)
5. `port_map.lua` lines 536-550 (documentation copy of all op tag tables)

### Schema Tag Gap

The **MOM back_tags.lua** derives tags from the ASDL schema union variant order (`i - 1`). These schema tags are **different from wire tags**.

For example:
- Schema: `CmdTargetModel` is the first variant → schema tag = 1 (index 2, minus 1)
- Wire: `CmdTargetModel` = 1 (matches by convention — but not guaranteed)
- Schema: `CmdTrap` is at variant index → schema tag = ? (depends on order in LalinBack.mlua)
- Wire: `CmdTrap` = 59

`lower_wire.mlua` `mom_schema_cmd_tag_to_wire` explicitly maps schema tags to wire tags for only 14 command variants (the ones MOM currently emits). This mapping function is **incomplete** — only ~14 of 61 commands are mapped.

The `mom_wire_slot_count` function (also in lower_wire.mlua) uses **wire tags** directly, not schema tags — which is inconsistent with `mom_schema_cmd_tag_to_wire` accepting schema tags.

---

## Relationships — Data Flow

```
Lua Compiler Path:
  BackProgram (ASDL) ──► back_command_binary.lua ──► MLBT bytes ──► ffi.parse_back_command_binary() ──► Vec<BackCmd>
                                                                         │
                                                                         ▼
                                                                  BackProgram::partition() ──► BackProgram
                                                                         │
                                                                         ▼
                                                                  Jit::compile() ──► Cranelift

MOM Compiler Path:
  Lalin source ──► native parse/typecheck/lower ──► CmdEntry[] ──► lower_wire.mlua ──► MLBT bytes
                                                                         │
                                                                         ▼
                                                                  mom_backend_compile_binary() ──►
                                                                      │                          │
                                                                      ▼                          ▼
                                                                ffi.parse_back_command_binary()   same as above
                                                                      │
                                                                      ▼
                                                              Rust BackCmd pipeline
```

Both paths converge at `ffi.parse_back_command_binary()` → same Rust decoder → same compiler.

### MOM's current limited command coverage

`lower_wire.mlua` `mom_schema_cmd_tag_to_wire` only maps 14 commands:
`CmdTargetModel(1)`, `CmdCreateSig(3)`, `CmdDeclareFunc(10)`, `CmdBeginFunc(12)`, `CmdCreateBlock(13)`, `CmdSwitchToBlock(14)`, `CmdSealBlock(15)`, `CmdBindEntryParams(16)`, `CmdConst(21)`, `CmdIntBinary(34)`, `CmdReturnVoid(57)`, `CmdReturnValue(58)`, `CmdFinishFunc(60)`, `CmdFinalizeModule(61)`

Missing are ~47 commands — all memory ops, atomics, vector ops, shifts, rotates, casts, compares, calls, jumps, brif, switch, etc.

### MOM's column-major command writer

`lower_wire.mlua` `mom_write_cmd_columns_to_wire` reads from 7 column arrays (tag, wa-wf) instead of a flat `CmdEntry` tape. It calls `mom_schema_cmd_tag_to_wire` per command. Only w0-w5 (6 slot columns) — commands with more than 6 slots are not supported.

---

## Observations

### 1. Triplicated/quadruplicated tag definitions
The 61 command tags, 13 scalar tags, and ~16 op tag tables are maintained in 3-5 separate locations with no automated cross-check. A tag added to `LalinBack.mlua` schema requires manual updates to:
- `BACK_WIRE_FORMAT.md` (text table)
- `back_command_binary.lua` (`CMD_TAG` table)
- `lower_wire.mlua` (`mom_schema_cmd_tag_to_wire` + `mom_wire_slot_count`)
- `src/ffi.rs` (`SLOT_COUNT` array + decode_commands match arms)
- `port_map.lua` (documentation)
- Back tags test expectations

### 2. Schema-tag vs wire-tag divergence
`back_tags.lua` derives tags from ASDL union variant index (`tag = i - 1`, with self-variant at index 0 unused). The wire format uses a **separate numbering** (1-61) that happens to start at 1 but is not automatically derived from schema variant order. They only match by convention/coincidence.

### 3. Inconsistent MOM encoder coverage
- `mom_schema_cmd_tag_to_wire` maps only 14/61 commands — MOM's native backend can only emit a small subset.
- `mom_wire_slot_count` covers all 61 (uses wire tags) — but the main mapping table doesn't.
- Commands with >7 slots (LoadInfo=15, AtomicCas=17, etc.) have no `mw_write_cmdN` helper.

### 4. Code duplication in wire.mlua vs lower_wire.mlua
`lower_wire.mlua` redefines `mw_init`, `mw_finish`, `mw_write_pool_string`, `mw_write_aux_i32s`, `mw_align4`, and byte-level primitives — duplicating `wire.mlua`.

### 5. Rust BackCmd expansion
The Rust `BackCmd` enum (~100+ variants) is **not** a 1:1 mapping of schema commands (61). The wire format preserves the schema's structure (CmdIntBinary with an op slot), but the Rust enum expands each op into a dedicated variant (Iadd, Isub, Imul, Sdiv, etc.). The binary decoder's decode_commands does this expansion inside each tag's match block.

### 6. No automatic slot count derivation
Slot counts (e.g., CmdLoadInfo = 15 slots) must be derived manually from the schema and kept in sync. The schema itself doesn't declare slot counts — they're implicit in the variant's field count + sub-encoding complexity (e.g., BackMemoryInfo expands to 8 slots).

### 7. LoadInfo/StoreInfo encode shape + scalar/lanes redundantly
CmdLoadInfo stores: `[dst, shape_tag(0/1), scalar, lanes, base_tag, base_id, byte_offset, mem*8]` = 15 slots. The scalar and lanes duplicate info that's derivable from shape_tag — but shape_tag==0 means scalar with scalar_tag, shape_tag==1 means vec with (scalar_tag, lanes). The decoder has custom logic for this dual interpretation.

### 8. `schemas/wire_tags` could be the single source
`LalinBack.mlua`'s `Cmd` union has `protocol_variants` listing all variants in order. If wire tags were derived from this order (like `back_tags.lua` already does for schema tags), and slot counts were derived from field counts (with a lookup for multi-field encodings like BackMemoryInfo), all duplication could be eliminated. The main blocker is: slot count is not the same as ASDL field count (e.g., BackMemoryInfo with 1 ASDL field expands to 8 wire slots).

## Knowledge-builder Output — 2026-05-18 14:25:22

Here is my analysis.

---

## What Matters Most for This Problem

Five dimensions are relevant here:

1. **Bijection faithfulness** — the wire format must be a lossless, deterministic encoding of BackProgram semantics. The most dangerous failures are silent ones where encoding produces bytes that decode to a **different** program.

2. **Slot desynchronization risk** — the wire format has no per-command length prefix. The decoder reads N slots based on slot-count-per-tag. A single slot count mismatch between encoder and decoder shifts all subsequent commands — catastrophic, undetectable corruption until pool/aux index bounds fail (and potentially not even then).

3. **Maintenance surface area** — how many independent human-maintained artifacts must change when a new command variant is added. Currently 5+.

4. **MOM's growth trajectory** — MOM currently emits 14/61 commands. As MOM matures and needs more commands, the cost of duplication grows superlinearly because each new command requires coordinated updates across unrelated files.

5. **ASDL schema authority** — whether the ASDL schema can be made authoritative for all tag/slot/layout information, or whether the wire format has intrinsic concerns (version stability, lossy encoding choices) that resist derivation.

---

## Non-Obvious Observations

### 1. The wire format is a lossy encoding of the ASDL schema — and this is structural, not incidental

The ASDL `CmdPtrOffset` has 7 fields: `dst`, `base`, `index`, `elem_size`, `const_offset`, `provenance`, `bounds`. The wire format encodes only 5 of these — **provenance and bounds are silently dropped** (neither the Lua encoder nor the MOM encoder writes them, and the Rust decoder doesn't reconstruct them). The schema says these fields exist; the wire format acts as if they don't.

Similarly, `BackAddress` in the schema has `provenance: BackPointerProvenance` and `formation_bounds: BackPointerBounds`. The wire format encodes only `base` and `byte_offset` — provenance and bounds are lost.

This means: **any approach that derives wire layout from the ASDL schema must know not just how many fields each type has, but which fields are intentionally excluded from serialization.** This is a schema-level annotation problem, not a counting problem. The slot count derivation cannot be purely structural — it requires encoding policy metadata attached to each field (or type).

### 2. The relationship between 61 schema commands and 100+ Rust variants is NOT a simple "expansion" — it's a fundamental representation mismatch with three distinct patterns

**Pattern A — Op explosion (predictable, mechanical):** Schema's `CmdCompare` (1 variant with `op: BackCompareOp` sub-union) produces 16 Rust variants (`IcmpEq` through `FCmpGe`). This is a straightforward 1:N expansion where N = number of sub-union variants. The sub-tag numbering is stable and documented in encoder tag tables + decoder match arms. This could be derived from the schema mechanically if the schema exposed sub-union variant lists.

**Pattern B — Field-split explosion (conditional, not mechanical):** Schema's `CmdAppendBlockParam` has `ty: BackShape`. The wire format encodes shape as 3 slots (shape_tag, scalar, lanes). The Rust decoder checks shape_tag and produces either `AppendBlockParam(... BackScalar)` or `AppendVecBlockParam(... BackVec)`. The same wire tag produces **different Rust variant names** depending on runtime slot values. This is NOT a simple expansion — the schema doesn't say "this field splits into two variant names."

**Pattern C — Synthetic command injection (side-effecting, hidden):** The decoder's `decode_address()` method, when processing `CmdLoadInfo` (tag 27), emits multiple Rust `BackCmd` values: first `StackAddr`/`DataAddr` (via `decode_address_base`), then `PtrAdd` (via `decode_address`), then `LoadInfo`. One wire command → 3 Rust commands. The synthetic commands have name-mangled `BackValId`s like `__binary:load:dst:base`. This creates synthetic identifiers that do not exist in the encoder's output or the ASDL schema — they exist only in the decoder's expanded representation.

**Implication:** An automatic code generator from ASDL schema → Rust decoder would need to handle all three patterns explicitly. Pattern A is derivable. Pattern B requires annotation saying "this shape field conditionally selects variant." Pattern C requires annotation saying "this schema command emits N subsidiary commands." Simple schema-to-decoder generation is not possible without a second annotation layer.

### 3. The schema-tag/wire-tag "divergence" is not a deliberate abstraction — it's two independent implementations of the *same derivation function* that happen to produce the same result by accident

The `back_tags.lua` derivation is: `tag = variant_index - 1` (skipping self-variant at index 0). The wire tag assignment is: declared in BACK_WIRE_FORMAT.md as "Tags are assigned in declaration order from the LalinBack.Cmd ASDL union." These are **structurally identical** — both compute `variant_index_in_protocol_variants - 1`.

They currently match because:
1. The Cmd variants are listed in the ASDL schema in declaration order
2. The `protocol_variants` method returns them in that order
3. The wire tag table happens to list them in that order

If someone reorders the Cmd variants in LalinBack.mlua, `back_tags.lua` auto-updates but the encoder's `CMD_TAG` table breaks **silently** — it still has entries for old names but with wrong numeric values. The Rust decoder's `SLOT_COUNT` also breaks silently. The `mom_schema_cmd_tag_to_wire` function breaks silently (maps go to wrong tags).

The only thing preventing this is manual discipline — there is no automated cross-check.

**But the real insight is:** the schema-tag and wire-tag systems serve different stability requirements. Schema tags can change during development (refactoring variant order, inserting new variants). Wire tags MUST NOT change once the format is versioned. They are currently conflated because the wire tags happen to be derived from the same ordering. A genuine abstraction layer would have the wire tags be an **independent numbering** with a defined migration policy, not a clone of schema ordering.

### 4. The slot count derivation problem is harder than it looks — there are FIVE encoding multipliers, not one

The scout correctly identifies BackMemoryInfo (1 ASDL field → 8 wire slots) as a complication. But the complete picture has more multipliers:

| ASDL Type | Wire Slots | Multiplier | Notes |
|-----------|-----------|------------|-------|
| `i32`, `bool`, `ptr(u8)`, `BackValId`, `BackFuncId`, etc. | 1 | 1x | Direct pool index or value |
| `BackScalar` | 1 | 1x | Scalar code |
| `BackShape` | 3 | 3x | shape_tag + scalar_code + lanes |
| `BackLiteral` | 3 | 3x | lit_tag + lo + hi |
| `view(T)` | 2 | 2x | aux_idx + count |
| `BackAddressBase` | 2 | 2x | base_tag + id_pool_idx |
| `BackAddress` | 5 | 5x (but see below) | base_tag + base_id + byte_offset [BUT provenance and bounds are dropped] |
| `BackMemoryInfo` | 8 | 8x | access_id + 7 sub-fields |
| `BackCallResult` | 3 | 3x | result_tag + dst_pool [+ scalar] |
| `BackCallTarget` | 2 | 2x | target_tag + id_pool |

But worse: **some commands have mixed encodings that don't correspond to any single ASDL type.** For example, the wire format inserts a `0` padding slot at the end of `CmdAtomicLoad` and `CmdAtomicCas` — it's not a field, not a type, it's just a reserved slot for alignment. The Rust decoder reads and ignores it. The encoder writes it as a literal `0`. There is no ASDL representation of this reserved slot.

**The deepest problem:** deriving slot counts from the schema requires not just mapping ASDL types to wire multipliers, but also knowing which schema fields to exclude (provenance, bounds) and which wire slots to insert (reserved zeros) that have no schema counterpart. This is a **lossy+additive encoding**, not a pure compression of the schema.

### 5. The CmdPtrOffset encoding has an asymmetry that reveals a deeper pattern — schema fields can be dropped unsafely

The encoder's `CmdPtrOffset` handler writes 7 slots: dst, base_tag, base_id, index_pool, elem_size, const_offset_lo, const_offset_hi. The **provenance and bounds fields are not written**. The ASDL schema says `CmdPtrOffset(dst, base, index, elem_size, const_offset, provenance, bounds)` — 7 fields. But the encoder drops 2.

The decoder reads 7 slots (slot count = 7 per SLOT_COUNT[26]) and reconstructs a `BackCmd::PtrOffset(dst, base, index, elem_size, const_offset)` with 5 parameters. **Provenance and bounds are lost forever.**

This is not an encoding optimization — it's an information loss. If any Rust analysis pass needs `provenance` or `bounds` on a `PtrOffset`, it will get default/missing data from the decoded binary path. The hosted Lua pipeline (which keeps BackProgram in ASDL) preserves these fields. The binary pipeline discards them. This creates **behavioral divergence between the two compilation paths** that is invisible until a pass inspects provenance information.

### 6. The MOM encoder and the Lua encoder assign pool indices differently — and this creates a subtle roundtrip hazard

The Lua encoder's `WireBuilder:pool()` assigns indices sequentially (first seen string = index 0). The MOM encoder's `mom_wire_value_pool` uses `value_id + 2`. These are different strategies, but both produce self-consistent buffers that the Rust decoder can read.

The hazard: if someone writes a tool that compares pool indices across the two encoders (e.g., for debugging or cross-validation), the indices don't match even for identical programs. But more importantly: **there is no single authoritative pool index assignment scheme** — each encoder has its own convention, and the Rust decoder doesn't validate pool index values, only their resolved strings. This means the binary format is only "weakly self-consistent" — pool indices are meaningful only within a single wire buffer, not across buffers.

### 7. The synthetic command naming convention (`__binary:`) is an implicit namespace with no collision detection

When the Rust decoder processes `CmdLoadInfo`, it creates `BackValId` values like `__binary:load:dst:base` and `__binary:load:dst:addr`. These are synthetic identifiers that don't exist in the original program. If a real program happens to contain a value named `__binary:load:x:base`, the decoder would create a name collision.

Currently this is safe because:
- The `__binary:` prefix is unlikely in real source code
- But there is NO enforcement mechanism — no validation, no collision check

This namespace convention is undocumented outside the decoder source code. Any new synthetic command injection (e.g., if a future decoder creates synthetic commands with different prefixes) must remember to avoid collisions with both existing synthetic prefixes and real identifiers.

### 8. The op sub-tag systems are a "second schema" entirely outside the ASDL model

The ASDL schema defines `BackUnaryOp`, `BackCompareOp`, `BackCastOp`, etc. as unions. The wire format assigns numeric sub-tags to each union variant: `BackUnaryIneg = 1`, `BackIcmpEq = 1`, `BackBitcast = 1`, etc.

These sub-tag assignments are:
- **Duplicate 1-3 times** (Lua encoder tag tables, Rust decoder match arms, docs)
- **Never validated against the schema** — if someone adds `BackUnaryFabs` to the `BackUnaryOp` union in the schema, there's nothing ensuring a sub-tag gets assigned before the encoder crashes
- **Inconsistently numbered** — each op union starts at 1, but there's no cross-union coordination. The sub-tag space is per-command, so 1 means different things in different contexts

The sub-tags are effectively a second tag system layered on top of the command tags. They have the same duplication problems as command tags, but with more locations (because each op union's sub-tags appear in at least 3 places).

### 9. The SLOT_COUNT array in Rust has a fixed size of 64 — this encodes an implicit invariant about maximum tag value

`static SLOT_COUNT: LazyLock<[usize; 64]>` — the 64-element array encodes "tag values 0-63, with 1-61 valid." This means:
- Adding a new command with tag > 63 requires changing the array size (loud failure — Rust won't compile)
- Tags 62, 63 are currently unused but reserved
- The `if tag == 0 || tag as usize >= SLOT_COUNT.len()` check will catch out-of-bounds tags at runtime

But the **implicit invariant** is: max wire tag = array length - 1. Currently that's 63, with actual max at 61. Any new command added to the ASDL schema gets a tag of (current max + 1) by convention, but if 2 new commands are added, the max becomes 63, hitting the array boundary.

### 10. The validation checklist (Appendix B of BACK_WIRE_FORMAT.md) is the only guard against corruption — and it's manually maintained

The 11 validation checks (pool index bounds, aux index bounds, scalar/op tag ranges, shape_tag validity, command stream bounds) are currently implemented **ad-hoc** in:
- The Lua encoder's `assert()` calls (e.g., `assert(SCALAR_TAG[s.kind])`)
- The Rust decoder's `if/return Err` checks
- The spec doc's checklist

If a new scalar type is added, 3+ locations must be updated: the `SCALAR_TAG` table, the `read_scalar_code()` function, the spec. If a new validation check is needed (e.g., "pool strings must be valid UTF-8"), it must be implemented independently in the encoder (assertion) and decoder (error check).

More critically: **the encoder has far fewer validation checks than the decoder.** The Lua encoder uses Lua assertions for op tags and scalar tags, but doesn't validate pool index bounds or aux data sizes. The Rust decoder validates all of these. This asymmetry means invalid wire buffers can be produced by an encoder bug but only caught at decode time. There's no "writer-side validation" equivalent to the decoder's checks.

---

## Knowledge Gaps

1. **Provenance propagation path:** I need to understand whether the schema-level provenance/bounds fields (`BackPointerProvenance`, `BackPointerBounds`) are used anywhere significant in the Rust backend's optimization passes. If they are, then the binary encoding's loss of these fields creates a semantic gap. If they aren't, the loss is benign. A scout should check `src/lib.rs` for provenance/bounds usage in analysis/optimization passes.

2. **DataInitWire variant expansion:** The schema has a single `CmdDataInit` variant. The wire format carries `lit_tag` as a sub-tag. The Rust decoder produces FIVE different BackCmd variants from this one wire tag: `DataInitZero`, `DataInitBool`, `DataInitInt`, `DataInitFloat`. And `DataInitZero` has TWO paths — one from `lit_tag == 0` in `CmdDataInit`, and another from `CmdDataInitZero` (tag 5) directly. This is Pattern B (field-split) at its most complex. I'd like to verify there's no actual double-handling.

3. **MOM's view plan encoder path:** The MOM encoder currently only handles 14 commands. As MOM expands, it will need to handle memory ops, atomics, calls, etc. The `mom_write_cmd_columns_to_wire` function reads from 7 column arrays (tags w0-w6). Some commands have more than 7 slots (LoadInfo=15, StoreInfo=15, etc.). The column-major approach may not scale to high-slot-count commands without redesigning the MOM-side encoding architecture.

## Approach-proposer Output — 2026-05-18 14:32:27

Now I have a complete picture. Let me synthesize three genuinely distinct approaches.

---

## Approach A: Schema-Annotated Wire Layout (Keep the Schema as Center)

**Core idea**: The existing `LalinBack.mlua` ASDL schema remains the single source of truth. A companion encoding annotation file (`wire_layout.lua`) declares the lossy+additive wire encoding policy per type and per variant — which fields to drop, which to multiply, where to insert padding — and a Lua codegen script reads both to produce the Lua encoder, MOM encoder helpers, Rust decoder, SLOT_COUNT array, and spec doc.

**Key changes**:

| What | What happens |
|------|-------------|
| `LalinBack.mlua` | Unchanged — still defines 61 Cmd variants, sub-op unions, `BackShape`, `BackMemoryInfo`, etc. |
| New: `wire_layout.lua` | Companion file declaring encoding policy: per-ASDL-type slot multiplier (e.g., `BackMemoryInfo → 8`, `BackShape → 3`, `BackLiteral → 3`), excluded fields (`BackAddress.provenance`, `BackAddress.formation_bounds`), per-command padding slots (`CmdAtomicLoad → [+0 after ordering]`), op sub-tag assignments for each op union |
| New: `back_codegen.lua` | Lua codegen that reads `LalinBack.mlua` + `wire_layout.lua`, and emits: `back_command_binary.lua` (encoder), `mom/driver/encoder.mlua` (MOM encoder), `src/decoder_generated.rs` (Rust decode match arms + SLOT_COUNT), `BACK_WIRE_FORMAT.md` (updated live) |
| `back_command_binary.lua` | Becomes **entirely generated** — hand-written CMD_TAG, SCALAR_TAG, and if-else chain replaced by generated output |
| `mom/driver/lower_wire.mlua` | Replaced by generated `mom/driver/encoder.mlua` — `mom_wire_slot_count`, `mom_schema_cmd_tag_to_wire`, and per-command encode logic all derived |
| `src/ffi.rs` | `SLOT_COUNT` array removed, `decode_commands` match arms replaced by `include!("decoder_generated.rs")` or a call into generated decode dispatcher |
| `BACK_WIRE_FORMAT.md` | Generated from annotations — single source of truth for documentation |
| Rust `BackCmd` enum | **Stays hand-written** in `src/lib.rs` — it is the target, not derived. The generated decoder maps wire tags to these variants. |
| Expansion patterns | Pattern A (op explosion): regex/replace generation — e.g., for each `BackIntOp` variant, emit a decode arm `isub`→`BackCmd::Isub(...)`. Pattern B (field-split): explicit in `wire_layout.lua` — `CmdAppendBlockParam` has annotation `{ shape_split: [AppendBlockParam, AppendVecBlockParam] }`. Pattern C (synthetic injection): still hand-coded in the generated decoder via emitted Rust helper functions `decode_address()` |

**Tradeoff**: Optimizes for **architectural clarity** — the schema remains the center of the system, encoding policy is explicit and declarative, no duplication. Sacrifices **codegen complexity** — `wire_layout.lua` must describe a lossy+additive encoding policy that includes excluded fields, multi-field encodings, and padding. The annotation language for this is non-trivial.

**Risk**: The encoding annotation file becomes complex enough that it replaces duplication with a different kind of complexity. If 8 of the 61 commands have unique encoding quirks (padding, dropped fields, shape-split), and every new command needs encoding annotations, the annotation burden may be higher than the current manual approach. Also: the codegen must emit correct Rust, which is sensitive to Rust syntax changes (the generated decoder must compile without errors).

**Rough sketch**:
1. Design `wire_layout.lua` — a Lua table keyed by ASDL type name, declaring slot multipliers and field exclusions. Keyed by Cmd variant name, declaring padding offsets and split annotations.
2. Write `back_codegen.lua` — reads ASDL schema via PVM (`protocol_variants`), reads `wire_layout.lua`, emits four output files.
3. Replace `back_command_binary.lua` — delete hand-written tag tables, keep `WireBuilder` serialization helpers but generate `Encoder:encode_cmd()`.
4. Replace `mom/driver/lower_wire.mlua` — generate MOM encoder from same pipeline.
5. Replace Rust `decode_commands()` — generate per-tag match arms, keep `BinaryReader` helpers (`pool_val`, `decode_address`, etc.) as hand-written library.
6. Generate `BACK_WIRE_FORMAT.md` slot count and op tag tables.
7. Add build step (`make codegen` or invoke inside `build.rs` before tests).

---

## Approach B: Rust-DSL Wire Declaration — Encode from Rust, Generate Lua

**Core idea**: Move the authoritative wire format declaration to Rust. A proc-macro or build.rs DSL declares each command's wire layout (tag, slot types, expansion rules) and generates both the Rust decoder and the Lua/MOM encoder. The ASDL schema becomes only a semantic reference, not an encoding source.

**Key changes**:

| What | What happens |
|------|-------------|
| New: `wire_decl.rs` | Single Rust file declaring each command's wire format using a custom derive macro or macro_rules. Example: `wire_cmd!(CmdCreateSig, tag=3, slots=[sig: SigId, params: Aux(Scalars), results: Aux(Scalars)])`. For command bodies: `wire_cmd!(CmdLoadInfo, tag=27, expand=Address+Memory, slots=[dst: ValId, shape: Shape, addr: AddressLayout, mem: MemoryLayout])`. |
| `src/lib.rs` `BackCmd` enum | **Generated** from the wire declaration. No more hand-written 100+ variants. The macro expands each wire command into the appropriate Rust variant(s), including op-split expansions. |
| `src/ffi.rs` decoder | Generated match arms + `SLOT_COUNT`. The `BinaryReader` helpers (`pool_val`, `decode_address`, `decode_memory`) are hand-written but called from generated dispatch. |
| `build.rs` | New step: reads `wire_decl.rs` macro expansions and emits `lua/lalin/back_command_binary_gen.lua` (Lua encoder) and `lua/lalin/mom/driver/encoder_gen.lua` (MOM encoder). These are emitted at Rust compile time. |
| `back_command_binary.lua` | Replaced by generated file. Hand-written `CMD_TAG`, `SCALAR_TAG`, and encoder dispatch gone. |
| `mom/driver/lower_wire.mlua` | Replaced by generated MOM encoder. MOM gets native code that matches Rust's declaration exactly. |
| `BACK_WIRE_FORMAT.md` | Generated from the macro expansion (build.rs emits markdown). |
| `wire_layout.lua` (companion) | Not needed — all encoding policy is in the Rust macro. |
| ASDL schema | Still used for semantic passes (typechecking, lowering) but no longer drives wire encoding. |

**Expansion patterns under this approach**:
- Pattern A (op explosion): The macro accepts an `op_dispatch = BackIntOp` attribute. It auto-generates N Rust variants (one per sub-op) and maps wire (tag, sub_tag) to the right variant. The sub-tag assignments are derived from the sub-union variant_order.
- Pattern B (field-split): The macro accepts `shape_split = [AppendBlockParam, AppendVecBlockParam]` — when a shape field has tag=0 (scalar) it decodes to the first variant, tag=1 (vec) to the second.
- Pattern C (synthetic injection): The macro accepts `expand = Address+Memory` and generates calls to helper functions that inject subsidiary commands.

**Tradeoff**: Optimizes for **Rust-side correctness** — the decoder is always in sync with the declaration, and the Rust BackCmd enum is derived from the same source. Sacrifices **Lua philosophical fit** — the wire format is now defined and owned by Rust, and Lua/MOM get a generated encoder they cannot easily override or inspect. Build.rs emitting Lua code adds a build dependency (Rust must know how to emit Lua/Lalin, not just Rust).

**Risk**: Rust macros calling into build.rs to emit arbitrary Lua is fragile. If the Lua encoder needs a fix, the fix goes through the Rust macro system, not through Lua. For MOM, the generated encoder may not match MOM's allocation-free column-major model — MOM may need to re-architect its encoder to match the generated format. Also: the Rust BackCmd enum is currently a triple-layer hierarchy (flat enum → `BackBodyCmd` wrapping sub-enums → `BackProgram::partition()`). Generating this from macros requires the macro to understand the partition boundaries (which commands are decls vs body).

**Rough sketch**:
1. Design the macro DSL. `wire_cmd!(CmdCreateSig, tag=3, slots=[...])` must handle direct u32, pool indices (with typed pool lookups), aux references (with count), shapes (3 slots expanded), literals (3 slots expanded), memory info (8 slots expanded), addresses (3+ slots expanded with sub-command injection).
2. Implement Rust proc-macro `#[derive(WireCmd)]` or `wire_decl!` macro that:
   a. Declares the `BackCmd` enum variants as Rust types
   b. Generates `fn decode_from_wire(slots: &[u32], reader: &BinaryReader) -> BackCmd`
   c. Generates `fn slot_count(tag: usize) -> usize`
   d. Generates `fn encode_to_wire(cmd: &BackCmd, builder: &mut WireBuilder)` in both Rust (for roundtrip tests) and Lua (for encoder emission)
3. In `build.rs`, read the expanded macro output and emit:
   - `lua/lalin/back_command_binary_gen.lua` (Lua encoder)
   - `lua/lalin/mom/driver/encoder_gen.lua` (MOM encoder)
   - `BACK_WIRE_FORMAT_GEN.md` (spec doc)
4. Delete `back_command_binary.lua` and `lower_wire.mlua`. Wire tests to the generated versions.
5. The Rust decoder calls generated dispatch.

---

## Approach C: Self-Describing Wire Format — Length-Prefixed Commands, No Shared Table

**Core idea**: Change the wire format fundamentally — each command carries its own slot count as a length prefix, making slot count derivation a per-command encoding concern rather than a shared table. This eliminates the catastrophic desync failure mode. The schema stays as the single source of truth for command existence, but each encoder writes `(tag, n_slots, slot...)` inline. The decoder reads length-generically before dispatching.

**Key changes**:

| What | What happens |
|------|-------------|
| Wire format v4 | Every command becomes `[tag: u32] [n_slots: u32] [slot_0: u32] ... [slot_{n-1}: u32]`. The header still has magic + version + pool_count + aux_count. The command stream no longer needs a shared SLOT_COUNT table. |
| `LalinBack.mlua` | Unchanged — still defines all Cmd variants. Tag assignment is automatic from variant order (same as today). |
| New: `layout_spec.lua` | Compact declaration per variant of its wire layout — purely descriptive, no code. Example: `CmdLoadInfo: { dst: pid, shape: shape3, addr: addr3, mem: mem8 }` — this plus the schema defines exactly what goes on the wire. |
| `WireBuilder:cmd()` | Changed to accept `(tag, slots)` and auto-insert `n_slots` before the slots. The `Encoder:encode_cmd()` methods stay mostly the same — they just get `n_slots` for free (Lua table length). |
| `SLOT_COUNT` array | **Deleted entirely** — the decoder reads `n_slots` from the stream. |
| `decode_commands()` | Simplified: read `tag`, read `n_slots`, read `n_slots * u32`, then dispatch to per-variant decode logic. The buffer bounds check is now `self.pos + 8 + 4*n_slots > buf.len()` instead of depending on a table. |
| `mom_wire_slot_count` | Deleted — MOM just writes `len(slots)` before the slots. |
| MOM `mom_write_cmd_columns_to_wire` | Gets `n_slots` from the column array's count or from a separate `column_count` parameter. |
| Rust `BackCmd` enum | **Stays hand-written** — same as today. |
| Expansion patterns | Same as today — Pattern A/B/C happen inside the per-variant decode match arms. But now the decoder reads slots generically (as `slots: &[u32]`) before dispatching, making the per-variant code slightly cleaner. |

**Critical design detail**: The `n_slots` field is purely structural — it says "how many u32 follow for this command." It doesn't encode semantic slot types. The decoder still must know the semantic meaning of each slot position. But if encoder and decoder disagree on slot structure, the error is now **local** to one command — subsequent commands remain parsable because `n_slots` tells the decoder where the next command starts.

**Tradeoff**: Optimizes for **robustness and simplicity** — eliminates the most dangerous class of desync bugs (undetected slot count mismatch shifting all subsequent commands). The per-command overhead is 1 u32 (4 bytes), negligible for programs with hundreds of commands. Sacrifices **space efficiency** and **fixed-size assumptions** — any code that currently indexes into the command stream by absolute offset (e.g., seeking to command N directly) can no longer do so without parsing each command.

**Risk**: The length prefix is written by the encoder, so if the encoder writes the wrong length, the decoder will still misparse — but the error is now caught earlier (inside the same command's slot bounds) rather than causing a shift. Tools that currently assume fixed-slot-per-tag (e.g., test validators that check "tag 21 has 5 slots") need updating. MOM's column-major writer needs to know the number of columns per command before writing — this requires the same layout knowledge as before, just expressed as `n_slots` rather than a lookup function.

**Rough sketch**:
1. Change wire format header to bump version to 4 (or keep 3 but change stream format — the `BACK_WIRE_FORMAT.md` update covers this).
2. Update `WireBuilder:cmd(tag, slots)` to emit `tag + len(slots) + slots[...]` instead of just `tag + slots[...]`.
3. Update `WireBuilder:tostring()` accordingly — the command stream now has interleaved lengths.
4. In Rust `BinaryReader::decode_commands()`, replace the `SLOT_COUNT[tag]` lookup with `let n_slots = self.take_u32("slot count")?` before reading slots. Buffer bounds check becomes `8 + 4*n_slots`.
5. Delete `SLOT_COUNT` static array and `mom_wire_slot_count` function.
6. Update MOM `mom_write_cmd_columns_to_wire` to write `n_slots` as a separate u32 before the slots. This is a 1-line change.
7. Update `BACK_WIRE_FORMAT.md` to describe the new stream format and remove Appendix A (slot count table). The tag table §7 becomes purely definitional.
8. No changes to ASDL schema, Rust BackCmd enum, or decoder expansion logic — they all stay as-is.

---

## Comparison

| Dimension | A: Schema-Annotated | B: Rust-DSL | C: Self-Describing |
|-----------|-------------------|-------------|-------------------|
| **Center of truth** | LalinBack.mlua + wire_layout.lua | Rust macro DSL (wire_decl.rs) | LalinBack.mlua (for semantics) + length prefix (for structure) |
| **Duplicate state eliminated** | CMD_TAG, SCALAR_TAG, slot counts, op tables, MOM encode logic, decoder match arms, spec doc | Same, plus generates BackCmd enum | SLOT_COUNT table (the most dangerous duplication) |
| **Rust BackCmd enum** | Hand-written (preserved) | Generated from macro | Hand-written (preserved) |
| **Build step required** | Yes — Lua codegen | Yes — build.rs emits Lua code | No — just change wire format |
| **MOM integration** | Natural — MOM reads Lua annotations | Awkward — MOM gets generated code | Natural — MOM just writes len |
| **Format change** | Same MLBT v3 slots | Same MLBT v3 slots | New v4 (length-prefixed) |
| **Catastrophic desync risk** | Still present (shared slot table) | Still present (shared slot table) | **Eliminated** (local lengths) |
| **Codegen complexity** | High — must express lossy+additive encoding policy | Very high — must express 3 expansion patterns + emit Lua | None — just add length before slots |
| **Best for** | Teams that want ASDL as architecture and are willing to invest in annotation DSL | Teams that want Rust to own the wire boundary and can tolerate generated Lua | Teams that want maximum robustness and minimal tooling investment |

**Pick A if**: You want the Lalin philosophy of "ASDL is the architecture" to extend to the wire format, and you're willing to design a clean encoding annotation DSL that handles the 3 expansion patterns, dropped fields, and padding slots. This is the philosophically purest choice.

**Pick B if**: You want the Rust backend to own and guarantee the wire format, and you're willing to accept that Lua encoders become generated artifacts. This works well if Rust is the primary target receiving the wire format and you want to eliminate the "schema variant reorder breaks everything silently" problem entirely.

**Pick C if**: You want the most robust solution with the least architectural overhead. The length prefix eliminates the worst failure mode (undetected slot count desync) without requiring any codegen, annotation DSLs, or build steps. The four bytes per command overhead is negligible. The tradeoff is philosophical purity for practical robustness — but sometimes a 4-byte length prefix is better than a 5-location duplication that requires a DSL to resolve.
