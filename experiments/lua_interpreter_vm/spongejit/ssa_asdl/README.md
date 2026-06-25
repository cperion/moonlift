# SpongeJIT ASDL Vocabulary

This folder contains the ASDL vocabulary for SpongeJIT's explicit semantic
compiler path.

Primary schema:

- `spongejit_lua_ssa.asdl`

Design authority:

- `explicit_programming.md`
- `PVM_GUIDE.md`
- `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md`
- `experiments/lua_interpreter_vm/SPONJIT_LALIN_COPY_PATCH_DESIGN.md`
- `experiments/lua_interpreter_vm/SPONJIT_FFI_DESIGN.md`
- `experiments/lua_interpreter_vm/SPONJIT_GC_DESIGN.md`

Core rule:

```text
Source mechanics are consumed into explicit semantic types.
Semantic choices become ASDL/LalinCFG structure.
Stencil artifacts are generated from semantic CFGs and contracts.
Runtime materialization is semantics-blind copy/patch/publish.
```

Layer questions:

| Module | Question |
|---|---|
| `LuaSrc` | What did PUC encode? |
| `LuaFact` | What evidence/facts/payload leases are available? |
| `LuaRT` / `LuaExec` | What Lua runtime semantics and control states are represented? |
| `CompileContract` | What executable-route obligations, guarantees, and invalidation assumptions are attached? |
| `LalinCFG` | What explicit Lalin-compatible CFG is emitted? |
| `Stencil` | What compiled artifact, patch holes, relocs, and bank keys are produced? |
| `LuaCompile` | What compile product is produced? |

Guardrails:

- No opcode-shaped final IR.
- No protocol `out_tag` accepted execution path.
- No hidden external semantic handoff.
- No strings or magic integers for semantic distinctions.
- Facts specialize semantics; facts do not replace semantics.
- Stencil metadata describes bytes/holes/relocs, not Lua behavior.
