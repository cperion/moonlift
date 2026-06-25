# Backend Completeness Audit
Map the gap between LANGUAGE_REFERENCE.md features and the Cranelift backend implementation. Identify every unsupported BackCmd variant, stub, and missing codegen path.
**Workflow ID**: wf-backend-gap
**Started**: 2026-06-17 19:46:03
---

## Completion Update — 2026-06-19

Closed the remaining backend-facing closure/handle items:

- implemented closure descriptor lowering in `code_to_back.lua`
- added synthetic closure-call Back signatures with the hidden context pointer
- lowered `CodeCallClosure` through loaded `{ fn, ctx }` descriptors and `BackCallIndirect`
- materialized converted closure literals as stack descriptors with inline capture environments for non-escaping use
- added a loud rejection for returning captured closure literals until an environment ownership model exists
- verified handle types are already representation-lowered and require no Back object or wire tag
- updated `BACKEND_GAPS.md` to remove stale open closure/handle entries

Validation run:

```sh
luajit tests/test_closure_escape.lua
luajit tests/test_code_to_back.lua
luajit tests/test_closure_convert.lua
luajit tests/test_handle_types.lua
```

Closed scalar kernel fragment placement discovered during the final regression pass:

- synthetic `KernelBinding` values now infer their Code block from direct value maps, loop block params, memory access facts, or recursive value-expression operands
- `tests/test_code_mem_facts.lua` and `tests/test_lower_to_back_kernel_scalar.lua` now pass alongside vector/closed-form lowering tests

## Completion Update — 2026-06-19

Executed the remaining vector-reduction plan:

- implemented Back lowering for supported integer `TailScalar` vector reductions
- enabled classifier/scheduler support for reduction candidates while keeping closed forms separate
- added executable JIT coverage for sum/product/xor/and/or/min/max vector reductions with scalar tails
- updated `BACKEND_GAPS.md` and the `vector-reductions` sidecar plan

Validation run:

```sh
luajit tests/test_lower_to_back_vector_reductions.lua
luajit tests/test_lower_to_back_kernel_vector.lua
luajit tests/test_code_schedule_plan.lua
luajit tests/test_code_value_facts.lua
luajit tests/test_parse_kernels.lua
```

## Scout Output — 2026-06-17 19:47:53

Now I have all the materials. Let me compile the comprehensive gap map.

---

## Files Retrieved

| # | File | Purpose |
|---|------|---------|
| 1 | `LANGUAGE_REFERENCE.md` (all 3057 lines) | Complete language spec — all types, ops, control, fragments, intrinsics, atomics, memory |
| 2 | `src/wire_tags.rs` (full) | All 111 Rust WireTag enum variants serving as the bridge contract |
| 3 | `src/decode.rs` (full) | Rust body decoder — `decode_body()` is the complete per-tag codegen dispatch (~600 lines) |
| 4 | `src/lib.rs` (full) | Top-level: JIT, object emission, `compile_tape` (stubbed), `compile_binary`, error types |
| 5 | `src/ffi.rs` (full) | C FFI surface — `lalin_jit_compile_binary`, `compile_tape` absent from FFI |
| 6 | `src/main.rs` (full) | Host binary — uses `_host_compile_binary` via hosted_jit.lua, never tape |
| 7 | `lua/lalin/schema/back.asdl` (full) | ASDL schema — all `BackCmd` variants, `BackScalar`, `BackLiteral`, ops, vec types |
| 8 | `lua/lalin/back_command_binary.lua` (full) | Binary wire encoder — Lua→Rust bridge encoding dispatch |
| 9 | `lua/lalin/back_jit.lua` (full) | FFI-based JIT bridge (loads `liblalin.so`) |
| 10 | `lua/lalin/hosted_jit.lua` (full) | In-process hosted JIT (used by `lalin` binary) |
| 11 | `lua/lalin/lower_to_back.lua` | LowerModule→BackProgram: vector kernel lowering with stubbed reductions |
| 12 | `lua/lalin/code_to_back.lua` | LalinCode→BackProgram: view return ABI stubbed |
| 13 | `lua/lalin/tree_control_to_back.lua` | Control regions→BackCmd (blocks, jumps, brif, switch, phi) |
| 14 | `lua/lalin/tape_encode.lua` | Legacy text tape encoder (kept for CI cross-check, more limited than binary) |
| 15 | `lua/lalin/back_validate.lua` | Backend validation (has handlers for ALL ASDL variants including CmdRotate, CmdVecMask, CmdAtomic*) |

---

## Key Code: The Wire Format Contract

### WireTag enum (`src/wire_tags.rs`) — 111 tags, all 1:1 with Cranelift IR ops

All integer/float arithmetic, bitwise, shift/rotate, compare, cast/convert, intrinsics, address ops, memory (load/store/atomic/cmpxchg/fence/memcpy/memset/memcmp), pointer, vector (splat/lane/arith/cmp/select/mask/load/store), select, control flow, call (direct/extern/indirect), alias, boolnot. **Every tag has a handler in `decode_body()`.**

### BackCmd ASDL schema (`lua/lalin/schema/back.asdl`) — 57 command variants

Declarations: `CmdCreateSig`, `CmdDeclareData`, `CmdDataInitZero`, `CmdDataInit`, `CmdDataAddr`, `CmdFuncAddr`, `CmdExternAddr`, `CmdDeclareFunc`, `CmdDeclareExtern`, `CmdBeginFunc`

Structural: `CmdCreateBlock`, `CmdSwitchToBlock`, `CmdSealBlock`, `CmdBindEntryParams`, `CmdAppendBlockParam`, `CmdCreateStackSlot`, `CmdAlias`, `CmdStackAddr`

Ops: `CmdConst`, `CmdUnary`, `CmdIntrinsic`, `CmdCompare`, `CmdCast`, `CmdPtrOffset`, `CmdIntBinary`, `CmdBitBinary`, `CmdBitNot`, `CmdShift`, `CmdRotate`, `CmdFloatBinary`, `CmdFma`, `CmdSelect`

Memory: `CmdLoadInfo`, `CmdStoreInfo`, **`CmdAtomicLoad`**, **`CmdAtomicStore`**, **`CmdAtomicRmw`**, **`CmdAtomicCas`**, **`CmdAtomicFence`**, `CmdMemcpy`, `CmdMemset`, `CmdMemcmp`

Vector: `CmdVecSplat`, `CmdVecBinary`, `CmdVecCompare`, `CmdVecSelect`, **`CmdVecMask`**, `CmdVecInsertLane`, `CmdVecExtractLane`

Control: `CmdJump`, `CmdBrIf`, `CmdSwitchInt`, `CmdReturnVoid`, `CmdReturnValue`, `CmdTrap`

Call: `CmdCall`

Termination: `CmdFinishFunc`, `CmdFinalizeModule`

---

## Gap Map: What REACHES the Rust Backend vs What Doesn't

### Gap A: ASDL BackCmd variants with NO binary encoder path (Lua can't produce them)

These variants exist in the ASDL schema and the Rust wire tags fully support them, but the Lua→binary encoder (`back_command_binary.lua`) has **no encoding dispatch**:

| BackCmd variant | Wire tag(s) | Rust codegen status | Binary encoder status |
|---|---|---|---|
| **`CmdAtomicLoad`** | `AtomicLoad` (112) | ✅ Full codegen in `decode_body` | ❌ Not encoded |
| **`CmdAtomicStore`** | `AtomicStore` (113) | ✅ Full codegen | ❌ Not encoded |
| **`CmdAtomicRmw`** | `AtomicRmw` (114) | ✅ Full codegen | ❌ Not encoded |
| **`CmdAtomicCas`** | `AtomicCas` (115) | ✅ Full codegen | ❌ Not encoded |
| **`CmdAtomicFence`** | `Fence` (116) | ✅ Full codegen | ❌ Not encoded |
| **`CmdRotate`** | `Rotl` (63), `Rotr` (64) | ✅ Full codegen | ❌ Not encoded |
| **`CmdVecMask`** | `VecMaskNot` (150), `VecMaskAnd` (151), `VecMaskOr` (152) | ✅ Full codegen | ❌ Not encoded |

**These 7 BackCmd variants are an immediate gap.** The Rust backend is ready; the Lua encoder needs `elseif k == "CmdAtomicLoad"` etc. branches.

### Gap B: Language features with NO lowering path at all

These LANGUAGE_REFERENCE.md features have **neither backend codegen nor lowering path** in the Lua compiler:

| Feature | Lang Ref § | Status |
|---|---|---|
| **Closure types** (`closure(i32): i32`) | §5.8 | No `code_to_back`/`lower_to_back` support. The ASDL has no `BackClosure` type. No wire tag. |
| **Handle types** (`handle Voice : u32 invalid 0 end`) | §21.2 | Memory convention only. No backend lowering, no BackCmd, no wire tag. |
| **Contracts/requires clauses** | §13 | Consumed by facts pipeline (optimization hints). No direct BackCmd emitted. |
| **Vector reductions** | §18.4 | `lower_to_back:631` explicitly errors: `"vector reductions are not implemented"` |
| **View return ABI** | §17 | `code_to_back:646` explicitly errors: `"view return ABI is not implemented below Code"` |
| **Indirect calls (interpreter)** | — | `debug_interpreter.lua:1111`: "Indirect call: not supported in interpreter" |
| **Route target in region compose** | — | `region_compose.lua:163`: "route target kind not yet lowerable in entry" |

### Gap C: Rust backend stub — tape compiler

`src/lib.rs:98-100`:
```rust
pub fn compile_tape(&self, _tape: &str) -> Result<Artifact, LalinError> {
    Err(LalinError("tape compiler not yet migrated; use binary wire format".into()))
}
```
The legacy text tape path is explicitly not migrated. The FFI surface (`src/ffi.rs`) doesn't even export a tape compilation function. The `lalin` binary uses the binary path exclusively.

### Gap D: Hosted JIT disassembly stub

`hosted_jit.lua`:
```lua
function Jit:peek(_program, _func, _opts)
    error("hosted_jit: disassembly/peek is not wired for hosted artifacts yet", 2)
end
```

### Gap E: Backend fully supports (complete codegen path exists)

Every wire tag 1–191 (111 implemented tags) has a real Cranelift `InstBuilder` call in `decode_body()`. The complete list:

**Structural** (5): CreateBlock, SwitchToBlock, AppendBlockParam, CreateStackSlot, AppendBlockParamVec

**Constants** (7): ConstI32, ConstI64, ConstF32, ConstF64, ConstBool, ConstNull, ConstInt

**Integer arithmetic** (8): Iadd, Isub, Imul, Sdiv, Udiv, Srem, Urem, Ineg

**Float arithmetic** (12): Fadd, Fsub, Fmul, Fdiv, Fneg, Fabs, Fma, Sqrt, Floor, Ceil, Trunc, Nearest

**Bitwise** (4): Band, Bor, Bxor, Bnot

**Shift/Rotate** (5): Ishl, Ushr, Sshr, Rotl, Rotr

**Compare** (2): Icmp (10 conditions), Fcmp (6 conditions)

**Cast/Convert** (10): Bitcast, Ireduce, Sextend, Uextend, Fpromote, Fdemote, FcvtFromSint, FcvtFromUint, FcvtToSint, FcvtToUint

**Intrinsics** (5): Popcnt, Clz, Ctz, Bswap, Iabs

**Address** (4): StackAddr, GlobalValue, FuncAddr, ExternAddr

**Memory** (10): Load, Store, AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, Fence, Memcpy, Memset, Memcmp

**Pointer** (2): PtrAdd, PtrOffset

**Vector** (25): Splat, InsertLane, ExtractLane, VecIadd, VecIsub, VecImul, VecBand, VecBor, VecBxor, VecIcmpEq/Ne, VecSIcmpLt/Le/Gt/Ge, VecUIcmpLt/Le/Gt/Ge, VecSelect, VecMaskNot/And/Or, VecLoad, VecStore

**Select** (1): Select

**Control** (6): Jump, Brif, SwitchInt, ReturnVoid, ReturnValue, Trap

**Call** (3): CallDirect, CallExtern, CallIndirect

**Singleton** (2): Alias, BoolNot

### Gap F: Encoding asymmetry — binary encoder has variants not in ASDL

The binary encoder handles `CmdDeclareFuncExport`, `CmdDeclareFuncExtern`, `CmdDeclareFuncLocal`, `CmdVecLoadInfo`, `CmdVecStoreInfo` — none of which exist in the ASDL schema. These appear to be the binary encoder parsing `CmdDeclareFunc.visibility` and `CmdLoadInfo`/`CmdStoreInfo` with vec types, splitting them at encode time. Not a bug, just a design detail.

---

## Relationships

### Data flow: Lua source → native code
```
.mlua source
  → parse (scan_document)
  → tree_typecheck
  → tree_to_code (LalinTree → LalinCode)
  → code_to_back / lower_to_back (LalinCode → BackCmd[])
  → back_command_binary.encode (BackCmd[] → binary wire bytes)
  → lalin_jit_compile_binary (FFI → decode.rs → Cranelift JITModule)
  → native machine code
```

### Wire format contract
```
back.asdl (57 Cmd variants)
  → back_command_binary.lua (encodes 50 of 57)
  → binary wire bytes (header + decls + body table + tag streams)
  → src/decode.rs (decode_body: match on all 111 WireTags)
  → Cranelift FunctionBuilder IR instructions
```

### Critical gap flow
```
CmdAtomicLoad (ASDL defined)
  → ❌ back_command_binary.lua has NO `elseif k == "CmdAtomicLoad"` branch
  → ❌ cannot produce AtomicLoad (112) wire tag bytes
  → ✅ decode.rs already handles AtomicLoad tag with full codegen
  → Gap: Lua encoder needs 5 new branches (AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence)
         + 1 branch for CmdRotate (Rotl/Rotr)
         + 1 branch for CmdVecMask (VecMaskNot/And/Or)
```

---

## Observations

1. **The Rust backend is surprisingly complete.** Every one of 111 wire tags dispatches to a real Cranelift `InstBuilder` call. The `_` catchall in `decode_body` returns `"unhandled wire tag {tag}"` — there are no silent no-ops.

2. **The gap is almost entirely in the Lua encoder, not in Rust.** 7 ASDL variants lack binary encoding. The Rust side is ready for all of them.

3. **Atomic operations are a pure encoder gap.** The wire tags (112–116) have full Cranelift codegen. The ASDL defines `CmdAtomicLoad`, `CmdAtomicStore`, `CmdAtomicRmw`, `CmdAtomicCas`, `CmdAtomicFence`. But the binary encoder has no branches for these. The same is true for `CmdRotate` (Rotl/Rotr) and `CmdVecMask`.

4. **Closure types, handle types, and contracts are not backend gaps** — they're design features that live in the Lua metaprogramming layer or facts pipeline, not in `BackCmd` at all. However, the language reference describes them as part of the language surface, which is worth noting.

5. **Vector reductions and view returns are explicitly error-stubbed** in the Lua lowering pipeline — these are known unimplemented features with loud failures.

6. **The tape path is dead.** `src/lib.rs` returns an error. The FFI doesn't export it. The `lalin` binary never calls it. Only the legacy `back_jit.lua` (cdylib path) mentions `compile_tape` in its FFI declarations.

