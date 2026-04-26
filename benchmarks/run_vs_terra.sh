#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
MODE="${1:-}"
if [[ "$MODE" != "" && "$MODE" != "quick" ]]; then
  echo "usage: moonlift/benchmarks/run_vs_terra.sh [quick]" >&2
  exit 2
fi
if ! command -v luajit >/dev/null 2>&1; then echo "ERROR: luajit not found" >&2; exit 1; fi
if ! command -v terra >/dev/null 2>&1; then echo "ERROR: terra not found" >&2; exit 1; fi
cargo build --manifest-path moonlift/Cargo.toml --release >/dev/null
ml_out="$(mktemp)"; terra_out="$(mktemp)"
trap 'rm -f "$ml_out" "$terra_out"' EXIT
if [[ "$MODE" == "" ]]; then
  luajit moonlift/benchmarks/bench_kernels.lua > "$ml_out"
  terra moonlift/benchmarks/bench_kernels_terra.t > "$terra_out"
else
  luajit moonlift/benchmarks/bench_kernels.lua "$MODE" > "$ml_out"
  terra moonlift/benchmarks/bench_kernels_terra.t "$MODE" > "$terra_out"
fi
awk '
  FNR == NR { t[$1]=$2; r[$1]=$3; names[++n]=$1; next }
  { t[$1]=$2; r[$1]=$3; names[++n]=$1 }
  END {
    printf("\nMoonlift vs Terra: jump-first i32 kernels\n")
    printf("Mode: %s\n\n", mode == "" ? "default" : mode)
    printf("%-20s %10s  %s\n", "kernel", "time", "result/check")
    printf("%-20s %10s  %s\n", "--------------------", "----------", "------------")
    for (i=1;i<=n;i++) {
      k=names[i]
      printf("%-20s %7.3f ms  %s\n", k, t[k]*1000, r[k])
    }
    printf("\nMoonlift / Terra ratios (lower is better for Moonlift):\n")
    printf("compile      %.2fx\n", t["moonlift_compile"] / t["terra_compile"])
    printf("sum_i32      %.2fx\n", t["moonlift_sum_i32"] / t["terra_sum_i32"])
    printf("dot_i32      %.2fx\n", t["moonlift_dot_i32"] / t["terra_dot_i32"])
    printf("add_i32      %.2fx\n", t["moonlift_add_i32"] / t["terra_add_i32"])
    printf("scale_i32    %.2fx\n", t["moonlift_scale_i32"] / t["terra_scale_i32"])
  }
' mode="$MODE" "$ml_out" "$terra_out"
