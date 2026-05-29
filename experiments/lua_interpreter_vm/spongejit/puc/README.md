# PUC Lua ↔ SponBank benchmark

This directory now contains only the current benchmark path.

The old patched-VM cache benchmark was removed because it targeted the pre-bank
`SponJitCacheDesc` pipeline and did not use `build/cp_lib/libsponbank.so`. It
could report VM probe overhead, but not current copy-and-patch JIT behavior.

Selector/materializer benchmark:

```sh
luajit experiments/lua_interpreter_vm/spongejit/puc/bench_sponbank_puc.lua \
  --build \
  experiments/lua_interpreter_vm/spongejit/bench/programs/int_loop.lua \
  50000000
```

It measures:

1. normal execution of the Lua program on vendored PUC Lua 5.5 via `liblua.a`;
2. extraction of the program's real PUC opcodes from its `Proto` tree;
3. current `libsponbank.so` greedy selection over those opcode streams;
4. copy/patch materialization using real `SponHoleReloc` metadata.

Minimal semantic execution proof:

```sh
luajit experiments/lua_interpreter_vm/spongejit/puc/bench_execute_tile.lua \
  --build \
  100000000 \
  UNM,BNOT,MUL,ADDI
```

This selects one real aggregate tile from `libsponbank.so`, mmap/copies it,
patches its relocation holes, executes it on PUC-compatible `TValue` slots, and
compares per-op throughput against vendored PUC Lua running a loop with the same
static opcode mix.

Current observed mixed-pattern results on this machine:

```text
UNM,BNOT,MUL,ADDI      ~0.67 ns/op, ~2.4x PUC
UNM,LOADI,ADDI,ADD     ~0.62 ns/op, ~2.4x PUC
ADDI,MUL,LOADI,SUB     ~0.55 ns/op, ~2.7x PUC
MOVE,UNM,ADD,ADDI      ~0.60 ns/op, ~2.6x PUC
LOADI,ADDI,LOADI,BNOT  ~0.49 ns/op, ~2.8x PUC
```

This executes one semantic aggregate tile, not a full stitched VM image yet.

Real PUC VM integration path:

```sh
# requires a bank rebuilt with current src/worker_compile.lua + src/build_bank.lua
luajit experiments/lua_interpreter_vm/spongejit/puc/build_puc_sponjit.lua
SPONJIT_ENABLE=1 \
  experiments/lua_interpreter_vm/spongejit/build/puc_sponjit/lua \
  experiments/lua_interpreter_vm/spongejit/bench/programs/int_loop.lua \
  1000000
```

This path patches the vendored PUC build with `Proto->sponjit`, frees image state
from `luaF_freeproto`, enters through a real `lvm.c` region hook, uses
`spon_select_flow*` so tile contracts propagate
`required/checked/produced/killed` facts across the image cover, materializes tiles
through `SponHoleReloc` plus `SponSlotMapEntry`, and executes the resulting
`SponImage` via the structured `SponExecCtx` stencil ABI. Runtime still does not run
SSA or generate code; it selects, copy-patches, executes, and exits/demotes.

Current app-local counted-loop measurement with a tiny bank for
`mixed_tile_hack.lua` (`UNM,BNOT,MUL,ADDI` body + `FORLOOP` tail):

```text
100M iterations:
  PUC baseline:       ~0.62s
  SponJIT image:      ~0.32s  (~1.9x)
  counters: probes=345 build_attempts=1 builds=1 entries=1 completions=1 exits=0

500M iterations:
  PUC baseline:       ~3.11s
  SponJIT image:      ~1.64s  (~1.9x)
```

The important distinction from the old hack is that the VM enters the active image
once at the loop-body region and the image driver owns the counted-loop backedge;
it does not call a tile from interpreter dispatch every iteration.

Legacy narrow PUC VM image-entry hack:

```sh
luajit experiments/lua_interpreter_vm/spongejit/puc/build_puc_bank_hack.lua
SPONBANK_HACK_ENABLE=1 SPONBANK_HACK_IMAGE=1 \
  experiments/lua_interpreter_vm/spongejit/build/puc_bank_hack/lua \
  experiments/lua_interpreter_vm/spongejit/bench/programs/mixed_tile_hack.lua \
  100000000
```

This narrow hack recognizes the hot loop body
`UNM,BNOT,MUL,MMBIN,ADDI,MMBINI`, enters once at the region body, executes the
selected SponBank tile inside a native counted-loop driver, simulates `FORLOOP`,
and returns after the loop. It is deliberately not a general VM integration, but it
matches the runtime-design rule: **enter an image once for a hot region, not one
bank tile per interpreter dispatch**.

Observed on this machine:

```text
100M iterations:
  PUC baseline:        ~0.62s
  dispatch tile call:  ~0.70s  (bad: per-iteration dispatch/call overhead)
  image-entry hack:    ~0.40s  (~1.55x)

500M iterations:
  PUC baseline:        ~3.10s
  image-entry hack:    ~1.97s  (~1.57x)
```
