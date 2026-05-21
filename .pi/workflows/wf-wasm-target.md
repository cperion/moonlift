# Moonlift WASM Compilation Target 
Explore what it would take to add WASM as a compilation target for Moonlift, using the existing Cranelift backend infrastructure.
**Started**: 2026-05-21 08:01:02
---

## Scout Output — 2026-05-21 08:06:42

## Files Retrieved

1. `src/lib.rs` (lines 1-338) — Rust backend entry: `Jit`, `compile_binary`, `compile_object_binary`, host ISA selection.
2. `src/decode.rs` (lines 1-647) — Flatline binary decoder; maps wire commands to Cranelift IR.
3. `src/ffi.rs` (lines 1-216) — C FFI boundary used by LuaJIT for JIT/object emission.
4. `src/wire_tags.rs` (lines 1-302) — Rust tag enum and fixed slot counts for BackCmd wire ops.
5. `src/main.rs` (lines 1-238) — standalone hosted binary; in-process `_host_compile_binary`.
6. `src/lua_api.rs` (lines 1-164) — native symbol registration for hosted JIT externs.
7. `src/host_arena.rs` (lines 1-283) — native host arena uses raw pointers, refs, generations.
8. `Cargo.toml` (lines 1-22) — Cranelift deps; no `cranelift-wasm` / wasm encoder deps.
9. `Cargo.lock` (queried) — Cranelift 0.131 packages present; no `cranelift-wasm`.
10. `Makefile` (lines 1-67) — builds static `moonlift`, `mom`, shared `libmoonlift`.
11. `BACK_WIRE_FORMAT.md` (lines 1-454) — Flatline v4 spec, tag table, declarations.
12. `lua/moonlift/back_command_binary.lua` (lines 1-751) — Lua encoder from `BackProgram` to binary wire format.
13. `lua/moonlift/schema/back.lua` (lines 1-1000, 500-800) — `MoonBack` schema: scalars, targets, BackCmd variants.
14. `lua/moonlift/back_validate.lua` (lines 1-968) — BackCmd validation, target supported shape checks, memory constraints.
15. `lua/moonlift/tree_to_back.lua` (lines 1-2616) — source tree lowering to BackCmd; functions, externs, memory, views, ABI.
16. `lua/moonlift/tree_control_to_back.lua` (lines 1-415) — jump-first regions/blocks/yield lowered to BackCmd CFG.
17. `lua/moonlift/type_to_back_scalar.lua` (lines 1-86) — source type → `BackScalar`.
18. `lua/moonlift/type_size_align.lua` (lines 1-141) — scalar/pointer/view layout; currently 64-bit pointer/index.
19. `lua/moonlift/type_func_abi_plan.lua` (lines 1-83) — executable ABI; views lower to `(ptr,index,index)`.
20. `lua/moonlift/back_target_model.lua` (lines 1-157) — default native target model; 64-bit, Cranelift JIT, SIMD facts.
21. `lua/moonlift/back_jit.lua` (lines 1-175) — Lua FFI wrapper for Rust JIT; encodes binary wire.
22. `lua/moonlift/back_object.lua` (lines 1-93) — Lua FFI wrapper for Rust object emission.
23. `lua/moonlift/frontend_pipeline.lua` (lines 1-260) — `.mlua` parse/typecheck/lower/validate pipeline.
24. `lua/moonlift/hosted_jit.lua` (lines 1-60) — hosted binary path using `_host_compile_binary`.
25. `lua/moonlift/schema/link.lua` (lines 1-300) — link schema already has `LinkPlatformWasm`, `LinkArchWasm32`, `LinkFormatWasm`.
26. `lua/moonlift/link_target_model.lua` (lines 1-52) — host-only link target model.
27. `lua/moonlift/link_command_plan.lua` (lines 1-116) — `cc`/`ar` command generation for native objects/shared libs.
28. `lua/moonlift/link_execute.lua` (lines 1-60) — executes linker commands.
29. `lua/moonlift/init.lua` (lines 1-170) — public `emit_object` / `emit_shared`.
30. `LANGUAGE_REFERENCE.md` (lines 450-620, 820-1210, 1580-1760, 3090-3170) — scalar/pointer/view types, externs, control, region fragments, view ABI.
31. `tests/test_back_command_binary.lua` (lines 1-48) — binary encoder smoke test; appears stale vs current wire magic.
32. `tests/test_back_object_emit.lua` (lines 1-67) — object emission smoke test.
33. External crate: `cranelift-object-0.130.1/src/backend.rs` (lines 1-240) — `ObjectBuilder` explicitly rejects wasm binary format.
34. External crate: `cranelift-codegen-0.130.1/Cargo.toml` (lines 1-260) and `src/isa/mod.rs` grep — Cranelift codegen ISA support is native ISAs/Pulley, not wasm output.

## Key Code

### Rust backend is shared JIT/Object decoder over `cranelift_module::Module`

```rust
// src/lib.rs
pub fn compile_object_binary(payload: &[u8], module_name: &str) -> Result<ObjectArtifact, MoonliftError> {
    let isa = host_isa(true)?;
    let builder = ObjectBuilder::new(isa, module_name, default_libcall_names())?;
    let mut module = ObjectModule::new(builder);

    decode::decode_module(payload, &mut module)?;
    ...
}
```

```rust
// src/decode.rs
pub fn decode_module<M: Module>(buf: &[u8], module: &mut M) -> Result<DecodeResult, MoonliftError> {
    let hdr = read_header(buf, &mut pos)?;
    let state = read_declarations(buf, &mut pos, decl_end, module)?;
    ...
    decode_body(bb, ptr_ty, &mut bctx, &refs)?;
    module.define_function(cfid, &mut ctx)?;
}
```

### Scalar mapping depends on target pointer type

```rust
// src/lib.rs
pub enum BackScalar {
    Bool, I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Ptr, Index,
}

pub fn clif_type(self, ptr_ty: Type) -> Type {
    match self {
        Self::Bool => types::I8,
        ...
        Self::Ptr | Self::Index => ptr_ty,
    }
}
```

### Current target creation is host-native only

```rust
// src/lib.rs
let isa_builder = cranelift_native::builder()
    .map_err(|e| MoonliftError(format!("host machine is not supported by Cranelift: {e}")))?;
```

### Object backend cannot emit wasm object format

External Cranelift object backend:

```rust
target_lexicon::BinaryFormat::Wasm => {
    return Err(ModuleError::Backend(anyhow!(
        "binary format wasm is unsupported",
    )));
}
```

### BackCmd control is arbitrary CFG + block params

```lua
-- lua/moonlift/tree_control_to_back.lua
cmds[#cmds + 1] = Back.CmdCreateBlock(records[i].block)
cmds[#cmds + 1] = Back.CmdAppendBlockParam(records[i].block, ...)
...
cmds[#cmds + 1] = Back.CmdJump(target.block, args)
```

