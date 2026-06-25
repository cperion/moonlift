# Rewrite stale AGENTS guidance for lua_compile 
Audit current lua VM / SpongeJIT lua_compile architecture and AGENTS.md guidance before rewriting stale project guidance.
**Workflow ID**: wf-lua-compile-agents-md
**Started**: 2026-06-07 18:21:44
---

## Scout Output — 2026-06-07 18:26:30

## Files Retrieved

1. `/home/cedric/.pi/agent/AGENTS.md` (lines 1-142) - Global agent-pipeline instructions; governs all work in this harness.
2. `AGENTS.md` (lines 1-337) - Project-root guidance; governs `experiments/lua_interpreter_vm/spongejit/lua_compile/`. It currently describes Lalin broadly, not this LuaCompile/SpongeJIT subtree specifically.
3. `museum/gps.lua/AGENTS.md` (lines 1-80) - Present in repo but **not an ancestor** of the Lua VM/SpongeJIT subtree; does not govern this area.
4. `experiments/lua_interpreter_vm/README.md` (lines 1-88) - Current top-level Lua VM + SpongeJIT direction, tests, docs, guardrails.
5. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-42) - Current high-level architecture and retired assumptions.
6. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-85) - Lua VM contract and SponJIT gate.
7. `experiments/lua_interpreter_vm/spongejit/Makefile` (lines 1-58) - Maintained test/foundry targets, no-old-import checks, retired target failures.
8. `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` (lines 1-5) - Explicitly retired old stencil path.
9. `experiments/lua_interpreter_vm/spongejit/build_lua_compile_foundry.sh` (lines 1-178) - Maintained offline foundry builder.
10. `experiments/lua_interpreter_vm/spongejit/foundry.lua` (lines 1-160) - Maintained foundry CLI; corpus-window source.
11. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/README.md` (lines 1-47) - ASDL vocabulary docs and guardrails.
12. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`:
    - lines 1-260 - Doctrine, `LuaSrc`, `LuaRegion`, `LuaFact`.
    - lines 264-533 - `LuaFFI`.
    - lines 534-1127 - `LuaRT`.
    - lines 1128-1392 - `LuaGC`.
    - lines 1393-1752 - `LuaExec`.
    - lines 1753-1822 - `CompileContract`.
    - lines 1823-2037 - `LalinCFG`.
    - lines 2038-2279 - `Stencil`.
    - lines 2280-2363 - `LuaCompile`.
