#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
MODE="${1:-}"
if [[ "$MODE" != "" && "$MODE" != "quick" ]]; then
  echo "usage: moonlift/benchmarks/run_vector_sum_vs_terra.sh [quick]" >&2
  exit 2
fi
if ! command -v luajit >/dev/null 2>&1; then echo "ERROR: luajit not found" >&2; exit 1; fi
if ! command -v terra >/dev/null 2>&1; then echo "ERROR: terra not found" >&2; exit 1; fi
cargo build --manifest-path moonlift/Cargo.toml --release >/dev/null
ml_out="$(mktemp)"; terra_out="$(mktemp)"
trap 'rm -f "$ml_out" "$terra_out"' EXIT
if [[ "$MODE" == "" ]]; then
  luajit moonlift/benchmarks/bench_vector_sum.lua > "$ml_out"
  terra moonlift/benchmarks/bench_vector_sum_terra.t > "$terra_out"
else
  luajit moonlift/benchmarks/bench_vector_sum.lua "$MODE" > "$ml_out"
  terra moonlift/benchmarks/bench_vector_sum_terra.t "$MODE" > "$terra_out"
fi
awk '
  FNR == NR { t[$1]=$2; r[$1]=$3; names[++n]=$1; next }
  { t[$1]=$2; r[$1]=$3; names[++n]=$1 }
  END {
    printf("\nMoonlift ASDL vector path vs Terra: sum reduction\n")
    printf("Mode: %s\n\n", mode == "" ? "default" : mode)
    printf("%-18s %10s  %s\n", "kernel", "time", "result")
    printf("%-18s %10s  %s\n", "------------------", "----------", "------")
    for (i=1;i<=n;i++) {
      k=names[i]
      printf("%-18s %7.3f ms  %s\n", k, t[k]*1000, r[k])
    }
    printf("\nvec/scalar: %.2fx\n", t["moonlift_vec2"] / t["moonlift_scalar"])
    if ("moonlift_vec2_u4" in t) {
      printf("vec_u4/scalar: %.2fx\n", t["moonlift_vec2_u4"] / t["moonlift_scalar"])
      printf("vec_u4/vec: %.2fx\n", t["moonlift_vec2_u4"] / t["moonlift_vec2"])
      printf("vec_u4/terra : %.2fx\n", t["moonlift_vec2_u4"] / t["terra"])
    }
    if ("moonlift_i32x4_u4" in t) {
      printf("i32x4_u4/scalar: %.2fx\n", t["moonlift_i32x4_u4"] / t["moonlift_scalar"])
      printf("i32x4_u4/terra : %.2fx\n", t["moonlift_i32x4_u4"] / t["terra"])
    }
    printf("vec/terra : %.2fx\n", t["moonlift_vec2"] / t["terra"])
    printf("scalar/terra: %.2fx\n", t["moonlift_scalar"] / t["terra"])
  }
' mode="$MODE" "$ml_out" "$terra_out"