Rust maps this directly to Cranelift blocks:

```rust
// src/decode.rs
CreateBlock => builder.create_block()
AppendBlockParam => builder.append_block_param(...)
Jump => builder.ins().jump(dest, &args)
Brif => builder.ins().brif(cond, tb, &t_args, eb, &e_args)
SwitchInt => Switch::new().emit(...)
```

### Extern imports are only symbol strings today

```lua
-- tree_to_back.lua
Back.CmdCreateSig(sig, ps, rs)
Back.CmdDeclareExtern(Back.BackExternId(func_node.symbol), func_node.symbol, sig)
```

```rust
// decode.rs
let cfid = module.declare_function(&sym, Linkage::Import, &sig)?;
```

WASM imports usually need at least `(module, name)` import metadata, not just a linker symbol.

### Views lower internally to three scalar ABI params

```lua
-- type_func_abi_plan.lua
if pvm.classof(param.ty) == Ty.TView then
    return Ty.AbiParamView(... data, len, stride)
end
```

```lua
-- tree_to_back.lua
elseif cls == Ty.AbiParamView then
    ps[#ps + 1] = Back.BackPtr
    ps[#ps + 1] = Back.BackIndex
    ps[#ps + 1] = Back.BackIndex
end
```

## Relationships

- `.mlua` source goes through `frontend_pipeline.lua`:
  `parse → open expand/validate → closure_convert → typecheck → layout → tree_to_back → back_validate`.
- `tree_to_back.lua` emits a flat `MoonBack.BackProgram`.
- `back_command_binary.lua` encodes `BackProgram` into Flatline binary bytes.
- Lua JIT path:
  `back_jit.lua` → `moonlift_jit_compile_binary` FFI → `Jit::compile_binary` → `decode_module` into `JITModule`.
- Object path:
  `back_object.lua` → `moonlift_object_compile_binary` FFI → `compile_object_binary` → `decode_module` into `ObjectModule`.
- Link path:
  `emit_shared.lua` / `moon.emit_shared` emits host object then builds `LinkPlan` using `cc` for shared library.
- Control regions/blocks/emit are already erased before backend into flat CFG commands; backend never sees “region” directly.
- Memory operations are pointer-value-based BackCmds: `PtrOffset`, `Load`, `Store`, atomics, static `DataAddr`, stack slots.

## Observations

- There is no real WASM backend now. Only link schema names exist: `LinkPlatformWasm`, `LinkArchWasm32`, `LinkFormatWasm`.
- Cranelift here is used as native machine-code backend. `cranelift-codegen` does not provide a wasm-output ISA; `cranelift-wasm` is not present and would be a wasm-to-CLIF frontend, not CLIF-to-wasm emission.
- `cranelift-object::ObjectBuilder` rejects wasm binary format, so the current object path cannot be pointed at `wasm32` and expected to produce `.wasm`.
- A WASM target likely needs either:
  - a separate WASM emitter from `BackCmd[]` / lowered CFG, or
  - a different toolchain path not relying on Cranelift object output.
- Natural WASM scalar mapping:
  - `i32/u32/bool/i8/i16/u8/u16` → wasm `i32` locals with narrow load/store/sign-extension rules.
  - `i64/u64` → wasm `i64`.
  - `f32/f64` → wasm `f32/f64`.
  - `ptr/index` for wasm32 should likely be `i32`; current Moonlift code hardcodes 64-bit pointer/index in several Lua layout/target files.
- Current memory model assumes native raw addresses. WASM linear memory would require redefining `ptr(T)` as linear-memory offsets, importing/exporting memory, and deciding how host pointers/views cross the boundary.
- Externs need redesign for WASM imports: current `CmdDeclareExtern` carries one symbol string only.
- `Memcpy` and `Memset` are currently no-ops in Rust decoder. This is a major correctness issue for both native and any WASM backend.
- Wire-format docs/tests appear stale/inconsistent:
  - `BACK_WIRE_FORMAT.md` describes `name_idx` + name table, but encoder/decoder inline function/extern names.
  - decoder reads tags as `u32`; docs/examples sometimes imply byte tags.
  - `tests/test_back_command_binary.lua` expects old `MLBT` magic bytes, while encoder writes `0x4D4C`.
- Host arena is native-pointer based and not currently exposed in `src/ffi.rs` despite Lua cdefs for `moonlift_host_*`; mapping it to WASM would need a linear-memory/object-handle story.

## Knowledge-builder Output — 2026-05-21 08:10:59

### What Matters Most for This Problem

- **Semantic target gap**: current backend is not “Cranelift IR → any target”; it is “BackCmd wire → Cranelift native machine code/object”.
- **Target-specific layout**: WASM is not only a final emission format; pointer/index width and ABI layout affect lowering before Rust sees the binary.
- **Memory/address model**: Moonlift currently treats pointers as native raw addresses; WASM treats them as linear-memory offsets, while functions/tables/memory are separate namespaces.
- **Control-flow restructuring**: Moonlift’s flat jump-first CFG maps naturally to Cranelift blocks, but not directly to structured WASM control.
- **Import/export ABI stability**: native symbol imports are not enough for WASM module/name imports, memory ownership, or host interop.
- **Wire-format adequacy**: the binary wire format is Cranelift-shaped and loses information that a WASM backend would likely need.
- **Philosophy fit**: Moonlift’s explicit ASDL/flat backend story is an opportunity, but current host-native defaults and no-op semantics conflict with “fail fast, fail loud”.

---

### Non-Obvious Observations

#### 1. “Add WASM to the Cranelift backend” is a category mismatch

The current Rust path is not using Cranelift as a portable backend abstraction. It depends on:

- `cranelift_native::builder()` for ISA selection.
- `Module::target_config().pointer_type()` for `BackPtr` / `BackIndex`.
- `ObjectModule` for native object emission.
- Cranelift `FuncRef`, `DataId`, `GlobalValue`, `StackSlot`, and native-style function addresses.

That means the existing decoder is already past the point where “WASM target” can be selected. It constructs native CLIF with native object/module assumptions.

Also, `cranelift-wasm` would not help in the obvious way: it is a WASM-to-CLIF frontend, not a CLIF-to-WASM emitter. Retaining Cranelift therefore preserves the native path but does not directly produce WASM.

#### 2. Target model currently validates shapes, but does not actually drive layout

The Lua-side target model has pointer/index facts, but core layout code still hardcodes 64-bit assumptions:

- `type_size_align.lua`: raw pointers and `index` are 8 bytes.
- Views are implicitly 24 bytes: `{ ptr, index, index }`.
- Closures/descriptors assume two 8-byte words.
- `tree_to_back.lua` closure lowering loads `fn` at offset `0` and `ctx` at offset `8`.

For WASM32, this is not a backend-only issue. Struct layout, view ABI, closure descriptors, stack-slot sizes, field offsets, and data initializers all depend on pointer/index width before BackCmd lowering.

