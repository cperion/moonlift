# Futurama stencil-only VM exploration
Explore how Lalin Lua VM and SponJIT would change for a stencil-only VM with Lalin-authored semantics, saturated L0/L1, and FFI/C as stencils.
**Workflow ID**: wf-futurama-stencil-vm
**Started**: 2026-06-01 09:21:28
---

## Scout Output — 2026-06-01 09:27:35

## Files Retrieved

1. `experiments/lua_interpreter_vm/README.md` (lines 1-156) — Directory status: Lalin VM and SpongeJIT are separate; VM not JIT-wired.
2. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-86) — Pre-SponJIT gates: validator, frame cache, native ABI, allocator, errors/yield.
3. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-247) — Native stencil vocabulary + online fusion architecture.
4. `experiments/lua_interpreter_vm/SPONJIT_FOUNDRY_SSA.md` (lines 1-305) — Foundry/SSA atom vocabulary, L0/L1 growth, fact saturation.
5. `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md` (lines 1-919) — Native stencil ABI, continuation relocations, conformance rules.
6. `experiments/lua_interpreter_vm/SPONJIT_RUNTIME_DESIGN.md` (lines 1-1236) — Future runtime/materializer model: floor/active images, no runtime compiler.
7. `experiments/lua_interpreter_vm/SPONJIT_TIER2_PLANNER_SPEC.md` (lines 1-1230) — Tier 2 fusion planner spec over prebuilt stencils.
8. `experiments/lua_interpreter_vm/src/contract.lua` (lines 1-20) — Machine-readable VM gate: `sponjit_allowed = false`.
9. `experiments/lua_interpreter_vm/src/init.lua` (lines 1-43) — VM module aggregation.
10. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-131) — Lalin-native VM data layouts.
11. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-244) — Tags, opcodes 0-84, resume modes, native result statuses, ABI versions.
12. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-178) — Main Lalin VM loop and dispatch continuations.
13. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-816) — Bytecode decode, inline hot opcode arms, handler dispatch.
14. `experiments/lua_interpreter_vm/src/op_handlers.lua` (lines 1-18) — Opcode handler aggregator.
15. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-138) — Shared handler parameter/protocol boilerplate.
16. `experiments/lua_interpreter_vm/src/op/protocols.lua` (lines 1-48) — Named opcode continuation protocols.
17. `experiments/lua_interpreter_vm/src/op/arithmetic.lua` (lines 1-260) — Arithmetic opcode semantics and fast paths.
18. `experiments/lua_interpreter_vm/src/op/call.lua` (lines 1-293) — Call/return opcode semantics.
19. `experiments/lua_interpreter_vm/src/op/loop.lua` (lines 1-132) — Numeric/generic loop opcode handlers.
20. `experiments/lua_interpreter_vm/src/op/table.lua` (lines 1-322) — Table op handlers and metamethod paths.
21. `experiments/lua_interpreter_vm/src/validate.lua` (lines 1-384) — Bytecode validation trust boundary.
22. `experiments/lua_interpreter_vm/src/regions_native.lua` (lines 1-83) — Explicit native ABI invocation/result decode.
23. `experiments/lua_interpreter_vm/src/regions_allocator.lua` (lines 1-192) — Explicit allocator/growth boundary.
24. `experiments/lua_interpreter_vm/src/regions_error.lua` (lines 1-235) — Error object/protected unwind/TBC regions.
25. `experiments/lua_interpreter_vm/src/regions_call.lua` (lines 1-400) — Prepare call, native call, return/resume engine.
26. `experiments/lua_interpreter_vm/src/regions_resume.lua` (lines 1-238) — ResumeState decoding and return convergence.
27. `experiments/lua_interpreter_vm/src/api.lua` (lines 1-158) — Sealed C-compatible API funcs.
28. `experiments/lua_interpreter_vm/src/bytecode.lua` (lines 1-115) — Lua 5.5 bytecode encoding/decoding facts.
29. `experiments/lua_interpreter_vm/src/regions_codegen.lua` (lines 1-260) — Source compiler bytecode builder regions.
30. `experiments/lua_interpreter_vm/src/regions_lower.lua` (lines 1-260) — HIR-to-bytecode lowering start.
31. `experiments/lua_interpreter_vm/src/regions_compiler.lua` (lines 1-244) — Public source-byte compiler entry.
32. `experiments/lua_interpreter_vm/spongejit/Makefile` (lines 1-55) — Test/build targets for stencils, bank, C L1 interpreter.
33. `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` (lines 1-166) — Chunked grammar/fact/stencil bank build; exact L0 appended.
34. `experiments/lua_interpreter_vm/spongejit/foundry.lua` (lines 1-272) — Foundry entry point; multi-layer atom selection.
35. `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` (lines 1-195) — Public SSA → Stencil IR compile facade.
36. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-466) — Opcode/facts → semantic SSA lowering.
37. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-484) — SSA graph, value/effect/exit model.
38. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-305) — Typed fact lattice and dependencies.
39. `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` (lines 1-357) — Curated fact bundle enumeration.
40. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` (lines 1-360) — SSA → hole-parametric Stencil IR.
41. `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` (lines 1-182) — Stencil IR data model/validation.
42. `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` (lines 1-208) — Stencil IR → native descriptor + x64 bytes.
43. `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua` (lines 1-1346) — First-surface executable x86-64 byte emitter.
44. `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua` (lines 1-561) — Descriptor schema/validation/ABI lowering.
45. `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua` (lines 1-369) — Standalone Lua copy/link/patch materializer.
46. `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` (lines 1-768) — SQLite → `libsponbank.so` C metadata/selector generation.
47. `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-281) — Generated bank C ABI: descriptors, selectors, exec ctx.
48. `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.h` (lines 1-110) — Prototype C L1 projection interpreter API.
49. `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.c` (lines 1-357) — C bank selector + copy/link/patch + execute.
50. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-205) — Parallel worker: opcode/facts → SSA normal forms.
51. `experiments/lua_interpreter_vm/spongejit/src/dedupe_normal_forms.lua` (lines 1-235) — Global dedupe and unique native lowering.
52. `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` (lines 1-480) — Opcode grammar enumeration up to arity 4.
53. `experiments/lua_interpreter_vm/spongejit/src/loop_regions.lua` (lines 1-210) — Structural numeric/generic loop-region recognition.
54. `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` (lines 1-91) — Coverage classification; no fallback-stub category.
55. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-10) — Removed PUC/C-function tile integration note.
56. `experiments/lua_interpreter_vm/tools/sponjit_shadow/README.md` (lines 1-166) — Older non-executing economic simulator.
57. `experiments/lua_interpreter_vm/tools/sponjit_shadow/stencils/README.md` (lines 1-12) — Archived old C stencil notes.
58. `experiments/lua_interpreter_vm/tools/sponjit_shadow/stencils/src/stencils.c` (lines 1-240) — Archived GCC-generated old C-stencil vocabulary.
59. Tests read:
    - `tests/test_vm_abi_contract.lua` (lines 1-63)
    - `tests/test_vm_native_abi_contract.lua` (lines 1-108)
    - `tests/test_vm_validation_contract.lua` (lines 1-189)
    - `tests/test_vm_native_return_convergence.lua` (lines 1-221)
    - `tests/test_spongejit_native_stencil_bytes.lua` (lines 1-535)
    - `tests/test_spongejit_materialize_native.lua` (lines 1-140)
    - `tests/test_spongejit_l1_interpreter.c` (lines 1-65)
    - `tests/test_spongejit_semantic_l0_coverage.lua` (lines 1-113)
    - `tests/test_spongejit_selector_no_fallback.lua` (lines 1-69)
    - `tests/test_spongejit_bank_materialize.lua` (lines 1-522)
    - `tests/test_spongejit_retired_fallback.lua` (lines 1-67)
    - `tests/test_spongejit_retirement.lua` (lines 1-63)

