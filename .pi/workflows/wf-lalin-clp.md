# Lalin Copy-Link-Patch compiler tier exploration 
Explore feasibility and architecture options for a copy-and-patch / copy-link-patch compiler tier in Lalin, grounded in cp.txt and experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md.
**Workflow ID**: wf-lalin-clp
**Started**: 2026-05-30 19:07:35
---

## Scout Output — 2026-06-06 09:09:19

## Files Retrieved

1. `cp.txt` (lines 1-1781) — Copy-and-Patch paper: stencil mechanics, CPS composition, register/pass-through scheme, MetaVar object extraction, runtime copy/patch, evaluation.
2. `experiments/lua_interpreter_vm/SPONJIT_LALIN_COPY_PATCH_DESIGN.md` (lines 1-751) — Current SpongeJIT copy/patch executor design; actual expected data/control tree.
3. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-42) — Current SpongeJIT pipeline and retired assumptions.
4. `experiments/lua_interpreter_vm/README.md` (lines 1-89) — Directory-level current direction and guardrails.
5. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` (lines 1-80, 1580-2114) — ASDL schema for LuaSrc/LuaExec/LalinCFG/Stencil.
6. `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_*.lua`:
   - `stencil_key.lua` (1-134)
   - `stencil_validate.lua` (1-332)
   - `stencil_materialize.lua` (1-433)
   - `stencil_bank.lua` (1-217)
   - `stencil_bundle.lua` (1-212)
   - `stencil_manifest.lua` (1-460)
   - `stencil_materialization_plan.lua` (1-105)
   - `stencil_object_extract.lua` (1-166)
   - `stencil_foundry.lua` (1-33)
7. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_foundry.lua` (1-580) — Maintained offline foundry: opcode windows + facts → LalinCFG + contract + Stencil.VariantKey representatives.
8. `experiments/lua_interpreter_vm/spongejit/foundry.lua` (1-180) and `build_lua_compile_foundry.sh` (1-180) — Maintained foundry entry points.
9. `experiments/lua_interpreter_vm/spongejit/Makefile` (1-67) — Current test/build gates and explicit retired old path failures.
10. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_stencil.lua` (1-420) — Concrete tests for stencil ASDL validation, materialization, bank lookup, bundles.
11. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_foundry.lua` (1-83) — Foundry representative/dedupe tests.
12. `experiments/lua_interpreter_vm/src/products.lua` (1-140) — VM data layouts: `Value`, `Table`, `Frame`, `LuaThread`, etc.
13. `experiments/lua_interpreter_vm/src/regions_value.lua` (1-286), `regions_table.lua` (1-674), `vm_loop.lua` (1-180), `api.lua` (1-174) — Existing Lalin-native VM semantic/fact-observation substrate.
14. `experiments/lua_interpreter_vm/src/jit/stencil_codegen.lua` (1-70) — Early bootstrap stub for StateOp → Lalin stencil source.
15. `experiments/lua_interpreter_vm/tools/sponjit_shadow/stencil_model.lua` (1-330), `tools/sponjit_shadow/stencils/*` — Retired/old shadow copy-and-patch prototype.
16. `lua/lalin/back_jit.lua` (1-217), `hosted_jit.lua` (1-59), `back_object.lua` (1-88), `back_command_binary.lua` (1-840), `BACK_WIRE_FORMAT.md` (1-456) — Current Lalin backend FFI/wire path.
17. `src/lib.rs` (1-340), `src/decode.rs` (1-712), `src/ffi.rs` (1-217), `src/main.rs` (1-225), `Cargo.toml` (1-21) — Rust Cranelift backend/JIT/object/FFI/hosted binary.
18. `lua/lalin/init.lua` (1-198), `frontend_pipeline.lua` (1-220), `tree_to_back.lua` (1-2730 sampled), `back_validate.lua` (1-970 sampled), `schema/back.lua` (520-950, 1385-1388) — Frontend-to-flat-backend pipeline and `BackProgram` schema.
19. `lua/lalin/link_*.lua`, `emit_object.lua`, `emit_shared.lua`, `tests/test_back_object_emit.lua` — Current AOT object/shared emission and linking path.

## Key Code

### Copy-and-Patch paper mechanics

`cp.txt` defines the central stencil structure and runtime copy/patch operation:

```c
struct PatchRecord {
 uint32_t binaryOffset;
 uint32_t ord; // ordinal of the missing value
};
struct Stencil {
 std::vector<uint8_t> binary;
 std::vector<uint32_t> pc32Patches;
 std::vector<PatchRecord> symbol32Patches;
 std::vector<PatchRecord> symbol64Patches;
};
// patches[i] is desired value for missing value ordinal i
void Stencil::copyPatch(uintptr_t dst, uint64_t* patches) {
 memcpy((void*)dst, binary.data(), binary.size());
 for (auto binaryOffset : pc32Patches)
 *(uint32_t*)(dst + binaryOffset) -= dst;
 for (auto p : symbol32Patches)
 *(uint32_t*)(dst + p.binaryOffset) += patches[p.ord];
 for (auto p : symbol64Patches)
 *(uint64_t*)(dst + p.binaryOffset) += patches[p.ord];
}
```

Important paper facts:
- Stencils are precompiled binary code fragments with holes for immediates, stack offsets, branches/calls.
- Runtime compilation does: select stencil variants → copy bytes → patch holes.
- CPS/tail-call style lets stencil continuations become jumps.
- GHC calling convention is used as a register-allocation protocol; pass-through parameters preserve registers across stencils.
- Runtime algorithm:
  1. postorder traversal for lightweight register/stack planning,
  2. second traversal to select stencil variants/supernodes and build CPS graph,
  3. depth-first copy into contiguous memory,
  4. patch literals, offsets, branch/call targets,
  5. elide jumps when copied continuation is adjacent.
- MetaVar creates stencils at install/build time by compiling C++ template generators, then parses object-file relocation records to identify hole offsets/ordinals.
- Paper numbers: Wasm library 1666 stencils / 35 kB; high-level compiler 98,831 stencils / 17.5 MB; runtime machine-code generation >300 MB/s on large Wasm modules.

### Current SpongeJIT copy/patch design

`experiments/lua_interpreter_vm/SPONJIT_LALIN_COPY_PATCH_DESIGN.md` defines current intended flow:

```text
Runtime VM state
  -> FactCollector regions
  -> FactSignature + PatchSet
  -> TileKey
  -> Bank lookup
  -> StencilTemplate
  -> copy / patch / relocate / protect
  -> MaterializedCode
```

Key data types include:

```lalin
struct TileKey
    window: WindowId
    facts: FactSetId
    contract: ContractId
    cfg: CfgShapeId
    target: TargetId
end

struct StencilTemplate
    id: TemplateId
    kind: TemplateKind
    key: TileKey
    code: CodeBlob
    holes: view(PatchHole)
    relocs: view(Reloc)
    symbols: view(Symbol)
    frame_bytes: u32
    entry_offset: u32
end

struct PatchHole
    kind: PatchKind
    code_offset: u32
    width_bytes: u8
    align_log2: u8
    source_index: u32
end
```

Control protocols are expressed as regions:

```lalin
region collect_tile_facts(...;
    collected: cont(signature: FactSignature, patches: PatchSet),
    capacity_exceeded: cont(required: index),
    invalid_window: cont())

region lookup_template(bank: ptr(BankImage), key: TileKey;
    found: cont(template: ptr(StencilTemplate)),
    not_found: cont())

region materialize_template(...;
    materialized: cont(code: MaterializedCode),
    alloc_failed: cont(code: i32),
    copy_failed: cont(code: i32),
    patch_failed: cont(hole_index: index),
    reloc_failed: cont(reloc_index: index),
    protect_failed: cont(code: i32),
    publish_failed: cont(code: i32))
```

Explicit guardrails:
- Runtime materializer is semantics-blind.
- Facts specialize already-generated semantic variants; facts are not semantics.
- No opcode dispatch in selector/materializer/patcher/stencil metadata.
- No `out_tag` accepted execution path.
- No interpreter/helper stencils.

### Current Stencil ASDL

`experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` has a maintained `Stencil` module:

```asdl
StencilTemplate = (Stencil.Name name,
                   Stencil.StencilKind kind,
                   Stencil.VariantKey variant,
                   Stencil.CodeBlobRef code,
                   Stencil.PatchHole* holes,
                   Stencil.Reloc* relocs,
                   Stencil.Symbol* local_symbols,
                   Stencil.MaterializationPlan plan) unique

VariantKey = (Stencil.StencilKind stencil_kind,
              LalinCFG.KernelKind kernel_kind,
              LuaContract.Contract contract,
              Stencil.Placement placement,
              Stencil.TargetABI target_abi,
              Stencil.FeatureSet features) unique

PatchHole = (Stencil.Name id,
             Stencil.PatchKind kind,
             number offset,
             number width_bytes,
             Stencil.PatchEncoding encoding,
             Stencil.PatchSource source) unique

MaterializationPlan = (Stencil.PatchSite* patch_sites,
                       Stencil.LinkStep* link_steps,
                       Stencil.EntryPoint entry) unique
```

Patch kinds already include backend/materialization concepts plus FFI/GC patch sites:

```asdl
PatchKind = ImmediatePatch
          | StackOffsetPatch
          | ConstAddressPatch
          | BranchTargetPatch
          | CallTargetPatch
          | SymbolAddressPatch
          | FrameLayoutPatch
          | RegisterPatch
          | VTablePatch
          | FFISymbolAddr64Patch
          | ...
          | GCStatePtrPatch
          | GCAllocatorFnPatch
          | GCBarrierEntryAddrPatch
          | GCEpochExpectedPatch
```

### Current Lua stencil materializer

`stencil_materialize.lua` is a pure Lua, non-executable-memory materializer:

```lua
function M.materialize(template, code_blobs, opts)
  opts = opts or {}
  local errors = {}
  local ok, verr = Validate.validate_template(template, opts.validate_opts or {})
  if not ok then for _, e in ipairs(verr) do add(errors, e) end; return nil, errors end

  local bytes = checked_code_bytes(template.code, code_blobs, errors)
  if #errors > 0 then return nil, errors end

  local out = bytes_to_array(bytes)
  local offsets, addresses = symbol_maps(template, opts)
  local records = {}
  apply_patches(out, template, offsets, addresses, opts, errors, records)
  apply_relocs(out, template, offsets, addresses, opts, errors, records)
  ...
  return S.MaterializedImage(template.name, template.code, array_to_bytes(out),
                             template.plan.entry.symbol, entry_offset, records)
end
```

Supported patch encodings:

```lua
ENCODING.U8 = { width = 1, signed = false }
ENCODING.U16 = { width = 2, signed = false }
ENCODING.U32 = { width = 4, signed = false }
ENCODING.U64 = { width = 8, signed = false }
ENCODING.I32 = { width = 4, signed = true }
ENCODING.I64 = { width = 8, signed = true }
ENCODING.PcRel32 = { width = 4, signed = true }
ENCODING.PcRel64 = { width = 8, signed = true }
ENCODING.Abs64 = { width = 8, signed = false }
```

Reloc support currently implemented:
- `AbsAddr` → write 8-byte absolute address.
- `PcRel` → write signed 32-bit PC-relative value.
- Other `RelocKind`s report unsupported.

### Current bank/bundle layer

`stencil_bank.lua`:
- validates `StencilModule`,
- builds indexes by structural `Stencil.VariantKey`,
- selects `StencilTemplate`,
- delegates materialization.

```lua
function M.lookup(index, variant_or_key)
  ...
  local entry = index.entries_by_variant_key[vk]
  if not entry then return nil, { "no template for variant key" } end
  local template = index.templates_by_name[name_text(entry.template_name)]
  ...
  return template, {}
end
```

`stencil_bundle.lua`:
- materializes selected/all templates in deterministic order,
- creates `Stencil.MaterializedBundle`,
- emits publish metadata with placeholder entry addresses.
- Does **not** allocate executable memory or call OS APIs.

### Current foundry path

`lua_compile_foundry.lua` compiles source opcode windows and fact bundles through LuaCompile into `LalinCFG.Kernel`, then computes representative identity:

```lua
local kernel = lalin_result.product.kernel
local contract = kernel.contract
local ckey = ContractKey.key(contract)
local cfg_key = CFGKey.key(kernel)
local variant = StencilFoundry.variant_for_kernel(kernel, contract, opts)
local stencil_variant_key = StencilKey.variant_key(variant)
local rep_key = table.concat({
  cfg_key,
  "-- Kernel LuaContract --",
  ckey,
  "-- Stencil.VariantKey --",
  stencil_variant_key,
}, "\n")
local ok, source_or_err = pcall(LalinEmit.emit, kernel, { name = opts.kernel_name or "lua_compile_foundry_kernel" })
```

