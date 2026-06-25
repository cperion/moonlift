# C backend / WASM support architecture exploration
Explore how to design a robust C backend that consumes Lalin's validated backend commands / wire format and can target native C and eventually WASM while keeping Cranelift.
**Workflow ID**: wf-c-backend-wasm
**Started**: 2026-06-08 07:36:43
---

## Scout Output — 2026-06-08 07:41:07

## Files Retrieved

1. `BACK_WIRE_FORMAT.md` (lines 1-455) — Flatline v4 binary wire format: header, declaration/body sections, scalar codes, memflags, comparator/atomic codes, full tag table, and “removed from v3” notes.
2. `lua/lalin/schema/back.lua` (lines 1-1398) — Source ASDL schema for `LalinBack`: scalars, shapes, target facts, memory/provenance facts, commands, validation issues, inspection products, `BackProgram`.
3. `lua/lalin/back_command_binary.lua` (lines 1-759) — Lua encoder from validated `BackProgram` to Flatline binary consumed by Rust.
4. `src/wire_tags.rs` (lines 1-306) — Rust enum/tag-slot table corresponding to the binary wire tags.
5. `src/decode.rs` (lines 1-711) — Rust Flatline decoder and Cranelift lowering implementation.
6. `src/lib.rs` (lines 1-339) — Rust public backend: scalar mapping, JIT/object entry points, host ISA configuration.
7. `src/ffi.rs` (lines 1-216) — C FFI surface used by LuaJIT (`lalin_jit_compile_binary`, `lalin_object_compile_binary`, artifact APIs).
8. `lua/lalin/back_jit.lua` (lines 1-189) — LuaJIT bridge to Rust JIT binary-wire compile path.
9. `lua/lalin/back_object.lua` (lines 1-93) — Lua bridge to Rust object emission via binary wire.
10. `lua/lalin/back_validate.lua` (lines 1-968) — Validation contract for `BackProgram`: refs, duplicates, command ordering, shape/memory constraints.
11. `lua/lalin/tree_to_back.lua` (lines 1-2729) — Main frontend lowering to backend commands: expressions/statements/control/function ABI/data/external declarations.
12. `lua/lalin/tree_control_to_back.lua` (not read) — Referenced by `tree_to_back`; likely relevant for region/control-specific lowering if continuing.
13. `lua/lalin/type_to_back_scalar.lua` (lines 1-86) — Source type → backend scalar mapping.
14. `lua/lalin/type_size_align.lua` (lines 1-141) — Layout sizes/alignment for scalars, pointers, views, closures, arrays/aggregates.
15. `lua/lalin/type_abi_classify.lua` (lines 1-72) — ABI class decisions: direct scalar/pointer, descriptors, indirect aggregate.
16. `lua/lalin/type_func_abi_plan.lua` (lines 1-83) — Function ABI plan: view flattening, aggregate-by-pointer, return handling.
17. `lua/lalin/back_target_model.lua` (lines 1-157) — Default native target facts and vector target conversion.
18. `lua/lalin/frontend_pipeline.lua` (lines 1-203) — Parse/typecheck/layout/lower/validate pipeline; rejects `CmdTrap` unless allowed.
19. `lua/lalin/init.lua` (lines 1-181) — Public API for hosted load, object/shared emission.
20. `lua/lalin/hosted_jit.lua` (lines 1-75) — In-process hosted Rust binary compile path for standalone binary.
21. `src/main.rs` (lines 1-224) — Standalone `lalin` binary embeds Lua and exposes `_host_compile_binary`.
22. `src/lua_api.rs` (lines 1-158) — Registers runtime/Lua helper symbols for hosted JIT.
23. `src/rt.rs` (lines 1-92) — Built-in runtime helpers: `__ml_memcpy`, `__ml_memset`, allocator.
24. `lua/lalin/link_target_model.lua` (lines 1-42), `link_*` files — Object/shared library linking model and system `cc` command planning.
25. `lua/lalin/back_inspect.lua` (lines 1-57), `back_diagnostics.lua` (lines 1-37) — Backend inspection/diagnostics and optional disassembly.
26. `lua/lalin/host_layout_resolve.lua` (lines 1-254) — Host layout/C ABI facts for exposed structs/views.
27. `lua/lalin/host_c_emit_plan.lua` (lines 1-31) — Existing C header emission for host layouts only, not a codegen backend.
28. `lua/lalin/host_view_abi_plan.lua` (lines 1-114) — Host view descriptor ABI planning.
29. `Cargo.toml` (lines 1-19) — Cranelift deps are native/JIT/object only; no wasm crate/target deps.
30. Tests read:
   - `tests/test_back_command_binary.lua` (lines 1-47)
   - `tests/test_back_add_i32.lua` (lines 1-57)
   - `tests/test_back_call.lua` (lines 1-83)
   - `tests/test_back_extern_mem.lua` (lines 1-117)
   - `tests/test_back_memory_data.lua` (lines 1-133)
   - `tests/test_back_branch_select.lua` (lines 1-109)
   - `tests/test_back_cast_intrinsic_switch.lua` (lines 1-150)
   - `tests/test_back_vector_smoke.lua` (lines 1-73)
   - `tests/test_back_validate.lua` (lines 1-286)
   - `tests/test_back_object_emit.lua` (lines 1-64)
   - `tests/test_back_object_full.lua` (lines 1-249)
   - `tests/test_back_shared_emit.lua` (lines 1-70)
   - `tests/test_back_memory_offset_binary.lua` (lines 1-31)
   - `tests/test_back_indirect_stmt.lua` (lines 1-126)
   - `tests/test_back_zero_alias_ops.lua` (lines 1-143)

