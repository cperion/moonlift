# MoonLift Rust Backend — Complete Reference

## Architecture Overview

The MoonLift Rust backend is a Cranelift-based code generator that compiles a
flat IR (the `BackCmd` command stream) into native machine code. It supports
both JIT and AOT compilation paths and is driven from LuaJIT via the FFI or
directly embedded.

```
┌──────────────────────────────────────────────────────────────────┐
│  Lua frontend (mlua/*.mlua)                                      │
│  ┌─────────────────┐   ┌──────────────────┐   ┌───────────────┐ │
│  │ protocols.mlua   │   │ jit/ir.mlua      │   │ asm/x64_*.mlua │ │
│  │ (type system)    │   │ (IR construction)│   │ (asm emission) │ │
│  └────────┬────────┘   └────────┬─────────┘   └───────┬───────┘ │
│           │                     │                       │         │
│           ▼                     ▼                       ▼         │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │  BackCommandTape (tab-separated text format)                  ││
│  │  or BackProgram (Rust Vec<BackCmd>)                           ││
│  └──────────────────────────┬───────────────────────────────────┘│
└─────────────────────────────┼────────────────────────────────────┘
                              │
┌─────────────────────────────┼────────────────────────────────────┐
│  Rust backend (src/*.rs)    ▼                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │ ffi.rs   │  │ lib.rs   │  │ main.rs  │  │ host_arena.rs    │ │
│  │ (C API)  │  │ (core)   │  │ (binary) │  │ (typed alloc)    │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────────┬─────────┘ │
│       │              │             │                  │           │
│       ▼              ▼             ▼                  ▼           │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │  Cranelift (codegen, frontend, jit, module, object)           ││
│  │  → machine code (in-process JIT) or .o file (AOT)             ││
│  └──────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

## Files

| File | Lines | Purpose |
|---|---|---|
| `src/lib.rs` | ~2595 | Core: BackCmd IR, Compiler, FunctionLowerer, Jit/Artifact API, tests |
| `src/main.rs` | ~150 | Host binary: embeds LuaJIT via mlua, loads .mlua files |
| `src/ffi.rs` | ~540 | C FFI: tape parser, extern C wrappers, error handling |
| `src/host_arena.rs` | ~270 | Typed arena: MoonHostRef/MoonHostPtr, HostSession, field writes |
| `src/lua_api.rs` | ~160 | Lua C API symbols registered for compiled code to call |

## Dependencies (Cargo.toml)

```
cranelift-codegen 0.131.0    — core code generation
cranelift-frontend 0.131.0   — FunctionBuilder, Switch
cranelift-jit 0.131.0        — in-process JIT compilation
cranelift-module 0.131.0     — module linking, data objects
cranelift-object 0.131.0     — AOT object file emission
cranelift-native 0.131.0     — host ISA detection
mlua 0.10 (luajit feature)   — LuaJIT embedding for the host binary
```

---

## The BackCmd IR Schema

The `BackCmd` enum is the complete interface between the frontend and backend.
It is a flat, imperative command stream — there is no nesting, no SSA
construction on the Rust side. Each command maps directly to a Cranelift IR
operation.

### Primitive Types

```rust
enum BackScalar {
    Bool,                              // i1, stored as i8
    I8, I16, I32, I64,                 // signed integers
    U8, U16, U32, U64,                 // unsigned integers
    F32, F64,                          // IEEE floats
    Ptr,                               // pointer (host pointer width)
    Index,                             // array index (host pointer width)
}
```

Each `BackScalar` maps to a Cranelift `Type`:
- `Bool` → `types::I8`
- `I8`/`U8` → `types::I8`
- `I16`/`U16` → `types::I16`
- `I32`/`U32` → `types::I32`
- `I64`/`U64` → `types::I64`
- `F32` → `types::F32`
- `F64` → `types::F64`
- `Ptr`/`Index` → `ptr_ty` (host pointer type: I32 on 32-bit, I64 on 64-bit)

### Vector Types

```rust
struct BackVec {
    elem: BackScalar,    // element type
    lanes: u32,          // lane count (must be power of two, >= 2)
}
```

Vector CLIF types are constructed as `elem_ty.by(lanes)`. Currently only
integer vector ops are fully supported; float vector select is deferred.

### Integer Semantics

```rust
enum BackIntOverflow { Wrap, NoSignedWrap, NoUnsignedWrap, NoWrap }
enum BackIntExact { MayLose, Exact }

struct BackIntSemantics {
    overflow: BackIntOverflow,
    exact: BackIntExact,
}
```

Currently, the integer semantics fields are accepted by the lowering but
Cranelift does not receive wrapping hints — all integer arithmetic uses
Cranelift's default behavior. The semantics are preserved in the IR for
future use.

### Float Semantics

```rust
enum BackFloatSemantics { Strict, FastMath }
```

Currently informational; Cranelift float ops don't receive these hints yet.

### Memory Info

```rust
enum BackAlignment  { Unknown, Known(u32), AtLeast(u32), Assumed(u32) }
enum BackDereference { Unknown, Bytes(u32), Assumed(u32) }
enum BackTrap       { MayTrap, NonTrapping, Checked }
enum BackMotion     { MayNotMove, CanMove }
enum BackAccessMode { Read, Write, ReadWrite }