`build_lua_compile_foundry.sh` describes current output:

```text
LuaCompile grammar/window plan -> parallel LuaCompile workers
-> LalinCFG + kernel LuaContract + Stencil.VariantKey representative dedupe
-> LalinCFG/Lalin source artifacts; binary StencilTemplate banks are separate object-extraction artifacts.
```

### Current Lalin backend/AOT path

Lua side:
- `frontend_pipeline.parse_and_lower` parses/typechecks/lowers to `LalinBack.BackProgram`.
- `back_command_binary.lua` encodes `BackProgram` to Flatline v4 binary wire format.
- `back_jit.lua` sends binary to Rust JIT.
- `back_object.lua` sends binary to Rust object emitter.
- `init.lua` exposes `lalin.emit_object` and `lalin.emit_shared`.

`back_object.lua`:

```lua
local payload = binary_api.encode(program)
local buf = ffi.new("uint8_t[?]", #payload)
ffi.copy(buf, payload, #payload)
local out = ffi.new("lalin_bytes_t[1]")
check_ok(
    lib.lalin_object_compile_binary(buf, #payload, cstring(compile_opts.module_name or "lalin_object"), out),
    "lalin.back_object compile_binary"
)
local bytes = ffi.string(out[0].data, tonumber(out[0].len))
```

Rust side:
`src/lib.rs`:

```rust
pub fn compile_object_binary(payload: &[u8], module_name: &str) -> Result<ObjectArtifact, LalinError> {
    let isa = host_isa(true)?;
    let builder = ObjectBuilder::new(isa, module_name, default_libcall_names())?;
    let mut module = ObjectModule::new(builder);

    decode::decode_module(payload, &mut module)?;

    let product = module.finish();
    let bytes = product.emit()?;
    Ok(ObjectArtifact { bytes })
}
```

JIT path:

```rust
pub fn compile_binary(&self, payload: &[u8]) -> Result<Artifact, LalinError> {
    let isa = host_isa(false)?;
    let mut builder = JITBuilder::with_isa(isa, default_libcall_names());
    ...
    let mut module = JITModule::new(builder);
    let result = decode::decode_module(payload, &mut module)?;
    module.finalize_definitions()?;
    ...
}
```

`decode.rs` is the shared binary-wire decoder for both JIT and object paths. It declares functions/data/externs and lowers flat tags to Cranelift IR, then calls `module.define_function`.

## Relationships

### Paper mechanics vs Lalin/SpongeJIT state

- Paper MetaVar:
  - build-time C++ stencil generators,
  - object-file relocation extraction,
  - runtime `memcpy + scalar patch`.
- Current SpongeJIT:
  - ASDL has typed `StencilTemplate`, `PatchHole`, `Reloc`, `MaterializationPlan`.
  - Lua materializer can copy/patch/reloc **strings of bytes** into `Stencil.MaterializedImage`.
  - Runtime executable allocation/protection/publish is design-only in `SPONJIT_LALIN_COPY_PATCH_DESIGN.md`; not implemented in the current Lua materializer.

### LalinCFG/foundry to stencil identity

Current maintained flow:

```text
opcode windows + fact bundles
→ LuaFact.Evidence
→ LuaCompile.Unit
→ LuaExec / LuaSem / LuaContract
→ LalinCFG.Kernel
→ emitted Lalin source
→ Stencil.VariantKey representative
```

Binary stencil banks are explicitly marked as separate future object-extraction artifacts.

### Lalin AOT/JIT backend

Current production compiler path:

```text
.mlua source
→ parse/typecheck/open/closure/layout
→ tree_to_back
→ LalinBack.BackProgram[]
→ Flatline v4 binary wire
→ Rust decode_module
→ Cranelift JITModule or ObjectModule
→ executable pointer or .o bytes
→ optional linker invocation for shared library
```

### Existing integration seams visible in code

First-order seams, not proposals:
- `LalinCFG.emit` already produces Lalin source for foundry kernels.
- `lalin.emit_object` / `back_object.lua` can compile Lalin source through Cranelift to relocatable object bytes.
- `stencil_object_extract.lua` already accepts explicit object metadata and converts it into `StencilTemplate`, but it does not invoke Cranelift or parse object bytes itself.
- `stencil_materialize.lua` already consumes `CodeBlobRef + concrete bytes + PatchHole/Reloc metadata`.
- `src/lib.rs::compile_object_binary` currently returns only full object bytes; it does not expose per-function `.text` bytes, symbol offsets, reloc records, or patch-hole metadata.
- `experiments/lua_interpreter_vm/src/jit/elf_parser.lua` can mine ELF function bytes/relocations using `nm`/`objdump`, but it is under the experiment old-ish JIT path and is binutils/ELF-oriented.