## Key Code

### VM gate is closed

```lua
-- experiments/lua_interpreter_vm/src/contract.lua
return {
    vm_abi_version = 2,
    native_abi_version = 2,
    validator_contract_version = 2,
    sponjit_allowed = false,
    required_gates = {
        "lua55_tm_order",
        "bytecode_validator_complete",
        "binary_chunk_loader_complete",
        "source_compiler_complete",
        "frame_cache_reload_on_all_switches",
        "native_return_converges_with_lua_return",
        "unified_error_value_unwind",
        "explicit_coroutine_transfer",
        "gc_finalizer_weak_table_protocols",
    },
}
```

### Main VM loop is Lalin-authored regions

```lua
-- experiments/lua_interpreter_vm/src/vm_loop.lua
region vm_loop(L: ptr(LuaThread);
               finished: cont(nres: i32),
               yielded: cont(nres: i32),
               error: cont(code: i32),
               oom: cont())
entry start()
    if L.frame_count == 0 then
        jump finished(nres = 0)
    end
    let frame: ptr(Frame) = L.frames + (L.frame_count - 1)
    let pc: index = frame.pc
    let base: index = frame.base
    let top: index = frame.top
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let code: ptr(Instr) = cl.proto.code
    let constants: ptr(Value) = cl.proto.constants
    jump loop(frame = frame, pc = pc, base = base, top = top, code = code, constants = constants)
end
```

