#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
MODE="${1:-}"
if [[ "$MODE" != "" && "$MODE" != "quick" ]]; then
  echo "usage: moonlift/benchmarks/run_vs_terra.sh [quick]" >&2
  exit 2
fi

if ! command -v luajit >/dev/null 2>&1; then
  echo "ERROR: luajit not found in PATH" >&2
  exit 1
fi

if ! command -v terra >/dev/null 2>&1; then
  echo "ERROR: terra not found in PATH" >&2
  echo "You can still run Moonlift only:" >&2
  echo "  cargo build --manifest-path moonlift/Cargo.toml --release" >&2
  if [[ "$MODE" == "" ]]; then
    echo "  luajit moonlift/benchmarks/bench_moonlift.lua" >&2
  else
    echo "  luajit moonlift/benchmarks/bench_moonlift.lua $MODE" >&2
  fi
  exit 1
fi

echo "Building Moonlift shared library (release)..." >&2
cargo build --manifest-path moonlift/Cargo.toml --release >/dev/null

ml_out="$(mktemp)"
terra_out="$(mktemp)"
cleanup() {
  rm -f "$ml_out" "$terra_out"
}
trap cleanup EXIT

echo "Running Moonlift${MODE:+ ($MODE)}..." >&2
if [[ "$MODE" == "" ]]; then
  luajit moonlift/benchmarks/bench_moonlift.lua > "$ml_out"
else
  luajit moonlift/benchmarks/bench_moonlift.lua "$MODE" > "$ml_out"
fi

echo "Running Terra${MODE:+ ($MODE)}..." >&2
if [[ "$MODE" == "" ]]; then
  terra moonlift/benchmarks/bench_terra.t > "$terra_out"
else
  terra moonlift/benchmarks/bench_terra.t "$MODE" > "$terra_out"
fi

awk '
  FNR == NR { mt[$1] = $2; mr[$1] = $3; next }
  { tt[$1] = $2; tr[$1] = $3 }
  END {
    names[1]="sum_loop"; names[2]="collatz_sum"; names[3]="mandelbrot_sum"; names[4]="poly_eval_grid";
    names[5]="popcount_sum"; names[6]="fib_sum"; names[7]="gcd_sum"; names[8]="switch_sum";
    printf("\nMoonlift (Cranelift) vs Terra (LLVM) scalar kernels\n")
    printf("Mode: %s\n\n", mode == "" ? "default" : mode)
    printf("Compile all  Moonlift %9.3f ms   Terra %9.3f ms   ratio %.2fx\n\n", mt["COMPILE_ALL"]*1000, tt["COMPILE_ALL"]*1000, mt["COMPILE_ALL"]/tt["COMPILE_ALL"])
    printf("%-16s %12s %12s %9s  %s\n", "kernel", "moonlift", "terra", "ml/terra", "result")
    printf("%-16s %12s %12s %9s  %s\n", "----------------", "------------", "------------", "---------", "------")
    total_m = 0; total_t = 0
    for (i = 1; i <= 8; i++) {
      n = names[i]
      m = mt[n] + 0; t = tt[n] + 0
      total_m += m; total_t += t
      ok = (mr[n] == tr[n]) ? "ok" : "MISMATCH"
      ratio = (t > 0) ? m / t : 0
      printf("%-16s %9.3f ms %9.3f ms %8.2fx  %s\n", n, m*1000, t*1000, ratio, ok)
    }
    printf("%-16s %9.3f ms %9.3f ms %8.2fx\n\n", "TOTAL", total_m*1000, total_t*1000, total_m/total_t)
    printf("ratio = Moonlift runtime / Terra runtime. <1 means Moonlift faster.\n")
  }
' mode="$MODE" "$ml_out" "$terra_out"