7. **The legacy tape encoder (`tape_encode.lua`) handles even fewer variants** than the binary encoder — no atomics, no vec operations, no Memcmp, no data/extern/func addr commands, no finalize/finish. It does handle `CmdRotate` though (which the binary encoder doesn't).

8. **Backend validation (`back_validate.lua`) already validates ALL ASDL variants** including CmdRotate, CmdVecMask, CmdAtomicLoad, etc. — so validation would catch issues if the encoder were extended.

9. **No `unimplemented!()` panics in Rust code.** The only stub is the `compile_tape` path which returns a clean error. No `todo!()`, no panics. The decoder's fallback arm returns an error for unrecognized tags.

10. **The `s[2]` vs `s[3]` slot count discrepancy in Splat.** The wire format doc says Splat has 3 slots `[dst, scalar_type, src]` but `wire_tags.rs` says 4 slots `[dst, scalar_type, lanes, src]`. The binary encoder writes 4 slots (dst, scalar_type, lanes, src). This inconsistency between doc and code should be reconciled.

## Knowledge-builder Output — 2026-06-17 19:55:56

Now I have the full picture. Here are my second-order observations.

---

## What Matters Most for This Problem

Given the "backend completeness audit" task:
1. **Correctness of the gap classification** — the gap isn't a single category; it's three fundamentally different kinds of missingness
2. **Coupling between Lua encoder and Rust decoder** — they are independent implementations of the same wire contract, maintained separately
3. **What tests actually exercise** — test coverage is misleading because BackCmd presence ≠ end-to-end execution
4. **Wire format fidelity** — what the wire format drops from the ASDL schema (atomic ordering, scale type info)

---

## Non-Obvious Observations

### 1. The encoder gap is NOT symmetric across the two JIT paths — but it is
Both `back_jit.lua` (CDylib) and `hosted_jit.lua` (standalone binary) call `back_command_binary.encode()`. **There is no alternative path.** Every BackProgram, regardless of how it enters Rust, transits the same encoder. This means the atomic/Rotate/VecMask gap blocks BOTH entry points equally. The distinction between "cdylib" and "hosted" is an FFI detail, not a separate compilation pipeline.

### 2. `test_atomics.lua` is a *coverage mirage*
The test asserts that `CmdAtomicLoad` etc. are produced by lowering (lines 33-38), then calls `jit():compile(program)` and asserts specific numeric results (line 44: `atomic_demo(cell) == 46`, line 45: `cell[0] == 21`). But the encoder silently drops atomic commands. The compiled function would have no atomic instructions — `old`, `seen`, `after` would reference **undefined Cranelift SSA values**, causing a compilation error in `decode.rs` (`ctx.val()` returns `"unknown value {id}"`). The test **cannot pass** the end-to-end execution check. This pattern — verifying BackCmd production but not execution — is a classic "test your abstractions, not your pipeline" trap. The test structure is correct (check BackCmds first, then execute) but the encoder gap makes the second half dead code that never runs successfully.

### 3. Atomic ordering is a **semantic gap at the wire boundary**, not just an encoding gap
The ASDL schema defines `BackAtomicOrdering` on every atomic command:
```
CmdAtomicLoad(dst, ty, addr, memory, ordering)
CmdAtomicStore(ty, addr, value, memory, ordering)
...
CmdAtomicFence(ordering)
```

But the wire format has **zero slots for ordering**: `AtomicLoad` has 4 slots `[dst, scalar_type, memflags, addr]`, `Fence` has 0 slots. The Rust decoder hardcodes all atomics via Cranelift's `atomic_load`/`atomic_store` instructions (which are implicitly seq_cst on x86 but NOT portable to other architectures). Cranelift does support relaxed/acquire/release memory orderings via `MemFlags` bits, but the current wire format doesn't expose them.

This means: even after adding encoder branches, the ordering field in the ASDL would be **silently lost** at the wire boundary. Fixing this properly requires extending the wire format to carry ordering bits (or accepting that only seq_cst is supported).

### 4. CmdVecMask has a non-uniform arity problem at the encoder level
The ASDL groups `VecMaskNot`, `VecMaskAnd`, `VecMaskOr` into a single `CmdVecMask(dst, op, ty, args*)` with variadic args. But the wire format has three separate tags with different slot counts:
- `VecMaskNot`: 2 slots (unary)
- `VecMaskAnd`: 3 slots (binary)
- `VecMaskOr`: 3 slots (binary)

The encoder must dispatch on `cmd.op.kind` to select the right tag AND emit `args[1]` only vs `args[1], args[2]`. This is more complex than adding a 1:1 branch — it requires a sub-dispatch inside the `CmdVecMask` branch. The pattern already exists in the encoder (e.g., `CmdUnary` dispatches on op to select `Ineg`/`Fneg`/`Bnot`/`BoolNot`), but CmdVecMask is the only case where the op determines arity.

### 5. CmdAtomicRmw needs an `op_kind` numeric mapping that must stay synchronized
The wire format uses slot `s[2]` as `op_kind` in `AtomicRmw`. The Rust decoder maps:
```
1→Add, 2→Sub, 3→And, 4→Or, 5→Xor, 6→Xchg
```
The ASDL defines `BackAtomicRmwOp` with the same 6 variants. The Lua encoder must produce the SAME numeric mapping. There is no shared constant definition between Lua and Rust — the mapping must be maintained independently in both files. This is a hidden coupling point that the existing encoder (for Load/Store) avoids because atomic loads/stores don't need an op_kind.

### 6. The "silent drop" pattern in the encoder is the root cause of the test mirage
The encoder's `if-then-elseif` chain ends without an `else` clause:
```lua
for _, cmd in ipairs(cmds) do
    local k = cmd.kind
    if k == "CmdCreateBlock" then ...
    elseif k == "CmdSwitchToBlock" then ...
    ...
    -- NO else clause
    end
end
```
Unrecognized commands are silently skipped. This means:
- The encoder produces a shorter-but-valid wire buffer
- Rust decodes it without errors (no "unhandled wire tag")
- Cranelift compiles a function that's missing instructions
- Values that should be defined by dropped commands become undefined
- The decoder fails at `ctx.val()` with `"unknown value {id}"` when a later instruction references them

If the encoder had a loud `else error("unrecognized BackCmd: " .. k)` clause, the gap would be immediately visible. Instead, it fails silently until a downstream instruction references an undefined value.

### 7. CmdRotate is the deepest gap because it requires new language surface, not just encoder wiring
Looking at `debug_interpreter.lua:568-576`, rotate is implemented as a **shift** ("Simplified: just shift for now"). The language reference mentions rotate syntax (e.g., `rotl(x, n)`), but:
- There's no lowering path from `.mlua` source to `CmdRotate` BackCmds (grep confirms no `CodeInstRotate` or lowering logic in `code_to_back.lua`)
- The rotate command only appears in hand-constructed BackPrograms (tests that build ASDL directly)
- No language-level test exercises rotate through the full pipeline

The encoder gap for CmdRotate is real but different from atomics: **atomics have a complete lowering path but no encoder; rotate has neither lowering NOR encoder.**

### 8. The `Splat` slot count discrepancy is a documentation bug that masks a deeper contract trust issue
`BACK_WIRE_FORMAT.md` says Splat has 3 slots. `wire_tags.rs` says 4. The encoder writes 4. The decoder reads 4. The documentation is wrong, not the code. But this reveals a pattern: **the wire format doc was written first, then the implementation diverged** (adding a `lanes` slot). This means the doc cannot be trusted as the contract specification. The `TAG_SLOTS` array in `wire_tags.rs` is the actual contract.

### 9. There are actually THREE distinct "gap layers" not two
The scout classified gaps as "encoder gap" vs "lowering gap." But there are really three:

| Layer | What's missing | Examples |
|-------|---------------|---------|
| **Lowering** | Lua compiler can't produce BackCmds | Closures, vector reductions, view returns, rotate |
| **Encoding** | BackCmds exist but can't reach Rust | Atomics, VecMask, (rotate if lowering existed) |
| **Wire format fidelity** | Wire format discards ASDL fields | Atomic ordering (BackAtomicOrdering) |

The third layer is subtle: even if lowering and encoding work, the wire format might not carry all the semantic information present in the ASDL. Atomic ordering is the clearest example — it exists in the schema, but the wire format has no slot for it.

### 10. The gap pattern suggests a specific development trajectory
The evidence suggests:
1. **Wire format was designed first** — all 111 tags, all slot layouts
2. **Rust backend was implemented** — all 111 tags get real Cranelift calls
3. **Lua lowering was implemented incrementally** — only what was needed for immediate features
4. **Encoder was implemented incrementally** — only what lowering produced
5. **At some point, atomics were added to the ASDL and the lowering** (possibly for C backend support first, since `test_atomics.lua` exercises BackCmd production but the binary encoder was never updated)

The ASDL schema, validation, C backend, and lowering all have atomics. The Rust backend has atomics. The ONLY gap is **the binary encoder**. This is the hallmark of a feature that was added to the "compiler model" (ASDL + validation + C output) but the Cranelift binary path was never plumbed through.

### 11. The debug interpreter's handling reveals design intent
The debug interpreter maps:
- `CmdAtomicLoad` → `"_handle_load_info"` — treats atomics as regular loads
- `CmdAtomicStore` → `"_handle_store_info"` — treats atomics as regular stores
- `CmdAtomicRmw`/`CmdAtomicCas`/`CmdAtomicFence` → `"_handle_noop"` — ignores them
- `CmdVecMask` → `"_handle_noop"` — ignores it
- `CmdRotate` → `"_handle_rotate"` — implements as shift, with a comment "Simplified: just shift for now"

This reveals intentional design: the interpreter is a "best effort" debugging tool, not a semantics-preserving executor. The mapping of atomics to regular loads/stores for Load/Store variants but no-ops for Rmw/Cas/Fence is the interpreter saying "we know these exist, we know what they mean, but we're not implementing the full semantics here." The Rust backend is the authoritative executor.

---

## Knowledge Gaps

I don't believe I need to spawn additional scouts — I have sufficient data to produce the observations above. However, one thing worth noting for the proposer:

- **Does Cranelift's `MemFlags` API actually expose memory ordering?** If so, extending the wire format to carry ordering would be straightforward. If not, the Rust backend may be limited to implicit seq_cst atomics, which would make the ASDL's `BackAtomicOrdering` informational-only (not executable). This affects whether fixing the atomic encoder gap is "add 5 branches" or "add 5 branches + redesign wire format slots."

## Scout Output — 2026-06-17 20:02:20

Now I have all the critical data. Here is the comprehensive scout report.

---

## Files Retrieved

| # | File | Range | Purpose |
|---|------|-------|---------|
| 1 | `lua/lalin/back_command_binary.lua` | Full (all ~415 lines) | Binary encoder — complete if-elseif chain, helpers, body layout |
| 2 | `src/wire_tags.rs` | Full | TAG_SLOTS static array — definitive slot counts for all 191 tags |
| 3 | `src/decode.rs` | Full | Complete Cranelift backend decoder — all tag handlers, memflags/rmw helpers |
| 4 | `lua/lalin/schema/back.asdl` | Full | Complete ASDL schema — all Cmd* variants, BackAtomicOrdering, BackAtomicRmwOp |
| 5 | `BACK_WIRE_FORMAT.md` | Full | Wire format specification — tag table, slot layouts, MemFlags encoding |
| 6 | `tests/test_atomics.lua` | Full (47 lines) | Atomic test — asserts BackCmd presence + JIT execution |
| 7 | `tests/test_dasm_multi_compile.lua` | Full (93 lines) | Rotate stress test via dasm backend (has CmdRotate) |
| 8 | `tests/test_back_cast_intrinsic_switch.lua` | Lines 70-95 | Rotate test via dasm backend |
| 9 | `lua/lalin/lower_to_back.lua` | Lines 298-340 | Memory lowering helpers — is_write_access, is_read_access, memory_info_for |
| 10 | `lua/lalin/lower_to_back.lua` | Lines 400-440 | Kernel load/store emission — uses CmdLoadInfo/CmdStoreInfo, NEVER CmdAtomic* |

---

## Key Findings

### 1. Encoder if-elseif chain structure

The encoder's `encode_body()` function (line ~146-335 of `back_command_binary.lua`) has `for _, cmd in ipairs(cmds) do` with a single `if k == "CmdCreateBlock" then ... elseif ... end` chain — **NO else clause**. Unrecognized commands are silently dropped. The chain ends implicitly (the `end` on the `for` loop).

The last recognized branch is `CmdCall` (around line ~330). After that, the `end` at line ~335 closes the `if`/`for`.

### 2. Load/Store encoding pattern (lines ~240-270) — exact template for atomics

```lua
-- CmdLoadInfo (lines ~240-256)
elseif k == "CmdLoadInfo" then
    local is_vec = cmd.ty.kind ~= "BackShapeScalar"
    local elem_st, lanes, mem
    if is_vec then
        elem_st = st(cmd.ty.vec.elem)
        lanes = cmd.ty.vec.lanes
        mem = memflags(cmd.memory)
    else
        elem_st = st(cmd.ty.scalar)
        lanes = 0
        mem = memflags(cmd.memory)
    end
    local addr_id = emit_effective_addr(buf, cmd.addr)
    if is_vec then
        w4(buf, T.VecLoad); w4(buf, b:nid(cmd.dst))
        w4(buf, elem_st); w4(buf, lanes); w4(buf, mem); w4(buf, b:nid(addr_id))
    else
        w4(buf, T.Load); w4(buf, b:nid(cmd.dst))
        w4(buf, elem_st); w4(buf, mem); w4(buf, b:nid(addr_id))
    end
```

Key observations:
- **`emit_effective_addr()`** (defined on line ~138) resolves an address object into a value ID, emitting StackAddr/GlobalValue/PtrAdd as needed inline
- **`memflags(cmd.memory)`** (line ~97-112) encodes memory bits: bit0=notrap, bit1=aligned, bit2=can_move, bit3=readonly
- **Scalar types**: `cmd.ty.scalar` (not `cmd.ty` — for CmdLoadInfo, `cmd.ty` is a BackShape)
- Atomics only need scalar types (atomic operations aren't vectorized), so the shape is always `BackShapeScalar(cmd.ty)` where `cmd.ty` is a BackScalar

### 3. Atomic BackCmd ASDL definitions vs wire contract

**ASDL** (back.asdl lines 260-264):
```
CmdAtomicLoad(dst, ty:BackScalar, addr:BackAddress, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicStore(ty:BackScalar, addr:BackAddress, value, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicRmw(dst, op:BackAtomicRmwOp, ty:BackScalar, addr:BackAddress, value, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicCas(dst, ty:BackScalar, addr:BackAddress, expected, replacement, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicFence(ordering:BackAtomicOrdering)
```

**Wire format** (TAG_SLOTS array in `wire_tags.rs`):
- `AtomicLoad` (112) = 4 slots: `[dst, scalar_type, memflags, addr]`
- `AtomicStore` (113) = 4 slots: `[scalar_type, memflags, addr, value]`
- `AtomicRmw` (114) = 6 slots: `[dst, scalar_type, op_kind, memflags, addr, value]`
- `AtomicCas` (115) = 6 slots: `[dst, scalar_type, memflags, addr, expected, replacement]`
- `Fence` (116) = 0 slots

**CRITICAL GAP**: The `ordering` field in the ASDL has **no wire slot**. Only `BackAtomicOrdering = BackAtomicSeqCst` exists (single variant). The Rust decoder ignores ordering entirely — it uses Cranelift's default `atomic_load`/`atomic_store`/`atomic_rmw`/`atomic_cas`/`fence()` instructions with `MemFlags`.

### 4. AtomicRmw op_kind numeric mapping (must be kept synchronized)

**Rust decoder** (`decode.rs` lines ~95-102):
```rust
fn rmw(kind: u32) -> Result<AtomicRmwOp, LalinError> {
    match kind {
        1 => Ok(AtomicRmwOp::Add), 2 => Ok(AtomicRmwOp::Sub),
        3 => Ok(AtomicRmwOp::And), 4 => Ok(AtomicRmwOp::Or),
        5 => Ok(AtomicRmwOp::Xor), 6 => Ok(AtomicRmwOp::Xchg),
        _ => ...
    }
}
```

**ASDL enum order** (back.asdl lines 97-102):
```
BackAtomicRmwAdd | BackAtomicRmwSub | BackAtomicRmwAnd | BackAtomicRmwOr | BackAtomicRmwXor | BackAtomicRmwXchg
```

The encoder must map these enum variants to 1-6 in the same order.

### 5. Rotate wire tags and handlers

- `Rotl` (63) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, rotl)`
- `Rotr` (64) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, rotr)`

ASDL `CmdRotate(dst, op:BackRotateOp, scalar:BackScalar, lhs, rhs)`:
- `BackRotateOp = BackRotateLeft | BackRotateRight`
- Pattern identical to `CmdShift` (lines ~210-218): `local ok = cmd.op.kind or cmd.op; if ok == "BackRotateLeft" then w4(buf, T.Rotl) elseif ok == "BackRotateRight" then w4(buf, T.Rotr) else w4(buf, T.Rotl) end`

### 6. VecMask wire tags and handlers

- `VecMaskNot` (150) = 2 slots: `[dst, vec]` — `unop!(0, 1, bnot)`
- `VecMaskAnd` (151) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, band)`
- `VecMaskOr` (152) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, bor)`

ASDL `CmdVecMask(dst, op:BackVecMaskOp, ty:BackVec, args:BackValId*)`:
- `BackVecMaskOp = BackVecMaskNot | BackVecMaskAnd | BackVecMaskOr`
- Sub-dispatch needed: `VecMaskNot` uses `args[1]` only; `VecMaskAnd`/`VecMaskOr` use `args[1], args[2]`

### 7. MemFlags helper (lines 97-112)

```lua
local function memflags(m)
    local bits = 0
    if m.trap.kind == "BackNonTrapping" or m.trap.kind == "BackChecked" then
        bits = bit.bor(bits, 1)
    end
    if (m.alignment.kind == "BackAlignKnown" or m.alignment.kind == "BackAlignAtLeast")
       and m.alignment.bytes >= 4 then
        bits = bit.bor(bits, 2)
    end
    if m.motion.kind == "BackCanMove" then
        bits = bit.bor(bits, 4)
    end
    if m.mode.kind == "BackAccessReadonly" then
        bits = bit.bor(bits, 8)
    end
    return bits
end
```

### 8. emit_effective_addr helper (lines ~128-145)

```lua
local function emit_effective_addr(buf, addr)
    local base_id = emit_base_addr(buf, addr.base)
    if addr.byte_offset == nil then return base_id end
    local at = fresh_id()
    w4(buf, T.PtrAdd); w4(buf, b:nid(at)); w4(buf, b:nid(base_id)); w4(buf, b:nid(addr.byte_offset))
    return at
end
```

### 9. CRITICAL DISCOVERY: Atomics are NEVER lowered to CmdAtomic*

`grep -rn "CmdAtomicLoad\|CmdAtomicStore\|CmdAtomicRmw\|CmdAtomicCas\|CmdAtomicFence" lua/ --include="*.lua"` returns **ZERO construction sites** in the Lua compiler source. The only references are:
- `schema/back.asdl` — ASDL definition
- `back_validate.lua` — validation handler (references by class, doesn't construct)
- `debug_interpreter.lua` — handler dispatch

**`lower_to_back.lua`** (lines 400-440) emits `CmdLoadInfo`/`CmdStoreInfo` for ALL memory operations including atomic ones — there is no `CmdAtomicLoad`/`CmdAtomicStore` emission path.

**`code_to_back.lua`** has no `CodeInstAtomicLoad`/`CodeInstAtomicStore`/etc. elseif branches — atomic CodeInsts silently fall through the if-elseif chain.

This means: **the `test_atomics.lua` test CANNOT pass**. When it runs, `program.cmds` will contain `CmdLoadInfo`/`CmdStoreInfo` (emitted by `lower_to_back`), NOT `CmdAtomicLoad`/`CmdAtomicStore`. The assertion on line 39 (`saw_load and saw_store and saw_rmw and saw_cas and saw_fence`) must be false.

The test is indeed a coverage mirage as the knowledge-builder identified.

### 10. Rotate existing lowering: CmdRotate only in hand-constructed programs

CmdRotate is NOT lowered from .mlua source through the pipeline. It only appears in:
- `test_back_cast_intrinsic_switch.lua` line 83 (hand-constructed via ASDL builders)
- `test_dasm_backend_full.lua` line 438 (hand-constructed)
- `test_dasm_multi_compile.lua` line 71 (hand-constructed)

The `code_to_back.lua` has no `CodeInstRotate` handler. The lowering path from `rotate` source syntax to BackCmd does not exist.

### 11. VecMask: also only in hand-constructed dasm tests

CmdVecMask only appears in dasm backend files (`back/dasm/`), never in the binary encoder path. The `lower_to_back.lua` vector kernel emitter uses `CmdVecBinary`/`CmdVecCompare`/`CmdVecSplat`/`CmdVecSelect` but never `CmdVecMask`. The dasm backend explicitly errors: `"isel: vector CmdVecMask not supported"` (rule_x64.lisle line 208).

---

## Exact Encoder Insertion Points

The if-elseif chain in `back_command_binary.lua` has these natural insertion points:

1. **After CmdStoreInfo** (line ~270): Insert `CmdAtomicLoad` branch (before `CmdMemcpy`/`CmdMemset`/`CmdMemcmp`)
2. **After CmdStoreInfo** (same place): Insert `CmdAtomicStore` branch
3. **After CmdAtomicLoad/CmdAtomicStore**: Insert `CmdAtomicRmw` branch
4. **After CmdAtomicRmw**: Insert `CmdAtomicCas` branch
5. **After CmdAtomicCas**: Insert `CmdAtomicFence` branch
6. **After CmdShift** (line ~218): Insert `CmdRotate` branch
7. **After CmdVecSelect** (line ~312): Insert `CmdVecMask` branch

The pattern for each follows the same `w4(buf, T.Tag); w4(buf, b:nid(cmd.field)); ...` style used throughout.

---

## Test Files

| File | What it tests | Status |
|------|---------------|--------|
| `tests/test_atomics.lua` | Full .mlua atomic pipeline → BackCmd check + JIT | **Cannot pass** — no atomic BackCmd construction path |
| `tests/test_back_cast_intrinsic_switch.lua` | Dasm backend with hand-constructed CmdRotate | Uses dasm, not binary wire |
| `tests/test_dasm_multi_compile.lua` | Random compilation stress test with CmdRotate | Uses dasm (`back.dasm`) |
| `tests/test_dasm_backend_full.lua` | Full dasm feature test with CmdRotate | Uses dasm |

## Edit-planner Output — 2026-06-17 20:04:04

Good. Now here is the complete file-by-file, line-level implementation plan:

---

# Edit Plan: Close Backend Encoder Gaps — `wf-backend-gap/encoder`

## Precondition Checks

Before any edits begin, a worker should verify:

1. **Confirm `back_command_binary.lua` is at ~415 lines** and the if-elseif chain structure is as documented below. The last recognized branch is `CmdCall`; there is no `else` clause.
2. **Confirm `decode.rs` op_kind mapping** at lines 81–83: `1=Add, 2=Sub, 3=And, 4=Or, 5=Xor, 6=Xchg`. This must stay synchronized with the encoder.
3. **Confirm `st()` helper handles `BackScalar` directly**: `st(s)` matches `s.kind == "BackShapeScalar"` → `s.scalar.kind`, otherwise directly `S[s.kind]`. For atomic commands where `cmd.ty` is a `BackScalar` (not BackShape), `st(cmd.ty)` resolves via the fallback `S[cmd.ty.kind]`. Verify this by tracing the `st()` function at lines 82–89.
4. **Confirm tape encoder is deleted**: grep for `tape_encode.lua` — it should no longer exist. Only binary format remains.
5. **Confirm `test_atomics.lua` exists** at `tests/test_atomics.lua` (47 lines) — this test documents the state of atomic lowering (produces `CmdLoadInfo` not `CmdAtomicLoad`).

---

## Files to Modify

### `lua/lalin/back_command_binary.lua`

**Goal**: Add 7 missing encoder branches (atomics, rotate, vecmask) plus a loud `else error(...)` clause so future gaps fail immediately instead of silently dropping commands.

This is the **only file modified**. All changes are in the `encode_body()` function's if-elseif chain inside the `for _, cmd in ipairs(cmds) do` loop.

#### Edit Block 1: CmdAtomicLoad — after CmdStoreInfo (insert before `-- Unary`)

**Location**: After the `end` that closes CmdStoreInfo's `if is_vec ... else ... end` block, and before the `-- Unary` comment line. Currently, the CmdStoreInfo branch ends and the next line is `-- Unary` followed by `elseif k == "CmdUnary" then`.

**Add**:

```lua
        -- Atomic memory
        elseif k == "CmdAtomicLoad" then
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicLoad); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty)); w4(buf, memflags(cmd.memory))
            w4(buf, b:nid(addr_id))
```

**Quirks/notes**:
- `cmd.ty` is `BackScalar` (not `BackShape`), so `st(cmd.ty)` dispatches via the `else` branch of `st()`: `S[cmd.ty.kind]`. This works because `BackScalar` kinds like `BackI32`, `BackF64` etc. are in the `S` table.
- `cmd.ordering` (BackAtomicOrdering) is silently dropped — the wire format has no slot for it. Rust hardcodes seq_cst.
- Uses `emit_effective_addr` exactly like CmdLoadInfo — this emits StackAddr/GlobalValue/PtrAdd preamble as needed.

#### Edit Block 2: CmdAtomicStore — immediately after CmdAtomicLoad

**Add**:

```lua
        elseif k == "CmdAtomicStore" then
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicStore); w4(buf, st(cmd.ty))
            w4(buf, memflags(cmd.memory)); w4(buf, b:nid(addr_id))
            w4(buf, b:nid(cmd.value))
```

**Quirks/notes**:
- No `cmd.dst` — store produces no value. The wire tag `AtomicStore` has slots `[scalar_type, memflags, addr, value]`.
- Same `st(cmd.ty)` pattern as CmdAtomicLoad.

#### Edit Block 3: CmdAtomicRmw — immediately after CmdAtomicStore

**Add**:

```lua
        elseif k == "CmdAtomicRmw" then
            local ok = cmd.op.kind or cmd.op
            local opk = 1
            if ok == "BackAtomicRmwAdd" then opk = 1
            elseif ok == "BackAtomicRmwSub" then opk = 2
            elseif ok == "BackAtomicRmwAnd" then opk = 3
            elseif ok == "BackAtomicRmwOr" then opk = 4
            elseif ok == "BackAtomicRmwXor" then opk = 5
            elseif ok == "BackAtomicRmwXchg" then opk = 6 end
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicRmw); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty)); w4(buf, opk); w4(buf, memflags(cmd.memory))
            w4(buf, b:nid(addr_id)); w4(buf, b:nid(cmd.value))
```

**Quirks/notes**:
- **CRITICAL**: The `opk` mapping MUST stay synchronized with `src/decode.rs` lines 81–83. The order is: Add=1, Sub=2, And=3, Or=4, Xor=5, Xchg=6.
- The ASDL enum order in `back.asdl` lines 109–114 is: `BackAtomicRmwAdd | BackAtomicRmwSub | BackAtomicRmwAnd | BackAtomicRmwOr | BackAtomicRmwXor | BackAtomicRmwXchg` — same order as the numeric mapping.
- Wire has 6 slots: `[dst, scalar_type, op_kind, memflags, addr, value]`. The `opk` goes in slot position 2 (third slot).
- Default `opk = 1` (Add) if unrecognized op — matches existing pattern (e.g., CmdShift falls back to `T.Ishl`).

#### Edit Block 4: CmdAtomicCas — immediately after CmdAtomicRmw

**Add**:

```lua
        elseif k == "CmdAtomicCas" then
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicCas); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty)); w4(buf, memflags(cmd.memory))
            w4(buf, b:nid(addr_id))
            w4(buf, b:nid(cmd.expected)); w4(buf, b:nid(cmd.replacement))
```

**Quirks/notes**:
- Wire has 6 slots: `[dst, scalar_type, memflags, addr, expected, replacement]`.
- No op_kind needed — CAS has a fixed operation. Fields `cmd.expected` and `cmd.replacement` map to the last two slots.

#### Edit Block 5: CmdAtomicFence — immediately after CmdAtomicCas

**Add**:

```lua
        elseif k == "CmdAtomicFence" then
            w4(buf, T.Fence)
```

**Quirks/notes**:
- Wire has 0 data slots. Pure tag emission, like `T.ReturnVoid` and `T.Trap`.
- `cmd.ordering` is silently dropped (no wire slot).
- Rust decoder at line 500: `ctx.builder.ins().fence()` — no arguments.

#### Edit Block 6: CmdRotate — after CmdShift (insert before `-- Compare`)

**Location**: After the final `w4(buf, b:nid(cmd.rhs))` of the CmdShift branch, and before the `-- Compare` comment line.

**Add**:

```lua
        -- Rotate
        elseif k == "CmdRotate" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackRotateLeft" then w4(buf, T.Rotl)
            elseif ok == "BackRotateRight" then w4(buf, T.Rotr)
            else w4(buf, T.Rotl) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))
```

**Quirks/notes**:
- Follows the CmdShift pattern EXACTLY: sub-dispatch tag write, then shared slot writes.
- Both Rotl and Rotr have 3 slots (same arity as shift).
- Fields: `cmd.dst`, `cmd.op` (BackRotateOp), `cmd.scalar` (not used in wire — scalar type is implicit), `cmd.lhs`, `cmd.rhs`.
- Note: there is no lowering path from .mlua to CmdRotate yet. This branch prevents silent drop when lowering is eventually added.

#### Edit Block 7: CmdVecMask — after CmdVecSelect (insert before `-- Vector load`)

**Location**: After the last `w4` of CmdVecSelect, before `-- Vector load`.

**Add**:

```lua
        -- Vector mask
        elseif k == "CmdVecMask" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackVecMaskNot" then
                w4(buf, T.VecMaskNot); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.args[1]))
            elseif ok == "BackVecMaskAnd" then
                w4(buf, T.VecMaskAnd); w4(buf, b:nid(cmd.dst))
                w4(buf, b:nid(cmd.args[1])); w4(buf, b:nid(cmd.args[2]))
            elseif ok == "BackVecMaskOr" then
                w4(buf, T.VecMaskOr); w4(buf, b:nid(cmd.dst))
                w4(buf, b:nid(cmd.args[1])); w4(buf, b:nid(cmd.args[2]))
            else
                w4(buf, T.VecMaskNot); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.args[1]))
            end
```

**Quirks/notes**:
- **Non-uniform arity**: VecMaskNot has 2 data slots `[dst, vec]`; VecMaskAnd/Or have 3 `[dst, lhs, rhs]`. Each sub-branch writes its own tag + slot sequence.
- `cmd.args` is a Lua array (variadic in ASDL).
- Fallback: `VecMaskNot` with `args[1]` only. This is the safe default — the not operation is unary and won't reference undefined args.
- The `cmd.ty` (BackVec) field is not emitted — it's not in the wire format slots. The Rust decoder doesn't use it for vec mask ops (they operate on mask registers, type is implicit).

#### Edit Block 8: Else clause — at end of if-elseif chain

**Location**: The if-elseif chain currently ends with the CmdCall branch at `end` (closing the `if`). Before that `end`, add an `else` clause.

**Current end of chain** (approximately lines 330–335):
```lua
        -- Call
        elseif k == "CmdCall" then
            ...
            emit_ids(buf, cmd.args, b)
        end
    end
```

**Replace with**:
```lua
        -- Call
        elseif k == "CmdCall" then
            ...
            emit_ids(buf, cmd.args, b)
        else
            error("unrecognized BackCmd: " .. tostring(k))
        end
    end
```

**Quirks/notes**:
- `tostring(k)` handles the case where `k` is nil (e.g., a malformed command).
- This is a **loud failure** — any future BackCmd variant added to the ASDL but not the encoder will immediately error instead of silently dropping.
- The error propagates through `encode_body()` → `M.encode()` → the JIT pipeline, producing a clear Lua-level error message.

---

### New Files

None. All changes are in `lua/lalin/back_command_binary.lua` only.

---

## Order of Operations

1. **First: Add all atomic branches** (Edit Blocks 1–5, CmdAtomicLoad through CmdAtomicFence). These are adjacent — insert them as a contiguous block after CmdStoreInfo, before `-- Unary`. The order within the block must be: Load, Store, Rmw, Cas, Fence. Do them in one edit to minimize disruption.

2. **Second: Add CmdRotate branch** (Edit Block 6). Insert after CmdShift, before `-- Compare`. Independent of the atomic block — can be tested separately.

3. **Third: Add CmdVecMask branch** (Edit Block 7). Insert after CmdVecSelect, before `-- Vector load`. Independent of prior blocks.

4. **Fourth: Add the else clause** (Edit Block 8). This is the safety net — do it last so that during development, if a partial edit leaves the chain in an inconsistent state, the else clause catches it. But once all branches are in place, add the else clause so the chain is complete.

5. **Fifth: Run existing tests** to confirm no regressions in the binary encoder path.

---

## Testing Strategy

### Incremental verification

After each block of branches (atomics, rotate, vecmask), there is **no way to test through the normal lowering pipeline** because the Lua compiler doesn't produce these BackCmd variants (yet). Verification must use hand-constructed BackPrograms:

```lua
-- Pattern for hand-constructed test (follow test_dasm_multi_compile.lua style)
local T = pvm.context()
A.Define(T)
local B = T.LalinBack

-- Construct a program with the new BackCmd
local program = B.BackProgram({
    B.CmdDeclareFunc(B.BackFuncId("test"), ..., B.VisibilityExport),
    B.CmdBeginFunc(B.BackFuncId("test")),
    B.CmdCreateBlock(B.BackBlockId("entry")),
    ...
    B.CmdAtomicLoad(B.BackValId("v"), B.BackI32, ...),  -- new cmd
    ...
    B.CmdReturnValue(B.BackValId("v")),
    B.CmdFinishFunc(B.BackFuncId("test")),
    B.CmdFinalizeModule()
})

-- Verify: encode → JIT compile → call
local jit = require("lalin.back_jit").Define(T).jit()
local artifact = jit:compile(program)
-- Should not error
artifact:free()
```

### Regression tests

After all edits, run:
```sh
luajit tests/test_back_add_i32.lua        # basic binary encoder path
luajit tests/test_back_object_emit.lua     # object emission path
luajit tests/test_mlua_host_pipeline.lua   # hosted pipeline
luajit tests/test_dasm_multi_compile.lua   # dasm path (unchanged, baseline)
luajit tests/test_back_cast_intrinsic_switch.lua  # dasm path with CmdRotate
```

These should all pass without changes — we're only adding branches, not modifying existing ones.

### test_atomics.lua status

`tests/test_atomics.lua` currently:
1. Checks for `CmdAtomicLoad` etc. in lowered `program.cmds` (lines 33-38)
2. Attempts JIT execution (lines 40-44)

The lowering pipeline emits `CmdLoadInfo`/`CmdStoreInfo` instead of `CmdAtomicLoad`/`CmdAtomicStore`. So:
- The BackCmd assertions at line 38 will **fail** (saw_load etc. are all false)
- Even if they passed, the encoder would now correctly encode atomic commands

**Do not modify the test's lowering expectation** — the encoder plan only adds encoding branches. The lowering gap is separate work. If the test fails on BackCmd checks, add a comment noting the encoder now supports atomics but lowering doesn't emit them yet.

---

## Structured Edit Plan Sidecar

Created sidecar `encoder` in `wf-backend-gap` with 10 tasks:

| Id | Task | File | Dependencies |
|----|------|------|-------------|
| T001 | Add CmdAtomicLoad encoder branch | `back_command_binary.lua` | — |
| T002 | Add CmdAtomicStore encoder branch | `back_command_binary.lua` | T001 |
| T003 | Add CmdAtomicRmw encoder branch with op_kind mapping | `back_command_binary.lua` | T002 |
| T004 | Add CmdAtomicCas encoder branch | `back_command_binary.lua` | T003 |
| T005 | Add CmdAtomicFence encoder branch (zero-data) | `back_command_binary.lua` | T004 |
| T006 | Add CmdRotate encoder branch | `back_command_binary.lua` | — |
| T007 | Add CmdVecMask encoder branch with non-uniform arity | `back_command_binary.lua` | — |
| T008 | Add loud else clause for unrecognized BackCmds | `back_command_binary.lua` | T001–T007 |
| T009 | Verify with hand-constructed BackProgram round-trip test | — | T008 |
| T010 | Update test_atomics.lua to document current state | `tests/test_atomics.lua` | T009 |

T001–T005 are ordered (atomic branch block). T006, T007 are independent. T008 depends on all branches being in place. T009–T010 are verification tasks.

---

## Pattern Memo

Reference for the worker during implementation:

- **Sub-dispatch pattern**: `local ok = cmd.op.kind or cmd.op` then `if ok == "BackVariantName" then ... elseif ... else fallback end`. Used by CmdShift, CmdVecBinary, CmdIntBinary, etc. Follow this exactly.
- **memflags encoding**: Call the existing `memflags(cmd.memory)` helper — do not reimplement. It returns bit0=notrap, bit1=aligned, bit2=can_move, bit3=readonly.
- **Address resolution**: Call `emit_effective_addr(buf, cmd.addr)` — do not inline StackAddr/GlobalValue/etc. Let the helper handle it.
- **Scalar type on atomics**: `cmd.ty` is a `BackScalar` (not BackShape). Use `st(cmd.ty)` directly. The `st()` helper's fallback branch `S[s.kind]` handles BackScalar kinds like `BackI32`, `BackF64`, etc.
- **Wire slot order**: Must match the TAG_SLOTS entries in `src/wire_tags.rs` and the Rust decoder handlers in `src/decode.rs`. Double-check slot order against the wire format spec in `BACK_WIRE_FORMAT.md` §5.
- **Silently dropped fields**: `cmd.ordering` (BackAtomicOrdering, always BackAtomicSeqCst) and `cmd.scalar`/`cmd.ty` (for Rotate/VecMask where type is not in wire) are intentionally omitted. Add a brief comment noting the omission.
- **Error style**: Use `error("unrecognized BackCmd: " .. tostring(k))` — no `assert`, no custom error object. Match the existing error style in the file.

## Scout Output — 2026-06-17 20:20:36

Here's the complete picture:

---

## Indirect Call Stub — `debug_interpreter.lua` lines 1109–1116

```lua
    elseif tc == Back.BackCallIndirect then
        -- Indirect call: not supported in interpreter
        -- Set result to 0 and continue
        local rc = pvm.classof(cmd.result)
        if rc == Back.BackCallValue then
            self.registers[cmd.result.dst.text] = 0
        end
    end
```

It's a **silent no-op with zero-result fallback**: if the call has a return value, the destination register is set to `0`. Otherwise, nothing happens. No attempt to resolve the callee from the function table. No call-stack push. No control flow transfer.

---

## Direct CmdCall Handling — for comparison (lines 1066–1109)

The interpreter handles **three** `BackCallTarget` subclasses:

| CallTarget variant | Lines | What it does |
|---|---|---|
| `BackCallExtern` | 1069–1085 | Looks up `self.extrn[func_name]`, calls via `pcall(fn, unpack(args))`, writes result to register |
| `BackCallDirect` | 1086–1108 | Looks up `self.func_map[func_id]`, pushes a call-stack frame (saves cursor, registers, current_block, return_dst), jumps cursor to `func_entry.start_idx - 1` |
| `BackCallIndirect` | 1109–1116 | **Stub** — zeroes return register, does nothing else |

The direct call path is fully functional: it saves state, transfers control, and the interpreter's `step()` loop will resume from the callee's first instruction. The indirect path just drops through.

---

## Where Indirect Calls Exist in the Real Pipeline

### Rust Cranelift backend — **fully implemented** (`src/decode.rs:619-626`)

```rust
t if t == WireTag::CallIndirect as u32 => {
    let rt = s[0]; let callee = ctx.val(s[3])?; let sig_id = s[4]; let na = read_u32(buf, &mut pos)? as usize;
    let ids = read_slots(buf, &mut pos, na)?;
    let args: Vec<Value> = ids.iter().map(|&id| ctx.val(id)).collect::<Result<_,_>>()?;
    let sig = refs.sigs.get(&sig_id).cloned().unwrap_or_else(|| Signature::new(ctx.builder.func.signature.call_conv));
    let sig_ref = ctx.builder.import_signature(sig);
    let inst = ctx.builder.ins().call_indirect(sig_ref, callee, &args);
    if rt == 1 { if let Some(&r) = ctx.builder.inst_results(inst).first() { ctx.bind(s[1], r)?; } }
}
```

This is a real Cranelift `call_indirect` instruction — the callee is a runtime value (SSA value), resolved by hardware. **The JIT path handles indirect calls correctly.**

### Binary encoder — **handles CmdCall with sub-dispatch** (`back_command_binary.lua:569-583`)

```lua
tag = T.CallIndirect   -- when target is BackCallIndirect
```

### Pipeline flow — lowering produces `BackCallIndirect`

- `tree_to_code.lua:627`: `CodeCallIndirect(callee, sig)` — code-level call target
- `code_to_back.lua` lowers this to `BackCallIndirect(callee)` via `CmdCall(result, BackCallIndirect(callee), sig, args)`
- `test_back_indirect_stmt.lua:81`: hand-constructed test exercising the full binary encoder→Rust JIT path
- `test_code_to_back.lua:74,107,132,145`: end-to-end tests with `indirect_call_i32_code` and `public_indirect_call_i32_code`

### Dasm backend — has an ISEL rule (`back/dasm/isel_x64.lua:890`)

```
elseif tk == "BackCallIndirect" then
```

### Other references

| File | Role |
|---|---|
| `schema/back.asdl:229` | ASDL definition: `BackCallIndirect(BackValId callee)` |
| `schema/code.asdl:108` | Code-level: `CodeCallIndirect(CodeValueId callee, CodeSigId sig)` |
| `code_validate.lua:283` | Validates indirect call targets |
| `code_effect_facts.lua:113` | Facts pipeline tracks indirect callees |
| `c_emit.lua:303`, `code_to_c.lua:252` | C backend emits indirect calls |
| `tests/test_c_emit.lua:87`, `test_c_validate.lua:67` | C backend tests |
| `dasn/phases/lower_facts.lua:58,281` | Dasm fact-lowering uses `BackCallIndirect` |

---

## Summary

The indirect call gap is **interpreter-only**. The full JIT pipeline (binary encoder → Rust Cranelift) has complete support. The debug interpreter explicitly declines to implement indirect calls, falling back to a zero-result stub. This is consistent with the interpreter's design philosophy described in the shared context — it's a "best effort" debugging tool, not a semantics-preserving executor, and atomics/vecmask/indirect calls are all mapped to no-ops or simplified forms.

## Scout Output — 2026-06-17 20:20:37

## `tests/test_atomics.lua` — Full Breakdown (47 lines)

### .mlua Source (lines 12–20)

```lalin
func atomic_demo(p: ptr(i32)): i32
    atomic_store(i32, p, 10)
    let old: i32 = atomic_fetch_add(i32, p, 5)
    let seen: i32 = atomic_cas(i32, p, 15, 21)
    atomic_fence()
    let after: i32 = atomic_load(i32, p)
    return old + seen + after
end
```

5 atomic operations exercised: **store**, **fetch_add** (RMW), **cas**, **fence**, **load**.

### BackCmd Assertions (lines 28–38)

Iterates over `program.cmds` and checks `pvm.classof(cmd)` against exactly these 5 ASDL variants:

| Flag | ASDL class |
|------|------------|
| `saw_load` | `B.CmdAtomicLoad` |
| `saw_store` | `B.CmdAtomicStore` |
| `saw_rmw` | `B.CmdAtomicRmw` |
| `saw_cas` | `B.CmdAtomicCas` |
| `saw_fence` | `B.CmdAtomicFence` |

Line 38 asserts **all five** are true: `assert(saw_load and saw_store and saw_rmw and saw_cas and saw_fence)`.

### JIT Execution Verification (lines 40–45)

```
cell = [0]
↓ atomic_store(p, 10)       → cell = [10]
↓ fetch_add(p, 5)           → old = 10,   cell = [15]
↓ cas(p, 15, 21)            → seen = 15,  cell = [21]   (matches, swap succeeds)
↓ fence()
↓ atomic_load(p)            → after = 21
↓ return 10 + 15 + 21       → 46
```

| Assertion | Expected |
|-----------|----------|
| `atomic_demo(cell) == 46` | Sum: old (10) + seen (15) + after (21) |
| `cell[0] == 21` | Final CAS result |

### Current Runtime Status

From the shared workflow context, this test **cannot currently pass** at line 38. The lowering pipeline (`code_to_back.lua` / `lower_to_back.lua`) emits `CmdLoadInfo`/`CmdStoreInfo` instead of `CmdAtomic*` variants — so all five `saw_*` flags remain `false`, and the assertion fires.

Even if that assertion were removed, there's a second gap: the binary encoder (`back_command_binary.lua`) has no branches for `CmdAtomicLoad`/`CmdAtomicStore`/`CmdAtomicRmw`/`CmdAtomicCas`/`CmdAtomicFence`, so atomic BackCmds would be silently dropped at encode time. The encoder gap is what the `encoder` edit plan (T001–T005) addresses — but the **lowering gap** (producing the right BackCmds in the first place) is separate, unplanned work.

## Scout Output — 2026-06-17 20:21:06

Here is the complete report.

---

## Files Retrieved

| # | File | Lines | Purpose |
|---|------|-------|---------|
| 1 | `lua/lalin/code_to_back.lua` | 312–338 | `inst_dst_type()` — value-to-type helper, also missing atomics |
| 2 | `lua/lalin/code_to_back.lua` | 446–608 | `inst()` — the full CodeInst→BackCmd dispatch chain |
| 3 | `lua/lalin/code_to_back.lua` | 562–584 | The CodeInstStore / CodeInstCall boundary — insertion point |
| 4 | `lua/lalin/schema/code.asdl` | 153–157 | ASDL definitions of all 5 CodeInstAtomic* variants |

---

## Key Finding: ZERO CodeInstAtomic* references in code_to_back.lua

```bash
grep -rn "CodeInstAtomic" lua/lalin/code_to_back.lua
# (no matches)
```

Confirmed. Every other CodeInst variant that exists in `code.asdl` and is produced by `tree_to_code.lua` has a branch in `code_to_back.lua` **except** the five atomic variants.

---

## The `inst()` Dispatch Chain — Complete (lines 446–608)

The `inst()` function starts at line 446:
```lua
local function inst(ctx, i)
    local k = i.kind
    local cls = pvm.classof(k)
```

### All 22 branches (with exact line numbers):

| Line | Branch | BackCmd emitted | Pattern |
|------|--------|-----------------|---------|
| **448** | `CodeInstConst` | `CmdConst` | `scalar(k.const.ty)` → `Back.CmdConst(bid(k.dst), s, const_literal(k.const))` |
| **454** | `CodeInstAlias` | `CmdAlias` | sub-dispatch on view/aggregate/scalar aliasing |
| **458** | `CodeInstUnary` | `CmdUnary` | `Back.CmdUnary(bid(k.dst), op, shape(k.ty), bid(k.value))` |
| **461** | `CodeInstBinary` | `CmdIntBinary` / `CmdBitBinary` / `CmdShift` | sub-dispatch via `int_op(k.op)`, `bit_op(k.op)`, `shift_op(k.op)` |
| **469** | `CodeInstFloatBinary` | `CmdFloatBinary` | `Back.CmdFloatBinary(bid(k.dst), op, s, float_semantics(...), bid(k.lhs), bid(k.rhs))` |
| **472** | `CodeInstCompare` | `CmdCompare` | `Back.CmdCompare(bid(k.dst), cmp_op(...), shape(k.operand_ty), lhs, rhs)` |
| **475** | `CodeInstCast` | `CmdCast` | `Back.CmdCast(bid(k.dst), cast_op(k.op), s, bid(k.value))` |
| **478** | `CodeInstSelect` | `CmdSelect` | `Back.CmdSelect(bid(k.dst), shape(k.ty), bid(k.cond), bid(k.then_value), bid(k.else_value))` |
| **480** | `CodeInstAddrOf` | `CmdDataAddr` | sub-dispatch on `CodePlaceGlobal` vs `CodePlaceData` |
| **485** | `CodeInstGlobalRef` | `CmdFuncAddr` / `CmdExternAddr` / `CmdDataAddr` | sub-dispatch on ref kind |
| **492** | `CodeInstPtrOffset` | `CmdPtrOffset` | `Back.CmdPtrOffset(bid(k.dst), Back.BackAddrValue(bid(k.base)), index, k.elem_size, k.const_offset, ...)` |
| **495** | `CodeInstViewMake` | `CmdAlias` ×3 | constructs view_component_ids for data/len/stride |
| **502** | `CodeInstViewData` | `CmdAlias` | `Back.CmdAlias(bid(k.dst), view_component_id(k.view, "data"))` |
| **504** | `CodeInstViewLen` | `CmdAlias` | `Back.CmdAlias(bid(k.dst), view_component_id(k.view, "len"))` |
| **506** | `CodeInstViewStride` | `CmdAlias` | `Back.CmdAlias(bid(k.dst), view_component_id(k.view, "stride"))` |
| **508** | `CodeInstLoad` | `CmdLoadInfo` | `Back.CmdLoadInfo(bid(k.dst), shape(k.access.ty), addr, memory_info(ctx, k.access, i.id))` |
| **524** | `CodeInstAggregate` | `CmdCreateStackSlot` + `CmdStackAddr` + `CmdAlias` + `CmdStoreInfo` per field | aggregates lowered to stack + field stores |
| **532** | `CodeInstArray` | same pattern as Aggregate | array lowered element by element |
| **543** | `CodeInstVariantCtor` | `CmdCreateStackSlot` + `CmdConst` (tag) + `CmdStoreInfo` (tag) + optional payload | variant lowered to stack, tag written explicitly |
| **554** | `CodeInstVariantTag` | `CmdLoadInfo` (read tag from offset 0) | loads tag from aggregate at offset 0 |
| **558** | `CodeInstVariantPayload` | `CmdLoadInfo` (read payload at layout offset) | loads payload field |
| **566** | `CodeInstStore` | `CmdStoreInfo` | `Back.CmdStoreInfo(shape(k.access.ty), addr, bid(k.value), memory_info(ctx, k.access, i.id))` |
| **584** | `CodeInstCall` | `CmdCall` | `Back.CmdCall(result, target, sig_id(k.sig), args)` |
| **607** | `else` | `unsupported(k)` | **catch-all — atomics silently hit this** |

### The `unsupported(k)` helper:
```lua
local function unsupported(k)
    error("code_to_back: unsupported instruction or terminator: " .. tostring(pvm.classof(k)), 2)
end
```
This is a **loud error**, not a silent drop. Any `CodeInstAtomicLoad` that reaches the `inst()` function will hit line 607 and error immediately.

---

## The Insertion Point: Lines 582–584

The exact gap where atomics would be inserted:

```lua
   566:         elseif cls == Code.CodeInstStore then
   567:             if pvm.classof(k.place) == Code.CodePlaceLocal and is_byref_aggregate_ty(k.access.ty) then
   ...
   582:                 ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(k.access.ty), addr, bid(k.value), memory_info(ctx, k.access, i.id))
   583:             end
   ╔═  INSERT ATOMICS HERE ══╗
   584:         elseif cls == Code.CodeInstCall then
   585:             check_call_effects(ctx, i.id)
```

Between the `end` that closes `CodeInstStore`'s `if is_view_ty...else...end` block (line 583) and the `elseif cls == Code.CodeInstCall` (line 584).

---

## The `inst_dst_type()` Helper Also Needs Atomics (lines 312–338)

```lua
   312: local function inst_dst_type(ctx, k)
   313:     local cls = pvm.classof(k)
   314:     if cls == Code.CodeInstConst then return k.dst, k.const.ty end
   ...
   324:     if cls == Code.CodeInstLoad then return k.dst, k.access.ty end
   325:     if cls == Code.CodeInstAggregate or cls == Code.CodeInstArray or cls == Code.CodeInstVariantCtor then return k.dst, k.ty end
   ...
   335:     if cls == Code.CodeInstCall then
   336:         local sig = k.sig and ctx.sigs[k.sig.text] or nil
   337:         if sig and sig.results[1] then return k.dst, sig.results[1] end
   338:     end
   339:     return nil, nil  -- atomics fall through to HERE
   340: end
```

The function is called at line 609 after every `inst()` invocation: `note_value(ctx, inst_dst_type(ctx, k))`. Atomic instructions without an `inst_dst_type` entry return `nil, nil`, which `note_value()` silently ignores. This is less catastrophic than the `unsupported(k)` in `inst()`, but means atomic value types won't be tracked in `ctx.value_types`.

---

## The CodeInst ASDL Definitions for Reference (code.asdl lines 153–157)

```
CodeInstAtomicLoad(dst, place, access, ordering)
CodeInstAtomicStore(place, value, access, ordering)
CodeInstAtomicRmw(dst, op, place, value, access, ordering)
CodeInstAtomicCas(dst, place, expected, replacement, access, ordering)
CodeInstAtomicFence(ordering)
```

These are produced by `tree_to_code.lua` (lines 908, 915, 923, 1316, 1318) and consumed by `code_to_c.lua`, `code_validate.lua`, `code_effect_facts.lua`, `code_mem_facts.lua`, `code_graph.lua` — but **not by `code_to_back.lua`**.

---

## The Call Path Into `inst()`

The only call sites for `inst()` are:

1. **`func()` at line 662**: `for j = 1, #b.insts do inst(ctx, b.insts[j]) end` — processes all instructions in a block
2. **`fragment_commands()` at line 843**: `for _, i in ipairs(b.insts or {}) do local dst, ty = inst_dst_type(ctx, i.kind); note_value(ctx, dst, ty) end` — this only calls `inst_dst_type()` to pre-register value types, then `inst()` is called later at line 847 via `inst(ctx, i)` (wait, let me verify this actually calls inst())

There is no alternative path that could handle atomics. Any atomic CodeInst that reaches `func()` or `fragment_commands()` will hit the loud `unsupported(k)` error at line 607.

---

## Summary

- **`code_to_back.lua` has ZERO references to any `CodeInstAtomic*` variant**
- **`inst()` (line 446)**: 22 if/elseif branches, no atomics → hits `unsupported(k)` loud error at line 607
- **`inst_dst_type()` (line 312)**: 18 if-branches, no atomics → returns `nil, nil` silently at line 339
- **Insertion point for `inst()`**: between line 583 (`end` of CodeInstStore) and line 584 (`elseif cls == Code.CodeInstCall`)
- **Insertion point for `inst_dst_type()`**: after line 324 (`CodeInstLoad`) and before line 325 (`CodeInstAggregate`)
- **Existing pattern for memory ops**: `CodeInstLoad` (line 508) and `CodeInstStore` (line 566) both use `memory_info(ctx, k.access, i.id)` and `addr_from_place(ctx, k.place, ...)` — atomics would follow the same pattern but emit `Back.CmdAtomicLoad`/`Back.CmdAtomicStore`/etc. instead of `Back.CmdLoadInfo`/`Back.CmdStoreInfo`
- **The `unsupported(k)` error catches atomics today** — this is a loud failure, not a silent skip

## Edit-planner Output — 2026-06-18 08:08:37

## Precondition Checks

- Confirm `lua/lalin/back_command_binary.lua` has encoder branches for `CmdAtomic*`, `CmdRotate`, `CmdVecMask`, and the final `else error("unrecognized BackCmd: ...")` at ~lines 371, 298, 520, 592.
- Confirm current failure is still in `lua/lalin/code_to_back.lua`: `CodeInstAtomicStore` reaches `unsupported(k)` near line 607.
- Confirm `tree_to_code.lua` already emits:
  - `CodeInstAtomicLoad/Rmw/Cas` at lines 904–923
  - `CodeInstAtomicStore/Fence` at lines 1313–1318
- Confirm `tests/test_atomics.lua` still expects all five `CmdAtomic*` variants and JIT result `46`.

## Files to Modify

### `lua/lalin/code_to_back.lua`

**Goal**: Lower `LalinCode.CodeInstAtomic*` instructions into executable `LalinBack.CmdAtomic*` commands.

#### Edit blocks

1. **Lines 86–91**: Add atomic mapping helpers after `shift_op`.

   **Add**:
   ```lua
   local function atomic_ordering(ordering)
       if ordering == Core.AtomicSeqCst then return Back.BackAtomicSeqCst end
       unsupported(ordering)
   end

   local function atomic_rmw_op(op)
       if op == Core.AtomicRmwAdd then return Back.BackAtomicRmwAdd end
       if op == Core.AtomicRmwSub then return Back.BackAtomicRmwSub end
       if op == Core.AtomicRmwAnd then return Back.BackAtomicRmwAnd end
       if op == Core.AtomicRmwOr then return Back.BackAtomicRmwOr end
       if op == Core.AtomicRmwXor then return Back.BackAtomicRmwXor end
       if op == Core.AtomicRmwXchg then return Back.BackAtomicRmwXchg end
       unsupported(op)
   end
   ```

2. **Lines 323–325**: Extend `inst_dst_type`.

   **Before**:
   ```lua
   if cls == Code.CodeInstLoad then return k.dst, k.access.ty end
   ```

   **After**:
   ```lua
   if cls == Code.CodeInstLoad
      or cls == Code.CodeInstAtomicLoad
      or cls == Code.CodeInstAtomicRmw
      or cls == Code.CodeInstAtomicCas then
       return k.dst, k.access.ty
   end
   ```

3. **Lines 583–584**: Insert atomic branches between `CodeInstStore` and `CodeInstCall`.

   **Add**:
   ```lua
   elseif cls == Code.CodeInstAtomicLoad then
       local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
       local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
       ctx.cmds[#ctx.cmds + 1] =
           Back.CmdAtomicLoad(bid(k.dst), s, addr, memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))

   elseif cls == Code.CodeInstAtomicStore then
       local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
       local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
       ctx.cmds[#ctx.cmds + 1] =
           Back.CmdAtomicStore(s, addr, bid(k.value), memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))

   elseif cls == Code.CodeInstAtomicRmw then
       local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
       local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
       ctx.cmds[#ctx.cmds + 1] =
           Back.CmdAtomicRmw(bid(k.dst), atomic_rmw_op(k.op), s, addr, bid(k.value), memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))

   elseif cls == Code.CodeInstAtomicCas then
       local s = scalar(k.access.ty); if s == nil then unsupported(k.access.ty) end
       local addr = addr_from_place(ctx, k.place, ctx.mem_backend_by_inst[i.id.text])
       ctx.cmds[#ctx.cmds + 1] =
           Back.CmdAtomicCas(bid(k.dst), s, addr, bid(k.expected), bid(k.replacement), memory_info(ctx, k.access, i.id), atomic_ordering(k.ordering))

   elseif cls == Code.CodeInstAtomicFence then
       ctx.cmds[#ctx.cmds + 1] = Back.CmdAtomicFence(atomic_ordering(k.ordering))
   ```

**Patterns to enforce**
- Use `scalar(k.access.ty)`, not `shape(k.access.ty)`, because `CmdAtomic*` requires `BackScalar`.
- Reuse `addr_from_place(...)` and `memory_info(...)` exactly like `CodeInstLoad/Store`.
- Do not add aggregate/view atomic support here; scalar-only is correct for current frontend validation.

**Danger zones**
- `AtomicRmw` op mapping must preserve Add/Sub/And/Or/Xor/Xchg exactly.
- Do not drop `k.ordering` at Code→Back; even if binary wire currently loses it, BackCmd should preserve it.

---

### `tests/test_atomics.lua`

**Goal**: Keep the existing end-to-end test, but improve diagnostics.

#### Edit blocks

1. **Lines 28–38**: Replace boolean-only assertion with counts or missing-list diagnostics.

   Example:
   ```lua
   local counts = { load = 0, store = 0, rmw = 0, cas = 0, fence = 0 }
   ...
   assert(counts.load == 1, "expected one CmdAtomicLoad")
   ...
   ```

2. **Lines 40–45**: Store JIT result before asserting.

   ```lua
   local got = atomic_demo(cell)
   assert(got == 46, "atomic_demo returned " .. tostring(got))
   assert(cell[0] == 21, "cell[0] was " .. tostring(cell[0]))
   ```

---

### `BACKEND_GAPS.md`

**Goal**: Update status after atomics pass.

#### Edit blocks

1. **Summary / Encoder Gaps sections**: Mark encoder gap as closed.
2. **Layer 3 / Lowering Gaps**: Remove atomics from active lowering gaps once `test_atomics.lua` passes.
3. Preserve open gaps:
   - Atomic ordering wire fidelity
   - Vector reductions
   - View return ABI
   - Debug interpreter indirect call stub
   - Closures/handles design gaps

---

## Later / Blocked Files

### `lua/lalin/lower_to_back.lua`

- **Blocked**: Vector reductions error at line 631.
- Needs design for reducing vector accumulators to scalar values via lane extraction/pairwise ops.

### `lua/lalin/code_to_back.lua`

- **Blocked**: View return ABI error at line 646.
- Needs ABI decision: sret pointer vs multi-result lowered descriptor.

### `lua/lalin/debug_interpreter.lua`

- **Blocked**: `BackCallIndirect` zero-stub at lines 1110–1115.
- Needs function-address representation; `CmdFuncAddr` currently no-ops in interpreter.

## Order of Operations

1. Add atomic helper mappings in `code_to_back.lua`.
2. Extend `inst_dst_type`.
3. Add `CodeInstAtomic*` lowering branches.
4. Improve `tests/test_atomics.lua` diagnostics.
5. Run tests.
6. Update `BACKEND_GAPS.md`.

## Testing Strategy

Run:

```sh
luajit tests/test_atomics.lua
luajit tests/test_back_add_i32.lua
luajit tests/test_back_object_emit.lua
luajit tests/test_mlua_host_pipeline.lua
```

If FFI loads stale backend artifacts, run:

```sh
cargo build --release
```

## Structured Edit Plan Sidecar

Created `wf-backend-gap/lowering` sidecar at revision `r1` with:

- T001–T007: atomic lowering, tests, docs
- T008–T010: blocked future design tasks for vector reductions, view return ABI, debug interpreter indirect calls

## Pattern Memo

- Code→Back lowering uses loud `unsupported(...)`; do not silently default.
- Memory ops must reuse `addr_from_place` + `memory_info`.
- Atomic BackCmds take `BackScalar`, not `BackShape`.
- Preserve ordering in BackCmd even though current binary wire fidelity is seq-cst-only.

## Scout Output — 2026-06-18 08:33:32

## Files Retrieved

1. `lua/lalin/lower_to_back.lua` (lines 1–925) — Back semantic lowering; scalar/vector kernel emitters; vector reduction stub.
2. `lua/lalin/code_kernel_plan.lua` (lines 1–369) — builds `KernelBody`, detects streams/effects/folds/results from Flow/Value/Mem.
3. `lua/lalin/code_schedule_plan.lua` (lines 1–160) — schedule selection; currently excludes vector schedules for reduction/closed-form results.
4. `lua/lalin/kernel_emit_support.lua` (lines 1–314) — executable capability classifier; currently rejects vector reductions/closed forms.
5. `lua/lalin/code_lower_plan.lua` (lines 1–189) — converts kernel/schedule decisions into lower fragments.
6. `lua/lalin/code_value_facts.lua` (lines 1–333) — detects `ReductionFact` and `ClosedFormFact`.
7. `lua/lalin/code_flow_facts.lua` (lines 1–340) — counted-loop / edge-arg / induction facts.
8. `lua/lalin/schema/kernel.asdl` (all) — kernel/reduction/result data structures.
9. `lua/lalin/schema/value.asdl` (all) — reduction facts and value expression types.
10. `lua/lalin/schema/schedule.asdl` (all) — `ScheduleVector`, `TailScalar`, lane shape.
11. `lua/lalin/schema/flow.asdl` (all) — loop facts, edge args, counted domains.
12. `lua/lalin/schema/back.asdl` (relevant vector/reduction-capable BackCmds) — vector commands.
13. `src/wire_tags.rs` (vector tags/slots) — actual wire contract.
14. `src/decode.rs` (lines 500–560) — Cranelift vector tag handlers.
15. `tests/test_lower_to_back_kernel_vector.lua` — current vector Back lowering test.
16. `tests/test_code_value_facts.lua` — reduction/closed-form fact tests.
17. `tests/test_code_flow_facts.lua` — end-to-end fact pipeline checks.
18. `tests/test_code_kernel_plan.lua` — kernel plan reduction/closed-form checks.
19. `tests/test_code_schedule_plan.lua` — schedule selection checks.
20. `tests/test_parse_kernels.lua` — scalar reduction execution corpus.
21. `tests/test_lower_to_c_semantic.lua` — C semantic/vector lowering tests.
22. `LANGUAGE_REFERENCE.md` (section 18) — vectorization/reduction language expectations.
23. `BACKEND_GAPS.md` — current documented open vector reduction gap.

## Key Code

### Vector reduction stub in Back lowering

`lua/lalin/lower_to_back.lua:624–632`

```lua
local function emit_vector_kernel_fragment(ctx, code_module, graph, flow, schedules, kernels, fragment)
    local strategy = fragment.strategy
    local kplan = kernel_by_id(kernels)[strategy.kernel.text]
    if kplan == nil then error("lower_to_back: vector kernel strategy references missing kernel", 2) end
    local schedule = ctx.schedule_by_id and ctx.schedule_by_id[strategy.schedule.text]
    if schedule == nil or pvm.classof(schedule.kind) ~= Schedule.ScheduleVector then error("lower_to_back: vector kernel strategy requires ScheduleVector", 2) end
    local vec, elem_ty, lanes = vector_for_lane_shape(schedule.kind.lanes)
    if schedule.kind.tail ~= Schedule.TailScalar and schedule.kind.tail ~= Schedule.TailNone then error("lower_to_back: vector kernel only implements TailScalar/TailNone", 2) end
    if pvm.classof(kplan.body.result) == Kernel.KernelResultReduction or pvm.classof(kplan.body.result) == Kernel.KernelResultClosedForm then error("lower_to_back: vector reductions are not implemented", 2) end
```

### Scalar kernel reduction preservation

`lua/lalin/lower_to_back.lua:438–441`

```lua
elseif cls == Kernel.KernelEffectFold then
    -- Scalar loop emission preserves reductions through the latch edge args
    -- produced by KernelBinding values; no separate Back command is needed.
    return
```

Scalar kernel lowering later emits original latch/exit edge arguments:

```lua
ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(header), edge_args(ctx, latch_fact))
```

### Current vector loop structure

`lua/lalin/lower_to_back.lua:646–733`

Facts:
- Creates two synthetic blocks:
  - `header:kernel_vector`
  - `header:kernel_tail`
- Header computes `next_i = counter + lanes`
- Header branches to vector block if `next_i <= stop`, else tail block
- Vector block emits vector loads/stores, then jumps back to header
- Jump args replace only the counter with `next_i`; other loop params use current `dst_param`

```lua
for _, arg in ipairs(latch_fact and latch_fact.args or {}) do
    if arg.dst_param == counter then jump_args[#jump_args + 1] = next_i else jump_args[#jump_args + 1] = bid(arg.dst_param) end
end
ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(header), jump_args)
```

### Vector expression support

`lua/lalin/lower_to_back.lua:541–592`

Current vector value lowering supports:
- `ValueExprValue`
- `ValueExprConst`
- `ValueExprAdd`
- `ValueExprSub`
- `ValueExprMul`

These lower to:
- scalar splat via `CmdVecSplat`
- vector int binary via `CmdVecBinary`

No reduction-specific operation exists here.

### Kernel planner reduction construction

`lua/lalin/code_value_facts.lua:159–231`

Detected reductions:
- `BinAdd` → `ReductionAdd`
- `BinMul` → `ReductionMul`
- `BinBitAnd` → `ReductionAnd`
- `BinBitOr` → `ReductionOr`
- `BinBitXor` → `ReductionXor`

Closed forms are only emitted for additive arithmetic-series style reductions where contribution is the primary induction variable.

```lua
if rkind == Value.ReductionAdd and primary[contribution.text] and loop_fact.counted ~= nil and loop_fact.counted.stop_exclusive then
    local closed_expr = arithmetic_series_expr(...)
    ...
    closed_forms[#closed_forms + 1] = Value.ClosedFormFact(...)
end
```

### Kernel result/effect construction

`lua/lalin/code_kernel_plan.lua:297–307`

```lua
local reductions, closed_forms = reductions_for_domain(value, domain)
for _, reduction in ipairs(reductions) do
    effects[#effects + 1] = Kernel.KernelEffectFold(reduction)
    proofs[#proofs + 1] = Kernel.KernelProofValue(reduction.proof, "reduction fact justifies kernel fold")
end
local result = Kernel.KernelResultOriginalControl("semantic loop kernel preserves original control by default")
if #closed_forms > 0 then
    result = Kernel.KernelResultClosedForm(closed_forms[1])
elseif #reductions > 0 then
    result = Kernel.KernelResultReduction(reductions[1])
end
```

### Vector schedule currently blocked for reductions

`lua/lalin/code_schedule_plan.lua:75–78`

```lua
local function vector_candidate_kind(plan, target)
    local body = plan.body
    if body == nil or #(body.streams or {}) == 0 then return nil end
    if pvm.classof(body.result) == Kernel.KernelResultReduction or pvm.classof(body.result) == Kernel.KernelResultClosedForm then return nil end
```

### Capability classifier also rejects vector reductions

`lua/lalin/kernel_emit_support.lua:252–254`

```lua
if pvm.classof(result) == Kernel.KernelResultReduction or pvm.classof(result) == Kernel.KernelResultClosedForm then rejects[#rejects + 1] = reject_target("vector reductions/closed forms are not implemented") end
```

So the normal planner path does not currently select `ScheduleVector` for reductions; the `lower_to_back.lua` stub is reached only by forced/hand-constructed vector schedules or after removing these earlier guards.

### Back vector capabilities

`lua/lalin/schema/back.asdl:276–282`

```asdl
CmdVecSplat(dst, ty, value)
CmdVecBinary(dst, op, ty, lhs, rhs)
CmdVecCompare(dst, op, ty, lhs, rhs)
CmdVecSelect(dst, ty, mask, then_value, else_value)
CmdVecMask(dst, op, ty, args*)
CmdVecInsertLane(dst, ty, value, lane_value, lane)
CmdVecExtractLane(dst, ty, value, lane)
```

There is no horizontal vector reduction BackCmd.

### Cranelift wire/vector handlers

`src/decode.rs:515–551`

Available backend vector operations include:
- `splat`
- `insertlane`
- `extractlane`
- vector `iadd/isub/imul`
- vector bitwise `band/bor/bxor`
- vector integer compares
- vector select implemented as mask logic
- vector load/store

No Cranelift-side horizontal-reduction wire tag exists.

## Relationships

### Fact/data flow for reductions

```text
Code blocks with loop params/backedges
  → code_flow_facts.lua
      FlowLoopFacts
      FlowEdgeFact(src → dst_param)
      counted loop + induction
  → code_value_facts.lua
      ReductionFact(accumulator, kind, init, contribution, ty)
      optional ClosedFormFact
  → code_kernel_plan.lua
      KernelEffectFold(reduction)
      KernelResultReduction or KernelResultClosedForm
  → code_schedule_plan.lua / kernel_emit_support.lua
      scalar or closed-form schedules today
      vector schedule rejected for reductions today
  → code_lower_plan.lua
      LowerStrategyKernel or LowerStrategyClosedForm
  → lower_to_back.lua
      scalar kernel preserves reduction through edge args
      closed form replaces accumulator on exit
      vector kernel errors on reduction/closed-form result
```

### Where reduction result is consumed

For `KernelResultClosedForm`, `emit_closed_form_fragment()` lowers the closed-form expression and substitutes it for the reduction accumulator on the loop exit edge, or returns it directly if the exit block immediately returns the accumulator.

`lua/lalin/lower_to_back.lua:760–775`

```lua
local result, _ = lower_value_expr(ctx, strategy.fact.expr)
if jump_block ~= nil and pvm.classof(jump_block.term.kind) == Code.CodeTermReturn
    and #(jump_block.term.kind.values or {}) == 1
    and jump_block.term.kind.values[1] == strategy.fact.reduction.accumulator then
    ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnValue(result)
    return
end
local args = {}
for i, arg in ipairs(jump_args_fact.args or {}) do
    if arg.src == strategy.fact.reduction.accumulator then args[i] = result else args[i] = bid(arg.src) end
end
ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(jump_dest), args)
```

For `KernelResultReduction`, scalar lowering keeps the original accumulator block param and latch args alive; `KernelEffectFold` emits no command.

### Current vector loop vs scalar tail

Current vector lowering:
1. Enters original header.
2. Computes whether a full vector chunk fits.
3. Runs vector body for full chunks.
4. Jumps back to the original header with `counter = counter + lanes`.
5. Falls to scalar tail when fewer than `lanes` remain.
6. Scalar tail uses the original scalar body and latch logic.

The scalar tail path already preserves scalar reductions via original Code/Flow edge args. The vector-main path currently has no reduction accumulator update path.

## Observations

- The language reference explicitly says vector reductions are accumulated in a vector register and horizontally reduced at loop exit.
- Back/Cranelift currently exposes lane extraction and vector binary ops, but no horizontal reduction primitive.
- `ReductionKind` includes `Add`, `Mul`, `Min`, `Max`, `And`, `Or`, `Xor`, but current detection only constructs add/mul/and/or/xor reductions.
- Current vector expression support in `lower_to_back.lua` covers integer add/sub/mul, not bitwise vector expressions in the semantic vector emitter.
- Current vector scheduling requires at least one stream and contiguous memory.
- Current vector schedule selection excludes any `KernelResultReduction` or `KernelResultClosedForm`.
- Current scalar kernel lowering treats `KernelEffectFold` as metadata; reduction correctness comes from original loop-carried block parameters and `FlowEdgeFact` args.
- Current vector lowering replaces only the induction counter in latch jump args; all non-counter params are passed through unchanged.
- Existing vector Back tests cover vector map/load/store/binary operations, not vector reductions.
- Existing reduction tests cover scalar execution and closed-form lowering, not vector reduction lowering.

## Knowledge-builder Output — 2026-06-18 08:36:08

### What Matters Most for This Problem

- **Reduction-state invariants**, not just instruction availability.
- **Loop-carried accumulator correctness** across vector body, scalar tail, and exit edges.
- **Avoiding double-counting or dropping contributions** when vector and scalar paths coexist.
- **BackCmd expressiveness limits**: no horizontal reduction primitive, only lane extract + scalar/vector ops.
- **Planner guard sequencing**: vector reduction must remain rejected until lowering can preserve scalar semantics.
- **Initial safe subset**: integer add/mul/bitwise reductions only; min/max and closed forms need separate treatment.

---

### Non-Obvious Observations

#### 1. Vector reductions are harder than vector map/store because they mutate loop-carried control state

Normal vector map/store kernels are mostly side-effecting stream transforms:

```text
load vector → compute vector → store vector → advance counter
```

The current vector emitter can safely update only the induction counter because all other loop params are unchanged.

A reduction is different: the accumulator is a loop-carried block parameter whose value is semantically updated every iteration. If the vector body processes `lanes` iterations but passes the accumulator through unchanged, then the vectorized iterations are skipped from the reduction result.

So the missing piece is not “emit vector add”; it is preserving the invariant:

```text
scalar_acc_after_vector_chunk
=
scalar_acc_before_chunk ⊕ contribution[i] ⊕ ... ⊕ contribution[i+lanes-1]
```

The current vector loop violates that invariant by advancing `counter` without advancing `accumulator`.

---

#### 2. Scalar reductions work because the original CFG already encodes the accumulator update

Scalar lowering does not need a special `CmdReduce` because the original latch edge already carries the updated accumulator value:

```text
jump header(i = i + 1, acc = acc + contribution)
```

`KernelEffectFold` being a no-op is only correct because the scalar CFG still executes the original accumulator-producing instructions.

Vector lowering, however, bypasses multiple scalar iterations at once. That breaks the implicit “the original latch updates the accumulator” mechanism.

So vector reduction lowering needs to recreate accumulator advancement explicitly; it cannot rely on the existing scalar edge args in the same way scalar lowering does.

---

#### 3. The vector accumulator and scalar accumulator must have a precise relationship

A vector reduction usually has two pieces of state:

```text
scalar_base_acc  -- accumulator value before vectorized chunks
vector_acc       -- lane-wise partial reductions over vectorized chunks
```

A key invariant is:

```text
final_acc = scalar_base_acc ⊕ horizontal_reduce(vector_acc) ⊕ scalar_tail_contributions
```

But the order of combining those pieces matters for semantics. For integer add/bitwise ops this is usually safe. For non-associative or order-sensitive operations, it is not.

This is why the safe initial reduction set should be restricted to operations where regrouping is valid under the language/backend semantics.

---

#### 4. Accumulator initialization is a major edge case

The `ReductionFact` has an `init` value. A vector accumulator cannot blindly be initialized with `splat(init)`.

For add:

```text
horizontal_sum(splat(init)) = init * lanes
```

which applies the initial accumulator too many times.

The vector partial accumulator should represent only vectorized contributions, while the scalar init must be included exactly once in the final scalar combination.

This applies to all reductions:

| Reduction | Neutral identity | Bug if splatting init |
|---|---:|---|
| add | 0 | adds init once per lane |
| mul | 1 | multiplies init once per lane |
| and | all-bits-1 | ANDs init once per lane |
| or | 0 | ORs init once per lane |
| xor | 0 | XORs init once per lane, parity-dependent |

The distinction between “reduction init” and “vector lane identity” is critical.

---

#### 5. Scalar tail interaction is the central correctness trap

With `TailScalar`, the scalar tail processes leftover iterations after the vector loop. There are two valid semantic shapes, but both require care:

```text
A. horizontal-reduce vector_acc before entering scalar tail
   tail starts with acc = scalar_base_acc ⊕ reduced_vector

B. scalar tail preserves original acc, then exit combines tail_acc with reduced_vector
```

The current emitter jumps to the original header/tail with non-counter params unchanged. That means the tail starts from the pre-vector accumulator and loses vector contributions unless the exit path compensates.

The invariant must be:

```text
tail_start_acc includes all vector chunks
OR
final_exit_acc combines tail result with vector chunks exactly once
```

Not both, not neither.

---

#### 6. `TailNone` is not simpler unless divisibility is guaranteed

If `TailNone` means the schedule proves the trip count is a multiple of lanes, then no scalar tail exists and the vector reduction result must be combined at exit.

If `TailNone` merely means “ignore tail” or “no generated scalar tail,” then reductions are unsafe unless there is a separate proof of no remainder.

So the vector reduction design depends on the exact semantic contract of `TailNone`, not just the code shape.

---

#### 7. Closed forms and vector reductions are conceptually competing optimizations

A `KernelResultClosedForm` already replaces a loop reduction with a mathematical expression. Vectorizing that same loop may be unnecessary or even harmful:

```text
closed form: O(1), no loop
vector reduction: O(n / lanes), still loop
```

So closed forms probably should not be treated as “vector reductions with a different finalizer.” They are a different lowering strategy.

The existing guard rejecting `KernelResultClosedForm` from vector schedules is defensible: relaxing it before deciding precedence between closed-form lowering and vector lowering could create duplicated or contradictory strategies.

---

#### 8. Safe initial reduction kinds are narrower than the schema

Schema mentions more reduction concepts than the fact detector currently constructs.

Detected today:

- add
- mul
- bitand
- bitor
- bitxor

Not detected currently:

- min
- max

Even among detected kinds, safe vector lowering depends on available BackCmd support:

| Kind | Vector op available? | Horizontal scalar op available? | Initial safety |
|---|---|---|---|
| add | yes, `CmdVecBinary Add` | yes | safest |
| mul | yes, `CmdVecBinary Mul` | yes | likely safe for integers |
| bitand | vector bitwise exists in wire/backend, but vector expression support may be incomplete | yes | safe if emitter supports it |
| bitor | same | yes | safe if emitter supports it |
| bitxor | same | yes | safe if emitter supports it |
| min/max | no current detection; vector op unclear | scalar op may be compare/select | not initial |

A subtle point: backend support is not the same as lowering support. The Rust backend may handle vector bitwise ops, but `lower_to_back.lua` vector expression support currently only mentions add/sub/mul. That limits the safe initial subset unless expression lowering is expanded.

---

#### 9. BackCmd limitations force horizontal reduction to be synthesized

There is no `CmdVecReduceAdd` or equivalent. The only available primitives are:

- `CmdVecExtractLane`
- scalar `CmdIntBinary` / `CmdBitBinary`
- vector binary ops
- possibly `CmdVecInsertLane`

Therefore horizontal reduction must be represented as multiple BackCmds. That has consequences:

- It creates several fresh scalar temps.
- It must know lane count statically.
- It must emit one extraction per lane, or a tree of vector shuffles if those existed — but they do not.
- The final result type must match the scalar accumulator type.
- The lowering must preserve deterministic naming/fresh-id discipline.

This also means vector reduction lowering is not just “one final instruction at loop exit”; it expands into a small scalar reduction sequence.

---

#### 10. Exit substitution must handle all consumers of the accumulator, not just `return acc`

Closed-form lowering has special logic for the easy case:

```lua
if exit immediately returns accumulator:
    CmdReturnValue(result)
else:
    substitute result into jump args
```

Vector reductions need the same class of correctness concern. The accumulator may be consumed by:

- direct return
- jump to another block
- block param on an exit continuation
- later scalar tail block
- possibly multiple exits, depending on region shape

The invariant is:

```text
Every control edge that observes the reduced accumulator must observe the combined scalar+vector value.
```

A design that only patches `return acc` will be incomplete.

---

#### 11. Multiple reductions in one loop are a likely hidden edge case

`code_kernel_plan.lua` appears to collect multiple `KernelEffectFold`s but chooses only one `KernelResultReduction`:

```lua
for reductions:
    effects += KernelEffectFold(reduction)

result = KernelResultReduction(reductions[1])
```

That suggests the planner can know about multiple folds, but result handling may privilege the first one.

Vector reduction lowering must be clear whether it supports:

- exactly one reduction accumulator
- multiple independent reductions
- reduction plus stores
- reduction plus other loop-carried params

The current vector latch behavior passes all non-counter params through unchanged, which would be wrong for every reduction accumulator, not just the first.

---

#### 12. The planner guards are currently protecting a real semantic hole

There are three layers of protection:

1. `code_schedule_plan.lua` does not select vector schedules for reductions.
2. `kernel_emit_support.lua` rejects vector reductions/closed forms.
3. `lower_to_back.lua` errors if such a fragment reaches it.

These guards are not redundant in practice:

- scheduler guard prevents normal path selection
- capability guard documents target executability
- lowering guard protects forced/hand-built strategies

Conceptually, the last guard should remain until lowering is correct. Then earlier guards can be relaxed selectively. Removing the scheduler guard first would route real programs into a known-bad lowering path.

---

#### 13. The scalar tail can be used as a correctness oracle

For a vector reduction with `TailScalar`, the result should match pure scalar lowering for all trip counts:

- `n = 0`
- `n < lanes`
- `n == lanes`
- `n == lanes + 1`
- `n` not divisible by lanes
- `n` divisible by lanes
- negative/zero/identity-sensitive values

These cases expose the usual bugs:

- vector init applied too many times
- tail contributions dropped
- vector contributions dropped
- last partial chunk mishandled
- accumulator combined twice

---

#### 14. Tests need to prove control-edge semantics, not only numeric happy paths

Good correctness tests should include:

- add reduction with non-zero init
- mul reduction with init not equal to `1`
- xor reduction with odd/even lane counts
- bitand with identity-sensitive initial value
- trip counts around lane boundaries
- reduction result returned directly
- reduction result passed through an exit block param before return
- vector body with stores plus reduction, to ensure effects and fold coexist
- scalar-only and vector-scheduled versions compared on same inputs

The most important tests are those where wrong initialization still compiles but returns a plausible incorrect value.

---

### Knowledge Gaps

- Exact `TailNone` semantic guarantee: does it prove no remainder, or merely omit tail generation?
- Whether vector bitwise lowering is already supported in `lower_to_back.lua` despite backend support.
- Whether multiple simultaneous `ReductionFact`s can reach one vector kernel in real programs.
- Whether integer overflow semantics are explicitly wrapping, because that affects associativity assumptions for add/mul reductions.

## Approach-proposer Output — 2026-06-18 08:52:08

### Approach A: Lua-Synthesized Vector Monoid Accumulators
- **Core idea**: Keep reductions as explicit vector accumulators in `lower_to_back.lua`, driven by a complete reduction algebra table, and synthesize horizontal reduction with existing `CmdVecExtractLane` plus scalar ops.

- **Key changes**:
  - Add a reduction algebra module/table used by `lower_to_back.lua`.
  - Extend vector kernel lowering to maintain one vector accumulator per reduction.
  - Synthesize min/max with `CmdVecCompare` + `CmdVecSelect`; synthesize horizontal fold with lane extraction.
  - Relax scheduler/capability guards only after lowering supports all reduction kinds.
  - Keep closed forms as a separate lowering strategy, preferably chosen over vector reduction when no side effects require vectorized execution.

- **Tradeoff**: Optimizes for true SIMD reduction structure and keeps most logic in Lua lowering; sacrifices simplicity because `lower_to_back.lua` must understand accumulator placement, tail merging, min/max semantics, and multi-reduction state.

- **Risk**: Incorrect accumulator initialization or tail entry substitution could silently double-count or drop vectorized contributions.

- **Rough sketch**:
  - Define complete algebra records for `add`, `mul`, `and`, `or`, `xor`, `min`, `max`: identity literal, scalar combine, vector combine, horizontal combine, type legality, signed/unsigned/float comparison semantics.
  - In the vector preheader, initialize each vector accumulator to the operation identity, **not** to the user reduction init.
  - In the vector body, compute each reduction contribution as a vector and update `vacc = algebra.vector_combine(vacc, contribution)`.
  - On transition to scalar tail, horizontally reduce `vacc`, combine with the original scalar accumulator, and pass that combined value as the tail accumulator block arg.
  - For `TailNone`, horizontally reduce and substitute the combined accumulator directly on the vector exit edge.

---

### Approach B: Lane-Scalarized Reduction Accumulators
- **Core idea**: Use vector loads/stream computation where possible, but represent each reduction as `lanes` independent scalar accumulators carried through the vector loop.

- **Key changes**:
  - Extend vector kernel lowering to create scalar lane accumulators instead of vector accumulators.
  - Extract each contribution lane and update the corresponding scalar accumulator with the full scalar reduction algebra.
  - Use scalar compare/select for min/max, avoiding dependency on missing vector min/max primitives.
  - Add lane-wise expression scalarization fallback for reductions whose vector expression form is unavailable.
  - Tail/exit logic folds all lane accumulators into the original scalar accumulator.

- **Tradeoff**: Optimizes for semantic completeness using existing scalar BackCmds; sacrifices SIMD reduction efficiency because the accumulation itself becomes scalarized inside the vector loop.

- **Risk**: Generated IR may be much larger for wide vectors or multiple reductions, and performance may disappoint despite correct vectorized memory traversal.

- **Rough sketch**:
  - For every reduction and lane, initialize a scalar lane accumulator to the algebra identity.
  - In each vector iteration, compute the contribution vector or scalarize the contribution expression per lane.
  - Emit `CmdVecExtractLane` for each lane contribution, then apply scalar `add/mul/bitop/select-min/select-max`.
  - At tail entry, fold lane accumulators into the original accumulator exactly once, then enter the scalar tail with that combined value.
  - This approach naturally supports add/mul/and/or/xor/min/max for signed, unsigned, and float semantics because the final operation is scalar Back lowering.

---

### Approach C: First-Class Backend Reduction Commands
- **Core idea**: Promote reductions into explicit Back/wire/backend operations so Lua lowering emits semantic reduction commands and Rust/Cranelift owns the lowering details.

- **Key changes**:
  - Extend `back.asdl` with first-class reduction algebra representation, e.g. `BackReductionOp`.
  - Add commands such as `CmdVecReduceUpdate` and `CmdVecHorizontalReduce`, or a combined `CmdVecReduceFinalize`.
  - Add binary encoder tags and Rust decoder support.
  - Implement horizontal reduction synthesis in Rust using Cranelift vector ops, lane extraction, scalar combines, compare/select for min/max, and exact type semantics.
  - Update validation, wire docs, and tests around the new semantic contract.

- **Tradeoff**: Optimizes for a clean semantic boundary and avoids duplicating reduction lowering logic in Lua; sacrifices migration cost because it changes ASDL, wire format, encoder, decoder, and validation.

- **Risk**: Wire/backend expansion can become another synchronization burden unless the reduction algebra is centralized and exhaustively tested.

- **Rough sketch**:
  - Define complete backend reduction algebra: identities, signed/unsigned/float legality, integer wrapping behavior, float NaN/min/max policy.
  - Lua vector lowering carries vector accumulators but emits semantic reduction commands rather than manually synthesizing every combine/finalize sequence.
  - Rust decoder lowers each reduction op into Cranelift IR, synthesizing missing horizontal operations with extracts and scalar combines.
  - Closed forms remain higher-priority when they replace the whole reduction; otherwise vectorized side effects may still run while the closed-form value substitutes the accumulator.
  - Relax guards in order: backend support → encoder/validator → forced lowering tests → capability classifier → scheduler.

---

### Comparison

Pick **Approach A** if Lalin wants real vector reduction structure now without changing the wire/backend contract.
Pick **Approach B** if semantic completeness is more important than SIMD arithmetic performance and you want to avoid backend changes.
Pick **Approach C** if reductions are considered a core backend concept and Lalin should have a durable, explicit reduction ABI instead of synthesizing everything in Lua.

All three should test the full algebra: add, mul, and, or, xor, min, max; signed/unsigned/float variants; non-zero init; identities; `n = 0`, `< lanes`, `== lanes`, `lanes + 1`, divisible and non-divisible trip counts; scalar tail; `TailNone`; direct return and exit-block-param consumers; multiple simultaneous reductions; and vector stores plus reductions in the same loop.

## Critique Output — 2026-06-18 09:54:03

### Approach A: Lua-synthesized vector monoid accumulators

| Dimension | Score | Rationale |
|---|---:|---|
| **ASDL clarity** | 4/5 | Preserves current Back ASDL as primitive, flat commands. Reduction lowering is explicit composition of existing ops. |
| **Coupling** | 3/5 | Couples `lower_to_back.lua` to detailed BackCmd capabilities and lane semantics, but avoids Lua/Rust wire changes. |
| **Cohesion** | 3/5 | Reduction logic belongs in lowering, but a full algebra table plus tail/exit handling risks making `lower_to_back.lua` too broad. |
| **Implementation cost** | 3/5 | Moderate-high: vector accumulator state, identities, horizontal fold, tail merge, exit substitution. |
| **Long-term maintainability** | 4/5 | If centralized cleanly, this is maintainable: one lowering path, no ASDL churn, no backend synchronization burden. |
| **Lalin philosophy fit** | 4/5 | Fits flat BackCmds and explicit lowering. Keeps ASDL as primitive architecture rather than adding semantic mega-ops. |
| **Overengineering risk** | 3/5 | Complete min/max/float/signed algebra could become too ambitious if done all at once. |
| **Brittle local paths risk** | 3/5 | Main risk is tail/exit substitution and accumulator initialization, but it can remain one coherent path. |

**Verdict**: **Yes with caveats**
**Key concern**: Keep it as one disciplined reduction-lowering mechanism, not scattered special cases for each reduction kind and tail shape.

---

### Approach B: Lane-scalarized reduction accumulators

| Dimension | Score | Rationale |
|---|---:|---|
| **ASDL clarity** | 4/5 | No ASDL changes; uses existing scalar/vector primitives. |
| **Coupling** | 3/5 | Avoids backend coupling, but tightly couples lowering to lane count, scalar temp generation, and expression scalarization. |
| **Cohesion** | 2/5 | Hybrid path: vector loads/computation plus scalar per-lane reduction. Conceptually muddier than true vector reduction. |
| **Implementation cost** | 3/5 | May be simpler for min/max and scalar semantics, but expression scalarization and per-lane state grow quickly. |
| **Long-term maintainability** | 2/5 | High risk of becoming many brittle little paths: per-lane extraction, scalarized fallbacks, multiple reductions, expression coverage gaps. |
| **Lalin philosophy fit** | 3/5 | Explicit and flat, but less clean: the semantic reduction is obscured by generated lane plumbing. |
| **Overengineering risk** | 3/5 | Not heavy architecturally, but can overproduce IR and fallback logic. |
| **Brittle local paths risk** | 5/5 | This is the biggest weakness: many small lane-specific cases are likely to accumulate. |

**Verdict**: **Significant concerns**
**Key concern**: It solves correctness by multiplying local lowering machinery, which conflicts with the priority to avoid brittle little paths.

---

### Approach C: First-class backend reduction commands

| Dimension | Score | Rationale |
|---|---:|---|
| **ASDL clarity** | 3/5 | Makes reductions explicit in ASDL, but risks raising Back ASDL above its current primitive instruction-like level. |
| **Coupling** | 5/5 | Strongly couples ASDL, validator, binary encoder, wire tags, Rust decoder, docs, and tests. |
| **Cohesion** | 4/5 | Backend owns backend lowering details, which is cohesive if reductions are considered a backend primitive. |
| **Implementation cost** | 5/5 | Highest cost: schema, wire format, Lua encoder, Rust decoder, validation, docs, migration tests. |
| **Long-term maintainability** | 3/5 | Could be durable if reductions become central, but creates another Lua/Rust synchronization surface. |
| **Lalin philosophy fit** | 3/5 | Fits “ASDL as architecture,” but less clearly fits “flat BackCmds” if commands become semantic reduction abstractions. |
| **Overengineering risk** | 5/5 | Highest. This is a large architectural expansion for a lowering problem currently expressible with existing primitives. |
| **Brittle local paths risk** | 2/5 | Centralizes semantics better than B, but replaces local brittleness with cross-layer contract brittleness. |

**Verdict**: **Significant concerns**
**Key concern**: Do not expand the Back/wire/Rust contract unless vector reductions are truly a first-class backend concept, not just missing lowering.

---

## Summary

- **Recommended**: **Approach A**. It best matches the stated priority: keeps ASDL clean, avoids wire/backend churn, preserves flat BackCmds, and can be implemented as one explicit lowering path rather than many ad hoc fallbacks.
- **Dark horse**: **Approach C**. It has upside if reductions become a major backend abstraction, but it is likely overengineered for the current gap.
- **Avoid**: **Approach B**. It avoids ASDL changes, but creates the highest risk of brittle per-lane local machinery and muddled long-term semantics.

## Documenter Output — 2026-06-18 09:58:05

# Vector Reduction Lowering Decision

## Goal

Enable Lalin’s Back lowering to compile vectorized reductions correctly by synthesizing reduction state and finalization in Lua using existing `BackCmd` primitives, without changing the Back ASDL, binary wire format, or Rust Cranelift backend contract.

## Incentives

Vector reductions are a documented language/backend expectation, but the current Back lowering path explicitly rejects them. `lower_to_back.lua` errors with `"vector reductions are not implemented"` when a vector kernel has `KernelResultReduction` or `KernelResultClosedForm`. Earlier planner layers also reject these cases, so normal vector scheduling avoids them. This protects correctness, because the current vector loop advances the induction counter by `lanes` while passing non-counter loop parameters, including reduction accumulators, through unchanged. If the guard were removed without a design, vectorized iterations would be skipped from the final reduction.

The decision addresses this semantic gap while preserving Lalin’s existing architecture: flat `BackCmd[]`, primitive backend commands, and no new Lua/Rust wire synchronization surface.

## Current State

Reduction facts are discovered before Back lowering:

- `lua/lalin/code_value_facts.lua` detects `ReductionFact` values for:
  - add
  - mul
  - bitand
  - bitor
  - bitxor
- It can also produce `ClosedFormFact` for additive arithmetic-series reductions.
- `lua/lalin/code_kernel_plan.lua` converts these into:
  - `KernelEffectFold(reduction)`
  - `KernelResultReduction(reduction)` or `KernelResultClosedForm(closed_form)`

Scalar lowering already preserves reductions correctly. In `lower_to_back.lua`, scalar kernel emission treats `KernelEffectFold` as metadata because the original scalar CFG already carries the updated accumulator through latch edge arguments:

```text
jump header(i = i + 1, acc = acc ⊕ contribution)
```

Vector lowering is different. The current vector kernel path creates a vector loop and scalar tail structure, but only updates the induction counter on the vector latch. Other loop parameters are passed through unchanged:

```text
jump header(counter = counter + lanes, acc = acc)
```

That is correct for vector map/store kernels, but incorrect for reductions because the accumulator must advance by all vectorized lane contributions.

The current codebase prevents this invalid lowering through three guards:

1. `code_schedule_plan.lua` does not select vector schedules for reduction or closed-form results.
2. `kernel_emit_support.lua` rejects vector reductions and closed forms.
3. `lower_to_back.lua` errors if a forced vector reduction reaches Back lowering.

The Back layer already has enough primitive operations to synthesize reductions:

- `CmdVecSplat`
- `CmdVecBinary`
- `CmdVecCompare`
- `CmdVecSelect`
- `CmdVecExtractLane`
- scalar `CmdIntBinary`
- scalar `CmdBitBinary`
- scalar compare/select as needed

There is no first-class horizontal reduction `BackCmd`, and the chosen design preserves that.

## Chosen Target

### Approach

Use **Approach A: Lua-synthesized vector monoid accumulators**.

Vector reductions will be implemented inside `lua/lalin/lower_to_back.lua` as explicit compositions of existing Back commands. The Back ASDL, binary encoder, wire tags, and Rust decoder remain unchanged.

This approach was chosen because it keeps Back commands flat and primitive, avoids adding a new Lua/Rust synchronization contract, and keeps reduction lowering as a compiler lowering responsibility rather than a new backend ABI feature.

### Architecture

The implementation must introduce one centralized reduction algebra mechanism/table used by vector reduction lowering. Reduction semantics must not be scattered across per-kind or per-tail ad hoc branches.

Each algebra entry must describe, as applicable:

- reduction kind:
  - add
  - mul
  - and
  - or
  - xor
  - min
  - max
- type legality:
  - integer signed/unsigned where relevant
  - float where relevant
- identity value
- vector combine operation
- scalar combine operation
- horizontal reduction sequence
- comparison/select semantics for min/max
- any operation-specific restrictions

Vector lowering should maintain one vector accumulator per reduction. The accumulator must be initialized to the operation identity, **not** to the user’s scalar reduction init.

That distinction is critical. For example, initializing an add vector accumulator with `splat(init)` would cause the init value to be counted once per lane:

```text
horizontal_sum(splat(init)) = init * lanes
```

Instead, the vector accumulator represents only the contributions processed by vectorized chunks:

```text
vector_acc = identity
vector_acc = vector_acc ⊕ contribution_vector
```

At the boundary between vector loop, scalar tail, and exit, lowering must combine values exactly once:

```text
final_acc =
    scalar_base_acc
    ⊕ horizontal_reduce(vector_acc)
    ⊕ scalar_tail_contributions
```

The implementation must ensure either:

1. the scalar tail starts with the scalar accumulator already combined with the vector contribution, or
2. the final exit combines the tail result with the vector contribution,

but never both and never neither.

Closed forms remain a distinct lowering strategy. `KernelResultClosedForm` should not be treated as a vector reduction variant. Closed-form lowering replaces a reduction with a mathematical expression and is conceptually separate from SIMD reduction lowering.

Planner and capability guards must remain in place until forced vector-reduction lowering and tests demonstrate correctness. Relaxation order should be conservative:

1. implement forced lowering path,
2. test correctness across identities, tails, and exit shapes,
3. then relax capability/scheduler guards selectively.

### Required invariants

The lowering must preserve these invariants:

```text
scalar_acc_after_vector_chunk
=
scalar_acc_before_chunk
⊕ contribution[i]
⊕ ...
⊕ contribution[i + lanes - 1]
```

```text
vector_acc contains only vectorized contributions,
not the user reduction init.
```

```text
Each vectorized contribution is included exactly once.
Each scalar tail contribution is included exactly once.
The user init is included exactly once.
```

```text
Every control edge that observes the reduced accumulator observes
the combined scalar + vector result.
```

### Rejected approaches

#### Approach B: Lane-scalarized reduction accumulators

Rejected because it would represent each lane as an independent scalar accumulator and fold them later. Although it avoids ASDL changes, it risks creating many brittle local paths: per-lane extraction, scalarized expression fallback, lane-specific temps, and duplicated reduction plumbing. The critique found this less cohesive and more likely to degrade maintainability.

#### Approach C: First-class backend reduction commands

Rejected because it would expand the Back ASDL, validator, binary encoder, wire format, Rust decoder, documentation, and tests. That creates a large new synchronization surface for a problem currently expressible with existing primitives. It was considered overengineered for this gap and less aligned with the current flat primitive Back command model.

### Tradeoffs acknowledged

This design keeps the backend contract stable, but makes `lower_to_back.lua` responsible for detailed reduction semantics, including identities, horizontal folding, tail merging, and type legality. That complexity is acceptable because it remains centralized in one reduction algebra mechanism rather than distributed across the backend stack.

The design also does not introduce a dedicated horizontal reduction instruction. Horizontal reduction will be synthesized with lane extraction and scalar combines. This may be less optimal than a backend-native reduction primitive, but it avoids ASDL and wire churn.

### Risks acknowledged

Known risks from the critique and analysis:

- initializing vector accumulators incorrectly can double-count the user init;
- tail handling can drop or double-count vector contributions;
- exit substitution must handle accumulator consumers beyond direct `return acc`;
- multiple simultaneous reductions may expose additional state-management complexity;
- min/max semantics require careful signed, unsigned, and float behavior;
- relaxing planner guards too early would route real programs into unsafe lowering.

## Implementation Implications

The implementation should focus on `lua/lalin/lower_to_back.lua`.

Expected changes include:

- introduce a centralized reduction algebra table/module;
- extend vector kernel lowering to allocate and update vector accumulator state;
- synthesize horizontal reduction using existing Back commands, especially `CmdVecExtractLane` plus scalar combines;
- merge vector accumulator results into scalar accumulator/tail/exit paths exactly once;
- keep closed-form lowering separate;
- preserve existing scheduler/capability guards until correctness tests exist.

Tests must cover:

- non-zero init values;
- identity-sensitive reductions;
- trip counts `0`, `< lanes`, `== lanes`, `lanes + 1`, divisible and non-divisible by lanes;
- scalar tail behavior;
- direct return and exit-block-param consumers;
- multiple reductions where supported;
- vector stores combined with reductions.

## Edit-planner Output — 2026-06-18 10:05:29

## Precondition Checks

Before editing, verify:

1. `lua/lalin/lower_to_back.lua:631` still contains:
   ```lua
   if pvm.classof(kplan.body.result) == Kernel.KernelResultReduction
      or pvm.classof(kplan.body.result) == Kernel.KernelResultClosedForm then
       error("lower_to_back: vector reductions are not implemented", 2)
   end
   ```
2. `lua/lalin/code_schedule_plan.lua:80` still rejects both `KernelResultReduction` and `KernelResultClosedForm`.
3. `lua/lalin/kernel_emit_support.lua:254` still has the blanket vector rejection:
   ```lua
   vector reductions/closed forms are not implemented
   ```
4. `lua/lalin/schema/value.asdl` already contains `ReductionMin` and `ReductionMax`; do **not** add Back ASDL/wire/Rust tags.
5. Run a baseline:
   ```sh
   luajit tests/test_lower_to_back_kernel_vector.lua
   luajit tests/test_code_value_facts.lua
   luajit tests/test_code_schedule_plan.lua
   ```

---

## Files to Modify

### `lua/lalin/reduction_algebra.lua` *(new)*

**Goal**: Centralize all reduction semantics and legality decisions.

**Contents sketch**:

```lua
local M = {}

function M.Define(T)
    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Back = T.LalinBack

    local api = {}

    -- type helpers:
    -- api.type_info(ty) -> { class="int"/"float"/"index"/"bool", bits=..., signed=... }

    -- detection helpers:
    -- api.binary_reduction_kind(op, is_float)
    -- api.select_minmax_kind(compare_op, true_value_is_lhs)

    -- legality:
    -- api.vector_support(reduction, elem_ty) -> ok, reason

    -- algebra lookup:
    -- api.entry(kind, ty) -> entry or nil, reason
    --
    -- entries for:
    -- add, mul, and, or, xor, min, max

    return api
end

return M
```

**Required algebra coverage**:

- `ReductionAdd`
  - integer vector: `BackVecIntAdd`
  - scalar: `BackIntAdd`
  - identity: `0`
  - float: recorded as designed but vector-unsupported until Back has float vector ops.
- `ReductionMul`
  - integer vector: `BackVecIntMul`
  - scalar: `BackIntMul`
  - identity: `1`
  - float: vector-unsupported.
- `ReductionAnd`
  - vector: `BackVecBitAnd`
  - scalar: `BackBitAnd`
  - identity: all bits set; use `-1`.
- `ReductionOr`
  - vector: `BackVecBitOr`
  - scalar: `BackBitOr`
  - identity: `0`.
- `ReductionXor`
  - vector: `BackVecBitXor`
  - scalar: `BackBitXor`
  - identity: `0`.
- `ReductionMin`
  - integer vector: `CmdVecCompare` + `CmdVecSelect`
  - signedness decides `BackVecSIcmpLe` vs `BackVecUIcmpLe`
  - identity:
    - signed: max signed value for bit width
    - unsigned: all bits set / max unsigned
  - float: vector-unsupported until Back has vector float compare.
- `ReductionMax`
  - integer vector: `CmdVecCompare` + `CmdVecSelect`
  - signedness decides `BackVecSIcmpGe` vs `BackVecUIcmpGe`
  - identity:
    - signed: min signed value for bit width
    - unsigned: `0`
  - float: vector-unsupported.

**Danger zones**:
- Do not make Back ASDL changes.
- Do not pretend float vector reductions are supported; represent them in the algebra with explicit unsupported reasons.
- Keep `index` min/max conservative unless target-width identity is unambiguous.

---

### `lua/lalin/code_value_facts.lua`

**Goal**: Use the centralized algebra for reduction detection and add min/max fact detection.

#### Edit blocks

1. **Lines 15–18**: Add import.

   **After**:
   ```lua
   local CodeGraph = require("lalin.code_graph").Define(T)
   local CodeFlowFacts = require("lalin.code_flow_facts").Define(T)
   local ReductionAlgebra = require("lalin.reduction_algebra").Define(T)
   ```

2. **Lines 159–165**: Replace local `reduction_kind_for`.

   **Before**:
   ```lua
   local function reduction_kind_for(op)
       if op == Core.BinAdd then return Value.ReductionAdd end
       ...
   end
   ```

   **After**:
   ```lua
   local function reduction_kind_for(op, is_float)
       return ReductionAlgebra.binary_reduction_kind(op, is_float)
   end
   ```

3. **After line 165**: Add helper for select/compare min-max recurrence detection.

   **Add structure**:
   ```lua
   local function select_minmax_reduction(param, select_def, defs)
       -- Require select_def.cls == Code.CodeInstSelect.
       -- Look up defs[select.cond.text]; require CodeInstCompare.
       -- Ensure compare operands are exactly accumulator param + one contribution.
       -- Ensure select then/else values are the same two values.
       -- Use ReductionAlgebra.select_minmax_kind(...)
       -- Return kind, contribution, ty, int_semantics, float_mode.
   end
   ```

4. **Lines 196–222**: Extend reduction detection.

   Current logic only handles:
   ```lua
   if def ~= nil and def.cls == Code.CodeInstBinary then
       ...
   end
   ```

   **Modify to handle**:
   - `CodeInstBinary`: existing add/mul/and/or/xor path via algebra.
   - `CodeInstFloatBinary`: add/mul facts with `float_mode = k.mode`; vector lowering will still reject float until supported.
   - `CodeInstSelect`: min/max facts from select/compare pattern.

**Patterns**:
- Preserve closed-form detection only for integer additive arithmetic-series reductions.
- Do not generate closed forms for min/max or bitwise reductions.

---

### `lua/lalin/lower_to_back.lua`

**Goal**: Implement forced TailScalar vector reduction lowering using existing BackCmd primitives.

#### Edit blocks

1. **Lines 27–29**: Import algebra module.

   **After**:
   ```lua
   local CodeLowerPlan = require("lalin.code_lower_plan").Define(T)
   local ReductionAlgebra = require("lalin.reduction_algebra").Define(T)
   ```

2. **After line 56**: Add CodeValue override plumbing.

   **Add**:
   ```lua
   local function code_value(ctx, id)
       local ov = ctx.value_overrides and ctx.value_overrides[id.text]
       if ov ~= nil then return ov.value, ov.ty end
       return bid(id), value_ty(ctx, id)
   end

   local function with_value_overrides(ctx, overrides, fn)
       local old = ctx.value_overrides
       ctx.value_overrides = setmetatable(overrides or {}, { __index = old })
       local ok, a, b = pcall(fn)
       ctx.value_overrides = old
       if not ok then error(a, 0) end
       return a, b
   end
   ```

3. **Line 225**: Modify `ValueExprValue` lowering.

   **Before**:
   ```lua
   return bid(expr.value), ty
   ```

   **After**:
   ```lua
   local v, ty = code_value(ctx, expr.value)
   if ty == nil then error(...) end
   return v, ty
   ```

4. **Line 397**: Modify `KernelExprValue`.

   **Before**:
   ```lua
   if cls == Kernel.KernelExprValue then return bid(expr.value), value_ty(ctx, expr.value) end
   ```

   **After**:
   ```lua
   if cls == Kernel.KernelExprValue then return code_value(ctx, expr.value) end
   ```

5. **Line 445**: Modify `edge_args`.

   Add optional substitutions:
   ```lua
   local function edge_args(ctx, edge_fact, overrides)
       local args = {}
       return with_value_overrides(ctx, overrides, function()
           for _, arg in ipairs(edge_fact and edge_fact.args or {}) do
               local v = code_value(ctx, arg.src)
               args[#args + 1] = v
           end
           return args
       end)
   end
   ```

6. **After `cmp_op` around line 154**: Add vector reduction emission helpers.

   Helpers needed:
   - `reduction_folds(kplan)`
   - `emit_reduction_scalar_identity(ctx, entry, ty)`
   - `emit_reduction_vector_identity(ctx, entry, vec, ty)`
   - `emit_reduction_vector_combine(ctx, entry, vec, lhs, rhs)`
   - `emit_reduction_scalar_combine(ctx, entry, ty, lhs, rhs)`
   - `emit_reduction_horizontal_fold(ctx, entry, ty, vec, base_scalar, vector_acc, lanes)`

   Horizontal fold must use:
   ```lua
   CmdVecExtractLane
   CmdIntBinary / CmdBitBinary / CmdCompare + CmdSelect
   ```

7. **Lines 541–592**: Extend vector expression lowering.

   Add support for:
   - `ValueExprCmp` → `CmdVecCompare`
   - `ValueExprSelect` → `CmdVecSelect`

   Keep float vector compare unsupported unless Back gains a float vector compare op.

8. **Line 631**: Replace vector reduction stub.

   **Before**:
   ```lua
   if pvm.classof(kplan.body.result) == Kernel.KernelResultReduction
      or pvm.classof(kplan.body.result) == Kernel.KernelResultClosedForm then
       error("lower_to_back: vector reductions are not implemented", 2)
   end
   ```

   **After**:
   ```lua
   if pvm.classof(kplan.body.result) == Kernel.KernelResultClosedForm then
       error("lower_to_back: vector closed forms remain a distinct lowering strategy", 2)
   end

   local reductions = reduction_folds(kplan)
   local has_reductions = #reductions > 0
   if has_reductions and schedule.kind.tail ~= Schedule.TailScalar then
       error("lower_to_back: vector reductions currently require TailScalar", 2)
   end
   ```

9. **Lines 646–714**: Split map-only vector path from reduction path.

   Preserve existing non-reduction behavior.

   For reduction path:
   - Create `vector_block` and `tail_check`.
   - Append synthetic params:
     - vector block:
       - vector counter param
       - one vector accumulator param per reduction
     - tail check:
       - scalar counter param
       - one scalar accumulator param per reduction
   - Header:
     - create identity vector accumulators;
     - branch to vector block with `[counter, identity_vecs...]`;
     - branch to tail check with `[counter, original_accs...]`.
   - Vector block:
     - use override `{ counter = vector_counter_param }`;
     - emit vector stores as before;
     - for each reduction:
       - lower contribution as vector;
       - combine current vector accumulator with contribution;
     - compute `next_i`;
     - if another chunk fits, jump to vector block with updated vector accumulators;
     - otherwise horizontally fold each updated vector accumulator into the original scalar accumulator and jump to tail check.
   - Tail check:
     - use overrides `{ counter = tail_counter, acc = tail_acc }`;
     - recompute scalar exit condition through binding expression, not by rebinding original Code value IDs;
     - branch to exit/body using `edge_args(ctx, fact, overrides)`.

**Danger zones**:
- Never initialize vector accumulators with user init.
- Do not bind the same `BackValId` twice when recomputing tail conditions.
- Each vector contribution must be included exactly once.
- Closed forms stay separate.

---

### `lua/lalin/kernel_emit_support.lua`

**Goal**: Let classifier validate vector reductions through the central algebra.

#### Edit blocks

1. **Lines 15–18**: Import algebra.

2. **Lines 189–203**: Extend `vector_value_expr_supported`.

   Add:
   - `ValueExprCmp`
   - `ValueExprSelect`

3. **Line 254**: Replace blanket reduction rejection.

   **Before**:
   ```lua
   if pvm.classof(result) == Kernel.KernelResultReduction
      or pvm.classof(result) == Kernel.KernelResultClosedForm then
       rejects[#rejects + 1] = reject_target("vector reductions/closed forms are not implemented")
   end
   ```

   **After**:
   - Reject `KernelResultClosedForm`.
   - For each `KernelEffectFold`, call `ReductionAlgebra.vector_support(reduction, sk.lanes.elem_ty)`.
   - Also validate `reduction.contribution` with `vector_value_expr_supported`.

---

### `lua/lalin/code_schedule_plan.lua`

**Goal**: Relax scheduler guard only after forced lowering/tests pass.

#### Edit block

1. **Line 80**:

   **Before**:
   ```lua
   if pvm.classof(body.result) == Kernel.KernelResultReduction
      or pvm.classof(body.result) == Kernel.KernelResultClosedForm then return nil end
   ```

   **After**:
   ```lua
   if pvm.classof(body.result) == Kernel.KernelResultClosedForm then return nil end
   ```

Classifier still decides whether vector reduction is executable.

---

### Tests

#### `tests/test_code_value_facts.lua`

Add tests for:
- min recurrence:
  ```lalin
  acc = select(acc < xs[i], acc, xs[i])
  ```
- max recurrence:
  ```lalin
  acc = select(acc > xs[i], acc, xs[i])
  ```
- operand-order variants.

Assert `ReductionMin` / `ReductionMax`.

#### `tests/test_lower_to_back_vector_reductions.lua` *(new)*

Create forced-vector test.

Must cover:
- sum with non-zero init
- product with non-one init
- xor odd/even
- and/or identity-sensitive cases
- min/max
- trip counts: `0`, `< lanes`, `== lanes`, `lanes + 1`, divisible, non-divisible

Verification:
```sh
luajit tests/test_lower_to_back_vector_reductions.lua
```

#### `tests/test_code_schedule_plan.lua`

After scheduler guard relaxation:
- supported integer reductions should receive `ScheduleVector`;
- closed forms should still choose `ScheduleClosedForm`, not vector;
- update clamp/select expectation if vector cmp/select makes it schedulable.

---

### `BACKEND_GAPS.md`

**Goal**: Update after tests pass.

Change vector reduction status from open to closed for:
- supported integer TailScalar reductions;
- Lua-synthesized BackCmd lowering;
- no Back ASDL/wire/Rust changes.

Document remaining limitations:
- float vector reductions blocked by missing Back vector float ops;
- TailNone requires divisibility proof;
- closed forms remain distinct.

---

## Order of Operations

1. Add `lua/lalin/reduction_algebra.lua`.
2. Update `code_value_facts.lua` and test min/max facts.
3. Add override plumbing in `lower_to_back.lua`.
4. Add reduction emission helpers.
5. Implement forced TailScalar vector reduction lowering.
6. Add forced lowering/JIT tests.
7. Update `kernel_emit_support.lua`.
8. Relax `code_schedule_plan.lua`.
9. Add automatic scheduler/JIT tests.
10. Update `BACKEND_GAPS.md`.

---

## Testing Strategy

Run incrementally:

```sh
luajit tests/test_code_value_facts.lua
luajit tests/test_lower_to_back_kernel_vector.lua
luajit tests/test_lower_to_back_vector_reductions.lua
luajit tests/test_code_schedule_plan.lua
luajit tests/test_parse_kernels.lua
```

If JIT artifacts are stale:

```sh
cargo build --release
```

---

## Structured Edit Plan Sidecar

Created/updated sidecar:

- Workflow: `wf-backend-gap`
- Sidecar: `vector-reductions`
- Revision: `r2`
- Tasks: `T001`–`T013`

Ready task:
- `T001 Add central reduction algebra module`

---

## Pattern Memo

- Keep Back ASDL, binary wire format, and Rust decoder unchanged.
- Centralize semantics in `reduction_algebra.lua`.
- Vector accumulator identity is algebra identity, never user init.
- Combine vector contribution with scalar accumulator exactly once at tail/exit boundary.
- Closed forms are separate lowering, not vector reductions.
- Guard relaxation order: forced lowering → forced tests → classifier → scheduler.
