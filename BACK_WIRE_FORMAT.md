# BackProgram Wire Format

The binary encoding for Moonlift `BackProgram` data crossing the Lua↔Rust
boundary. Replaces the text-based `moonlift-back-command-tape-v2` format.
Serves as the single ABI for both the current Lua compiler and MOM (the native
Moonlift-on-Moonlift compiler).

## 1. Motivation

The text tape pays three costs:

1. **Encoder complexity** (Lua, 141 lines): string escaping, `kind`-dispatched
   formatting, `tostring()` everywhere, tab-concatenation of heterogeneous
   fields.
2. **Decoder complexity** (Rust, 661 lines): line splitting, `String`
   allocation per field, `match` on string op names (`"BackIntAdd"`),
   `HashMap<String, _>` lookups for every ID.
3. **Redundancy**: the same identifier string (`"sig:add_i32"`, `"entry"`,
   `"v3"`) is copied into the tape every time it appears — often 3–10 times
   per program. The Rust side allocates and hashes each copy independently.

The binary format eliminates all three:

- **No string escaping or field splitting**: fields are fixed-position `u32`
  slots after a `u32` tag.
- **No stringly dispatch**: ops, scalars, semantics are numeric tags consumed
  by `match` on integers.
- **No redundant string copies**: identifiers are interned once into a string
  pool and referenced by `u32` index.
- **No per-command HashMap lookup**: pool index → `Vec[idx]` is O(1) with zero
  hashing.

## 2. Format overview

A BackProgram wire buffer has four contiguous sections, all `u32`-aligned and
little-endian:

```
┌──────────────────────────────────────────────────┐
│  Header         (4 × u32 = 16 bytes)             │
├──────────────────────────────────────────────────┤
│  String Pool    (n_strings entries)               │
├──────────────────────────────────────────────────┤
│  Auxiliary Data  (n_aux entries)                  │
├──────────────────────────────────────────────────┤
│  Command Stream  (n_cmds commands)                │
└──────────────────────────────────────────────────┘
```

Every multi-byte value is stored **little-endian**. The entire buffer is passed
as `(ptr: *const u8, len: usize)` across the C FFI boundary.

## 3. Header

| Offset | Type | Field      | Value                                   |
|--------|------|------------|-----------------------------------------|
| 0      | u32  | `magic`    | `0x4D4C4254` (`"MLBT"` in LE)           |
| 4      | u32  | `version`  | `3`                                     |
| 8      | u32  | `n_strings`| Number of string pool entries            |
| 12     | u32  | `n_aux`    | Number of auxiliary data entries         |

`n_cmds` is not in the header; it is implicit in the command stream which runs
to the end of the buffer. (This avoids a forward reference: the Lua encoder
does not need to know the command count before starting to write commands.)

## 4. String pool

All identifiers (`BackSigId`, `BackFuncId`, `BackValId`, `BackBlockId`,
`BackDataId`, `BackStackSlotId`, `BackAccessId`, `BackExternId`, extern
symbol names) are stored once in the string pool. Commands reference them by
**pool index** — a `u32` offset into the pool (0-based).

### Pool entry layout

Each entry is:

| Field  | Type | Description                             |
|--------|------|-----------------------------------------|
| `len`  | u32  | Byte length of the string (no null terminator) |
| `data` | u8[] | UTF-8 bytes                              |
| `pad`  | u8[] | 0–3 zero bytes to reach u32 alignment   |

Pool indices are assigned in first-seen order during encoding. The Lua encoder
maintains a `{ [string] → u32 }` dedup table; MOM does the same with its
interned name ids.

### Example

Strings `["add_i32", "sig:0", "entry", "a", "b", "r"]` become:

```
len=7  "add_i32" pad=1    → pool index 0
len=5  "sig:0"  pad=3    → pool index 1
len=5  "entry"  pad=3    → pool index 2
len=1  "a"      pad=3    → pool index 3
len=1  "b"      pad=3    → pool index 4
len=1  "r"      pad=3    → pool index 5
```

### Rust-side handling

The Rust decoder reads the pool into a `Vec<String>` once. When decoding a
command slot that is a pool index `i`, it constructs the typed ID
(e.g. `BackValId(pool[i].clone())`) — each string allocated exactly once per
pool entry. The existing `HashMap<String, _>` compiler state works unchanged.