struct BackMemoryInfo {
    access: BackAccessId,    // identity label (for debugging/invalidation)
    alignment: BackAlignment,
    dereference: BackDereference,
    trap: BackTrap,
    motion: BackMotion,
    mode: BackAccessMode,
}
```

This maps to Cranelift `MemFlags`:
- `NonTrapping` → `flags.set_notrap()`
- `CanMove` → `flags.set_can_move()`
- `Known(n)`/`AtLeast(n)`/`Assumed(n)` where `n >= natural_align` → `flags.set_aligned()`
- `MayTrap` + `dereference` bytes ≥ access bytes → `flags.set_notrap()` (elides trap because bounds are provably safe)

### ID Types (newtype wrappers around String)

```
BackSigId       BackFuncId      BackExternId    BackDataId
BackBlockId     BackValId       BackStackSlotId  BackAccessId
```

All IDs are `String`-backed. The `id_type!` macro generates the newtype with
`Clone`, `Debug`, `PartialEq`, `Eq`, `Hash`, and `From<&str>`/`From<String>`.

### Switch Cases

```rust
struct BackSwitchCase {
    raw: String,        // the case value as text (parsed per type rules)
    dest: BackBlockId,  // target block for this case
}
```

---

## Complete BackCmd Reference

### Module-Level Commands

These must appear outside function bodies (or are re-validated inside).

| Command | Parameters | Description |
|---|---|---|
| `CreateSig(id, params, results)` | sig id, vec of param scalars, vec of result scalars (≤1 for now) | Define a function signature |
| `DeclareData(id, size, align)` | data id, byte size, byte alignment (power of 2, ≥1) | Declare a global data object |
| `DataInitZero(id, offset, size)` | data id, byte offset, byte length | Zero-fill a region of a data object |
| `DataInitInt(id, offset, ty, raw)` | data id, offset, scalar type, text integer | Write an integer into a data object |
| `DataInitFloat(id, offset, ty, raw)` | data id, offset, scalar type, text float | Write a float into a data object |
| `DataInitBool(id, offset, value)` | data id, offset, bool | Write a bool (1 byte: 0 or 1) into a data object |
| `DataAddr(dst, id)` | value id, data id | Get the address of a data object → ptr value |
| `FuncAddr(dst, id)` | value id, func id | Get the address of a function → ptr value |
| `ExternAddr(dst, id)` | value id, extern id | Get the address of an extern → ptr value |
| `DeclareFuncLocal(id, sig)` | func id, sig id | Declare a local (non-exported) function |
| `DeclareFuncExport(id, sig)` | func id, sig id | Declare an exported function (uses its id as symbol name) |
| `DeclareFuncExtern(id, symbol, sig)` | extern id, C symbol name, sig id | Declare an external (imported) function |
| `FinalizeModule` | — | Marker for end of module (must be last, at top level) |

### Function Delimitation

| Command | Description |
|---|---|
| `BeginFunc(id)` | Start a function body. Must match a prior DeclareFunc*. Nesting not allowed. |
| `FinishFunc(id)` | End a function body. Must match the most recent BeginFunc. |

Between BeginFunc and FinishFunc, all remaining commands form the function body.

### Block and CFG

| Command | Parameters | Description |
|---|---|---|
| `CreateBlock(id)` | block id | Create a new basic block |
| `SwitchToBlock(id)` | block id | Switch the builder to this block (subsequent instructions go here) |
| `SealBlock(id)` | block id | Seal the block (no more predecessors will be added; enables SSA construction) |
| `BindEntryParams(block, vals)` | block id, vec of value ids | Bind function entry parameters to the block (only on entry block). Binds `block_params[i]` → `vals[i]`. |
| `AppendBlockParam(block, val, scalar)` | block id, value id, scalar type | Append a typed block parameter and bind it to the given value id |
| `AppendVecBlockParam(block, val, vec)` | block id, value id, vector type | Same for vector-typed block parameters |

### Value Binding

| Command | Parameters | Description |
|---|---|---|
| `Alias(dst, src)` | value id, value id | Bind dst to the same Cranelift Value as src. No new instruction. |

Values are single-assignment: each `BackValId` may be bound at most once per function.

### Constants

| Command | Parameters | Description |
|---|---|---|
| `ConstInt(dst, ty, raw)` | value id, scalar type, text integer | Create an integer constant. Raw is parsed as i64 (signed types) or u64→i64 (unsigned/ptr). Bool rejected — use ConstBool. |
| `ConstFloat(dst, ty, raw)` | value id, scalar type, text float | Create a float constant. Raw is parsed as f32 or f64. |
| `ConstBool(dst, value)` | value id, bool | Create a bool constant (i8: 0 or 1). |
| `ConstNull(dst)` | value id | Create a null pointer (ptr_ty zero constant). |

### Stack Slots

| Command | Parameters | Description |
|---|---|---|
| `CreateStackSlot(id, size, align)` | slot id, byte size, byte alignment (power of 2) | Create an explicit stack slot |
| `StackAddr(dst, slot)` | value id, slot id | Get the address of a stack slot → ptr value |

### Unary Operations

| Command | Parameters | Cranelift IR |
|---|---|---|
| `Ineg(dst, ty, val)` | dst, scalar (for context), src val | `ineg` |
| `Fneg(dst, ty, val)` | dst, scalar, src val | `fneg` |
| `Bnot(dst, ty, val)` | dst, scalar, src val | `bnot` |
| `BoolNot(dst, val)` | dst, src val | `icmp_imm(Equal, val, 0)` → select between 0 and 1 |
| `Popcount(dst, ty, val)` | dst, scalar, src val | `popcnt` |
| `Clz(dst, ty, val)` | dst, scalar, src val | `clz` |
| `Ctz(dst, ty, val)` | dst, scalar, src val | `ctz` |
| `Bswap(dst, ty, val)` | dst, scalar, src val | `bswap` |
| `Sqrt(dst, ty, val)` | dst, scalar, src val | `sqrt` |
| `Abs(dst, ty, val)` | dst, scalar, src val | `fabs` (float) or `iabs` (integer) |
| `Floor(dst, ty, val)` | dst, scalar, src val | `floor` |
| `Ceil(dst, ty, val)` | dst, scalar, src val | `ceil` |
| `TruncFloat(dst, ty, val)` | dst, scalar, src val | `trunc` |
| `Round(dst, ty, val)` | dst, scalar, src val | `nearest` |

### Binary Operations

All take `(dst, scalar_type, int_semantics_or_float_semantics, lhs, rhs)`.

| Command | Cranelift IR |
|---|---|
| `Iadd` | `iadd` |
| `Isub` | `isub` |
| `Imul` | `imul` |
| `Fadd` | `fadd` |
| `Fsub` | `fsub` |
| `Fmul` | `fmul` |
| `Sdiv` | `sdiv` |
| `Udiv` | `udiv` |
| `Fdiv` | `fdiv` |
| `Srem` | `srem` |
| `Urem` | `urem` |

### Bitwise Operations

| Command | Cranelift IR |
|---|---|
| `Band(dst, ty, lhs, rhs)` | `band` |
| `Bor(dst, ty, lhs, rhs)` | `bor` |
| `Bxor(dst, ty, lhs, rhs)` | `bxor` |
| `Ishl(dst, ty, lhs, rhs)` | `ishl` |
| `Ushr(dst, ty, lhs, rhs)` | `ushr` |
| `Sshr(dst, ty, lhs, rhs)` | `sshr` |
| `Rotl(dst, ty, lhs, rhs)` | `rotl` |
| `Rotr(dst, ty, lhs, rhs)` | `rotr` |

### Integer Comparisons

All produce a bool value (i8: 0 or 1). `IntCC` used:

| Command | IntCC |
|---|---|
| `IcmpEq` | `Equal` |
| `IcmpNe` | `NotEqual` |
| `SIcmpLt` | `SignedLessThan` |
| `SIcmpLe` | `SignedLessThanOrEqual` |
| `SIcmpGt` | `SignedGreaterThan` |
| `SIcmpGe` | `SignedGreaterThanOrEqual` |
| `UIcmpLt` | `UnsignedLessThan` |
| `UIcmpLe` | `UnsignedLessThanOrEqual` |
| `UIcmpGt` | `UnsignedGreaterThan` |
| `UIcmpGe` | `UnsignedGreaterThanOrEqual` |

### Float Comparisons

Same pattern, using `FloatCC`:

| Command | FloatCC |
|---|---|
| `FCmpEq` | `Equal` |
| `FCmpNe` | `NotEqual` |
| `FCmpLt` | `LessThan` |
| `FCmpLe` | `LessThanOrEqual` |
| `FCmpGt` | `GreaterThan` |
| `FCmpGe` | `GreaterThanOrEqual` |

### Type Conversions

| Command | Cranelift IR |
|---|---|
| `Bitcast(dst, ty, val)` | `bitcast` |
| `Ireduce(dst, ty, val)` | `ireduce` (truncate integer) |
| `Sextend(dst, ty, val)` | `sextend` |
| `Uextend(dst, ty, val)` | `uextend` |
| `Fpromote(dst, ty, val)` | `fpromote` (f32→f64) |
| `Fdemote(dst, ty, val)` | `fdemote` (f64→f32) |
| `SToF(dst, ty, val)` | `fcvt_from_sint` |
| `UToF(dst, ty, val)` | `fcvt_from_uint` |
| `FToS(dst, ty, val)` | `fcvt_to_sint` |
| `FToU(dst, ty, val)` | `fcvt_to_uint` |

### Memory Operations

| Command | Parameters | Description |
|---|---|---|
| `LoadInfo(dst, ty, addr, mem)` | dst, scalar type, ptr value, BackMemoryInfo | Load from memory |
| `StoreInfo(ty, addr, val, mem)` | scalar type, ptr, value, BackMemoryInfo | Store to memory |
| `Memcpy(dst, src, len)` | ptr, ptr, ptr-size length | Call `call_memcpy` libcall |
| `Memset(dst, byte, len)` | ptr, i8 value id, ptr-size length | Call `call_memset` libcall. byte value is ireduced to i8 if needed. |

### Pointer Arithmetic

| Command | Parameters | Description |
|---|---|---|
| `PtrAdd(dst, base, offset)` | dst, ptr base, ptr byte offset | `iadd(base, offset)`. Both must be ptr_ty. |
| `PtrOffset(dst, base, index, elem_size, const_offset)` | dst, ptr base, ptr index, u32 elem size, i64 const offset | `iadd(base, iadd(imul(index, iconst(elem_size)), iconst(const_offset)))` |

### Control Flow

| Command | Parameters | Description |
|---|---|---|
| `Select(dst, ty, cond, then_val, else_val)` | dst, scalar, condition (bool→icmp_imm NE 0), then, else | `select(cond, then, else)` |
| `Fma(dst, ty, sem, a, b, c)` | dst, scalar, float sem, 3 values | `fma(a, b, c)` |
| `Jump(dest, args)` | block id, vec of value ids | Unconditional branch with block arguments |
| `BrIf(cond, then_block, then_args, else_block, else_args)` | cond value, 2× (block, args) | Conditional branch |
| `SwitchInt(val, ty, cases, default)` | value, scalar type, vec of (raw text, block id), default block | Switch table (Cranelift Switch). Cases parsed per type rules. |
| `ReturnVoid` | — | Void return |
| `ReturnValue(val)` | value id | Return single value |
| `Trap` | — | Emit `trap(TrapCode::unwrap_user(1))` |

### Calls

Three target kinds × two result kinds = 6 call commands:

| Command | Description |
|---|---|
| `CallValueDirect(dst, result_ty, func, sig, args)` | Call declared local/export function, capture result |
| `CallStmtDirect(func, sig, args)` | Call declared function, discard result |
| `CallValueExtern(dst, result_ty, extern_id, sig, args)` | Call extern (imported) function, capture result |
| `CallStmtExtern(extern_id, sig, args)` | Call extern function, discard result |
| `CallValueIndirect(dst, result_ty, callee_val, sig, args)` | Call through function pointer, capture result |
| `CallStmtIndirect(callee_val, sig, args)` | Call through function pointer, discard result |

All calls currently support at most 1 result value. The signature is retrieved
from the declared `BackSigId` and imported into the function via
`builder.import_signature()`. For direct calls, the function reference is
obtained via `module.declare_func_in_func()`.

### Vector Operations

| Command | Parameters | Cranelift IR |
|---|---|---|
| `VecSplat(dst, vec_ty, scalar)` | dst, BackVec, scalar value id | `splat` |
| `VecIcmpEq/Ne/Lt/Le/Gt/Ge` | dst, BackVec, 2 val ids | `icmp(IntCC, ...)` |
| `VecSelect(dst, vec_ty, mask, then, else)` | dst, BackVec, 3 val ids | `band(mask,then)` + `band(bnot(mask),else)` + `bor` (int only; float rejected) |
| `VecMaskNot(dst, vec_ty, val)` | dst, BackVec, val | `bnot` |
| `VecMaskAnd/Or(dst, vec_ty, 2 vals)` | dst, BackVec, 2 val ids | `band` / `bor` |
| `VecIadd/Isub/Imul(dst, vec_ty, 2 vals)` | dst, BackVec, 2 val ids | `iadd` / `isub` / `imul` |
| `VecBand/Bor/Bxor(dst, vec_ty, 2 vals)` | dst, BackVec, 2 val ids | `band` / `bor` / `bxor` |
| `VecLoadInfo(dst, vec_ty, addr, mem)` | dst, BackVec, ptr val, BackMemoryInfo | `load` |
| `VecStoreInfo(vec_ty, addr, val, mem)` | BackVec, ptr val, value val, BackMemoryInfo | `store` |
| `VecInsertLane(dst, vec_ty, vector, lane_val, lane)` | dst, BackVec, 2 val ids, u32 lane idx | `insertlane` |
| `VecExtractLane(dst, scalar_ty, vector, lane)` | dst, scalar type, val, u32 lane idx | `extractlane` |

Vector types must have lane counts that are powers of two ≥ 2. Lane
indices are validated against `ty.lanes`. Element types are validated
against the vector's lane type.

---

## Compilation Pipeline

### Phase 1: Collect (`Compiler::collect`)

The full `BackProgram::cmds` list is scanned once to:

1. **Separate global declarations from function bodies**: `BeginFunc`/`FinishFunc`
   pairs delimit function bodies. Everything between them is collected into
   `self.bodies` as `(BackFuncId, Vec<BackCmd>)`.
2. **Validate nesting**: Nested `BeginFunc`, unmatched `FinishFunc`,
   unterminated function bodies are all errors.
3. **Collect global decls**: Each `BackCmd` variant relevant to declarations
   (`CreateSig`, `DeclareData`, `DeclareFuncLocal`, etc.) is processed by
   `collect_global_decl()` which stores entries in `self.signatures`,
   `self.datas`, `self.funcs`, `self.externs`. Duplicate declarations with
   mismatched shapes are rejected.
4. **Validate top-level**: Only declaration commands, `BeginFunc`, and
   `FinalizeModule` are allowed outside function bodies.

### Phase 2: Declare (`Compiler::declare_all`)

All collected declarations are registered with the Cranelift `Module`:

- **Data objects**: `module.declare_data()` with `Linkage::Local`
- **Externs**: `module.declare_function()` with `Linkage::Import`
- **Functions**: `module.declare_function()` with `Linkage::Local` or
  `Linkage::Export` (exported functions use the function id as the symbol name;
  local functions get a hex-encoded symbol `moonlift_fn_<hex>`)

### Phase 3: Define (`Compiler::define_all`)

1. **Data objects**: For each `DataDecl`, build a byte vector, apply all
   `DataInit` operations in order (zero, int, float, bool), then
   `module.define_data()`.
2. **Function bodies**: For each function:
   - Create a `FunctionBuilderContext` and Cranelift `Context`
   - Create a `FunctionLowerer` and call `lower(cmds)` which processes
     each `BackCmd` in the body
   - Seal all blocks with `builder.seal_all_blocks()`
   - Finalize with `builder.finalize()`
   - If `MOONLIFT_DUMP_CLIF=1`, print the CLIF IR to stderr
   - Call `module.define_function()` and `module.clear_context()`

### JIT Finalization

`Compiler::compile()` calls `module.finalize_definitions()` then extracts
function pointers via `module.get_finalized_function()` into the `Artifact`.

### AOT Finalization

`Compiler::compile_object()` calls `module.finish()` then
`product.emit()` → `ObjectArtifact` bytes.

---

## Function Lowering

`FunctionLowerer` is the per-function lowering engine. It maintains:

| Map | Key → Value |
|---|---|
| `values: HashMap<BackValId, Value>` | MoonLift value id → Cranelift SSA Value |
| `blocks: HashMap<BackBlockId, Block>` | MoonLift block id → Cranelift Block |
| `stack_slots: HashMap<BackStackSlotId, StackSlot>` | MoonLift slot id → Cranelift StackSlot |

### Lowering Rules

Each `BackCmd` is lowered by a dedicated method or match arm:

- **Re-declaration commands** (`CreateSig`, `DeclareData`, etc.): Validated
  against what was collected in phase 1 to ensure the function body doesn't
  contradict the module declarations.
- **Value binding**: `bind_value()` inserts into `self.values`, errors on
  duplicate.
- **Value lookup**: `value()` looks up by id, errors if unknown.
- **Block lookup**: `block()` looks up by id, errors if unknown.
- **Type checking**: `require_value_type()` validates that a Cranelift Value
  has the expected type, used for pointer operations, vector ops, etc.
- **Condition values**: `cond_value()` converts a bool (i8) to a Cranelift
  condition by emitting `icmp_imm(NotEqual, raw, 0)`.
- **Bool from condition**: `bool_value_from_cond()` converts a Cranelift
  condition result back to i8 via `select(cond, iconst(1), iconst(0))`.
- **Call single-result extraction**: `take_single_result()` requires exactly
  one result from calls (multi-result is not yet supported).

---

## The Jit API

### Construction

```rust
let mut jit = Jit::new();
jit.symbol("my_func", my_func_ptr as *const u8);
```

### Compilation

```rust
let program = BackProgram::new(vec![
    BackCmd::CreateSig(...),
    BackCmd::DeclareFuncExport(...),
    BackCmd::BeginFunc(...),
    // ... function body commands ...
    BackCmd::FinishFunc(...),
    BackCmd::FinalizeModule,
]);
let artifact = jit.compile(&program)?;
```

### Retrieving Function Pointers

```rust
let ptr: *const c_void = artifact.getpointer(&BackFuncId::from("my_func"))?;
let f: extern "C" fn(i32) -> i32 = unsafe { std::mem::transmute(ptr) };
let result = f(42);
```

### Tape-Based Compilation

```rust
let tape = "moonlift-back-command-tape-v2\nCmdCreateSig\t...";
let artifact = jit.compile_tape(tape)?;
```

### AOT Compilation

```rust
let obj = compile_object(&program, "my_module")?;
std::fs::write("output.o", obj.bytes())?;
```

---

## Tape Format (BackCommandTape v2)

The tape format is a tab-separated text protocol for cross-language
communication (used between Lua and Rust, and via the C FFI).

**Header**: `moonlift-back-command-tape-v2`

Each line after the header is one command. Fields are separated by `\t`.
Escape sequences: `\n`, `\t`, `\\`.

### Command Reference

```
CmdCreateSig          sig  nparams  param0...paramN  nresults  result0...resultN
CmdDeclareData        data  size  align
CmdDataInitZero       data  offset  size
CmdDataInit           data  offset  scalar_code  I|F|B|N  literal
CmdDataAddr           dst   data
CmdFuncAddr           dst   func
CmdExternAddr         dst   extern
CmdDeclareFunc        E|L   func  sig
CmdDeclareExtern      extern  symbol  sig
CmdBeginFunc          func
CmdFinishFunc         func
CmdCreateBlock        block
CmdSwitchToBlock      block
CmdSealBlock          block
CmdBindEntryParams    block  nvals  val0...valN
CmdAppendBlockParam   block  val  S|V  scalar|elem lanes
CmdCreateStackSlot    slot  size  align
CmdAlias              dst  src
CmdStackAddr          dst  slot
CmdConst              dst  scalar  I|F|B|N  literal
CmdUnary              dst  op  S|V  scalar|elem lanes  value
CmdIntrinsic          dst  op  S|V  scalar|elem lanes  nargs  arg0...argN
CmdCompare            dst  op  S|V  scalar|elem lanes  lhs  rhs
CmdCast               dst  op  scalar  value
CmdPtrOffset          dst  base_kind  base  index  elem_size  const_offset
CmdLoadInfo           dst  S|V  scalar|elem lanes  addr_base_kind  addr_base  byte_offset  access  align_kind  align_bytes  deref_kind  deref_bytes  trap_kind  motion_kind  mode_kind
CmdStoreInfo          S|V  elem lanes  addr_base_kind  addr_base  byte_offset  value  access  ...memory_info...
CmdIntBinary          dst  op  scalar  overflow  exact  lhs  rhs
CmdBitBinary          dst  op  scalar  lhs  rhs
CmdBitNot             dst  scalar  value
CmdShift              dst  op  scalar  lhs  rhs
CmdRotate             dst  op  scalar  lhs  rhs
CmdFloatBinary        dst  op  scalar  semantics  lhs  rhs
CmdMemcpy             dst  src  len
CmdMemset             dst  byte  len
CmdSelect             dst  S|V  scalar|elem lanes  cond  then  else
CmdFma                dst  scalar  sem  a  b  c
CmdVecSplat           dst  elem  lanes  value
CmdVecBinary          dst  op  elem  lanes  lhs  rhs
CmdVecCompare         dst  op  elem  lanes  lhs  rhs
CmdVecSelect          dst  elem  lanes  mask  then  else
CmdVecMask            dst  op  elem  lanes  nargs  arg0  [arg1]
CmdVecInsertLane      dst  elem  lanes  value  lane_value  lane_index
CmdVecExtractLane     dst  scalar  value  lane_index
CmdCall               result_kind  result_dst  result_ty  target_kind  target  sig  nargs  arg0...argN
CmdJump               dest  nargs  arg0...argN
CmdBrIf               cond  then_block  n_then_args  then_arg0...then_argN  else_block  n_else_args  else_arg0...else_argN
CmdSwitchInt          value  scalar  n_cases  case0_raw  case0_dest  ...  default
CmdReturnVoid
CmdReturnValue        value
CmdTrap
CmdFinalizeModule
```

### Scalar Codes

```
1=Bool  2=I8   3=I16  4=I32  5=I64
6=U8   7=U16  8=U32  9=U64
10=F32 11=F64 12=Ptr 13=Index
```

### Operation Codes (selected)

- Unary: `BackUnaryIneg`, `BackUnaryFneg`, `BackUnaryBnot`, `BackUnaryBoolNot`
- Intrinsic: `BackIntrinsicPopcount`, `BackIntrinsicClz`, `BackIntrinsicCtz`,
  `BackIntrinsicBswap`, `BackIntrinsicSqrt`, `BackIntrinsicAbs`,
  `BackIntrinsicFloor`, `BackIntrinsicCeil`, `BackIntrinsicTruncFloat`,
  `BackIntrinsicRound`
- Compare: `BackIcmpEq/Ne`, `BackSIcmpLt/Le/Gt/Ge`, `BackUIcmpLt/Le/Gt/Ge`,
  `BackFCmpEq/Ne/Lt/Le/Gt/Ge`
- Cast: `BackBitcast`, `BackIreduce`, `BackSextend`, `BackUextend`,
  `BackFpromote`, `BackFdemote`, `BackSToF`, `BackUToF`, `BackFToS`, `BackFToU`
- Int binary: `BackIntAdd`, `BackIntSub`, `BackIntMul`, `BackIntSDiv`,
  `BackIntUDiv`, `BackIntSRem`, `BackIntURem`
- Bit binary: `BackBitAnd`, `BackBitOr`, `BackBitXor`
- Shift: `BackShiftLeft`, `BackShiftLogicalRight`, `BackShiftArithmeticRight`
- Rotate: `BackRotateLeft`, `BackRotateRight`
- Float binary: `BackFloatAdd`, `BackFloatSub`, `BackFloatMul`, `BackFloatDiv`
- Vec binary: `BackVecIntAdd`, `BackVecIntSub`, `BackVecIntMul`,
  `BackVecBitAnd`, `BackVecBitOr`, `BackVecBitXor`
- Vec mask: `BackVecMaskNot`, `BackVecMaskAnd`, `BackVecMaskOr`

### Call Kinds

- Result: `BackCallValue` | `BackCallStmt`
- Target: `BackCallDirect` | `BackCallExtern` | `BackCallIndirect`

### Memory Info Fields (in order)

```
access (string id)
align_kind (0=Unknown 1=Known 2=AtLeast 3=Assumed)
align_bytes (u32)
deref_kind (0=Unknown 1=Bytes 2=Assumed)
deref_bytes (u32)
trap_kind (0=MayTrap 1=NonTrapping 2=Checked)
motion_kind (0=MayNotMove 1=CanMove)
mode_kind (1=Read 2=Write 3=ReadWrite)
```

### Address Base Kinds

```
V = Value (existing BackValId)
S = Stack (BackStackSlotId)
D = Data (BackDataId)
```

---

## C FFI API

All extern "C" functions are declared in `src/ffi.rs`.

### Opaque Types

```c
typedef struct moonlift_jit_t moonlift_jit_t;
typedef struct moonlift_artifact_t moonlift_artifact_t;
```

### Lifecycle

```c
moonlift_jit_t *moonlift_jit_new(void);
void moonlift_jit_free(moonlift_jit_t *jit);
void moonlift_artifact_free(moonlift_artifact_t *art);
```

### Symbol Registration

```c
int moonlift_jit_symbol(moonlift_jit_t *jit, const char *name, const void *ptr);
```

Registers a C function pointer under a name. Returns 1 on success, 0 + error
message (retrievable via `moonlift_last_error_message()`).

### Compilation

```c
moonlift_artifact_t *moonlift_jit_compile_tape(
    moonlift_jit_t *jit,
    const char *tape_payload
);
```

Returns an artifact or NULL. On NULL, call `moonlift_last_error_message()`.

### AOT Compilation

```c
int moonlift_object_compile_tape(
    const char *tape_payload,
    const char *module_name,
    moonlift_bytes_t *out
);
```

Fills `out.data` and `out.len`. Caller must free with `moonlift_bytes_free()`.

### Artifact Access

```c
const void *moonlift_artifact_getpointer(
    const moonlift_artifact_t *art,
    const char *function_id
);
```

### Error Handling

```c
const char *moonlift_last_error_message(void);
```

Thread-local error string. Cleared on successful calls, set on errors.

---

## Host Arena (host_arena.rs)

A typed bump-allocator arena for host-side objects that compiled code can
reference. Uses session-based invalidation with generation counters.

### Types

```c
typedef struct {
    uint64_t session_id;
    uint32_t generation;
    uint32_t kind;       // 1 = HOST_KIND_RECORD
    uint32_t type_id;
    uint32_t tag;
    uint64_t offset;     // index into session's block vector
} MoonHostRef;