A backend that merely maps `BackPtr` to `i32` would still consume a program whose memory layout was planned for 64-bit native.

#### 3. `BackPtr` conflates data pointers, function pointers, extern addresses, and callable values

Native code can treat many address-like things as machine pointers. WASM cannot:

- Linear-memory addresses are `i32`/`i64` offsets.
- Function references live in function/table index spaces.
- Imports are module/name entries, not raw symbols.
- `call_indirect` uses tables and typed function references, not arbitrary numeric addresses.

Moonlift currently maps callable types to `BackPtr`, and `CmdFuncAddr` / `CmdExternAddr` produce `BackPtr` values. That creates a deep mismatch: if `BackPtr` becomes a linear-memory address in WASM, function pointers cannot remain the same scalar without an additional interpretation layer.

This affects closures especially. Closure descriptors currently store `{ fn, ctx }` as pointer-sized words. In WASM, `fn` and `ctx` may belong to different address spaces.

#### 4. WASM imports need semantic metadata, not just a symbol string

`CmdDeclareExtern` carries only:

```lua
extern id
symbol string
sig
```

Native linking can treat that as a linker symbol. WASM imports usually require at least:

- import module name,
- import field/name,
- function/memory/table/global kind,
- ABI expectations around linear memory.

The source-level extern syntax supports `as "symbol"`, but that is still a single string. Encoding `"env.write"` into one symbol would hide ASDL meaning in strings, which conflicts with Moonlift’s explicit-ASDL design principle.

More subtly, native externs like `write(fd, buf: ptr(u8), count: index)` pass process addresses. In WASM the same apparent signature would pass a linear-memory offset. The host import must know to read from the module’s memory. The same scalar signature is therefore not the same ABI.

#### 5. The binary wire format is not target-neutral enough for WASM as-is

The Flatline binary format is described as backend commands, but it is actually “one tag per Cranelift IR operation” in several places.

Important information is dropped or compressed:

- `CmdTargetModel` is skipped entirely.
- `CmdAliasFact` is skipped.
- Pointer provenance and bounds are dropped.
- Rich `BackMemoryInfo` becomes a few Cranelift `MemFlags`.
- `CmdIntBinary`’s scalar type is not encoded in the wire tag; Cranelift infers from operand types.
- `CmdSwitchInt` carries scalar type in schema, but the Rust decoder effectively ignores it.
- Many Back-level distinctions become CLIF conveniences.

For native Cranelift this is acceptable because CLIF’s verifier and type system recover enough. For WASM, especially with i8/i16/bool canonicalization to i32 locals, scalar width is semantically important. A WASM backend consuming only the current binary would need to reconstruct a full value-type environment, and even then some Back-level intent has already been erased.

#### 6. WASM’s lack of i8/i16 locals is more than a load/store detail

The scout noted that i8/u8/i16/u16 would naturally use WASM `i32` locals with narrow loads/stores. The deeper issue is that arithmetic and comparison semantics also change unless explicitly constrained.

Example risks:

- `BackI8` add in Cranelift can be an 8-bit operation.
- WASM `i32.add` wraps at 32 bits, not 8 bits.
- Signed comparisons on i8/i16 require the value to be sign-extended to the right width before comparison.
- Unsigned comparisons require masking.
- Bool values currently map to Cranelift `I8`; WASM branch conditions are `i32`.

So a WASM backend cannot only map storage widths. It needs a consistent invariant for narrow scalar values at every def/use boundary.

#### 7. Control flow is explicit, but not necessarily WASM-structured

Moonlift’s jump-first model is an advantage: all blocks, jumps, and branch args are explicit before backend emission.

But the current BackCmd form is arbitrary CFG:

- `CmdJump` can target any block with args.
- `CmdBrIf` can pass different arg lists to different blocks.
- Blocks have params, Cranelift-style.
- There is no validation that the CFG is reducible or structured.
- There is no validator check for block param arity/type consistency.
- `CmdSwitchInt` has no per-edge args, which already creates a mismatch with block-param destinations.

Cranelift accepts this model naturally. WASM requires structured `block`/`loop`/`if`/`br`/`br_table` nesting. Arbitrary BackCmd CFG may need substantial restructuring. Edge cases include irreducible control flow, multiple-entry loops, switches targeting parameterized blocks, and branches crossing structured scopes.

This creates a philosophical tension: Moonlift’s backend boundary is flat and grep-shaped, while WASM emission may require an internal structured reconstruction pass.

#### 8. Bypassing Cranelift means inheriting verification duties Cranelift currently performs implicitly

The Lua validator mostly checks declaration ordering, duplicate/missing refs, some memory metadata consistency, and target-supported shapes. It does not appear to fully validate:

- value type consistency,
- block param arity/type matching,
- call argument/result signature matching,
- terminator completeness,
- reducibility/structuredness,
- switch destination compatibility,
- stack-slot/address typing.

Today, Cranelift’s builder/verifier absorbs many of these responsibilities. A WASM path that bypasses Cranelift would need equivalent confidence somewhere, or malformed BackCmd could produce invalid or semantically wrong WASM.

This is an architectural risk because it is easy to underestimate: implementing op emission is only part of what Cranelift currently provides.

#### 9. The memory model mismatch is deeper than “linear memory instead of raw pointers”

Current BackCmd memory operations assume:

- raw pointer values,
- stack addresses via `CmdStackAddr`,
- data addresses via `CmdDataAddr`,
- pointer arithmetic via `CmdPtrOffset`,
- loads/stores from address values,
- native host pointers crossing extern boundaries.

WASM separates:

- locals/value stack,
- linear memory,
- function/table references,
- globals,
- imports/exports.

`CmdStackAddr` is particularly revealing. Cranelift stack slots are native frame memory. In WASM, addressable stack slots would need to correspond to linear-memory locations if their address is observable. But WASM locals themselves are not addressable. Aggregate locals, captured descriptors, and any address-taken value therefore require a different storage story than simple locals.

Also, `DataAddr` currently names native data symbols. WASM data segments are offsets into a linear memory, not separately addressable object symbols in the same way.

#### 10. Existing no-op `Memcpy`/`Memset` becomes a blocker, not a footnote

`CmdMemcpy` is emitted for aggregate stores in `tree_to_back.lua`. The Rust decoder currently treats `Memcpy` and `Memset` as no-ops.

For native, this is already a correctness bug. For WASM, it is especially central because linear memory operations are the core representation of aggregate data movement. Any WASM backend would expose this gap immediately.

The presence of no-op memory commands also indicates that BackCmd semantics are not yet fully enforced by the current backend, which raises the bar for adding a second backend without divergence.

#### 11. Atomics are target-feature-sensitive in a way the current model barely captures

Back atomics are explicit and only expose seq-cst ordering, which superficially aligns with WASM’s relatively simple atomic model. But WASM atomics require:

- shared memory,
- atomic feature availability,
- legal alignment/width combinations,
- host/runtime support.

The current target shape support does not distinguish “scalar arithmetic supported” from “atomic operation on this memory supported”. Native Cranelift can reject or lower based on ISA/runtime assumptions; WASM needs this surfaced as target capability.

#### 12. Vector support is both an opportunity and a trap

Current native target facts already cap vector shapes around 128-bit lanes, which resembles WASM SIMD’s `v128`.

That is an opportunity: some vector shapes like i32x4/i64x2 map conceptually well.

But the trap is that WASM SIMD is feature-gated and has its own operation set. Back target facts currently say things like “supports shape” and “supports vector op class”, but WASM needs more precise distinctions:

- scalar vs vector availability,
- lane widths,
- mask representation,
- relaxed vs strict operations,
- availability of specific intrinsics.

A shape that Cranelift-native supports is not automatically a shape a WASM runtime supports.

#### 13. The object/link APIs encode native assumptions

Moonlift’s public API exposes:

- JIT compile/load as callable native functions,
- object emission as `.o`,
- shared library emission through `cc`/`ar`-style native linking.

WASM artifacts do not fit cleanly:

- A `.wasm` module is not a native object file.
- Running it requires a WASM runtime or embedding layer.
- Exported functions are not LuaJIT FFI-callable machine pointers.
- Linking imports/memory/table/data is part of WASM module construction or WASM-specific tooling, not ordinary host `cc`.

The existing `LinkPlatformWasm` / `LinkArchWasm32` / `LinkFormatWasm` schema names are therefore only labels; the surrounding artifact lifecycle remains native.

#### 14. Host arena and hosted-JIT assumptions do not carry over

The host arena uses raw pointers, references, generations, and native object identity. Even if it is not fully exposed through current Rust FFI, the Lua-facing hosted pipeline expects compiled native code to interoperate with LuaJIT memory and C ABI values.

WASM cannot directly dereference LuaJIT memory. Any pointer/view crossing the boundary changes meaning from “host address” to “linear-memory offset” or some handle. That affects not just backend codegen but user expectations around `ptr(T)`, views, externs, and host integration.

#### 15. Back target support currently conflates “operation shape” with “storage ABI”

`BackTargetSupportsShape` is used to reject unsupported scalar/vector shapes. But WASM needs at least three different notions:

- value/local type support,
- memory load/store representation,
- ABI/import/export representation.

For example, i8 is a valid memory storage type but not a WASM local type. Bool may be stored as one byte but passed/branched as i32. Function references may be callable but not linear-memory pointers.

The existing target fact vocabulary is too coarse to express these distinctions cleanly.

#### 16. Moonlift’s design philosophy favors a WASM backend, but exposes current inconsistencies

Philosophically, Moonlift has a strong advantage: the backend consumes explicit, flat, verified commands rather than hidden AST callbacks or stringly side tables.

But WASM stresses places where the current implementation violates that philosophy:

- import metadata hidden in one symbol string,
- target model skipped by binary encoder,
- hardcoded host-native layout,
- memory semantics compressed into Cranelift flags,
- stale wire docs/tests,
- no-op `Memcpy`/`Memset`,
- reliance on Cranelift for unstated validation.

A WASM backend would force these implicit assumptions to become explicit.

---

### Knowledge Gaps

- Exact desired WASM artifact: final `.wasm`, WASM object, component model, or runtime-loaded module.
- Whether WASM support is meant for browser, WASI, embedded runtime, or standalone tooling.
- Desired interop model for `ptr(T)` and `view(T)` across host/WASM boundaries.
- Whether arbitrary Moonlift CFG must be supported, or whether lowering can guarantee reducible/structured CFG for source-produced programs.
- How much of the existing public API should work unchanged versus exposing WASM as a separate artifact path.

## Approach-proposer Output — 2026-05-21 08:12:27

### Approach A: Rust Parallel Backend over Flatline

- **Core idea**: Keep `BackCmd[]` / Flatline as the backend boundary, but add a second Rust decoder that emits final `.wasm` instead of Cranelift IR.

- **Key changes**:
  - Add `src/wasm/` backend using `wasm-encoder` or similar.
  - Add `moon.emit_wasm(...)` Lua API alongside `emit_object`.
  - Extend `BackCmd` / Flatline v5 for:
    - target model preservation,
    - WASM import module/name metadata,
    - memory/table/export declarations.
  - Parameterize Lua layout by target so `ptr/index` become 4 bytes for wasm32.
  - Keep current Cranelift JIT/object backend unchanged for native.

- **Tradeoff**: Optimizes for preserving Moonlift’s flat-command architecture and reusing the existing frontend/lowering path; sacrifices Cranelift reuse for WASM emission because Cranelift cannot emit WASM.

- **Risk**:
  - Rust backend must reimplement verification Cranelift currently provides implicitly.
  - Arbitrary BackCmd CFG must be transformed into structured WASM control.
  - Narrow integer semantics need careful masking/sign-extension.

- **Rough sketch**:
  - Add explicit WASM target model: `wasm32`, later `wasm64`.
  - Fix target-driven layout in Lua: pointer/index size, view ABI, closure descriptor layout.
  - Extend extern declarations from single symbol string to `{ module, name, kind, sig }`.
  - Build a Rust BackCmd interpreter that constructs a typed CFG.
  - Add CFG structuring pass using stackification/Relooper-style algorithm; reject irreducible CFG initially.
  - Emit core `.wasm` module with linear memory, imports, exports, data segments, functions.

---

### Approach B: WASM-Native ASDL Backend Before Flatline

- **Core idea**: Treat WASM as a different semantic target and add an explicit WASM ASDL IR/lowering path in Lua before the Cranelift-shaped Flatline format.

- **Key changes**:
  - Add `lua/moonlift/schema/wasm.lua` with explicit module/function/import/memory/table/control nodes.
  - Add `tree_to_wasm.lua` or `back_to_wasm.lua` that lowers typed Moonlift directly to WASM-shaped IR.
  - Add a WASM binary encoder, either in Lua or Rust, consuming this new ASDL.
  - Keep Flatline/Cranelift as the native backend only.
  - Add target-specific ABI planning for WASM imports/exports, memory ownership, function tables, and closures.

- **Tradeoff**: Optimizes for semantic correctness and Moonlift’s “explicit ASDL meaning” philosophy; sacrifices reuse of the current Rust decoder and creates a larger second backend.

- **Risk**:
  - More invasive compiler architecture change.
  - Needs duplicate lowering/validation logic for calls, memory, control, and data.
  - Source constructs that map naturally to Cranelift may need explicit WASM restrictions or transformations.