On parent/child frame changes it reloads cached proto pointers, matching `VM_CONTRACT.md`’s frame-cache invariant.

### VM products are Lalin-native, not PUC layouts

```lua
-- experiments/lua_interpreter_vm/src/products.lua
local Value = host.struct [[struct Value tag: u32; aux: u32; bits: u64 end]]
local NativeFunc = host.struct [[struct NativeFunc abi_version: u32; flags: u32; addr: ptr(u8); name: ptr(String) end]]
local NativeCallResult = host.struct [[struct NativeCallResult status: u8; nresults: i32; err: Value; stack_needed: index; continuation: ptr(u8) end]]
local NativeCallContext = host.struct [[struct NativeCallContext func_slot: index; nargs: i32; wanted: i32; result_base: index; stack_top: index; yieldable: u8; reserved: u8; resume: ResumeState end]]
local Frame = host.struct [[struct Frame closure: Value; base: index; top: index; pc: index; wanted: i32; tailcalls: i32; result_base: index; call_top: index; resume: ResumeState; yieldable: u8; flags: u8; reserved: u16 end]]
```

### Bytecode validator is the interpreter/JIT trust boundary

```lua
-- experiments/lua_interpreter_vm/src/validate.lua
-- validate_proto: verify Proto is safe to execute. This is the canonical
-- interpreter/JIT trust boundary; opcode handlers may assume these facts.
local validate_proto = host.region(I) [[
region validate_proto(L: ptr(LuaThread), p: ptr(Proto);
                      ok: cont(), invalid: cont(code: i32), oom: cont())
...
    if op > @{OP_EXTRAARG} then
        jump invalid(code = @{ERR_BAD_OPCODE})
    end
...
    -- Pair-only opcodes must be paired with their producers.
    if op == @{OP_EXTRAARG} then
...
    -- Arithmetic fast paths rely on adjacent metamethod fallback opcodes.
...
    -- Comparisons/tests are followed by the jump they conditionally skip.
...
    -- Jump and loop targets/windows.
...
    -- Call/return register windows.
```

### Native ABI is explicit function-pointer call today

```lua
-- experiments/lua_interpreter_vm/src/regions_native.lua
let fn: func(ptr(LuaThread), ptr(CClosure), ptr(NativeCallContext), ptr(NativeCallResult)) -> index =
    as(func(ptr(LuaThread), ptr(CClosure), ptr(NativeCallContext), ptr(NativeCallResult)) -> index, cl.fn.addr)
let rc: index = fn(L, cl, &ctx_cell, &result)
if rc ~= as(index, 0) then jump invalid() end
emit decode_native_result(&result; ...)
```

This is a present C/FFI-style native boundary, not currently a stencil.

### SpongeJIT current maintained pipeline

```lua
-- experiments/lua_interpreter_vm/spongejit/src/ssa.lua
-- Offline foundry brain:
--   facts/opcodes -> semantic SSA -> Lua-semantic optimization ->
--   hole-parametric Stencil IR -> canonical stencil hash/form.
--
-- Runtime remains simple copy/patch/execute and never runs SSA/lowering.
```

```lua
function M.compile(ops, facts, config)
    local fs = factset(facts)
    local g = Lift.lift(ops or {}, fs, config)
    if not g.rejected then Opt.optimize(g, config) end
    return summarize(g, ops or {}, fs, config)
end
```

### SSA makes boundaries/rejections explicit

```lua
-- experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua
function Graph:reject(opcode, pc, reason, event)
    self.rejected = true
    self.rejections[#self.rejections + 1] = {
        opcode = opcode,
        pc = pc or 0,
        reason = reason or "unsupported",
        event = event,
    }
    return true
end

function Graph:boundary(opcode, pc, event, reason)
    return self:add("Boundary", {
        source = pc,
        effect = "branch",
        args = { opcode = opcode, reason = reason or "vm_boundary", event = event },
        exit = self:exit_projection("boundary:" .. tostring(opcode), pc),
    })
end
```

