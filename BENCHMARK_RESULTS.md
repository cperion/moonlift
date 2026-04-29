# Moonlift benchmark notes

Date: 2026-04-29
Host: local development machine used by this run
Command:

```text
moonlift/benchmarks/run_vs_terra.sh
```

The benchmark suite now compares a broader set of idiomatic Moonlift kernels
against equivalent Terra kernels.  Moonlift uses the jump-first typed block/jump
source form plus contracts/views where meaningful; Terra uses ordinary low-level
`while` loops over the same buffers/descriptors.  The default run uses
`N=16777216`, `WARMUP=1`, and `ITERS=3` to keep total wall time comfortably under
30 seconds on the local fast CPU while making fixed overhead mostly irrelevant.

## Default broad-suite run

```text
Moonlift vs Terra: jump-first typed block/jump kernel suite
Mode: default

kernel                               moonlift        terra    ratio  result/check
-------------------------------- ------------ ------------ --------  ------------
compile                            297.953 ms   126.869 ms    2.35x  0
sum_i32                              1.412 ms     1.707 ms    0.83x  -8388608
dot_i32                              3.268 ms     2.984 ms    1.10x  -1904214016
prod_i32                             1.416 ms     1.825 ms    0.78x  0
xor_reduce_i32                       1.402 ms     1.595 ms    0.88x  0
fill_i32                             2.934 ms     2.680 ms    1.09x  246
copy_i32                             4.814 ms     4.931 ms    0.98x  -11
add_i32                              6.888 ms     7.315 ms    0.94x  -28
sub_i32                              6.881 ms     7.240 ms    0.95x  6
scale_i32                            4.805 ms     4.876 ms    0.99x  -33
inc_i32                              3.555 ms     2.684 ms    1.32x  17
axpy_i32                             4.942 ms     5.215 ms    0.95x  -71
and_i32                              6.817 ms     7.034 ms    0.97x  -29
or_i32                               6.968 ms     7.049 ms    0.99x  1
xor_i32                              6.821 ms     7.162 ms    0.95x  30
clamp_nonneg_i32                     4.804 ms     4.912 ms    0.98x  1010
max_i32                              6.817 ms     6.984 ms    0.98x  -7
in_range_i32                         5.059 ms     4.943 ms    1.02x  0
sum_i64                              2.754 ms     2.769 ms    0.99x  8455709361
dot_i64                              7.004 ms     6.711 ms    1.04x  4210939748947
add_i64                             14.224 ms    14.879 ms    0.96x  1302
sub_i64                             14.121 ms    14.369 ms    0.98x  -4
scale_i64                            9.721 ms    10.428 ms    0.93x  1947
or_i64                              13.881 ms    14.968 ms    0.93x  653
sum_u32                              1.381 ms     1.529 ms    0.90x  4160742065
add_u32                              6.802 ms     7.624 ms    0.89x  1302
min_u32                              6.863 ms     7.058 ms    0.97x  649
sum_u64                              2.753 ms     3.116 ms    0.88x  8455709361
add_u64                             15.956 ms    15.072 ms    1.06x  1302
xor_u64                             14.428 ms    14.949 ms    0.97x  4
add_view_i32                         6.857 ms    21.026 ms    0.33x  -28
copy_view_i32                        4.799 ms    11.549 ms    0.42x  -11
threshold_view_i32                   4.908 ms    11.572 ms    0.42x  0
max_view_prefix_window_i32          14.401 ms    20.459 ms    0.70x  1009
```

## Broad-suite interpretation

Runtime is broadly at Terra parity or better on the large default problem size:

- signed `i32` reductions/maps/selects are mostly within noise of parity;
- `i64`, `u32`, and `u64` families are also around parity, with several kernels
  modestly faster in this run;
- descriptor-backed `view(i32)` kernels are substantially faster than the direct
  Terra descriptor loop baseline here, because Moonlift lowers the semantic view
  facts into the same optimized data/len/stride backend shape used by the normal
  vector path;
- `inc_i32` is the notable remaining runtime outlier in this run (`1.32x`), worth
  inspecting as an in-place same-base store/load schedule case;
- compile time remains slower (`2.35x`) and should be split into phase timings.

The important architectural result is that widening from four hand-picked i32
kernels to reductions, maps, bitwise maps, selects, signed/unsigned 32/64-bit
families, and descriptor-backed views does not collapse the generated-code story:
the fact-rich Moon2Back path remains LLVM/Terra-class on these source-shaped
kernels.

## Quick run

Command:

```text
moonlift/benchmarks/run_vs_terra.sh quick
```

Quick mode uses `N=1048576`, `WARMUP=1`, and `ITERS=2`.  It is useful as a smoke
check, but fixed overhead and cache effects dominate several ratios.  Prefer the
default run for runtime comparisons.

## Backend diagnostics

Command:

```text
luajit moonlift/benchmarks/bench_diagnostics.lua
```

Current schedule/fact summary from the focused diagnostic kernels:

```text
schedule sum_i32    elem=VecElemI32 lanes=4 unroll=1 interleave=1 accumulators=4 tail=VecTailScalar
schedule dot_i32    elem=VecElemI32 lanes=4 unroll=1 interleave=1 accumulators=4 tail=VecTailScalar
schedule add_i32    elem=VecElemI32 lanes=4 unroll=1 interleave=1 accumulators=1 tail=VecTailScalar
schedule scale_i32  elem=VecElemI32 lanes=4 unroll=1 interleave=1 accumulators=1 tail=VecTailScalar
cmd CmdAliasFact             39
cmd CmdLoadInfo              21
cmd CmdStoreInfo             4
cmd CmdVecBinary             14
cmd CmdVecExtractLane        32
cmd CmdVecSplat              3
memory_alignment BackAlignKnown       25
memory_dereference BackDerefAssumed   25
memory_trap BackNonTrapping           25
aliases 39
addresses 25
pointer_offsets 0
```

Optional disassembly capture:

```text
MOONLIFT_BENCH_DIAGNOSTICS_DISASM=1 luajit moonlift/benchmarks/bench_diagnostics.lua
```

## Next tuning candidates

1. Add phase timing diagnostics for compile time:
   - parse;
   - typecheck;
   - vector planning/lowering;
   - validation;
   - tape encode/decode;
   - Cranelift compile.
2. Inspect `inc_i32` as an in-place load/store kernel and compare its emitted
   alias/same-index facts with `copy_i32` and `axpy_i32`.
3. Keep descriptor-backed `view(i32)` kernels in the benchmark suite as a
   regression guard for the zero-copy ABI path.
4. Keep quick mode as smoke-only; use default mode for generated-code claims.