13. `experiments/lua_interpreter_vm/spongejit/lua_compile/schema.lua` (lines 1-79) - ASDL bootstrap; only file loading textual schema.
14. `experiments/lua_interpreter_vm/spongejit/lua_compile/builders.lua` (lines 1-46) - ASDL constructor conveniences.
15. `experiments/lua_interpreter_vm/spongejit/lua_compile/init.lua` (lines 1-66) - Public facade exports all current modules/phases.
16. `experiments/lua_interpreter_vm/spongejit/lua_compile/validate.lua` (lines 1-158) - Shared cross-layer validators.
17. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_validate.lua` (lines 1-49) - Whole-pipeline boundary validators.
18. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_unit.lua` (lines 1-31) - Source/evidence -> `LuaCompile.Unit` PVM phase.
19. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_to_lalin_kernel.lua` (lines 1-98) - Public `LuaCompile.Unit -> LuaCompile.Result` compile route through LuaExec/LalinCFG.
20. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_from_puc_decode.lua` (lines 1-216) - PUC event -> `LuaSrc.Op` decoding phase.
21. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_window_collect.lua` (lines 1-60) - Source events -> `LuaSrc.Window`.
22. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_runtime_observe.lua` (lines 1-252) - Runtime/foundry observation import to `LuaFact.Evidence`.
23. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_foundry_bundle.lua` (lines 1-51) - Foundry bundle -> evidence.
24. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_payload_lease.lua` (lines 1-95) - Payload lease construction/validation.
25. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` (lines 1-220, 1080-1147) - `LuaSrc.Window + LuaFact.Evidence -> LuaExec.Kernel/Module`.
26. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_lalin_cfg_lower.lua` (lines 1-220, 1110-1158) - Mechanical `LuaExec -> LalinCFG`.
27. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua` (lines 1-140) - Region taxonomy and supported/unsupported status.
28. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_static_region_model.lua` (lines 1-140) - Static-region validation/composition gates.
29. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_call_static_model.lua` (lines 1-80) - Strict evidence-backed source `CALL` slice.
30. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_closure_static_model.lua` (lines 1-80) - Strict evidence-backed source `CLOSURE` slice.
31. `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_cfg_abi.lua` (lines 1-27) - Typed parameter helpers; no `out_tag` ABI.
32. `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_cfg_emit.lua` (lines 1-80, 1570-1593) - LalinCFG -> Lalin source renderer and PVM phase.
33. `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_cfg_validate.lua` (lines 1-80) - LalinCFG structural honesty checks and forbidden strings.
34. `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua` (lines 1-80) - CompileContract structural validation.
35. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua` (lines 1-120) - LuaExec structural CFG validation.
36. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua` (lines 1-80) - LuaRT semantic validation.
37. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_ffi_validate.lua` (lines 1-80) - LuaFFI structural validation.
38. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_gc_validate.lua` (lines 1-80) - LuaGC structural validation.
39. `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_validate.lua` (lines 1-120) - Stencil artifact validation and old-string rejection.
40. `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_materialization_plan.lua` (lines 1-115) - Stencil variant/template ASDL builders.
41. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_foundry.lua` (lines 1-555) - Offline enumeration, compile, representative dedupe, artifact writing.
42. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-46) - Maintained LuaCompile foundry worker.
43. `experiments/lua_interpreter_vm/tools/sponjit_shadow/README.md` (lines 1-14) - Shadow tools explicitly not architecture source.
44. `experiments/lua_interpreter_vm/tools/sponjit_shadow/stencils/README.md` (lines 1-16) - Shadow stencil tooling explicitly not current contract.
45. `experiments/lua_interpreter_vm/tools/jit_harness/README.md` (lines 1-28) - Harness is source-window/profile utility, not architecture source.
46. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-13) - PUC bytecode role.
47. Tests:
    - `tests/test_spongejit_lua_compile_schema.lua` (lines 1-202)
    - `tests/test_spongejit_lua_compile_pipeline.lua` (lines 1-57)
    - `tests/test_spongejit_lua_compile_pvm_boundaries.lua` (lines 1-166)
    - `tests/test_spongejit_lua_compile_semantic_gates.lua` (lines 1-104)
    - `tests/test_spongejit_lua_compile_foundry.lua` (lines 1-78)
    - `tests/test_spongejit_lua_compile_completion.lua` (lines 1-63)
    - `tests/test_spongejit_lua_compile_corpus100.lua` (lines 1-91)
    - `tests/test_spongejit_lua_compile_stencil.lua` (lines 1-120)

## Key Code

### Governing AGENTS files

```text
find AGENTS.md:
AGENTS.md
museum/gps.lua/AGENTS.md
```

For the target subtree, only these govern by ancestry/context:

- `/home/cedric/.pi/agent/AGENTS.md` - global harness rules.
- `/home/cedric/dev/lalin/AGENTS.md` - project root rules.

`museum/gps.lua/AGENTS.md` is not under/above `experiments/lua_interpreter_vm/spongejit/lua_compile`.

### Current architecture direction

`experiments/lua_interpreter_vm/README.md` lines 7-14:

```text
Lua bytecode / trace windows
→ LuaSrc + LuaFact
→ LuaRT / LuaExec semantic ASDL
→ LalinCFG ASDL
→ Stencil ASDL backend artifacts
→ Lalin-native fact collection, selection, copy/patch materialization
→ executable native fast paths
```

`SPONJIT_ARCHITECTURE.md` lines 8-17 adds `CompileContract`:

```text
LuaSrc / LuaFact
→ LuaRT / LuaExec semantic ASDL
→ CompileContract ASDL
→ LalinCFG ASDL
→ Stencil ASDL backend artifacts
...
Accepted kernels are LuaExec-derived `LalinCFG.Kernel` products with `CompileContract` obligations.
```

Retired assumptions in `SPONJIT_ARCHITECTURE.md` lines 29-41:

```text
- protocol exits as successful lowering completion;
- semantic `out_tag` ABI as accepted execution;
- external semantic fallback or handoff;
- descriptor-bank compatibility names;
- opcode-shaped stencil keys;
- tests that treat compiler rejection as success for valid Lua behavior.
```

### ASDL schema modules

`experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` module boundaries:

```text
20:   module LuaSrc
139:  module LuaRegion
170:  module LuaFact
264:  module LuaFFI
534:  module LuaRT
1128: module LuaGC
1393: module LuaExec
1753: module CompileContract
1823: module LalinCFG
2038: module Stencil
2280: module LuaCompile
```

Doctrine lines 6-17:

```asdl
--   LuaSrc          answers: what did PUC encode?
--   LuaEvidence     answers: what did runtime/foundry prove and lease?
--   LuaFFI          answers: what Lua-visible C FFI declarations/types/values/facts exist.
--   LuaGC           answers: what explicit Lua GC objects/state/control facts exist.
--   LuaRT           answers: what Lua runtime semantic objects/state exist.
--   LuaExec         answers: what explicit semantic Lua CFG is executed over LuaRT.
--   CompileContract answers: what executable-route obligations/facts/invalidation assumptions are attached.
--   LalinCFG         answers: what explicit Lalin CFG is emitted.
--   Stencil         answers: what typed copy-and-patch backend artifact is materialized from LalinCFG.
```

### PVM phase usage

`grep pvm.phase` found these current PVM boundaries in `lua_compile/`:

```text
lua_src_from_puc_decode.lua:165       spongejit_lua_src_decode_event
lua_src_window_collect.lua:49         spongejit_lua_src_collect_window
lua_fact_from_runtime_observe.lua:230 spongejit_lua_fact_import_evidence
lua_compile_unit.lua:14               spongejit_lua_compile_unit_from_inputs
lua_src_to_lua_exec_lower.lua:1108    spongejit_lua_src_to_lua_exec_lower
lua_exec_to_lalin_cfg_lower.lua:1116   spongejit_lua_exec_to_lalin_cfg_lower
lua_exec_to_lalin_cfg_lower.lua:1125   spongejit_lua_exec_module_to_lalin_cfg_lower
lua_exec_static_region_inline.lua:189 spongejit_lua_exec_static_region_inline
lua_compile_to_lalin_kernel.lua:87     spongejit_lua_compile_to_lalin_kernel
lalin_cfg_emit.lua:1579                spongejit_lalin_cfg_emit
lalin_cfg_key.lua:32                   spongejit_lalin_cfg_key
compile_contract_key.lua:43           spongejit_compile_contract_key
stencil_key.lua:113/118/123/128       semantic/variant/template/representative keys
stencil_materialization_plan.lua:57   spongejit_stencil_variant_for_kernel
stencil_materialize.lua:426           spongejit_stencil_materialize_template
stencil_bundle.lua:170/175            stencil bundle materialization
lua_src_call_static_model.lua:203     source CALL products
lua_src_closure_static_model.lua:110  source CLOSURE products
```

### Public compile route

`lua_compile_to_lalin_kernel.lua` lines 70-82:

```lua
-- Accepted LalinKernel compilation has one executable route:
-- LuaSrc.Window -> LuaExec.Kernel/LuaExec.Module -> LalinCFG.Kernel.
-- LuaExec.Module is typed static region composition inlined before LalinCFG;
-- unsupported source windows return diagnostics with no fallback.
local exec_product, exec_errors = LuaExecLower.lower(unit.source, unit.evidence)
...
local cfg_kernel, cfg_errors = lower_exec_to_cfg(exec_product)
...
return T.LuaCompile.Ok(T.LuaCompile.LalinKernel(cfg_kernel))
```

### Current strict source CALL/CLOSURE gates

`lua_src_call_static_model.lua` lines 1-7:

```lua
-- strict evidence-backed source CALL slice.
-- ... accepts fixed-shape direct Lua-closure calls only when typed payload leases carry
-- the closure/proto identity and static callee LuaExec.Region binding.
-- It does not dispatch to the VM, synthesize helper calls, or accept dynamic/metamethod/C/FFI targets.
```

`lua_src_closure_static_model.lua` lines 1-7:

```lua
-- strict evidence-backed source CLOSURE slice.
-- ... accepts only typed no-upvalue Lua closure values with a proven direct Lua closure target,
-- static callee binding, and successful GC allocation effect.
```

### Makefile current/retired targets

`Makefile` lines 1-5:

```make
# Maintained offline foundry artifacts are LalinCFG + CompileContract +
# Stencil.VariantKey representatives. The old SSA/stencil/sponbank path is
# quarantined historical material and is not a maintained build/test path.
```

`Makefile` lines 18-23:

```make
# Main test is the current honest implemented-slice gate.
# Completion/corpus gates are opt-in targets.
test: test-lua-compile test-lua-compile-foundry no-old-imports
```

`Makefile` lines 51-55:

```make
# Retired old-runtime targets. They intentionally fail instead of silently
# rebuilding quarantined descriptor/bank/materializer artifacts.
bank test-bank test-c-interp probe play-bytecode bench-l1-fusion bench-puc-span bench-function:
	@printf '%s\n' 'ERROR: $@ belongs to the retired SSA/stencil/sponbank runtime path.' >&2
