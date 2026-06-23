# Moonlift Binary Wire Format v4 — Flatline

**Version**: 4
**Magic**: `0x4D4C` (little-endian)
**Replaces**: MLBT v3 (parametric format with sub-tag dispatch)

The wire format is a **section-indexed two-level** structure: declarations precede function
bodies, and a body table maps function IDs to byte offsets. Function bodies are flat
streams of `(tag, slots...)` pairs — one tag per Cranelift IR operation, no sub-tag
dispatch.

Architecturally, Flatline is Moonlift's current LLPVM-style ABI for backend
records. It is not a parser format and not a source language. It is a borrowed
record image consumed by the native Cranelift host:

```text
MoonCompiler.CodeResult
  -> MoonBack.Program
  -> MoonCompiler.FlatlineImage
  -> MoonCompiler.NativeArtifact | MoonCompiler.ObjectArtifact
```

That makes it the concrete native ABI half of the bootstrap split.

---

## 1. Header (28 bytes)

```
[magic:u32, ver:u32, n_funcs:u32,
 decl_offset:u32, decl_len:u32,
 body_tbl_offset:u32, body_tbl_len:u32]
```

| Field | Description |
|-------|-------------|
| `magic` | `0x4D4C` (little-endian) |
| `ver` | `4` |
| `n_funcs` | Number of function declarations |
| `decl_offset` | Byte offset of declaration section |
| `decl_len` | Byte length of declaration section |
| `body_tbl_offset` | Byte offset of body table |
| `body_tbl_len` | Byte length of body table |

After the header, the declaration section begins at `decl_offset`.

---

## 2. Declaration Section

All declarations are read sequentially in this order. Each section has a count prefix.

### 2.1 Signature Table

```
[n_sigs:u32,
 sig_0: [sig_id:u32, n_params:u32, param_types:u32..., n_results:u32, result_types:u32...],
 ...]
```

`param_types` and `result_types` are scalar type codes (see §4).

### 2.2 Function Table

```
[n_funcs:u32,
 func_0: [func_id:u32, sig_id:u32, visibility:u32, name_idx:u32],
 ...]
```

`visibility`: 0 = local, 1 = export.
`name_idx`: index into the trailing name table, or 0 for auto-generated names.

### 2.3 Data Table

```
[n_datas:u32,
 data_0: [data_id:u32, size:u32, align_log2:u32],
 ...]
```

`align_log2`: log2 of alignment (e.g., 2 for 4-byte alignment).

### 2.4 Data Initializers

```
[n_inits:u32,
 init_0: [data_id:u32, offset:u32, lit_tag:u32, lo:u32, hi:u32],
 ...]
```

`lit_tag`:
- 0: Zero-fill `lo` bytes at `offset`
- 1: Bool — `lo != 0` means true
- 2: Integer — 64-bit value from `(lo | hi << 32)`
- 3: Float — IEEE 754 bits from `(lo | hi << 32)`

### 2.5 Extern Table

```
[n_externs:u32,
 extern_0: [extern_id:u32, sig_id:u32, name_idx:u32],
 ...]
```

### 2.6 Name Table

```
[n_names:u32,
 name_0: [len:u32, bytes..., pad...],
 ...]
```

Each name is a `len`-byte UTF-8 string followed by padding to 4-byte alignment.

---

## 3. Body Table

```
entry_0: [func_id:u32, body_offset:u32, body_len:u32],
entry_1: ...
```

Each entry maps a `func_id` to its body bytes at `body_offset` with length `body_len`.
Body bytes are a flat stream of `(tag, slots...)` pairs (see §5).

---

## 4. Scalar Type Codes

| Code | Type |
|------|------|
| 1 | `Bool` |
| 2 | `I8` |
| 3 | `I16` |
| 4 | `I32` |
| 5 | `I64` |
| 6 | `U8` |
| 7 | `U16` |
| 8 | `U32` |
| 9 | `U64` |
| 10 | `F32` |
| 11 | `F64` |
| 12 | `Ptr` |
| 13 | `Index` |

## 5. MemFlags Bitfield

Single u32:
- Bit 0: `notrap` — load/store will not fault
- Bit 1: `aligned` — address is aligned to natural alignment
- Bit 2: `can_move` — instruction is safe to reorder

---

## 6. Comparator Codes

Used by Icmp and Fcmp ops.