### Stencil IR forbids encoding exits as data holes

```lua
-- experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua
function Stencil:hole(t)
  t = t or {}
  assert(t.role_kind ~= "exit" and t.role_kind ~= "fail", "exit/fail are control endpoints, not data holes")
...
end
```

### Native descriptor lowering

```lua
-- experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua
local SUPPORTED_OP = {
  LoadSlot = true,
  StoreSlot = true,
  StoreI64Slot = true,
  LoadConst = true,
  ConstNil = true,
  ConstBool = true,
  Move = true,
  NotTValue = true,
  GuardI64 = true,
  GuardNumber = true,
  GuardNonZeroI64 = true,
  GuardTable = true,
  GuardShape = true,
  GuardMetatableAbsent = true,
  ...
  ExitBoundary = true,
}
```

```lua
local native, native_errors = NativeX64.emit(st, {
  exit_endpoint_by_node = exit_endpoint_by_node,
  ok_endpoint_index = ok_endpoint_index,
  endpoints = endpoints
})
...
executable = true,
exact = true,
semantic_mode = semantic_mode,
layout = native.layout,
code_hex = native.code_hex,
data_relocs = native.data_relocs,
control_relocs = native.control_relocs,
```

### Materializer is mechanical copy/link/patch only

```lua
-- experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua
-- This module consumes already-built native stencil descriptors. It never runs
-- SSA, never normalizes, and never infers hidden semantics.
```

```lua
function M.materialize(entries, opts)
...
    if st.executable ~= true then error("cannot materialize non-executable stencil at entry " .. tostring(i)) end
...
    for _, r in ipairs(entry.stencil.data_relocs or {}) do patch_data_reloc(image, entry.base, entry, r) end
...
      if edge == "fallthrough" and i < #norm then
        patch_u32(image, site, target - (site + 4))
      end
```

### Generated C bank exposes native stencil metadata and selector

```c
// experiments/lua_interpreter_vm/spongejit/include/sponbank.h
typedef struct {
  SponStencilId stencil_id;
  uint32_t offset;
  uint32_t size;
  ...
  uint16_t flags;
  uint16_t physical_abi;
  ...
  SponFactSig selector_sig;
  SponFactSig required_sig;
  SponFactSig checked_sig;
  SponFactSig produced_sig;
  SponFactSig killed_sig;
} SponStencilDesc;

SponStencilId spon_l0_stencil_for_opcode(uint32_t opcode);
const SponStencilChoice *spon_select_flow_flags_slots(...);
```

### C L1 prototype projects bank choices into executable image

```c
// experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.c
int spon_l1_project(const SponL1Op *ops, uint32_t start, uint32_t end,
                    SponFactSig entry_sig, SponFactSig observed_sig,
                    SponL1Image *out_img) {
...
  const SponStencilChoice *choices = spon_select_flow_flags_slots_stats(
      bc, start, end, entry_sig, observed_sig, SPON_STENCIL_NATIVE | SPON_STENCIL_EXACT,
      actual_slots, n_actual_slots, &n_choices, &stats);
...
    memcpy(code + off, src, d->size);
...
    if (patch_data_reloc(...) != 0) ...
...
        int64_t rel = (int64_t)bases[i + 1] - (int64_t)(site + 4);
        patch_pc32(code, total, site, rel)
...
}
```

## Relationships

- `src/` VM:
  - `src/init.lua` loads products, runtime regions, API, validator, opcode handlers, compiler.
  - `src/vm_loop.lua` calls `opcodes.dispatch_instruction`.
  - `src/opcodes.lua` decodes packed Lua 5.5 words, inlines some hot opcodes, and emits into handler regions from `src/op/*.lua`.
  - Handlers call runtime regions (`prepare_call`, `table_get`, `raise_code_error`, `call_native`, etc.).
  - `validate_proto` is documented and implemented as the trust boundary for interpreter and future JIT/stencils.

