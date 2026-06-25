# Cranelift-First Seam Redesign 
Redesign the wire format and Rust backend from first principles. The Rust side should be a thin, fast layer over Cranelift — consuming wire bytes directly with no expansion pass, no synthetic commands, no sub-tag dispatch. Start from what Cranelift actually needs.
**Started**: 2026-05-18 14:40:55
---

## Scout Output — 2026-05-18 14:42:44

Now I have a complete picture. Let me compile everything.

---

## Files Retrieved

1. **`src/lib.rs`** (lines 1-3245, entire file) — Core Rust backend: Compiler struct, FunctionLowerer, all Cranelift IR lowering, JIT + object emission paths, test suite
2. **`src/ffi.rs`** (lines 1-1629, entire file) — FFI layer: text tape decoder, binary wire decoder (MLBT v3), C exports for LuaJIT
3. **`BACK_WIRE_FORMAT.md`** (entire file) — Binary wire format specification
4. **`lua/lalin/back_command_binary.lua`** (entire file) — Lua-side binary encoder
5. **`lua/lalin/back_jit.lua`** (entire file) — LuaJIT FFI bridge between Lua compiler and Rust backend
6. **`Cargo.toml`** — Cranelift dependencies (6 crates at v0.131.0)

---

## Key Findings

### 1. Cranelift IR Concepts — What CLIF Actually Needs

The Cranelift IR (CLIF) concepts used by Lalin are:

**Functions & Signatures:**
- `Signature` with `params: Vec<AbiParam>` and `returns: Vec<AbiParam>` — each param/return is a `Type`
- `UserFuncName::user(0, id_as_u32)` for naming
- Declared via `module.declare_function(name, linkage, &sig)` → `FuncId`
- Defined via `module.define_function(func_id, &mut ctx)` on a `Context` containing the compiled function

**Blocks:**
- Created by `builder.create_block()` → `Block` (essentially a labeled basic block)
- Have block parameters (SSA phi nodes) via `builder.append_block_param(block, type)`
- Sealed via `builder.seal_block(block)` — once sealed, no more predecessors can be added
- `FunctionBuilder` tracks current block via `builder.switch_to_block(block)`
- Block arguments are `Vec<BlockArg>` passed at jump/brif sites

**Instructions** (all from `builder.ins().*`):
- **Constants**: `iconst(type, i64)`, `f32const(Ieee32)`, `f64const(Ieee64)`
- **Arithmetic**: `iadd`, `isub`, `imul`, `sdiv`, `udiv`, `srem`, `urem`, `ineg`
- **Float**: `fadd`, `fsub`, `fmul`, `fdiv`, `fneg`, `fabs`, `fma`, `sqrt`, `floor`, `ceil`, `trunc`, `nearest`
- **Bitwise**: `band`, `bor`, `bxor`, `bnot`
- **Shift/Rotate**: `ishl`, `ushr`, `sshr`, `rotl`, `rotr`
- **Conversion**: `bitcast`, `ireduce`, `sextend`, `uextend`, `fpromote`, `fdemote`, `fcvt_from_sint`, `fcvt_from_uint`, `fcvt_to_sint`, `fcvt_to_uint`
- **Comparison**: `icmp(IntCC, lhs, rhs)` → returns `b1`, `fcmp(FloatCC, lhs, rhs)` → returns `b1`
- **Intrinsics**: `popcnt`, `clz`, `ctz`, `bswap`, `iabs`
- **Memory**: `load(type, MemFlags, addr, offset)`, `store(MemFlags, value, addr, offset)` — load offset is always 0 in Lalin
- **Atomics**: `atomic_load(type, MemFlags, addr)`, `atomic_store(MemFlags, value, addr)`, `atomic_rmw(type, MemFlags, op, addr, value)`, `atomic_cas(MemFlags, addr, expected, replacement)`, `fence()`
- **Address**: `stack_addr(ptr_type, StackSlot, 0)`, `global_value(ptr_type, GlobalValue)`, `func_addr(ptr_type, FuncRef)`
- **Control**: `jump(block, &[BlockArg])`, `brif(cond, then_block, &[BlockArg], else_block, &[BlockArg])`, `return_(&[Value])`, `trap(TrapCode)`
- **Call**: `call(FuncRef, &[Value])` → returns an `Inst` with results, `call_indirect(SigRef, callee, &[Value])`
- **Vector**: `splat(type, scalar)`, `insertlane(vector, scalar, lane_u8)`, `extractlane(vector, lane_u8)`, `icmp` (on vector types returns vector mask)
- **Select**: `select(cond, then_val, else_val)` — works on `b1` condition

**Values & SSA:**
- `Value` is a handle to an SSA value in Cranelift's DataFlowGraph
- Values are produced by instructions and consumed by subsequent instructions
- Block parameters are also `Value`s
- The `FunctionLowerer` maintains `HashMap<BackValId, Value>` to map Lalin's named values to CLIF values

**Types (Cranelift types used):**
- `types::I8`, `types::I16`, `types::I32`, `types::I64`, `types::F32`, `types::F64`
- `ptr_ty` (from `module.target_config().pointer_type()`) — the pointer type (I64 on 64-bit targets)
- Vector types constructed via `elem_ty.by(lanes)` — e.g., `types::I32.by(4)` gives `I32X4`
- `Type::bits()`, `Type::bytes()`, `Type::lane_type()`, `Type::lane_count()`, `Type::is_vector()`, `Type::is_int()`

**Memory:**
- `MemFlags` — constructed via `MemFlags::new()`, settable flags: `set_notrap()`, `set_aligned()`, `set_can_move()`, `trap_code()` returns `Some(TrapCode)` for checked access
- `StackSlot` — via `builder.create_sized_stack_slot(StackSlotData)` with `StackSlotKind::ExplicitSlot`, size, and alignment shift (log2)
- `GlobalValue` — via `module.declare_data_in_func(data_id, func)` for data segment addresses
- `FuncRef` — via `module.declare_func_in_func(func_id, func)` for function pointers

### 2. Current Rust Backend Structure

**`Compiler<M: Module>`** generic struct (lines ~1546-1605):
```rust
struct Compiler<M: Module> {
    module: M,
    signatures: HashMap<BackSigId, Signature>,
    funcs: HashMap<BackFuncId, FuncDecl>,
    externs: HashMap<BackExternId, ExternDecl>,
    datas: HashMap<BackDataId, DataDecl>,
    bodies: Vec<(BackFuncId, Vec<BackBodyCmd>)>,
}
```

Three-phase compilation: `collect()` → `declare_all()` → `define_all()`

**`FunctionLowerer`** (lines ~1607-2650):
- Has: `builder: &mut FunctionBuilder`, `values: HashMap<BackValId, Value>`, `blocks: HashMap<BackBlockId, Block>`, `stack_slots: HashMap<BackStackSlotId, StackSlot>`
- `lower_cmd()` for the 20 sub-enum dispatch
- Each `lower_*` method is a match on the sub-enum, producing 1-5 Cranelift IR instructions

**State maintained during function lowering:**
- `values` — BackValId → Value mapping
- `blocks` — BackBlockId → Block mapping
- `stack_slots` — BackStackSlotId → StackSlot mapping
- `builder` — the Cranelift FunctionBuilder (owns the current block, DFG, etc.)

### 3. Cranelift Dependencies (Cargo.toml)

```toml
cranelift-codegen = "0.131.0"    # Core IR types (Signature, Value, Block, Inst, Type, MemFlags, etc.)
cranelift-frontend = "0.131.0"   # FunctionBuilder, FunctionBuilderContext, Switch
cranelift-jit = "0.131.0"        # JITModule, JITBuilder — runtime compilation
cranelift-module = "0.131.0"     # Module trait, FuncId, DataId, Linkage, DataDescription
cranelift-object = "0.131.0"     # ObjectModule, ObjectBuilder — object file emission
cranelift-native = "0.131.0"     # Native host ISA detection
```

### 4. What is NOT Needed on the Rust Side

These BackCmd/BackBodyCmd variants are **purely frontend concerns** that could be eliminated from the wire format:

- **`SealBlock`** — sealing is a `FunctionBuilder` constraint (must be done before `finalize()`). Could be implicit: all blocks with no `SwitchToBlock` after their last terminator are sealed at the end, or just seal all blocks after processing.
- **`FinalizeModule`** — just signals end-of-stream. Redundant with buffer end.
- **`BeginFunc`/`FinishFunc`** — these structure the command stream. The Rust side currently uses them to partition commands. With a two-level wire (declarations separate from function bodies), these become unnecessary separators.
- **`BindEntryParams`** — currently binds function signature params to block params on the entry block. Could be implicit: entry block's first N block params are the function params.
- **`CreateStackSlot`** — could be implicit (frontend knows the stack layout when lowering).

**The key insight**: The current `BackCmd` list mixes module-level declarations and function body commands in a single linear stream. After `BackProgram::partition()`, they're separated into `BackDeclCmd` and per-function `BackBodyCmd`. The wire format could be restructured to separate these levels directly.

### 5. Phase Boundaries

**Module-level** (no function in progress):
- `CreateSig`, `DeclareData`, `DataInit*`, `DeclareFunc*`, `DeclareFuncExtern`
- `BeginFunc` / `FinishFunc` / `FinalizeModule` — structural markers

**Function-level** (between BeginFunc and FinishFunc):
- `CreateBlock`, `SwitchToBlock`, `SealBlock`, `BindEntryParams`, `AppendBlockParam`, `CreateStackSlot`
- All value/operation commands: `Alias`, `Const*`, `Iadd`, `Band`, `LoadInfo`, `Jump`, `BrIf`, `Return*`, etc.

**State transitions in Rust:**
```
Compiler::collect() reads BackDeclCmd[] and stores bodies as (BackFuncId, BackBodyCmd[])[]
  ↓
Compiler::declare_all() registers all functions/externs/datas with the Module
  ↓
Compiler::define_all() iterates bodies, for each:
  → make_context() → FunctionBuilder new
  → FunctionLowerer::lower(body_cmds)  ← all per-func translation
  → builder.seal_all_blocks() + finalize()
  → module.define_function(func_id, &mut ctx)
```

### 6. Object Emission Path vs JIT Path

Differences are minimal:

| Aspect | JIT | Object |
|--------|-----|--------|
| Module type | `JITModule` | `ObjectModule` |
| Builder | `JITBuilder::with_isa(isa, libcall_names)` | `ObjectBuilder::new(isa, module_name, libcall_names)` |
| ISA flags | `is_pic = false` (default) | `is_pic = true` |
| Finalization | `module.finalize_definitions()` | `module.finish()` → `product.emit()` |
| Output | `*const u8` function pointers | `Vec<u8>` ELF/Mach-O bytes |

**Both use identical lowering code** — the same `FunctionLowerer`, same `BackBodyCmd` processing, same Cranelift IR construction. The difference is only in how the module is finalized and what form the output takes.