## Observations

- The user-mentioned file `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md` does not exist. The current matching document is `SPONJIT_LALIN_COPY_PATCH_DESIGN.md`.
- Current SpongeJIT docs say old descriptor/opcode-shaped copy-link-patch assumptions are retired.
- `spongejit/Makefile` intentionally fails old targets like `stencils`, `bank`, `test-bank`, `probe`, etc.
- Maintained stencil metadata is ASDL-first and structural-keyed; tests reject opcode-shaped names, `out_tag`, old `sponbank`/`SponStencil` strings, and runtime-boundary stencils unless explicitly allowed.
- Current Lua `stencil_materialize.lua` is deterministic and testable but not an executable-memory publisher.
- Current Rust backend uses Cranelift `opt_level = speed` for both JIT and PIC object emission.
- Current object path emits full `.o` bytes suitable for system linker; tests link a generated object with C and call exported `add_i32`.
- Potential bug/ABI mismatch observed: `lua/lalin/back_object.lua` declares `lalin_bytes_free(uint8_t* data, size_t len)`, but current `src/ffi.rs` defines `lalin_bytes_free(bytes: *mut lalin_bytes_t)`. The old museum version had the two-argument signature.
- Old shadow prototype under `tools/sponjit_shadow` contains C stencils, hole externs, ELF extraction, and abstract stencil lowering, but comments/design vocabulary there are explicitly older and opcode/SSA-descriptor-flavored compared to current ASDL/LalinCFG direction.
- `tools/sponjit_shadow/stencil_model.lua` contains an apparent local bug in `template_from_ssa`: it references `tmpl` before assignment (`if not tmpl then ...`), consistent with it not being the maintained path.
- Current VM data (`products.lua`) already has fact-observable fields named in the design: stack slots (`LuaThread.stack/top`), frames/pc, table `shape_epoch`, `array_len`, `metatable`, GC/global state fields.

## Knowledge-builder Output — 2026-06-06 09:11:47

### What Matters Most for This Problem

- **Artifact boundary correctness**: a normal AOT object file is not automatically a stencil bank.
- **Patch-hole provenance**: copy-and-patch depends on knowing exactly which bytes are holes, their encodings, ordinals, addends, and legal value ranges.
- **ABI/register invariants**: the paper’s performance model depends on CPS tail calls plus a calling convention used as a register protocol.
- **Semantic separation**: SpongeJIT’s current design forbids opcode/helper/fallback semantics in the materializer.
- **Relocation/link stability**: copied bytes must remain valid after relocation into a runtime code heap.
- **AOT bank validity**: generated stencil bytes are tied to target ISA, Cranelift version/settings, VM layout, ABI, and schema identity.
- **Runtime safety/lifecycle**: executable memory, invalidation, GC, fact freshness, and code-cache coherence matter as much as byte copying.

### Non-Obvious Observations

- Lalin already has an AOT object path, but that path emits **whole relocatable objects**, not extractable copy-and-patch stencils. The missing piece is not “getting bytes”; it is preserving a typed mapping from semantic patch sources to concrete object relocations/byte offsets.

- The paper’s MetaVar trick relies on placeholder extern symbols so the object file contains relocation records for holes. Ordinary Lalin constants, stack offsets, branch destinations, and function references compiled through Cranelift may become opaque instruction bytes with no recoverable semantic identity.

- Cranelift `opt_level = speed` increases the risk that potential holes are folded, reordered, narrowed, dead-code-eliminated, or encoded differently. A value is patchable only if the compiled instruction sequence remains valid for every runtime value admitted by the stencil key.

- Patch encodings imply hidden range contracts. A `PcRel32`, `I32`, stack displacement, or immediate field is valid only while the runtime value fits that encoding. If a branch target, code-cache distance, stack frame, or constant exceeds the encoded range, the materializer cannot repair it without re-running instruction selection.

- The paper’s register allocation is not generic CPS; it depends on the **GHC calling convention** and on tail calls becoming jumps. Lalin/Cranelift’s normal C/System V-style ABI does not automatically provide the same pass-through register preservation semantics.