Future optimization: the Rust `Compiler` can switch from `HashMap<String, V>`
to `Vec<V>` indexed by pool index, eliminating all hashing. This is a
transparent refactor on the Rust side with no format change.

## 5. Auxiliary data

Variable-length data (value ID lists, scalar lists, switch cases) does not fit
in fixed-width command slots. It lives in the auxiliary data section. Commands
reference aux entries by **aux index** — a `u32` offset into the aux section
(0-based) — paired with an inline **count** slot.

### Aux entry layout

Each entry is:

| Field   | Type   | Description                               |
|---------|--------|-------------------------------------------|
| `count` | u32    | Number of `u32` data words that follow    |
| `data`  | u32[]  | `count` data words                        |

Aux entries are written sequentially; there is no padding between them. An aux
entry's size in bytes is `4 + 4 * count`.

### Aux entry semantics by context

The meaning of aux data is determined by which command slot references it:

| Command                     | Slot name     | Aux content                                     |
|-----------------------------|---------------|-------------------------------------------------|
| `CmdCreateSig` (slot 1)    | `params_aux`  | `count` scalar tags (u32 each)                  |
| `CmdCreateSig` (slot 3)    | `results_aux` | `count` scalar tags (u32 each)                  |
| `CmdBindEntryParams` (slot 1)| `vals_aux`  | `count` pool indices for value IDs              |
| `CmdIntrinsic` (slot 5)    | `args_aux`    | `count` pool indices for value IDs              |
| `CmdCall` (slot 6)         | `args_aux`    | `count` pool indices for value IDs              |
| `CmdJump` (slot 1)         | `args_aux`    | `count` pool indices for value IDs              |
| `CmdBrIf` (slot 2)         | `then_aux`    | `count` pool indices for then-branch value IDs  |
| `CmdBrIf` (slot 5)         | `else_aux`    | `count` pool indices for else-branch value IDs  |
| `CmdSwitchInt` (slot 2)    | `cases_aux`   | `3 * count` u32s: per case `[raw_lo, raw_hi, dest]` |
| `CmdVecMask` (slot 4)      | `args_aux`    | `count` pool indices for value IDs              |

### Switch case encoding

Each switch case occupies 3 `u32` words in aux:

| Word     | Meaning                                 |
|----------|-----------------------------------------|
| `raw_lo` | Low 32 bits of the case value           |
| `raw_hi` | High 32 bits of the case value          |
| `dest`   | Pool index for the destination block ID |

The `count` in the `CmdSwitchInt` command is the number of cases (not the
number of u32 words). The actual aux entry has `3 * count` data words.

## 6. Command stream

Commands occupy the remainder of the buffer after aux data. Each command is:

| Field   | Type   | Description                               |
|---------|--------|-------------------------------------------|
| `tag`   | u32    | Command tag (see §7)                      |
| `slots` | u32[]  | Tag-specific fixed-length slot array      |

The slot count for each tag is a compile-time constant known to both encoder
and decoder. The decoder reads:

```rust
let tag = read_u32(buf, pos); pos += 4;
let n = SLOT_COUNT[tag as usize];
let slots = &buf[pos..pos + 4 * n]; pos += 4 * n;
```

No delimiters, no length prefixes per command, no string parsing.

## 7. Command tag table

Tags are assigned in declaration order from the `MoonBack.Cmd` ASDL union.
Tags 1–60 are defined below. Tag 0 is invalid.

Tag assignment is **stable**: new commands append at the end. Tags are never
reused or reordered.

