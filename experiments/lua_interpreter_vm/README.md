# Lua VM + SpongeJIT Experiment

This directory contains the Lalin-native Lua VM experiment and SpongeJIT, a
semantic compiler/foundry for generating native Lua fast paths.

## Current direction

```text
Lua bytecode / trace windows
→ LuaSrc + LuaFact
→ LuaRT / LuaExec semantic ASDL
→ LalinCFG ASDL
→ Stencil ASDL backend artifacts
→ Lalin-native fact collection, selection, copy/patch materialization
→ executable native fast paths
```

The design goal is explicit Lua semantics first, then efficient generated
copy-and-patch stencils. Runtime materialization is semantics-blind: it selects
by typed facts/contracts/CFG keys, copies bytes, patches typed holes, resolves
relocations, and publishes executable code.

## What is here

```text
experiments/lua_interpreter_vm/
├── src/                         Lalin Lua VM implementation work
├── tests/                       standalone Lua/Lalin tests
├── benchmarks/                  VM and SpongeJIT benchmarks
├── spongejit/                   SpongeJIT ASDL/LalinCFG/stencil compiler work
│   ├── lua_compile/             maintained LuaCompile pipeline
│   ├── ssa_asdl/                ASDL schema
│   ├── src/                     corpus/profiling bridge utilities
│   └── Makefile                 test/foundry entry point
├── tools/                       bytecode/corpus/shadow tools
├── SPONJIT_ARCHITECTURE.md      current architecture map
├── SPONJIT_LALIN_COPY_PATCH_DESIGN.md
├── SPONJIT_FFI_DESIGN.md
├── SPONJIT_GC_DESIGN.md
└── VM_CONTRACT.md
```

## Tests

VM tests are standalone, for example:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

SpongeJIT tests:

```sh
cd experiments/lua_interpreter_vm/spongejit
make test
make lua-compile-foundry
make test-lua-compile-corpus100
```

`make test` is for the currently implemented honest scope. Completion gates for
future generic Lua behavior must stay positive-only: valid behavior either works
or the gate is red.

## Current design documents

| File | Purpose |
|---|---|
| `SPONJIT_ARCHITECTURE.md` | Current high-level map and guardrails. |
| `SPONJIT_LALIN_COPY_PATCH_DESIGN.md` | Lalin-native fact collector, selector, stencil bank, copy/patch executor. |
| `SPONJIT_FFI_DESIGN.md` | First-class LuaJIT-quality FFI design. |
| `SPONJIT_GC_DESIGN.md` | First-class GC, barriers, finalizers, facts, and stencil integration. |
| `spongejit/ssa_asdl/spongejit_lua_ssa.asdl` | Current ASDL vocabulary source. |
| `VM_CONTRACT.md` | VM contract notes. |

## Guardrails

- Lua semantics belong in explicit ASDL / LalinCFG / Lalin regions.
- Copy-and-patch stencils are backend artifacts derived from semantic CFGs.
- Stencil keys, holes, and relocations must not encode hidden Lua behavior.
- Runtime selector/materializer must not inspect opcode semantics.
- No protocol `out_tag` accepted execution path.
- No rejection-as-success tests for valid Lua behavior.
- FFI and GC are first-class typed subsystems, not side helpers.