- **Rough sketch**:
  - Introduce a WASM target model as a first-class compiler input.
  - Make layout/type ABI target-parametric before backend lowering.
  - Represent WASM imports explicitly instead of hiding meaning in strings.
  - Lower Moonlift regions/control into a structured WASM ASDL, not arbitrary Cranelift-style blocks.
  - Encode final `.wasm` directly from the WASM ASDL.
  - Initially support core WASM module output, not JIT/shared-library parity.

---

### Approach C: External Toolchain / LLVM-WASM Bridge

- **Core idea**: Add a WASM path that lowers Moonlift to C-like or LLVM-like IR and delegates WASM code generation, CFG structuring, linking, and object emission to LLVM/clang/wasm-ld.

- **Key changes**:
  - Add an alternate backend emitter: `BackCmd[] -> LLVM IR` or `Moonlift typed IR -> C/LLVM`.
  - Add `emit_wasm_object` and `emit_wasm` using `clang --target=wasm32-wasi` / `wasm-ld`.
  - Reuse existing link planning concepts, but add WASM-specific linker commands.
  - Add source/ABI annotations for WASI/browser/embedded imports.
  - Still parameterize Lua layout for wasm32/wasm64 before emission.

- **Tradeoff**: Optimizes for fastest path to valid WASM and avoids writing a CFG structurer; sacrifices purity, dependency simplicity, and some “zero escape hatch” philosophy by outsourcing semantics to LLVM.

- **Risk**:
  - Harder to keep Moonlift’s backend semantics grep-shaped and fully explicit.
  - External toolchain versions become part of correctness.
  - C/LLVM lowering may obscure precise BackCmd semantics, especially narrow integers, pointer provenance, atomics, and closures.

- **Rough sketch**:
  - Define supported WASM triples first: likely `wasm32-wasi`.
  - Fix target-driven pointer/index layout in Lua.
  - Emit LLVM IR with explicit function declarations, memory accesses, phis, and branches.
  - Use LLVM’s WASM backend to handle arbitrary CFG and structured-control conversion.
  - Use LLVM/wasm attributes for imports/exports where possible.
  - Produce either `.wasm.o` or final `.wasm` via `wasm-ld`.

---

### Comparison

- Pick **Approach A** if the priority is preserving Moonlift’s current flat backend boundary while building a real native `.wasm` emitter.
- Pick **Approach B** if the priority is philosophical correctness: explicit WASM semantics, explicit ASDL, explicit imports/memory/tables, and no hidden meaning.
- Pick **Approach C** if the priority is getting a usable WASM artifact soon, accepting LLVM/clang as a pragmatic external backend rather than making WASM a fully native Moonlift backend.

## Critique Output — 2026-05-21 08:13:48

Scoring note: for **Coupling**, **Migration cost**, and **Risk**, lower is better. For **Cohesion**, **Philosophy fit**, **Maintainability**, and **Testability**, higher is better.

### Approach A: Rust Parallel Backend over Flatline

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Keeps native Cranelift mostly isolated, but makes Flatline carry both Cranelift-shaped and WASM-shaped semantics. Risk of turning BackCmd into a lowest-common-denominator IR. |
| **Cohesion** | 4/5 | A dedicated `src/wasm/` backend is cohesive, and `emit_wasm` can be separate from `emit_object`. Cohesion weakens where Flatline v5 absorbs imports, memory, tables, exports, and target model details. |
| **Migration cost** | 3/5 | Native path can remain largely intact, but target-parametric layout, pointer/index width, extern metadata, wire format v5, and public API additions touch core Lua lowering and validation. |
| **Philosophy fit** | 4/5 | Preserves Moonlift’s flat backend-command architecture and can make target facts explicit. Less ideal because WASM structuring/verification would happen behind the flat boundary. |
| **Risk** | 4/5 | High semantic risk: arbitrary CFG structuring, narrow integer invariants, BackPtr address-space conflation, linear memory semantics, and replacing Cranelift’s implicit verifier. |
| **Maintainability** | 3/5 | Maintainable if Flatline remains disciplined, but long-term pressure to encode target-specific exceptions into BackCmd/Flatline is significant. |
| **Testability** | 4/5 | Can be validated incrementally with wire v5 tests, target-layout tests, golden WASM output, and staged unsupported-CFG rejection. |

**Verdict**: Yes with caveats  
**Key concern**: Do not let Flatline become an ambiguous hybrid IR; WASM-specific semantics must be explicit enough to avoid reconstructing lost meaning in Rust.

---

### Approach B: WASM-Native ASDL Backend Before Flatline

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 2/5 | Best separation: native Cranelift keeps Flatline, WASM gets its own semantic IR. Avoids forcing WASM memory/table/import concepts into a Cranelift-shaped backend. |
| **Cohesion** | 5/5 | Strongest cohesion. WASM module/function/import/memory/table/control concepts live in a WASM ASDL where they belong. Native and WASM backends each have clear responsibilities. |
| **Migration cost** | 5/5 | Highest upfront cost. Requires target-parametric layout, new schema, lowering, validation, encoder, ABI planning, and likely new control/memory restrictions. |
| **Philosophy fit** | 5/5 | Best match for Moonlift: explicit ASDL meaning, no hidden string metadata, no external semantic escape hatch, and target semantics represented as typed compiler data. |
| **Risk** | 4/5 | Large implementation surface and duplicated validation/lowering logic. However, the risks are architectural and visible rather than hidden behind an ill-fitting IR. |
| **Maintainability** | 5/5 | Best long-term shape. It gives WASM room to evolve independently: imports, memories, tables, component model, WASI/browser differences, wasm32/wasm64, and feature gates. |
| **Testability** | 4/5 | Very testable at phase boundaries: typed WASM ASDL validation, layout tests, control-structuring tests, import/export ABI tests, and binary golden tests. |

**Verdict**: Strong yes  
**Key concern**: The new WASM ASDL must become a real verification boundary, not just a prettier encoder input.

---

### Approach C: External Toolchain / LLVM-WASM Bridge

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Couples Moonlift semantics to LLVM IR, clang/wasm-ld behavior, flags, triples, and toolchain versions. The backend boundary becomes partly external. |
| **Cohesion** | 2/5 | Responsibilities are split awkwardly: Moonlift emits partial semantics, LLVM handles CFG/legalization/codegen, wasm-ld handles artifact semantics. Harder to reason about as one compiler. |
| **Migration cost** | 3/5 | Avoids writing a WASM encoder and CFG structurer, but still requires target layout, ABI annotations, LLVM IR emission, imports/exports, and linker integration. |
| **Philosophy fit** | 2/5 | Weak fit. It hides important semantics in LLVM/toolchain behavior and conflicts with Moonlift’s explicit-ASDL, fail-loud, grep-shaped design. |
| **Risk** | 4/5 | Reduces some codegen risk, but introduces toolchain/version risk and still leaves hard semantic issues: BackPtr, linear memory, function pointers, narrow integers, atomics, closures. |
| **Maintainability** | 2/5 | Likely fastest to demo, but hardest to keep principled. Debugging semantic mismatches across Moonlift → LLVM → wasm-ld would be expensive. |
| **Testability** | 3/5 | End-to-end tests are possible, but failures may depend on external toolchain behavior. Harder to isolate compiler bugs from LLVM/linker assumptions. |