### 7.1 Structural commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 1   | CmdTargetModel     | 0     | *(reserved, no slots)*                                       |
| 2   | CmdAliasFact       | 0     | *(reserved, no slots)*                                       |
| 3   | CmdCreateSig       | 5     | `[sig, params_aux, n_params, results_aux, n_results]`        |
| 4   | CmdDeclareData     | 3     | `[data, size, align]`                                        |
| 5   | CmdDataInitZero    | 3     | `[data, offset, size]`                                       |
| 6   | CmdDataInit        | 6     | `[data, offset, scalar, lit_tag, lit_lo, lit_hi]`            |
| 7   | CmdDataAddr        | 2     | `[dst, data]`                                                |
| 8   | CmdFuncAddr        | 2     | `[dst, func]`                                                |
| 9   | CmdExternAddr      | 2     | `[dst, extern_id]`                                           |
| 10  | CmdDeclareFunc     | 3     | `[visibility, func, sig]`                                    |
| 11  | CmdDeclareExtern   | 3     | `[extern_id, symbol, sig]`                                   |
| 12  | CmdBeginFunc       | 1     | `[func]`                                                     |
| 13  | CmdCreateBlock     | 1     | `[block]`                                                    |
| 14  | CmdSwitchToBlock   | 1     | `[block]`                                                    |
| 15  | CmdSealBlock       | 1     | `[block]`                                                    |
| 16  | CmdBindEntryParams | 3     | `[block, vals_aux, count]`                                   |
| 17  | CmdAppendBlockParam| 5     | `[block, value, shape_tag, scalar, lanes]`                   |
| 18  | CmdCreateStackSlot | 3     | `[slot, size, align]`                                        |

### 7.2 Value commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 19  | CmdAlias           | 2     | `[dst, src]`                                                 |
| 20  | CmdStackAddr       | 2     | `[dst, slot]`                                                |
| 21  | CmdConst           | 5     | `[dst, scalar, lit_tag, lit_lo, lit_hi]`                     |
| 22  | CmdUnary           | 6     | `[dst, op, shape_tag, scalar, lanes, value]`                 |
| 23  | CmdIntrinsic       | 7     | `[dst, op, shape_tag, scalar, lanes, args_aux, count]`       |
| 24  | CmdCompare         | 7     | `[dst, op, shape_tag, scalar, lanes, lhs, rhs]`              |
| 25  | CmdCast            | 4     | `[dst, op, scalar, value]`                                   |

### 7.3 Pointer and memory commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 26  | CmdPtrOffset       | 7     | `[dst, base_tag, base_id, index, elem_size, offset_lo, offset_hi]` |
| 27  | CmdLoadInfo        | 15    | `[dst, shape_tag, scalar, lanes, base_tag, base_id, byte_offset, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k]` |
| 28  | CmdStoreInfo       | 15    | `[shape_tag, scalar, lanes, base_tag, base_id, byte_offset, value, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k]` |

### 7.4 Atomic commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 29  | CmdAtomicLoad      | 15    | `[dst, scalar, base_tag, base_id, byte_offset, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k, ordering, _pad]` |
| 30  | CmdAtomicStore     | 14    | `[scalar, base_tag, base_id, byte_offset, value, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k, ordering]` |
| 31  | CmdAtomicRmw       | 16    | `[dst, op, scalar, base_tag, base_id, byte_offset, value, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k, ordering]` |
| 32  | CmdAtomicCas       | 17    | `[dst, scalar, base_tag, base_id, byte_offset, expected, replacement, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k, ordering, _pad]` |
| 33  | CmdAtomicFence     | 1     | `[ordering]`                                                 |

### 7.5 Arithmetic commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 34  | CmdIntBinary       | 7     | `[dst, op, scalar, overflow, exact, lhs, rhs]`               |
| 35  | CmdBitBinary       | 5     | `[dst, op, scalar, lhs, rhs]`                                |
| 36  | CmdBitNot          | 3     | `[dst, scalar, value]`                                       |
| 37  | CmdShift           | 5     | `[dst, op, scalar, lhs, rhs]`                                |
| 38  | CmdRotate          | 5     | `[dst, op, scalar, lhs, rhs]`                                |
| 39  | CmdFloatBinary     | 6     | `[dst, op, scalar, semantics, lhs, rhs]`                     |

### 7.6 Memory operation commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 40  | CmdMemcpy          | 3     | `[dst, src, len]`                                            |
| 41  | CmdMemset          | 3     | `[dst, byte, len]`                                           |

### 7.7 Select and FMA

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 42  | CmdSelect          | 7     | `[dst, shape_tag, scalar, lanes, cond, then_val, else_val]`  |
| 43  | CmdFma             | 6     | `[dst, scalar, semantics, a, b, c]`                          |

