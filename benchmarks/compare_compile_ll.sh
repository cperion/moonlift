#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Default compile profile (flat back_validate) =="
luajit benchmarks/profile_compile.lua

echo

echo "== Back-validation A/B microbenchmark (30 rounds) =="
luajit benchmarks/bench_compile_back_validate_ll.lua "${1:-30}"

echo

echo "== Back-validation verify (10 rounds, verbose) =="
luajit benchmarks/bench_compile_back_validate_ll.lua verbose 10