**Verdict**: Significant concerns  
**Key concern**: Avoid outsourcing Moonlift’s semantic contract to LLVM in a way that makes backend behavior non-explicit and version-dependent.

---

### Summary

- **Recommended**: **Approach B — WASM-Native ASDL Backend Before Flatline**. It has the highest migration cost, but best matches Moonlift’s architecture and philosophy. WASM is semantically different enough from native Cranelift that it deserves a first-class target IR.

- **Dark horse**: **Approach A — Rust Parallel Backend over Flatline**. It could work if the project wants to preserve the current flat backend boundary, but only if Flatline v5 becomes explicitly target-aware rather than merely extended with ad hoc WASM fields.

- **Avoid**: **Approach C — External Toolchain / LLVM-WASM Bridge**. It is the most pragmatic short-term path, but weakest architecturally and least aligned with Moonlift’s explicit compiler-data model.

## Documenter Output — 2026-05-21 08:17:18

# WASM Compilation Target — Approach B: WASM-Native ASDL Backend Before Flatline

## Goal

Enable Moonlift to emit WebAssembly as a first-class compilation target by adding a WASM-native ASDL backend before the existing Flatline/Cranelift backend boundary, so WASM semantics—modules, imports, exports, memories, tables, linear-memory pointers, control structure, and target-specific ABI/layout—are represented explicitly in compiler data rather than forced through the current native Cranelift-shaped backend.

## Incentives

Moonlift currently emits native machine code and native object files through Cranelift. That path is host-native by design: it selects the host ISA, uses Cranelift `Module` abstractions, maps `BackPtr`/`BackIndex` to the native pointer type, and emits native object artifacts. WebAssembly is not another Cranelift object format in this codebase: `cranelift-object::ObjectBuilder` explicitly rejects `BinaryFormat::Wasm`, and `cranelift-wasm` is a WASM-to-CLIF frontend, not a CLIF-to-WASM backend.

The motivation for this decision is to avoid treating WASM as a bolt-on output format for a backend whose semantics are native-address, native-symbol, native-object, and native-C-ABI oriented. WASM requires different compiler facts earlier in the pipeline: pointer/index width, view ABI layout, import module/name metadata, memory ownership, function/table address spaces, structured control, and narrow integer invariants. The current Flatline wire format and Rust decoder erase or compress several facts that a WASM backend would need, including target model details, richer memory metadata, pointer provenance, import semantics, and some scalar-width intent.

This matters because Moonlift’s design philosophy relies on explicit ASDL meaning and fail-fast verification boundaries. A WASM target that hides semantics in symbol strings, target-specific side channels, or an external toolchain would conflict with that model. The chosen design makes WASM a real semantic target instead of overloading the existing Cranelift-native backend.

## Current State

Moonlift’s compilation pipeline is:

```text
.mlua source
  → parse / scan_document
  → tree_typecheck
  → layout
  → tree_to_back
  → back_validate
  → back_command_binary
  → Rust Cranelift backend
```

The relevant Lua frontend and backend-lowering files are:

- `lua/moonlift/frontend_pipeline.lua`
  - Runs the source pipeline through parse, typecheck, layout, lowering, and validation.
- `lua/moonlift/tree_to_back.lua`
  - Lowers typed Moonlift source into `MoonBack.BackProgram`.
  - Emits flat `BackCmd[]` commands for functions, externs, memory, data, control flow, stack slots, loads/stores, calls, and ABI values.
- `lua/moonlift/tree_control_to_back.lua`
  - Lowers jump-first regions/blocks/yield into explicit backend CFG commands.
  - Emits `CmdCreateBlock`, `CmdAppendBlockParam`, `CmdJump`, `CmdBrIf`, and related control commands.
- `lua/moonlift/schema/back.lua`
  - Defines the `MoonBack` ASDL schema: scalars, targets, BackCmd variants, memory metadata, signatures, externs, functions, blocks, values, and data declarations.
- `lua/moonlift/back_validate.lua`
  - Validates `BackCmd[]` shape, declaration ordering, duplicate/missing references, memory metadata, and target-supported shapes.
- `lua/moonlift/back_command_binary.lua`
  - Encodes `BackProgram` into the Flatline binary wire format consumed by Rust.
- `lua/moonlift/type_size_align.lua`
  - Computes type size and alignment.
  - Currently hardcodes 64-bit pointer/index assumptions.
- `lua/moonlift/type_func_abi_plan.lua`
  - Lowers function ABI types.
  - Views lower to three scalar ABI values: `(ptr, index, index)`.
- `lua/moonlift/back_target_model.lua`
  - Provides the current native target model.
  - Describes 64-bit pointer/index facts and native Cranelift support.
- `lua/moonlift/back_jit.lua`
  - Lua FFI wrapper for native JIT compilation.
- `lua/moonlift/back_object.lua`
  - Lua FFI wrapper for native object emission.
- `lua/moonlift/init.lua`
  - Public API surface for `emit_object` and `emit_shared`.

The relevant Rust backend files are:

- `src/lib.rs`
  - Defines native JIT/object entry points.
  - Uses `cranelift_native::builder()` to select the host ISA.
  - Uses `ObjectBuilder`/`ObjectModule` for native object emission.
  - Defines `BackScalar` and maps `BackPtr`/`BackIndex` through the Cranelift module pointer type.
- `src/decode.rs`
  - Decodes Flatline binary commands into Cranelift IR.
  - Defines Cranelift blocks, block params, calls, branches, switches, memory ops, stack slots, data symbols, and functions.
- `src/ffi.rs`
  - Exposes native compilation APIs to LuaJIT.
- `src/main.rs`
  - Standalone hosted binary path using the same native backend.
- `src/lua_api.rs`
  - Native symbol registration for hosted JIT externs.
- `src/host_arena.rs`
  - Native host arena implementation based on raw pointers, references, and generations.

The existing native object path is host-oriented:

```rust
pub fn compile_object_binary(
    payload: &[u8],
    module_name: &str,
) -> Result<ObjectArtifact, MoonliftError> {
    let isa = host_isa(true)?;
    let builder = ObjectBuilder::new(isa, module_name, default_libcall_names())?;
    let mut module = ObjectModule::new(builder);

    decode::decode_module(payload, &mut module)?;
    // ...
}
```

The existing decoder is parameterized over `cranelift_module::Module`:

```rust
pub fn decode_module<M: Module>(
    buf: &[u8],
    module: &mut M,
) -> Result<DecodeResult, MoonliftError> {
    let hdr = read_header(buf, &mut pos)?;
    let state = read_declarations(buf, &mut pos, decl_end, module)?;
    // ...
    decode_body(bb, ptr_ty, &mut bctx, &refs)?;
    module.define_function(cfid, &mut ctx)?;
}
```