**Additional info needed for object emission**: The module name string (for the `.o` file's section naming). That's it.

### 7. What BackCmd Variants Carry Extra Data Cranelift Doesn't Use

**`BackIntSemantics` (overflow + exact)** — Cranelift's integer arithmetic instructions (`iadd`, `isub`, `imul`) have no overflow/exact tracking. These semantics are Lalin-level annotations that map to no CLIF attributes. Currently **discarded** in `lower_int_binary` (all match arms use `_` or ignore the semantics parameter).

**`BackMemoryInfo`** — carries rich metadata:
- `BackAccessId` — a name/anchor string — **never used by Cranelift**
- `BackAlignment` — maps to `MemFlags::set_aligned()` only if alignment >= natural alignment
- `BackDereference` — used internally in Rust to decide `set_notrap()` — not a Cranelift concept
- `BackTrap` — maps to `notrap` or default heap check
- `BackMotion` — maps to `set_can_move()`
- `BackAccessMode` — **not used at all** by Cranelift (no readonly flag set in MemFlags)

**`BackAccessId` (in BackMemoryInfo)** — a string name for the access pattern ident in the type system. Sent across the wire and decoded on the Rust side, but **never stored or used** in lowering. It's purely for frontend bookkeeping.

**`BackFloatSemantics`** — `Strict` vs `FastMath`. Currently **discarded**. Cranelift's float ops have no fast-math flag.

**BackSwitchCase::raw (string parsing)** — every case value is parsed from string on the Rust side. The Rust side re-parses what was already an integer in the Lua compiler. This is a wire overhead that could be avoided by sending raw u64s.

**DataInit strings** — integer/float literal strings are parsed on the Rust side for data initialization. These could be raw bytes.

### 8. Sub-Enum Mapping to Cranelift

The sub-enums map **almost perfectly** to Cranelift instruction categories, but with some gaps:

| Sub-enum | Cranelift fit | Issues |
|----------|--------------|--------|
| `IntBinaryOp` (7 ops) | 1:1 — each has a `b.ins().*` method | semantic params ignored |
| `FloatBinaryOp` (4 ops) | 1:1 | semantic params ignored |
| `BitwiseOp` (3 ops) | 1:1 | — |
| `ShiftOp` (3 ops) | 1:1 | — |
| `RotateOp` (2 ops) | 1:1 | — |
| `CompareOp` (16 ops) | 1:1 → maps to IntCC/FloatCC enum | — |
| `CastOp` (10 ops) | 1:1 | — |
| `ScalarUnaryOp` (4 ops) | 1:1 | BoolNot is composite (icmp_imm + select) |
| `IntrinsicOp` (10 ops) | 1:1 except Abs (merged fabs/iabs) | — |
| `MemoryOp` (9 ops) | 1:1 for loads/stores/atomics; memcpy/memset via libcalls | — |
| `PtrOp` (2 ops) | PtrAdd = iadd; PtrOffset = composite (imul + iadd) | — |
| `AddressOp` (4 ops) | 1:1 | — |
| `CallOp` (6 variants) | 1:1 | — |
| `ControlOp` (6 variants) | 1:1 | SwitchInt uses `cranelift_frontend::Switch` |
| `CfgOp` (7 variants) | 1:1 | — |
| `VecBinaryOp` (8 ops) | 1:1 (same as scalar) | — |
| `VecCompareOp` (10 ops) | 1:1 (same as scalar icmp) | — |
| `VecMemoryOp` (2 ops) | 1:1 | — |
| `VecUnaryOp` (5 ops) | 1:1 | VecSelect is composite (band/bnot/bor) |
| `OtherOp` (3 ops) | 1:1 | Alias = HashMap insert |

**Verdict**: The sub-enum split is clean. Each variant maps to 1-3 CLIF instructions. No mismatch significant enough to warrant a different grouping.

### 9. Most Complex `lower_cmd()` Match Arms

By lines of Rust code and Cranelift instructions emitted:

1. **`lower_control` → SwitchInt** (~45 lines) — the most complex: parses case values from strings, deduplicates, builds a `Switch` table, calls `switch.emit()`
2. **`lower_memory`** (~100 lines total across 9 ops) — the largest method due to MemFlags construction, type checking, and 9 different operations
3. **`lower_ptr` → PtrOffset** (~25 lines) — emits 4 Cranelift instructions (iconst, imul, iadd, iadd) plus type checks
4. **`lower_vec_unary` → VecSelect** (~25 lines) — emits band/bnot/band/bor (4 instructions) — the most verbose vector lowering
5. **`lower_vec_memory` → VecLoadInfo/VecStoreInfo** — MemFlags construction doubled

**What makes them complex**:
- Type validation (require_value_type calls add 3-5 lines per operand)
- Non-trivial instruction composition (PtrOffset = imul + iadd; VecSelect = band + bnot + band + bor)
- SwitchInt's string parsing and dedup logic
- MemFlags construction from BackMemoryInfo (alignment calc, notrap logic, mode checks)

### 10. Cranelift's Own IR Encoding

Cranelift **does not have a stable serialization format** for IR. The `Context` and `Function` can be displayed via `.display()`, but there's no binary serialization format. Cranelift's "CLIF" text format (`.display()`) is the only native representation, and it's a debug/development tool, not a serialization ABI.

However, **Cranelift has internal bytecode** — its backend (machinst) works from `VCode` which is a machine-specific intermediate. There's no stable wire format at the CLIF level that we could target directly.

**Implication**: Aligning with Cranelift's internal encoding is not feasible. The wire format must be Lalin-specific.

---

## Observations

### The Current Architecture Has Two Expansions

Looking at the data flow from Lua to Cranelift:

1. **Lua lowering** (`tree_to_back`): Lalin source → `BackProgram` ASDL (flattened command list)
2. **Binary encoding** (`back_command_binary.lua`): `BackProgram` → wire bytes
3. **Binary decoding** (`ffi.rs`): wire bytes → `Vec<BackCmd>` (the Rust ASDL types)
4. **Partitioning** (`BackProgram::partition`): `Vec<BackCmd>` → `BackProgram` (separated decls + bodies)
5. **Lowering** (`FunctionLowerer`): `BackBodyCmd` → Cranelift IR

Steps 2, 3, and part of 4 are pure overhead — they exist only for the FFI boundary. The Rust ASDL types (`BackCmd`, `BackBodyCmd`, sub-enums) are an **expansion** that mirrors the Lua ASDL types. They're materialized on the Rust side only to be consumed by `lower_cmd()`.

### The Wire Format Is Already Close to Cranelift-Native

The binary wire format's commands directly mirror Cranelift instructions:
- `CmdIntBinary(Add, I32)` → `b.ins().iadd(l, r)`
- `CmdCast(Sextend, I64, v)` → `b.ins().sextend(I64, v)`
- `CmdJump(dest, args)` → `b.ins().jump(block, &args)`

**The gap** between wire command and Cranelift instruction is already small (1:1 or 1:few). This means:

### Minimal Rust Backend Vision

The Rust side could be radically simplified:
- **No `BackCmd`/`BackBodyCmd` Rust enum** — consume wire bytes directly in a streaming fashion
- **No `BackProgram::partition()`** — the two-level structure (decls separate from bodies) could be baked into the wire format: first all module-level declarations, then for each function: header + body commands
- **No sub-enum types** — just a flat function `fn lower_tag(tag: u32, slots: &[u32], pool: &[String]) -> Result<(), Error>` that matches on tag and emits Cranelift IR directly
- **No string parsing for constants** — accept raw u64/u128 from wire, pass directly to `iconst()`
- **No `BackValId` string mapping** — use integer indices directly as value handles (pool indices are already integers)

### What Would Change Under a Cranelift-First Wire Format

1. **Remove SealBlock, FinalizeModule** — handled implicitly
2. **Remove BindEntryParams** — first N block params are function params on the entry block
3. **Separate declarations + function bodies at wire level** — module-global data first, then function streams
4. **Replace string IDs with u32 indices** — the pool could be a `Vec<u32>` of typed ID slots, not strings
5. **Remove BackIntSemantics, BackFloatSemantics from wire** — Cranelift doesn't use them
6. **Remove BackAccessId** — never used by Cranelift
7. **Simplify BackMemoryInfo to just MemFlags-equivalent** — Cranelift only uses: notrap, aligned, can_move
8. **Send raw u64/u128 for case values, not strings** — eliminate switch case string parsing

### The Real Bottleneck Today

The current bottleneck is **not the wire format** — it's the **Rust enum matching**: 60+ `BackCmd` variants → `partition()` (20+ matches) → 20 sub-enums → 200+ match arms in `lower_*` methods. Each match arm unpacks the same fields that were already decoded from the wire. This is a lot of repetitive code.

A truly thin Rust backend would:
1. Decode wire bytes sequentially using a loop over `(tag, slots)`
2. Maintain `HashMap<u32, Value>` for value handles (integer IDs, not strings)
3. Match tag → emit Cranelift instruction. No intermediate ASDL types.
4. Do module-level state (signatures, func declarations) via Cranelift's `Module` API directly

### Cranelift API Surface Summary

The complete set of Cranelift API calls used (grouped by category):

**Module API**: `declare_function`, `declare_data`, `define_function`, `define_data`, `finalize_definitions`, `make_context`, `clear_context`, `declare_data_in_func`, `declare_func_in_func`, `target_config()`, `make_signature`, `get_finalized_function`

**FunctionBuilder**: `create_block`, `switch_to_block`, `seal_block`, `seal_all_blocks`, `finalize`, `append_block_param`, `append_block_params_for_function_params`, `block_params`, `create_sized_stack_slot`, `import_signature`, `call_memcpy`, `call_memset`, `inst_results`

**Instructions** (via `builder.ins()`): `iconst`, `f32const`, `f64const`, `iadd`, `isub`, `imul`, `sdiv`, `udiv`, `srem`, `urem`, `ineg`, `fadd`, `fsub`, `fmul`, `fdiv`, `fneg`, `fabs`, `iabs`, `fma`, `sqrt`, `floor`, `ceil`, `trunc`, `nearest`, `band`, `bor`, `bxor`, `bnot`, `ishl`, `ushr`, `sshr`, `rotl`, `rotr`, `popcnt`, `clz`, `ctz`, `bswap`, `bitcast`, `ireduce`, `sextend`, `uextend`, `fpromote`, `fdemote`, `fcvt_from_sint`, `fcvt_from_uint`, `fcvt_to_sint`, `fcvt_to_uint`, `icmp`, `icmp_imm`, `fcmp`, `load`, `store`, `atomic_load`, `atomic_store`, `atomic_rmw`, `atomic_cas`, `fence`, `stack_addr`, `global_value`, `func_addr`, `jump`, `brif`, `return_`, `trap`, `call`, `call_indirect`, `select`, `splat`, `insertlane`, `extractlane`

**Types**: `types::I8..I64`, `types::F32`, `types::F64`, `By(usize)` for vector types, `Type::bits()`, `Type::bytes()`

**Signatures**: `AbiParam::new(type)`, `Signature { params, returns }`

**MemFlags**: `MemFlags::new()`, `set_notrap()`, `set_aligned()`, `set_can_move()`, `trap_code()`

## Knowledge-builder Output — 2026-05-18 14:54:41

Now I have a thorough understanding. Let me produce the analysis.

---

## What Matters Most for This Problem

The dimensions that matter most for this specific redesign:

1. **MOM-side encoding cost**: MOM writes `CmdEntry` structs into a buffer, then serializes them to wire bytes. The wire format is the serialization of MOM's internal representation. This constrains the design: the format must be *easy to produce from MOM's existing data structures*, not just easy to consume on the Rust side.

2. **Rust-side elimination of ASDL types**: The primary win is removing `BackCmd`/`BackBodyCmd`/sub-enum Rust enums and the `partition()` pass. This means the decoder must emit Cranelift IR directly, not intermediate typed values.

3. **Functional changes, not just structural**: The wire format must only carry what Cranelift actually uses. Every field that is materialized on the Rust side but discarded at lowering is waste in the decoder too.

4. **Error path preservation**: Error messages currently contain string names. Moving to integer handles must not degrade diagnostics.

5. **Test comprehension**: Both Rust tests and Lua tests construct `BackProgram` ASDL values. Moving to byte-focused testing changes the debugging UX.

---

## Non-Obvious Observations

### (a) Ideal wire format shape from Cranelift's perspective

**The ideal format is not a 1:1 encoding of Cranelift IR instructions.** Here's the hidden tension:

Cranelift's `FunctionBuilder` API requires *stateful interaction* — you create blocks, switch to them, append instructions, seal blocks. It's not a data-processing API where you can just emit instructions. The ideal wire format would be:

- **A flat sequence of tags + slots**, exactly as-is (`tag | slot0 | slot1 | ...`), but with the tag namespace *collapsed* to the operation level, not the sub-enum level. I.e., a single tag for `IaddI32` (combining op + scalar type), not a separate tag for `CmdIntBinary` plus sub-tag for `BackIntAdd` plus scalar tag for `I32`.

  **The current format uses 61 command tags + ~10 sub-tag tables + ~13 scalar tags = ~84 distinct numeric values that must be matched.** A Cranelift-first format could use ~60 flat tags (one per distinct Cranelift instruction variant), eliminating sub-tag dispatch entirely. But this means the format has no reuse of shared command structures — each tag carries its own fixed slot layout. For instructions that share slot layout (e.g., all int binaries have `[dst, lhs, rhs]`), this is redundant on the wire but faster to decode (no sub-tag match).

- **The format must carry "structural" commands that Cranelift needs but are not Cranelift IR instructions**: `CreateBlock`, `SwitchToBlock`, `AppendBlockParam`, `CreateStackSlot`, `BindEntryParams`. These are not Cranelift instructions — they're FunctionBuilder state transitions. They *cannot* be implicit if we want streaming decode, because the Rust decoder needs to call `builder.create_block()`, `builder.switch_to_block()`, etc. as it encounters these in the stream.

- **SealBlock CAN be implicit** — after switching away from a block, the previous block can be sealed. Or at the end of a function, seal all blocks. But this requires the decoder to track which blocks have been switched away from, adding decoder state. **BindEntryParams is harder to make implicit** — the decoder needs to know which block params correspond to function params. Could be implicit by position (first N block params of the entry block are the function params), but this requires the function body stream to start with those append_block_param calls.

**Real constraint**: The wire format cannot be *purely* Cranelift IR encoded as bytes. It must carry module-level state (signatures, declarations, data segments) that Cranelift needs *before* function bodies. The cleanest split: a **module-level section** (signatures, func/data/extern declarations) followed by a **function body section** per function (blocks, params, instructions). This is exactly what `Compiler::collect()` + `declare_all()` + `define_all()` already does, just currently re-derived from the flat stream.

### (b) What must flow from frontend that Cranelift cannot derive

These are the *essential* fields — the irreducible minimum:

1. **Signatures**: `(params: Type[], returns: Type[])` per function — Cranelift needs these to declare functions and to generate proper calling convention code. Cannot derive.

2. **Function declarations**: `(func_id, sig_id, visibility)` — Cranelift's `Module::declare_function()` needs these. The function ID (for naming the symbol) and which signature it uses.

3. **Data segments**: `(data_id, size, alignment, initializer bytes)` — Cranelift's `Module::declare_data()` and `define_data()` need these for global data. The init bytes are opaque to Cranelift (just bytes stored in the object file).

4. **Extern function declarations**: `(extern_id, symbol_name, sig_id)` — for `call_indirect` and linking against external symbols.

5. **Function body structure**: Blocks with their types, parameters, and instructions. Cranelift needs the full CFG.

6. **Stack slot declarations**: Size and alignment for each stack slot.

7. **Control flow edges**: Jump targets with block arguments. Cranelift must know the full CFG before finalization.

8. **Types**: Scalar and vector types for every instruction and block parameter. Cranelift's IR is typed.

9. **Address bases**: Which global data, stack slot, or value a memory operation addresses — Cranelift needs `global_value`, `stack_addr`, or the value directly.

10. **Atomic ordering**: Cranelift's atomic instructions need the ordering (SeqCst is the only one currently used).

**What Cranelift can derive but currently receives explicitly**: Integer semantics (overflow/exact), float semantics (strict/fastmath), access IDs (provenance strings), memory access mode (read/write — Cranelift's `store` never sets readonly). These are optimization hints that Cranelift's API doesn't expose.

### (c) Three-phase compilation model implications

The scout correctly identified `collect → declare → define`. Here's the critical observation:

**The three phases are not a Rust-side artifact — they're a Cranelift Module API requirement.** Cranelift's `Module` trait separates function/data *declaration* from *definition*:

```rust
// Phase 1: collect (read all commands, classify into decls vs bodies)
// Phase 2: declare_all()
for each func/data/extern: module.declare_function(...)
// Phase 3: define_all()
for each (func, body): define_function(...)
```

This means the wire format *must* support a two-pass structure even in the most streaming design. The Rust decoder must:
1. First read all module-level declarations (signatures, func/data/extern declarations) — these are CRITICAL and must be processed before any function body
2. Optionally buffer function body bytes, or read them after declarations

**Hidden constraint**: Cranelift's `Module::declare_function()` requires that the *signature* already exists. So declarations must be ordered: all signatures first, then func/data/extern declarations that reference them. This is currently an *implicit ordering invariant* enforced by the linear command stream. A two-level wire format (declarations section, then body section per function) makes this explicit.

**The function body stream CAN be fully streaming** within a function — the decoder reads commands sequentially, calls `builder.create_block()`, `builder.switch_to_block()`, `builder.ins().iadd()`, etc. No buffering needed for the body itself, only the resulting Cranelift `Context`. But the module-level *declarations* must be fully processed before any function body can be defined.

**Tension**: If the wire is two-level (declarations then bodies), the Rust decoder can be:
- Declaration pass: read all module-level commands, call `module.declare_*()` for each
- Per-function pass: for each function body, read its stream from position `X` and emit Cranelift IR

But the MOM producer doesn't have functions separated — it writes everything into a single `MomCmdBuffer`. Separating them requires either:
- A two-buffer approach (one for declarations, one for bodies)
- A position-based scheme where the wire has a function body table (offset + length per func)
- Or just keep the current single-stream approach and let the Rust decoder sort it out

**The current `partition()` is 451 lines because it handles interleaving**. If the producer ensures declarations precede all bodies, partition simplifies dramatically. If the producer structures the buffer with a body index, partition disappears entirely.

### (d) Integer value handles vs string IDs — the real picture

This is subtler than the scout suggests. Here's what's actually happening:

**MOM side**: MOM's `back/ids.mlua` already uses sequential `i32` IDs. `mb_fresh_value()` returns `1, 2, 3, ...` (per function). These are purely numeric — no string materialization during lowering. **MOM would be completely fine with u32 value handles on the wire.** In fact, MOM's `CmdEntry` already stores value IDs as `i32` fields.

**Lua compiler side**: The Lua compiler uses string IDs like `"v1"`, `"v2"`, etc. These go through the Lua encoder (`back_command_binary.lua`) which interns them into the string pool. The Rust decoder reads pool indices and constructs `BackValId(pool[idx].clone())`. With integer handles, the Lua compiler would need to either:
- Generate numeric IDs instead of strings (easy — it already tracks a counter)
- Or have the encoder map string IDs to integers before writing

**Error messages implications**: Currently, when a lowering fails, messages look like:
```
error at function "add1": value "v3" not found
```
With integer handles:
```
error at function id 0: value id 3 not found
```
**This is worse for debuggability** unless the Rust side maintains a reverse mapping from IDs back to their string names. But the scout's whole point is to eliminate string IDs from the Rust side... **This is a real tension**: thin Rust decoder wants raw integers, but debuggable errors want human-readable names.

**Possible resolution**: The string pool could be kept but *not used for identity* — just for debug names. The wire format would carry both a numeric handle AND (optionally) a string name for each value/block. The Rust side would use the numeric handle for lookups but include the string name in error messages. But this requires the pool to exist on the Rust side "just for errors", which adds decoder complexity.

**Alternative**: Errors are rare. The Rust side could collect string names from the pool only when an error occurs (lazy debug info), or the MOM could include a separate debug section with name mappings.

**The real issue**: MOM's current `back/ids.mlua` resets per function. Value IDs are scoped to a function. But the current Rust side uses globally-unique string IDs (`"v1"` in one function doesn't conflict with `"v1"` in another because the Rust side only processes one function at a time). u32 handles scoped per function work naturally with the three-phase model — per-function `HashMap<u32, Value>`.

### (e) MOM encoder consequences — the critical constraint

This is where the most important design constraint lives.

**MOM's current cmd.mlua structure**: MOM writes commands as `CmdEntry` structs (18 x i32 words) into a `MomCmdBuffer`. The struct fields are indexed by Rust-reading position. The wire format serialization happens *after* all commands are written.

**If the wire format changes to eliminate sub-tags (e.g., `CmdIaddI32` instead of `CmdIntBinary + BackIntAdd + I32`), MOM must change every `mb_emit_*` helper to produce a different tag + slot layout.** This is a mechanical change in MOM's cmd.mlua — every emit helper needs its tag constant and slot mapping updated.

**Real constraint**: MOM's `CmdEntry` is currently 18 i32 words with a fixed layout. A Cranelift-first format might have different slot counts per tag — some with 2 slots, some with 7, some with 15. MOM would still use the `CmdEntry` struct but fill only the needed prefix. This is fine — the current code already does this (zeroing unused words).

**The bigger constraint is MOM's dispatch tables**: MOM's `mb_lower_binary()` dispatches on `BinAdd | BinSub | ...` and maps to different wire tags (`BackIntAdd`, `BackFloatAdd`, etc.) with helper fills. If the wire format is a flat tag space (one tag per Cranelift instruction), MOM's dispatch becomes simpler — `BinAdd → CmdIadd` for integers, `CmdFadd` for floats — but the number of cases in MOM's dispatch grows because now there's no sub-tag sharing.

**Hidden implication for MOM**: MOM's compile_module.mlua currently emits commands sequentially into the linear stream. If the wire format splits declarations from bodies (two-level), MOM needs to either:
1. Write all commands to one buffer and have the Rust side figure out the split (current approach, works)
2. Write declarations to one buffer/buffer region, function bodies to another

MOM's `MomCmdBuffer` is a flat array. Two-level requires either two buffers or a post-hoc split. A post-hoc split is complex because MOM's dropping logic doesn't know the partition boundaries.

**The cleanest approach for MOM**: Keep the single linear stream of commands with BeginFunc/FinishFunc markers. The Rust side can use these markers to partition during decode, just like today — but without materializing BackCmd enums. The decoder enters a "declarations" mode until `BeginFunc`, then a "body" mode for each function, tracking the partition naturally in a streaming fashion.

### (f) The lossy encoding question — explicit vs accidental

**The current situation is worse than the scout suggests.** Not only are some fields silently dropped, but they're dropped at *different layers*:

- **BackIntSemantics (overflow/exact)**: Encoded in wire (2 u32 slots per int binary command), decoded into BackIntSemantics struct, passed to lower_int_binary, which matches on the op and **ignores semantics entirely** (wildcard `_` match). So 2 u32 slots on the wire, plus Rust enum allocation, plus match arm — all wasted.

- **BackFloatSemantics (strict/fastmath)**: Same pattern — encoded, decoded, passed to lower_float_binary, **discarded**. 1 u32 slot wasted.

- **BackAccessId**: Encoded in wire (1 pool index per memory command), decoded into BackAccessId(String), **never used in lowering**. The string is allocated and immediately dropped. 10+ memory commands × pool entry bytes wasted.

- **BackDereference (provenance info)**: Encoded as `(deref_kind, deref_bytes)` in every memory command, decoded, **never used in lowering**. 2 u32 slots wasted per memory command.

- **BackAccessMode (read/write/readwrite)**: Encoded and decoded, **never used** (Cranelift's store always writes, load always reads — the mode is intrinsic to the operation, not a flag).

- **BackMotion (can_move)**: Used by Cranelift's MemFlags (set_can_move). This one is actually used.

- **BackAlignment and BackTrap**: Used to construct MemFlags. Essential.

**The redesign should explicitly decide**:

| Field | Should be on wire? | Why |
|-------|-------------------|-----|
| BackIntSemantics | **No** | Cranelift ignores it entirely |
| BackFloatSemantics | **No** | Cranelift ignores it entirely |
| BackAccessId | **No** | Never used by Cranelift; pure frontend bookkeeping |
| BackDereference | **No** | Never used by Cranelift |
| BackAccessMode | **No** | Implicit in load vs store operation |
| BackMotion | **Yes** | Maps to MemFlags::set_can_move() |
| BackAlignment | **Yes** | Maps to MemFlags::set_aligned() |
| BackTrap | **Yes** | Maps to notrap flag |
| Base provenance (value/stack/data) | **Yes** | Cranelift needs stack_addr, global_value, or raw value |
| Byte offset | **Yes** | Cranelift's load/store offset |

**The critical non-obvious point**: If MemFlags is the *only* memory metadata that Cranelift uses, then the wire format should encode MemFlags *directly* — a single u32 with bit flags (notrap=1, aligned=2, can_move=4, readonly=8, trap_code=...). This would replace 8 slots of current memory info with 1 slot. **But** the frontend (both Lua and MOM) must derive these flags from the same type system information it currently encodes as rich structs. The compression happens in the encoding, not in the frontend's work.

### (g) Rust code size implications — estimated breakdown

From the line analysis:

**Current essential code (~1552 lines)**:
- `lower_*` methods: ~996 lines (the actual Cranelift IR emission)
- Helper functions: ~267 lines (MemFlags construction, const lowering, type lookups)
- `Compiler` struct + core methods: ~107 lines (module state, collect core)
- `FunctionLowerer` struct + dispatch: ~74 lines (state, lower_cmd switch)
- `declare_all` + `define_all`: ~108 lines (Cranelift Module API orchestration)

**Current overhead (~1350 lines)**:
- `BackCmd` enum + sub-enum types: ~270 lines
- `BackBodyCmd` enum: ~35 lines
- `partition()`: ~451 lines
- `collect_global_decl_from_decl_cmd`: ~179 lines
- String ID types (`id_type!` macro expansion): ~50 lines
- Extra decoding machinery in ffi.rs that materializes ASDL: ~365 lines (rough estimate)

**In a streaming decoder design**:
- The decoder ~filter loop (read tag, slots, dispatch): ~100 lines
- Tag → Cranelift match arms: ~400 lines (one arm per instruction, ~50 arms × ~8 lines each)
- Module state (Compiler-like struct but simpler): ~80 lines
- Function body streaming state (FunctionLowerer-like): ~60 lines
- Module sub-decode (signatures, declarations): ~100 lines
- Error handling + validation: ~150 lines
- MemFlags construction helpers: ~80 lines
- **Total essential: ~970 lines**

**Reduction**: from ~3244 lines to ~970 lines (lib.rs), a ~70% reduction. But this assumes the decoder lives in `ffi.rs` (replacing the current binary decoder there) and calls lowerers directly, with `lib.rs` drastically simplified or merged.

**However**, the current `lower_*` methods include substantial type validation (e.g., `require_value_type` checks). A streaming decoder would still need these checks. The lowerer code doesn't shrink — it just gets reorganized into tag-match arms.

**Real estimate**: ~1200-1400 lines of Rust (down from 3244). About 55-60% reduction. The big wins are removing partition(), removing BackCmd/BackBodyCmd enums, and removing the sub-enum types. The actual Cranelift emission code stays largely unchanged.

### (h) Test implications

**The Rust-side tests** currently construct `BackProgram` via `BackCmd::Foo(...)` enum variants:
```rust
BackProgram::partition(vec![
    BackCmd::CreateSig(BackSigId::from("sig:add1"), vec![BackScalar::I32], vec![BackScalar::I32]),
    BackCmd::DeclareFuncExport(BackFuncId::from("add1"), BackSigId::from("sig:add1")),
    ...
]).unwrap()
```

If `BackCmd` enum disappears, these tests must construct wire bytes directly:
```rust
let bytes = build_wire_program(&[
    WireCmd::CreateSig(0, &[I32], &[I32]),
    WireCmd::DeclareFuncExport(1, 0),
    ...
]);
```

**The readability impact is severe**: currently readers see named fields (`BackCmd::Iadd(dst, ty, semantics, lhs, rhs)`). With wire bytes, it's `WireCmd::Iadd(3, 4, 5, 6)` — opaque integer indices. A test helper that wraps wire construction in a builder API would help, but that builder API *is the BackCmd enum we're trying to eliminate*.

**The Lua-side tests** (like `test_back_add_i32.lua`) construct BackProgram ASDL values through the `LalinBack` API:
```lua
local program = B.BackProgram({
    B.CmdCreateSig(sig, { B.BackI32, B.BackI32 }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    ...
})
```
These go through the encoder. If the wire format changes, the encoder changes, but the test ASDL construction stays the same — the ASDL types are on the Lua side, not Rust. **The Lua tests are insulated from Rust wire format changes** because they construct BackProgram values and encode them.

**The MOM tests** construct `MomCmdBuffer` content directly via wire helper functions. They're already at the "construct wire bytes" level. A format change just means different tags + slots in the test helpers.

**Real implication**: Rust `#[test]` tests will be the hardest hit. Either they need a builder API (which is the old `BackCmd` enum) or they construct raw bytes (which are unreadable). The pragmatic choice: keep a `build_wire_program()` test helper that looks very much like the current `BackCmd` enum, but only in the test module. This is not a regression — it's just moving the builder from production code to test code.

**Hidden insight**: The Rust tests currently bypass the wire encoding entirely (constructing `BackProgram` directly). A streaming decoder design would force Rust tests to go through the wire, or there'd be two code paths (one for direct `&[WireCmd]` and one for wire bytes). **Two code paths is a maintenance burden and a correctness risk.** Better to have one path: convert test wire representation to bytes, then feed bytes to decoder.

### (i) Implicit invariants that must be preserved

These are the invariants that the current system enforces (mostly through partition(), Cranelift API validation, or implicit ordering):

1. **Functions declared before defined**: `module.declare_function()` must precede `module.define_function()`. In the current system, `declare_all()` processes all declarations, then `define_all()` processes bodies. A streaming decoder must buffer function bodies until declarations are processed, or the wire must be structured with declarations first.

2. **Data declared before initialized**: Same pattern. `declare_data()` before `define_data()`.

3. **Signatures exist before use**: A `DeclareFunc` references a `SigId` that must have been previously created. In the linear command stream, this is satisfied by ordering. A two-level format must ensure the signature declaration precedes its use, or forward-reference them.

4. **Blocks created before referenced**: `builder.create_block()` must precede `builder.switch_to_block()` or any jump to that block. In the linear stream, `CreateBlock` precedes `SwitchToBlock` and jump targets. A streaming decoder must enforce this ordering, or buffer instructions until blocks are created (complexity).

5. **Block parameter counts match at jump sites**: If block L has K parameters, every jump to L must supply exactly K arguments. Cranelift's `append_block_param()` defines the expected count; validation happens at `seal_block()` or `finalize()`. The wire format need not validate this — Cranelift will error.

6. **Block parameter types match at jump sites**: Same as counts — Cranelift validates.

7. **Stack slots created before referenced**: `builder.create_sized_stack_slot()` must precede `builder.ins().stack_addr()` for that slot. Linear stream ordering handles this.

8. **Function-level value scoping**: Value IDs are unique within a function but can repeat across functions. The Rust side currently uses `HashMap<String, Value>` per function — same string doesn't collide across functions because the map is recreated per function. With u32 handles, scoping by function is natural.

9. **Extern function symbol names**: These are actual ELF/linkage symbol names, not internal IDs. They must survive as strings on the Rust side for `module.declare_function()`.

10. **No block is sealed before all predecessors are known**: Cranelift requires `seal_block()` only after all predecessors have been added. The current `SealBlock` command is explicit. If we make it implicit (seal on switch-away), we must track predecessor completeness.

**The trickiest invariant is #4**: streaming decoder must ensure blocks exist before they're jumped to. This is naturally satisfied if `CreateBlock` precedes `Jump` in the command stream, which it *almost always* does in practice, but is not guaranteed by the format. A decoder could buffer jumps and process them after the target block is created, or simply validate the ordering and fail on violation.

### (j) The "thin layer" ideal vs Cranelift's API requirements

**The thin layer vision**: Read tag, read slots, match tag → call one Cranelift API method. No intermediate types, no allocations except Cranelift's own data structures.

**Where this works perfectly**: Most instructions are 1:1 with Cranelift:
- `Iadd(tag=34, dst, lhs, rhs)` → `builder.ins().iadd(lhs_val, rhs_val)`, store result as `dst_val`
- `Jump(tag=54, dest_aux, count)` → `builder.ins().jump(block, &args)`

**Where it breaks down**: Several instructions require *multiple* Cranelift calls:

1. **Constants**: `CmdConst(dst, scalar, lit_tag, lit_lo, lit_hi)` → either `iconst()`, `f32const()`, or `f64const()` depending on scalar type + lit_tag. A match on 3 dimensions. Not 1:1.

2. **PtrOffset**: Currently emits 4 instructions (`iconst` + `imul` + `iadd` + `iadd`). With stream decode, it would emit all four in sequence, which is fine — Cranelift is accumulating into a FunctionBuilder. **No buffering needed.**

3. **VecSelect**: Currently emits 4 instructions (`band` + `bnot` + `band` + `bor`). Same — streaming decode handles this naturally by calling `builder.ins()` four times.

4. **SwitchInt**: Uses `cranelift_frontend::Switch` which requires collecting all cases before `emit()`. This requires **buffering switch cases across commands** — the wire format must convey them together (which it does, via aux data). The `Switch::emit()` call is fully self-contained with the case data in one command. No problem.

5. **LoadInfo/StoreInfo**: MemFlags construction from alignment + trap + motion fields. This requires computing alignment vs natural alignment to decide `set_aligned()`. More complex than bit-extraction, but still stateless.

6. **StackAddr, GlobalValue, FuncAddr**: These compute the address differently — `stack_addr` needs a `StackSlot`, `global_value` needs a `GlobalValue` declared in the function. The decoder needs access to the `module` to call `declare_data_in_func()` for data segment references. **This requires the decoder to have a reference to the Cranelift Module**, not just a FunctionBuilder.

**Where thinness truly conflicts with Cranelift's API**:

- **Block creation must precede usage**: As noted in (i), the decoder must ensure `create_block()` is called before `switch_to_block()`. This is an ordering invariant that the wire producer must satisfy. The decoder can validate but cannot fix violations.

- **FunctionBuilder's borrow semantics**: `builder.ins()` borrows `&mut self` on the FunctionBuilder. You cannot interleave Module API calls with instruction emission within the same function. This is fine — function bodies are self-contained.

- **Function params**: Cranelift's `append_block_params_for_function_params()` is magical convenience. The decoder currently calls this after `BindEntryParams`. If we make entry params implicit, the decoder must still call this or manually append block params matching the function signature. This requires knowing the signature's param types *at the point of function body entry*, which means the decoder must look up the signature from its earlier declaration. **This is the real complication for a streaming decoder**: function bodies reference declarations (signatures, other functions) that were seen earlier. The decoder needs a lookup table from IDs to Cranelift types/refs.

**Verdict**: A streaming decoder IS feasible but MUST maintain state:
- `HashMap<u32, Value>` per function (value handles)
- `HashMap<u32, Block>` per function (block handles)
- `HashMap<u32, StackSlot>` per function (stack slot handles)
- `HashMap<u32, Signature>` per module (signatures)
- `HashMap<u32, FuncId>` per module (function declarations)
- `HashMap<u32, DataId>` per module (data declarations)
- `HashMap<u32, GlobalValue>` per function (data references for `global_value`)
- `HashMap<u32, FuncRef>` per function (func refs for `func_addr` and `call`)

**This state IS the intermediate representation.** It's not ASDL enums, but it's still allocation on the Rust side — HashMaps, Cranelift `Value`s, etc. The "thin layer" is thin in code structure and instruction dispatch, NOT in memory footprint. The Rust side must still track all the Cranelift handles.

**Real constraint**: The Rust side's `HashMap<u32, Value>` with u32 keys is simpler and faster than `HashMap<String, Value>`, but it's still a HashMap. The only way to eliminate it is to make values be Cranelift `Value` indices directly, but Cranelift assigns `Value` handles internally and they're not stable or predictable from the wire format. So some mapping is essential.

---

## Knowledge Gaps

1. **How MOM's `MomCmdBuffer` is currently serialized to wire bytes** — is there a separate `mw_serialize` step, or is each `CmdEntry` written as it's produced? I need to see the MOM wire serialization module to understand what the encoder code change would look like.

2. **What the current MOM tests look like** — do they construct `MomCmdBuffer` directly or go through wire helpers? This affects how much test code changes.

3. **The full `MomBackLowerCtx` struct definition** — what state does MOM's lowerer maintain? This determines how MOM would adapt to a new format. (I saw the struct reference in cmd.mlua but not its definition.)

4. **Cranelift's `append_block_params_for_function_params()`** — does this require the signature to be declared before the function body starts? This affects whether entry block params can be handled implicitly or require explicit signatures.

5. **Whether Cranelift has a `block_params()` method that returns already-created block parameters** — if so, the decoder could avoid tracking block params explicitly.

## Approach-proposer Output — 2026-05-18 15:00:25

Now I have complete understanding. Let me produce the three approaches.

---

### Approach A: "Flatline" — Flat per-Cranelift tags, section-indexed two-level wire, direct-match Rust

**Core idea**: One wire tag per distinct Cranelift IR operation (~90 tags), no sub-tag dispatch, section-indexed two-level wire (section table maps offsets to each function body), and a Rust decoder that reads `(tag, slots)` and calls Cranelift APIs directly from a flat `match` — no BackCmd/BackBodyCmd enums, no partition(), no sub-enum dispatch at any layer.

**Key changes**:

| Layer | What changes |
|-------|--------------|
| Wire structure | Header: `[magic, ver, n_funcs, n_sigs, n_datas, n_externs]` + section table: per-function `[body_offset, body_len]` + Declaration section (sig table, func table, data table, extern table) + Function bodies (contiguous, no markers) |
| Tag space | ~90 flat tags. Each tag has a fixed slot count. Tags encode the operation only; type is a slot. E.g.: `Iadd=1` (3 slots: dst, lhs, rhs — types from operands), `ConstI32=12` (2 slots: dst, value), `ConstF64=14` (3 slots: dst, val_lo, val_hi), `Load=30` (5 slots: dst, memflags, base_tag, base_id, offset), `Call=55` (6 slots: result_tag, dst, sig, target_tag, target_id, n_args + inline args) |
| MemFlags | Single `u32` bitfield slot: bit 0 = `notrap`, bit 1 = `aligned`, bit 2 = `can_move`. MOM computes this from its alignment/trap/motion analysis before encoding. |
| Value handles | `u32` per-function. The Rust decoder maintains `HashMap<u32, Value>` per function body. Function scoping is natural — new HashMap each body. |
| String pool | Only for extern symbol names. Debug names are in an optional trailing section that the Rust decoder reads only on error. |
| CmdTrap, CmdFinishFunc, CmdFinalizeModule | Removed from wire. Trap is implicit (tag `Trap=60` has 0 slots). FinishFunc is implicit — body end. FinalizeModule is implicit — buffer end. |
| SealBlock, BindEntryParams | Removed from wire. Sealing: all blocks sealed at body end. Entry params: first N block params of entry block are function params (N = sig param count). |
| Aux data section | Eliminated. Variable-length data (block args, sig params/results) is inline with count prefix. E.g., Jump: `[tag=50, dest_block, n_args, arg0, arg1, ...]` — all in contiguous slots after tag. |

**Tradeoff**: Optimizes for simplest, fastest Rust decoder (~900-1000 lines, single match, no intermediate types). Sacrifices wire compactness — ~90 tags means the tag table is medium-sized, and inline variable-length data means variable slot counts per command (the Rust decoder reads a count slot, then reads N more slots). MOM must compute MemFlags bitfield before encoding (more frontend work per memory op).

**Risk**: Tag proliferation. Adding a new Cranelift instruction means adding a new tag, a new match arm, and possibly changing MOM's lowering to emit it. The flat tag table must be maintained carefully — no reordering or gaps. Error messages with integer-only handles may be harder to debug — solved by optional debug name section.

**Rough sketch**:

1. **Design the wire header + section table**: `[magic=0x4D4C, ver=4, n_funcs, decls_offset, decls_len, body_table_offset, body_table_len]`. Body table is `n_funcs × [func_id, body_offset, body_len]`.
2. **Define the 90-tag flat table** in a `const TAG_SLOTS: &[u8]` array and a Rust enum `#[repr(u32)] enum WireTag { Iadd=1, IaddWithOverflow=2, Fadd=3, ... }`.
3. **Write the Rust decoder**: `fn decode_module(buf: &[u8], module: &mut M)`. Reads header, reads declaration section (processes sigs, funcs, datas, externs via Cranelift Module API), then iterates body entries and for each: reads body bytes, creates FunctionBuilder, matches tags in a flat loop, seals all blocks, finalizes, defines.
4. **Rewrite MOM's encoder**: Each `mb_emit_*` helper now computes its flat tag directly. `mb_emit_load_info` drops access_id, deref info, mode — instead computes a `memflags = (notrap << 0) | (aligned << 1) | (can_move << 2)` u32. `mb_emit_int_binary` drops overflow/exact semantics. The encoder writes inline-counted block args (not aux-referenced).
5. **Eliminate `NameKind_Lua` encoder** (`back_command_binary.lua`): The Lua compiler's encoder is replaced with a new binary encoder that matches the flat tag format. Since the Lua compiler constructs BackProgram ASDL and passes it through an encoder, the new encoder translates from ASDL to flat tags (same structure as MOM's encoder but in Lua).
6. **Eliminate `ffi.rs` decoder → `BackCmd` expansion**: The old `parse_back_command_binary` that produces `Vec<BackCmd>` is deleted entirely. The new decoder goes directly from wire bytes to Cranelift Module calls.

---

### Approach B: "SchemaDriven" — Compact parametric tags, codegen from single YAML schema, pointer-table Rust decode

**Core idea**: Keep parametric tags (op + scalar_type + memflags as separate slots, ~45 command forms) but DRIVE all code generation from a single YAML schema file. Build.rs generates MOM tag constants, all `mb_cmd_*` and `mb_emit_*` helpers, the Rust tag table (slot counts, type mappings), and the BACK_WIRE_FORMAT.md documentation. The Rust decoder uses a static `fn` pointer table indexed by tag — no match arms to hand-write, no sub-dispatch to hand-roll.

**Key changes**:

| Layer | What changes |
|-------|--------------|
| One source of truth | `/home/cedric/dev/lalin/schema/commands.yaml` — each entry: `{tag, name, slots: [{name, type: u32|scalar|id|memflags|...}], cranelift_op: "iadd"}` |
| Build system | `build.rs` generates: `lua/lalin/mom/tags/mom_tags_gen.mlua` (tag constants), `src/tags_gen.rs` (SCHEDULE: `[(tag, slot_count); N]` + dispatch table), `BACK_WIRE_FORMAT.md` (auto-docs). |
| Tag space | ~45 parametric tags. Sub-tags (like op kinds) are INLINE in the slot array: e.g., `IntBinary=20` has 6 slots: `[dst, op_kind, scalar, lhs, rhs, memflags?]`. The Rust dispatch table maps tag→`fn(&mut Ctx, &[u32])` that reads the op_kind slot and calls the right Cranelift method. |
| MemFlags | Inline as a slot per flag: `[trap_kind, align_kind, align_bytes, motion_kind]` — 4 slots. MOM fills these directly from its type analysis; the Rust decoder converts to Cranelift `MemFlags`. This means the wire is fatter per memory op, but MOM's encoding is trivial (no bitfield computation). |
| Rust dispatch table | Static array `[Option<fn(&mut DecoderCtx, &[u32]) -> Result<()>>; 256]`. Generated by build.rs. Each function is a tiny (~5-10 line) closure that reads slots by position and calls Cranelift APIs. |
| Codegen scope | The schema captures only the tag→slot layout and Cranelift mapping. The Cranelift API call body is still hand-written (the gen can emit parameter extraction, leaving the Cranelift call as a placeholder). |
| Value handles | u32 per-function (`HashMap<u32, Value>`), managed by `DecoderCtx`. Entry params implicit (first N block params are sig params). |
| Aux data | Kept for variable-length data (sig params/results, block args) but encoded more compactly. |

**Tradeoff**: Optimizes for maintenance scalability — adding an instruction means editing one YAML entry and running `make`. Sacrifices wire compactness and per-command decode speed vs Flatline (parametric tags require reading more slots per command, per-slot MemFlags is 4 slots instead of 1). The Rust decoder is slightly slower due to indirect dispatch through function pointers.

**Risk**: Codegen complexity. The build.rs parser/schema handler must be robust and fast. Generated code must be readable for debugging. If the schema → Cranelift mapping is incomplete, the hand-written portions become messy ("half-generated"). The pointer-table dispatch defeats some compiler optimizations (no inline match specialization).

**Rough sketch**:

1. **Design `schema/commands.yaml`**: Each entry:
   ```yaml
   - tag: 4
     name: IntBinary
     slots:
       - {name: dst, type: val_id}
       - {name: op_kind, type: int_op}
       - {name: scalar, type: scalar}
       - {name: lhs, type: val_id}
       - {name: rhs, type: val_id}
     cranelift_op: "iadd"
     description: "Integer binary operation. op_kind selects add/sub/mul/div/rem."
   ```
   Plus metadata for Cranelift type/op mappings (e.g., `int_op: {1: iadd, 2: isub, ...}`).

2. **Write `build.rs` generator**: Reads YAML, produces:
   - Tag constant enum for MOM (`lua/lalin/mom/tags/mom_tags_gen.mlua`)
   - Rust dispatch table + slot count array (`src/tags_gen.rs`)
   - Markdown documentation for `BACK_WIRE_FORMAT.md`
   - Each `mb_cmd_*` helper becomes a simple field-fill identical to the current pattern, but generated.

3. **Rewrite MOM's encoder**: Keep `mb_cmd_*` fillers but tag constants come from generated code. MemFlags encoding is the same per-slot approach as today (no bitfield computation). Move away from 18-word CmdEntry to a struct sized per command variant (less zero-fill overhead).

4. **Write the Rust decoder**: ~50 generated dispatch entries + shared `DecoderCtx` (holds `module: &mut M`, `values: HashMap<u32, Value>`, `blocks: HashMap<u32, Block>`, `builder: &mut FunctionBuilder`). The loop is:
   ```rust
   while pos < buf.len() {
       let tag = read_u32()?;
       let (f, n) = DISPATCH[tag];
       let slots = &buf[pos..pos + n*4];
       f(&mut ctx, slots)?;
       pos += n * 4;
   }
   ```

5. **Generate `BACK_WIRE_FORMAT.md`**: The schema → doc generator produces the complete specification with tag tables, slot layouts, and sub-encoding tables.

---

### Approach C: "ImplicitVM" — Stateful bytecode with position-based SSA addressing

**Core idea**: Replace the explicit command list with a Cranelift-native bytecode where the Rust decoder is a finite-state machine over implicit block structure. The wire encodes function bodies as: block list (each block = [param types][instruction sequence][terminator with successor list]), and values are addressed by their POSITION in the instruction sequence (value `N` is the result of the Nth instruction in the current block, plus block parameters are `param_0, param_1, ...`). No `CreateBlock`/`SwitchToBlock`/`AppendBlockParam` commands — block structure IS the structure of the body section. No `HashMap<u32, Value>` — values are decoded implicitly from Cranelift `Value` handles returned by each instruction emission.

**Key changes**:

| Aspect | Description |
|--------|-------------|
| Module encoding | Simple table format (same as A and B): separate from body sections. Sig table, func table, data table, extern table — fixed-length records. |
| Function body | A single body per function. No begin/end markers. Structure: `[n_blocks]` then for each block `[n_params][param_types...][n_instrs][instrs...][terminator_tag][terminator_data...]`. |
| Value addressing | No `dst` slot on instructions. Each instruction implicitly produces one result value. The value is addressed by `(block_index, instr_index)`. For block parameters: `(block_index, -param_index-1)`. The Rust decoder tracks: for each block, a `Vec<Value>` of instruction results. |
| Block addressing | Blocks are addressed by their index in the block list (0, 1, 2, ...). No `CreateBlock` command needed. The decoder creates blocks in order at the start of function body processing. |
| Implicit block management | The decoder: (1) reads n_blocks, creates all blocks via `builder.create_block()`, (2) reads entry block params, appends to block 0, (3) for each block: reads instruction stream (emitting Cranelift IR as encountered, pushing results onto block's result stack), reads terminator tag, emits terminator (jump/brif/return referencing successor blocks by index). After all blocks processed: `builder.seal_all_blocks()`, `builder.finalize()`. |
| Instruction encoding | Compact opcode space (~50-60 opcodes). Each opcode has fixed slot layout. Most opcodes pop operands from the current block's result stack (by `(block, instr)` reference, or last-N for stack-like). No dst slot. |
| MemFlags | u32 bitfield (same as Approach A). |
| Aux data | Eliminated. Variable-length lists (block args at terminators) are inline-counted. |
| String pool | Only for extern symbol names. |

**Tradeoff**: Optimizes for maximum compactness (~40% fewer bytes than Approach A) and elimination of HashMap value lookups (position-based addressing is O(1) with Vec). Sacrifices MOM encoding simplicity — MOM must compute block indices and instruction positions to reference values, and must order blocks and instructions such that every value reference points backward or to block params. This requires a MOM-side "block scheduler" pass that orders blocks and assigns instruction positions.

**Risk**: Position-based value references impose a strict ordering: a value must be defined before it's referenced (which is already true in SSA form, but MOM currently emits "forward references" where a value is created then immediately used — with position addressing, the reference is by position, not by name). MOM must ensure all block-level dependencies are satisfied (block params used before block instructions that reference params). The block scheduler is the highest-risk component. Additionally, Cranelift requires `switch_to_block()` before emitting instructions — the decoder must manage which block is "current" during body decode.

**Rough sketch**:

1. **Design the body section format**: Header: `[n_blocks: u32]`. Then for block i: `[n_params: u32, param_types...: u32, n_instrs: u32, instrs...: (opcode, slots...), terminator_tag: u32, terminator_slots...]`.

2. **Write the MOM block scheduler**: A MOM pass that takes the current flat lowering (which emits CreateBlock, SwitchToBlock, instructions, SealBlock) and reorders into block-major order. The scheduler: (a) collects all commands per block by tracking CreateBlock → SwitchToBlock → SwitchToBlock boundaries, (b) assigns block indices in definition order, (c) rewrites value references from ID-based to (block_idx, instr_idx), (d) rewrites block references from ID-based to block_idx. This is ~200-300 lines of MOM Lalin code.

3. **Write the Rust block VM decoder**: 
   ```rust
   struct BlockVM<'a, M: Module> {
       ctx: DecoderCtx<'a, M>,
       body: &'a [u8],
       blocks: Vec<Block>,     // Cranelift Block handles
       values: Vec<Vec<Value>>, // per-block instruction result stack
   }
   
   fn decode_body(&mut self) -> Result<()> {
       let n_blocks = read_u32(&mut self.body)?;
       // Phase 1: create all blocks
       for _ in 0..n_blocks {
           self.blocks.push(self.ctx.builder.create_block());
       }
       // Phase 2: read block 0 params (entry block params = function params)
       let n_entry_params = read_u32(&mut self.body)?;
       for _ in 0..n_entry_params {
           let ty = read_scalar(&mut self.body)?;
           self.ctx.builder.append_block_param(self.blocks[0], ty);
       }
       // Phase 3: process each block
       for block_idx in 0..n_blocks {
           self.ctx.builder.switch_to_block(self.blocks[block_idx]);
           let n_instrs = read_u32(&mut self.body)?;
           let mut results: Vec<Value> = Vec::new();
           // Push block params as available values
           for param in self.ctx.builder.block_params(self.blocks[block_idx]) {
               results.push(*param);
           }
           for _ in 0..n_instrs {
               let opcode = read_u32(&mut self.body)?;
               let result = self.decode_instr(opcode, &mut self.body, &results)?;
               results.push(result);
           }
           // Read terminator
           let term_tag = read_u32(&mut self.body)?;
           self.decode_terminator(term_tag, &mut self.body, &results)?;
           // Seal block (safe now — all successors have been emitted)
           self.ctx.builder.seal_block(self.blocks[block_idx]);
           // Guard: block results must survive if this block is a predecessor
           // This means results Vec must outlive this iteration
           // Store for the block to keep values alive
           self.values.push(results);
       }
       Ok(())
   }
   ```
   
   Operand references in instructions use a compact encoding: a single u32 where the high bit indicates `0=block_param, 1=instr_result`, and the remaining bits carry the index. E.g., `0x80000005` = instruction result at index 5, `0x00000002` = block param at index 2. This is a 1-slot reference to any value in scope.

4. **Wire format**: Module declarations use a simple record format (not command-based). Each declaration is a fixed-size record:

   | Tag | Fields | Size |
   |-----|--------|------|
   | 1: CreateSig | `[sig_id, n_params, ct_params..., n_results, ct_results...]` | variable |
   | 2: DeclareFunc | `[func_id, sig_id, visibility]` | 3 slots |
   | 3: DeclareData | `[data_id, size, align]` | 3 slots |
   | 4: DeclareExtern | `[extern_id, symbol_pool, sig_id]` | 3 slots |
   | 5: DataInit | `[data_id, offset, lit_tag, lit_lo, lit_hi]` | 5 slots |
   | 6: BeginBody | `[func_id, body_offset, body_len]` | 3 slots |

   Each function body is a separate contiguous `&[u8]` within the buffer (same as section-table in A).

---

### Comparison

| Criterion | Flatline (A) | SchemaDriven (B) | ImplicitVM (C) |
|-----------|-------------|-----------------|-----------------|
| **Rust code size** | ~1000 lines (smallest) | ~1200 lines (gen + hand) | ~1400 lines (state machine) |
| **Wire compactness** | Medium (~90 tags, inline args) | Medium (~45 tags, per-slot memflags, aux) | High (~60 opcodes, position-addressing) |
| **MOM encoding effort** | Medium (compute memflags bitfield) | Low (same per-slot as today) | High (block scheduler pass) |
| **Decode speed** | Fastest (flat match, no indirection) | Fast (function pointer dispatch) | Medium (position resolution + block ordering) |
| **Maintenance cost** | Medium (hand-write each new tag + arm) | Low (edit YAML, regenerate) | Medium (hand-write opcodes + scheduler) |
| **Error messages** | Integers only (optional names) | Integers only (optional names) | Integers only (optional names) |
| **Risk** | Tag proliferation, slot count errors | Build.rs complexity, half-gen | Block scheduler correctness, SSA ordering |
| **Value lookup cost** | HashMap<u32, Value> | HashMap<u32, Value> | Vec<Value> per block (O(1)) |
| **Schema/tooling** | Hand-maintained tag table | Codegen from YAML | Hand-maintained opcode table |

- **Pick Flatline (A)** if your priority is the smallest, most transparent Rust backend and you're confident the tag set is stable enough that hand-maintenance is fine. One file, one match, one loop. The clearest single-responsibility design.

- **Pick SchemaDriven (B)** if you expect the instruction set to grow over time and want a single source of truth that generates encoder, decoder, schema, and docs. Slower decode but lower long-term maintenance. Best if you expect external contributors or multiple backends.

- **Pick ImplicitVM (C)** if wire compactness and zero-HashMap decode are paramount — e.g., if you're targeting embedded/web where wire size matters, or if profiling shows HashMap lookups are a bottleneck. The block scheduler is the highest-risk component; only choose this if maximum decode throughput justifies the MOM-side complexity.

## Documenter Output — 2026-05-18 15:08:49

---

# Cranelift-First Seam Redesign — Architectural Decision

**Workflow**: wf-cranelift-seam
**Date**: 2026-05-18
**Decision**: Approach A — "Flatline"
**Status**: Approved

---

## Goal

Replace the current MLBT v3 parametric wire format and the Rust backend's intermediate ASDL expansion layers (BackCmd/BackBodyCmd enums, sub-enum types, partition pass) with a single, flat tag-space wire format where each tag corresponds to exactly one Cranelift IR operation. The Rust backend becomes a thin streaming decoder loop that reads `(tag, slots)` pairs from wire bytes and calls Cranelift APIs directly, without materializing any intermediate Rust enums or undergoing a partitioning pass. The wire format carries only what Cranelift actually needs — no synthetic commands, no frontend bookkeeping metadata that Cranelift discards, no string-based value handles.

---

## Incentives

The redesign is motivated by three concrete problems with the current architecture:

**1. Unnecessary expansion layers produce ~1350 lines of overhead Rust code.** The current data flow from Lua to Cranelift is: Lua lowering → BackProgram ASDL → binary encoding → binary decoding → Vec\<BackCmd\> → partition() → separated decls + bodies → FunctionLowerer → Cranelift IR. Steps 2–4 (encoding, decoding into Rust ASDL, partitioning) are pure overhead required only by the FFI boundary. The Rust enum matching involves 60+ `BackCmd` variants → `partition()` (20+ matches) → 20 sub-enums → 200+ match arms in `lower_*` methods. Every match arm unpacks the same fields that were already decoded from the wire. This repetitive code constitutes ~1350 lines (of ~3244 total in `lib.rs`) that serve no Cranelift-facing purpose.

**2. The wire format carries metadata Cranelift cannot use, all of which is wasted decode cost.** The scout identified seven categories of frontend-only data that the Rust side materializes and then silently discards: `BackIntSemantics` (overflow/exact), `BackFloatSemantics` (strict/fastmath), `BackAccessId` (provenance string), `BackDereference` (provenance info), `BackAccessMode` (read/write — implicit in the operation), plus string-based switch case parsing that re-parses integers already available in the Lua compiler. Each such field consumes wire bytes, slots in the `CmdEntry` struct, decoder match arms, and Rust memory allocation — all for nothing. The knowledge builder quantified this precisely: per memory command, 8 slots of memory info collapse to 1 slot of MemFlags bitfield that Cranelift actually uses.

**3. The flat stream of commands forces a 451-line partition pass** that re-separates already-separate concerns. The current wire format mixes module-level declarations and function body commands in a single linear stream delimited by `BeginFunc`/`FinishFunc` markers. `BackProgram::partition()` must re-sort these into declarations vs. per-function bodies. This pass exists only because the wire format does not reflect the Cranelift Module API's inherent two-phase structure (declare-then-define). A section-indexed two-level wire eliminates partitioning entirely — the decoder reads declarations from one region of the buffer and function bodies from another.

---

## Current State

### The Wire Format (MLBT v3)

The current binary wire format uses **parametric commands**: ~61 command tags, ~10 sub-tag tables, ~13 scalar type tags. A command like `CmdIntBinary` carries a sub-tag for the operation kind (`BackIntAdd`, `BackIntSub`, ...) and a scalar type tag (`I32`, `I64`, ...). The decoder must match on the command tag, then again on the sub-tag, then potentially on the scalar tag — three levels of dispatch for a single Cranelift instruction.

The wire format is defined in `BACK_WIRE_FORMAT.md` and encoded by `lua/lalin/back_command_binary.lua` (the Lua-side encoder) and by MOM's `cmd.mlua` (the MOM-side encoder which writes `CmdEntry` structs into a `MomCmdBuffer`). Command slots are 16 i32 words per command (the `CmdEntry` struct), many of which are zero-filled for simple commands.

The format has an **auxiliary data section** for variable-length data (block arguments, signature parameter lists). Commands reference aux data by offset. This indirection adds decoder complexity.

### The Rust Backend (`src/lib.rs`, ~3244 lines)

**`Compiler<M: Module>`** (lines ~1546–1605):
```rust
struct Compiler<M: Module> {
    module: M,
    signatures: HashMap<BackSigId, Signature>,
    funcs: HashMap<BackFuncId, FuncDecl>,
    externs: HashMap<BackExternId, ExternDecl>,
    datas: HashMap<BackDataId, DataDecl>,
    bodies: Vec<(BackFuncId, Vec<BackBodyCmd>)>,
}
```
Three-phase compilation:
1. **`collect()`** — reads `Vec<BackCmd>` from decoder, calls `partition()` to separate declarations from per-function body command lists
2. **`declare_all()`** — iterates declarations, calls `module.declare_function()`, `module.declare_data()`, etc.
3. **`define_all()`** — iterates bodies, creates `FunctionBuilder`, runs `FunctionLowerer::lower()` per body, calls `module.define_function()`

**`FunctionLowerer`** (lines ~1607–2650):
```rust
struct FunctionLowerer<'a> {
    builder: &'a mut FunctionBuilder<'a>,
    values: HashMap<BackValId, Value>,
    blocks: HashMap<BackBlockId, Block>,
    stack_slots: HashMap<BackStackSlotId, StackSlot>,
}
```
`lower_cmd()` dispatches through a 20-sub-enum match, with each `lower_*` method matching further on operation variants. Most methods produce 1–5 Cranelift IR instructions.

**`BackCmd` enum + sub-enum types** (~270 lines) and `partition()` (~451 lines) together constitute the primary Rust-side overhead. `BackValId`, `BackBlockId`, and other `id_type!` macro-derived types use `String` internally — every handle involves a heap allocation for the string copy from the wire pool.

**The FFI decoder** (`src/ffi.rs`, lines ~1–1629) contains `parse_back_command_binary()` which reads wire bytes and materializes `Vec<BackCmd>`. This is the entry point for the Rust ASDL expansion.

### The Data Flow

```
Lua/MOM lowering → BackProgram ASDL (Lua tables)
    → back_command_binary.lua (binary encoding)
        → wire bytes (MLBT v3)
            → ffi.rs parse_back_command_binary (binary decoding)
                → Vec<BackCmd> (Rust ASDL)
                    → BackProgram::partition()
                        → BackProgram { decls: Vec<BackDeclCmd>, bodies: Vec<(FuncId, Vec<BackBodyCmd>)> }
                            → Compiler::declare_all() (Cranelift Module API)
                            → Compiler::define_all() → FunctionLowerer::lower()
                                → Cranelift IR
```

The Rust ASDL types (`BackCmd`, `BackBodyCmd`, 20 sub-enums) are an **expansion** that mirrors the Lua-side ASDL types. They exist only to be consumed by `lower_cmd()`. The wire format is the serialization of the Lua ASDL, not an encoding derived from what Cranelift needs.

### What Cranelift Actually Needs

From the scout's analysis of the complete Cranelift API surface used:

- **Module-level**: Signatures (param/return types), function declarations (id + sig + linkage), data declarations (id + size + align), extern declarations (name + sig)
- **Function-level**: Block creation/switch, block parameters, stack slots, SSA value definitions and uses, typed instructions (60+ instruction variants), MemFlags (3 bits: notrap/aligned/can_move), control flow (jump/brif/return/trap/call), memory addressing (stack_addr/global_value/func_addr)
- **Not needed**: Integer overflow/exact semantics, float fast-math flags, access provenance strings, access mode tags, dereference metadata, string-based value IDs

### Key Tensions in the Current State

1. **String value handles (`BackValId(String)`) incur unnecessary allocation** — the Rust side `HashMap<String, Value>` allocates a heap string for every value handle. MOM already uses sequential integer IDs per function. The Lua compiler could generate integer IDs instead of `"v1"`, `"v2"` strings.

2. **Block sealing, entry params, and finish markers are explicit on the wire** but could be derived from structure — `SealBlock` becomes implicit (seal all at body end), `BindEntryParams` is implicit (first N block params of entry block = function params), `FinishFunc`/`FinalizeModule` are implicit (buffer boundaries).

3. **Sub-enum dispatch multiplies match arms** — 84 distinct numeric values to match across three dispatch levels, when ~60 flat tags would suffice.

4. **Aux data indirection** adds decoder complexity — variable-length lists referenced by offset rather than inline-counted.

5. **Three-phase compilation is a Cranelift Module API requirement, not an artifact** — the wire must support the declare-then-define structure. A two-level wire (declarations section + per-function body sections) makes this explicit and eliminates the partition pass.

---

## Chosen Target

### Approach: Flatline (Approach A)

Flatline was chosen because it produces the smallest, most transparent Rust backend with the clearest single-responsibility design. The ~90-tag flat table is a natural fit for a well-established compiler backend whose instruction set changes infrequently (Cranelift's IR is stable across minor versions). The elimination of sub-tag dispatch, partition(), and all intermediate ASDL Rust types yields the maximum reduction in Rust code complexity for the minimum MOM encoder adaptation cost.

### Wire Architecture

The wire format is restructured into a **section-indexed two-level** layout:

```
┌─────────────────────────────────────┐
│ HEADER                              │
│ [magic=0x4D4C, ver=4,              │
│  n_funcs, n_sigs, n_datas, n_externs] │
├─────────────────────────────────────┤
│ DECLARATION SECTION                 │
│ [sig table, func table,             │
│  data table, extern table]          │
│ — fixed-length records, no commands │
├─────────────────────────────────────┤
│ BODY SECTION TABLE                  │
│ per func: [func_id,                 │
│            body_offset, body_len]   │
├─────────────────────────────────────┤
│ FUNCTION BODY SECTIONS (contiguous) │
│ — each body is a flat tag+slots     │
│   stream, no begin/finish markers   │
└─────────────────────────────────────┘
```

**Header**: Fixed-size preamble declaring the counts of everything that follows. `n_funcs` drives the body table size; `n_sigs`, `n_datas`, `n_externs` drive the declaration section size.

**Declaration section**: Fixed-length records for each declaration type — no command-based encoding. Each record is self-contained with known slot count:

| Declaration | Slots |
|---|---|
| `CreateSig` | `[sig_id, n_params, ct_param0, ..., n_results, ct_result0, ...]` |
| `DeclareFunc` | `[func_id, sig_id, visibility (0=export, 1=local)]` |
| `DeclareData` | `[data_id, size, align_log2]` |
| `DeclareExtern` | `[extern_id, symbol_name_pool_idx, sig_id]` |
| `DataInit` | `[data_id, offset, lit_tag, lit_lo, lit_hi]` |

The string pool is retained only for extern symbol names. The declaration section must appear before any function body may reference its IDs — this ordering is enforced by the section structure itself, not by command ordering.

**Body section table**: An array of `(func_id, offset, length)` entries pointing into the contiguous body data region. The Rust decoder uses this to locate each function's body stream without scanning.

**Function body sections**: Each body is a flat stream of commands in tag+slots format. No `BeginFunc`/`FinishFunc` markers — body section boundaries are the delimiters. No `SealBlock` — all blocks are sealed at body end via `builder.seal_all_blocks()`. No `BindEntryParams` — the first N block params of block 0 (the entry block) are the function params, where N is the parameter count of the function's signature (looked up from the declaration section).

### Tag Space

~90 flat tags, one per distinct Cranelift IR operation. Each tag has a fixed number of 32-bit slots. Tags encode the operation fully — there are no sub-tag tables, no scalar type tags, no op-kind enums. For operations that exist in multiple type variants (e.g., `iadd` on i32 vs i64), the tag encodes the scalar type in the tag name (e.g., `IaddI32=1`, `IaddI64=2`). Where a Cranelift instruction operates on the type of its operands (e.g., `band`, `bnot`), a generic tag with a type slot is sufficient.

**Representative tag layout**:

| Tag | Slots | Description |
|---|---|---|
| `IaddI32`=1 | 3: `[dst, lhs, rhs]` | i32 addition |
| `IaddI64`=2 | 3: `[dst, lhs, rhs]` | i64 addition |
| `Fadd`=3 | 3: `[dst, lhs, rhs]` | f32 or f64 addition (type from operands) |
| `ConstI32`=12 | 2: `[dst, value]` | i32 constant |
| `ConstF64`=14 | 3: `[dst, val_lo, val_hi]` | f64 constant (low/high u32 halves) |
| `LoadI32`=30 | 5: `[dst, memflags, base_tag, base_id, offset]` | Load i32 from address |
| `StoreI32`=31 | 4: `[src, memflags, base_tag, base_id, offset]` | Store i32 |
| `Jump`=50 | `var: [dest_block, n_args, arg0, arg1, ...]` | Unconditional jump with block args inline |
| `Brif`=51 | `var: [cond, then_block, then_n_args, then_arg0..., else_block, else_n_args, else_arg0...]` | Conditional branch |
| `Return`=52 | `var: [n_vals, val0, val1, ...]` | Return with values |
| `Trap`=60 | 0 slots | Trap (ud2) |
| `Call`=55 | `var: [result_tag, dst, sig_id, target_tag, target_id, n_args, arg0, arg1, ...]` | Function call |
| `CallIndirect`=56 | `var: [result_tag, dst, sig_id, callee, n_args, arg0, ...]` | Indirect call |
| `StackAddr`=40 | 3: `[dst, ptr_type, stack_slot_id]` | stack_addr |
| `GlobalValue`=41 | 3: `[dst, ptr_type, data_id]` | global_value |
| `CreateBlock`=70 | 1: `[block_id]` | Allocate block |
| `SwitchToBlock`=71 | 1: `[block_id]` | Activate block |
| `AppendBlockParam`=72 | 2: `[block_id, scalar_type]` | Add block parameter |
| `CreateStackSlot`=73 | 3: `[stack_slot_id, size, align_log2]` | Allocate stack slot |

Variable-length commands (Jump, Brif, Return, Call, CallIndirect, SwitchInt) use a count prefix after the fixed tag slots. The decoder reads the count, then reads that many additional slots. This replaces the aux data section entirely.

The full tag table is maintained as a hand-written `#[repr(u32)] enum WireTag` and a `const TAG_SLOT_COUNTS: &[u8]` array indexed by tag — slot_count for tags 0..=N, where each entry is the minimum slot count (before the variable-length portion, if any).

### MemFlags Encoding

A single `u32` bitfield replaces the current 8-slot `BackMemoryInfo`. Bit assignments:

| Bit | Meaning |
|---|---|
| 0 | `notrap` — load/store will not fault |
| 1 | `aligned` — address is aligned to natural alignment |
| 2 | `can_move` — instruction is safe to reorder |

The frontend (MOM's `mb_emit_*` helper for memory operations) computes this bitfield from its type analysis before encoding. The Rust decoder extracts the three bits and calls `MemFlags::new().set_notrap(b0).set_aligned(b1).set_can_move(b2)`.

Bits beyond bit 2 are reserved for future use (e.g., read-only hints, atomic ordering flags).

### Value Handles

All value and block handles are `u32` integers, scoped per function. The Rust decoder maintains:

```rust
// Per function body:
values: HashMap<u32, Value>,      // u32 handle → Cranelift Value
blocks: HashMap<u32, Block>,       // u32 handle → Cranelift Block
stack_slots: HashMap<u32, StackSlot>,  // u32 handle → Cranelift StackSlot
```

These HashMaps are created fresh per function body. Per-function scoping is natural — handles `0..N` are valid only within the current body and are reset for the next.

For debuggability, an **optional debug section** may be appended after all body sections. If present, it contains a map from handle IDs to string names. The Rust decoder reads this section only on error, attaching names to error messages. This avoids polluting the fast path with string allocation while preserving diagnostic quality.

### What Is Removed from the Wire

| Current construct | Status |
|---|---|
| `SealBlock` | Implicit — all blocks sealed at body end |
| `BindEntryParams` | Implicit — entry block's first N block params = function params (N from signature) |
| `FinishFunc` | Implicit — body section end |
| `FinalizeModule` | Implicit — buffer end |
| `BackIntSemantics` (overflow/exact) | Removed — Cranelift ignores |
| `BackFloatSemantics` (strict/fastmath) | Removed — Cranelift ignores |
| `BackAccessId` | Removed — never used |
| `BackDereference` | Removed — never used |
| `BackAccessMode` | Removed — implicit in load vs store tag |
| Aux data section | Removed — variable-length data inline with count prefix |
| String pool (for values/blocks) | Removed — handles are `u32` |
| String case values for SwitchInt | Removed — sent as raw u64s |

### Rust Decoder Architecture

The new Rust backend is a single `decode_module()` function (not a struct with phases):

```rust
fn decode_module(buf: &[u8], module: &mut M) -> Result<(), DecodeError>
where M: Module
```

**Phase 1 — Read header**: Extract magic, version, counts, and section table offsets.

**Phase 2 — Process declarations**: For each signature declaration, construct Cranelift `Signature` and store in `HashMap<u32, Signature>`. For each func/data/extern declaration, call `module.declare_function()` / `module.declare_data()` and store returned IDs. For data initializers, accumulate into byte buffers for later `module.define_data()`.

**Phase 3 — Per-function body decode**: For each body table entry, locate the body bytes. Create a Cranelift `Context` and `FunctionBuilder`. Enter a loop reading `(tag, slots)` from the body bytes:

- Structural tags (`CreateBlock`, `SwitchToBlock`, `AppendBlockParam`, `CreateStackSlot`) → call `builder.*` methods, record in per-function HashMaps
- Value tags (`IaddI32`, `Fadd`, `LoadI32`, `ConstI64`, ...) → call `builder.ins().*()`, store result in `values` HashMap under the `dst` handle
- Control tags (`Jump`, `Brif`, `Return`, `Trap`, `Call`, ...) → call `builder.ins().*()`, lookup blocks by handle
- At end of body: `builder.seal_all_blocks()`, `builder.finalize()`, `module.define_function(func_id, &mut ctx)`

**Phase 4 — Finalize**: Call `module.finalize_definitions()` for JIT, or `module.finish()` + `product.emit()` for object emission.

State maintained across phases:
```rust
struct DecodeState {
    signatures: HashMap<u32, Signature>,
    func_ids: HashMap<u32, FuncId>,
    data_ids: HashMap<u32, DataId>,
    data_inits: Vec<(DataId, Vec<u8>)>,
    extern_ids: HashMap<u32, FuncId>,
    // Per-function state (reset each body):
    values: HashMap<u32, Value>,
    blocks: HashMap<u32, Block>,
    stack_slots: HashMap<u32, StackSlot>,
}
```

The JIT vs object emission difference is compressed to a single parameter (whether to call `finalize_definitions()` or `finish()` + `emit()`), factored into a shared `decode_module()` that takes a finalization closure.

### MOM Encoder Adaptation

Each `mb_emit_*` helper in MOM's `cmd.mlua` is rewritten to emit its flat tag directly:

- **`mb_emit_load_info`** / **`mb_emit_store_info`**: Drop `access_id`, `deref_kind`, `deref_bytes`, `access_mode`. Compute `memflags = (notrap << 0) | (aligned << 1) | (can_move << 2)` as a single `u32`. Emit `[tag, dst, memflags, base_tag, base_id, offset]`.
- **`mb_emit_int_binary`**: Drop overflow/exact semantics slots. Emit `[IaddI32_tag, dst, lhs, rhs]` (type-specific tag).
- **`mb_emit_switch`**: Send raw u64 case values (as two u32s each) inline, not as pool strings.
- **CreateBlock / SwitchToBlock / AppendBlockParam / CreateStackSlot**: Emit their flat structural tags.

The Lua compiler's encoder (`back_command_binary.lua`) is replaced with a new encoder that maps from `BackProgram` ASDL to flat tags. The mapping is mechanical — each ASDL command variant maps to one or more flat-tag commands, dropping the unused fields.

### Tradeoffs Acknowledged

1. **Wire compactness vs. approach A's tag density is medium** — ~90 tags with inline variable-length data is less compact than approach C's position-addressed bytecode, but this is acceptable because wire size is not a bottleneck (the wire is ephemeral — produced once per compilation, consumed once by the Rust decoder, then freed). The ~90-tag space means the tag table is medium-sized but straightforward.

2. **Tag proliferation risk** — Adding a new Cranelift instruction variant requires adding a new tag, a new match arm, and possibly changing MOM's lowering to emit it. For a stable backend like Cranelift whose IR rarely adds new opcodes, this is acceptable. The tag table must be maintained carefully with no reordering or gaps.

3. **MOM must compute MemFlags bitfields** — The frontend does more work per memory operation (computing notrap/aligned/can_move from type analysis) rather than sending raw metadata and letting Rust compute it. This is acceptable because the frontend has the type context to make these decisions, and the work is a simple bit-wise OR of booleans.

4. **Rust tests use raw bytes** — Rust `#[test]` tests currently construct `BackProgram` via named enum variants. With the enum gone, tests construct wire bytes or use a `build_wire_program()` test helper. This is acceptable — the builder API moves from production code to test code, with wire bytes as the sole production path.

5. **Integer-only error messages** — Error messages use handle IDs instead of string names by default. The optional debug section provides names on error for diagnostics. This is acceptable because errors are rare, and the fast path is not penalized with string allocation.

### Risks Acknowledged

1. **Slot count mismatches** — The tag→slot count table in the Rust decoder must exactly match the encoder. A mismatch (decoder expecting 4 slots when encoder wrote 5) will desynchronize the decoder, causing either garbage interpretation or buffer over-read. Mitigation: the tag table is a single source of truth maintained in one file (`tags.rs`), and the body table's per-function length bounds the damage to a single function.

2. **Cranelift version drift** — If a future Cranelift version removes an instruction or changes its API, the corresponding tag changes meaning. Mitigation: the flat tag space is Lalin-specific; tags map to Cranelift API calls at decode time, not to Cranelift's internal encoding. A Cranelift upgrade requires updating the match arms in the decoder, but the wire format is stable across Cranelift versions.

3. **Implicit block sealing requires all predecessors to be known** — Cranelift requires `seal_block()` only after all predecessors have been added. Sealing all blocks at body end works only if the body stream correctly records all jumps to each block before the end. If a jump target references a block that has already been sealed (because it was switched away from and the decoder sealed it early), Cranelift will panic. Mitigation: seal all blocks *after* the entire body stream is processed, not on switch-away. This requires the decoder to defer sealing until body end, which is safe because `FunctionBuilder` supports this deferred sealing.

4. **Ordering invariants are producer-enforced** — The decoder does not reorder commands. If the producer emits `SwitchToBlock(block_id)` before `CreateBlock(block_id)`, the decoder will attempt `builder.switch_to_block()` with an uncreated block handle, causing a runtime panic. Mitigation: this is both explicit in the format specification (blocks must be created before use) and guaranteed by MOM's lowering order (which currently emits CreateBlock before SwitchToBlock). The decoder can optionally validate ordering with an extra bound check.

## Edit-planner Output — 2026-05-18 15:14:42

Now I have a thorough understanding of all the files. Let me produce the complete implementation plan.

---

## Precondition Checks

Before any edits begin, verify:

1. `src/lib.rs` line 20: confirm `pub mod ffi;` is still present; the new `pub mod decode;` and `pub mod wire_tags;` will be added after it.
2. `src/lib.rs` line 3245: confirm the file ends at `}` (closing the `mod tests` block).
3. `src/ffi.rs` line 1629: confirm the file ends with a non-whitespace line.
4. `lua/lalin/back_command_binary.lua` total length: confirm the `Define` function still starts around line 640.
5. `lua/lalin/mom/driver/lower_wire.mlua`: confirm the slot count function `mom_wire_slot_count` is the last major function before the export block (~line 284).
6. Cargo.toml does not have `src/decode.rs` or `src/wire_tags.rs` listed — these are auto-discovered as sibling modules of `src/lib.rs`.

---

## Files to Modify

### 1. `src/wire_tags.rs` (NEW)

**Goal**: Define the ~90 flat tags as a Rust `#[repr(u32)]` enum and a static slot-count table.

**Contents sketch**:
```rust
/// Flat wire tags — one per Cranelift IR operation variant.
/// The tag space is dense (1..=N) with no gaps.
#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WireTag {
    // ── Structural tags (function body scaffold) ────
    CreateBlock = 1,
    SwitchToBlock = 2,
    AppendBlockParam = 3,
    CreateStackSlot = 4,

    // ── Constants ────
    ConstI32 = 10,
    ConstI64 = 11,
    ConstF32 = 12,
    ConstF64 = 13,
    ConstBool = 14,
    ConstNull = 15,

    // ── Integer arithmetic (type-specific tags) ────
    IaddI32 = 20, IaddI64 = 21,
    IsubI32 = 22, IsubI64 = 23,
    ImulI32 = 24, ImulI64 = 25,
    SdivI32 = 26, SdivI64 = 27,
    UdivI32 = 28, UdivI64 = 29,
    SremI32 = 30, SremI64 = 31,
    UremI32 = 32, UremI64 = 33,
    InegI32 = 34, InegI64 = 35,

    // ── Float arithmetic ────
    Fadd = 40, Fsub = 41, Fmul = 42, Fdiv = 43,
    Fneg = 44, Fabs = 45, Fma = 46,
    Sqrt = 47, Floor = 48, Ceil = 49, Trunc = 50, Nearest = 51,

    // ── Bitwise ────
    Band = 60, Bor = 61, Bxor = 62, Bnot = 63,

    // ── Shift/Rotate ────
    Ishl = 70, Ushr = 71, Sshr = 72,
    Rotl = 73, Rotr = 74,

    // ── Compare (returns b1) ────
    IcmpEq = 80, IcmpNe = 81,
    SIcmpLt = 82, SIcmpLe = 83, SIcmpGt = 84, SIcmpGe = 85,
    UIcmpLt = 86, UIcmpLe = 87, UIcmpGt = 88, UIcmpGe = 89,
    FCmpEq = 90, FCmpNe = 91, FCmpLt = 92, FCmpLe = 93, FCmpGt = 94, FCmpGe = 95,

    // ── Cast/Convert ────
    Bitcast = 100,
    Ireduce = 101, Sextend = 102, Uextend = 103,
    Fpromote = 104, Fdemote = 105,
    FcvtFromSint = 106, FcvtFromUint = 107,
    FcvtToSint = 108, FcvtToUint = 109,

    // ── Intrinsics ────
    Popcnt = 110, Clz = 111, Ctz = 112, Bswap = 113, Iabs = 114,

    // ── Address ops ────
    StackAddr = 120, GlobalValue = 121, FuncAddr = 122,

    // ── Memory ────
    LoadI8 = 130, LoadI16 = 131, LoadI32 = 132, LoadI64 = 133,
    LoadF32 = 134, LoadF64 = 135,
    StoreI8 = 136, StoreI16 = 137, StoreI32 = 138, StoreI64 = 139,
    StoreF32 = 140, StoreF64 = 141,
    AtomicLoad = 142, AtomicStore = 143,
    AtomicRmw = 144, AtomicCas = 145, Fence = 146,
    Memcpy = 147, Memset = 148,

    // ── Pointer ────
    PtrAdd = 150, PtrOffset = 151,

    // ── Vector ────
    Splat = 160, InsertLane = 161, ExtractLane = 162,
    VecIadd = 163, VecIsub = 164, VecImul = 165,
    VecBand = 166, VecBor = 167, VecBxor = 168,
    VecIcmpEq = 169, VecIcmpNe = 170,
    VecSIcmpLt = 171, VecSIcmpLe = 172, VecSIcmpGt = 173, VecSIcmpGe = 174,
    VecUIcmpLt = 175, VecUIcmpLe = 176, VecUIcmpGt = 177, VecUIcmpGe = 178,
    VecLoad = 179, VecStore = 180,
    VecSelect = 181,

    // ── Select ────
    Select = 190,

    // ── Control flow ────
    Jump = 200, Brif = 201, SwitchInt = 202,
    ReturnVoid = 203, ReturnValue = 204, Trap = 205,

    // ── Call ────
    Call = 210, CallIndirect = 211,
}

/// Slot count per tag (minimum fixed slots, before any variable-length data).
pub static TAG_SLOTS: [u8; 256] = {
    let mut t = [0u8; 256];
    t[WireTag::CreateBlock as usize]  = 1;  // [block_id]
    t[WireTag::SwitchToBlock as usize] = 1; // [block_id]
    t[WireTag::AppendBlockParam as usize] = 2; // [block_id, scalar_type]
    t[WireTag::CreateStackSlot as usize] = 3;  // [slot_id, size, align_log2]
    t[WireTag::ConstI32 as usize] = 2;   // [dst, value]
    t[WireTag::ConstI64 as usize] = 3;   // [dst, lo, hi]
    t[WireTag::ConstF32 as usize] = 2;   // [dst, bits]
    t[WireTag::ConstF64 as usize] = 3;   // [dst, lo, hi]
    t[WireTag::ConstBool as usize] = 2;  // [dst, 0/1]
    t[WireTag::ConstNull as usize] = 1;  // [dst]
    // ... all binary ops: [dst, lhs, rhs] = 3 slots
    // ... loads: [dst, memflags, base_tag, base_id, offset] = 5
    // ... stores: [src, memflags, base_tag, base_id, offset] = 5
    // ... Jump: [dest_block, n_args] + inline args = 2 + variable
    // ... Brif: [cond, then_block, then_n, else_block, else_n] + inline args
    t
};
```

**Imports required**: None (standalone; no Cranelift deps).

---

### 2. `src/decode.rs` (NEW)

**Goal**: The streaming decoder that reads wire bytes and drives Cranelift APIs directly.

**Contents sketch**:
```rust
use crate::wire_tags::WireTag;
use crate::LalinError;
use cranelift_codegen::ir::*;
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::immediates::{Ieee32, Ieee64};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
use cranelift_module::{DataDescription, FuncId, Linkage, Module, UserFuncName};
use std::collections::HashMap;

/// Result of decoding a module — provides function pointer lookup for artifacts.
pub struct DecodeResult {
    pub func_ids: HashMap<u32, (String, FuncId)>, // wire_id → (symbol_name, Cranelift FuncId)
}

/// Main entry point: decode a wire buffer into a Cranelift Module.
pub fn decode_module<M: Module>(
    buf: &[u8],
    module: &mut M,
    symbols: &HashMap<String, *const u8>,
) -> Result<DecodeResult, LalinError> { ... }
```

Internal phases:

**Phase 1 — Header** (read magic, version, counts, section offsets):
```rust
fn read_header(buf: &[u8]) -> Result<Header, LalinError>
// Layout: [magic(4), ver(4), n_funcs(4), decls_off(4), decls_len(4), body_tbl_off(4), body_tbl_len(4)]
```

**Phase 2 — Declarations** (read sigs, funcs, datas, externs via fixed-length records):
```rust
fn read_declarations(buf: &[u8], off: usize, len: usize, state: &mut DecodeState, module: &mut M) -> Result<(), LalinError>
// Reads inline-counted sigs: [sig_id, n_params, params..., n_results, results...]
// Reads funcs: [func_id, sig_id, visibility, symbol_pool_idx] — pool_idx indexes into trailing name section
// Reads datas: [data_id, size, align_log2]
// Reads externs: [extern_id, symbol_pool_idx, sig_id]
// Calls module.declare_function(), module.declare_data() as it reads
```

**Phase 3 — Per-function body** (iterate body table, create FunctionBuilder, decode instructions):
```rust
fn decode_body(buf: &[u8], state: &DecodeState, module: &mut M, func_id: u32, sig: &Signature) -> Result<(), LalinError>
```

The inner instruction loop:
```rust
fn decode_instrs(buf: &[u8], pos: &mut usize, ctx: &mut FuncCtx) -> Result<(), LalinError>
// Reads tag, dispatches via match WireTag:
//   WireTag::CreateBlock => let id = read_u32(); let block = builder.create_block(); blocks.insert(id, block);
//   WireTag::IaddI32 => let dst = read_u32(); let lhs = *values.get(&read_u32())?; let rhs = *values.get(&read_u32())?; let v = builder.ins().iadd(lhs, rhs); values.insert(dst, v);
//   ... (~180 match arms)
// At body end: builder.seal_all_blocks(); builder.finalize();
```

**Structs**:
```rust
struct DecodeState {
    signatures: HashMap<u32, Signature>,
    func_decls: HashMap<u32, FuncDecl>, // wire_id → (symbol: String, sig_id: u32, linkage: Linkage, func_id: Option<FuncId>)
    data_decls: HashMap<u32, DataDecl>,  // wire_id → (size, align, data_init_bytes, data_id: Option<DataId>)
    extern_decls: HashMap<u32, ExternDecl>, // wire_id → (symbol, sig_id, func_id: Option<FuncId>)
}

struct FuncCtx<'a> {
    builder: &'a mut FunctionBuilder<'a>,
    values: HashMap<u32, Value>,
    blocks: HashMap<u32, Block>,
    stack_slots: HashMap<u32, StackSlot>,
}
```

**MemFlags helper**:
```rust
fn decode_memflags(bits: u32) -> MemFlags {
    let mut f = MemFlags::new();
    if bits & 1 != 0 { f.set_notrap(); }
    if bits & 2 != 0 { f.set_aligned(); }
    if bits & 4 != 0 { f.set_can_move(); }
    f
}
```

**Imports required**: `crate::wire_tags::WireTag`, `crate::LalinError`, various Cranelift types.

**Key patterns**:
- All identifiers are `u32` — no `id_type!` macro usage.
- Every error message includes the wire func_id and/or value id for debuggability.
- The `values` HashMap is reset per function body.
- `seal_all_blocks()` called at end of each body, never inline.
- Entry block params are implicit: the first N `AppendBlockParam` commands on block 0 correspond to function params (N = sig.param_count).

Full estimate: ~900-1100 lines.

---

### 3. `src/lib.rs` — Major Rewrite

**Goal**: Delete ~2300 lines of ASDL types, BackCmd/BackBodyCmd enums, partition(), Compiler, FunctionLowerer. Keep Jit/Artifact wrappers, helper functions, and tests — but rewrite Jit::compile_binary and compile_object_binary to call the new decoder.

**Lines to DELETE** (entire ranges removed):

| Lines | What | Count |
|-------|------|-------|
| 22–55 | `id_type!` macro + BackSigId..BackStackSlotId | ~34 |
| 57–81 | BackSwitchCase, BackScalar enum definition | ~25 |
| 82–105 | BackScalar impl (clif_type, byte_size, supports_atomic) | ~24 |
| 106–115 | BackVec | ~10 |
| 116–145 | BackIntOverflow, BackIntExact, BackIntSemantics | ~30 |
| 146–268 | BackFloatSemantics..BackMemoryInfo (6 structs/enums + impl) | ~123 |
| 269–462 | BackCmd enum (~150 variants) | ~194 |
| 462–470 | BackDeclCmd enum | ~9 |
| 470–699 | All sub-op enums (IntBinaryOp..OtherOp) | ~230 |
| 700–723 | BackBodyCmd enum | ~24 |
| 725–1185 | BackProgram + impl, FuncDecl, ExternDecl, DataInit, DataDecl | ~461 |
| 1187–1578 | Compiler struct + impl (collect, declare_all, define_all, etc.) | ~392 |
| 1581–2732 | FunctionLowerer + all lower_* methods (~996 lines essential + dispatch) | ~1152 |
| 2734–2765 | lower_const_int, lower_const_float | ~32 |
| 2767–2848 | write_data_*, symbol_name_*, hex_digit | ~82 |

**Rough total deleted**: ~2822 lines (some overlap with kept lines below)

**Lines to MODIFY** (keep but rewrite):

| Lines | Current | New |
|-------|---------|-----|
| 1–20 | imports + `pub mod ...` | **Add** `pub mod wire_tags;` and `pub mod decode;` after `pub mod ffi;` on line 20. Keep existing imports. |
| 1061–1062 | `pub struct Jit { symbols: HashMap<String, *const u8> }` | Keep Jit struct unchanged (symbols HashMap stays for extern linkage) |
| 1066–1091 | `Jit::compile()`, `compile_tape()`, `compile_binary()` | **Rewrite** `compile()` to directly call decode_module. `compile_tape` removed (backward compat not needed). `compile_binary` rewritten: create JITModule, call `decode_module(buf, &mut module, &self.symbols)`, `module.finalize_definitions()`, build function_ptrs from DecodeResult. |
| 1094–1098 | `compile_object_binary()` | **Rewrite**: create ObjectModule, call decode_module, module.finish(), emit bytes. |
| 1125–1128 | `compile_object(program: &BackProgram, ...)` | **Remove** — takes BackProgram which is deleted. |
| 1130–1155 | Artifact struct + methods | **Keep** Artifact struct. **Rewrite** internals: remove `BackFuncId` from function_ptrs, use `String` key (from symbol names in DecodeResult). Change `getpointer_by_name` to look up by the symbol string. |
| 2949–3245 | `mod tests` | **Rewrite** all tests to use `Jit::compile_binary()` with raw wire bytes (or use a `build_wire_program!()` macro in the test module). |

**Lines to KEEP UNCHANGED**:

| Lines | What | Reason |
|-------|------|--------|
| 1–20 | imports (minus BackCmd/BackBodyCmd types) | Remove unused imports; add decode/wire_tags |
| 21 | empty line | Keep |
| Varies | LalinError struct | Used everywhere |
| Varies | host_isa(), build_host_isa() | Used by JIT and object paths |
| Varies | hex_digit, local_symbol_name, local_data_symbol_name | May keep for symbol name generation |
| Varies | align_to_shift | Used by stack slot creation |

**After the rewrite, lib.rs shape**:

```
Lines 1-20:   Imports + `pub mod host_arena; pub mod lua_api; pub mod ffi; pub mod wire_tags; pub mod decode;`
Lines ~22-60: LalinError struct + impl
Lines ~62-100: BackScalar enum + impl (clif_type, byte_size — still needed by decoder)
Lines ~102-112: BackVec enum + impl
Lines ~114-120: BackAtomicOrdering, BackAtomicRmwOp + impl
Lines ~122-180: Jit struct, Artifact struct, ObjectArtifact struct, compile_object_binary
Lines ~182-250: host_isa(), build_host_isa(), hex_digit, align_to_shift
Lines ~252-320: #[cfg(test)] mod tests
```

Total: ~320 lines (down from 3245). A ~90% reduction.

---

### 4. `src/ffi.rs` — Major Rewrite

**Goal**: Delete old binary decoder (SLOT_COUNT, BinaryReader, decode_commands, parse_back_command_binary, all read_* helpers), rewrite `lalin_jit_compile_binary` and `lalin_object_compile_binary` to call the new decoder, keep tape decoder and all C API wrappers.

**Lines to DELETE**:

| Lines | What |
|-------|------|
| 1–20 | Imports of BackCmd/BackBodyCmd/BackProgram types — replace with `crate::decode` imports. |
| 82–326 | All `read_*` helper functions (`read_scalar`, `read_int_overflow`, `read_alignment`, etc.) — these are decode helpers for the old format. |
| 666–1564 | `SLOT_COUNT` static, `BinaryReader` struct + impl, `decode_commands()`, all `aux_*`, `pool_*` methods. |

**Lines to MODIFY**:

| Lines | Current | New |
|-------|---------|-----|
| 1566–1569 | `pub(crate) fn parse_back_command_binary(...)` → `Reader::new()` + `decode_commands()` | **Delete** entirely. |
| 1576–1590 | `lalin_jit_compile_binary`: calls `parse_back_command_binary`, then `jit.inner.compile()`, then `BackProgram::partition()` | **Rewrite** to create JITModule, call `decode::decode_module(buf, &mut module, &jit_inner.symbols)`, finalize, build artifact. |
| 1598–1620 | `lalin_object_compile_binary`: calls `parse_back_command_binary`, then `compile_object()`, then `BackProgram::partition()` | **Rewrite** to create ObjectModule, call `decode::decode_module()`, finish, emit. |

**Lines to KEEP**:

| Lines | What |
|-------|------|
| 1–20 | Imports (rewritten to remove old types, add decode) |
| 21–80 | `lalin_jit_t`, `lalin_artifact_t`, `lalin_bytes_t`, `lalin_host_session_t` structs, error helpers |
| 327–665 | `parse_back_command_tape()` text decoder (keep for now — only the binary path changes) |
| 402–665 | All `extern "C"` functions: `lalin_last_error_message`, `lalin_jit_new`, `lalin_jit_free`, `lalin_artifact_free`, `lalin_bytes_free`, `lalin_host_*`, `lalin_jit_symbol`, `lalin_jit_compile_tape`, `lalin_artifact_getpointer`, `lalin_object_compile_tape` |

**After rewrite, ffi.rs shape**: ~700 lines (down from 1629).

---

### 5. `lua/lalin/back_command_binary.lua` — Rewrite Encoder

**Goal**: Replace the MLBT v3 parametric encoder with a flat-tag encoder for the new wire format.

**Current** (lines 1–640):
- `SCALAR_TAG`, `CMD_TAG`, `OVERFLOW_TAG`, etc. tables (parametric tags)
- `WireBuilder` class with `_pool_map`, `_aux_entries`, `_cmd_buf`, string pooling, aux data
- `M.Define(T)` function that returns `{ encode = function(program) ... }`

**New**:
- Remove all sub-tag tables (`INT_OP_TAG`, `BIT_OP_TAG`, `FLOAT_OP_TAG`, `SHIFT_OP_TAG`, `ROTATE_OP_TAG`, `CAST_OP_TAG`, `COMPARE_OP_TAG`, `UNARY_OP_TAG`, `INTRINSIC_OP_TAG`, `VEC_BIN_OP_TAG`, `VEC_CMP_OP_TAG`, `VEC_MASK_OP_TAG`, `ATOMIC_RMW_OP_TAG`)
- Remove `OVERFLOW_TAG` table
- Remove `WireBuilder` class (string pool, aux data, CMD_STRIDE concept)
- Remove `shape_parts`, `base_parts`, `mem_parts`, `int_sem_parts`, `float_sem_tag`, `call_result_parts`, `call_target_parts`, `ordering_tag`, `lit_parts`, `u64_parts_from_number`

**New structure**:
- Flat tag table: `local FLAT_TAG = { CreateBlock = 1, SwitchToBlock = 2, ... IaddI32 = 20, ... }` (~90 entries)
- `memflags_bits(memory_info)` → returns u32 bitfield
- `str_to_i64(s)` → i64 raw integer (no string parsing at decode)
- Simple `encode(program)` function:
  1. Write header: `[magic, ver, n_funcs, n_sigs, n_datas, n_externs]`
  2. Write declaration section (inline, no pool for value identifiers)
  3. Write body section table
  4. For each function body, emit flat-tag commands with count-prefixed variable-length lists

**Key differences** from old encoder:
- No string pool for value/block names — all IDs are `u32`.
- No aux data section — variable-length data (block args, sig params) is inline count-prefixed.
- MemFlags is a single `u32` bitfield, not 8 slots.
- Each command has a fixed minimal slot count + optional variable prefix.
- Export symbol names are written in a small trailing string table.

---

### 6. `lua/lalin/mom/driver/lower_wire.mlua` — Rewrite MOM Encoder

**Goal**: Replace column-major parametric encoder with flat-tag encoder for the MOM native path.

**Current** (lines 1~284):
- `mom_wire_slot_count()` — switch on 61 parametric tags
- `mom_schema_cmd_tag_to_wire()` — schema tag → MLBT v3 tag mapping
- `mom_write_cmd_columns_to_wire()` — column-major write
- `mom_wire_value_pool()` — value_id pool adjustment

**New**:
- Rewrite `mom_wire_slot_count` to use ~90 flat tags
- Replace `mom_schema_cmd_tag_to_wire` with direct flat tag mapping
- Remove `mom_wire_value_pool` (no pool needed — wire IDs pass through as-is)
- Add `mw_memflags()` helper: compute u32 bitfield from alignment/trap/motion
- `mom_write_cmd_columns_to_wire` emits flat tags with inline variable-length data
- Remove `mw_write_pool_string`, `mw_write_pool_slice`, `mw_write_pool_generated` (only extern names need strings)
- Remove `mw_begin_aux`, `mw_write_aux_i32s` (no aux data section)

---

### 7. `BACK_WIRE_FORMAT.md` — Rewrite Specification

**Goal**: Complete specification of the new flat-tag section-indexed format.

**Sections**:
1. **Header** — magic `0x4D4C` (little-endian), version `4`, counts, offsets
2. **Declaration Section** — inline records for CreateSig, DeclareFunc, DeclareData, DeclareExtern, DataInit
3. **Body Section Table** — per-function offset+length entries
4. **Function Body Format** — flat tag+slots stream
5. **Flat Tag Table** — all ~90 tags with slot layouts
6. **MemFlags Bitfield** — bit assignments
7. **Variable-Length Encoding** — count-prefixed inline lists
8. **Trailing String Table** — for extern symbol names
9. **Migrated vs Dropped Fields** — what changed from MLBT v3

---

### 8. `tests/test_back_*.lua` (21 test files)

**Goal**: Update Lua-side tests to construct flat-tag wire bytes instead of BackProgram ASDL + old binary encoder.

**Minimal change approach**: Each test currently:
```lua
local binary_api = require("lalin.back_command_binary").Define(T)
local payload = binary_api.encode(program)
local artifact = jit:compile(payload)
```

With the rewrite, `back_command_binary.Define(T).encode(program)` still works — it now emits flat tags instead of parametric tags. **Most Lua tests should pass without changes** because the Lua-side ASDL types (`B2.BackProgram({...})`) are the same; only the encoder changes.

**However**, some tests may construct `BackProgram` values with fields that no longer exist in the wire format:
- `BackIntSemantics`, `BackFloatSemantics` — these ASDL types still exist on the Lua side for the `tree_to_back` lowering, but the encoder now discards them. The test construction needs to check.
- Memory info construction — tests that build `BackMemoryInfo` directly may need to adjust.

**Tests to verify specifically**:
- `test_back_command_binary.lua` — tests the old encoder directly; needs complete rewrite or removal.
- `test_back_program.lua` — tests BackProgram partitioning; remove this test.
- `test_back_add_i32.lua` — constructs `BackIntSemantics`, verify encoder handles it.

---

### 9. `tests/test_back_object_emit.lua`, `tests/test_back_object_full.lua`

**Goal**: Update object emission tests to work with new wire format.

These tests call `lalin_object_compile_binary` with encoded payload. If the encoder is updated to emit flat tags, the test wire bytes change, but the test API surface (`lalin.Object.Define(T)`) stays the same. **No changes needed** to the Lua test logic — only the encoder output changes.

---

## Order of Operations

1. **First**: Create `src/wire_tags.rs` — the tag enum and slot-count table. This is imported by everything else and has no dependencies.

2. **Second**: Create `src/decode.rs` — the streaming decoder. Depends on `wire_tags.rs`. Can be tested with a small hardcoded wire buffer.

3. **Third**: Rewrite `src/lib.rs` — delete old types, add `pub mod wire_tags; pub mod decode;`, rewrite `Jit::compile_binary`, `compile_object_binary`, and the `Artifact` internals. Remove everything between `LalinError` and `Jit/Artifact`. Keep `BackScalar` and `host_isa`.

4. **Fourth**: Rewrite `src/ffi.rs` — delete old binary decoder, rewrite `lalin_jit_compile_binary` and `lalin_object_compile_binary` to call `decode::decode_module`. Keep all other C exports.

5. **Fifth**: Rewrite `lua/lalin/back_command_binary.lua` — flat-tag encoder.

6. **Sixth**: Rewrite `lua/lalin/mom/driver/lower_wire.mlua` — flat-tag MOM encoder.

7. **Seventh**: Rewrite `BACK_WIRE_FORMAT.md` — full spec.

8. **Eighth**: Update Rust tests in `src/lib.rs` `mod tests { }` — rewrite to construct wire bytes directly.

9. **Ninth**: Run `cargo build --release`, then `luajit tests/test_back_add_i32.lua` incrementally.

---

## Testing Strategy

- **After step 1** (wire_tags.rs alone): `cargo check` — no-op, module not referenced yet.
- **After step 2** (decode.rs alone): `cargo check` — module not referenced from lib.rs yet, but can `cargo check --lib` by adding `pub mod decode;` temporarily.
- **After step 3** (lib.rs rewrite): `cargo build --release` should compile. Run `cargo test` — 6 Rust tests will fail because we haven't rewritten them yet. That's expected.
- **After step 4** (ffi.rs rewrite): `cargo build --release` clean compile.
- **After step 5** (binary encoder rewrite): Run `luajit tests/test_back_add_i32.lua` — this round-trips through the new encoder + new decoder.
- **After step 8** (Rust tests): `cargo test` — all 6 tests pass.
- **Final**: Run the full test suite: `for t in tests/test_back_*.lua; do luajit "$t"; done`

---

## Pattern Memo

- **All new wire tags** use `#[repr(u32)]` enum with explicit integer values. No gaps between 1..N are permitted.
- **Error messages** use the pattern: `"decode func {func_id}: {detail}"` — always include the function ID for traceability.
- **The `DecodeResult`** must return function pointer lookup table keyed by symbol name (String) → Cranelift FuncId, so Artifact can produce `getpointer_by_name`.
- **`BackScalar`** is kept in `lib.rs` (moved to be a small standalone enum + impl), but `clif_type()` is still used by the decoder's constant-lowering path.
- **No `unsafe` blocks** in `decode.rs` except for reading from `&[u8]` (which is safe via `read_u32` helper).
- **The decoder reads all inline-counted data** (block args, sig params/results) as fixed-size reads: count prefix, then N × u32.
- **Function entry block params** are implicit: the first M `AppendBlockParam` commands targeting block 0 define the function parameters, M = sig.param_count. If fewer or more, that's a decode error.
- **All blocks are sealed at body end** via `builder.seal_all_blocks()`, never inline.
- **The Jit struct's `symbols` HashMap** passes through to `decode_module` so Cranelift can link extern function symbols.

---

## Danger Zones

1. **`lib.rs` line ~1187 (old Compiler)** — The `declare_all()` method calls `module.declare_function()` etc. The new decoder must call the same Cranelift Module API methods, but in a streaming fashion. Ensure that `module.declare_function()` for externs is called BEFORE function body processing (Phase 2 processes all declarations before Phase 3 starts).

2. **`lib.rs` line ~1581 (old FunctionLowerer::new)** — Takes `&'b mut FunctionBuilder<'a>` with complex lifetime. The new decoder in `decode.rs` must similarly scope the FunctionBuilder borrow correctly. Use the same pattern: create the builder, call `decode_instrs` with a `&mut FunctionBuilder`, drop the borrow, then `seal_all_blocks` and `finalize`.

3. **`ffi.rs` line ~1587** — The current `lalin_jit_compile_binary` calls `jit.inner.compile(&BackProgram::partition(cmds)?)`. The new version must call `decode::decode_module(buf, &mut module, &jit_inner.symbols)` where `module` is freshly created. This means the module creation moves into the function — currently `jit.inner` holds a `Jit { symbols }` without a module.

4. **MemFlags bitfield** — The new format uses `u32 bit 0=notrap, 1=aligned, 2=can_move`. The old `BackMemoryInfo::memflags()` logic computed aligned based on `alignment >= natural_align`. The frontend must now compute this bit before encoding. Ensure the encoder and decoder agree on the bit positions.

5. **Artifact API** — `Artifact` currently uses `HashMap<BackFuncId, *const u8>` for function pointers. `BackFuncId(String)` is deleted. Replace with `HashMap<String, *const u8>` keyed by the wire-provided symbol name (export name for exported functions, hex-encoded for local). The C API `lalin_artifact_getpointer(artifact, "add1")` continues to work because it takes a C string.

6. **The `compile_object` pub function** at `lib.rs` line ~1125 takes `&BackProgram`. Since `BackProgram` is deleted, this function signature must change. The new name is `compile_object_binary` (already exists at line 1094) — keep only the `compile_object_binary` variant that takes raw bytes and calls the new decoder.

## Worker Output — 2026-05-18 15:41:10

Let me verify the shared library is produced:
