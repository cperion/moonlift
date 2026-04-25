# Moonlift / Terra comparison benchmarks

This directory is a small, honest benchmark track for comparing the parts of
Moonlift that are already meaningful against Terra.

The current set intentionally uses **scalar kernels only** because Moonlift's
aggregate/slice/view ABI is still being completed. The goal is to compare the
closed path that works today:

```text
Surface source -> Elab -> Sem -> Back -> Cranelift Artifact -> FFI call
```

## Files

- `bench_moonlift.lua` — compiles one Moonlift source module through the normal
  public `moonlift.source` facade and runs exported functions through LuaJIT FFI.
- `bench_terra.t` — equivalent Terra kernels.
- `bench_moonlift_shapes.lua` — Moonlift-only shape comparison: generic scalar
  formulations vs explicit Moonlift constructs such as range domains, `select`,
  and intrinsics.
- `bench_vector_sum.lua` — validates the ASDL vector fact/plan path by lowering
  detected add-reduction, unrolled reduction, and bounded chunked `i32x4`
  reduction plans to explicit vector `Back` commands.
- `bench_vector_sum_terra.t` — Terra side for that vectorization-path check.
- `run_vector_sum_vs_terra.sh` — compares scalar Moonlift, vectorized Moonlift,
  and Terra for the sum-reduction kernel.
- `FINDINGS.md` — current observations from shape runs and codegen inspection.
- `run_vs_terra.sh` — builds the Moonlift Rust shared library, runs both sides,
  and prints a comparison table.

## Run

From the repository root:

```bash
moonlift/benchmarks/run_vs_terra.sh quick
moonlift/benchmarks/run_vs_terra.sh
```

If Terra is not installed, run the Moonlift side alone:

```bash
cargo build --manifest-path moonlift/Cargo.toml --release
luajit moonlift/benchmarks/bench_moonlift.lua quick
```

To check whether Moonlift-specific source shapes help a kernel, run:

```bash
luajit moonlift/benchmarks/bench_moonlift_shapes.lua quick
```

To inspect one shaped function's machine code:

```bash
luajit moonlift/benchmarks/bench_moonlift_shapes.lua quick disasm popcount_intrinsic_sum
luajit moonlift/benchmarks/bench_moonlift_shapes.lua quick disasm switch_expr_sum
```

To validate the current vectorization path against Terra:

```bash
moonlift/benchmarks/run_vector_sum_vs_terra.sh quick
moonlift/benchmarks/run_vector_sum_vs_terra.sh
```

## Kernels

- `sum_loop` — integer mixed accumulation (chosen to avoid a closed-form loop fold)
- `collatz_sum` — branch-heavy integer loop
- `mandelbrot_sum` — floating point plus branches
- `poly_eval_grid` — nested floating point arithmetic
- `popcount_sum` — bitwise loop
- `fib_sum` — data-dependency loop
- `gcd_sum` — division-heavy nested loop
- `switch_sum` — multi-way scalar dispatch

## Moonlift-shaped checks

`bench_moonlift_shapes.lua` exists because Moonlift should not rely only on the
backend rediscovering high-level intent. It compares pairs such as:

- `while` index loop vs `for i in 0..n` range-domain loop
- generic `if` expression vs explicit `select(cond, a, b)`
- manual bit-counting loop vs `popcount(...)`
- `x * y + z` vs `fma(x, y, z)`

This track is architecture feedback, not a Terra fairness track: if an explicit
ASDL/source construct produces better `Back` facts and better machine code, that
is evidence that the source/lowering shape matters.

## Notes

- Timings use best-of-N `os.clock()` measurements after warmup.
- `COMPILE_ALL` measures compilation of all benchmark functions on each side.
- Runtime ratios are `Moonlift / Terra`; values below `1.0` mean Moonlift was
  faster for that kernel in that run.
- This is not a complete-language benchmark. Keep arrays, slices, views,
  aggregates, and non-scalar ABI tests out of this track until those features are
  implemented end-to-end in Moonlift.