### IntCC Codes
| Code | Meaning |
|------|---------|
| 1 | Equal |
| 2 | NotEqual |
| 3 | SignedLessThan |
| 4 | SignedLessThanOrEqual |
| 5 | SignedGreaterThan |
| 6 | SignedGreaterThanOrEqual |
| 7 | UnsignedLessThan |
| 8 | UnsignedLessThanOrEqual |
| 9 | UnsignedGreaterThan |
| 10 | UnsignedGreaterThanOrEqual |

### FloatCC Codes
| Code | Meaning |
|------|---------|
| 1 | Equal |
| 2 | NotEqual |
| 3 | LessThan |
| 4 | LessThanOrEqual |
| 5 | GreaterThan |
| 6 | GreaterThanOrEqual |

### AtomicRmwOp Codes
| Code | Meaning |
|------|---------|
| 1 | Add |
| 2 | Sub |
| 3 | And |
| 4 | Or |
| 5 | Xor |
| 6 | Xchg |

---

## 7. Flat Tag Table

Tags are dense (1..=N). Each tag has a fixed slot count defined in `TAG_SLOTS`.
Variable-length tags have their fixed prefix counted; the decoder reads additional slots
based on count fields.

### Structural (1–5)

| Tag | Name | Slots | Description |
|-----|------|-------|-------------|
| 1 | `CreateBlock` | 1 | `[block_id]` |
| 2 | `SwitchToBlock` | 1 | `[block_id]` |
| 3 | `AppendBlockParam` | 3 | `[block_id, scalar_type, value_id]` |
| 4 | `CreateStackSlot` | 3 | `[slot_id, size, align_log2]` |
| 5 | `AppendBlockParamVec` | 4 | `[block_id, scalar_type, lanes, value_id]` |

### Constants (10–16)

| Tag | Name | Slots | Description |
|-----|------|-------|-------------|
| 10 | `ConstI32` | 2 | `[dst, value]` |
| 11 | `ConstI64` | 3 | `[dst, lo, hi]` |
| 12 | `ConstF32` | 2 | `[dst, bits]` |
| 13 | `ConstF64` | 3 | `[dst, lo, hi]` |
| 14 | `ConstBool` | 2 | `[dst, 0/1]` |
| 15 | `ConstNull` | 1 | `[dst]` |
| 16 | `ConstInt` | 4 | `[dst, scalar_type, lo, hi]` |

### Integer Arithmetic (20–27)

All: `[dst, lhs, rhs]` except Ineg: `[dst, src]`

| Tag | Name | C/Op |
|-----|------|------|
| 20 | `Iadd` | iadd |
| 21 | `Isub` | isub |
| 22 | `Imul` | imul |
| 23 | `Sdiv` | sdiv |
| 24 | `Udiv` | udiv |
| 25 | `Srem` | srem |
| 26 | `Urem` | urem |
| 27 | `Ineg` | ineg (unary) |

### Float Arithmetic (30–41)

Most: `[dst, lhs/rhs or src]`

| Tag | Name | Slots | C/Op |
|-----|------|-------|------|
| 30 | `Fadd` | 3 | fadd |
| 31 | `Fsub` | 3 | fsub |
| 32 | `Fmul` | 3 | fmul |
| 33 | `Fdiv` | 3 | fdiv |
| 34 | `Fneg` | 2 | fneg |
| 35 | `Fabs` | 2 | fabs |
| 36 | `Fma` | 4 | `[dst, a, b, c]` |
| 37 | `Sqrt` | 2 | sqrt |
| 38 | `Floor` | 2 | floor |
| 39 | `Ceil` | 2 | ceil |
| 40 | `Trunc` | 2 | trunc |
| 41 | `Nearest` | 2 | nearest |

### Bitwise (50–53)

| Tag | Name | Slots | Op |
|-----|------|-------|----|
| 50 | `Band` | 3 | band |
| 51 | `Bor` | 3 | bor |
| 52 | `Bxor` | 3 | bxor |
| 53 | `Bnot` | 2 | bnot |

### Shift / Rotate (60–64)

| Tag | Name | Slots |
|-----|------|-------|
| 60 | `Ishl` | 3 |
| 61 | `Ushr` | 3 |
| 62 | `Sshr` | 3 |
| 63 | `Rotl` | 3 |
| 64 | `Rotr` | 3 |

### Compare (70–71)

