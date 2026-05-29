# SponJIT — A Fact-Guided Bytecode Absorption JIT

The "sponge JIT": soaks up hot interpreter work in contiguous patches and leaves
the rest as residual.

```text
Offline foundry enumerates → builds a read-only bank of TileTemplates.
Runtime selects from the bank → copy-patches into executable Images.
```

**Type:** JIT architecture + prototype for a PUC Lua 5.5 register-bytecode VM.  
**Status:** foundry builds real binary stencils (~472K, 7.8 MB .text across 16 CPU cores).  
Runtime selection mechanism: design-complete (see architecture docs).

---

## Project structure

```
experiments/lua_interpreter_vm/
├── SPONJIT_ARCHITECTURE.md      — The thesis: absorption, seam tax, two-pointer runtime
├── SPONJIT_FOUNDRY_SSA.md       — Offline foundry: grammar enumeration, SSA lowering, bank
├── SPONJIT_RUNTIME_DESIGN.md    — Runtime: two-pointer selector, hysteresis, multimorphism
├── README.md                    — This file
│
├── src/                         — Lua VM interpreter source
│   ├── vm_loop.lua              — Main interpreter loop
│   ├── opcodes.lua              — Opcode definitions and decoder
│   └── ...
│
├── spongejit/                   — JIT foundry + runtime prototype
│   ├── src/
│   │   ├── grammar_enum.lua     — Grammar-driven opcode enumeration (472K sequences)
│   │   ├── ssa.lua              — SSA lowering facade
│   │   ├── ssa_lift.lua         — Bytecode → SSA IR
│   │   ├── ssa_ir.lua           — SSA node types
│   │   ├── ssa_opt.lua          — 2 SSA passes (frame_forward, guard_dominance)
│   │   ├── ssa_to_c.lua         — SSA → C with extern-symbol HOLEs
│   │   ├── facts.lua            — Type/shape fact model
│   │   ├── fact_schema.lua      — Fact schema definitions
│   │   ├── stencil_model.lua    — Stencil cost model
│   │   └── util.lua             — JSON I/O, helpers
│   ├── build/
│   │   └── cp_lib/              — Stencil library output
│   ├── build_stencils.sh        — Build the complete stencil library
│   ├── puc/                     — PUC Lua 5.5 integration
│   └── tests/                   — SSA/stencil tests
│
├── tools/                       — Analysis and shadow validation
│   └── sponjit_shadow/          — Shadow simulator (experimental)
│
├── tests/                       — VM tests (~130 scripts)
└── benchmarks/                  — Performance benchmarks
```

---

## Architecture in one screen

The engine has two components separated by a build step:

```text
OFFLINE (foundry):
  grammar enumeration (arity≤4, 40 opcode categories)
  → fact combination powerset per sequence
  → SSA lowering (2 passes: frame_forward, guard_dominance)
  → C codegen with extern-symbol HOLEs
  → GCC -O2 compile
  → extract .text + HOLE relocations
  → read-only bank file

RUNTIME (two-pointer selector):
  region: [floor pointer] [active pointer] [hysteresis counter]
  floor = always-correct L0 image (composed from bank L0 tiles)
  active = currently-selected image (may equal floor)
  
  observe facts → canonicalize → bank lookup → copy/patch → atomic swap
  on guard failure: project state, fall to floor
  on persistent failure: demote to floor, log for next training run
```

---

## Bank layers

Two layers cover the full enumeration:

| Layer | Arity | Facts | Coverage |
|-------|-------|-------|----------|
| **L0** | 0 | none | Every valid PUC Lua 5.5 opcode (40 categories by instruction format). Generic, always correct. The floor source. |
| **L1** | 1–4 | all fact combinations | Every valid opcode sequence up to arity 4, specialized under every applicable fact combination. The complete bank. |

The enumeration is flat: L1 covers all fact-specialized sequences exhaustively. No
recursive layers (L2, L3) are needed — the flat enumeration already contains every
fusion up to arity 4 under every fact set the foundry can produce.

A multimorphic directory (LM) may be added in the future for fact-env unions observed
in corpus pressure, but is not yet enumerated.

---

## Build the stencil library