typedef struct {
    uint8_t *ptr;
    uint64_t session_id;
    uint32_t generation;
    uint32_t kind;
    uint32_t type_id;
    uint32_t tag;
} MoonHostPtr;
```

### Field Types

```
HOST_FIELD_BOOL=1  I8=2  I16=3  I32=4  I64=5
U8=6  U16=7  U32=8  U64=9  F32=10  F64=11
```

### API

```c
moonlift_host_session_t *moonlift_host_session_new(void);
void moonlift_host_session_free(moonlift_host_session_t *s);
uint64_t moonlift_host_session_id(const moonlift_host_session_t *s);
uint32_t moonlift_host_session_generation(const moonlift_host_session_t *s);
int moonlift_host_session_reset(moonlift_host_session_t *s);

int moonlift_host_alloc_record(
    moonlift_host_session_t *s,
    uint32_t type_id, uint32_t tag,
    size_t size, size_t align,
    MoonHostRef *out_ref, MoonHostPtr *out_ptr
);

int moonlift_host_alloc_records(
    moonlift_host_session_t *s,
    const MoonHostRecordSpec *specs, size_t specs_len,
    const MoonHostFieldInit *fields, size_t fields_len,
    MoonHostRef *out_refs, MoonHostPtr *out_ptrs
);

