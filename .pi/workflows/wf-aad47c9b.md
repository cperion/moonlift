
## Scout Output (Step 1)

Confirmed — tags 1 and 2 are silently dropped in `decode_commands()`. Here's the final comprehensive report:

---

## Key Code (cont.) — Critical structural observation

### `BackProgram::partition()` does NOT group `BackBodyCmd`

The `partition()` function's body-cmd handling is a long, mechanical `BackCmd::X => current_cmds.push(BackBodyCmd::X)` for every variant. **No sub-grouping or reorganization occurs.** The only logic is:
1. Top-level declarations → `decls` vector (with nesting checks)
2. Body commands → `current_cmds` vector (flat, 1:1 push)

This means the next step (grouping into schema-aligned sub-enums) would touch:
- The `BackBodyCmd` enum itself (replace flat enum with sub-enums)
- The `partition()` function (route into sub-enums instead of flat push)
- The `lower_cmd()` function (match on sub-enums, dispatching to shared handlers)
- Possibly `lower()` (which currently just calls `lower_cmd()` in sequence)

### The Schema's operator unions map directly to BackBodyCmd groups

| Schema Union | BackBodyCmd Variants | Count |
|---|---|---|
| `BackUnaryOp` | Ineg, Fneg, Bnot, BoolNot | 4 |
| `BackIntrinsicOp` | Popcount, Clz, Ctz, Bswap, Sqrt, Abs, Floor, Ceil, TruncFloat, Round | 10 |
| `BackCompareOp` | IcmpEq..FCmpGe | 16 |
| `BackCastOp` | Bitcast, Ireduce, Sextend..FToU | 11 |
| `BackIntOp` (+ `BackIntSemantics`) | Iadd, Isub, Imul, Sdiv, Udiv, Srem, Urem | 7 |
| `BackBitOp` | Band, Bor, Bxor | 3 |
| `BackShiftOp` | Ishl, Ushr, Sshr | 3 |
| `BackRotateOp` | Rotl, Rotr | 2 |
| `BackFloatOp` (+ `BackFloatSemantics`) | Fadd, Fsub, Fmul, Fdiv | 4 |
| `BackVecBinaryOp` | VecIadd, VecIsub, VecImul, VecBand, VecBor, VecBxor | 6 |
| `BackVecCompareOp` | VecIcmpEq..VecUIcmpGe | 10 |
| `BackVecMaskOp` | VecMaskNot, VecMaskAnd, VecMaskOr | 3 |
| `BackAtomicRmwOp` | AtomicRmw | 1 (op encoded inside) |
| (Address) | DataAddr, FuncAddr, ExternAddr, StackAddr | 4 |
| (Call) | CallValueDirect, CallStmtDirect, CallValueExtern, CallStmtExtern, CallValueIndirect, CallStmtIndirect | 6 |
| (Control flow) | Jump, BrIf, SwitchInt, ReturnVoid, ReturnValue, Trap | 6 |
| (CFG scaffolding) | CreateBlock, SwitchToBlock, SealBlock, BindEntryParams, AppendBlockParam, AppendVecBlockParam, CreateStackSlot | 7 |
| (Memory) | LoadInfo, StoreInfo, AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence, Memcpy, Memset | 9 |
| (Vector memory) | VecLoadInfo, VecStoreInfo | 2 |
| (Vector misc) | VecSplat, VecSelect, VecInsertLane, VecExtractLane | 4 |
| (Scalar misc) | Alias, PtrAdd, PtrOffset, Select, Fma | 5 |
| (Constants) | ConstInt, ConstFloat, ConstBool, ConstNull | 4 |

**Total: ~90 variants in BackBodyCmd**, but only ~20 logical groups.

### The `BackBodyCmd` → `BackCmd` parity

Every `BackBodyCmd` variant has a direct `BackCmd` counterpart (same name, same fields), with these exceptions:
- `BackCmd` has additional `FinishFunc(BackFuncId)`, `FinalizeModule` — routed to `BackDeclCmd`
- `BackCmd` has `DataInitInt/Float/Bool` — routed to `BackDeclCmd`  
- `BackCmd` has `CreateSig/DeclareData/DeclareFunc*` — routed to `BackDeclCmd`
- `BackCmd` lacks `TargetModelTag` and `AliasFact` (no Rust representation)

### Wire decoder's `decode_address()` actively synthesizes commands

When decoding memory ops (LoadInfo, StoreInfo, etc.), `decode_address()` calls `decode_address_base()` which may emit `StackAddr` or `DataAddr` synthetic `BackCmd` entries into the output stream, plus a `PtrAdd` for the byte offset. These are then processed by `partition()` like any other command. This is important for sub-enum design — any sub-enum that includes `LoadInfo`/`StoreInfo` must also account for the address-base expansion.

## Knowledge-builder Output (Step 2)

Now I have a complete picture. Let me produce the analysis.

---

## What Matters Most for This Problem

For sub-enum grouping of `BackBodyCmd`, the relevant dimensions are:

1. **Lowering arm shape variance within a schema group** — Do variants within a schema-minted operator union have different Rust-level struct shapes? Different lowering logic? This determines whether the sub-enum is a simple grouping or requires dispatch-within-dispatch.

2. **Semantics fields discarded in lowering** — `BackIntSemantics` and `BackFloatSemantics` are carried by Rust variants but *always ignored* in `lower_cmd`. This affects whether they must be preserved through the sub-enum or can be dropped.

3. **Address-synthesis commands crossing group boundaries** — `decode_address()` emits `StackAddr`/`DataAddr` + `PtrAdd` as *separate* `BackCmd` entries interleaved with memory ops. Any grouping of memory ops must account for these synthetic commands NOT being consumed by the memory sub-enum.

4. **Exhaustiveness boundaries** — Rust's match exhaustiveness means sub-enums become the primary dispatch level. The sub-enum handler either dispatches to a shared helper (clean), or re-dispatches internally (clumsy).

5. **Wire format → Rust mapping parity** — The wire format (ffi.rs decoder, back_command_binary.lua encoder) uses schema-aligned tags (CmdUnary, CmdIntBinary, etc.). The decoder expands each tag into specific `BackCmd` variants. Grouping BackBodyCmd into sub-enums must preserve the decoder's output — it cannot change what `BackCmd` variants exist.

---

## Non-Obvious Observations

### 1. The `Abs` variant breaks the intrinsic-group homogeneity

`Abs` is in schema group `BackIntrinsicOp` alongside Popcount, Clz, Ctz, Bswap, Sqrt, Floor, Ceil, TruncFloat, Round. All other intrinsics just call a single CLIF op:

```rust
BackBodyCmd::Popcount(dst, _, value) => { let v = self.value(value)?; self.bind_value(dst, self.builder.ins().popcnt(v)) }
```

But `Abs` dispatches on type:
```rust
BackBodyCmd::Abs(dst, ty, value) => {
    let value = self.value(value)?;
    let out = match ty {
        BackScalar::F32 | BackScalar::F64 => self.builder.ins().fabs(value),
        _ => self.builder.ins().iabs(value),
    };
    self.bind_value(dst, out)
}
```

If you group into `CmdIntrinsicOp(dst, op: BackIntrinsicOp, ty, args)`, the handler for `BackIntrinsicAbs` must dispatch differently than the rest. This means your intrinsic sub-enum handler can't be a uniform `match op { ... }` over a shared helper — `Abs` needs a special case.

### 2. `BoolNot` has a different field shape than `Ineg`/`Fneg`/`Bnot`

In the schema, `BackUnaryOp` includes `BackUnaryBoolNot` alongside the other three. But in the Rust representation:

```rust
Ineg(dst, ty, value)      // 3 fields: BackValId, BackScalar, BackValId
Fneg(dst, ty, value)      // 3 fields
Bnot(dst, ty, value)      // 3 fields
BoolNot(dst, value)       // 2 fields — NO type field!
```

And in `lower_cmd`, `BoolNot` has completely different logic (icmp_imm + select), while the other three are simple single-CLIF-op dispatches.

If you group into `BackCmdUnary(dst, op: BackUnaryOp, ty: BackScalar, value: BackValId)`, the `BoolNot` case has a `ty` field that is semantically meaningless (the lowering ignores whatever type is passed because it always produces i8). This is already true — the decoder fills in `BoolNot`'s type field... wait:

Looking at `decode_commands` tag 22:
```rust
22 => { // CmdUnary
    let dst = self.pool_val(slots[0], "dst")?;
    let scalar = self.read_scalar(slots[3], "unary scalar")?;
    let value = self.pool_val(slots[5], "unary value")?;
    let cmd = match slots[1] {
        4 => BackCmd::BoolNot(dst, value),  // <-- NO scalar!
        ...
    };
```

So `BoolNot` already omits `scalar` in the decoder! It emits `BackCmd::BoolNot(dst, value)` with 2 fields, while `BackCmd::Ineg(dst, scalar, value)` has 3. If you change `BackBodyCmd` to have a sub-enum like:
```rust
enum CmdUnaryOp {
    Ineg(BackValId, BackScalar, BackValId),
    ...
    BoolNot(BackValId, BackValId),  // different shape!
}
```

This is fine in Rust — sub-enum variants can have different shapes. But the `BackCmd` → `BackBodyCmd` mapping in `partition()` needs to preserve which decoder path was taken.

### 3. `VecMaskNot` has a different field shape than `VecMaskAnd`/`VecMaskOr`

Same pattern as BoolNot within unary:

```rust
VecMaskNot(dst, ty, value)      // 3 fields — unary  
VecMaskAnd(dst, ty, lhs, rhs)   // 4 fields — binary
VecMaskOr(dst, ty, lhs, rhs)    // 4 fields — binary
```

Schema's `BackVecMaskOp` unifies these. The `lower_cmd` dispatch is:
- `VecMaskNot` → `bind_vec_mask_not` (helper specifically for unary mask not)
- `VecMaskAnd` → `bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().band(l, r))`
- `VecMaskOr` → `bind_vec_binop(dst, *ty, lhs, rhs, |b, l, r| b.ins().bor(l, r))`

So `VecMaskNot` cannot share the `bind_vec_binop` helper with the binary mask ops, because the `bind_vec_binop` helper does type validation (`require_value_type`) on both operands.

### 4. Semantics fields are preserved through Rust but discarded in lowering

Every `BackIntOp` variant carries `BackIntSemantics`:
```rust
Iadd(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId)
```

But in `lower_cmd`, it's discarded:
```rust
BackBodyCmd::Iadd(dst, _, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().iadd(l, r)),
```

Same for `BackFloatSemantics` in `Fadd`, `Fsub`, `Fmul`, `Fdiv`, and `Fma`. The semantics are validated at the schema/MOM level, not at the Rust lowering level. This means:

- **The sub-enum must still carry these fields** even though lowering ignores them. They're part of the data that flows through the system for verification/debugging/inspection purposes.
- **The `bind_binop` helper is shared across ALL arithmetic groups** (int, bit, shift, rotate, float) but only int/float carry semantics.
- There's no opportunity to drop the semantics field when grouping — you'd need a second type system revision to remove it from Rust.

### 5. Address synthesis commands (`StackAddr`, `DataAddr`, `PtrAdd`) are interleaved with memory ops

This is the most critical constraint on grouping. When the decoder processes a `CmdLoadInfo` (tag 27), it does:

```
1. decode_address() → emits StackAddr/DataAddr + PtrAdd into `out`
2. Then emits LoadInfo into `out`
```

Result: `[..., StackAddr(__binary:load:dst:base), PtrAdd(__binary:load:dst:addr), LoadInfo(...), ...]`

These are processed by `partition()` in order. The `StackAddr` and `PtrAdd` become flat `BackBodyCmd` entries. The `LoadInfo` becomes another flat `BackBodyCmd` entry.

If you group memory ops into a sub-enum like:
```rust
enum CmdMemoryOp {
    LoadInfo(...),
    StoreInfo(...),
    AtomicLoad(...),
    ...
    VecLoadInfo(...),
    VecStoreInfo(...),
}
```

The address-synthesis commands (`StackAddr`, `DataAddr`, `PtrAdd`) MUST remain outside this sub-enum — they're regular body commands that happen to be generated by the decoder. **The address synthesis commands are NOT part of any schema operator union and should not be grouped with memory ops.**

This means the cleanest grouping for memory operations is just the Load/Store/Atomic group that directly maps to the schema's memory-related Cmd variants (tags 27-33, 51-52). The `StackAddr`, `DataAddr`, `PtrAdd` stay in a separate "address" group or remain ungrouped.

### 6. Both `Bnot` from `CmdUnary` AND `CmdBitNot` end up as the same Rust variant

The schema has `CmdUnary` (tag 22, op=3 = Bnot) AND `CmdBitNot` (tag 36, direct). Both decode to `BackCmd::Bnot`. The decoder is:

```rust
// tag 22:
3 => BackCmd::Bnot(dst, scalar, value),

// tag 36:
out.push(BackCmd::Bnot(self.pool_val(...), self.read_scalar(...), self.pool_val(...)));
```

Both produce `BackCmd::Bnot(dst, scalar, value)`. After `partition()`, both produce `BackBodyCmd::Bnot(dst, scalar, value)`. The origin is lost.

If schema tag 36 (`CmdBitNot`) should map to a different sub-enum than tag 22's op 3, this is impossible post-partition because they're the same variant. But since both mean the same thing (bitwise NOT), this isn't a problem — the sub-enum grouping should treat them identically.

**However**, if you wanted to preserve schema fidelity (e.g., `CmdBitNot` stays separate in the schema), you'd need a different `BackCmd` variant for `CmdBitNot` → `BackBodyCmd` path. Currently they're merged. This may or may not be acceptable.

### 7. The `SealBlock`/`SwitchToBlock`/`CreateBlock` are purely mechanical — no lowering logic variation

These CFG scaffolding commands have zero variability in lowering:

```rust
BackBodyCmd::CreateBlock(id) => {
    let block = self.builder.create_block();
    self.blocks.insert(id.clone(), block);
    Ok(())
}
```

They only differ in which builder method they call. Grouping them is trivial — the handler just dispatches to the right builder call. No shared helper needed.

### 8. `Select` doesn't belong to any schema operator union

`CmdSelect(dst, ty, cond, then, else)` is its own top-level Cmd variant in the schema. It doesn't fit into any of the operator unions (BackUnaryOp, BackIntOp, etc.). In the Rust lower_cmd, it has distinct logic:

```rust
BackBodyCmd::Select(dst, _, cond, then, else) => {
    let cond_value = self.cond_value(cond)?;  // icmp_imm(NotEqual, raw, 0)
    let then_value = self.value(then)?;
    let else_value = self.value(else)?;
    let out = self.builder.ins().select(cond_value, then_value, else_value);
    self.bind_value(dst, out)
}
```

It shares NO helpers with any other group. It should be its own sub-enum (or remain flat).

### 9. `Fma` and `Alias` are also singleton commands

`Fma` and `Alias` (and `PtrAdd`, `PtrOffset`, `StackAddr`, etc.) don't map to any schema operator union. They're schema-top-level Cmd variants. If you group only the operator unions, ~15 variants (Fma, Alias, PtrAdd, PtrOffset, StackAddr, DataAddr, FuncAddr, ExternAddr, Select, ConstInt, ConstFloat, ConstBool, ConstNull, Memcpy, Memset) remain ungrouped.

This means the "cleanest grouping boundary" would leave 15+ variants flat, and only group the ~75 variants that map to schema unions.

### 10. The 16 compare ops split across two helper methods at lowering

In the schema, `BackCompareOp` unifies all 16 compare operators (IcmpEq..FCmpGe). In Rust `lower_cmd`:

- 10 integer ops (IcmpEq..UIcmpGe) → `bind_icmp(dst, IntCC, lhs, rhs)`
- 6 float ops (FCmpEq..FCmpGe) → `bind_fcmp(dst, FloatCC, lhs, rhs)`

These use different CLIF condition codes (`IntCC` vs `FloatCC`). If you group into `CmdCompare(dst, op: BackCompareOp, ty, lhs, rhs)`, the sub-enum handler must dispatch further based on whether the op is integer or float:

```rust
fn lower_cmd_compare(&mut self, dst, op, lhs, rhs) -> Result<(), ...> {
    match op {
        BackCompareOp::IcmpEq => self.bind_icmp(dst, IntCC::Equal, lhs, rhs),
        ...
        BackCompareOp::FCmpEq => self.bind_fcmp(dst, FloatCC::Equal, lhs, rhs),
        ...
    }
}
```