This makes the backend reusable between native JIT and native object emission, but not between native and WASM emission. The abstraction is “Flatline BackCmd wire format into Cranelift-native module,” not “target-independent compiler IR into arbitrary artifact.”

Several current assumptions conflict with WASM:

- `cranelift_native::builder()` selects the host machine, not `wasm32`.
- `ObjectBuilder` rejects WASM object output.
- `BackPtr` and `BackIndex` map to the Cranelift pointer type.
- Lua layout currently assumes 64-bit pointers and indexes.
- Closures/descriptors assume pointer-sized native words.
- Views are represented as `(ptr, index, index)`, currently 24 bytes under 64-bit layout.
- `CmdFuncAddr` and `CmdExternAddr` produce `BackPtr` values, conflating data pointers, function pointers, extern addresses, and callable values.
- Native extern declarations carry one symbol string, while WASM imports require at least module/name/kind metadata.
- Memory operations assume native raw addresses; WASM uses linear-memory offsets.
- `CmdStackAddr` maps naturally to native frame memory, but WASM locals are not addressable.
- `CmdDataAddr` names native data symbols, while WASM data segments live at offsets in linear memory.
- `CmdMemcpy` and `CmdMemset` are currently no-ops in the Rust decoder, which is already a native correctness issue and would be central in WASM.
- The Lua validator does not fully replace Cranelift verification for value typing, block param arity/type matching, call signature matching, terminator completeness, structuredness, or stack/address typing.
- Flatline v4 is Cranelift-shaped and drops or compresses facts that are meaningful for WASM.

There are WASM labels in link schema files:

- `lua/moonlift/schema/link.lua`
  - Contains `LinkPlatformWasm`, `LinkArchWasm32`, and `LinkFormatWasm`.
- `lua/moonlift/link_target_model.lua`
  - Currently host-only in practice.
- `lua/moonlift/link_command_plan.lua`
  - Generates native `cc`/`ar` style link commands.

These schema names do not constitute a WASM backend. The artifact lifecycle remains native: `.o` files, shared libraries, native linker commands, LuaJIT FFI-callable function pointers, and host process addresses.

## Chosen Target

### Approach

The chosen design is **Approach B: WASM-Native ASDL Backend Before Flatline**.

WASM will be treated as a separate semantic compilation target with its own explicit ASDL IR and lowering path before the existing Flatline format. Flatline remains the native Cranelift backend boundary. WASM does not pass through the Cranelift-native decoder and does not rely on Cranelift object emission.

This approach was selected because it has the best architectural fit with Moonlift’s core principles:

- explicit ASDL meaning;
- typed compiler data instead of stringly metadata;
- target semantics represented before backend emission;
- clear phase boundaries;
- no hidden dependence on Cranelift or LLVM behavior for WASM semantics;
- long-term maintainability for WASM-specific concepts such as imports, memories, tables, WASI/browser/embedded environments, wasm32/wasm64, feature gates, and component-model evolution.

The critique rated Approach B strongest in cohesion, philosophy fit, and maintainability, despite having the highest migration cost.

| Dimension | Score | Meaning |
|---|---:|---|
| Coupling | 2/5 | Best separation between native Cranelift and WASM semantics. |
| Cohesion | 5/5 | WASM concepts live in a WASM-specific IR. |
| Migration cost | 5/5 | Highest upfront implementation cost. |
| Philosophy fit | 5/5 | Best match for explicit ASDL and fail-loud boundaries. |
| Risk | 4/5 | Large implementation surface and validation burden. |
| Maintainability | 5/5 | Best long-term architecture. |
| Testability | 4/5 | Strong phase-boundary testing opportunities. |

### Architecture

The native backend remains:

```text
typed Moonlift
  → tree_to_back.lua
  → MoonBack.BackProgram
  → back_validate.lua
  → back_command_binary.lua / Flatline
  → src/decode.rs
  → Cranelift JIT/Object
```

The new WASM backend path is:

```text
typed Moonlift
  → target-parametric layout / ABI planning
  → WASM lowering
  → MoonWasm ASDL
  → WASM validation
  → WASM binary encoding
  → .wasm module
```

The selected architecture introduces a WASM-specific schema and lowering path, rather than extending Flatline into a hybrid native/WASM IR.

#### New WASM ASDL schema

A new schema module is introduced conceptually as:

```text
lua/moonlift/schema/wasm.lua
```

This schema represents WASM concepts directly. Its node families cover:

- module declarations;
- functions;
- function types/signatures;
- imports;
- exports;
- memories;
- tables;
- globals where needed;
- data segments;
- function bodies;
- structured control;
- locals;
- value types;
- memory operations;
- calls and indirect calls where supported;
- target features and WASM-specific ABI facts.

The schema is the semantic boundary for WASM output. It is not merely a prettier binary encoder input. It must carry enough typed meaning for validation and emission without reconstructing lost facts from Cranelift-shaped commands.

#### WASM lowering path

A new lowering module is introduced conceptually as one of:

```text
lua/moonlift/tree_to_wasm.lua
```

or, where appropriate after typed backend lowering,

```text
lua/moonlift/back_to_wasm.lua
```

The selected approach is not committed to reusing Flatline. The important decision is that WASM lowering happens before the Cranelift-shaped Flatline wire format and produces WASM-shaped ASDL.

The lowering path owns WASM-specific transformations and restrictions, including:

- target-specific pointer/index width;
- WASM import/export ABI planning;
- memory/table ownership model;
- function-reference representation;
- closure representation under WASM address-space constraints;
- conversion from Moonlift jump-first control into structured WASM control;
- representation of linear-memory loads, stores, data segments, and addressable storage.

#### Target-parametric layout and ABI

WASM support requires target facts to affect layout before backend emission.

Current native assumptions include:

- `ptr` is 8 bytes;
- `index` is 8 bytes;
- `view(T)` ABI lowers to `{ ptr, index, index }`, currently 24 bytes;
- closure descriptors use two pointer-sized words;
- descriptor field offsets assume 64-bit words.

Under the chosen design, layout and ABI planning become target-parametric before lowering into either native BackCmd or WASM ASDL. For `wasm32`, `ptr` and `index` are represented as 32-bit linear-memory offsets/indices where applicable. This affects:

- struct layout;
- field offsets;
- stack slot sizes;
- data initializers;
- view ABI;
- closure descriptors;
- pointer arithmetic;
- extern/import signatures;
- exported function signatures.

This is part of the architecture because mapping `BackPtr` to WASM `i32` at the final backend stage would be too late: the memory layout would already have been planned using native 64-bit assumptions.

#### WASM imports and exports

The current native extern declaration is:

```text
extern id + symbol string + signature
```

That is sufficient for native symbol linking but insufficient for WASM.

