# Backend Completeness Gaps

Audit date: 2026-06-17  
Last updated: 2026-06-19  
Workflow: `wf-backend-gap`

The Rust Cranelift backend (`src/decode.rs`) has real codegen for all 111 binary wire tags. The backend-facing gaps from the 2026-06-17 audit are closed; remaining limits are explicit subset boundaries rather than silent missing codegen paths.

---

## Current Status

| Area | Status | Notes |
|------|--------|-------|
| Binary encoder coverage | **Closed** | `back_command_binary.lua` now encodes atomics, rotate, vecmask, and errors loudly on unknown BackCmds. |
| Atomic lowering | **Closed** | `code_to_back.lua` now lowers `CodeInstAtomic*` to `CmdAtomic*`; `tests/test_atomics.lua` passes end-to-end. |
| Atomic ordering wire fidelity | **Closed for current schema** | `MoonCore.AtomicOrdering`/`BackAtomicOrdering` currently contain only `SeqCst`; the zero-slot wire encoding is lossless until weaker orderings are added. |
| Intrinsic/rotate lowering | **Closed** | `CodeInstIntrinsic` now lowers to `CmdIntrinsic`, `CmdRotate`, `CmdFma`, or `CmdTrap`; executable JIT coverage exists. |
| Vector reductions | **Closed for integer TailScalar subset** | `lower_to_back.lua` lowers supported contiguous integer reductions through vector accumulators, lane extraction, and scalar tail handling. |
| Scalar kernel fragments | **Closed** | Synthetic `KernelBinding` values now infer their Code block from instruction results, block params, memory access facts, or value expressions. |
| View return ABI | **Closed** | View results now use sret descriptor ABI and pass executable JIT coverage. |
| Closures | **Closed for descriptor ABI** | Closure descriptors lower as `{ fn, ctx }`; closure calls load both words and emit indirect calls with a synthetic context-parameter signature. Captured closure returns fail loudly pending an ownership model. |
| Handle types | **Closed/no Back object needed** | Handles lower through their declared scalar representation; typing opacity is enforced before backend lowering. |
| Debug interpreter indirect calls | **Closed** | `debug_interpreter.lua` now resolves `CmdFuncAddr` values and executes `BackCallIndirect` through the same internal call path as direct calls. |
| Hosted JIT disassembly | **Closed** | `hosted_jit.lua` now supports `getbytes`, `hexbytes`, `disasm`, and `peek`; verified through the standalone hosted binary. |

---

## Closed: Binary Encoder Gaps

The following ASDL `Cmd` variants used to be silently dropped by `lua/moonlift/back_command_binary.lua`; they are now encoded:

- `CmdAtomicLoad` → `AtomicLoad` (112)
- `CmdAtomicStore` → `AtomicStore` (113)
- `CmdAtomicRmw` → `AtomicRmw` (114)
- `CmdAtomicCas` → `AtomicCas` (115)
- `CmdAtomicFence` → `Fence` (116)
- `CmdRotate` → `Rotl` (63) / `Rotr` (64)
- `CmdVecMask` → `VecMaskNot` (150) / `VecMaskAnd` (151) / `VecMaskOr` (152)

The encoder now ends its `encode_body()` dispatch with:

```lua
else
    error("unrecognized BackCmd: " .. tostring(k))
end
```

Future BackCmd/schema drift should fail at encode time rather than producing a shorter invalid wire buffer.

---

## Closed: Atomic Code→Back Lowering

`lua/moonlift/code_to_back.lua` now lowers:

- `CodeInstAtomicLoad` → `Back.CmdAtomicLoad`
- `CodeInstAtomicStore` → `Back.CmdAtomicStore`
- `CodeInstAtomicRmw` → `Back.CmdAtomicRmw`
- `CodeInstAtomicCas` → `Back.CmdAtomicCas`
- `CodeInstAtomicFence` → `Back.CmdAtomicFence`

The lowering preserves `BackAtomicOrdering` in BackCmds and maps RMW ops explicitly:

| Core op | Back op | Wire op_kind |
|---------|---------|--------------|
| `AtomicRmwAdd` | `BackAtomicRmwAdd` | 1 |
| `AtomicRmwSub` | `BackAtomicRmwSub` | 2 |
| `AtomicRmwAnd` | `BackAtomicRmwAnd` | 3 |
| `AtomicRmwOr` | `BackAtomicRmwOr` | 4 |
| `AtomicRmwXor` | `BackAtomicRmwXor` | 5 |
| `AtomicRmwXchg` | `BackAtomicRmwXchg` | 6 |

Validation:

```sh
luajit tests/test_atomics.lua
```

passes and verifies both BackCmd production and JIT execution.

---

## Closed For Current Schema: Atomic Ordering Wire Fidelity

ASDL and Code→Back preserve atomic ordering. The binary wire format does not encode an ordering slot, but this is currently lossless because the only ordering variant is `SeqCst`.

- `MoonCore.AtomicOrdering = AtomicSeqCst`
- `BackAtomicOrdering = BackAtomicSeqCst`
- `CmdAtomicLoad/Store/Rmw/Cas/Fence` include ordering fields, all currently `SeqCst`
- Wire tags 112–116 imply `SeqCst`

If weaker orderings are added to the schemas later, the wire format and decoder must be extended at the same time rather than silently defaulting.

---

## Closed: Intrinsic and Rotate Code→Back Lowering

`lua/moonlift/code_to_back.lua` now lowers `CodeInstIntrinsic`:

- `IntrinsicPopcount/Clz/Ctz/Bswap/Sqrt/Abs/Floor/Ceil/TruncFloat/Round` → `Back.CmdIntrinsic`
- `IntrinsicRotl/IntrinsicRotr` → `Back.CmdRotate`
- `IntrinsicFma` → `Back.CmdFma`
- `IntrinsicTrap` → `Back.CmdTrap`

`tests/test_code_to_back.lua` includes executable JIT coverage for popcount + rotl, verifying both `CmdIntrinsic` and `CmdRotate` production.

---

## Closed: Vector Reductions, Integer TailScalar Subset

`lower_to_back.lua` now lowers supported vector reductions without adding Back ASDL or wire tags.

Implemented subset:

- contiguous integer/vector schedules with `TailScalar`
- `add`, `mul`, `and`, `or`, `xor`, `min`, and `max`
- vector accumulator block params initialized from reduction identities
- vector contribution combines via `CmdVecBinary` or `CmdVecCompare` + `CmdVecSelect`
- horizontal fold via `CmdVecExtractLane` and scalar combines
- scalar tail/exit handoff with accumulator overrides

Validation:

```sh
luajit tests/test_lower_to_back_vector_reductions.lua
luajit tests/test_lower_to_back_kernel_vector.lua
luajit tests/test_parse_kernels.lua
```

Remaining limitations:

- closed forms remain a separate lowering strategy, not a vector-reduction path
- `TailNone` still needs a divisibility proof before it should bypass scalar tail handling
- float reductions remain blocked by missing Back vector float arithmetic/compare ops

---

## Closed: View Return ABI

View returns now use an sret descriptor ABI.

A returned view is written to the hidden result pointer as three 8-byte components:

- offset 0: `data`
- offset 8: `len`
- offset 16: `stride`

`CodeAggregateAbi.lowered_sig` treats single view results as sret. `code_to_back.lua` stores returned view components to the hidden result pointer and loads view components after sret calls. `tests/test_code_to_back.lua` includes executable JIT coverage for returning a view descriptor.

---

## Closed: Scalar Kernel Fragment Placement

Scalar kernel lowering now places synthetic `KernelBinding` values back into Code blocks even when the binding is not a direct instruction result.

Placement sources:

- existing instruction-result value maps
- loop/header block params used by affine/index expressions
- memory access facts for `KernelExprLoad`
- recursive value-expression operands for algebra/select/compare expressions

Validation:

```sh
luajit tests/test_code_mem_facts.lua
luajit tests/test_lower_to_back_kernel_scalar.lua
```

---

## Closed: Closure Descriptor Lowering

Closure values now use the existing aggregate/by-reference path rather than a new BackCmd or wire tag.

Implemented behavior:

- descriptor storage is `{ fn, ctx }`, two pointer-sized words
- converted closure literals materialize helper function pointers and inline capture environments after the descriptor
- `CodeCallClosure` lowers by loading `fn` and `ctx`, then emitting `BackCallIndirect`
- synthetic Back signatures insert the context pointer after any hidden sret pointer
- `CodeInstClosure` lowers explicit `{ fn, ctx }` descriptors
- returning captured closure literals is rejected with a clear ownership-model error

Validation:

```sh
luajit tests/test_closure_escape.lua
luajit tests/test_code_to_back.lua
```

Remaining language-design boundary:

- heap/arena ownership for captured environments that escape their defining frame is not a backend wire/codegen gap; captured closure returns fail loudly until that model exists

---

## Closed: Handle Types

Handle types are backend-transparent values. They lower through their declared scalar representation and require no BackCmd or wire tag.

Implemented behavior:

- `THandle` maps to `CodeTyHandle(repr, source_ty)`
- `CodeAggregateAbi.scalar(CodeTyHandle(...))` returns the scalar representation
- layout and ABI classification use the handle representation size/alignment
- invalid values, `repr(handle)`, and `Handle.from_repr(raw)` are checked before backend lowering
- unsafe casts between handles and raw representation scalars are rejected by typechecking

Validation:

```sh
luajit tests/test_handle_types.lua
```

---

## Closed Tooling Gaps

### Debug interpreter indirect calls

`debug_interpreter.lua` now gives `CmdFuncAddr` a function-address value and resolves `BackCallIndirect` targets through the same internal call machinery as direct calls. It also binds callee entry params from call arguments and writes returned values back into the caller frame.

Validation:

```sh
luajit tests/test_debug_interpreter.lua
```

### Hosted JIT disassembly

`hosted_jit.lua` now mirrors the cdylib artifact helpers:

- `Artifact:getbytes`
- `Artifact:hexbytes`
- `Artifact:writebytes`
- `Artifact:disasm`
- `Jit:peek`

Validation:

```sh
cargo build --release
target/release/moonlift /tmp/moonlift_hosted_peek_smoke.mlua
```

---

## Removed: Tape Compiler Path

The dead text-tape path has been deleted. The backend now uses only the binary wire format.

Removed/cleaned:

- `lua/moonlift/tape_encode.lua`
- `lua/moonlift/tape_exec.lua`
- `Jit::compile_tape`
- `_host_compile` tape hook
- tape FFI declaration/comments

---

## Closed: Wire Format Documentation Drift

`BACK_WIRE_FORMAT.md` now documents the implemented `Splat` layout:

- `Splat` has 4 slots: `[dst, scalar_type, lanes, src]`

`src/wire_tags.rs` / `TAG_SLOTS` remains the authoritative implementation contract.