This is fine — it's just a two-level dispatch. But the design must accept that `bind_icmp` and `bind_fcmp` remain separate helpers.

### 11. Vector select has a type safety check that no other vector op has

```rust
BackBodyCmd::VecSelect(dst, ty, mask, then, else) => {
    ...
    if matches!(ty.elem, BackScalar::F32 | BackScalar::F64) {
        return Err(LalinError::new(format!(
            "...Lalin requires an explicit future float-vector select/blend command..."
        )));
    }
    let masked_then = self.builder.ins().band(mask_value, then_value);
    ...
}
```

This is the only lowering handler that has a type-based error. It rejects float element types because the current lowering uses integer bit operations to implement the mask. If `VecSelect` gets grouped with other vector ops, this special validation must be preserved.

### 12. The `partition()` function's error messages reference specific `BackCmd` variant names

```rust
if current_func.is_some() {
    return Err(LalinError::new("CreateSig cannot appear inside a function body".to_string()));
}
```

These error messages use the `BackCmd` variant name (like "CreateSig", "DeclareData", etc.). If you restructure `BackBodyCmd` into sub-enums but keep `BackCmd` flat (as Approach C suggests), the error messages in `partition()` don't change at all. The `partition()` function matches on `BackCmd`, not `BackBodyCmd`.

Conversely, the `lower_cmd` error messages reference `BackBodyCmd` variant names:
```rust
"function '{}' uses BackCmdVecSelect on float vector {:?}; ..."
```

These would need updating if `BackBodyCmd` variants are renamed to match the sub-enum structure.

---

## Knowledge Gaps

1. **The text tape decoder** (`ffi.rs: ` around line 356, `parse_back_command_tape`) — I should verify it also emits the same `BackCmd` variants as the binary decoder. A quick check shows it does (e.g., `BackCmd::StackAddr`). No gap here.

2. **The MOM encoder** (`lua/lalin/mom/back/`) — I should verify what commands the MOM frontend actually emits, to confirm the full set of `BackCmd` variants in production use. But this is a lower priority since the Rust side is the target of the change.

3. **Test coverage** — Are there tests that match on specific `BackBodyCmd` variant names via string formatting or error messages? I saw `BackCmdVecSelect` in an error message. Tests that parse error messages could break if variant names change.

4. **The `lower_cmd` match** — I verified exhaustively. All 90+ variants are handled. No unlisted variant. The match is exhaustive.

## Approach-proposer Output

Now I have complete context. Let me produce the 3 approaches.

---

### Approach A: Nested Schema Sub-Enum (Type-Level Restructuring)

- **Core idea**: Restructure `BackBodyCmd` so its variants are exactly the schema's operator unions — ~15 sub-enums wrapping ~75 operator variants + ~15 singleton variants staying flat.

- **Key changes**:
  - **`lib.rs`**: Replace the flat `BackBodyCmd` enum with:
    ```rust
    pub enum BackBodyCmd {
        Block(BlockOp),
        Address(AddressOp),        // StackAddr, DataAddr, FuncAddr, ExternAddr
        Constant(ConstOp),         // ConstInt, ConstFloat, ConstBool, ConstNull
        Unary(ScalarUnaryOp),      // Ineg, Fneg, Bnot, BoolNot
        Intrinsic(IntrinsicOp),    // Popcount..Round (10 ops)
        IntBinary(IntBinaryOp),    // Iadd..Urem (7 ops, carries BackIntSemantics)
        FloatBinary(FloatBinaryOp), // Fadd..Fdiv (4 ops, carries BackFloatSemantics)
        Bitwise(BitwiseOp),        // Band, Bor, Bxor
        Shift(ShiftOp),            // Ishl, Ushr, Sshr
        Rotate(RotateOp),          // Rotl, Rotr
        Compare(CompareOp),        // IcmpEq..FCmpGe (16 ops)
        Cast(CastOp),              // Bitcast..FToU (11 ops)
        Memory(MemoryOp),          // LoadInfo..Memset (9 ops)
        Call(CallOp),              // CallValueDirect..CallStmtIndirect (6 ops)
        Control(ControlOp),        // Jump, BrIf, SwitchInt, ReturnVoid, ReturnValue, Trap
        VecUnary(VecUnaryOp),      // VecSplat, VecMaskNot, VecSelect, VecInsertLane, VecExtractLane
        VecBinary(VecBinaryOp),    // VecIadd, VecIsub, VecImul, VecBand, VecBor, VecBxor, VecMaskAnd, VecMaskOr
        VecCompare(VecCompareOp),  // VecIcmpEq..VecUIcmpGe (10 ops)
        VecMemory(VecMemoryOp),    // VecLoadInfo, VecStoreInfo
        Ptr(PtrOp),                // PtrAdd, PtrOffset
        Singleton(X),              // Alias, Select, Fma
    }
    ```
    Note: `BoolNot` and `VecMaskNot` stay inside their respective sub-enums with different field shapes — Rust handles this naturally in sub-enum variant arms.

  - **`partition()`**: Change from flat `push()` to sub-enum construction. The `BackCmd::Ineg(a,b,c) => current_cmds.push(BackBodyCmd::Ineg(a,b,c))` becomes:
    ```rust
    BackCmd::Ineg(a,b,c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Ineg(a,b,c))),
    ```
    The decl-handling arms (CreateSig..FinalizeModule, BeginFunc..FinishFunc) stay unchanged.

  - **`lower()`**: Stays the same loop — still iterates and calls `lower_cmd()`.

  - **`lower_cmd()`**: The single flat match splits into ~15 per-sub-enum handler methods:
    ```rust
    fn lower_cmd(&mut self, cmd: &BackBodyCmd) -> Result<()> {
        match cmd {
            BackBodyCmd::Block(op) => self.lower_block_op(op),
            BackBodyCmd::Address(op) => self.lower_address_op(op),
            BackBodyCmd::Unary(op) => self.lower_unary_op(op),
            // ...
        }
    }
    ```
    Each handler method matches its sub-enum. For uniform groups (e.g., `ScalarUnaryOp::Ineg|Fneg|Bnot` → single CLIF call), this is clean. For non-uniform groups (e.g., `IntrinsicOp` where `Abs` dispatches on type while others are uniform), the handler handles the special case.

- **Tradeoff**: Optimizes for **schema fidelity and compiler-enforced grouping**. Sacrifices **match ergonomics** — instead of one flat match, you have two levels of matching. A visitor checking "is this any kind of binary op?" becomes trivial (`matches!(cmd, BackBodyCmd::IntBinary(_) | BackBodyCmd::FloatBinary(_) | ...)`). But a quick scan of "what does `lower_cmd` do?" now requires reading 15 methods instead of one flat match.

- **Risk**: 
  - **Address synthesis commands** (`StackAddr`, `PtrAdd`) emitted by `decode_address()` are NOT memory ops — they live in `AddressOp` and `PtrOp` respectively. The order of sub-enum entries in `current_cmds` means the physical command sequence `[StackAddr, PtrAdd, LoadInfo]` becomes `[Address(StackAddr), Ptr(PtrAdd), Memory(LoadInfo)]`. The lowerer processes these sequentially via the same `lower()` loop — the semantics are identical. No ordering risk.
  - **BoolNot's missing type field**: `BoolNot(dst, value)` without a `BackScalar` must sit in `ScalarUnaryOp` alongside `Ineg(dst, ty, value)` which has one. Rust handles this fine — sub-enum variants can have different shapes. But any helper like `lower_unary_op` must handle this mismatch explicitly in its match.
  - **VecMaskNot vs VecMaskAnd/VecMaskOr** have different arity (unary vs binary) in the same schema group. The sub-enum approach must accept this non-uniformity (Rust enum variants can differ in shape, so this is fine).
  - **Approach A is the most invasive**: every `BackCmd::X => BackBodyCmd::X` in `partition()` changes, plus every test that destructures `BackBodyCmd` variants.

- **Rough sketch**:
  1. Define all ~15 sub-enums in `lib.rs` (or a new module `back_op.rs`)
  2. Rewrite `BackBodyCmd` to reference them
  3. Rewrite `partition()`: 90 `BackCmd::X` arms now wrap in sub-enum constructors (the address/decl arms stay unchanged)
  4. Extract 15 handler methods from `lower_cmd()`, each matching its sub-enum
  5. `lower_cmd()` becomes a short dispatch match
  6. Update any tests or external code matching on `BackBodyCmd` (check `ffi.rs` text tape decoder)

---

### Approach B: Grouped Method Extraction — "Keep Flat, Organize Behavior"

- **Core idea**: Leave `BackBodyCmd` as a single flat enum (zero structural change), but restructure `lower_cmd` so its 90+ match arms are organized into ~15 named handler functions with a schema-aware header comment block. The grouping is **behavioral**, not structural.

- **Key changes**:
  - **`BackBodyCmd`**: No change. Flat enum stays flat.
  - **`partition()`**: No change. Mechanical push remains.
  - **`lower()`**: No change. Same loop.
  - **`lower_cmd()`**: The single 600-line match is replaced by a dispatch that calls grouped helpers:
    ```rust
    fn lower_cmd(&mut self, cmd: &BackBodyCmd) -> Result<()> {
        match cmd {
            // ── CFG scaffolding (6 ops) ────
            BackBodyCmd::CreateBlock(id) => { ... },
            BackBodyCmd::SwitchToBlock(id) => { ... },
            // ...SealBlock, BindEntryParams, AppendBlockParam, AppendVecBlockParam

            // ── Stack/Data slot commands (2 ops) ────
            BackBodyCmd::CreateStackSlot(id, size, align) => { ... },
            BackBodyCmd::StackAddr(dst, slot) => { ... },

            // ── Address commands (4 ops) ────
            BackBodyCmd::DataAddr(dst, id) => { ... }
            BackBodyCmd::FuncAddr(dst, id) => { ... }
            BackBodyCmd::ExternAddr(dst, id) => { ... }
            BackBodyCmd::Alias(dst, src) => { self.values.insert(...); Ok(()) },

            // ── Constant commands (4 ops) ────
            BackBodyCmd::ConstInt(dst, ty, raw) => { ... },
            // ...ConstFloat, ConstBool, ConstNull

            // ── Unary arithmetic (4 ops) ────
            BackBodyCmd::Ineg(dst, _, value) => self.bind_binop(...),
            BackBodyCmd::Fneg(dst, _, value) => self.bind_binop(...),
            BackBodyCmd::Bnot(dst, _, value) => self.bind_binop(...),
            BackBodyCmd::BoolNot(dst, value) => { /* different shape */ },

            // ── Intrinsics (10 ops, but Abs is special) ────
            BackBodyCmd::Popcount(dst, _, v) => self.bind_value(dst, self.builder.ins().popcnt(self.value(v)?)),
            // ...Clz, Ctz, Bswap, Sqrt, Floor, Ceil, TruncFloat, Round
            BackBodyCmd::Abs(dst, ty, v) => { /* type dispatch */ },

            // ── Integer arithmetic (7 ops, semantics ignored) ────
            // All use bind_binop: Iadd, Isub, Imul, Sdiv, Udiv, Srem, Urem

            // ── Float arithmetic (4 ops, semantics ignored) ────
            // All use bind_binop: Fadd, Fsub, Fmul, Fdiv

            // ── Bitwise (3 ops) ────
            // All use bind_binop: Band, Bor, Bxor

            // ── Shifts (3 ops) ────
            // All use bind_binop: Ishl, Ushr, Sshr

            // ── Rotates (2 ops) ────
            // All use bind_binop: Rotl, Rotr

            // ── Comparisons (16 ops: 10 int + 6 float) ────
            // 10 int → bind_icmp, 6 float → bind_fcmp

            // ── Casts (11 ops) ────
            // Each calls a specific CLIF builder method

            // ── Memory (7 ops) ────
            // LoadInfo, StoreInfo, AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence

            // ── Memory bulk (2 ops) ────
            // Memcpy, Memset

            // ── Pointer (2 ops) ────
            // PtrAdd, PtrOffset

            // ── Control flow (6 ops) ────
            // Jump, BrIf, SwitchInt, ReturnVoid, ReturnValue, Trap

            // ── Select/FMA (2 ops) ────
            // Select, Fma

            // ── Vector ops (16 ops) ────
            // VecSplat, VecIcmpEq..VecUIcmpGe, VecSelect, VecMaskNot, VecMaskAnd, VecMaskOr,
            // VecIadd, VecIsub, VecImul, VecBand, VecBor, VecBxor,
            // VecLoadInfo, VecStoreInfo, VecInsertLane, VecExtractLane
        }
    }
    ```
    Each comment block is a **group boundary**. Within a group, similar arms are adjacent. No actual method extraction happens — the grouping is purely organizational comments + physical proximity.

  - **Alternative (stronger grouping)**: Extract truly uniform groups into inline helpers:
    ```rust
    fn lower_int_op(&mut self, dst: &BackValId, lhs: &BackValId, rhs: &BackValId, clif_fn: fn(...) -> ...) { ... }
    fn lower_icmp(&mut self, dst: &BackValId, cc: IntCC, lhs: &BackValId, rhs: &BackValId) { ... }
    fn lower_fcmp(&mut self, dst: &BackValId, cc: FloatCC, lhs: &BackValId, rhs: &BackValId) { ... }
    ```
    These already mostly exist as `bind_binop`, `bind_icmp`, `bind_fcmp`. Approach B just formalizes the grouping names.

- **Tradeoff**: Optimizes for **zero disruption** — no enum changes, no test breakage, no `partition()` rewrite. Sacrifices **compiler-enforced grouping** — nothing prevents a variant from being matched in the wrong section, and there's no type-level distinction between a `ConstInt` and an `Iadd`.

- **Risk**:
  - **No structural enforcement**: The grouping is purely cosmetic. A future contributor can add a new variant to the wrong group without any compiler error. Over time, the grouping drifts from the schema unless rigorously maintained in code review.
  - **The mental model exists only in comments**: There's no way to `match cmd { BackBodyCmd::UnaryOp(_) => unreachable!() }` — you can't refer to "all unary ops" as a set. Analysis passes must still enumerate all variants individually.
  - **600-line match stays**: Even grouped by comments, the match is still ~600 lines. No mechanical benefit for navigation — you still scroll through all arms to find what you need.