```sh
cd spongejit
./build_stencils.sh                    # defaults to $(nproc) workers
N=8 ./build_stencils.sh                # override worker count
```

The pipeline:

1. Grammar enumeration — 472,000 valid opcode sequences (arity 1–4, 40 categories)
2. SSA compile + C codegen — 16 parallel workers via xargs -P
3. GCC compile — 16 parallel workers, each ~4 MB .o → ~88 KB .text
4. Extract metrics — stencil count, bytes, HOLE relocations

Current measured output:

| Metric | Value |
|--------|-------|
| Total stencils | **471,976** |
| Real stencils (>5 B) | 127,565 |
| Tiny stencils (≤5 B) | 344,411 |
| Total .text | **7.8 MB** |
| Real machine code | 7.3 MB |
| Avg real stencil | 58 bytes |

---

## Key numbers

| Number | Meaning |
|--------|---------|
| 40 | Opcode categories by instruction format (iABC, ivABC, iABx, iAsBx, iAx, isJ) |
| 4 | Maximum arity of fused sequences |
| 472,000 | Valid opcode sequences (arity 1–4, after handler equivalence dedup) |
| 471,976 | Equivalence classes that produced stencils (~100% coverage) |
| 127,565 | Stencils with real machine code (>5 bytes) |
| 7.3 MB | Machine code for all real stencils |
| 16 | Parallel workers (xargs -P) |
| 2 | SSA passes (frame_forward, guard_dominance) |
| 24 | HOLE extern symbols (`__H_0` to `__H_23`) |

---

## Design vocabulary

```text
TileTemplate   prebuilt stencil in the bank (bytes, HOLEs, contract, exits)
Image          runtime materialized cover of a region (copy-patched tiles)
Floor          always-installed L0 image (all-opcode generic tiles)
Active         currently-selected image (may use higher-arity tiles)
L0             generic per-opcode stencil (arity 0, no facts, always legal)
L1             fact-specialized stencil (arity 1–4, all fact combinations)
LM             multimorphic tile (future: internal discriminator for stable polymorphism)
Seam tax       cost of a boundary between a specialized tile and an L0 tile
               (makes islands grow by accretion, never fragment)
Hysteresis     integer counter that gates re-selection to prevent oscillation
Guard          operation that buys absorbability by spending an exit
Residual       unabsorbed bytecode → L0 tile in the image (priced, first-class)
Bank           read-only library of TileTemplates (offline-built, mmap'd at startup)
```

---

## Key documents

| Document | Content |
|----------|---------|
| `SPONJIT_ARCHITECTURE.md` | Full thesis: absorption as dual of covering, seam tax, two-pointer runtime, multimorphism, worked examples |
| `SPONJIT_FOUNDRY_SSA.md` | Foundry design: grammar enumeration, SSA as offline fact-consuming layer, bank construction |
| `SPONJIT_RUNTIME_DESIGN.md` | Runtime design: two-pointer selector, hysteresis, bank miss as megamorphic cutoff, exits as cross-run training signal |

---

## Relation to existing JITs

```text
                    tile granularity
  small ─────────────────────────────────────────────► large
    │                                                       │
   interpreter ─── baseline JIT ───────── trace JIT (LuaJIT)
   (all-L0         (one tile per op,      (one trace per region,
    image)          no runtime selection)   zero residual by fiat)
    │
    └────────────────── SPONJIT ──────────────────┘
      (window tiles arity≤4, retile>0, priced L0 residual)
```

LuaJIT's defining limit: no concept of an acceptable residual. SponJIT's first-class
L0 residual is the axis LuaJIT lacks — mixed images are a stable steady state.

---

## Core invariants

- **Bank is read-only** at runtime. The foundry is the only thing that writes it.
- **Runtime never compiles.** It selects, copies, patches, and swaps.
- **Floor is always installed.** Every region starts with an all-L0 image.
- **A guard failure is not a failure.** It is a demand signal for the next foundry run.
- **Exits are cross-run training,** not within-run code triggers.
- **Multimorphism is a tile shape,** not a runtime cache.
- **A propagated fact is a hole value.** Fact propagation and materialization are the same operation.
- **Enumeration is flat.** L1 covers all fact-specialized sequences exhaustively. No recursive layers.