| Tag | Name | Slots | Description |
|-----|------|-------|-------------|
| 70 | `Icmp` | 4 | `[dst, cc_kind, lhs, rhs]` |
| 71 | `Fcmp` | 4 | `[dst, cc_kind, lhs, rhs]` |

### Cast / Convert (80–89)

All: `[dst, scalar_type, src]`

| Tag | Name | Op |
|-----|------|----|
| 80 | `Bitcast` | bitcast |
| 81 | `Ireduce` | ireduce |
| 82 | `Sextend` | sextend |
| 83 | `Uextend` | uextend |
| 84 | `Fpromote` | fpromote |
| 85 | `Fdemote` | fdemote |
| 86 | `FcvtFromSint` | fcvt_from_sint |
| 87 | `FcvtFromUint` | fcvt_from_uint |
| 88 | `FcvtToSint` | fcvt_to_sint |
| 89 | `FcvtToUint` | fcvt_to_uint |

### Intrinsics (90–94)

All: `[dst, src]`

| Tag | Name | Op |
|-----|------|----|
| 90 | `Popcnt` | popcnt |
| 91 | `Clz` | clz |
| 92 | `Ctz` | ctz |
| 93 | `Bswap` | bswap |
| 94 | `Iabs` | iabs |

### Address Ops (100–103)

All: `[dst, ptr_type, id]`

| Tag | Name | Description |
|-----|------|-------------|
| 100 | `StackAddr` | stack_addr from slot |
| 101 | `GlobalValue` | global_value from data |
| 102 | `FuncAddr` | func_addr from func |
| 103 | `ExternAddr` | func_addr from extern |

### Memory (110–118)

| Tag | Name | Slots | Description |
|-----|------|-------|-------------|
| 110 | `Load` | 4 | `[dst, scalar_type, memflags, addr]` |
| 111 | `Store` | 4 | `[scalar_type, memflags, addr, value]` |
| 112 | `AtomicLoad` | 4 | `[dst, scalar_type, memflags, addr]` |
| 113 | `AtomicStore` | 4 | `[scalar_type, memflags, addr, value]` |
| 114 | `AtomicRmw` | 6 | `[dst, scalar_type, op_kind, memflags, addr, value]` |
| 115 | `AtomicCas` | 6 | `[dst, scalar_type, memflags, addr, expected, replacement]` |
| 116 | `Fence` | 0 | — (`SeqCst`; current ASDL has no weaker ordering variants) |
| 117 | `Memcpy` | 3 | `[dst, src, len]` |
| 118 | `Memset` | 3 | `[dst, byte, len]` |

### Pointer (120–121)

| Tag | Name | Slots | Description |
|-----|------|-------|-------------|
| 120 | `PtrAdd` | 3 | `[dst, base, offset]` |
| 121 | `PtrOffset` | 6 | `[dst, base, index, elem_size, const_lo, const_hi]` |

### Vector (130–154)

| Tag | Name | Slots | Description |
|-----|------|-------|-------------|
| 130 | `Splat` | 4 | `[dst, scalar_type, lanes, src]` |
| 131 | `InsertLane` | 4 | `[dst, vector, lane_value, lane_idx]` |
| 132 | `ExtractLane` | 4 | `[dst, scalar_type, vector, lane_idx]` |
| 133–138 | `VecIadd`/`VecIsub`/`VecImul`/`VecBand`/`VecBor`/`VecBxor` | 3 | `[dst, lhs, rhs]` |
| 139–148 | `VecIcmp*`/`VecSIcmp*`/`VecUIcmp*` | 3 | `[dst, lhs, rhs]` |
| 149 | `VecSelect` | 4 | `[dst, mask, then_val, else_val]` |
| 150 | `VecMaskNot` | 2 | `[dst, vec]` |
| 151 | `VecMaskAnd` | 3 | `[dst, lhs, rhs]` |
| 152 | `VecMaskOr` | 3 | `[dst, lhs, rhs]` |
| 153 | `VecLoad` | 5 | `[dst, scalar_type, lanes, memflags, addr]` |
| 154 | `VecStore` | 5 | `[scalar_type, lanes, memflags, addr, value]` |

### Select (160)

| Name | Slots | Description |
|------|-------|-------------|
| `Select` | 4 | `[dst, cond, then_val, else_val]` |

### Control Flow (170–175) — variable

