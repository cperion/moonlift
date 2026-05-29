# Lua Interpreter VM Experiment

This directory contains the Moonlift-hosted Lua interpreter VM experiment and a separate SpongeJIT foundry prototype.

Important status note: **the interpreter in `src/` is not currently wired to a JIT.** The VM is an interpreter/compiler experiment built out of Moonlift regions. SpongeJIT lives under `spongejit/` as an offline native-fragment foundry prototype; it is not the execution engine for `src/vm_loop.lua` today.

## What is here

```text
experiments/lua_interpreter_vm/
├── src/                         Moonlift Lua VM/interpreter implementation
│   ├── init.lua                 module loader
│   ├── constants.lua            tags, opcodes, error/status constants
│   ├── products.lua             runtime data layouts
│   ├── opcodes.lua              Lua 5.5-style bytecode dispatch regions
│   ├── op_handlers.lua          opcode handler descriptions/templates
│   ├── vm_loop.lua              interpreter loop and entry points
│   ├── regions_*.lua            value/table/call/parser/gc/etc. regions
│   └── api.lua                  VM API-facing regions
│
├── tests/                       standalone Lua/Moonlift tests for the VM and prototypes
├── benchmarks/                  interpreter and prototype benchmark scripts
│
├── spongejit/                   separate SpongeJIT native-fragment foundry prototype
│   ├── src/                     offline SSA → Stencil IR → fragment metadata pipeline
│   ├── puc/                     status note for removed legacy PUC integration
│   └── Makefile                 SpongeJIT native-fragment test entry point
│
├── tools/                       older/shadow analysis harnesses
│   └── sponjit_shadow/          shadow simulator; not the current bank path
│
├── SPONJIT_ARCHITECTURE.md      conceptual SpongeJIT design notes
├── SPONJIT_FOUNDRY_SSA.md       historical/current foundry notes
└── SPONJIT_RUNTIME_DESIGN.md    runtime design notes, partly aspirational
```

## Current status

### Interpreter VM (`src/`)

The main VM is a Moonlift experiment for implementing Lua runtime structures and bytecode execution as typed regions.

It includes:

- runtime data products/layouts
- value, table, stack, call, closure, upvalue, string, GC, error, parser, and API regions
- opcode dispatch/handler generation
- parser/compiler experiment pieces
- unit/integration tests under `tests/`

It does **not** currently call into SpongeJIT or install native images at runtime.

### SpongeJIT (`spongejit/`)

SpongeJIT is an adjacent prototype for an offline-trained native-fragment catalog.

Current implementation shape:

```text
opcode sequence + fact bundle
→ semantic SSA (`src/ssa_lift.lua`, `src/ssa_ir.lua`, `src/ssa_opt.lua`)
→ hole-parametric Stencil IR (`src/ssa_to_stencil.lua`, `src/stencil_ir.lua`)
→ canonical Stencil IR hash/form (`src/stencil_normalize.lua`)
→ abstract native-fragment descriptors (`src/stencil_to_fragment.lua`)
→ ABI-lowered fragment metadata (`src/fragment_ir.lua`, `include/sponbank.h`)
```

The legacy PUC Lua 5.5 C-function materializer and benchmarks were removed during the native-fragment ABI hard-yank. `spongejit/puc/` now documents that no maintained executable PUC integration exists until a native fragment linker is implemented.

## Running tests

From the repository root:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

SpongeJIT-focused checks:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_retirement.lua
```

The tests are standalone scripts; there is no central test runner in this directory.

## SpongeJIT build notes

From `experiments/lua_interpreter_vm/spongejit/`:

```sh
make test
```

`src/worker_compile.lua` still consumes pre-split `grammar_chunk_N.json` inputs and emits metadata-only `grammar_fragments_N.json` plus `grammar_result_N.json`. There is intentionally no maintained C-function stencil build, generated shared-object bank, or PUC runtime build in this hard-yanked native-fragment foundation.

Useful environment knobs for worker metadata generation include:

```sh
MAX_FACT_COMBOS=32
FACT_AXIS_MODE=curated
WORKER_PROGRESS_SEQS=1000
SPON_TMP=/path/to/chunks-and-output
```

Do not confuse these offline fragment metadata experiments with the Moonlift interpreter VM in `src/`. Building SpongeJIT artifacts does not automatically make `src/vm_loop.lua` JIT-enabled.

## Documentation map

The SpongeJIT documents are design/history documents and may include aspirational runtime pieces. Read status claims carefully.

| File | Purpose |
|---|---|
| `SPONJIT_ARCHITECTURE.md` | Conceptual design: absorption, fragment/template banks, image materialization. |
| `SPONJIT_FOUNDRY_SSA.md` | Foundry/SSA design notes; older sections may still use pre-native-fragment terminology. |
| `SPONJIT_RUNTIME_DESIGN.md` | Runtime selector/materialization design; not the current Moonlift VM runtime. |
| `SPONJIT_COPY_LINK_PATCH.md` | Native fragment ABI direction for copy-link-patch. |
| `spongejit/puc/README.md` | PUC Lua integration status after legacy path removal. |

## Non-goals / warnings

- This directory is not a production Lua implementation.
- The Moonlift interpreter VM and SpongeJIT are not one integrated JIT system today.
- `tools/sponjit_shadow/` is an older shadow harness; do not treat it as the current fragment pipeline.
- Generated fragment metadata under `spongejit/build/` is configuration-dependent and can be removed with `make clean`.