- SpongeJIT foundry:
  - `grammar_enum.lua` / `enumerate.lua` produce opcode windows.
  - `ssa_fact_axes.lua` produces bounded curated fact bundles.
  - `ssa_lift.lua` consumes opcode + fact semantics into `ssa_ir.lua`.
  - `ssa_opt.lua` cleans SSA.
  - `ssa_to_stencil.lua` lowers SSA to `stencil_ir.lua`.
  - `stencil_normalize.lua` hashes canonical stencil normal forms.
  - `worker_compile.lua` stores per-worker normal forms and pattern aliases in SQLite.
  - `dedupe_normal_forms.lua` globally dedupes by `canonical_stencil_hash` / normal form and lowers one representative.
  - `stencil_lower.lua` calls `stencil_native_x64.lua` and validates via `stencil_desc.lua`.
  - `build_bank.lua` emits `libsponbank.so` with C arrays and selectors.
  - `materialize_native_x64.lua` and `runtime/sponjit_l1_interpreter.c` copy/link/patch selected native bytes.

- Current runtime integration:
  - `src/vm_loop.lua` does not call SponJIT.
  - `contract.lua` and tests assert `sponjit_allowed == false`.
  - C L1 interpreter is under `spongejit/runtime/`, tested through `make test-bank`, not wired into Lalin VM.

## Observations

- Current VM is already heavily Lalin-authored: counted 264 `host.region`/`lalin.region`/`lalin.func` occurrences under `experiments/lua_interpreter_vm/src`.
- Current SpongeJIT is mostly stencil infrastructure already:
  - native x64 byte emission exists for a “first surface”;
  - bank descriptors include data/control relocations, endpoint metadata, projections, fact transfer;
  - standalone Lua and prototype C materializers exist.
- Major documented gate remains: no VM integration until contract gates pass.
- C-function tile/stencil path is explicitly retired:
  - docs say C-function-shaped stencils are not linkable stencils;
  - tests scan for retired tile/fallback/helper terminology.
- There is still C in the maintained path:
  - generated `libsponbank.so`;
  - `sponbank.h`;
  - `runtime/sponjit_l1_interpreter.c`;
  - native helper primitive table in `SponExecCtx` (`barrier`, `pow_f64`).
- That C is currently infrastructure/native stencil host code, not the old C-function tile ABI.
- Runtime helper calls are not stencils today:
  - `stencil_native_x64.lua` emits calls through `ctx->prims` for `PowF64` and `BarrierCheck`.
  - `regions_native.lua` invokes `NativeFunc.addr` directly through a function pointer.
- Strict complete L0 is not guaranteed by default:
  - build appends exact L0 candidates for all opcodes;
  - `test_spongejit_semantic_l0_coverage.lua` reports missing coverage unless `SPON_STRICT_SEMANTIC_L0=1`, where it asserts none missing.
- Loop opcodes are treated specially:
  - docs and `ssa_lift.lua` say `FORPREP`/`FORLOOP` and `TFOR*` are structural loop-region boundaries, not scalar fact-axis opcodes.
  - `loop_regions.lua` recognizes paired topology records for future whole-loop lowering.
- First native conformance surface is narrow relative to full Lua semantics:
  - i64 slots/stores/guards/arithmetic, constants, simple boundary exits are strongest.
  - payload-heavy roles exist in code (`shape_offset`, `field_offset`, array/upvalue/barrier), but docs warn dependency/payload machinery is needed before broad executable use.
- Tests cover both VM gates and stencil mechanics:
  - VM ABI/native ABI/validator/native return convergence.
  - Native stencil bytes execute.
  - Materializer links fallthrough.
  - Generated bank selects/materializes.
  - Selector has no hidden fallback for unknown opcode.
  - Retired C-function/fallback tokens are absent.

## Knowledge-builder Output — 2026-06-01 09:30:49

### What Matters Most for This Problem

- **Exhaustive semantic floor**: L0 must be complete enough to execute all validated programs, not merely “cover all opcode numbers.”
- **Single semantic authority**: Lalin-authored VM semantics and SpongeJIT semantic SSA currently duplicate meaning; stencil-only raises divergence risk.
- **Exit/projection correctness**: without interpreter fallback, every guard, error, yield, return, call, and deopt-like edge must resume through a native floor/protocol.
- **C/FFI conformance**: C calls cannot be old “C-function tiles”; they must either be explicit helpers with modeled effects or true stencil ABI participants.
- **Fact/dependency soundness**: saturated L1+ atoms only work if facts, kills, payload dependencies, frame state, and invalidation are complete.
- **Artifact/ABI stability**: the stencil bank becomes the executable VM, so product layouts, ABI versions, validator facts, and bank descriptors become one contract.

