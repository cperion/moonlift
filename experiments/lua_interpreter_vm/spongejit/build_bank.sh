#!/bin/bash
# build_bank.sh — Generate the SponJIT bank .so from the stencil object.
#
# One bank pipeline:
#   stencils.o -> .text binary + symbols -> metadata C -> metadata object
#             -> link metadata + binary .text object -> libsponbank.so
#
# The stencil bytes are linked as a binary object instead of emitted as a giant
# C hex array. This keeps bank compilation proportional to metadata, not code
# bytes.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/cp_lib

log() { printf '[bank.sh] %s\n' "$*" >&2; }

OUT=build/cp_lib
CONFIG=$OUT/build_config.env
if [ -f "$CONFIG" ]; then
  if [ -z "${CHUNKS+x}" ]; then
    CHUNKS=$(awk -F= '$1 == "CHUNKS" {print $2}' "$CONFIG")
  fi
  if [ -z "${SPON_TMP+x}" ]; then
    SPON_TMP=$(awk -F= '$1 == "SPON_TMP" {print $2}' "$CONFIG")
  fi
fi
CHUNKS=${CHUNKS:-${N:-64}}
SPON_TMP=${SPON_TMP:-"$PWD/build/cp_lib/tmp"}
export CHUNKS SPON_TMP

OBJ=$OUT/stencils.o
TEXT=$OUT/stencils.text.bin
TEXT_OBJ=$OUT/stencils_text.o
SYMS=$OUT/stencil_syms.txt
COUT=$OUT/libsponbank.c
META_OBJ=$OUT/libsponbank_meta.o
SO=$OUT/libsponbank.so

if [ ! -f "$OBJ" ]; then
  echo "missing $OBJ; run ./build_stencils.sh first" >&2
  exit 1
fi

log "config: chunks=$CHUNKS tmp=$SPON_TMP"

newer_than() { [ ! -e "$1" ] || [ "$2" -nt "$1" ]; }

log "1/5 extract .text + symbols"
if [ "${FORCE:-0}" = 1 ] || [ "${FORCE_BANK:-0}" = 1 ] || newer_than "$TEXT" "$OBJ"; then
  objcopy -O binary --only-section=.text "$OBJ" "$TEXT"
  log ".text rebuilt bytes=$(wc -c < "$TEXT" | tr -d ' ')"
else
  log ".text cache hit bytes=$(wc -c < "$TEXT" | tr -d ' ')"
fi

if [ "${FORCE:-0}" = 1 ] || [ "${FORCE_BANK:-0}" = 1 ] || newer_than "$SYMS" "$OBJ"; then
  nm -S "$OBJ" 2>/dev/null | awk '/ z_/{printf("%s %s %s\n",$1,$2,$4)}' > "$SYMS"
  log "symbols rebuilt count=$(wc -l < "$SYMS" | tr -d ' ')"
else
  log "symbols cache hit count=$(wc -l < "$SYMS" | tr -d ' ')"
fi

log "2/5 wrap .text as binary object"
if [ "${FORCE:-0}" = 1 ] || [ "${FORCE_BANK:-0}" = 1 ] || newer_than "$TEXT_OBJ" "$TEXT"; then
  (
    cd "$OUT"
    ld -r -b binary -o "$(basename "$TEXT_OBJ")" "$(basename "$TEXT")"
  )
  log "text object rebuilt bytes=$(wc -c < "$TEXT_OBJ" | tr -d ' ')"
else
  log "text object cache hit bytes=$(wc -c < "$TEXT_OBJ" | tr -d ' ')"
fi

log "3/5 generate metadata C"
BANK_STAMP=$OUT/.bank_meta.cachekey
bank_key() {
  {
    printf 'CHUNKS=%s\nSPON_TMP=%s\n' "$CHUNKS" "$SPON_TMP"
    sha256sum src/build_bank.lua include/sponbank.h build_bank.sh "$SYMS" 2>/dev/null || true
    find "$SPON_TMP" -maxdepth 1 \( -name 'grammar_result_*.json' -o -name 'grammar_holes_*.json' \) -print | sort | xargs -r sha256sum
  } | sha256sum | awk '{print $1}'
}
BKEY=$(bank_key)
if [ "${FORCE:-0}" = 1 ] || [ "${FORCE_BANK:-0}" = 1 ] || [ ! -s "$COUT" ] || [ ! -f "$BANK_STAMP" ] || [ "$(cat "$BANK_STAMP")" != "$BKEY" ]; then
  luajit src/build_bank.lua "$OBJ" "$CHUNKS" "$OUT" 2>&1
  printf '%s\n' "$BKEY" > "$BANK_STAMP"
  log "metadata C rebuilt bytes=$(wc -c < "$COUT" | tr -d ' ')"
else
  log "metadata C cache hit bytes=$(wc -c < "$COUT" | tr -d ' ')"
fi

log "4/5 compile metadata object"
if [ "${FORCE:-0}" = 1 ] || [ "${FORCE_BANK:-0}" = 1 ] || newer_than "$META_OBJ" "$COUT" || newer_than "$META_OBJ" "include/sponbank.h"; then
  gcc -O2 -fPIC -Wno-overflow -Iinclude -c -o "$META_OBJ" "$COUT"
  log "metadata object rebuilt bytes=$(wc -c < "$META_OBJ" | tr -d ' ')"
else
  log "metadata object cache hit bytes=$(wc -c < "$META_OBJ" | tr -d ' ')"
fi

log "5/5 link libsponbank.so"
if [ "${FORCE:-0}" = 1 ] || [ "${FORCE_BANK:-0}" = 1 ] || newer_than "$SO" "$META_OBJ" || newer_than "$SO" "$TEXT_OBJ"; then
  gcc -shared -o "$SO" "$META_OBJ" "$TEXT_OBJ"
  log ".so rebuilt bytes=$(wc -c < "$SO" | tr -d ' ')"
else
  log ".so cache hit bytes=$(wc -c < "$SO" | tr -d ' ')"
fi

log "exports"
nm -D "$SO" | grep ' T ' | grep -v '_fini\|_init' >&2 || true
log "done"