The WASM ASDL represents imports explicitly as typed compiler data, including at least:

- import module name;
- import field/name;
- import kind;
- function signature or relevant memory/table/global type;
- ABI expectations.

This avoids hiding WASM import semantics inside strings such as `"env.write"` and preserves Moonlift’s explicit-ASDL rule.

Exports are likewise represented explicitly in the WASM ASDL rather than inferred from native object/linker conventions.

#### Memory model

The native backend treats pointers as process addresses and memory operations as native loads/stores. WASM uses linear memory.

The chosen WASM backend represents:

- linear memory declarations;
- memory imports/exports where applicable;
- data segments as linear-memory initialization;
- pointer-like values as linear-memory offsets where applicable;
- loads and stores against linear memory;
- aggregate movement through explicit memory operations;
- address-taken storage in linear memory rather than native stack addresses.

This separates WASM data pointers from function references and table entries. The current `BackPtr` conflation is not carried forward as the WASM semantic model.

#### Control model

Moonlift source uses jump-first control. The native backend lowers this into arbitrary Cranelift CFG blocks:

- `CmdCreateBlock`
- `CmdAppendBlockParam`
- `CmdJump`
- `CmdBrIf`
- `CmdSwitchInt`

Cranelift accepts this naturally. WASM requires structured control using constructs such as blocks, loops, conditionals, and branches.

The chosen design gives the WASM backend its own structured control representation in the WASM ASDL. The control lowering/validation boundary is part of the WASM path, not hidden inside the Flatline decoder. Source-produced Moonlift control must be represented in the WASM schema in a form suitable for WASM emission, with unsupported or invalid shapes rejected by the WASM validation boundary.

#### Binary emission

The final encoder consumes the WASM ASDL and emits a core `.wasm` module. The encoder may be implemented in Lua or Rust; the architectural decision is that it consumes the explicit WASM ASDL, not Flatline v4 and not Cranelift IR.

The initial artifact target is a WASM module, not native JIT parity, native `.o` parity, or shared-library parity.

### Tradeoffs Acknowledged

The chosen approach deliberately sacrifices short-term implementation speed and reuse of the current Rust decoder.

It requires:

- a new WASM schema;
- a new lowering path;
- target-parametric layout and ABI;
- explicit WASM import/export modeling;
- WASM validation;
- a WASM binary encoder;
- control lowering into WASM-shaped structure;
- separate tests for WASM ASDL, validation, and binary output.

It may duplicate some logic currently handled by `tree_to_back.lua`, `back_validate.lua`, and Cranelift verification. This is accepted because WASM semantics are different enough that forcing them through the existing Cranelift-shaped Flatline boundary would create a weaker long-term architecture.

The approach also accepts that native and WASM backends become separate backend families:

```text
Native backend: typed Moonlift → BackCmd/Flatline → Cranelift
WASM backend:   typed Moonlift → MoonWasm ASDL → WASM encoder
```

This separation is intentional. It prevents `BackCmd` and Flatline from becoming a lowest-common-denominator IR carrying both native Cranelift and WASM-specific meanings.

### Risks Acknowledged

The critique identified the following risks for Approach B:

- **Highest migration cost**: it requires new schema, lowering, validation, encoder, target layout work, and ABI planning.
- **Large implementation surface**: calls, memory, control, data, imports, exports, closures, function references, and target features all need explicit handling.
- **Validation burden**: the WASM ASDL must become a real verification boundary, not only an encoder input.
- **Duplicate logic risk**: some validation and lowering responsibilities currently implicit in Cranelift must be represented explicitly for WASM.
- **Control complexity**: Moonlift’s explicit CFG must be lowered or constrained into WASM-compatible structured control.
- **Narrow integer semantics**: WASM lacks i8/i16 locals, so width, masking, sign extension, bool representation, comparisons, and arithmetic invariants must be preserved.
- **Memory model mismatch**: native raw pointers, stack addresses, and data symbols do not directly translate to WASM linear memory.
- **Function pointer/address-space mismatch**: WASM separates linear-memory offsets from function/table references.
- **Extern ABI mismatch**: native symbol imports and WASM module/name imports have different semantics.
- **Feature-gated operations**: atomics and SIMD require WASM-specific target capability modeling.

These risks are accepted because they are visible architectural responsibilities in the chosen design. The rejected alternatives either hide these risks behind an ill-fitting Flatline extension or outsource them to an external toolchain.

## Rejected Alternatives

### Approach A — Rust Parallel Backend over Flatline

Approach A would keep `BackCmd[]` and Flatline as the backend boundary, then add a second Rust decoder that emits final `.wasm` instead of Cranelift IR.

It would add:

- `src/wasm/`;
- `moon.emit_wasm(...)`;
- Flatline v5 extensions for target model, WASM imports, memories, tables, exports;
- target-parametric Lua layout;
- a Rust BackCmd interpreter and CFG structuring pass;
- direct `.wasm` emission using a crate such as `wasm-encoder`.

This approach was not chosen.

It preserves more of the existing flat backend boundary and keeps native Cranelift mostly isolated, but it risks turning Flatline into a hybrid IR that carries both Cranelift-shaped and WASM-shaped semantics. The critique rated it “yes with caveats,” with the key concern that Flatline must not become ambiguous or require the Rust WASM backend to reconstruct meaning already erased by the Cranelift-oriented wire format.

Approach A was rejected in favor of Approach B because WASM semantics deserve a first-class target IR rather than an extension of a native Cranelift command stream.

### Approach C — External Toolchain / LLVM-WASM Bridge

Approach C would lower Moonlift to C-like or LLVM-like IR and use `clang --target=wasm32-wasi`, LLVM’s WASM backend, and/or `wasm-ld` to produce WASM artifacts.

It would add:

- a C/LLVM-like backend emitter;
- WASM linker command planning;
- external toolchain integration;
- LLVM/WASI/browser import/export annotations;
- target-parametric layout before emission.

This approach was not chosen.

It likely offers the fastest route to a demonstrable WASM artifact and avoids writing a WASM encoder and CFG structurer. However, it couples Moonlift semantics to LLVM IR, clang/wasm-ld behavior, flags, triples, and toolchain versions. It also weakens Moonlift’s explicit-ASDL architecture by outsourcing important semantic decisions to an external backend.

The critique rated it weakest in philosophy fit, cohesion, and maintainability. It was rejected because it hides too much of Moonlift’s semantic contract in toolchain behavior and makes backend correctness version-dependent.

## Decision Summary

Moonlift will pursue WASM support through a **WASM-native ASDL backend before Flatline**.

Flatline remains the native Cranelift backend boundary. WASM gets its own explicit schema, lowering path, validation boundary, target-parametric ABI/layout handling, and binary emission path. This choice has the highest upfront cost, but best preserves Moonlift’s architecture: meaningful compiler state remains typed, explicit, inspectable, and target-correct before artifact emission.
