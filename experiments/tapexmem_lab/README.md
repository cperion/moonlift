# Tape × Memory Product-Space Lab

This folder is a focused experiment for the Moonlift runtime shape idea:

- **Every executed op has two projections**:
  1. **Tape projection** (record / fold / optimization facts)
  2. **Memory projection** (concrete VM + heap mutation)
- **GC and optimization share one fact stream** gathered at execution time.
- The runtime maintains **invariants in the product space** `Tape × Mem`.

## Files

- `product_space_experiment.lua` — runnable Lua prototype of dual-projection execution.
- `product_space_machine_eval.mlua` — Moonlift machine-shape prototype (regions + jumps), evaluated via `Host.eval`.

## Run

```bash
# Pure Lua prototype
luajit tapexmem_lab/product_space_experiment.lua

# Moonlift prototype (force Cranelift backend)
MOONLIFT_BACKEND=cranelift \
luajit -e 'package.path="./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;"..package.path; dofile("experiments/tapexmem_lab/product_space_machine_eval.mlua")'
```

## Core invariants in this experiment

1. **Slot coherence**: current memory slot values agree with replaying the tape prefix.
2. **GC soundness**: no reachable object is swept.
3. **Fold safety**: folded/elided tape ops must preserve memory projection.

This is intentionally small and brutalist: the goal is to discover the right machine shape, not polish APIs yet.
