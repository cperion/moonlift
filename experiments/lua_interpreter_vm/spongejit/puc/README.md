# SponJIT PUC Lua measurement harness

Builds a vanilla PUC Lua and a SponJIT-instrumented PUC Lua from tracked
`.vendor/Lua` sources.

```sh
luajit experiments/lua_interpreter_vm/spongejit/puc/build_sponjit_puc.lua
# or
cd experiments/lua_interpreter_vm/spongejit && make puc-build
```

Outputs:

```text
experiments/lua_interpreter_vm/spongejit/build/puc_baseline/lua
experiments/lua_interpreter_vm/spongejit/build/puc_sponjit/lua
```

## Runtime controls

- `SPONJIT_ENABLE=1` — enable SponJIT probe/scanner path
- `SPONJIT_STATS=/path` — dump counters
- `SPONJIT_PRINT=1` — print counters at exit
- `SPONJIT_UNSAFE_EXECUTE=1` — allow execution of cache files generated with `--allow-unsafe`
- `SPONJIT_TRACE=1` — print the first cache-entry executions for debugging

`SPONJIT_UNSAFE_EXECUTE` is intentionally separate. The safe generator emits
only opcode-complete chains. Raw foundry chains can still be emitted for
research with `--allow-unsafe`, but those require the explicit runtime opt-in.

## Cache data

`puc/build_cache.lua` emits `build/sponjit_cache_data.c`.

Default mode is safe: it emits only generated chains with a known executable
PUC opcode contract. Currently implemented executable families include integer
`ADDI+MMBINI` and `ADD/SUB/MUL+MMBIN` fast paths plus simple value movement and
constant stores when found as complete single-op forms. Use `--allow-unsafe`
only to inspect/reproduce raw foundry output.

The last full unsafe corpus snapshot is preserved as:

```text
experiments/lua_interpreter_vm/spongejit/build/sponjit_cache_data.unsafe_full.c
```

## Benchmark

```sh
luajit experiments/lua_interpreter_vm/spongejit/puc/bench_compare.lua \
  --reps 5 -- experiments/lua_interpreter_vm/spongejit/bench/programs/int_loop.lua 100000000
```

Current safe runtime reports correct output and real cache hits for executable
integer arithmetic forms present in the selected corpus. With the current
`lua/moonlift` training corpus, safe generation emits four `ADDI+MMBINI` native
cache entries.