### 7.8 Vector commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 44  | CmdVecSplat        | 4     | `[dst, elem_scalar, lanes, value]`                           |
| 45  | CmdVecBinary       | 6     | `[dst, op, elem_scalar, lanes, lhs, rhs]`                    |
| 46  | CmdVecCompare      | 6     | `[dst, op, elem_scalar, lanes, lhs, rhs]`                    |
| 47  | CmdVecSelect       | 6     | `[dst, elem_scalar, lanes, mask, then_val, else_val]`        |
| 48  | CmdVecMask         | 6     | `[dst, op, elem_scalar, lanes, args_aux, count]`             |
| 49  | CmdVecInsertLane   | 6     | `[dst, elem_scalar, lanes, value, lane_value, lane]`         |
| 50  | CmdVecExtractLane  | 4     | `[dst, scalar, value, lane]`                                 |
| 51  | CmdVecLoadInfo     | 15    | `[dst, elem_scalar, lanes, base_tag, base_id, byte_offset, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k, _pad]` |
| 52  | CmdVecStoreInfo    | 14    | `[elem_scalar, lanes, base_tag, base_id, byte_offset, value, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k]` |

### 7.9 Control flow commands

| Tag | Name               | Slots | Layout                                                       |
|-----|--------------------|-------|--------------------------------------------------------------|
| 53  | CmdCall            | 8     | `[result_tag, result_dst, result_scalar, target_tag, target_id, sig, args_aux, count]` |
| 54  | CmdJump            | 3     | `[dest, args_aux, count]`                                    |
| 55  | CmdBrIf            | 7     | `[cond, then_block, then_aux, then_count, else_block, else_aux, else_count]` |
| 56  | CmdSwitchInt       | 5     | `[value, scalar, cases_aux, n_cases, default]`               |
| 57  | CmdReturnVoid      | 0     | *(no slots)*                                                 |
| 58  | CmdReturnValue     | 1     | `[value]`                                                    |
| 59  | CmdTrap            | 0     | *(no slots)*                                                 |
| 60  | CmdFinishFunc      | 1     | `[func]`                                                     |
| 61  | CmdFinalizeModule  | 0     | *(no slots)*                                                 |

## 8. Sub-encodings

### 8.1 Scalar tags

Numeric tags for `BackScalar` — used wherever a type width is needed. Matches
the ASDL declaration order.

| Tag | Name        | Byte width (64-bit target) |
|-----|-------------|----------------------------|
| 1   | BackBool    | 1                          |
| 2   | BackI8      | 1                          |
| 3   | BackI16     | 2                          |
| 4   | BackI32     | 4                          |
| 5   | BackI64     | 8                          |
| 6   | BackU8      | 1                          |
| 7   | BackU16     | 2                          |
| 8   | BackU32     | 4                          |
| 9   | BackU64     | 8                          |
| 10  | BackF32     | 4                          |
| 11  | BackF64     | 8                          |
| 12  | BackPtr     | 8                          |
| 13  | BackIndex   | 8                          |

### 8.2 Shape encoding

A `BackShape` is encoded as three slots in the command:

| Slot       | Meaning                                    |
|------------|--------------------------------------------|
| `shape_tag`| `0` = scalar, `1` = vector                 |
| `scalar`   | If scalar: the `BackScalar` tag. If vector: the element `BackScalar` tag. |
| `lanes`    | If scalar: `0`. If vector: lane count (power of 2, ≥ 2). |

For commands that only carry a scalar type (no vector variant), the `shape_tag`
and `lanes` slots are omitted and only `scalar` appears.

### 8.3 Address base encoding

A `BackAddressBase` is encoded as two slots:

| Slot      | Meaning                                    |
|-----------|--------------------------------------------|
| `base_tag`| `0` = value (BackAddrValue), `1` = stack slot (BackAddrStack), `2` = data (BackAddrData) |
| `base_id` | Pool index: for value→`BackValId`, stack→`BackStackSlotId`, data→`BackDataId` |

This is a simpler encoding than the text tape's `"V"/"S"/"D"` prefix, but
identical in semantics. The Rust decoder materializes the appropriate
`BackCmd::PtrAdd`/`BackCmd::StackAddr`/`BackCmd::DataAddr` sequences from these
two slots, exactly as the text decoder does.

### 8.4 Memory info encoding

A `BackMemoryInfo` is encoded as seven slots:

| Slot      | Meaning                                    |
|-----------|--------------------------------------------|
| `access`  | Pool index for `BackAccessId`              |
| `align_k` | Alignment kind: `0`=Unknown, `1`=Known, `2`=AtLeast, `3`=Assumed |
| `align_b` | Alignment bytes (0 if Unknown)             |
| `deref_k` | Dereference kind: `0`=Unknown, `1`=Bytes, `2`=Assumed |
| `deref_b` | Dereference bytes (0 if Unknown)           |
| `trap_k`  | Trap kind: `0`=MayTrap, `1`=NonTrapping, `2`=Checked |
| `motion_k`| Motion kind: `0`=MayNotMove, `1`=CanMove   |
| `mode_k`  | Access mode: `1`=Read, `2`=Write, `3`=ReadWrite |

### 8.5 Literal encoding

A `BackLiteral` is encoded as three slots shared by `CmdConst` and
`CmdDataInit`:

| Slot      | Meaning                                    |
|-----------|--------------------------------------------|
| `lit_tag` | `0`=null, `1`=bool, `2`=int, `3`=float     |
| `lit_lo`  | Low 32 bits of payload                     |
| `lit_hi`  | High 32 bits of payload                    |

Payload interpretation by `lit_tag`:

| `lit_tag` | `lit_lo`                  | `lit_hi`                  |
|-----------|---------------------------|---------------------------|
| 0 (null)  | 0                         | 0                         |
| 1 (bool)  | `0` or `1`                | 0                         |
| 2 (int)   | Low 32 bits of integer    | High 32 bits of integer   |
| 3 (float) | IEEE 754 bits (f32 in low 32, zero-extended; f64 in both) | |

For integer literals, the `scalar` slot in the same command determines the
signedness and width for masking/extension. 64 bits is sufficient for all
current scalar types; `CmdSwitchInt` case values are also masked to the
scalar width by the backend.

### 8.6 Integer semantics encoding

| Slot       | Meaning                                    |
|------------|--------------------------------------------|
| `overflow` | `0`=Wrap, `1`=NoSignedWrap, `2`=NoUnsignedWrap, `3`=NoWrap |
| `exact`    | `0`=MayLose, `1`=Exact                     |

### 8.7 Float semantics encoding

| Slot        | Meaning                                    |
|-------------|--------------------------------------------|
| `semantics` | `0`=Strict, `1`=FastMath                   |

### 8.8 Visibility encoding

| Slot         | Meaning                                    |
|--------------|--------------------------------------------|
| `visibility` | `0`=Local, `1`=Export                      |

### 8.9 Call result encoding

| Slot           | Meaning                                    |
|----------------|--------------------------------------------|
| `result_tag`   | `0`=stmt (no return value), `1`=value (returns a value) |
| `result_dst`   | If value: pool index for `BackValId`. If stmt: `0xFFFFFFFF` |
| `result_scalar`| If value: `BackScalar` tag. If stmt: `0`   |

### 8.10 Call target encoding

| Slot          | Meaning                                    |
|---------------|--------------------------------------------|
| `target_tag`  | `0`=direct (`BackFuncId`), `1`=extern (`BackExternId`), `2`=indirect (`BackValId`) |
| `target_id`   | Pool index: for direct→`BackFuncId`, extern→`BackExternId`, indirect→`BackValId` |

### 8.11 Atomic ordering encoding

| Slot       | Meaning                                    |
|------------|--------------------------------------------|
| `ordering` | `1`=SeqCst                                  |

### 8.12 Atomic RMW op encoding

| Slot  | Meaning                                    |
|-------|--------------------------------------------|
| `op`  | `1`=Add, `2`=Sub, `3`=And, `4`=Or, `5`=Xor, `6`=Xchg |

### 8.13 Integer op tags (for CmdIntBinary slot 1)

| Tag | Name          |
|-----|---------------|
| 1   | BackIntAdd    |
| 2   | BackIntSub    |
| 3   | BackIntMul    |
| 4   | BackIntSDiv   |
| 5   | BackIntUDiv   |
| 6   | BackIntSRem   |
| 7   | BackIntURem   |

### 8.14 Bit op tags (for CmdBitBinary slot 1)

| Tag | Name       |
|-----|------------|
| 1   | BackBitAnd |
| 2   | BackBitOr  |
| 3   | BackBitXor |

### 8.15 Shift op tags (for CmdShift slot 1)

| Tag | Name                      |
|-----|---------------------------|
| 1   | BackShiftLeft             |
| 2   | BackShiftLogicalRight     |
| 3   | BackShiftArithmeticRight  |

### 8.16 Rotate op tags (for CmdRotate slot 1)

