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
  function suffix(k) {
    sub(/^moonlift_/, "", k)
    sub(/^terra_/, "", k)
    return k
  }
  FNR == NR {
    ml_t[$1]=$2; ml_r[$1]=$3; s=suffix($1); order[++n]=s; next
  }
  {
    terra_t[$1]=$2; terra_r[$1]=$3
  }
  END {
    printf("\nMoonlift vs Terra: jump-first typed block/jump kernel suite\n")
    printf("Mode: %s\n\n", mode == "" ? "default" : mode)
    printf("%-32s %12s %12s %8s  %s\n", "kernel", "moonlift", "terra", "ratio", "result/check")
    printf("%-32s %12s %12s %8s  %s\n", "--------------------------------", "------------", "------------", "--------", "------------")
    for (i=1;i<=n;i++) {
      s=order[i]
      mk="moonlift_" s
      tk="terra_" s
      if (!(tk in terra_t)) continue
      ratio=ml_t[mk] / terra_t[tk]
      mismatch=(ml_r[mk] != terra_r[tk]) ? "  MISMATCH terra=" terra_r[tk] : ""
      printf("%-32s %9.3f ms %9.3f ms %7.2fx  %s%s\n", s, ml_t[mk]*1000, terra_t[tk]*1000, ratio, ml_r[mk], mismatch)
    }
    printf("\nMoonlift / Terra ratios by family (lower is better for Moonlift):\n")
    printf("compile                  %.2fx\n", ml_t["moonlift_compile"] / terra_t["terra_compile"])
    for (i=1;i<=n;i++) {
      s=order[i]
      if (s == "compile") continue
      mk="moonlift_" s
      tk="terra_" s
      if (!(tk in terra_t)) continue
      printf("%-24s %.2fx\n", s, ml_t[mk] / terra_t[tk])
    }
  }
' mode="$MODE" "$ml_out" "$terra_out"