- Lalin regions look CPS-like at the source/control level, but `emit` splices regions into CFGs before backend lowering. That is almost the inverse of paper-style binary stencil composition: Lalin erases region boundaries for optimization, while copy-and-patch needs selected binary boundaries to survive as copyable artifacts.

- If stencils are extracted as whole Cranelift functions, each fragment may carry function ABI machinery—prologues, epilogues, stack alignment assumptions, unwind metadata expectations—that does not compose like paper stencils unless the ABI boundary is intentionally part of the stencil contract.

- Current `stencil_materialize.lua` materializes one template-shaped byte blob. The paper’s jump elision and branch patching rely on laying out a **graph of selected stencils** before patching. Single-template materialization cannot express adjacency-dependent jump removal unless the “template” is already a larger pre-fused tile.

- The current ASDL `Stencil` schema is richer than the Lalin runtime design sketch: it includes FFI, GC, GOT/PLT, target-specific relocations, and many patch kinds. The simplified runtime patch vocabulary would reject or under-specify some artifacts that the maintained ASDL can describe.

- PIC object emission can introduce GOT/PLT/section-relative relocations, while the current Lua materializer only meaningfully handles absolute and PC-relative cases. This is not just missing coverage; it affects whether copied bytes are self-contained or still depend on linker-created tables.

- A stencil bank’s `target` identity cannot safely mean only architecture/triple. It is coupled to Cranelift version, optimization flags, PIC/code model, CPU features, pointer width, endianness, Lalin ABI, Flatline wire version, ASDL schema version, and VM struct layout.

- `cranelift_native::builder()` ties emitted code to the build host’s CPU feature set. That is fine for same-machine JIT/object tests, but a prebuilt AOT stencil bank may be invalid on a different runtime host with the same broad architecture.

- The SpongeJIT materializer being semantics-blind is a strong constraint: “no matching tile,” patch failure, or invalid facts cannot be repaired by running Lua opcode semantics inside the patcher. All semantic fallback/guard behavior must already be represented outside that layer.

- Fact hashes in `TileKey` are dangerous if treated as complete identity. The design text says equality is over typed facts, but the bank index shape shown stores hash handles. A collision here would select wrong native code, not merely cause a cache miss.

- Runtime patch values derived from mutable VM state create validity/lifetime constraints. Embedding table shapes, epochs, metatable pointers, GC state pointers, or object addresses into code means the materialized code is only valid while the corresponding contract remains true.

- GC-related patch kinds imply process-local, lifetime-sensitive addresses. Even with non-moving objects, code may retain stale pointers after finalization, epoch changes, or allocator/barrier replacement. With a moving GC, raw patched object pointers would require stronger invariants.

- Existing old ELF/binutils extraction code is tempting but semantically misaligned: it comes from the retired descriptor/opcode-shaped path, while maintained SpongeJIT explicitly rejects opcode-shaped names, `out_tag`, interpreter/helper stencils, and old `sponbank` vocabulary.

- The observed `lalin_bytes_free` FFI mismatch is relevant beyond being a bug: it shows that the current Lua↔Rust object-emission seam is not yet a hardened artifact ABI. A copy-and-patch bank generator would be more sensitive to this kind of drift than normal object emission.

- The paper’s external-call exception machinery has no direct equivalent in the current design. SpongeJIT’s typed-continuation discipline means helper calls, guard failures, yields, and Lua errors cannot be hidden as ad hoc call/return conventions inside copied code.

- Current tests validate deterministic byte-string materialization, not executable memory publication. They do not exercise page permissions, instruction-cache flushing, W^X restrictions, relocation distance, concurrent publication, or invalidation races.

### Knowledge Gaps

- Exact Cranelift support for exposing per-function bytes, relocations, addends, symbols, and stack/frame metadata before final object emission.
- Whether Lalin can request or model a calling convention suitable for pass-through register stencils.
- The intended granularity of stencils: whole kernels/tiles, regions, blocks, branches, or smaller CPS fragments.
- Runtime invalidation model for facts/contracts and how published code is retired.
- Whether the Lua VM GC is moving/non-moving and what pointer-stability guarantees fast paths may assume.

## Approach-proposer Output — 2026-06-06 09:14:17

### Approach A: Cranelift-Derived Native Stencil Bank