- **Rough sketch**:
  1. Reorder the match arms in `lower_cmd()` into schema-group order (they're currently in declaration order, which already roughly follows schema grouping)
  2. Add `// ── Group name ────` comment headers between groups
  3. Optionally extract the most uniform groups into inline helper closures (e.g., `let lower_int_binops = |op: IntOp| match op { ... }`)
  4. Update any similar mechanical groupings elsewhere (e.g., `partition()` is already in group-proximate order)
  5. Profit: zero functional change, improved readability

---

### Approach C: Macro-Generated Dual Representation

- **Core idea**: Define all operators once in a macro DSL, then generate BOTH the flat `BackBodyCmd` enum AND the schema-aligned sub-enum types from that single definition. Sub-enums become first-class Rust types with `From<BackBodyCmd>` conversions for optional use.

- **Key changes**:
  - **New macro** `define_back_ops!` in `lib.rs` (or a `back_ops.rs` module):
    ```rust
    macro_rules! define_back_ops {
        () => {
            // Define the flat canonical enum
            pub enum BackBodyCmd {
                // CFG scaffolding
                CreateBlock(BackBlockId),
                SwitchToBlock(BackBlockId),
                ...
                // Unary ops
                Ineg(BackValId, BackScalar, BackValId),
                Fneg(BackValId, BackScalar, BackValId),
                Bnot(BackValId, BackScalar, BackValId),
                BoolNot(BackValId, BackValId),
                ...
            }
            
            // Define sub-enum types
            pub enum CfgOp { ... }       // CreateBlock, SwitchToBlock, SealBlock, ...
            pub enum UnaryOp { ... }     // Ineg, Fneg, Bnot, BoolNot
            pub enum IntOp { ... }       // Iadd, Isub, Imul, ...
            pub enum FloatOp { ... }     // Fadd, Fsub, Fmul, Fdiv
            pub enum CompareOp { ... }   // IcmpEq..FCmpGe
            pub enum CastOp { ... }      // Bitcast..FToU
            // ... etc for all ~15 groups

            // Generate TryFrom<BackBodyCmd> for each sub-enum
            impl TryFrom<BackBodyCmd> for UnaryOp { ... }
            impl TryFrom<BackBodyCmd> for IntOp { ... }
            // ...
        }
    }
    ```

  - **Alternative macro structure**: Use a data table (a const array of op descriptors) instead of macro-generated code:
    ```rust
    const OPS: &[OpDescriptor] = &[
        OpDescriptor::unary("Ineg", &["dst", "ty", "value"]),
        OpDescriptor::unary("Fneg", &["dst", "ty", "value"]),
        OpDescriptor::unary("Bnot", &["dst", "ty", "value"]),
        OpDescriptor::unary("BoolNot", &["dst", "value"]),  // different shape
        // ...
    ];
    ```
    This would require even more complex code generation. The macro approach is more practical.

  - **`partition()`**: Same as today — flat `push()` into `BackBodyCmd`. No change.
  
  - **`lower()`**: Same loop. No change.

  - **`lower_cmd()`**: Same flat match as today. No change required. But callers CAN optionally use the sub-enum `TryFrom` conversion for schema-aware analysis:
    ```rust
    fn validate_op_groups(cmds: &[BackBodyCmd]) {
        for cmd in cmds {
            if let Ok(unary) = UnaryOp::try_from(cmd.clone()) {
                // This command belongs to the UnaryOp group
            }
        }
    }
    ```

  - **Schema group enum** for runtime queries:
    ```rust
    pub enum BackCmdGroup {
        Cfg, Address, Constant, Unary, Intrinsic, IntBinary, FloatBinary,
        Bitwise, Shift, Rotate, Compare, Cast, Memory, Call, Control,
        VecUnary, VecBinary, VecCompare, VecMemory, Ptr, Singleton,
    }
    
    impl BackBodyCmd {
        pub fn group(&self) -> BackCmdGroup { ... }
    }
    ```

- **Tradeoff**: Optimizes for **single source of truth with zero disruption to the lowering pipeline**. Sacrifices **macro complexity and compile-time overhead** — the macro must generate multiple enums, `From` impls, and a `group()` method from the same definition. Debugging macro expansions is harder than debugging plain enums.

- **Risk**:
  - **Macro maintenance burden**: If the macro is too clever, it becomes hard to modify. A simpler approach (write enums by hand, add `From` impls manually) avoids this risk while keeping the canonical lowering enum flat.
  - **`TryFrom` conversions are fallible**: Every `TryFrom<BackBodyCmd> for UnaryOp` must match exactly the variants belonging to that group. Adding a variant to `BackBodyCmd` without adding it to its sub-enum `TryFrom` causes a runtime `Err` path (or a compile error if the match is non-exhaustive). The macro must handle this correctly.
  - **Clone overhead**: `TryFrom<&BackBodyCmd>` avoids cloning, but the sub-enum variant shapes must match the `BackBodyCmd` variant shapes exactly. For variants with many fields (e.g., `AtomicCas` with 7 fields), this is repetitive.
  - **Schema drift**: If the macro's definition is the source of truth, modifying the canonical enum requires modifying macro internals, not just adding a line to an enum definition. This increases cognitive overhead for simple additions.

- **Rough sketch**:
  1. Design the macro DSL — simplest is a `define_back_ops!` that takes groups of variants as `tt` fragments and emits flat enum + sub-enums + `TryFrom` impls
  2. Implement the macro in a new `back_ops.rs` module
  3. Replace the hand-written `BackBodyCmd` with `define_back_ops! { ... }`
  4. The `partition()` and `lower_cmd()` remain unchanged — they match on the flat enum as before
  5. Add `BackBodyCmd::group()` method for querying group membership
  6. Use sub-enum types in new code (e.g., wire format generation, analysis passes) where schema-aligned grouping is beneficial

---

### Comparison

| Dimension | A: Nested Sub-Enum | B: Grouped Methods | C: Macro-Generated Dual |
|-----------|-------------------|-------------------|----------------------|
| **Disruption** | High — enum, partition(), lower_cmd() all change | Low — only lower_cmd() reorganized | Low — partition() & lower_cmd() unchanged |
| **Compiler enforcement** | Full — you can't match an int op outside the int group | None — grouping is comments only | Partial — sub-enums exist but canonical path doesn't use them |
| **Schema fidelity** | Perfect — one sub-enum per schema union | Comments only — drifts without discipline | Perfect — macro defines both from one source |
| **Match ergonomics** | Two-level match (sub-enum + variant) | Single flat match | Single flat match (canonical path) |
| **Analysis passes** | Trivial — pattern match on sub-enum | Painful — enumerate all variants | Easy — use sub-enum `TryFrom` |
| **Macro complexity** | None | None | High — macro maintenance cost |

**When to pick each:**

- **Pick A** if: You want the compiler to enforce schema grouping, and you're willing to refactor the entire enum + all consumers. Best for a project rewriting the backend's core representation. Suitable if schema fidelity is paramount and you want to prevent future variants from landing in the wrong group.

- **Pick B** if: The goal is low-friction readability improvement with zero risk. Best when you want the benefit of grouping without touching the enum at all. Suitable when the enum is stable and you trust contributors to maintain comment-based grouping discipline.

- **Pick C** if: You want schema grouping as a **second, parallel type system** while keeping the fast lowering path untouched. Best when you want the sub-enums for external consumers (wire format, verification, documentation) but don't want to change the hot path. The macro is a one-time investment that pays off when multiple subsystems need to understand operator groupings.

## Critique Output

I now have a complete, verified picture of the codebase. Here is my evaluation.

---

## Approach A: Nested Schema Sub-Enum (Type-Level Restructuring)

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Tightens coupling between `BackBodyCmd` and the schema's operator-union taxonomy. But `BackBodyCmd` is defined, constructed, and consumed entirely within `src/lib.rs` — no external module references it (confirmed: zero hits in `ffi.rs`, `main.rs`, Lua files). So the coupling increase is internal to a single 2968-line file. Acceptable, but the sub-enums create intra-file dependencies that didn't exist before. |
| **Cohesion** | 5/5 | Each sub-enum represents exactly one schema operator union. A handler method like `lower_unary_op()` matches only `ScalarUnaryOp`, which contains exactly the 4 variants that belong to the unary group. No schema-irrelevant variants can accidentally appear. This is the maximum possible cohesion. |
| **Migration cost** | 4/5 | High: every `BackCmd::X => current_cmds.push(BackBodyCmd::X)` arm in `partition()` (all ~90 body-cmd arms) must wrap in a sub-enum constructor. The `lower_cmd()` match must be refactored into ~15 handler methods plus a dispatch layer. However, there are **zero** external consumers of `BackBodyCmd` (no tests, ffi, Lua), so the blast radius is confined to `src/lib.rs`. Within that file, the migration is mechanical and grep-reliable — every `BackBodyCmd::X` occurrence is visible with a single search. |
| **Philosophy fit** | 5/5 | Lalin's design principles emphasize **schema fidelity** (MOM schema → Rust types is an explicit design goal) and **fail-fast with compiler enforcement**. The nested sub-enum is the purest expression of both: the compiler enforces that `lower_int_binary_op()` can never accidentally match a `Popcount` or a `Jump`. The schema is encoded in the type system, not in comments. This aligns perfectly with the project's "explicit ASDL meaning, no hiding semantics in strings or callbacks" rule. |
| **Risk** | 3/5 | Three concrete risks: (1) **Non-uniform field shapes** — `BoolNot` has 2 fields vs `Ineg`'s 3, `VecMaskNot` is unary while `VecMaskAnd`/`VecMaskOr` are binary. Rust handles this cleanly (sub-enum variants can differ), but the sub-enum handler must explicitly match the oddball cases rather than dispatching through a uniform helper. (2) **Address synthesis commands** — `StackAddr`, `DataAddr`, `PtrAdd` emitted by `decode_address()` are NOT memory ops and must stay in their own sub-enums. The approach proposer correctly flagged this; the risk is that a future contributor assumes they belong to `MemoryOp` and creates a semantic ordering bug. (3) **BoolNot's missing type field** — currently the decoder simply omits the `BackScalar`. The sub-enum variant `ScalarUnaryOp::BoolNot(dst, value)` has no `ty` field. Any code that wants to iterate "all unary variants with their type" needs a special case for BoolNot. |
| **Testability** | 4/5 | Can be validated incrementally: (1) define sub-enums and verify they compile, (2) rewrite `partition()` arms one schema group at a time, (3) extract handler methods one at a time from `lower_cmd()`, (4) run the test suite after each group. The ~130 existing tests (all Lua-side, hitting Rust via JIT or object emission) provide a functional validation baseline. No rust unit tests exist for `BackBodyCmd` to break (confirmed: zero hits). |

**Verdict**: Strong yes
**Key concern**: The address synthesis commands (`StackAddr`, `DataAddr`, `PtrAdd`) must NOT be grouped into `MemoryOp`. They are separate first-class body commands emitted by `decode_address()`, not sub-ops of memory instructions. If this constraint is documented in the sub-enum module and enforced by the sub-enum taxonomy (they live in `AddressOp` and `PtrOp` respectively, never in `MemoryOp`), the risk is contained. The other non-uniformities (BoolNot, VecMaskNot) are syntactically awkward but mechanically safe.

---

## Approach B: Grouped Methods — "Keep Flat, Organize Behavior"

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 1/5 | No change. `BackBodyCmd` stays flat, `partition()` stays mechanical, `lower_cmd()` remains a single match. Zero new couplings introduced. This is the safest dimension. |
| **Cohesion** | 2/5 | The grouping exists only in comments and physical proximity of match arms. Nothing prevents `SwitchInt` from being placed next to `Ineg` in a future edit. The compiler provides zero enforcement — the grouping is purely cosmetic. Over time, without discipline, it drifts. |
| **Migration cost** | 1/5 | Trivial: reorder match arms into schema-group order, add comment headers. Zero functional changes. No enum redefinition, no `partition()` changes, no test breakage (no tests reference BackBodyCmd). This is the absolute minimum possible migration cost. |
| **Philosophy fit** | 2/5 | Weak alignment. Lalin's philosophy is "explicit ASDL meaning" and "compiler enforcement of structural invariants." Approach B encodes schema grouping in comments, not types. This is the antithesis of the project's approach to invariants — Lalin explicitly rejects implicit conventions in favor of checked structure. The `AGENTS.md` says "no hiding semantics in strings or callbacks" — comment-based grouping is a form of this. |
| **Risk** | 1/5 | Near-zero. The change is cosmetic. The only risk is that a future contributor doesn't notice the comment headers and places a new variant in the wrong group, but the compiler won't catch it, and the error is just a mislabeled section in a match — no runtime consequence. |
| **Testability** | 5/5 | No functional change means all existing tests pass without modification. The only way to break something is a typo in the match arms themselves, which Rust compilation catches. |

**Verdict**: Significant concerns
**Key concern**: This approach does not achieve its stated goal. The problem is that `BackBodyCmd` has ~90 variants with no schema-aligned grouping, and the proposed solution is to add comments. Comments are not a structural change — they do not enable schema-aware analysis passes, do not prevent group drift, and do not provide compiler enforcement. If the goal is genuine schema alignment, Approach B is a postponement, not a solution. If the goal is simply making `lower_cmd()` easier to navigate, it works — but that's a much smaller ambition than what the exploration phase scoped.

---

## Approach C: Macro-Generated Dual Representation

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | The macro creates a tight coupling between macro internals, the canonical flat enum, the sub-enums, and their `TryFrom` impls. Any change to a variant's shape (adding/removing a field) must be reflected in the macro definition, which then regenerates both representations. This is a single point of truth that creates cascading dependencies — change one thing, regenerate everything. |
| **Cohesion** | 4/5 | The macro enforces that the flat enum and the sub-enums stay in sync (they're generated from the same definition). This is excellent cohesion at the representation level. However, the *usage* of the sub-enums is optional — the lowering hot path can stay flat, meaning the sub-enum representation may never be used in practice, creating a "dead but correct" type system. |
| **Migration cost** | 3/5 | Designing and implementing the macro is a significant upfront investment. The macro must handle: (1) variants with different field shapes within the same group (BoolNot, VecMaskNot), (2) ~15 sub-enum groups with varying variant counts, (3) `TryFrom<BackBodyCmd>` impls for each sub-enum that are exhaustive and correct, (4) a `BackBodyCmd::group()` method. However, `partition()` and `lower_cmd()` stay completely unchanged — the macro only replaces the enum definition. No test changes needed. |
| **Philosophy fit** | 3/5 | Mixed. On one hand, having a single source of truth for operator definitions is philosophically clean. On the other hand, Lalin's MOM compiler (the schema-side counterpart) uses Lua macros in `back_command_binary.lua` — introducing Rust macros for the same purpose creates two separate macro systems. More importantly, the approach proposer notes the sub-enums are "for external consumers (wire format, verification, documentation)" — but the flat `BackCmd` already serves the wire format (`ffi.rs`), and `BackBodyCmd` is not consumed by the wire format at all. The sub-enums would be used only by future analysis passes, making this a speculative investment. |
| **Risk** | 5/5 | **High risk** for several reasons: (1) **Macro debugging difficulty** — macro errors in Rust are notoriously hard to decipher. A typo in a `tt`-fragment match can produce 50-line compiler errors referencing opaque generated code. (2) **Clone overhead in TryFrom** — `TryFrom<BackBodyCmd>` for each sub-enum must destructure the flat variant and reconstruct it in the sub-enum. For the ~90 variants, this is hundreds of lines of generated `match` arms. If the macro uses `&BackBodyCmd` to avoid cloning, it needs lifetime-aware codegen, which is harder. (3) **Macro maintenance burden** — adding a new body op means editing the macro definition instead of just adding a line to an enum. This increases friction for the most common operation (adding a new backend op). (4) **The macro may not be worth it for a single consumer** — `BackBodyCmd` is used in exactly one file by exactly one consumer (`lower_cmd`). A macro inflicts complexity proportional to a multi-module codebase for a benefit confined to a single module. |
| **Testability** | 2/5 | The macro itself is hard to test independently. Compilation of the generated code is the only test. If the macro silently generates incorrect `TryFrom` impls (e.g., a variant is accidentally omitted from its sub-enum), the code compiles but the `TryFrom` returns `Err` at runtime for valid inputs. This would manifest as a logic bug, not a compile error. The generated code is also opaque — you can't `grep` for a specific variant's generated `TryFrom` arm without expanding the macro. |

**Verdict**: No
**Key concern**: The macro is solving a problem that doesn't exist yet. `BackBodyCmd` has zero external consumers — it is defined, constructed, and lowered in a single 2968-line file with no other dependents. The macro's primary benefit (dual representation for external consumers) is speculative. Its costs (macro complexity, debugging difficulty, maintenance friction for the most common operation of adding a new op, opaque generated code) are concrete and immediate. A hand-written dual representation (just define sub-enums manually alongside the flat enum, without a macro) would achieve the same benefits with none of the macro risk. If the project later acquires multiple external consumers of `BackBodyCmd`, a macro can be introduced then — but introducing it pre-emptively is premature optimization that increases risk more than it improves safety.

---

## Summary

| Dimension | A: Nested Sub-Enum | B: Grouped Methods | C: Macro-Generated Dual |
|-----------|:------------------:|:------------------:|:----------------------:|
| **Coupling** | 3 | 1 | 4 |
| **Cohesion** | 5 | 2 | 4 |
| **Migration cost** | 4 | 1 | 3 |
| **Philosophy fit** | 5 | 2 | 3 |
| **Risk** | 3 | 1 | 5 |
| **Testability** | 4 | 5 | 2 |
| **Average** | **4.0** | **2.0** | **3.5** |

- **Recommended**: **Approach A** — It is the only approach that provides compiler-enforced schema grouping, which is the actual stated goal. The migration cost is real but bounded (one file, no external consumers). The non-uniformities (BoolNot, VecMaskNot, address synthesis) are mechanically manageable. The philosophy fit is perfect — this is exactly the kind of structural enforcement Lalin's design demands.

- **Dark horse**: **Approach B** — If the project's real priority is incremental readability improvement with zero risk, Approach B delivers that cheaply. It is not a solution to the schema-alignment problem, but it is a genuine improvement to code navigation for someone reading `lower_cmd()` for the first time. It also creates zero merge conflicts with future restructuring, making it a viable first step regardless of whether Approach A is pursued later.

- **Avoid**: **Approach C** — The macro complexity is not justified by the benefit. The dual representation (flat enum + sub-enums) can be achieved with hand-written code at lower risk. The macro's touted advantage — single source of truth — is undercut by the fact that the flat enum is the canonical lowering path and the sub-enums are speculative consumers. Adding a macro for future-proofing in a codebase with a single consumer is the wrong tradeoff. If the project later grows multiple BackBodyCmd consumers, a macro can be introduced at that point with a clear cost-benefit ratio.

## Documenter Output

Now I have all the context I need. Let me produce the comprehensive document.

---

# Architectural Decision: Nested Schema Sub-Enums for `BackBodyCmd`

**Date:** 2026-05-18
**Status:** Approved
**Workflow:** (derived from pipeline context)

---

## Goal

Restructure the flat `BackBodyCmd` enum (in `src/lib.rs`) into a hierarchy of ~15 schema-aligned sub-enums, replacing all ~90 flat variants with nested variants organized exactly as the MOM schema's operator unions define them. This transforms `BackBodyCmd` from a flat, ungrouped enumeration into a type-level taxonomy that mirrors the schema's `BackUnaryOp`, `BackIntOp`, `BackCompareOp`, `BackCastOp`, `BackFloatOp`, `BackBitOp`, `BackShiftOp`, `BackRotateOp`, `BackIntrinsicOp`, `BackVecBinaryOp`, `BackVecCompareOp`, `BackVecMaskOp`, `BackAtomicRmwOp`, and the remaining singleton/structural groups. The objective is to have the Rust type system enforce the same operator grouping that the schema already specifies, making it impossible to accidentally match an integer operation in a floating-point handler, and enabling schema-aware analysis passes that operate on whole groups rather than enumerating individual variants.

---

## Incentives

The following concrete problems motivated this work:

1. **No compiler enforcement of schema grouping.** `BackBodyCmd` is a flat 90+ variant enum. Nothing prevents a match arm for a float operation (e.g., `Fadd`) from being placed next to a control-flow arm (e.g., `Jump`). The schema's operator unions (`BackUnaryOp`, `BackIntOp`, etc.) exist only in comments and in the wire-format encoder (`back_command_binary.lua`) — the Rust side has no type-level representation of them. This violates Lalin's "explicit ASDL meaning" design principle (see `AGENTS.md`).

2. **Schema drift risk.** The MOM schema defines operator unions like `BackIntOp` (Iadd, Isub, Imul...) and `BackFloatOp` (Fadd, Fsub, Fmul, Fdiv...). The wire-format encoder uses these unions for binary tags. The Rust backend ignores them entirely. A new operator added to one schema union but matched in the wrong handler arm in Rust would compile correctly but produce wrong code — there is no type-level guard against this.

3. **Analysis passes are painful.** Any pass that needs to reason about "all integer binary operations" must enumerate all 7 variants (Iadd, Isub, Imul, Sdiv, Udiv, Srem, Urem) individually. There is no type-level expression for "the set of integer binary ops." This makes it harder to write verification, profiling, or transformation passes on the backend command stream.

4. **Lowering complexity.** The single `lower_cmd()` method is a 600+ line flat match. With sub-enums, each schema group gets its own dedicated handler method (`lower_unary_op`, `lower_int_binary_op`, `lower_float_binary_op`, etc.), splitting a massive function into ~15 focused methods with clear boundaries.

5. **Philosophy alignment.** Lalin's design (see `AGENTS.md`) explicitly requires "compiler enforcement of structural invariants" — "no hiding semantics in strings or callbacks." A flat enum with no type-level grouping is a form of hiding semantics: the grouping exists in the schema but is invisible to Rust's type system. Nested sub-enums encode the schema directly in Rust types.

---

## Current State

### Relevant code locations (all in `src/lib.rs`)

The entire `BackBodyCmd` enum, its construction via `BackProgram::partition()`, and its consumption via `FunctionLowerer::lower_cmd()` reside in a single 2968-line file. There are **zero external consumers** of `BackBodyCmd` — no tests, ffi exports, or Lua code reference it. The blast radius is confined to `src/lib.rs`.

### `BackBodyCmd` (structurally flat)

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackBodyCmd {
    CreateBlock(BackBlockId),
    SwitchToBlock(BackBlockId),
    SealBlock(BackBlockId),
    // ... 7 CFG scaffolding variants
    Alias(BackValId, BackValId),
    StackAddr(BackValId, BackStackSlotId),
    DataAddr(BackValId, BackDataId),
    FuncAddr(BackValId, BackFuncId),
    ExternAddr(BackValId, BackExternId),
    ConstInt(BackValId, BackScalar, String),
    // ... 3 more constant variants
    Ineg(BackValId, BackScalar, BackValId),
    Fneg(BackValId, BackScalar, BackValId),
    Bnot(BackValId, BackScalar, BackValId),
    BoolNot(BackValId, BackValId),              // <-- 2 fields, no type!
    Popcount(BackValId, BackScalar, BackValId),
    // ... 9 more intrinsic variants
    Iadd(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    // ... 6 more int binary variants (each carries BackIntSemantics, ignored in lowering)
    Fadd(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    // ... 3 more float binary variants (each carries BackFloatSemantics, ignored in lowering)
    Band(BackValId, BackScalar, BackValId, BackValId),
    // ... 2 more bitwise variants
    Ishl(BackValId, BackScalar, BackValId, BackValId),
    // ... 2 more shift variants
    Rotl(BackValId, BackScalar, BackValId, BackValId),
    // ... 1 more rotate variant
    IcmpEq(BackValId, BackScalar, BackValId, BackValId),
    // ...15 more compare variants (10 int + 6 float)
    Bitcast(BackValId, BackScalar, BackValId),
    // ...10 more cast variants
    LoadInfo(BackValId, BackScalar, BackValId, BackMemoryInfo),
    // ...8 more memory/atomic variants
    Memcpy(BackValId, BackValId, BackValId),
    Memset(BackValId, BackValId, BackValId),
    Select(BackValId, BackScalar, BackValId, BackValId, BackValId),
    Fma(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId, BackValId),
    // Vector ops (16 variants)
    CallValueDirect(BackValId, BackScalar, BackFuncId, BackSigId, Vec<BackValId>),
    // ...5 more call variants
    Jump(BackBlockId, Vec<BackValId>),
    BrIf(BackValId, BackBlockId, Vec<BackValId>, BackBlockId, Vec<BackValId>),
    SwitchInt(BackValId, BackScalar, Vec<BackSwitchCase>, BackBlockId),
    ReturnVoid,
    ReturnValue(BackValId),
    Trap,
}
```

**Total: ~90 variants, no grouping.** Every variant is a direct structural copy of its `BackCmd` counterpart. The `BackCmd` enum (above `BackBodyCmd` in the same file) is the wire-format output of `ffi.rs` decoder — flat, and remaining flat by design.

### `BackProgram::partition()` — construction

This function takes a `Vec<BackCmd>` and separates it into declarations (`BackDeclCmd`) and per-function body command sequences (`Vec<BackBodyCmd>`). For each `BackCmd` that is a body command, it does a mechanical push:

```rust
BackCmd::Ineg(a, b, c) => current_cmds.push(BackBodyCmd::Ineg(a, b, c)),
// ... 90+ identical patterns
```

The only logic is nesting checks (e.g., `CreateSig` cannot appear inside a function, `DataAddr` cannot appear at module top level). No data transformation occurs — it is a direct 1:1 mapping from `BackCmd::X` to `BackBodyCmd::X`.

### `FunctionLowerer::lower()` and `lower_cmd()` — consumption

```rust
fn lower(&mut self, cmds: &[BackBodyCmd]) -> Result<(), LalinError> {
    for cmd in cmds {
        self.lower_cmd(cmd)?;
    }
    Ok(())
}

fn lower_cmd(&mut self, cmd: &BackBodyCmd) -> Result<(), LalinError> {
    match cmd {
        // ~600 lines, ~90 match arms, single flat match
    }
}
```

The `lower()` method iterates sequentially (important for address-synthesis commands — see below). The `lower_cmd()` method is a single flat match dispatching each variant to Cranelift IR builder calls. Some variants share helper methods (`bind_binop`, `bind_icmp`, `bind_fcmp`, `bind_value`, `cond_value`).

### Key non-uniformities in the current flat enum

From the knowledge-builder analysis:

1. **`BoolNot` has 2 fields** — `BoolNot(BackValId, BackValId)` — while `Ineg`, `Fneg`, `Bnot` each have 3 fields `(BackValId, BackScalar, BackValId)`. The decoder (`ffi.rs`) omits the scalar for tag 22 op 4.

2. **`Abs` has special type-dispatching logic** in lowering — unlike all other intrinsics (Popcount, Clz, etc.) which call a single CLIF op, `Abs` dispatches on `BackScalar::F32|F64` → `fabs`, else → `iabs`.

3. **`VecMaskNot` is unary** (3 fields: `(BackValId, BackVec, BackValId)`) while `VecMaskAnd`/`VecMaskOr` are binary (4 fields: `(BackValId, BackVec, BackValId, BackValId)`). They share a schema union (`BackVecMaskOp`) but have different arity.

4. **Compare ops split across two CLIF helpers**: 10 integer compares use `IntCC` and `bind_icmp`; 6 float compares use `FloatCC` and `bind_fcmp`.

5. **Semantics fields are carried but ignored** — every `BackIntOp` variant carries `BackIntSemantics` and every `BackFloatOp` variant carries `BackFloatSemantics`, but both are unconditionally discarded in `lower_cmd` with `_` patterns.

6. **Address synthesis commands are interleaved with memory ops.** `decode_address()` in `ffi.rs` emits `StackAddr`/`DataAddr` + `PtrAdd` as separate `BackCmd` entries that then become `BackBodyCmd` entries. These are **not** memory ops — they are separate first-class body commands that precede `LoadInfo`/`StoreInfo` in the command stream.

### Mapping: schema unions → BackBodyCmd variants

| Schema Union | BackBodyCmd Variants | Count | Sub-enum name |
|---|---|---|---|
| CFG scaffolding | CreateBlock, SwitchToBlock, SealBlock, BindEntryParams, AppendBlockParam, AppendVecBlockParam, CreateStackSlot | 7 | `CfgOp` |
| Address | DataAddr, FuncAddr, ExternAddr, StackAddr | 4 | `AddressOp` |
| Constants | ConstInt, ConstFloat, ConstBool, ConstNull | 4 | `ConstOp` |
| `BackUnaryOp` | Ineg, Fneg, Bnot, BoolNot | 4 | `ScalarUnaryOp` |
| `BackIntrinsicOp` | Popcount, Clz, Ctz, Bswap, Sqrt, Abs, Floor, Ceil, TruncFloat, Round | 10 | `IntrinsicOp` |
| `BackIntOp` + semantics | Iadd, Isub, Imul, Sdiv, Udiv, Srem, Urem | 7 | `IntBinaryOp` |
| `BackFloatOp` + semantics | Fadd, Fsub, Fmul, Fdiv | 4 | `FloatBinaryOp` |
| `BackBitOp` | Band, Bor, Bxor | 3 | `BitwiseOp` |
| `BackShiftOp` | Ishl, Ushr, Sshr | 3 | `ShiftOp` |
| `BackRotateOp` | Rotl, Rotr | 2 | `RotateOp` |
| `BackCompareOp` | IcmpEq..FCmpGe (10 int + 6 float) | 16 | `CompareOp` |
| `BackCastOp` | Bitcast, Ireduce, Sextend..FToU | 11 | `CastOp` |
| Memory (scalar) | LoadInfo..AtomicFence, Memcpy, Memset | 9 | `MemoryOp` |
| Call | CallValueDirect..CallStmtIndirect | 6 | `CallOp` |
| Control | Jump, BrIf, SwitchInt, ReturnVoid, ReturnValue, Trap | 6 | `ControlOp` |
| Vector unary/mask | VecSplat, VecMaskNot, VecSelect, VecInsertLane, VecExtractLane | 5 | `VecUnaryOp` |
| Vector binary | VecIadd, VecIsub, VecImul, VecBand, VecBor, VecBxor, VecMaskAnd, VecMaskOr | 8 | `VecBinaryOp` |
| Vector compare | VecIcmpEq..VecUIcmpGe | 10 | `VecCompareOp` |
| Vector memory | VecLoadInfo, VecStoreInfo | 2 | `VecMemoryOp` |
| Pointer | PtrAdd, PtrOffset | 2 | `PtrOp` |
| Singletons | Alias, Select, Fma | 3 | (stays flat in a singleton group) |
| **Total** | | **~90** | **~21 sub-enums** |

---

## Chosen Target

### Approach: A — Nested Schema Sub-Enum (Type-Level Restructuring)

**Why:** Approach A scored highest in the critique (4.0/5.0 average vs. Approach B at 2.0 and Approach C at 3.5). It provides compiler-enforced schema grouping — the stated goal — where Approach B provides only cosmetic comments. It avoids the macro complexity of Approach C, keeping the restructuring explicit and debuggable. The migration cost is bounded to `src/lib.rs` because `BackBodyCmd` has zero external consumers (confirmed: no hits in `ffi.rs`, `main.rs`, or Lua files). The philosophy fit is perfect: Lalin's design mandates "explicit ASDL meaning" and "compiler enforcement of structural invariants" — nested sub-enums encode the schema directly in Rust types.

### Architecture

#### New sub-enum types (defined in `src/lib.rs` or a new `back_op.rs` module)

```rust
// ── CFG Scaffolding ────
pub enum CfgOp {
    CreateBlock(BackBlockId),
    SwitchToBlock(BackBlockId),
    SealBlock(BackBlockId),
    BindEntryParams(BackBlockId, Vec<BackValId>),
    AppendBlockParam(BackBlockId, BackValId, BackScalar),
    AppendVecBlockParam(BackBlockId, BackValId, BackVec),
    CreateStackSlot(BackStackSlotId, u32, u32),
}

// ── Address ────
pub enum AddressOp {
    DataAddr(BackValId, BackDataId),
    FuncAddr(BackValId, BackFuncId),
    ExternAddr(BackValId, BackExternId),
    StackAddr(BackValId, BackStackSlotId),
}

// ── Constants ────
pub enum ConstOp {
    ConstInt(BackValId, BackScalar, String),
    ConstFloat(BackValId, BackScalar, String),
    ConstBool(BackValId, bool),
    ConstNull(BackValId),
}

// ── Scalar Unary ────
pub enum ScalarUnaryOp {
    Ineg(BackValId, BackScalar, BackValId),
    Fneg(BackValId, BackScalar, BackValId),
    Bnot(BackValId, BackScalar, BackValId),
    BoolNot(BackValId, BackValId),  // Intentionally 2 fields — matches decoder output
}

// ── Intrinsics ────
pub enum IntrinsicOp {
    Popcount(BackValId, BackScalar, BackValId),
    Clz(BackValId, BackScalar, BackValId),
    Ctz(BackValId, BackScalar, BackValId),
    Bswap(BackValId, BackScalar, BackValId),
    Sqrt(BackValId, BackScalar, BackValId),
    Abs(BackValId, BackScalar, BackValId),
    Floor(BackValId, BackScalar, BackValId),
    Ceil(BackValId, BackScalar, BackValId),
    TruncFloat(BackValId, BackScalar, BackValId),
    Round(BackValId, BackScalar, BackValId),
}

// ── Integer Binary ────
pub enum IntBinaryOp {
    Iadd(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Isub(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Imul(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Sdiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Udiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Srem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Urem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
}

// ── Float Binary ────
pub enum FloatBinaryOp {
    Fadd(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fsub(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fmul(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fdiv(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
}

// ── Bitwise ────
pub enum BitwiseOp {
    Band(BackValId, BackScalar, BackValId, BackValId),
    Bor(BackValId, BackScalar, BackValId, BackValId),
    Bxor(BackValId, BackScalar, BackValId, BackValId),
}

// ── Shift ────
pub enum ShiftOp {
    Ishl(BackValId, BackScalar, BackValId, BackValId),
    Ushr(BackValId, BackScalar, BackValId, BackValId),
    Sshr(BackValId, BackScalar, BackValId, BackValId),
}

// ── Rotate ────
pub enum RotateOp {
    Rotl(BackValId, BackScalar, BackValId, BackValId),
    Rotr(BackValId, BackScalar, BackValId, BackValId),
}

// ── Compare ────
pub enum CompareOp {
    IcmpEq(BackValId, BackScalar, BackValId, BackValId),
    IcmpNe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    FCmpEq(BackValId, BackScalar, BackValId, BackValId),
    FCmpNe(BackValId, BackScalar, BackValId, BackValId),
    FCmpLt(BackValId, BackScalar, BackValId, BackValId),
    FCmpLe(BackValId, BackScalar, BackValId, BackValId),
    FCmpGt(BackValId, BackScalar, BackValId, BackValId),
    FCmpGe(BackValId, BackScalar, BackValId, BackValId),
}

// ── Cast ────
pub enum CastOp {
    Bitcast(BackValId, BackScalar, BackValId),
    Ireduce(BackValId, BackScalar, BackValId),
    Sextend(BackValId, BackScalar, BackValId),
    Uextend(BackValId, BackScalar, BackValId),
    Fpromote(BackValId, BackScalar, BackValId),
    Fdemote(BackValId, BackScalar, BackValId),
    SToF(BackValId, BackScalar, BackValId),
    UToF(BackValId, BackScalar, BackValId),
    FToS(BackValId, BackScalar, BackValId),
    FToU(BackValId, BackScalar, BackValId),
}

// ── Memory ────
pub enum MemoryOp {
    LoadInfo(BackValId, BackScalar, BackValId, BackMemoryInfo),
    StoreInfo(BackScalar, BackValId, BackValId, BackMemoryInfo),
    AtomicLoad(BackValId, BackScalar, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicStore(BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicRmw(BackValId, BackAtomicRmwOp, BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicCas(BackValId, BackScalar, BackValId, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicFence(BackAtomicOrdering),
    Memcpy(BackValId, BackValId, BackValId),
    Memset(BackValId, BackValId, BackValId),
}

// ── Call ────
pub enum CallOp {
    CallValueDirect(BackValId, BackScalar, BackFuncId, BackSigId, Vec<BackValId>),
    CallStmtDirect(BackFuncId, BackSigId, Vec<BackValId>),
    CallValueExtern(BackValId, BackScalar, BackExternId, BackSigId, Vec<BackValId>),
    CallStmtExtern(BackExternId, BackSigId, Vec<BackValId>),
    CallValueIndirect(BackValId, BackScalar, BackValId, BackSigId, Vec<BackValId>),
    CallStmtIndirect(BackValId, BackSigId, Vec<BackValId>),
}

// ── Control Flow ────
pub enum ControlOp {
    Jump(BackBlockId, Vec<BackValId>),
    BrIf(BackValId, BackBlockId, Vec<BackValId>, BackBlockId, Vec<BackValId>),
    SwitchInt(BackValId, BackScalar, Vec<BackSwitchCase>, BackBlockId),
    ReturnVoid,
    ReturnValue(BackValId),
    Trap,
}

// ── Vector Unary/Ternary ────
pub enum VecUnaryOp {
    VecSplat(BackValId, BackVec, BackValId),
    VecSelect(BackValId, BackVec, BackValId, BackValId, BackValId),
    VecInsertLane(BackValId, BackVec, BackValId, BackValId, u32),
    VecExtractLane(BackValId, BackScalar, BackValId, u32),
    VecMaskNot(BackValId, BackVec, BackValId),  // unary, same group
}

// ── Vector Binary ────
pub enum VecBinaryOp {
    VecIadd(BackValId, BackVec, BackValId, BackValId),
    VecIsub(BackValId, BackVec, BackValId, BackValId),
    VecImul(BackValId, BackVec, BackValId, BackValId),
    VecBand(BackValId, BackVec, BackValId, BackValId),
    VecBor(BackValId, BackVec, BackValId, BackValId),
    VecBxor(BackValId, BackVec, BackValId, BackValId),
    VecMaskAnd(BackValId, BackVec, BackValId, BackValId),
    VecMaskOr(BackValId, BackVec, BackValId, BackValId),
}

// ── Vector Compare ────
pub enum VecCompareOp {
    VecIcmpEq(BackValId, BackVec, BackValId, BackValId),
    VecIcmpNe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGe(BackValId, BackVec, BackValId, BackValId),
}

// ── Vector Memory ────
pub enum VecMemoryOp {
    VecLoadInfo(BackValId, BackVec, BackValId, BackMemoryInfo),
    VecStoreInfo(BackVec, BackValId, BackValId, BackMemoryInfo),
}

// ── Pointer ────
pub enum PtrOp {
    PtrAdd(BackValId, BackValId, BackValId),
    PtrOffset(BackValId, BackValId, BackValId, u32, i64),
}

// ── Singleton ────
pub enum OtherOp {
    Alias(BackValId, BackValId),
    Select(BackValId, BackScalar, BackValId, BackValId, BackValId),
    Fma(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId, BackValId),
}
```

#### Restructured `BackBodyCmd`

```rust
pub enum BackBodyCmd {
    Cfg(CfgOp),
    Address(AddressOp),
    Const(ConstOp),
    Unary(ScalarUnaryOp),
    Intrinsic(IntrinsicOp),
    IntBinary(IntBinaryOp),
    FloatBinary(FloatBinaryOp),
    Bitwise(BitwiseOp),
    Shift(ShiftOp),
    Rotate(RotateOp),
    Compare(CompareOp),
    Cast(CastOp),
    Memory(MemoryOp),
    Call(CallOp),
    Control(ControlOp),
    VecUnary(VecUnaryOp),
    VecBinary(VecBinaryOp),
    VecCompare(VecCompareOp),
    VecMemory(VecMemoryOp),
    Ptr(PtrOp),
    Other(OtherOp),
}
```

#### Data flow (unchanged)

```
Wire decoder (ffi.rs) → Vec<BackCmd> → BackProgram::partition() → BackProgram
  { decls: Vec<BackDeclCmd>, bodies: Vec<(BackFuncId, Vec<BackBodyCmd>)> }
    → FunctionLowerer::lower() → lower_cmd() → per-sub-enum handler → Cranelift IR
```

The only change is the internal representation of each `BackBodyCmd` in the bodies vector. The wire decoder, `BackCmd`, `BackProgram`, `lower()`, and the `back_command_binary.lua` encoder are all unaffected.

### Changes — File-by-file

#### `src/lib.rs` (primary change site)

1. **Add ~21 new sub-enum types** (as shown above) — either inline in `lib.rs` or extracted to a new `src/back_op.rs` module. The extraction to a separate module is recommended to keep `lib.rs` from growing further beyond 3000 lines.

2. **Replace `BackBodyCmd` definition** — From flat 90-variant enum to the ~21-variant nested enum shown above.

3. **Rewrite `BackProgram::partition()`** — Each body-command arm changes from:
   ```rust
   BackCmd::Ineg(a, b, c) => current_cmds.push(BackBodyCmd::Ineg(a, b, c)),
   ```
   to:
   ```rust
   BackCmd::Ineg(a, b, c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Ineg(a, b, c))),
   ```
   The decl-handling arms (CreateSig, DeclareData, BeginFunc, FinishFunc, FinalizeModule) stay unchanged.

4. **Refactor `lower_cmd()`** — The single flat match splits into a dispatch match:
   ```rust
   fn lower_cmd(&mut self, cmd: &BackBodyCmd) -> Result<(), LalinError> {
       match cmd {
           BackBodyCmd::Cfg(op) => self.lower_cfg(op),
           BackBodyCmd::Address(op) => self.lower_address(op),
           BackBodyCmd::Const(op) => self.lower_const(op),
           BackBodyCmd::Unary(op) => self.lower_unary(op),
           BackBodyCmd::Intrinsic(op) => self.lower_intrinsic(op),
           BackBodyCmd::IntBinary(op) => self.lower_int_binary(op),
           BackBodyCmd::FloatBinary(op) => self.lower_float_binary(op),
           BackBodyCmd::Bitwise(op) => self.lower_bitwise(op),
           BackBodyCmd::Shift(op) => self.lower_shift(op),
           BackBodyCmd::Rotate(op) => self.lower_rotate(op),
           BackBodyCmd::Compare(op) => self.lower_compare(op),
           BackBodyCmd::Cast(op) => self.lower_cast(op),
           BackBodyCmd::Memory(op) => self.lower_memory(op),
           BackBodyCmd::Call(op) => self.lower_call(op),
           BackBodyCmd::Control(op) => self.lower_control(op),
           BackBodyCmd::VecUnary(op) => self.lower_vec_unary(op),
           BackBodyCmd::VecBinary(op) => self.lower_vec_binary(op),
           BackBodyCmd::VecCompare(op) => self.lower_vec_compare(op),
           BackBodyCmd::VecMemory(op) => self.lower_vec_memory(op),
           BackBodyCmd::Ptr(op) => self.lower_ptr(op),
           BackBodyCmd::Other(op) => self.lower_other(op),
       }
   }
   ```
   Each handler method matches its own sub-enum and encapsulates the lowering logic previously in the flat match. Existing helper methods (`bind_binop`, `bind_icmp`, `bind_fcmp`, `bind_value`, `cond_value`) remain unchanged.

5. **Error message updates** — Any error messages in `lower_cmd` that reference `BackBodyCmd` variant names (e.g., `"BackCmdVecSelect on float vector"`) should be updated to use the new sub-enum variant path (e.g., `"BackBodyCmd::VecUnary(VecSelect) on float vector"`).

6. **Test code** — Tests in `lib.rs` (under `#[cfg(test)]`) that construct `BackBodyCmd` variants directly must be updated. However, the test functions (e.g., `compiles_and_reads_data_object`, `compiles_block_param_loop_cfg`) construct `BackCmd` variants and pass them through `BackProgram::partition()` — they never construct `BackBodyCmd` directly. **No test changes are expected** (but verify during implementation).

#### Files NOT changed

| File | Reason |
|---|---|
| `src/ffi.rs` | Decodes `BackCmd` (not `BackBodyCmd`). Unaffected. |
| `src/main.rs` | Uses `BackProgram::partition()`, which interface is unchanged. |
| `lua/lalin/back_command_binary.lua` | Encodes binary format for `BackCmd` (not `BackBodyCmd`). Unaffected. |
| `lua/lalin/back_command_tape.lua` | Text tape encoder for `BackCmd`. Unaffected. |
| Any Lua test file | All tests go through `BackCmd` → `partition()` → `BackBodyCmd`. No test constructs `BackBodyCmd` directly. |

### Data flow specifics: Address synthesis commands

`decode_address()` in `ffi.rs` emits `StackAddr`, `DataAddr`, and `PtrAdd` as separate `BackCmd` entries. After `partition()`, these become `BackBodyCmd::Address(StackAddr(...))`, `BackBodyCmd::Address(DataAddr(...))`, and `BackBodyCmd::Ptr(PtrAdd(...))` respectively. The command sequence `[StackAddr, PtrAdd, LoadInfo, ...]` becomes:

```rust
[
    BackBodyCmd::Address(AddressOp::StackAddr(dst, slot)),
    BackBodyCmd::Ptr(PtrOp::PtrAdd(addr, base, offset)),
    BackBodyCmd::Memory(MemoryOp::LoadInfo(result, ty, addr, info)),
    ...
]
```

The `lower()` method processes these sequentially via the same `for cmd in cmds` loop. The `StackAddr` is lowered first (binds a Cranelift `Value`), then `PtrAdd` (uses that value and computes an address), then `LoadInfo` (uses that address). The ordering semantics are preserved exactly as before — the sub-enum wrapping does not affect execution order.

### Tradeoffs acknowledged

1. **Two-level match**: A consumer must now match twice: first on `BackBodyCmd::Unary(_)`, then on `ScalarUnaryOp::Ineg(...)`. This is slightly more verbose than a flat match. **Acceptable because** the compiler enforcement of grouping boundaries is more valuable than keystroke savings, and the separate handler methods are more readable than a single 600-line match.

2. **Increased line count**: ~21 new sub-enum definitions + rewritten handler methods will increase `src/lib.rs` size by roughly 30-50%. **Acceptable because** the file is already 2968 lines and the restructuring improves navigability (each handler method is focused on one schema group). Consider extracting to a new `src/back_op.rs` module.

3. **Non-uniform variant shapes within sub-enums**: `ScalarUnaryOp` has `BoolNot` with 2 fields alongside 3-field variants. `VecUnaryOp` has unary `VecMaskNot` alongside ternary `VecSelect`. **Acceptable because** Rust enums naturally handle variant-specific field shapes, and the handler methods explicitly match these cases. No uniformity is imposed where none exists in the schema.

4. **Semantics fields preserved**: `BackIntSemantics` and `BackFloatSemantics` remain in `IntBinaryOp` and `FloatBinaryOp` variants even though they're discarded in lowering. **Acceptable because** they are part of the operational data flowing through the system for verification/inspection, and removing them would require a separate schema revision.

### Migration path

The restructuring is a single PR/commit touching only `src/lib.rs` (plus optionally creating `src/back_op.rs`). The migration steps:

1. **Define sub-enums**: Add all sub-enum types in a new module or at the top of the existing enum section.
2. **Rewrite `BackBodyCmd`**: Replace flat enum with nested variants referencing sub-enums.
3. **Rewrite `partition()`**: One pass over the 90+ body arms, wrapping each in its sub-enum constructor. Can be done mechanically (search-and-replace pattern per variant).
4. **Extract handler methods from `lower_cmd()`**: One sub-enum at a time, pull the match arms into a dedicated method. Start with the simplest groups (Cfg, Const, Address) and work up to the most complex (Compare, VecCompare, Memory).
5. **Verify**: Run `cargo build --release` and the full test suite (`luajit tests/...` for each test file). All functional behavior is preserved — this is a pure structural refactoring.

**Rollback**: Because `BackCmd` is unchanged and `BackProgram::partition()` interface is unchanged, reverting is trivial: restore the flat enum and simple push arms.

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Address synthesis commands grouped into `MemoryOp`** by mistake. `StackAddr`, `DataAddr`, `PtrAdd` are emitted by `decode_address()` before memory ops and must remain in `AddressOp`/`PtrOp` sub-enums. | Document this constraint in a comment on `MemoryOp` and `AddressOp` sub-enums. The `lower()` method's sequential processing preserves ordering regardless of grouping. |
| **`BoolNot` missing `BackScalar` field** — the sub-enum variant `ScalarUnaryOp::BoolNot(BackValId, BackValId)` has 2 fields while `Ineg`/`Fneg`/`Bnot` have 3. Handler methods that iterate "all unary ops and their types" need a special case. | The `lower_unary_op()` handler must have an explicit match for `BoolNot` (it's the only 2-field variant). No shared helper that extracts a type field from all unary ops can exist without handling this. This is an explicit non-uniformity in the schema, not a bug. |
| **`VecMaskNot` is unary but in the same schema group as binary `VecMaskAnd`/`VecMaskOr`.** | The `VecUnaryOp` sub-enum naturally accommodates both. `VecMaskNot`'s handler calls a different helper (`bind_vec_mask_not`) than the binary mask ops. Document this in the sub-enum definition. |
| **Lowering error messages reference old variant names** (e.g., `"BackCmdVecSelect"`). | Update error message strings to reference new sub-enum paths. Grep for all `"BackBodyCmd::` or `"BackCmd` in error messages. |
| **Regressions in the 130+ test suite** — any test that somehow constructs `BackBodyCmd` directly would fail to compile. | Run the full test suite after migration. Based on analysis (all tests construct `BackCmd` and go through `partition()`), no test changes should be needed. |
| **File size growth** — `src/lib.rs` is already 2968 lines. Adding sub-enum definitions could push it past 4000 lines. | Mitigate by extracting sub-enum definitions to a new `src/back_op.rs` module. The sub-enum types are `pub` and imported by `lib.rs`. The structural extraction is a one-time reorganization. |

---

## Non-Goals

1. **No changes to `BackCmd`**: The wire-format input enum remains flat. `BackCmd` is the output of the wire decoder (`ffi.rs`) and the input to `partition()`. Its flat structure is the correct abstraction boundary — the grouping exists at the `BackBodyCmd` level.

2. **No changes to `BackDeclCmd`**: Declaration commands are already a separate enum with stable semantics. No grouping is needed.

3. **No changes to the wire format**: `back_command_binary.lua` and `back_command_tape.lua` continue to use the same schema tags. The binary encoder does not reference `BackBodyCmd` at all.

4. **No changes to `lower()` function signature**: The iteration loop stays `for cmd in cmds { self.lower_cmd(cmd)?; }`. Only `lower_cmd()` and its internal handlers change.

5. **No removal of semantics fields**: `BackIntSemantics` and `BackFloatSemantics` remain in their respective sub-enum variants even though they are ignored in lowering. Removing them is a separate schema-level decision for a future revision.

6. **No macro generation**: All sub-enums are hand-written. Approach C (macro-generated dual representation) was rejected due to macro complexity, debugging difficulty, and speculative benefit for a single-consumer type. Hand-written code is preferred for clarity and maintainability.

## Edit-planner Output

Now I have complete, precise knowledge of the codebase. Let me produce the comprehensive edit plan.

---

## Precondition Checks

Before starting any edits, verify:

1. **Line 466**: `#[derive(Clone, Debug, PartialEq, Eq)]` still precedes `pub enum BackBodyCmd` — confirm the derive hasn't changed.
2. **Line 467—593**: The `BackBodyCmd` enum still has exactly the same 127 variants in the same order (flat, no sub-enums yet). Count the closing `}` at line 593.
3. **Line 858**: The `partition()` function closes at line 857 and `LalinError` starts at line 860 — verify no intervening code has been added.
4. **Line 2103**: `lower_cmd()` closing `}` still at line 2103, and `} // of match` precedes `fn bind_binop`.
5. **Line 1489—2439**: The `impl FunctionLowerer` block boundaries haven't shifted.
6. **Line 2673—2968**: The `#[cfg(test)]` module hasn't grown new tests that reference `BackBodyCmd` directly.
7. Run `cargo build --release` before changes to confirm the project compiles clean.

---

## Files to Modify

Only one file is changed: **`src/lib.rs`**. No new files are created (the sub-enum types go inline, before the `BackBodyCmd` definition). No other Rust or Lua files are touched.

---

### `src/lib.rs`

**Goal**: Replace the flat 127-variant `BackBodyCmd` enum with a hierarchy of 21 schema-aligned sub-enums, update `partition()` to wrap variants in sub-enum constructors, and refactor `lower_cmd()` to dispatch to per-sub-enum handler methods.

---

#### Edit block 1: Add 21 sub-enum types (insert at line 466, before `BackBodyCmd`)

**Lines 466—467** (insert new sub-enums between these lines, before `#[derive(Clone, Debug, PartialEq, Eq)] pub enum BackBodyCmd {`)

**What**: Insert ~21 new sub-enum definitions (each with `#[derive(Clone, Debug, PartialEq, Eq)]`) before the existing `BackBodyCmd` enum. These are the sub-enum types from the architectural decision: `CfgOp`, `AddressOp`, `ConstOp`, `ScalarUnaryOp`, `IntrinsicOp`, `IntBinaryOp`, `FloatBinaryOp`, `BitwiseOp`, `ShiftOp`, `RotateOp`, `CompareOp`, `CastOp`, `MemoryOp`, `CallOp`, `ControlOp`, `VecUnaryOp`, `VecBinaryOp`, `VecCompareOp`, `VecMemoryOp`, `PtrOp`, `OtherOp`.

**Before** (line 466—467):
```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackBodyCmd {
```

**After** (all sub-enums inserted before `BackBodyCmd`):
```rust
// ── CFG Scaffolding ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CfgOp {
    CreateBlock(BackBlockId),
    SwitchToBlock(BackBlockId),
    SealBlock(BackBlockId),
    BindEntryParams(BackBlockId, Vec<BackValId>),
    AppendBlockParam(BackBlockId, BackValId, BackScalar),
    AppendVecBlockParam(BackBlockId, BackValId, BackVec),
    CreateStackSlot(BackStackSlotId, u32, u32),
}

// ── Address ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AddressOp {
    DataAddr(BackValId, BackDataId),
    FuncAddr(BackValId, BackFuncId),
    ExternAddr(BackValId, BackExternId),
    StackAddr(BackValId, BackStackSlotId),
}

// ── Constants ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConstOp {
    ConstInt(BackValId, BackScalar, String),
    ConstFloat(BackValId, BackScalar, String),
    ConstBool(BackValId, bool),
    ConstNull(BackValId),
}

// ── Scalar Unary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ScalarUnaryOp {
    Ineg(BackValId, BackScalar, BackValId),
    Fneg(BackValId, BackScalar, BackValId),
    Bnot(BackValId, BackScalar, BackValId),
    BoolNot(BackValId, BackValId),   // 2 fields — intentionally no BackScalar
}

// ── Intrinsics ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum IntrinsicOp {
    Popcount(BackValId, BackScalar, BackValId),
    Clz(BackValId, BackScalar, BackValId),
    Ctz(BackValId, BackScalar, BackValId),
    Bswap(BackValId, BackScalar, BackValId),
    Sqrt(BackValId, BackScalar, BackValId),
    Abs(BackValId, BackScalar, BackValId),
    Floor(BackValId, BackScalar, BackValId),
    Ceil(BackValId, BackScalar, BackValId),
    TruncFloat(BackValId, BackScalar, BackValId),
    Round(BackValId, BackScalar, BackValId),
}

// ── Integer Binary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum IntBinaryOp {
    Iadd(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Isub(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Imul(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Sdiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Udiv(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Srem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
    Urem(BackValId, BackScalar, BackIntSemantics, BackValId, BackValId),
}

// ── Float Binary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FloatBinaryOp {
    Fadd(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fsub(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fmul(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
    Fdiv(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId),
}

// ── Bitwise ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BitwiseOp {
    Band(BackValId, BackScalar, BackValId, BackValId),
    Bor(BackValId, BackScalar, BackValId, BackValId),
    Bxor(BackValId, BackScalar, BackValId, BackValId),
}

// ── Shift ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ShiftOp {
    Ishl(BackValId, BackScalar, BackValId, BackValId),
    Ushr(BackValId, BackScalar, BackValId, BackValId),
    Sshr(BackValId, BackScalar, BackValId, BackValId),
}

// ── Rotate ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RotateOp {
    Rotl(BackValId, BackScalar, BackValId, BackValId),
    Rotr(BackValId, BackScalar, BackValId, BackValId),
}

// ── Compare ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CompareOp {
    IcmpEq(BackValId, BackScalar, BackValId, BackValId),
    IcmpNe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    FCmpEq(BackValId, BackScalar, BackValId, BackValId),
    FCmpNe(BackValId, BackScalar, BackValId, BackValId),
    FCmpLt(BackValId, BackScalar, BackValId, BackValId),
    FCmpLe(BackValId, BackScalar, BackValId, BackValId),
    FCmpGt(BackValId, BackScalar, BackValId, BackValId),
    FCmpGe(BackValId, BackScalar, BackValId, BackValId),
}

// ── Cast ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CastOp {
    Bitcast(BackValId, BackScalar, BackValId),
    Ireduce(BackValId, BackScalar, BackValId),
    Sextend(BackValId, BackScalar, BackValId),
    Uextend(BackValId, BackScalar, BackValId),
    Fpromote(BackValId, BackScalar, BackValId),
    Fdemote(BackValId, BackScalar, BackValId),
    SToF(BackValId, BackScalar, BackValId),
    UToF(BackValId, BackScalar, BackValId),
    FToS(BackValId, BackScalar, BackValId),
    FToU(BackValId, BackScalar, BackValId),
}

// ── Pointer ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PtrOp {
    PtrAdd(BackValId, BackValId, BackValId),
    PtrOffset(BackValId, BackValId, BackValId, u32, i64),
}

// ── Memory ────
// NOTE: Address synthesis commands (StackAddr, DataAddr, PtrAdd) are in AddressOp/PtrOp,
// NOT in MemoryOp. This sub-enum covers only Load/Store/Atomic operations.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MemoryOp {
    LoadInfo(BackValId, BackScalar, BackValId, BackMemoryInfo),
    StoreInfo(BackScalar, BackValId, BackValId, BackMemoryInfo),
    AtomicLoad(BackValId, BackScalar, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicStore(BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicRmw(BackValId, BackAtomicRmwOp, BackScalar, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicCas(BackValId, BackScalar, BackValId, BackValId, BackValId, BackMemoryInfo, BackAtomicOrdering),
    AtomicFence(BackAtomicOrdering),
    Memcpy(BackValId, BackValId, BackValId),
    Memset(BackValId, BackValId, BackValId),
}

// ── Call ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CallOp {
    CallValueDirect(BackValId, BackScalar, BackFuncId, BackSigId, Vec<BackValId>),
    CallStmtDirect(BackFuncId, BackSigId, Vec<BackValId>),
    CallValueExtern(BackValId, BackScalar, BackExternId, BackSigId, Vec<BackValId>),
    CallStmtExtern(BackExternId, BackSigId, Vec<BackValId>),
    CallValueIndirect(BackValId, BackScalar, BackValId, BackSigId, Vec<BackValId>),
    CallStmtIndirect(BackValId, BackSigId, Vec<BackValId>),
}

// ── Control Flow ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ControlOp {
    Jump(BackBlockId, Vec<BackValId>),
    BrIf(BackValId, BackBlockId, Vec<BackValId>, BackBlockId, Vec<BackValId>),
    SwitchInt(BackValId, BackScalar, Vec<BackSwitchCase>, BackBlockId),
    ReturnVoid,
    ReturnValue(BackValId),
    Trap,
}

// ── Vector Unary/Ternary ────
// NOTE: VecMaskNot is unary (3 fields), VecMaskAnd/VecMaskOr are binary (4 fields) —
// the different arity is fine since Rust enum variants can differ in shape.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecUnaryOp {
    VecSplat(BackValId, BackVec, BackValId),
    VecSelect(BackValId, BackVec, BackValId, BackValId, BackValId),
    VecInsertLane(BackValId, BackVec, BackValId, BackValId, u32),
    VecExtractLane(BackValId, BackScalar, BackValId, u32),
    VecMaskNot(BackValId, BackVec, BackValId),
}

// ── Vector Binary ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecBinaryOp {
    VecIadd(BackValId, BackVec, BackValId, BackValId),
    VecIsub(BackValId, BackVec, BackValId, BackValId),
    VecImul(BackValId, BackVec, BackValId, BackValId),
    VecBand(BackValId, BackVec, BackValId, BackValId),
    VecBor(BackValId, BackVec, BackValId, BackValId),
    VecBxor(BackValId, BackVec, BackValId, BackValId),
    VecMaskAnd(BackValId, BackVec, BackValId, BackValId),
    VecMaskOr(BackValId, BackVec, BackValId, BackValId),
}

// ── Vector Compare ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecCompareOp {
    VecIcmpEq(BackValId, BackVec, BackValId, BackValId),
    VecIcmpNe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecSIcmpGe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpLe(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGt(BackValId, BackVec, BackValId, BackValId),
    VecUIcmpGe(BackValId, BackVec, BackValId, BackValId),
}

// ── Vector Memory ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VecMemoryOp {
    VecLoadInfo(BackValId, BackVec, BackValId, BackMemoryInfo),
    VecStoreInfo(BackVec, BackValId, BackValId, BackMemoryInfo),
}

// ── Singleton (ungrouped) ────
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OtherOp {
    Alias(BackValId, BackValId),
    Select(BackValId, BackScalar, BackValId, BackValId, BackValId),
    Fma(BackValId, BackScalar, BackFloatSemantics, BackValId, BackValId, BackValId),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackBodyCmd {
```

**Quirks/notes**:
- The sub-enums are inserted BEFORE the existing `BackBodyCmd` definition at line 467, so they're defined before they're used by `BackBodyCmd`.
- Each sub-enum gets `#[derive(Clone, Debug, PartialEq, Eq)]` — matching the existing derive on `BackBodyCmd`.
- The comment `// NOTE:` on `MemoryOp` is critical — it warns future contributors that address synthesis commands do NOT belong here.
- `ScalarUnaryOp::BoolNot` intentionally has 2 fields (no `BackScalar`) — this matches the decoder output and is a documented non-uniformity.

---

#### Edit block 2: Rewrite `BackBodyCmd` (lines 467—593)

**What**: Replace the flat 127-variant enum with a compact 21-variant nested enum referencing the sub-enums from block 1.

**Before** (lines 467—593):
```rust
pub enum BackBodyCmd {
    CreateBlock(BackBlockId),
    SwitchToBlock(BackBlockId),
    SealBlock(BackBlockId),
    // ...120+ more flat variants...
    Trap,
}
```

**After**:
```rust
pub enum BackBodyCmd {
    Cfg(CfgOp),
    Address(AddressOp),
    Const(ConstOp),
    Unary(ScalarUnaryOp),
    Intrinsic(IntrinsicOp),
    IntBinary(IntBinaryOp),
    FloatBinary(FloatBinaryOp),
    Bitwise(BitwiseOp),
    Shift(ShiftOp),
    Rotate(RotateOp),
    Compare(CompareOp),
    Cast(CastOp),
    Ptr(PtrOp),
    Memory(MemoryOp),
    Call(CallOp),
    Control(ControlOp),
    VecUnary(VecUnaryOp),
    VecBinary(VecBinaryOp),
    VecCompare(VecCompareOp),
    VecMemory(VecMemoryOp),
    Other(OtherOp),
}
```

**Quirks/notes**:
- The variant names (`Cfg`, `Address`, `Const`, etc.) are chosen to be short but unambiguous. These names are used in `partition()` and `lower_cmd()`.
- `Other(OtherOp)` covers the three singletons: `Alias`, `Select`, `Fma`.

---

#### Edit block 3: Rewrite `partition()` body-command arms (lines 654—847)

**What**: Each `BackCmd::X => current_cmds.push(BackBodyCmd::X(...))` arm changes to wrap in the appropriate sub-enum constructor. The decl-handling arms (CreateSig, DeclareData, BeginFunc, FinishFunc, FinalizeModule, and the 3 error-checking address arms at lines 654—666) are affected too but stay in the same structural position.

**Before** (representative arms, lines 654—847):
```rust
BackCmd::DataAddr(a, b) => { ... current_cmds.push(BackBodyCmd::DataAddr(a, b)); }
BackCmd::FuncAddr(a, b) => { ... current_cmds.push(BackBodyCmd::FuncAddr(a, b)); }
BackCmd::ExternAddr(a, b) => { ... current_cmds.push(BackBodyCmd::ExternAddr(a, b)); }
BackCmd::CreateBlock(a) => current_cmds.push(BackBodyCmd::CreateBlock(a)),
BackCmd::Alias(a, b) => current_cmds.push(BackBodyCmd::Alias(a, b)),
BackCmd::Ineg(a, b, c) => current_cmds.push(BackBodyCmd::Ineg(a, b, c)),
BackCmd::Iadd(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Iadd(a, b, c, d, e)),
BackCmd::Band(a, b, c, d) => current_cmds.push(BackBodyCmd::Band(a, b, c, d)),
BackCmd::IcmpEq(a, b, c, d) => current_cmds.push(BackBodyCmd::IcmpEq(a, b, c, d)),
BackCmd::FCmpEq(a, b, c, d) => current_cmds.push(BackBodyCmd::FCmpEq(a, b, c, d)),
BackCmd::Bitcast(a, b, c) => current_cmds.push(BackBodyCmd::Bitcast(a, b, c)),
BackCmd::LoadInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::LoadInfo(a, b, c, d)),
BackCmd::CallValueDirect(a, b, c, d, e) => current_cmds.push(BackBodyCmd::CallValueDirect(a, b, c, d, e)),
BackCmd::Jump(a, b) => current_cmds.push(BackBodyCmd::Jump(a, b)),
// ... etc for each body command arm
```

**After** (each arm wraps in sub-enum constructor):
```rust
BackCmd::DataAddr(a, b) => { ... current_cmds.push(BackBodyCmd::Address(AddressOp::DataAddr(a, b))); }
BackCmd::FuncAddr(a, b) => { ... current_cmds.push(BackBodyCmd::Address(AddressOp::FuncAddr(a, b))); }
BackCmd::ExternAddr(a, b) => { ... current_cmds.push(BackBodyCmd::Address(AddressOp::ExternAddr(a, b))); }
// ... (interleaving decl-handling arms — CreateSig, DeclareData, etc., unchanged)

// ── CFG ────
BackCmd::CreateBlock(a) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::CreateBlock(a))),
BackCmd::SwitchToBlock(a) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::SwitchToBlock(a))),
BackCmd::SealBlock(a) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::SealBlock(a))),
BackCmd::BindEntryParams(a, b) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::BindEntryParams(a, b))),
BackCmd::AppendBlockParam(a, b, c) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::AppendBlockParam(a, b, c))),
BackCmd::AppendVecBlockParam(a, b, c) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::AppendVecBlockParam(a, b, c))),
BackCmd::CreateStackSlot(a, b, c) => current_cmds.push(BackBodyCmd::Cfg(CfgOp::CreateStackSlot(a, b, c))),

// ── Aliases / StackAddr / Constants (Other, Address, Const) ────
BackCmd::StackAddr(a, b) => current_cmds.push(BackBodyCmd::Address(AddressOp::StackAddr(a, b))),
BackCmd::Alias(a, b) => current_cmds.push(BackBodyCmd::Other(OtherOp::Alias(a, b))),
BackCmd::ConstInt(a, b, c) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstInt(a, b, c))),
BackCmd::ConstFloat(a, b, c) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstFloat(a, b, c))),
BackCmd::ConstBool(a, b) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstBool(a, b))),
BackCmd::ConstNull(a) => current_cmds.push(BackBodyCmd::Const(ConstOp::ConstNull(a))),

// ── Scalar Unary ────
BackCmd::Ineg(a, b, c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Ineg(a, b, c))),
BackCmd::Fneg(a, b, c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Fneg(a, b, c))),
BackCmd::Bnot(a, b, c) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::Bnot(a, b, c))),
BackCmd::BoolNot(a, b) => current_cmds.push(BackBodyCmd::Unary(ScalarUnaryOp::BoolNot(a, b))),

// ── Intrinsics ────
BackCmd::Popcount(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Popcount(a, b, c))),
BackCmd::Clz(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Clz(a, b, c))),
BackCmd::Ctz(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Ctz(a, b, c))),
BackCmd::Bswap(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Bswap(a, b, c))),
BackCmd::Sqrt(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Sqrt(a, b, c))),
BackCmd::Abs(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Abs(a, b, c))),
BackCmd::Floor(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Floor(a, b, c))),
BackCmd::Ceil(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Ceil(a, b, c))),
BackCmd::TruncFloat(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::TruncFloat(a, b, c))),
BackCmd::Round(a, b, c) => current_cmds.push(BackBodyCmd::Intrinsic(IntrinsicOp::Round(a, b, c))),

// ── Integer Binary ────
BackCmd::Iadd(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Iadd(a, b, c, d, e))),
BackCmd::Isub(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Isub(a, b, c, d, e))),
BackCmd::Imul(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Imul(a, b, c, d, e))),
BackCmd::Sdiv(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Sdiv(a, b, c, d, e))),
BackCmd::Udiv(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Udiv(a, b, c, d, e))),
BackCmd::Srem(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Srem(a, b, c, d, e))),
BackCmd::Urem(a, b, c, d, e) => current_cmds.push(BackBodyCmd::IntBinary(IntBinaryOp::Urem(a, b, c, d, e))),

// ── Float Binary ────
BackCmd::Fadd(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fadd(a, b, c, d, e))),
BackCmd::Fsub(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fsub(a, b, c, d, e))),
BackCmd::Fmul(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fmul(a, b, c, d, e))),
BackCmd::Fdiv(a, b, c, d, e) => current_cmds.push(BackBodyCmd::FloatBinary(FloatBinaryOp::Fdiv(a, b, c, d, e))),

// ── Bitwise ────
BackCmd::Band(a, b, c, d) => current_cmds.push(BackBodyCmd::Bitwise(BitwiseOp::Band(a, b, c, d))),
BackCmd::Bor(a, b, c, d) => current_cmds.push(BackBodyCmd::Bitwise(BitwiseOp::Bor(a, b, c, d))),
BackCmd::Bxor(a, b, c, d) => current_cmds.push(BackBodyCmd::Bitwise(BitwiseOp::Bxor(a, b, c, d))),

// ── Shifts ────
BackCmd::Ishl(a, b, c, d) => current_cmds.push(BackBodyCmd::Shift(ShiftOp::Ishl(a, b, c, d))),
BackCmd::Ushr(a, b, c, d) => current_cmds.push(BackBodyCmd::Shift(ShiftOp::Ushr(a, b, c, d))),
BackCmd::Sshr(a, b, c, d) => current_cmds.push(BackBodyCmd::Shift(ShiftOp::Sshr(a, b, c, d))),

// ── Rotates ────
BackCmd::Rotl(a, b, c, d) => current_cmds.push(BackBodyCmd::Rotate(RotateOp::Rotl(a, b, c, d))),
BackCmd::Rotr(a, b, c, d) => current_cmds.push(BackBodyCmd::Rotate(RotateOp::Rotr(a, b, c, d))),

// ── Comparisons ────
BackCmd::IcmpEq(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::IcmpEq(a, b, c, d))),
BackCmd::IcmpNe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::IcmpNe(a, b, c, d))),
// ...(4 signed, 4 unsigned, 6 float — same pattern)
BackCmd::FCmpGe(a, b, c, d) => current_cmds.push(BackBodyCmd::Compare(CompareOp::FCmpGe(a, b, c, d))),

// ── Casts ────
BackCmd::Bitcast(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Bitcast(a, b, c))),
BackCmd::Ireduce(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Ireduce(a, b, c))),
BackCmd::Sextend(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::Sextend(a, b, c))),
// ...(3 more extend, 2 float convert, 4 float/int convert — same pattern)
BackCmd::FToU(a, b, c) => current_cmds.push(BackBodyCmd::Cast(CastOp::FToU(a, b, c))),

// ── Pointer ────
BackCmd::PtrAdd(a, b, c) => current_cmds.push(BackBodyCmd::Ptr(PtrOp::PtrAdd(a, b, c))),
BackCmd::PtrOffset(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Ptr(PtrOp::PtrOffset(a, b, c, d, e))),

// ── Memory ────
BackCmd::LoadInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::LoadInfo(a, b, c, d))),
BackCmd::StoreInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::StoreInfo(a, b, c, d))),
BackCmd::AtomicLoad(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicLoad(a, b, c, d, e))),
BackCmd::AtomicStore(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicStore(a, b, c, d, e))),
BackCmd::AtomicRmw(a, b, c, d, e, f, g) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicRmw(a, b, c, d, e, f, g))),
BackCmd::AtomicCas(a, b, c, d, e, f, g) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicCas(a, b, c, d, e, f, g))),
BackCmd::AtomicFence(a) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::AtomicFence(a))),
BackCmd::Memcpy(a, b, c) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::Memcpy(a, b, c))),
BackCmd::Memset(a, b, c) => current_cmds.push(BackBodyCmd::Memory(MemoryOp::Memset(a, b, c))),

// ── Singletons (Other) ────
BackCmd::Select(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Other(OtherOp::Select(a, b, c, d, e))),
BackCmd::Fma(a, b, c, d, e, f) => current_cmds.push(BackBodyCmd::Other(OtherOp::Fma(a, b, c, d, e, f))),

// ── Vector ────
BackCmd::VecSplat(a, b, c) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecSplat(a, b, c))),
BackCmd::VecIcmpEq(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecIcmpEq(a, b, c, d))),
// ...(9 more VecCompare ops)
BackCmd::VecUIcmpGe(a, b, c, d) => current_cmds.push(BackBodyCmd::VecCompare(VecCompareOp::VecUIcmpGe(a, b, c, d))),
BackCmd::VecSelect(a, b, c, d, e) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecSelect(a, b, c, d, e))),
BackCmd::VecMaskNot(a, b, c) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecMaskNot(a, b, c))),
BackCmd::VecMaskAnd(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecMaskAnd(a, b, c, d))),
BackCmd::VecMaskOr(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecMaskOr(a, b, c, d))),
BackCmd::VecIadd(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecIadd(a, b, c, d))),
BackCmd::VecIsub(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecIsub(a, b, c, d))),
BackCmd::VecImul(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecImul(a, b, c, d))),
BackCmd::VecBand(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecBand(a, b, c, d))),
BackCmd::VecBor(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecBor(a, b, c, d))),
BackCmd::VecBxor(a, b, c, d) => current_cmds.push(BackBodyCmd::VecBinary(VecBinaryOp::VecBxor(a, b, c, d))),
BackCmd::VecLoadInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::VecMemory(VecMemoryOp::VecLoadInfo(a, b, c, d))),
BackCmd::VecStoreInfo(a, b, c, d) => current_cmds.push(BackBodyCmd::VecMemory(VecMemoryOp::VecStoreInfo(a, b, c, d))),
BackCmd::VecInsertLane(a, b, c, d, e) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecInsertLane(a, b, c, d, e))),
BackCmd::VecExtractLane(a, b, c, d) => current_cmds.push(BackBodyCmd::VecUnary(VecUnaryOp::VecExtractLane(a, b, c, d))),

// ── Call ────
BackCmd::CallValueDirect(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Call(CallOp::CallValueDirect(a, b, c, d, e))),
BackCmd::CallStmtDirect(a, b, c) => current_cmds.push(BackBodyCmd::Call(CallOp::CallStmtDirect(a, b, c))),
BackCmd::CallValueExtern(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Call(CallOp::CallValueExtern(a, b, c, d, e))),
BackCmd::CallStmtExtern(a, b, c) => current_cmds.push(BackBodyCmd::Call(CallOp::CallStmtExtern(a, b, c))),
BackCmd::CallValueIndirect(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Call(CallOp::CallValueIndirect(a, b, c, d, e))),
BackCmd::CallStmtIndirect(a, b, c) => current_cmds.push(BackBodyCmd::Call(CallOp::CallStmtIndirect(a, b, c))),

// ── Control Flow ────
BackCmd::Jump(a, b) => current_cmds.push(BackBodyCmd::Control(ControlOp::Jump(a, b))),
BackCmd::BrIf(a, b, c, d, e) => current_cmds.push(BackBodyCmd::Control(ControlOp::BrIf(a, b, c, d, e))),
BackCmd::SwitchInt(a, b, c, d) => current_cmds.push(BackBodyCmd::Control(ControlOp::SwitchInt(a, b, c, d))),
BackCmd::ReturnVoid => current_cmds.push(BackBodyCmd::Control(ControlOp::ReturnVoid)),
BackCmd::ReturnValue(a) => current_cmds.push(BackBodyCmd::Control(ControlOp::ReturnValue(a))),
BackCmd::Trap => current_cmds.push(BackBodyCmd::Control(ControlOp::Trap)),
```

**Quirks/notes**:
- The order of arms in the match can follow the existing flat order, or can be reorganized by sub-enum group. Reorganizing by group is clearer. The code will be ~120 lines (one per body variant) as before, but with the double-qualified constructor name.
- Arms for `BackCmd::DataAddr`, `BackCmd::FuncAddr`, `BackCmd::ExternAddr` (at lines 654—666) keep their existing error-checking bodies — only the `push()` argument changes.
- **DO NOT use a wildcard arm** — the match must remain exhaustive to catch new `BackCmd` variants at compile time.

---

#### Edit block 4: Rewrite `lower_cmd()` (lines 1498—2101)

**Goal**: Replace the single flat 600-line match with a dispatch match + 21 handler methods. The existing range 1498—2101 becomes:

1. A short dispatch match `lower_cmd()` (lines 1498—~1525)
2. Then 21 new per-sub-enum handler methods (lines ~1526—2101)

**Before** (lines 1498—2101):
```rust
fn lower_cmd(&mut self, cmd: &BackBodyCmd) -> Result<(), LalinError> {
    match cmd {
        BackBodyCmd::CreateBlock(id) => { /* ~13 lines */ }
        BackBodyCmd::SwitchToBlock(id) => { /* ~5 lines */ }
        BackBodyCmd::SealBlock(id) => { /* ~5 lines */ }
        // ... ~90 more arms, ~600 lines total ...
        BackBodyCmd::Trap => { /* ~3 lines */ }
    }
}
```

**After** — Step A: Replace `lower_cmd()` with dispatch match (lines 1498—1523):
```rust
fn lower_cmd(&mut self, cmd: &BackBodyCmd) -> Result<(), LalinError> {
    match cmd {
        BackBodyCmd::Cfg(op) => self.lower_cfg(op),
        BackBodyCmd::Address(op) => self.lower_address(op),
        BackBodyCmd::Const(op) => self.lower_const(op),
        BackBodyCmd::Unary(op) => self.lower_unary(op),
        BackBodyCmd::Intrinsic(op) => self.lower_intrinsic(op),
        BackBodyCmd::IntBinary(op) => self.lower_int_binary(op),
        BackBodyCmd::FloatBinary(op) => self.lower_float_binary(op),
        BackBodyCmd::Bitwise(op) => self.lower_bitwise(op),
        BackBodyCmd::Shift(op) => self.lower_shift(op),
        BackBodyCmd::Rotate(op) => self.lower_rotate(op),
        BackBodyCmd::Compare(op) => self.lower_compare(op),
        BackBodyCmd::Cast(op) => self.lower_cast(op),
        BackBodyCmd::Ptr(op) => self.lower_ptr(op),
        BackBodyCmd::Memory(op) => self.lower_memory(op),
        BackBodyCmd::Call(op) => self.lower_call(op),
        BackBodyCmd::Control(op) => self.lower_control(op),
        BackBodyCmd::VecUnary(op) => self.lower_vec_unary(op),
        BackBodyCmd::VecBinary(op) => self.lower_vec_binary(op),
        BackBodyCmd::VecCompare(op) => self.lower_vec_compare(op),
        BackBodyCmd::VecMemory(op) => self.lower_vec_memory(op),
        BackBodyCmd::Other(op) => self.lower_other(op),
    }
}
```

**After** — Step B: Insert 21 handler methods after the dispatch match, before `fn bind_binop` (which starts at line 2105 post-migration). Each handler method takes a reference to its sub-enum type and matches on it, with the original lowering logic from the old flat match.

Here is the content sketch for each handler, with the line count of lowering logic to extract from the flat match:

| Handler | Sub-enum variants | Lines to extract from old lower_cmd | Notes |
|---|---|---|---|
| `lower_cfg(&mut self, op: &CfgOp)` | 7 | 1500—1582 (CreateBlock, SwitchToBlock, SealBlock, BindEntryParams, AppendBlockParam, AppendVecBlockParam, CreateStackSlot) | Plus SwitchInt from 1521—1550 |
| `lower_address(&mut self, op: &AddressOp)` | 4 | 1607—1642 (StackAddr, DataAddr, FuncAddr, ExternAddr) | |
| `lower_const(&mut self, op: &ConstOp)` | 4 | 1643—1658 (ConstInt, ConstFloat, ConstBool, ConstNull) | |
| `lower_unary(&mut self, op: &ScalarUnaryOp)` | 4 | 1659—1679 (Ineg, Fneg, Bnot, BoolNot) | BoolNot is special (2 fields, icmp_imm + select) |
| `lower_intrinsic(&mut self, op: &IntrinsicOp)` | 10 | 1680—1732 (Popcount..Round) | Abs has type-dispatch (fabs vs iabs) |
| `lower_int_binary(&mut self, op: &IntBinaryOp)` | 7 | 1733—1735, 1739—1743 | All via bind_binop (semantics ignored) |
| `lower_float_binary(&mut self, op: &FloatBinaryOp)` | 4 | 1736—1738, 1741 | All via bind_binop (semantics ignored) |
| `lower_bitwise(&mut self, op: &BitwiseOp)` | 3 | 1744—1746 | All via bind_binop |
| `lower_shift(&mut self, op: &ShiftOp)` | 3 | 1747—1749 | All via bind_binop |
| `lower_rotate(&mut self, op: &RotateOp)` | 2 | 1750—1751 | All via bind_binop |
| `lower_compare(&mut self, op: &CompareOp)` | 16 | 1752—1767 | 10 int → bind_icmp, 6 float → bind_fcmp |
| `lower_cast(&mut self, op: &CastOp)` | 10 | 1768—1819 | Each calls a specific CLIF builder method |
| `lower_ptr(&mut self, op: &PtrOp)` | 2 | 1820—1856 (PtrAdd, PtrOffset) | |
| `lower_memory(&mut self, op: &MemoryOp)` | 9 | 1857—1995 (LoadInfo..Memset) | Atomic ops have SeqCst matching |
| `lower_call(&mut self, op: &CallOp)` | 6 | 2039—2062 (CallValueDirect..CallStmtIndirect) | Dispatch to existing call_direct/call_extern helpers |
| `lower_control(&mut self, op: &ControlOp)` | 6 | 1521—1550 (SwitchInt moved here), 2063—2101 (Jump, BrIf, ReturnVoid, ReturnValue, Trap) | SwitchInt was at 1521—1550 in old flat match |
| `lower_vec_unary(&mut self, op: &VecUnaryOp)` | 5 | 1996—2013 (VecSplat), 2027—2038 (VecSelect), 2039—2041 (VecMaskNot), VecInsertLane, VecExtractLane | VecSelect has float-safety check |
| `lower_vec_binary(&mut self, op: &VecBinaryOp)` | 8 | 2042—2054 (VecIadd, VecIsub, VecImul, VecBand, VecBor, VecBxor, VecMaskAnd, VecMaskOr) | All via bind_vec_binop or bind_vec_mask_not |
| `lower_vec_compare(&mut self, op: &VecCompareOp)` | 10 | 2013—2027 (VecIcmpEq..VecUIcmpGe) | All via bind_vec_icmp |
| `lower_vec_memory(&mut self, op: &VecMemoryOp)` | 2 | 2055—2077 (VecLoadInfo, VecStoreInfo) | |
| `lower_other(&mut self, op: &OtherOp)` | 3 | 1597—1601 (Alias), 2078—2095 (Select, Fma) | |

**Critical patterns for each handler**:

- **`lower_cfg`**: Must order operations to match the flat match. `SwitchInt` (a control-flow op) was at lines 1521—1550 in the flat match — move it into `lower_control`, not `lower_cfg`. The CFG ops are: CreateBlock, SwitchToBlock, SealBlock, BindEntryParams, AppendBlockParam, AppendVecBlockParam, CreateStackSlot.

- **`lower_control`**: Gets the 6 control-flow variants (Jump, BrIf, SwitchInt, ReturnVoid, ReturnValue, Trap). SwitchInt's match arm was at lines 1521—1550 — move it here.

- **`lower_unary`**: Handle `BoolNot` specially (the 2-field variant that does icmp_imm + bool_value_from_cond). Other three use existing inline logic.

- **`lower_intrinsic`**: Handle `Abs` specially (type-dispatch between `fabs` and `iabs`). Other 9 use the inline `.popcnt()`, `.clz()`, etc. pattern.

- **`lower_int_binary` / `lower_float_binary` / `lower_bitwise` / `lower_shift` / `lower_rotate`**: All dispatch through `self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().XXX(l, r))`. The semantics field (3rd positional arg) is always ignored with `_`. These are the simplest handlers.

- **`lower_compare`**: Must dispatch 10 integer ops to `bind_icmp` and 6 float ops to `bind_fcmp`. Pattern: `CompareOp::IcmpEq(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::Equal, lhs, rhs)`.

- **`lower_cast`**: Each of the 10 cast variants calls a different CLIF builder method. Straightforward extraction of existing code.

- **`lower_memory`**: Atomic variants (AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence) all match on `BackAtomicOrdering::SeqCst` before the existing logic. This pattern must be preserved exactly.

- **`lower_call`**: Dispatches to existing helper methods `self.call_direct()`, `self.call_direct_stmt()`, `self.call_extern()`, `self.call_extern_stmt()`, `self.call_indirect()`, `self.call_indirect_stmt()`. Already cleanly extracted — easy.

- **`lower_vec_select`** (inside `lower_vec_unary`): Preserve the float-type safety check that returns an error for F32/F64 elements.

**All 21 handlers go after the dispatch match, before `fn bind_binop` at line ~2105.**

---

#### Edit block 5: Update error messages referencing `BackBodyCmd` variant names

**What**: Search for error message strings in the `lower_cmd` region (and extracted handlers) that reference old variant names like `"BackCmdVecSelect"`, `"BackCmdAtomicLoad"`, etc., and update them to use the new sub-enum path.

**Locations** (approximate, check during implementation):

| Old string | New string | Line |
|---|---|---|
| `"BackCmdVecSelect on float vector"` | `"BackBodyCmd::VecUnary(VecSelect) on float vector"` | ~2031 |
| `"BackCmdAtomicLoad requires integer/pointer type"` | `"BackBodyCmd::Memory(AtomicLoad) requires integer/pointer type"` | ~1867 |
| `"BackCmdAtomicStore requires integer/pointer type"` | `"BackBodyCmd::Memory(AtomicStore) requires integer/pointer type"` | ~1881 |
| `"BackCmdAtomicRmw op"` | keep as-is or use sub-enum path | ~1899 |
| `"BackCmdAtomicCas requires integer/pointer type"` | `"BackBodyCmd::Memory(AtomicCas) requires integer/pointer type"` | ~1915 |
| `"BackCmdMemcpy destination"` | `"BackBodyCmd::Memory(Memcpy) destination"` | ~1935 |
| `"BackCmdMemset destination"` | `"BackBodyCmd::Memory(Memset) destination"` | ~1945 |
| `"BackCmdVecLoadInfo addr"` | `"BackBodyCmd::VecMemory(VecLoadInfo) addr"` | ~2056 |
| `"BackCmdVecStoreInfo addr"` | `"BackBodyCmd::VecMemory(VecStoreInfo) addr"` | ~2065 |
| `"BackCmdVecExtractLane value"` | `"BackBodyCmd::VecUnary(VecExtractLane) value"` | ~2088 |
| `"BackCmdVecInsertLane vector"` | `"BackBodyCmd::VecUnary(VecInsertLane) vector"` | ~2015 |
| `"BackCmdPtrAdd base"` | `"BackBodyCmd::Ptr(PtrAdd) base"` | ~1827 |
| `"BackCmdPtrAdd byte_offset"` | `"BackBodyCmd::Ptr(PtrAdd) byte_offset"` | ~1828 |
| `"BackCmdPtrOffset base"` | `"BackBodyCmd::Ptr(PtrOffset) base"` | ~1844 |
| `"BackCmdPtrOffset index"` | `"BackBodyCmd::Ptr(PtrOffset) index"` | ~1845 |

---

### Patterns to enforce throughout this file

1. **Derive macros**: All sub-enum types use `#[derive(Clone, Debug, PartialEq, Eq)]` — exactly matching the existing `BackBodyCmd` derive.
2. **Naming conventions**: Sub-enum variant names use existing names (PascalCase, same as `BackCmd` / `BackBodyCmd` flat variant names). Sub-enum type names use PascalCase without `Back` or `Cmd` prefix (e.g., `CfgOp`, `AddressOp`, not `BackCfgOp`).
3. **Handler method naming**: `lower_{sub_enum}` where `{sub_enum}` is the snake_case of the sub-enum type (e.g., `lower_cfg`, `lower_int_binary`, `lower_vec_unary`).
4. **Handler method signature**: All take `&self` (or `&mut self`) and `op: &{SubEnum}` and return `Result<(), LalinError>`.
5. **`BackBodyCmd` variant naming**: Use short names — `Cfg`, `Address`, `Const`, `Unary`, `Intrinsic`, `IntBinary`, `FloatBinary`, `Bitwise`, `Shift`, `Rotate`, `Compare`, `Cast`, `Ptr`, `Memory`, `Call`, `Control`, `VecUnary`, `VecBinary`, `VecCompare`, `VecMemory`, `Other`.
6. **partition() arms**: Keep the original `BackCmd::X =>` arm syntax and only change the `push()` argument. Do not reorganize `partition()` arm order unless it makes the code clearer.
7. **lower_cmd dispatch match**: No wildcard arm. Exhaustiveness is critical.
8. **Error message references to variant names**: Update from `"BackCmd{Variant}"` to `"BackBodyCmd::{SubEnum}({Variant})"` format for consistency.

### Danger zones in this file

1. **The `lower_cmd` dispatch match must be exhaustive** — 21 arms, no wildcard. If a sub-enum variant is added but not dispatched, the compiler catches it.
2. **The `partition()` match arms must not use a wildcard** — the match on `BackCmd` (which remains flat and unchanged) must stay exhaustive.
3. **Address synthesis commands (`StackAddr`, `DataAddr`, `PtrAdd`) emitted by `decode_address()` in `ffi.rs` become `AddressOp::StackAddr`, `AddressOp::DataAddr`, and `PtrOp::PtrAdd`** — they are NOT in `MemoryOp`. This is critical for the `lower()` sequential processing to work correctly.
4. **`BoolNot` has 2 fields** (`BackValId, BackValId`) while `Ineg`/`Fneg`/`Bnot` have 3 (`BackValId, BackScalar, BackValId`). The `lower_unary` handler must match `BoolNot` separately.
5. **`VecMaskNot` is in `VecUnaryOp`** (unary, 3 fields) while `VecMaskAnd`/`VecMaskOr` are in `VecBinaryOp` (binary, 4 fields). The architectural decision deliberately placed `VecMaskNot` in `VecUnaryOp` and `VecMaskAnd`/`VecMaskOr` in `VecBinaryOp`. Double-check this placement.
6. **`SwitchInt` lowering logic was at lines 1521—1550** in the flat match but conceptually belongs in `ControlOp`, not `CfgOp`. Move it to `lower_control`.

---

## Order of Operations

1. **First**: Insert the 21 sub-enum type definitions (edit block 1) — before the existing `BackBodyCmd` definition. This is the most important structural change and everything else depends on it. Compile to verify the types are valid Rust.

2. **Second**: Rewrite `BackBodyCmd` to reference sub-enums (edit block 2). Compile to verify the enum compiles and all old `BackBodyCmd::VariantName` references now fail to compile (confirming they all need updating).

3. **Third**: Rewrite `partition()` body-cmd arms (edit block 3). This is purely mechanical — every `BackCmd::X => current_cmds.push(BackBodyCmd::X(...))` becomes `BackCmd::X => current_cmds.push(BackBodyCmd::Sub(SubEnum::X(...)))`. Can be done with regex find-and-replace. Compile to verify no arm is missing.

4. **Fourth**: Replace `lower_cmd()` with a dispatch match + 21 handler methods (edit block 4). This is the most labor-intensive step. Do one sub-enum at a time:
   a. Write the dispatch match.
   b. Extract the simplest handlers first (`lower_bitwise`, `lower_shift`, `lower_rotate` — these are just `bind_binop` calls).
   c. Then `lower_int_binary`, `lower_float_binary` (also `bind_binop`).
   d. Then `lower_cast`, `lower_const` (inline CLIF calls).
   e. Then `lower_unary`, `lower_intrinsic` (need BoolNot/Abs special cases).
   f. Then `lower_compare` (dispatches to bind_icmp/bind_fcmp).
   g. Then `lower_address`, `lower_cfg`, `lower_ptr`, `lower_memory`, `lower_call`, `lower_control` (complex handlers).
   h. Finally `lower_vec_unary`, `lower_vec_binary`, `lower_vec_compare`, `lower_vec_memory` (vector ops).
   Compile after each handler to catch errors early.

5. **Fifth**: Update error message strings (edit block 5). Grep for all `"BackCmd` in error messages in the lower_cmd region and update to the new naming scheme. Compile and run tests.

6. **Sixth**: Run `cargo build --release` and verify it compiles.

7. **Seventh**: Run the full test suite: `luajit tests/test_back_add_i32.lua` (basic JIT test), then more demanding tests like `luajit tests/test_back_object_emit.lua` and `luajit tests/test_mom_source_to_binary.lua`.

---

## Testing Strategy

Incremental verification:

| Step | Test to run |
|---|---|
| After step 1 (sub-enum types) | `cargo build --release` — should compile. The sub-enum types exist but aren't used yet. |
| After step 2 (BackBodyCmd rewrite) | `cargo build --release` — should **fail to compile** because `partition()` and `lower_cmd()` still reference old flat variants. This confirms the old paths are fully replaced. |
| After step 3 (partition() rewrite) | `cargo build --release` — should compile (if `lower_cmd()` still uses the flat match, it will fail; but `partition()` alone should be checkable with `cargo check`). |
| After step 4 (lower_cmd rewrite) | `cargo build --release` — **must compile cleanly**. First full compilation point. |
| After step 4a (first simple handler) | `cargo check` — verifies basic handler method pattern works. |
| After step 4e (all handlers done) | `cargo build --release` — full compilation. |
| After step 5 (error messages) | `cargo build --release` — must compile. |
| After step 5 | `luajit tests/test_back_add_i32.lua` — basic JIT test. |
| After step 5 | `luajit tests/test_back_object_emit.lua` — object emission test. |
| After step 5 | `luajit tests/test_mom_source_to_binary.lua` — full pipeline test. |
| After step 5 | Run ALL tests: `for t in tests/*.lua; do luajit "$t" || echo "FAILED: $t"; done` |

**Key insight**: Since all tests construct `BackCmd::*` variants and pass them through `BackProgram::partition()`, and the `BackCmd` enum is unchanged, the tests are a functional validation that the transformation preserves semantics. **No tests should require updating.**

---

## Pattern Memo

| # | Pattern | Applicable in |
|---|---|---|
| 1 | All new sub-enums use `#[derive(Clone, Debug, PartialEq, Eq)]` — matching existing `BackBodyCmd` derive | Block 1 |
| 2 | Sub-enum variant fields exactly match the original flat `BackBodyCmd` variant fields (same types, same order) | Blocks 1, 2, 3, 4 |
| 3 | `partition()` body-cmd arms always wrap in `BackBodyCmd::Sub(SubOp::Variant(…))` — never direct `BackBodyCmd::Variant(…)` | Block 3 |
| 4 | `lower_cmd()` has 21 dispatch arms with no wildcard — each arm calls `self.lower_{name}(op)` | Block 4 |
| 5 | Handler methods are named `lower_{sub_enum_snake}` and take `&mut self, op: &{SubEnum}` -> `Result<(), LalinError>` | Block 4 |
| 6 | Error messages use format `"BackBodyCmd::{SubEnum}({Variant}) ..."` | Block 5 |
| 7 | `BoolNot` has 2 fields (no BackScalar) — the only variant with different shape in `ScalarUnaryOp` | Blocks 1, 4 |
| 8 | `Abs` type-dispatch (f32/f64 -> fabs, else -> iabs) preserved inside `lower_intrinsic` | Block 4 |
| 9 | `VecMaskNot` goes in `VecUnaryOp` (unary); `VecMaskAnd`/`VecMaskOr` go in `VecBinaryOp` (binary) | Block 1, 3, 4 |
| 10 | Address synthesis commands (`StackAddr`, `DataAddr`, `PtrAdd`) are in `AddressOp`/`PtrOp`, **never** in `MemoryOp` | Blocks 1, 3, 4 |
| 11 | Compare ops dispatch 10 int → `bind_icmp`, 6 float → `bind_fcmp` — never mixed | Block 4 |
| 12 | Semantics fields (`BackIntSemantics`, `BackFloatSemantics`) are always discarded with `_` in lowering handlers | Block 4 |

## Worker Output

The `mom` CLI binary crash is a pre-existing platform issue (SIGILL — illegal instruction), unrelated to this restructuring.

## Completed

Successfully implemented **Approach A: Nested Schema Sub-Enums** for `BackBodyCmd`. The flat 127-variant enum was replaced with a hierarchy of 21 schema-aligned sub-enums. Changes confined entirely to `src/lib.rs`.

### What was done:

1. **Added 21 new sub-enum types**: `CfgOp`, `AddressOp`, `ConstOp`, `ScalarUnaryOp`, `IntrinsicOp`, `IntBinaryOp`, `FloatBinaryOp`, `BitwiseOp`, `ShiftOp`, `RotateOp`, `CompareOp`, `CastOp`, `PtrOp`, `MemoryOp`, `CallOp`, `ControlOp`, `VecUnaryOp`, `VecBinaryOp`, `VecCompareOp`, `VecMemoryOp`, `OtherOp`

2. **Rewrote `BackBodyCmd`**: From a flat 127-variant enum to a 21-variant nested enum where each variant holds a sub-enum (e.g., `BackBodyCmd::Unary(ScalarUnaryOp)`)

3. **Updated `BackProgram::partition()`**: All 90+ body-command arms now wrap in sub-enum constructors (e.g., `BackBodyCmd::Unary(ScalarUnaryOp::Ineg(...))`)

4. **Refactored `lower_cmd()`**: Split the single 600-line flat match into a 21-arm dispatch match + 21 focused handler methods (`lower_cfg`, `lower_address`, `lower_const`, ..., `lower_other`)

5. **Preserved all semantics**: Non-uniform variant shapes (BoolNot's 2 fields, VecMaskNot's unary arity), type-dispatching (Abs), address synthesis commands staying in AddressOp/PtrOp, BackIntSemantics/BackFloatSemantics fields carried but ignored — all preserved exactly.

### Key design decisions:
- `VecMaskNot` → `VecUnaryOp` (unary), `VecMaskAnd`/`VecMaskOr` → `VecBinaryOp` (binary)
- `SwitchInt` → `ControlOp` (not `CfgOp`)
- Address synthesis commands (`StackAddr`, `DataAddr`, `PtrAdd`) are in `AddressOp`/`PtrOp`, NOT `MemoryOp`
- Hand-written (no macro) for clarity

## Files Changed

- `src/lib.rs` — only file modified

## Tests
- ✅ All 10 Rust unit tests pass
- ✅ `test_back_add_i32.lua` (JIT path)
- ✅ `test_back_object_emit.lua` (object emission)
- ✅ `test_mom_source_to_binary.lua` (full MOM pipeline)
- ✅ `test_parse_typecheck.lua` (parse + typecheck)
- ✅ `test_parse_kernels.lua` (jump-first kernels)
- ✅ `cargo build --release` (clean compile)