```

### Tests assert old names are gone

`test_spongejit_lua_compile_pipeline.lua` lines 40-56 lists exactly 59 planned files under `lua_compile/` and rejects names matching:

```lua
lua_sem
lua_nf
lua_contract
lua_place
normal_form
lalin_cfg_closed
ssa2
```

`test_spongejit_lua_compile_schema.lua` lines 15-18:

```lua
assert(not T["Lua" .. "Sem"] and not T["Lua" .. "NF"] and not T["Lua" .. "Contract"] and not T["Lua" .. "Place"])
```

`test_spongejit_lua_compile_foundry.lua` lines 5-9:

```lua
assert(package.loaded["src.ssa"] == nil)
assert(package.loaded["src.ssa_ir"] == nil)
assert(package.loaded["src.ssa_to_stencil"] == nil)
assert(package.loaded["src.stencil_lower"] == nil)
```

### Stale workflow reference

`SPONJIT_ARCHITECTURE.md` line 26 calls `.pi/workflows/wf-b7b79a56.md` “Live curated no-interpreter design workflow and implementation plan.”

But `.pi/workflows/wf-b7b79a56.md` lines 13-20 reference now-absent old files:

```text
lua_compile_to_normal_form.lua
lua_src_to_lua_sem_lower.lua
lua_sem_to_lua_nf_normalize.lua
lua_nf_to_lua_contract_derive.lua
lua_nf_to_lalin_out_lower.lua
lalin_out_abi.lua
lalin_out_emit.lua
lalin_out_validate.lua
```

`find` returned no current files matching `*normal_form*.lua`, `*lua_sem*.lua`, `*lua_nf*.lua`, or `*lalin_out*.lua` under `spongejit/lua_compile`.

## Relationships

Current maintained data flow:

```text
PUC/full operand events
  -> lua_src_from_puc_decode.lua
  -> lua_src_window_collect.lua
  -> LuaSrc.Window