- **Core idea**: Keep Lalin’s Flatline → Cranelift backend as the authority, but extend object/JIT emission to produce extractable native stencil artifacts with typed patch metadata.

- **Key changes**:
  - Extend `src/lib.rs`, `src/decode.rs`, and object emission to expose per-function `.text` bytes, symbols, relocations, and addends.
  - Extend `lua/lalin/back_object.lua` / backend FFI with a “compile stencil artifact” entrypoint.
  - Teach SpongeJIT foundry flow to compile LalinCFG-emitted Lalin source into Cranelift objects, then convert relocations into `StencilTemplate`.
  - Harden `stencil_object_extract.lua` into the maintained extraction bridge.

- **Tradeoff**: Optimizes for preserving the existing native backend and Cranelift investment; sacrifices portability because the resulting stencil bank is native-ISA-specific and does not directly help Wasm emission.

- **Risk**: Cranelift may optimize away or obscure values that need to remain patch holes unless Lalin deliberately emits placeholder symbols / externs that survive into relocations.

- **Rough sketch**:
  - Add explicit “hole extern” lowering in Lalin-generated stencil source.
  - Compile stencil kernels through Cranelift object mode.
  - Extract function bytes + relocations + symbols.
  - Map relocations back to ASDL `PatchHole` / `Reloc` records.
  - Materializer copies native bytes and patches runtime values.


### Approach B: Flatline Template / Multi-Target Patch Tier

- **Core idea**: Move copy-link-patch up one level: specialize and patch Lalin `BackProgram` / Flatline templates, then lower the patched artifact to either Cranelift native code or Wasm.

- **Key changes**:
  - Add a typed `FlatlineTemplate` or `BackProgramTemplate` representation beside the current `StencilTemplate`.
  - Represent holes as typed backend-level values: constants, addresses, function refs, layout offsets, guard facts.
  - Reuse `back_command_binary.lua` as the portable serialization boundary.
  - Add a Wasm backend that consumes the same patched Flatline-level artifact.
  - SpongeJIT bank lookup returns a backend-neutral template instead of native bytes.

- **Tradeoff**: Optimizes for portability and a shared native/Wasm story; sacrifices the paper’s fast `memcpy + patch machine bytes` compile speed.

- **Risk**: This may become “template-based partial compilation” rather than true copy-and-patch, because Cranelift or Wasm lowering still runs after patching.

- **Rough sketch**:
  - Define an ASDL schema for Flatline-level templates and holes.
  - Have the foundry emit template-shaped `BackProgram`s rather than binary stencils.
  - Runtime selects a template using `TileKey`.
  - Patch typed operands / constants / layout facts.
  - Dispatch patched Flatline to Cranelift native or Wasm emission.


### Approach C: Lalin-Owned Stencil Backend

- **Core idea**: Build a dedicated stencil codegen path owned by Lalin/SpongeJIT, with explicit stencil ABI, register protocol, patch encodings, and optional native/Wasm emitters.

- **Key changes**:
  - Add a low-level `StencilIR` / `MachineStencil` layer distinct from normal `LalinBack.BackProgram`.
  - Implement native x86-64/aarch64 stencil emission directly or through a small assembler layer.
  - Define the stencil calling convention explicitly instead of relying on Cranelift’s normal function ABI.
  - Optionally emit Wasm function-body templates from the same stencil IR where possible.
  - Keep Cranelift as the baseline compiler; use this only for SpongeJIT hot tiles.

- **Tradeoff**: Optimizes for paper-style copy-and-patch control over bytes, registers, and patch sites; sacrifices reuse of Cranelift for the stencil tier.

- **Risk**: This introduces a second backend with its own ABI, verifier, register discipline, relocation model, and target maintenance burden.

- **Rough sketch**:
  - Define a small stencil instruction/operand schema in ASDL.
  - Lower selected LalinCFG kernels to this stencil IR.
  - Encode holes explicitly before instruction selection.
  - Emit native bytes with known patch offsets and encodings.
  - Add Wasm-template emission only for stencil shapes that map cleanly to Wasm.


### Comparison

- Pick **A** if the priority is: “keep Cranelift, get native copy-and-patch as an acceleration tier.”
- Pick **B** if the priority is: “one portable specialization path that can target native and Wasm.”
- Pick **C** if the priority is: “true paper-style copy-and-patch with explicit ABI/register control.”