int moonlift_host_ptr_for_ref(
    const moonlift_host_session_t *s,
    MoonHostRef ref, MoonHostPtr *out_ptr
);
```

### Invalidation

`reset()` increments the generation counter and drops all blocks. Any
`MoonHostRef` or `MoonHostPtr` with a stale generation is rejected on
subsequent access.

---

## Lua API Symbols (lua_api.rs)

These are registered as extern symbols that compiled MoonLift code can
call directly (via `DeclareFuncExtern`):

| Symbol | Signature | Purpose |
|---|---|---|
| `lua_gettop` | `i32(ptr)` | Lua C API |
| `lua_settop` | `i32(ptr, i32)` | Lua C API |
| `lua_createtable` | `i32(ptr, i32, i32)` | Lua C API |
| `lua_pushlstring` | `i32(ptr, ptr, usize)` | Lua C API |
| `lua_pushnumber` | `i32(ptr, f64)` | Lua C API |
| `lua_pushboolean` | `i32(ptr, i32)` | Lua C API |
| `lua_pushnil` | `i32(ptr)` | Lua C API |
| `lua_setfield` | `i32(ptr, i32, ptr)` | Lua C API |
| `lua_settable` | `i32(ptr, i32)` | Lua C API |
| `lua_rawseti` | `i32(ptr, i32, i32)` | Lua C API |
| `moonlift_scratch_raw` | `ptr(i32 slot, i32 elem_size, i32 count)` | Zeroed scratch memory, thread-local, auto-freed on function return |
| `moonlift_scratch_i32` | `ptr(i32 slot, i32 count)` | 4-byte scratch wrapper |
| `moonlift_scratch_u8` | `ptr(i32 slot, i32 count)` | 1-byte scratch wrapper |
| `moonlift_alloc_i32` | `ptr(i32 count)` | Heap allocation (must free with moonlift_free_i32) |
| `moonlift_free_i32` | `i32(ptr, i32 count)` | Free heap allocation |
| `moonlift_lua_arg_lstring_ptr` | `ptr(ptr, i32 idx)` | Get Lua string pointer at stack index |
| `moonlift_lua_arg_lstring_len` | `isize(ptr, i32 idx)` | Get Lua string length at stack index (-1 if not a string) |
| `memcmp` | `i32(ptr, ptr, usize)` | Standard C memcmp |

---

## Host Binary (main.rs)

The `moonlift` binary embeds a LuaJIT runtime (via mlua) and exposes two
Lua globals:

- **`_host_symbol(name, ptr)`**: Register a C function pointer as a JIT symbol
- **`_host_compile(tape)`**: Compile a tape string → `HostedArtifact` userdata

`HostedArtifact` methods:
- `getpointer(name)` → raw pointer as integer
- `cfunction(name)` → LuaJIT C function (can be called from Lua)
- `call(name, args...)` → call the compiled function with Lua args, return results
- `free()` → release the artifact

The binary also sets up Lua package paths and preloads the `moonlift.back_jit`
module.

---

## ISA Configuration

The host ISA is built once (cached in `OnceLock`):

```rust
flags:
  use_colocated_libcalls = "false"
  is_pic = "true" (for AOT) / "false" (for JIT)
  opt_level = "speed"