| Tag | Name              |
|-----|-------------------|
| 1   | BackRotateLeft    |
| 2   | BackRotateRight   |

### 8.17 Float op tags (for CmdFloatBinary slot 1)

| Tag | Name           |
|-----|----------------|
| 1   | BackFloatAdd   |
| 2   | BackFloatSub   |
| 3   | BackFloatMul   |
| 4   | BackFloatDiv   |

### 8.18 Unary op tags (for CmdUnary slot 1)

| Tag | Name              |
|-----|-------------------|
| 1   | BackUnaryIneg     |
| 2   | BackUnaryFneg     |
| 3   | BackUnaryBnot     |
| 4   | BackUnaryBoolNot  |

### 8.19 Intrinsic op tags (for CmdIntrinsic slot 1)

| Tag | Name                   |
|-----|------------------------|
| 1   | BackIntrinsicPopcount  |
| 2   | BackIntrinsicClz       |
| 3   | BackIntrinsicCtz       |
| 4   | BackIntrinsicBswap     |
| 5   | BackIntrinsicSqrt      |
| 6   | BackIntrinsicAbs       |
| 7   | BackIntrinsicFloor     |
| 8   | BackIntrinsicCeil      |
| 9   | BackIntrinsicTruncFloat|
| 10  | BackIntrinsicRound     |

### 8.20 Compare op tags (for CmdCompare slot 1)

| Tag | Name          |
|-----|---------------|
| 1   | BackIcmpEq    |
| 2   | BackIcmpNe    |
| 3   | BackSIcmpLt   |
| 4   | BackSIcmpLe   |
| 5   | BackSIcmpGt   |
| 6   | BackSIcmpGe   |
| 7   | BackUIcmpLt   |
| 8   | BackUIcmpLe   |
| 9   | BackUIcmpGt   |
| 10  | BackUIcmpGe   |
| 11  | BackFCmpEq    |
| 12  | BackFCmpNe    |
| 13  | BackFCmpLt    |
| 14  | BackFCmpLe    |
| 15  | BackFCmpGt    |
| 16  | BackFCmpGe    |

### 8.21 Cast op tags (for CmdCast slot 1)

| Tag | Name         |
|-----|--------------|
| 1   | BackBitcast  |
| 2   | BackIreduce  |
| 3   | BackSextend  |
| 4   | BackUextend  |
| 5   | BackFpromote |
| 6   | BackFdemote  |
| 7   | BackSToF     |
| 8   | BackUToF     |
| 9   | BackFToS     |
| 10  | BackFToU     |

### 8.22 Vector binary op tags (for CmdVecBinary slot 1)

| Tag | Name            |
|-----|-----------------|
| 1   | BackVecIntAdd   |
| 2   | BackVecIntSub   |
| 3   | BackVecIntMul   |
| 4   | BackVecBitAnd   |
| 5   | BackVecBitOr    |
| 6   | BackVecBitXor   |

### 8.23 Vector compare op tags (for CmdVecCompare slot 1)

| Tag | Name              |
|-----|-------------------|
| 1   | BackVecIcmpEq     |
| 2   | BackVecIcmpNe     |
| 3   | BackVecSIcmpLt    |
| 4   | BackVecSIcmpLe    |
| 5   | BackVecSIcmpGt    |
| 6   | BackVecSIcmpGe    |
| 7   | BackVecUIcmpLt    |
| 8   | BackVecUIcmpLe    |
| 9   | BackVecUIcmpGt    |
| 10  | BackVecUIcmpGe    |

### 8.24 Vector mask op tags (for CmdVecMask slot 1)

| Tag | Name            |
|-----|-----------------|
| 1   | BackVecMaskNot  |
| 2   | BackVecMaskAnd  |
| 3   | BackVecMaskOr   |

## 9. C ABI / FFI surface

### 9.1 New entry points

```c
// Compile from binary wire format (JIT path).
// Returns null on error; call moonlift_last_error_message() for details.
moonlift_artifact_t* moonlift_jit_compile_binary(
    moonlift_jit_t* jit,
    const uint8_t*  data,
    size_t          len
);

// Compile from binary wire format (object emission path).
// Returns 1 on success, 0 on error.
int moonlift_object_compile_binary(
    const uint8_t*  data,
    size_t          len,
    const char*     module_name,
    moonlift_bytes_t* out
);
```

