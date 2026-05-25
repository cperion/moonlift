# StateOp → Moonlift Code Generation Design

## Overview

This document describes the automated compilation of semantic StateOp sequences (from the stencil promotion plan) into executable Moonlift functions, whose bytes can be extracted and used as stencil fixtures.

## Architecture

```
StateOp sequence (from promotion_plan.json)
  ↓
Moonlift function generator (string-based template)
  ↓
Moonlift source (64+ functions in one module)
  ↓
moon.emit_object() → ELF bytes
  ↓
ELF parser → extract function bytes + relocations
  ↓
Populate promotion_plan.json with physical.bytes_hex + holes
```

## Key Design Decisions

### 1. Function Signature

All generated stencil functions share the same ABI:

```moonlift
func stencil_<name>(
    state: ptr(u8),          -- pointer to VM state/frame base
    exits: ptr(u8),          -- exit jump table (for side_exit, etc.)
    return_addr: ptr(u8)     -- where to jump on fallthrough
) -> ptr(u8)
    -- execute StateOps
    -- return jump target or fallthrough address
end
```

The `state` pointer points to the frame's stack slot 0 (base of local variables).
Exit indices are enumerated and marshalled through an exit table.

### 2. Stack Slot Access

StateOps reference slots by name: `ReadSlot{slot=dst}`, `WriteSlot{slot=dst, value=const}`.

At codegen time, we don't know actual slot offsets (they're filled in at runtime). Instead:
- Emit load/store with **marker displacement** (distinctive constant)
- Record as a **hole** in the plan
- Runtime fixup fills in real displacement

Example:
```moonlift
-- For: ReadSlot{slot=lhs}
let lhs_tag = as(u32, state[0x5a5a5a5a])    -- marker: HOLE_SLOT_LHS_TAG
let lhs_bits = as(u64, state[0x5a5a5a5a + 8])
```

The marker `0x5a5a5a5a` appears in the compiled bytes and is replaced with the real displacement.

### 3. Hole Markers

Instead of trying to track holes through Cranelift's optimizer, we use **distinctive byte patterns**:

| Hole Type | Marker | Width | Purpose |
|-----------|--------|-------|---------|
| Slot displacement | `0x5a5a5a5a` | 4 | Stack slot offset from base |
| Immediate i32 | `0x3d3d3d3d` | 4 | 32-bit constant payload |
| Immediate i64 | `0x3d3d3d3d3d3d3d3d` | 8 | 64-bit constant payload |

When the ELF is parsed, we search for these markers in the function bytes and record their offsets as holes.

At runtime, the materializer replaces the markers with real values:
- Slot displacements → actual frame offsets
- Immediates → actual literal values

### 4. Guard Implementation

Guards are conditional branches. Example:

```
GuardTag{exit=side_exit, tag=INTEGER, value=lhs}
```

Compiled as:

```moonlift
let lhs_tag = as(u32, state[0x5a5a5a5a])  -- marker for slot
if lhs_tag != 0xDEADBEEF then              -- marker for INTEGER tag constant
    jump side_exit_idx
end
```

