# SpongeJIT Architecture

## Current direction

SpongeJIT is moving to an explicit-programming pipeline:

```text
LuaSrc / LuaFact
→ LuaRT / LuaExec semantic ASDL
→ CompileContract ASDL
→ LalinCFG ASDL
→ Stencil ASDL backend artifacts
→ Lalin-native fact collection, selection, copy/patch materialization
→ executable native fast paths
```

Accepted kernels are LuaExec-derived `LalinCFG.Kernel` products with `CompileContract` obligations. They must not carry retired executable payloads, semantic `out_tag` protocol ABI, or interpreter handoff exits.

## Current design documents

| Document | Purpose |
|---|---|
| `SPONJIT_LALIN_COPY_PATCH_DESIGN.md` | Lalin-native fact collector, selector, stencil bank, and copy/patch executor. |
| `SPONJIT_FFI_DESIGN.md` | First-class LuaJIT-quality FFI design. |
| `SPONJIT_GC_DESIGN.md` | First-class GC, barriers, finalizers, facts, and stencil integration. |
| `.pi/workflows/wf-b7b79a56.md` | Live curated no-interpreter design workflow and implementation plan. |
| `spongejit/ssa_asdl/spongejit_lua_ssa.asdl` | Current ASDL vocabulary source. |

## Retired assumptions

The following are obsolete and must not be treated as current design:

- protocol exits as successful lowering completion;
- semantic `out_tag` ABI as accepted execution;
- external semantic fallback or handoff;
- descriptor-bank compatibility names;
- opcode-shaped stencil keys;
- tests that treat compiler rejection as success for valid Lua behavior.

The retained goal is copy-and-patch, but with stencils generated mechanically
from ASDL semantic CFGs and contracts, not from opcode/protocol descriptors.