### 9.2 Existing entry points (unchanged)

```c
// Text tape path — remains available during migration.
moonlift_artifact_t* moonlift_jit_compile_tape(
    moonlift_jit_t* jit,
    const char*     payload
);
```

### 9.3 Buffer ownership

The Lua side owns the wire buffer. It allocates a `uint8_t[]` via `ffi.new`,
writes the format into it, and passes `(ptr, len)` to
`moonlift_jit_compile_binary`. The Rust side reads the buffer during the call
and does not retain any pointer into it after the call returns. The Lua side
can free or reuse the buffer immediately.

### 9.4 Error reporting

Errors are reported through the existing `moonlift_last_error_message()` C API.
On parse errors, the message includes the byte offset and the failing tag.

## 10. MOM ABI compatibility

MOM (the native Moonlift-on-Moonlift compiler) produces `BackProgram` data and
must deliver it to the same Rust Cranelift backend. MOM uses the wire format
directly — no intermediate text representation, no Lua involvement.

### 10.1 MOM encoder design

MOM writes the wire buffer using compiled Moonlift functions:

```
wire_begin(buf: ptr(WireBuilder))
  → resets pool, aux, and command cursors

wire_pool_string(buf: ptr(WireBuilder), str: ptr(u8), len: index) -> u32
  → interns string, returns pool index (dedup by content)

wire_aux_u32s(buf: ptr(WireBuilder), data: ptr(u32), count: index) -> u32
  → appends u32 array to aux section, returns aux index

wire_cmd_N(buf: ptr(WireBuilder), tag: u32, s0: u32, ..., sN: u32)
  → appends tag + N slots to command stream
  → one function per slot count, or a single function with a fixed
    slot-count table indexed by tag
```

MOM already uses numeric IDs (from `back/ids.mlua`) and numeric op tags (from
`back/ops.mlua`). The only new requirement is string pool construction for
extern symbols and debug names.

### 10.2 MOM's numeric IDs → pool indices

MOM's `BackValId`, `BackBlockId`, etc. are already integers from
`back/ids.mlua`. These integers can be used **directly** as pool indices if MOM
writes its name strings into the pool in the same order as its ID allocator
assigns them. This makes the encoding zero-copy for value IDs: the same
integer that MOM uses internally is the pool index in the wire format.

Alternatively, MOM can maintain a separate `name_id → pool_index` map if the
internal ID assignment order differs from the pool order.

### 10.3 No intermediate representation

The current Lua path goes: `BackProgram ASDL → text tape → Rust parse →
BackProgram Rust`. MOM goes: `command writes → wire buffer → Rust decode →
BackProgram Rust`. There is no ASDL materialization step. MOM's lowering
phases write commands directly into the wire buffer, exactly as they would
write into a `CmdEntry` tape today.

### 10.4 Shared decoder

The Rust side has one decoder for the wire format. Both the Lua compiler and
MOM produce the same binary encoding. There is no "MOM mode" or "Lua mode" —
just `moonlift_jit_compile_binary(jit, data, len)`.

## 11. Encoding example

The `add_i32` program from the test suite, which produces this text tape (341
bytes):

```
moonlift-back-command-tape-v2
CmdCreateSig	sig:add_i32	2	4	4	1	4
CmdDeclareFunc	E	add_i32	sig:add_i32
CmdBeginFunc	add_i32
CmdCreateBlock	entry.add_i32
CmdSwitchToBlock	entry.add_i32
CmdBindEntryParams	entry.add_i32	2	a	b
CmdIntBinary	r	BackIntAdd	4	0	1	a	b
CmdReturnValue	r
CmdSealBlock	entry.add_i32
CmdFinishFunc	add_i32
CmdFinalizeModule
```

### Binary encoding

**Header** (16 bytes):

```
4D4C4254  00000003  00000006  00000003
 magic     version  n_strings  n_aux
```

**String pool** (6 entries):

```
pool 0: len=10 "sig:add_i32" pad=2
pool 1: len=7  "add_i32"    pad=1
pool 2: len=13 "entry.add_i32" pad=3
pool 3: len=1  "a"          pad=3
pool 4: len=1  "b"          pad=3
pool 5: len=1  "r"          pad=3
```

**Aux data** (3 entries):