If the guard fails (tag doesn't match), we jump to the exit. The exit target is filled in at runtime.

### 5. Branch Implementation

Branch instructions map to Moonlift's `if`/region control flow:

```
LtInt{lhs=lhs, rhs=rhs}
Branch{cond=lt, false_target=false_edge, true_target=true_edge}
```

Compiles to:

```moonlift
if lhs < rhs then
    jump true_edge_idx
else
    jump false_edge_idx
end
```

Exit indices are holes filled at runtime.

### 6. Effects and Exits

Each StateOp sequence declares:
- `effects`: what side effects occur (PURE, MAY_BRANCH, MAY_CALL, etc.)
- `exits`: possible jump targets (next, side_exit, true_edge, false_edge, etc.)

The generated code must:
1. Emit all exits as reachable jump instructions
2. Mark exit indices as holes
3. Ensure all paths terminate (no fallthrough except fallback exit)

### 7. No Optimization

The generated Moonlift source is intentionally straightforward:
- No CSE or dead code elimination (Moonlift/Cranelift can do that)
- No loop unrolling or fusion
- Direct translation of StateOp → Moonlift operations
- Holes are marked with distinctive immediates, not obscured

This keeps the generated code simple and the hole positions predictable.

## StateOp Translation Table

| StateOp | Translation | Notes |
|---------|-----------|-------|
| `ReadSlot{slot=S}` | `as(u32/u64, state[slot_offset_S])` | Slot offset is a hole marker `0x5a5a5a5a` |
| `WriteSlot{slot=S, value=V}` | `state[slot_offset_S] = bitcast(V)` | Slot offset is a hole marker |
| `ConstInt{value=imm}` | `imm` literal | Immediate is a hole marker for i32/i64 |
| `AddIntWrap{lhs=L, rhs=R}` | `L + R` | Wrap-on-overflow; Moonlift handles implicitly |
| `GuardTag{exit=E, tag=T, value=V}` | `if tag(V) != T then jump exit_E` | Tag check; mismatch jumps to exit |
| `LtInt{lhs=L, rhs=R}` | `L < R` | Standard comparison |
| `Branch{cond=C, true=T, false=F}` | `if cond then jump T else jump F` | Maps condition value to jump |
| `Jump{target=T}` | `jump exit_T` or return | Fallthrough to exit or return |
| `ProjectSlot{slot=S, value=V}` | `state[slot_offset_S] = bitcast(V)` | Projection = store to snapshot location |

## Hole Extraction

After `moon.emit_object()`, the ELF parser:
1. Finds each generated function by name
2. Extracts the raw bytes
3. Scans for marker patterns (0x5a5a5a5a, 0x3d3d3d3d, etc.)
4. Records offset and marker type for each hole

Example:
```json
{
  "holes": [
    {
      "kind": "slot_disp",
      "marker": "5a 5a 5a 5a",
      "name": "lhs_slot_offset",
      "offsets": [42, 87],
      "width": 4
    },
    {
      "kind": "imm32",
      "marker": "3d 3d 3d 3d",
      "name": "constant_payload",
      "offsets": [120],
      "width": 4
    }
  ]
}
```

## Examples

### Example 1: LOADI (load immediate to slot)

StateOps:
```
ConstInt{value=imm_i64}
WriteSlot{slot=dst, value=const}
Jump{target=next}
```

Generated Moonlift:
```moonlift
func compound_loadi(
    state: ptr(u8),
    exits: ptr(u8),
    return_addr: ptr(u8)
) -> ptr(u8)
    let imm = 0x3d3d3d3d3d3d3d3d_i64   -- hole marker for 64-bit immediate
    let dst_offset = 0x5a5a5a5a_u32    -- hole marker for slot displacement
    let dst_base = as(ptr(u8), state + as(index, dst_offset))

    as(ptr(u64), dst_base)[0] = imm

    return return_addr
end
```

Holes:
- `0x3d3d3d3d3d3d3d3d` @ offset X → filled with actual i64 value
- `0x5a5a5a5a` @ offset Y → filled with actual dst slot displacement

### Example 2: GUARD + ADD (integer guard + guarded addition)

StateOps:
```
ReadSlot{slot=lhs}
GuardTag{exit=side_exit, tag=INTEGER, value=lhs}
ReadSlot{slot=rhs}
GuardTag{exit=side_exit, tag=INTEGER, value=rhs}
AddIntWrap{lhs=lhs, rhs=rhs}
WriteSlot{slot=dst, value=sum}
Jump{target=next}
```

Generated Moonlift:
```moonlift
func compound_guard_add(
    state: ptr(u8),
    exits: ptr(u8),
    return_addr: ptr(u8)
) -> ptr(u8)
    let lhs_offset = 0x5a5a5a5a_u32     -- hole: lhs slot offset
    let lhs_base = as(ptr(u8), state + as(index, lhs_offset))
    let lhs_tag = as(u32, lhs_base[0])

    if lhs_tag != 0xdead_beef_u32 then   -- hole: INTEGER tag constant (optional)
        let exit_idx = 0x5a5a5a5a_u32   -- hole: side_exit index
        return as(ptr(u8), exits[as(index, exit_idx)])
    end

    let rhs_offset = 0x5a5a5a5a_u32     -- hole: rhs slot offset
    let rhs_base = as(ptr(u8), state + as(index, rhs_offset))
    let rhs_tag = as(u32, rhs_base[0])

    if rhs_tag != 0xdead_beef_u32 then
        let exit_idx = 0x5a5a5a5a_u32
        return as(ptr(u8), exits[as(index, exit_idx)])
    end

    let lhs_bits = as(i64, lhs_base[8])
    let rhs_bits = as(i64, rhs_base[8])
    let sum = lhs_bits + rhs_bits

    let dst_offset = 0x5a5a5a5a_u32     -- hole: dst slot offset
    let dst_base = as(ptr(u8), state + as(index, dst_offset))
    as(ptr(i64), dst_base)[8] = sum

    return return_addr
end
```

Holes: many slot offsets, exit indices, tag constants.

## Implementation Steps

1. **StateOp → Moonlift translator** (string builder)
   - Walk StateOps in sequence
   - Emit Moonlift function source with markers
   - Handle variable reuse (lhs, rhs, sum, etc.)

2. **Batch module generator**
   - Collect all ~64 candidate functions
   - Wrap in single `local moon = require("moonlift")` module
   - Return as string

3. **ELF extraction + hole mapping**
   - Parse ELF via elf_parser.lua
   - Extract function bytes for each candidate
   - Scan bytes for hole markers
   - Record marker offsets → holes JSON

4. **Promotion plan population**
   - Merge extracted holes/bytes back into plan
   - Validate all candidates have physical data
   - Mark as ready for runtime

## Trade-offs

### Simplicity vs. Performance

- **Current**: Simple, direct translation. Cranelift/llvm-opt will optimize.
- **Alternative**: Hand-tuned assembly for each pattern (faster, unmaintainable).

We choose simplicity: the stencil library builder runs offline, and perf comes from runtime selection accuracy.

### Hole Markers vs. Relocation Info

- **Current**: Scan binary for marker patterns.
- **Alternative**: Extract ELF relocation sections (cleaner, more complex parsing).

We choose markers because:
- Relocation sections are sparse (only external symbols, not internal immediates)
- Marker scanning is simple and doesn't depend on relocation table structure
- Works across platforms (ELF, Mach-O, COFF all differ in relocation format)

### Moonlift String vs. AST Builder

- **Current**: Generate source as strings (easy to debug, inspect).
- **Alternative**: Use Moonlift's AST builder API (more complex, type-safe).

We choose strings for:
- Easier debugging (can print and read the source)
- Simpler template logic
- No need for ASDL machinery in offline tool

## Future Improvements

1. **Incremental compilation**: Cache previously compiled candidates; only regenerate changed ones.
2. **Relocation-based hole detection**: Use ELF reloc tables for external symbols (guards, exits).
3. **Marker uniqueness per compound**: Use compound ID in marker (e.g., `0x5a5a_00XX`) to track holes.
4. **Verification**: Compare generated hole positions against manual/reference stencils.