## Key Code

### Back command schema

`lua/lalin/schema/back.lua` defines the semantic command set. Critical command families:

```lua
A.sum "Cmd" {
  A.variant "CmdCreateSig" { sig, params, results }
  A.variant "CmdDeclareFunc" { visibility, func, sig }
  A.variant "CmdDeclareExtern" { func, symbol, sig }
  A.variant "CmdBeginFunc" { func }
  A.variant "CmdCreateBlock" { block }
  A.variant "CmdBindEntryParams" { block, values }
  A.variant "CmdAppendBlockParam" { block, value, ty }
  A.variant "CmdCreateStackSlot" { slot, size, align }
  A.variant "CmdConst" { dst, ty, value }
  A.variant "CmdIntBinary" { dst, op, scalar, semantics, lhs, rhs }
  A.variant "CmdLoadInfo" { dst, ty, addr, memory }
  A.variant "CmdStoreInfo" { ty, addr, value, memory }
  A.variant "CmdCall" { result, target, sig, args }
  A.variant "CmdJump" / "CmdBrIf" / "CmdSwitchInt"
  A.variant "CmdReturnVoid" / "CmdReturnValue" / "CmdTrap"
  A.variant "CmdFinishFunc"
  A.variant "CmdFinalizeModule"
}
```

The schema is richer than the binary wire: target facts, alias/provenance, memory evidence, int/float semantics, etc. exist in `BackProgram`.

### Validation contract

`lua/lalin/back_validate.lua` enforces:

- declarations precede references (`sig`, `func`, `extern`, `data`)
- no duplicate sig/data/func/extern/block/slot/value/access
- commands must be inside a function body
- functions must begin/finish correctly
- module must finalize exactly before end
- memory modes/alignment/deref/notrap/can_move constraints
- scalar/shape constraints for int/float/bit/shift/vector operations
- optional target-supported-shape constraints from `CmdTargetModel`

Important excerpt:

```lua
if cls == B.BackFactValueDef then
  note_unique(seen_value, fact.value, ...)
elseif cls == B.BackFactValueUse then
  if active_func ~= nil and not has(seen_value, fact.value) then
    add_issue(issues, B.BackIssueMissingValue(fact.index, fact.value))
  end
end
```

Validation is single-pass in command order for uses/defs; C backend consuming validated programs can assume no forward value uses unless validation changes.

### Binary wire encoder

`lua/lalin/back_command_binary.lua` maps ASDL commands to flat u32 tags/slots.

Notable:

```lua
-- Scalar tags 1-13
local S = { BackBool=1, BackI8=2, ..., BackPtr=12, BackIndex=13 }

-- MemFlags: bit0=notrap, bit1=aligned, bit2=can_move
local function memflags(m)
  local bits = 0
  if m.trap.kind == "BackNonTrapping" or m.trap.kind == "BackChecked" then bits = bit.bor(bits, 1) end
  ...
end
```

`CmdTargetModel` and `CmdAliasFact` are explicitly skipped in binary encoding:

```lua
elseif k == "CmdTargetModel" or k == "CmdAliasFact" then
  -- skip, no-op in Rust decoder
```

At final write:

```lua
w4(buf, 0x4D4C); w4(buf, 4); w4(buf, #body_data)
w4(buf, header_size); w4(buf, #decl_bytes)
w4(buf, header_size + #decl_bytes); w4(buf, body_tbl_size)
```

### Rust decode/lowering

`src/decode.rs` maps scalar codes to Cranelift types:

```rust
fn st(code: u32, ptr_ty: Type) -> Result<Type, LalinError> {
    match code {
        1 => BackScalar::Bool,
        ...
        12 => BackScalar::Ptr,
        13 => BackScalar::Index,
    }.clif_type(ptr_ty)
}
```

`BackScalar::Bool` lowers to `types::I8` in `src/lib.rs`.

Comparisons return `i8` booleans via `bfc`:

```rust
fn bfc(b: &mut FunctionBuilder<'_>, cond: Value) -> Value {
    let one = b.ins().iconst(types::I8, 1);
    let zero = b.ins().iconst(types::I8, 0);
    b.ins().select(cond, one, zero)
}
```

Control tags lower to Cranelift blocks/branches/switch:

```rust
WireTag::Brif => {
  let cond = ctx.builder.ins().icmp_imm(IntCC::NotEqual, cv, 0);
  ctx.builder.ins().brif(cond, tb, &t_args, eb, &e_args);
}
```

Memory lowers with Cranelift `load/store` at offset 0 after address computation:

```rust
WireTag::Load => {
  let ty = st(s[1], ptr_ty)?;
  let fl = mf(s[2]);
  let a = ctx.val(s[3])?;
  let v = ctx.builder.ins().load(ty, fl, a, 0);
}
```

`PtrOffset` is lowered as integer pointer arithmetic:

```rust
let sc = ctx.builder.ins().imul(idx, elem_size);
let total = iadd(sc, const_offset);
let result = ctx.builder.ins().iadd(base, total);
```

### JIT/object flow

Lua:

```lua
-- back_jit.lua
local payload = binary_api.encode(program)
lib.lalin_jit_compile_binary(self._raw, buf, #payload)

-- back_object.lua
local payload = binary_api.encode(program)
lib.lalin_object_compile_binary(buf, #payload, module_name, out)
```

Rust:

```rust
pub fn compile_binary(&self, payload: &[u8]) -> Result<Artifact, LalinError> {
    let isa = host_isa(false)?;
    let mut module = JITModule::new(builder);
    let result = decode::decode_module(payload, &mut module)?;
    module.finalize_definitions()?;
}
```

Object emission:

```rust
pub fn compile_object_binary(payload: &[u8], module_name: &str) -> Result<ObjectArtifact, LalinError> {
    let isa = host_isa(true)?;
    let mut module = ObjectModule::new(builder);
    decode::decode_module(payload, &mut module)?;
    let product = module.finish();
    let bytes = product.emit()?;
}
```

`host_isa` uses `cranelift_native::builder()` only.

### ABI/layout facts

- `type_size_align.lua`: pointers/index are assumed 8/8 in core layout.
- `host_layout_resolve.lua`: host target can be 32/64-bit via `ffi.abi`, but most backend lowering assumes 64-bit today.
- `type_func_abi_plan.lua`: views become `{ptr,index,index}` internally; exported view params get wrappers.
- Aggregates/arrays are passed by pointer for params; aggregate results rejected except view return descriptor path.

## Relationships

Compilation path:

```text
Lalin source
  -> frontend_pipeline.parse_and_lower
  -> open_expand / typecheck / layout_resolve
  -> tree_to_back.module
  -> LalinBack.BackProgram
  -> back_validate.validate
  -> back_command_binary.encode
  -> Rust FFI lalin_jit_compile_binary / lalin_object_compile_binary
  -> src/decode.rs decode_module
  -> Cranelift JITModule/ObjectModule
```

Object/shared path:

```text
BackProgram -> back_object.lua -> compile_object_binary -> .o bytes
.o bytes -> link_command_plan/link_execute -> cc -shared or executable
```

Hosted binary path:

```text
src/main.rs embeds Lua modules
package.preload["lalin.back_jit"] = hosted_jit
hosted_jit encodes binary and calls _host_compile_binary
_host_compile_binary calls lalin::Jit::compile_binary
```

Validation vs wire relationship:

- Validation operates on rich ASDL `BackProgram`.
- Wire strips or flattens parts:
  - drops `CmdTargetModel`
  - drops `CmdAliasFact`
  - drops `CmdSealBlock`, `CmdFinishFunc`, `CmdFinalizeModule`
  - converts memory info to 3-bit memflags
  - converts names/text IDs to per-body numeric IDs
  - declarations/body boundaries become section tables

Tests constrain behavior at both semantic and executable levels:
- validation tests cover missing/duplicate refs, memory facts, shape/target issues.
- JIT tests cover scalar arithmetic, branching, switch, calls, externs, data/stack memory, mem intrinsics, vectors, alias/bool ops, indirect calls.
- object tests cover `.o` emission and linking with C via system `cc`.

## Observations

- **No maintained wasm backend exists.** Searches found wasm only in museum/third-party archived code. Current Rust uses `cranelift_native`, `cranelift-jit`, and `cranelift-object`; `Cargo.toml` has no wasm-specific deps.
- **Flatline spec and implementation have drift.**
  - `BACK_WIRE_FORMAT.md` says function table has `name_idx` plus trailing name table, but Lua encoder/Rust decoder use inline length+name strings in function/extern declarations.
  - Rust `read_header` ignores version value and does not seek to `decl_offset`; it reads declarations at current post-header position.
  - Encoder writes tags as u32 via `w4`; docs/examples visually suggest one-byte tags in places.
- **`tests/test_back_command_binary.lua` currently fails.** I ran `luajit tests/test_back_command_binary.lua`; it fails at line 35 expecting old `"MLBT"` magic bytes, while encoder writes `0x4D4C`.
- **Data encoding appears limited/buggy for multiple data objects.** In `back_command_binary.lua` declaration encoding writes `w4(dbuf, 0)` for every data declaration and initializer rather than each mapped data id.
- **Object FFI free signature mismatch.**
  - Lua declares `lalin_bytes_free(uint8_t* data, size_t len)`.
  - Rust defines `lalin_bytes_free(bytes: *mut lalin_bytes_t)`.
  - Museum version had the two-argument signature.
- **Runtime/libcall assumptions matter.**
  - `src/decode.rs` lowers `Memcpy/Memset/Memcmp` through Cranelift `LibCall::*`.
  - It hardcodes `types::I64` for pointer params in those libcalls instead of `ptr_ty`.
- **Booleans are storage `i8`, not Cranelift `b1`, at the wire/API boundary.** Comparisons produce `i8` 0/1 using select.
- **`BackIndex` and `BackPtr` are pointer-sized in Rust, but Lua lowering/layout frequently assumes 64-bit.** This is significant for wasm32 or 32-bit native.
- **The binary wire is already closer to Cranelift than the ASDL schema.** Many rich semantic facts are discarded because “Cranelift ignores” them. A C backend consuming wire gets less provenance/target information than one consuming validated `BackProgram`.
- **Extern/import/export model today maps directly to C symbols.**
  - `CmdDeclareExtern(symbol)` → Cranelift import named `symbol`.
  - `CmdDeclareFunc(VisibilityExport)` → exported object symbol.
  - JIT externs resolved by `jit:symbol(name, ptr)`.
- **Validated BackProgram has stronger information than Rust decode validates.** Rust decoder assumes sane ordering and types after Lua validation but still catches unknown IDs/tags and Cranelift definition errors.


## Knowledge-builder Output — 2026-06-08 07:44:55

### What Matters Most for This Problem

- **Semantic equivalence with Cranelift**, not just “can emit C”.
- **UB avoidance in generated C**, because C compiler optimization can change behavior even when the emitted code looks equivalent.
- **Input-format fidelity**: validated `BackProgram` retains facts the Flatline wire discards.
- **Pointer/index/layout correctness**, especially for wasm32.
- **CFG/block-param preservation**, since Lalin backend commands are jump-first SSA, not structured AST.
- **Spec stability and validation boundaries**, because the current wire spec, encoder, and decoder have drift.

### Non-Obvious Observations

- **Choosing wire vs `BackProgram` is a semantic decision.**
  The wire is not merely a compact transport format. It drops `CmdTargetModel`, `CmdAliasFact`, provenance, detailed alignment bytes, dereference facts, access IDs, overflow semantics, and float semantics. A C backend consuming wire would have to be much more conservative or risk inventing semantics Cranelift never saw.

- **The wire currently encodes Cranelift-lowering artifacts, not the full Lalin backend contract.**
  `BackAddress` is flattened to pointer arithmetic; memory facts become three memflags; block/function names are renumbered; finish/finalize commands disappear. That makes the wire suitable for today’s Rust decoder but weak as a design-stable C backend API.

- **C signed integer operators are a major semantic trap.**
  Lalin lowering currently uses wrapping integer semantics for ordinary arithmetic. Cranelift `iadd/isub/imul` are bitwise/wrapping unless extra flags are used. In C, signed overflow is UB. Emitting `int32_t a + b` for `BackI32` would not match Cranelift under overflow.

- **Division/remainder are even sharper than add/mul.**
  C signed division by zero and `INT_MIN / -1` are UB. Cranelift has its own trap semantics. The backend contract needs one shared meaning for those cases, or C and Cranelift will diverge exactly on hard edge cases.

- **Shift operations cannot be emitted naively.**
  In C, shifting by a count ≥ bit width, or left-shifting into/sign bits on signed types, can be UB. Cranelift shift ops operate on IR values with machine-like semantics. This affects `CmdShift` and rotate lowering.

- **Pointer arithmetic in Cranelift is integer arithmetic; pointer arithmetic in C is provenance-constrained.**
  The Rust decoder lowers `PtrOffset` as `base + index * elem_size + const_offset` on pointer-sized integers. In C, `p + n` is only defined inside one object, and integer-pointer roundtrips have provenance concerns. Generated C must not accidentally make Lalin pointer math depend on C object-provenance rules.

- **Memory loads/stores cannot safely be lowered as typed pointer dereferences in general.**
  A direct `*(int32_t*)addr` can violate C alignment, strict-aliasing, effective-type, or null-deref rules. Lalin stack/data memory behaves more like byte-addressable storage; Cranelift loads/stores do not impose C effective-type rules.

- **The absence of volatile semantics matters.**
  `BackMemoryInfo` has access mode, motion, trap, dereference, alignment, alias facts, but no explicit volatile operation. C compiler reordering may be stronger/different than Cranelift unless memory side effects are represented in a way C cannot incorrectly optimize.

- **`BackCanMove` is not automatically safe to map to C optimization assumptions.**
  Cranelift receives `can_move` as a memflag. C has no direct equivalent. If the C backend uses richer facts to enable alias or motion assumptions that Cranelift ignores, the two backends can disagree.

- **Alias facts are currently validated but discarded before Cranelift.**
  This creates a hidden alignment rule: if the C backend consumes rich `BackProgram`, exploiting `BackNoAlias` would make C more aggressive than Cranelift. That may be valid only if those facts are treated as semantic promises, not hints.

- **Vector masks require all-bits mask semantics, not boolean-lane semantics.**
  Rust lowers vector select as `(mask & then) | (~mask & else)`. That only works if compare masks are all-zero/all-ones bit patterns. A C vector emulation using `0/1` booleans per lane would produce wrong results.

- **Scalar booleans are `i8` values with a 0/1 invariant.**
  Cranelift comparisons are normalized to `I8` 0 or 1. C `_Bool` has similar logical behavior but ABI/details differ; `uint8_t`-like representation is closer to the backend boundary.

- **Function pointer calls are UB-prone in C.**
  `CmdCallIndirect` carries a signature. In Cranelift the signature is explicit at the call site. In C, calling through a mismatched function pointer type is UB, so preserving exact signature identity is a correctness requirement, not cosmetic type hygiene.

- **The current layout world is effectively 64-bit-first.**
  `type_size_align.lua` hardcodes pointers, callable values, closures, views, and `index` as 8-byte aligned/8-byte sized. wasm32 cannot be a late backend choice after this lowering; it changes view descriptors, array offsets, ABI plans, and memory layout.

- **`BackPtr` and `BackIndex` being both pointer-sized in Cranelift hides ABI distinctions.**
  On native x64 that works conveniently. On C/wasm32, `ptr` maps to address values while `index` maps to integer sizes/counts. Same bit width does not mean same C type or ABI role.

- **Data and stack alignment have a schema/wire mismatch.**
  Tests and schema appear to pass alignment in bytes, e.g. `align = 4`. `BACK_WIRE_FORMAT.md` says `align_log2`, and Rust treats data alignment as `1 << align2`. This can silently over-align today. A C backend must know which contract is authoritative.

- **Data initialization is not robust in the current wire.**
  The encoder writes data id `0` for every declaration/init and stores integer/float literals as fixed-width low/high words. Multiple data objects and exact literal widths are therefore risky through wire. `BackProgram` contains more precise data identity and scalar type.

- **Lua `tonumber` in wire encoding can lose integer precision.**
  `BackLitInt.raw` is a string in the schema, but the encoder converts through Lua numbers. Integer constants above 53 bits can be corrupted before Rust/C ever sees them if the backend consumes the existing wire.

- **wasm32 amplifies every hidden 64-bit assumption.**
  `size_t`, pointer values, view descriptors, `BackIndex`, memcpy lengths, function signatures, and data relocations all become 32-bit. The current Rust `Memcpy/Memset/Memcmp` lowering even hardcodes `I64` pointer parameters, showing the native-64 assumption is already embedded.

- **WASM import/export is not the same as native C symbol linkage.**
  Current externs map directly to C/linker symbols. wasm usually needs import module/name structure, linear-memory conventions, and possibly different runtime shims. The existing symbol model is a lowest-level native object model, not a complete wasm ABI model.

- **Atomics are not portable “just C” operations.**
  C atomics require `_Atomic` objects, suitable alignment, and compatible effective type. wasm atomics require shared-memory/thread features. Current `BackAtomicOrdering` is only seq-cst, which is simple semantically but still target-feature-sensitive.

- **The C backend cannot rely on structured control reconstruction.**
  Backend commands form arbitrary CFG with block parameters. Correctness depends on preserving phi-like block params and jumps, not producing pretty C loops/ifs. Structured C is optional; CFG equivalence is mandatory.

- **The wire spec is not currently the source of truth.**
  `BACK_WIRE_FORMAT.md`, Lua encoder, Rust decoder, and tests disagree: magic bytes, declaration names, header offsets, version handling, and data IDs have drift. Robust architecture should treat current encoder/decoder behavior as empirical compatibility data, not as a stable spec.

- **Keeping Cranelift and C aligned requires a shared semantic subset.**
  Any fact ignored by Cranelift but used by C can create divergence. Any Cranelift behavior relying on IR semantics but emitted in C using UB can also create divergence. The hard part is not emitting C syntax; it is defining which backend facts are semantic obligations versus optimization hints.

### Knowledge Gaps

- Exact intended semantics for integer div/rem traps, overflow, and invalid float-to-int conversions.
- Whether the C backend is expected to consume rich ASDL `BackProgram`, current Flatline wire, or a revised wire.
- Intended wasm target model: plain wasm32, wasm32+SIMD, wasm32+threads/atomics, WASI vs embedded imports.
- Whether alias/no-wrap/fast-math facts are semantic promises or optimization-only evidence.
