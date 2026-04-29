#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Lua PVM back_validate =="
luajit benchmarks/profile_compile.lua

echo

echo "== LL-wired flat back_validate =="
MOONLIFT_BACK_VALIDATE=ll luajit benchmarks/profile_compile.lua
