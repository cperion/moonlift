## SponJIT Measurement Harness (planned)

Real measurement, not estimates. Instruments PUC Lua with rdtsc.

### Approach

1. Compile PUC Lua with a thin instrumentation layer
2. Each bytecode region can be hot-patched: insert a pre/post rdtsc probe
3. The probe records: opcodes visited, cycles elapsed, exits taken
4. When an artifact template is candidate, inject it into the region
5. Compare artifact cycles vs interpreter cycles on the same workload
6. Feed real speedup back to foundry selection

### Build plan

```sh
# 1. Build PUC Lua with instrumentation
cd vendor/lua && make MYCFLAGS="-DSPONJIT_INSTRUMENT"

# 2. Run the benchmark
luajit bench/measure.lua --artifact-pack build/artifact_pack.json --workload AWFY
```

### Measurement loop

```text
for each hot bytecode region:
    measure_baseline(region)      → baseline_cycles
    for each candidate artifact:
        inject(artifact, region)
        measure_artifact(region)  → artifact_cycles
        speedup = baseline_cycles / artifact_cycles
        record(candidate, speedup)
    select best per region
```

### What to measure

- Cycles per opcode-equivalent (rdtsc deltas)
- Guard exit rate (how often assumptions fail)
- Cache behavior (i-cache and d-cache misses via perf counters)
- Projection cost (time spent reconstructing state on exit)
- Total artifact bytes loaded (memory pressure)

### Status

Not yet implemented. The foundry currently uses the stencil cost model
(instruction count × cycle estimate) as a proxy. Real measurement requires
building an instrumented PUC Lua with artifact injection hooks.