plain observations / foundry bundles
  -> lua_fact_from_runtime_observe.lua / lua_fact_from_foundry_bundle.lua
  -> LuaFact.Evidence

LuaSrc.Window + LuaFact.Evidence
  -> lua_compile_unit.lua
  -> LuaCompile.Unit

LuaCompile.Unit
  -> lua_src_to_lua_exec_lower.lua
  -> LuaExec.Kernel or LuaExec.Module
  -> lua_exec_static_region_inline.lua when module/static regions are involved
  -> lua_exec_to_lalin_cfg_lower.lua
  -> LalinCFG.Kernel + CompileContract.Contract
  -> lalin_cfg_validate.lua / lalin_cfg_emit.lua / lalin_cfg_key.lua
  -> Stencil.VariantKey / StencilTemplate metadata
  -> foundry representative artifacts
```

Foundry artifacts:

```text
opcode windows + fact bundles
  -> lua_compile_foundry.compile_window
  -> LuaCompile.Unit
  -> LalinCFG.Kernel
  -> CompileContract key
  -> Stencil.VariantKey
  -> representative key = LalinCFG + CompileContract + Stencil.VariantKey
  -> JSON/Markdown artifacts
```

Tests divide current scope:

- `make test` runs implemented-slice LuaCompile tests, foundry test, and no-old-import checks.
- `test-completion` is stricter opt-in future completeness gate and must not treat rejection as success.
- `test-lua-compile-corpus100` requires built corpus artifacts and checks full operand windows plus no stale artifact schema.

## Observations

- Only root `AGENTS.md` governs the target subtree; there is no nested `AGENTS.md` under `experiments/`.
- Root `AGENTS.md` is broad Lalin guidance and does not mention `experiments/lua_interpreter_vm/spongejit/lua_compile`.
- Current code no longer has `LuaSem`, `LuaNF`, `LuaContract`, `LuaPlace`, `LalinOut`, or `NormalForm` files/types in `lua_compile/`; tests assert their absence.
- Current final accepted compiler product is `LuaCompile.Ok(LuaCompile.LalinKernel(LalinCFG.Kernel))`, not `NormalForm` or `LalinOut`.
- `out_tag`/`out_event_kind` appear only in guardrails/tests/validators as forbidden strings, not as accepted ABI.
- `spongejit/src/` now contains corpus/profile utilities plus `worker_compile.lua`; old `ssa*.lua`, `stencil*.lua`, and bank builder files are absent there.
- `spongejit/include/` and `spongejit/runtime/` are empty.
- `build_stencils.sh`, `make stencils`, `make bank`, and related targets intentionally fail as retired old path names.
- Shadow tooling under `tools/sponjit_shadow/` remains in repo but README files explicitly say it is not current architecture/contract source.
- There is mixed spelling in docs/comments: current docs often say “SpongeJIT”; older/local names and artifact schemas still use `SponJIT`/`sponjit` (`VM_CONTRACT.md`, `Makefile`, schema strings).
