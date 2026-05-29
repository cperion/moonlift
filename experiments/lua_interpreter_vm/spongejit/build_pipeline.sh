#!/bin/bash
# build_pipeline.sh — One-command SponJIT stencil + bank build.
set -euo pipefail
cd "$(dirname "$0")"

printf '[pipeline] starting stencil build\n' >&2
./build_stencils.sh

printf '[pipeline] starting bank build\n' >&2
./build_bank.sh

printf '[pipeline] done: build/cp_lib/libsponbank.so\n' >&2