### Non-Obvious Observations

- **“No interpreter fallback” does not remove fallback semantics; it relocates them into L0.**
  Current SpongeJIT has `Boundary` / `ExitBoundary` concepts that assume some VM boundary exists. In a stencil-only VM, those exits cannot mean “go back to the Lalin loop”; they must mean “transfer to an exact native floor continuation with sufficient projected state.” This is a semantic change to the meaning of boundary exits, not just a runtime wiring change.

- **L0 coverage is larger than opcode coverage.**
  The validator establishes multi-instruction invariants: `EXTRAARG` pairing, arithmetic fast-path/fallback adjacency, comparison/test followed by jump, call/return register windows, loop target windows. Therefore an “L0 stencil for every opcode” is not enough unless those stencils encode the validator-implied neighboring obligations. The true floor unit is sometimes a validated opcode phrase, not a raw opcode.

- **Loop handling is the sharpest mismatch with current SpongeJIT assumptions.**
  Current foundry treats `FORPREP`/`FORLOOP` and `TFOR*` as structural loop-region boundaries, not scalar fact-axis opcodes. That is fine when boundaries can hand back to an interpreter. In stencil-only execution, structural loop boundaries need native floor semantics; otherwise loops become the first place “no fallback” is violated.

- **The existing Lalin VM already contains the best semantic taxonomy for stencil endpoints.**
  `vm_loop.lua`, `op/protocols.lua`, `regions_call.lua`, `regions_resume.lua`, `regions_error.lua`, and `regions_native.lua` already carve semantics into named continuations: finished, yielded, error, oom, native result statuses, resume modes, protected unwind, TBC handling. Those are more precise than generic “exit” categories. The opportunity is that the current VM control protocols are close to the control vocabulary a stencil-only VM needs.

- **The biggest semantic risk is duplicated opcode meaning.**
  Current opcode handlers in `src/op/*.lua` are Lalin-authored, while `spongejit/src/ssa_lift.lua` independently models opcode semantics for stencils. With an interpreter fallback, mismatches can be survivable if unsupported paths exit. With stencil-only execution, any divergence between Lalin handler semantics and SSA/stencil semantics becomes VM misexecution.

- **The validator becomes even more central, not less.**
  It is already documented as the interpreter/JIT trust boundary. In a stencil-only VM, stencils inherit every assumption currently consumed by opcode handlers. If a materialized span cuts across a validator-protected pair or ignores a validator-proven window fact, the native floor can become unsound even when individual stencil descriptors validate.

- **C/FFI as “stencils/helpers” conflicts with retired C-tile terminology unless conformance is extremely explicit.**
  The docs intentionally retired C-function-shaped tiles because they are not linkable native stencils. The user direction can still fit, but only if “C/FFI stencil” means either:
  - a true native stencil with endpoints, relocations, facts, effects, and projections; or
  - an opaque helper call whose effects, kills, yield/error behavior, and dependency invalidation are fully declared.
  A raw `NativeFunc.addr` call through `regions_native.lua` is not enough.

- **Native calls are not just calls; they are control-producing VM events.**
  `NativeCallResult` can report success, yield, error, OOM/stack growth, continuation, and result counts. Treating FFI/C as stencilable means those statuses become stencil endpoints. Otherwise native calls smuggle an interpreter-shaped mini-VM back into the system.

- **Fact saturation increases the importance of kill sets.**
  L1+ atoms depend on fact transfer. But table ops, metatables, GC barriers, native calls, weak tables, finalizers, and helpers can invalidate facts globally or conditionally. In a no-fallback VM, conservative `killed_sig` and dependency epochs are not optimization metadata; they are safety metadata.

- **The current first native surface is far narrower than the target VM.**
  Existing executable stencils are strongest for i64 slots, guards, constants, simple arithmetic, and simple exits. Full Lua execution needs tables, metamethods, closures, varargs, upvalues, coroutines, errors, allocator paths, GC protocols, finalizers, weak tables, and native calls. The distance is not just opcode count; it is effect modeling and projection richness.

- **Projection sufficiency is the hidden hard problem.**
  The planner spec distinguishes projection presence from projection sufficiency. In stencil-only execution, every possible exit from an optimized atom must reconstruct enough frame/stack/PC/resume state for the native floor. If atoms keep values resident in registers or elide stores, every guard/error/yield path inherits a precise repair obligation.