```

Two cached ISAs: one for JIT (non-PIC) and one for AOT (PIC).

---

## Error Handling

```rust
struct MoonliftError(pub String);  // implements Error + Display
```

All compilation functions return `Result<T, MoonliftError>`. The C FFI stores
the last error in a thread-local `CString` retrievable via
`moonlift_last_error_message()`.

---

## Testing

Tests in `lib.rs` cover:

1. **Memory flag mapping**: `back_memory_info_maps_only_exact_cranelift_flags`
   verifies that `BackMemoryInfo::memflags()` produces correct Cranelift
   MemFlags for various combinations of alignment, dereference, trap, and
   motion.

2. **End-to-end compilation + execution**:
   - `compiles_and_calls_exported_function`: `add1(x) → x + 1`
   - `compiles_and_calls_registered_extern`: caller calls `triple_host` extern
   - `compiles_and_reads_data_object`: reads a constant from a data object
   - `compiles_block_param_loop_cfg`: loop with block parameters, counts 0→3,
     returns 4
   - `compiles_memcpy_command`: copies 4 bytes, returns the result
   - `compiles_memset_command`: zeroes 4 bytes, returns the result

3. **Host arena tests** (in `host_arena.rs`):
   - `alloc_record_returns_stable_ref_and_ptr`
   - `reset_rejects_stale_ref`
   - `writes_scalar_fields_by_offset`

---

## Internal Design Notes

### Why BackCmd is flat

The IR is a flat command stream rather than a tree or SSA graph because:

1. **Language boundary**: The frontend is in Lua, the backend is in Rust. A
   flat text protocol (tape) is the simplest wire format.
2. **Simplicity**: No recursive descent or graph construction needed on the
   Rust side — just iterate and dispatch.
3. **Validation is incremental**: Each command is validated as it's lowered,
   with clear error messages including the function name.

### Single-result limitation

All call and function return commands currently support exactly 0 or 1 result
values. This is explicitly enforced:

- `CreateSig` rejects signatures with >1 result
- `DeclareFunc*` rejects function declarations with >1 result sig
- `take_single_result()` panics if a call produces != 1 result (for value calls)

### Symbol naming

- **Exported functions**: use the `BackFuncId` string directly (e.g., `"add1"`)
- **Local functions**: hex-encoded to avoid collisions (`moonlift_fn_<hex>`)
- **Data objects**: prefixed similarly (`moonlift_data_<hex>`)

### Cranelift module integration

The backend uses `cranelift-module` for linking, which handles:

- Data object allocation and initialization
- Function declaration and definition
- Libcall resolution (memcpy, memset)
- Relocation and finalization

For JIT, `cranelift-jit` provides in-process memory management.
For AOT, `cranelift-object` emits ELF/Mach-O/COFF object files.

### Vectors are second-class

Float vector select is explicitly rejected with an error directing users to
a future explicit float-vector select/blend command. The int vector lowering
for select uses bitwise operations (`band(bnot(mask),else) | band(mask,then)`).

### Bool representation

Bools are stored as `i8` (0 or 1) per Cranelift convention. All comparison
operations produce a Cranelift boolean condition value which is then converted
to i8 via `select(cond, iconst(1), iconst(0))`. Control flow conditions
(`BrIf`) convert i8 back to a condition via `icmp_imm(NotEqual, val, 0)`.

### Block parameters

Functions use Cranelift's block parameter model for SSA construction:

- Entry block: `BindEntryParams` binds function signature params to block params
- Other blocks: `AppendBlockParam` adds typed params, which become Cranelift
  `BlockParam` values
- Jumps: pass values as block arguments, matched positionally
- Sealing: `SealBlock` tells Cranelift no more predecessors will be added

### The Compiler pattern: collect → declare → define

This three-phase design follows Cranelift's own conventions:

1. **Collect**: scan all commands, validate structure, build internal tables
   (signatures, funcs, externs, datas, bodies). No Cranelift interaction.
2. **Declare**: register everything with the Cranelift module. This establishes
   symbols, linkage, and types before any code references them.
3. **Define**: emit code. At this point all forward references are resolvable.