| Tag | Name | Fixed | Description |
|-----|------|-------|-------------|
| 170 | `Jump` | 2 | `[dest_block, n_args]` + `n_args` value IDs |
| 171 | `Brif` | 2 | `[cond, then_block]` + then_args + else_block + else_args |
| 172 | `SwitchInt` | 3 | `[value, scalar_type, n_cases]` + default_block + cases |
| 173 | `ReturnVoid` | 0 | — |
| 174 | `ReturnValue` | 1 | `[value]` |
| 175 | `Trap` | 0 | — |

**Brif layout**: `[cond, then_block, then_nargs:u32, then_args:u32..., else_block:u32, else_nargs:u32, else_args:u32...]`

**SwitchInt layout**: `[value, scalar_type, n_cases:u32, default_block:u32, (case_lo:u32, case_hi:u32, dest_block:u32)...]`

### Call (180–182) — variable

| Tag | Name | Fixed | Description |
|-----|------|-------|-------------|
| 180 | `CallDirect` | 5 | `[result_tag, dst/void, scalar_type, func_id, sig_id]` + `n_args:u32` + args |
| 181 | `CallExtern` | 5 | `[result_tag, dst/void, scalar_type, extern_id, sig_id]` + `n_args:u32` + args |
| 182 | `CallIndirect` | 5 | `[result_tag, dst/void, scalar_type, callee, sig_id]` + `n_args:u32` + args |

`result_tag`: 0 = void, 1 = value

### Singleton Ops (190–191)

| Tag | Name | Slots | Description |
|-----|------|-------|-------------|
| 190 | `Alias` | 2 | `[dst, src]` — binds dst to src value |
| 191 | `BoolNot` | 2 | `[dst, value]` — logical not (icmp eq 0 → select) |

---

## 8. What Changed from MLBT v3

| Removed | Reason |
|---------|--------|
| `SealBlock` | Implicit — all blocks sealed at body end |
| `BindEntryParams` | Implicit — entry block params are function params |
| `FinishFunc` / `FinalizeModule` | Implicit — body end / buffer end |
| `BackIntSemantics` (overflow/exact) | Cranelift ignores |
| `BackFloatSemantics` (strict/fastmath) | Cranelift ignores |
| `BackAccessId` (provenance strings) | Never used by Cranelift |
| `BackDereference` | Never used by Cranelift |
| `BackAccessMode` | Implicit in load vs store operation |
| String pool for values/blocks | Handles are u32 integers |
| Aux data section | Variable-length data inline with count prefix |
| String-based switch case values | Raw u64 values |
| Sub-tag dispatch | Flat tag per Cranelift operation |

---

## 9. Wire Format Example

A minimal wire buffer for `func add1(a: i32): i32 { return a + 1 }`:

```
Header:
  4D4C 0000  | magic
  0400 0000  | version 4
  0100 0000  | n_funcs = 1
  1C00 0000  | decl_offset = 28
  2400 0000  | decl_len = 36
  4000 0000  | body_tbl_offset = 64
  0C00 0000  | body_tbl_len = 12

Declarations:
  0100 0000  | n_sigs = 1
  0000 0000  | sig_id = 0
  0100 0000  | n_params = 1
  0400 0000  | I32
  0100 0000  | n_results = 1
  0400 0000  | I32
  0100 0000  | n_funcs = 1
  0000 0000  | func_id = 0
  0000 0000  | sig_id = 0
  0100 0000  | visibility = export
  0000 0000  | name_idx = 0
  0000 0000  | n_datas = 0
  0000 0000  | n_inits = 0
  0000 0000  | n_externs = 0
  0000 0000  | n_names = 0

Body Table:
  0000 0000  | func_id = 0
  4C00 0000  | body_offset = 76
  3C00 0000  | body_len = 60

Body (60 bytes at offset 76):
  01 00000000  | CreateBlock(block=0)
  02 00000000  | SwitchToBlock(block=0)
  03 00000000 04000000 00000000  | AppendBlockParam(block=0, I32, value=0)
   BE 00000000 01000000  | Alias(dst=0, src=1)  -- v0 = arg
  0A 01000000 01000000  | ConstI32(dst=1, value=1)  -- v1 = 1
  14 02000000 00000000 01000000  | Iadd(dst=2, lhs=0, rhs=1)  -- v2 = v0 + v1
  AE 03000000 02000000  | ReturnValue(value=2)
```

Note: The body example assumes block params are accessible via Alias. In practice, the
frontend must emit appropriate Alias commands to bind block parameters to value IDs.