- **Frame-cache invariants become stencil ABI invariants.**
  The Lalin loop reloads cached frame/proto pointers on parent/child frame switches. Native images that inline or cache `frame`, `pc`, `base`, `top`, `code`, or `constants` must preserve the same reload points. This is especially important across calls, returns, yields, tailcalls, and native continuations.

- **“Floor image” needs to be cold-execution capable.**
  Runtime docs talk about active images demoting to floor. With no interpreter fallback, the floor is not merely a safe deopt target; it is also the cold start execution engine, invalidation target, and recovery target after failed planning/materialization. That makes L0 operationally equivalent to the VM.

- **Bank artifacts become part of the VM release ABI.**
  `products.lua` layouts, `constants.lua` opcodes/statuses, `contract.lua` ABI versions, validator contract versions, and `sponbank.h` descriptor formats must move in lockstep. A stale bank against changed `Frame`, `Value`, `NativeCallContext`, or opcode constants is not a JIT bug; it is a broken VM binary.

- **Selector “no fallback” tests are necessary but not sufficient.**
  Tests currently ensure there is no hidden selector fallback for unknown opcodes. Stencil-only needs a stronger invariant: every selector rejection, missing fact, missing payload, failed dependency, failed materialization, or unsupported helper must have a native L0 execution path or become a load-time/build-time error.

- **Saturated atoms shift runtime complexity from codegen to proof selection.**
  The runtime avoids arbitrary compilation, but it still performs selection over variants, endpoints, bridges, fact states, dependency constraints, and projection obligations. The complexity is not gone; it is constrained into planner/materializer legality. Bad descriptor quality makes Tier 2 collapse into direct-linking L0 atoms.

- **C helper calls can silently destroy the “stencil-only” property if they become semantic black boxes.**
  Existing native emitter calls helper primitives such as `pow_f64` and `barrier`. If helper calls are allowed without explicit memory/effect/fact contracts, the system regains hidden interpreter-like semantics under another name.

- **There is a useful alignment between Lalin’s jump-first style and stencil endpoints.**
  Lalin regions already expose named continuations and explicit control edges. That maps naturally to stencil endpoint metadata, unlike callback/vtable-style interpreters. This is a non-obvious advantage of keeping Lalin as the semantic authoring language.

- **The current VM gates remain relevant even if the interpreter loop disappears.**
  Gates like native return convergence, unified error unwind, explicit coroutine transfer, frame cache reloads, allocator boundaries, and GC/finalizer/weak-table protocols are not “pre-JIT cleanup”; they are exact requirements for a stencil-only VM to avoid hidden fallback paths.

### Knowledge Gaps

- How complete the intended L0 floor must be at first milestone: all validated bytecode, or a restricted validated subset?
- Whether Lalin-authored regions are expected to remain executable artifacts, semantic source artifacts, or both.
- How C/FFI “conforming stencils/helpers” should be classified in the descriptor schema: true native stencils vs opaque helper endpoints.
- The intended treatment of GC, weak tables, finalizers, and allocator slow paths in a no-interpreter system.
- Whether current bank generation size remains tractable once full Lua payload/effect axes are included.

## Approach-proposer Output — 2026-06-01 09:32:41

### Approach A: Lalin-to-Stencil Single Source

- **Core idea**: Treat Lalin VM regions as the only semantic source and add a backend that lowers them directly into stencil descriptors for both L0 floor and L1+ atoms.

- **Key changes**:
  - Add a Lalin region → Stencil IR/native descriptor lowering path.
  - Refactor `src/op/*.lua`, `regions_call.lua`, `regions_error.lua`, `regions_resume.lua`, `regions_native.lua` into stencil-friendly semantic regions with explicit endpoints.
  - Retire duplicated semantic lowering in `spongejit/src/ssa_lift.lua` or make it consume generated Lalin semantic summaries.
  - Extend `stencil_desc.lua`, `sponbank.h`, and bank generation to understand Lalin-derived control protocols.

- **Tradeoff**: Optimizes for single semantic authority and minimal divergence; sacrifices short-term reuse of the existing hand-authored SponJIT semantic SSA model.

- **Risk**: Lalin-to-stencil lowering may become a second compiler backend with hard requirements around continuation endpoints, layout holes, projections, and effect metadata.

