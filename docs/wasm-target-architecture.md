
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