```
aux 0: count=2, data=[4, 4]          ← CmdCreateSig params (BackI32, BackI32)
aux 1: count=1, data=[4]             ← CmdCreateSig results (BackI32)
aux 2: count=2, data=[3, 4]          ← CmdBindEntryParams vals (pool 3="a", pool 4="b")
```

**Command stream** (11 commands):

```
tag=3  [0, 0, 2, 1, 1]              ← CmdCreateSig(sig=0, params_aux=0, n_params=2, results_aux=1, n_results=1)
tag=10 [1, 1, 0]                     ← CmdDeclareFunc(export, func=1, sig=0)
tag=12 [1]                           ← CmdBeginFunc(func=1)
tag=13 [2]                           ← CmdCreateBlock(block=2)
tag=14 [2]                           ← CmdSwitchToBlock(block=2)
tag=16 [2, 2, 2]                     ← CmdBindEntryParams(block=2, vals_aux=2, count=2)
tag=34 [5, 1, 4, 0, 0, 3, 4]        ← CmdIntBinary(dst=5, op=1(Add), scalar=4(I32), overflow=0(Wrap), exact=0(MayLose), lhs=3, rhs=4)
tag=58 [5]                           ← CmdReturnValue(value=5)
tag=15 [2]                           ← CmdSealBlock(block=2)
tag=60 [1]                           ← CmdFinishFunc(func=1)
tag=61 []                            ← CmdFinalizeModule
```

**Approximate size**: 16 (header) + ~72 (pool) + 24 (aux) + 104 (commands) ≈
216 bytes — a 37% reduction from the 341-byte text tape, with zero string
parsing on the Rust side. Larger programs see even greater savings because
identifier strings dominate text tape size but are deduplicated in the pool.

## 12. Migration path

### Phase 1: Implement binary encoder and decoder alongside text path

- Add `lua/moonlift/back_command_binary.lua` — Lua encoder producing the wire
  format. Same input (`BackProgram` ASDL), different output (byte buffer).
- Add `parse_back_command_binary()` in `src/ffi.rs` — Rust decoder.
- Add `moonlift_jit_compile_binary` and `moonlift_object_compile_binary` FFI
  entry points.
- All existing tests continue to use the text path. New tests exercise the
  binary path.

### Phase 2: Switch Lua compiler to binary path

- Change `back_jit.lua` to use the binary encoder by default.
- Run all tests against the binary path.
- Keep the text encoder and `moonlift_jit_compile_tape` available for
  debugging and as a cross-check.

### Phase 3: MOM uses the binary ABI

- MOM's lowering phases write commands directly into a wire buffer using the
  encoder functions described in §10.
- MOM calls the same `moonlift_jit_compile_binary` entry point.

### Phase 4: Remove text path

- Delete `back_command_tape.lua`, `parse_back_command_tape()`, and
  `moonlift_jit_compile_tape`.
- The wire format is the sole ABI.

## Appendix A: Slot count table

For decoder implementation convenience. Index by tag.

```
Tag  Slots   Tag  Slots   Tag  Slots   Tag  Slots
 1      0      17     5     33     1     49     6
 2      0      18     3     34     7     50     4
 3      5      19     2     35     5     51    15
 4      3      20     2     36     3     52    14
 5      3      21     5     37     5     53     8
 6      6      22     6     38     5     54     3
 7      2      23     7     39     6     55     7
 8      2      24     7     40     3     56     5
 9      2      25     4     41     3     57     0
10      3      26     7     42     7     58     1
11      3      27    15     43     6     59     0
12      1      28    15     44     4     60     1
13      1      29    15     45     6     61     0
14      1      30    14     46     6
15      1      31    16     47     6
16      3      32    17     48     6
```

## Appendix B: Format validation checklist

A conforming decoder must check:

- [ ] Header magic is `0x4D4C4254`
- [ ] Header version is `3`
- [ ] All pool indices in command slots are `< n_strings`
- [ ] All aux indices in command slots are `< n_aux`
- [ ] All aux entry `count` values match the command's declared count slot
- [ ] All scalar tags are in `1..=13`
- [ ] All op tags are in the valid range for their command class
- [ ] `shape_tag` is `0` or `1`
- [ ] `base_tag` is `0`, `1`, or `2`
- [ ] `lit_tag` is `0`, `1`, `2`, or `3`
- [ ] Command stream does not overflow the buffer