- **Rough sketch**:
  - Define a stencil ABI projection for Lalin continuations: `ok`, `yield`, `error`, `oom`, `return`, `native_result`, etc.
  - Lower each opcode handler or validated opcode phrase from Lalin region form into exact L0 stencil descriptors.
  - Generate fact/effect summaries from the same Lalin region lowering, not from independent opcode models.
  - Teach the foundry to build L1+ atoms by composing Lalin-derived semantic units.
  - Model C/FFI calls as Lalin-authored wrapper regions that lower to helper-call stencils with declared effects, kills, and endpoints.

---

### Approach B: Native Floor from Lalin, Optimized Atoms from Subordinate SSA

- **Core idea**: Keep the current SponJIT SSA/foundry pipeline for L1+ optimization, but make a complete Lalin-derived L0 floor the mandatory semantic recovery and cold-execution target.

- **Key changes**:
  - Build an exhaustive L0 bank from current Lalin VM regions, likely phrase-based rather than raw-opcode-based.
  - Keep `spongejit/src/ssa_lift.lua`, fact axes, dedupe, and native lowering for saturated/fused L1+ atoms.
  - Change `Boundary` / `ExitBoundary` semantics so every exit targets an exact L0 native continuation, never the Lalin interpreter loop.
  - Add projection sufficiency checks linking optimized atoms to L0 floor entry protocols.
  - Extend bank selection/materialization so missing L1 choices always demote to L0, while missing L0 is a build/load error.

- **Tradeoff**: Optimizes for incremental migration and reuse of existing SponJIT infrastructure; sacrifices pure single-source semantics because L1+ SSA still duplicates meaning.

- **Risk**: Semantic drift between Lalin L0 and SponJIT L1+ atoms could cause misexecution unless conformance testing/proof obligations are strong.

- **Rough sketch**:
  - First make the L0 bank complete for all validated bytecode phrases, including loop-region boundaries, calls, returns, errors, and native statuses.
  - Reinterpret every SponJIT boundary exit as a patched jump into the L0 floor with repaired frame/stack/PC state.
  - Add descriptor fields for required projection state and validate them during planning/materialization.
  - Keep L1+ saturation and fusion as an optimization tier over existing fact signatures.
  - Treat C/FFI as opaque helper stencils in L1+, but require conservative effect/killed sets and L0-native result convergence.

---

### Approach C: Protocol-First Stencil VM Kernel

- **Core idea**: Define the VM as a small set of native stencil protocols—dispatch, call, return, resume, error, allocation, native-call—and rewrite Lalin regions to author those protocols rather than opcode bodies directly.

- **Key changes**:
  - Introduce an explicit VM stencil protocol schema: endpoint kinds, frame-cache rules, resume modes, native result statuses, allocator/error/yield transitions.
  - Refactor current Lalin regions into protocol kernels and opcode phrases that target those kernels.
  - Generate L0 as a linked native floor image composed of protocol stencils plus opcode/phrase stencils.
  - Make SponJIT planner operate over protocol-aware atoms instead of generic `Boundary` exits.
  - Replace raw `NativeFunc.addr` calls with protocol-conforming native-call stencils.

- **Tradeoff**: Optimizes for explicit control correctness and long-term extensibility of calls/yields/errors/FFI; sacrifices simplicity because it introduces a new architectural layer before full VM execution works.

- **Risk**: The protocol layer could become too abstract or too large, making ordinary opcode lowering and bank selection more complex than necessary.

- **Rough sketch**:
  - Promote existing continuation vocabulary from `vm_loop.lua`, `op/protocols.lua`, `regions_call.lua`, `regions_resume.lua`, and `regions_error.lua` into a formal stencil endpoint contract.
  - Define legal state projections for each endpoint: frame, pc, base, top, constants, resume state, native call context.
  - Build L0 as protocol-linked native stencils, with structural phrases for validator-enforced pairs and loop regions.
  - Let L1+ atoms fuse only when their exits can target one of the declared protocol endpoints with sufficient projection.
  - Classify C/FFI as protocol participants: either true native stencils with endpoints or helper calls with declared effects, kills, yield/error/OOM behavior.

---

### Comparison

- **Approach A** is the cleanest single-authority model: Lalin semantics directly become stencil artifacts.
- **Approach B** is the most incremental: complete Lalin L0 first, then keep current SponJIT SSA for optimization under stronger conformance rules.
- **Approach C** is the most control-protocol-centric: it formalizes VM events and endpoints first, making calls, errors, yields, allocator paths, and C/FFI behavior explicit across all tiers.
