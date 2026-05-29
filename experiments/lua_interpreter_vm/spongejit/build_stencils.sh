#!/bin/bash
# build_stencils.sh — Build the complete copy-and-patch stencil object.
#
# One stencil pipeline:
#   grammar -> weighted chunks -> parallel SSA/C codegen -> parallel GCC -> stencils.o
#
# The full stencil build is expensive, so the script keeps a coarse content
# cache. Set FORCE=1 or FORCE_STENCILS=1 to discard it. CHUNKS controls shard
# size; WORKERS/GCC_JOBS control parallelism. Weighted chunks keep large
# fact-combo builds from leaving one slow worker at the end.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/cp_lib

log() { printf '[stencils] %s\n' "$*" >&2; }

CORES=$(nproc 2>/dev/null || echo 16)
CHUNKS=${CHUNKS:-${N:-64}}
WORKERS=${WORKERS:-$CORES}
GCC_JOBS=${GCC_JOBS:-$WORKERS}
MAX_ARITY=${MAX_ARITY:-4}
MAX_FACT_COMBOS=${MAX_FACT_COMBOS:-0}
FACT_AXIS_MODE=${FACT_AXIS_MODE:-curated}
WORKER_PROGRESS_SEQS=${WORKER_PROGRESS_SEQS:-1000}
export CHUNKS WORKERS GCC_JOBS MAX_ARITY MAX_FACT_COMBOS FACT_AXIS_MODE WORKER_PROGRESS_SEQS

SPON_TMP=${SPON_TMP:-"$PWD/build/cp_lib/tmp"}
export SPON_TMP
mkdir -p "$SPON_TMP"
cat > build/cp_lib/build_config.env <<EOF
CHUNKS=$CHUNKS
MAX_ARITY=$MAX_ARITY
MAX_FACT_COMBOS=$MAX_FACT_COMBOS
FACT_AXIS_MODE=$FACT_AXIS_MODE
SPON_TMP=$SPON_TMP
EOF

STAMP=build/cp_lib/.stencils.cachekey
cache_key() {
  {
    printf 'CHUNKS=%s\nMAX_ARITY=%s\nMAX_FACT_COMBOS=%s\nFACT_AXIS_MODE=%s\n' \
      "$CHUNKS" "$MAX_ARITY" "$MAX_FACT_COMBOS" "$FACT_AXIS_MODE"
    sha256sum build_stencils.sh 2>/dev/null || true
    find src -type f -name '*.lua' ! -name 'build_bank.lua' -print | sort | xargs -r sha256sum
  } | sha256sum | awk '{print $1}'
}
KEY=$(cache_key)
if [ "${FORCE:-0}" != 1 ] && [ "${FORCE_STENCILS:-0}" != 1 ] && \
   [ -s build/cp_lib/stencils.o ] && [ -s build/cp_lib/stencil_library.json ] && \
   [ -s "$SPON_TMP/grammar_result_${CHUNKS}.json" ] && [ -s "$SPON_TMP/grammar_holes_${CHUNKS}.json" ]; then
  if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$KEY" ]; then
    log "cache hit: reusing build/cp_lib/stencils.o and $SPON_TMP grammar artifacts"
    exit 0
  fi
  if [ "${ADOPT_EXISTING_STENCILS:-1}" = 1 ] && [ ! -f "$STAMP" ]; then
    printf '%s\n' "$KEY" > "$STAMP"
    log "cache adopted existing build/cp_lib/stencils.o and $SPON_TMP grammar artifacts"
    exit 0
  fi
fi

if [ "${KEEP_STENCIL_PARTIALS:-0}" != 1 ]; then
  rm -f "$SPON_TMP"/grammar_chunk_*.json "$SPON_TMP"/grammar_result_*.json \
        "$SPON_TMP"/grammar_holes_*.json "$SPON_TMP"/grammar_c_code_*.c \
        "$SPON_TMP"/grammar_c_*.o "$SPON_TMP"/grammar_chunk_manifest.json
fi

log "config: chunks=$CHUNKS workers=$WORKERS gcc_jobs=$GCC_JOBS max_arity=$MAX_ARITY fact_mode=$FACT_AXIS_MODE max_fact_combos=$MAX_FACT_COMBOS tmp=$SPON_TMP"

log "1/5 grammar enumeration + weighted chunk plan"
luajit -e '
package.path = "src/?.lua;src/?/init.lua;" .. package.path
local Util = require("src.util")
local Grammar = require("src.grammar_enum")
local FactAxes = require("src.ssa_fact_axes")

local max_arity = tonumber(os.getenv("MAX_ARITY") or "4") or 4
local chunks = tonumber(os.getenv("CHUNKS") or os.getenv("N") or "64") or 64
local config = {
  max_fact_combos = tonumber(os.getenv("MAX_FACT_COMBOS") or "0") or 0,
  fact_axis_mode = tostring(os.getenv("FACT_AXIS_MODE") or "curated"),
}
local tmp = assert(os.getenv("SPON_TMP"), "SPON_TMP unset")
local function t(name) return tmp .. "/" .. name end

local seqs = Grammar.generate_all(max_arity)

-- Add exact L0 floor forms for every concrete opcode. generate_all() is
-- handler-deduped; the runtime fallback table must not be.
local seen_l0 = {}
for _, seq in ipairs(seqs) do
  if #(seq.ops or {}) == 1 then
    local op = seq.ops[1]
    local name = type(op) == "table" and op.op or tostring(op)
    seen_l0[name] = true
  end
end
for _, seq in ipairs(Grammar.generate_l0_all()) do
  local op = seq.ops[1]
  local name = type(op) == "table" and op.op or tostring(op)
  if not seen_l0[name] then
    seqs[#seqs + 1] = seq
    seen_l0[name] = true
  end
end

local function subset_count(n)
  return n >= 31 and math.huge or 2 ^ n
end

local function estimate_combos(ops)
  local axes = FactAxes.axes_for_ops(ops)
  local max = tonumber(config.max_fact_combos or 0) or 0
  if max > 0 then
    return math.max(1, math.min(subset_count(#axes), max))
  end
  if config.fact_axis_mode == "powerset" then
    return math.max(1, subset_count(#axes))
  end
  -- Default curated mode has no sparse powerset tail when max=0, so the exact
  -- list is small and safe to count here.
  return math.max(1, #FactAxes.subsets(axes, config))
end

local items, total_cost, max_cost = {}, 0, 0
for i, seq in ipairs(seqs) do
  local combos = estimate_combos(seq.ops)
  items[#items + 1] = {idx=i, ops=seq.ops, cost=combos}
  total_cost = total_cost + combos
  if combos > max_cost then max_cost = combos end
  if i % 50000 == 0 then
    io.stderr:write(string.format("[plan] costed %d/%d sequences\n", i, #seqs))
  end
end

table.sort(items, function(a, b)
  if a.cost ~= b.cost then return a.cost > b.cost end
  return a.idx < b.idx
end)

local buckets = {}
for ci = 1, chunks do buckets[ci] = {cost=0, count=0, ops={}} end
for _, item in ipairs(items) do
  local best = 1
  for ci = 2, chunks do
    if buckets[ci].cost < buckets[best].cost then best = ci end
  end
  local b = buckets[best]
  b.cost = b.cost + item.cost
  b.count = b.count + 1
  b.ops[#b.ops + 1] = item.ops
end

local min_cost, max_bucket_cost = math.huge, 0
local manifest = {
  max_arity=max_arity,
  chunks=chunks,
  sequences=#seqs,
  estimated_compiles=total_cost,
  max_sequence_combos=max_cost,
  fact_axis_mode=config.fact_axis_mode,
  max_fact_combos=config.max_fact_combos,
  buckets={},
}
for ci = 1, chunks do
  local b = buckets[ci]
  if b.cost < min_cost then min_cost = b.cost end
  if b.cost > max_bucket_cost then max_bucket_cost = b.cost end
  Util.write_json(t("grammar_chunk_" .. ci .. ".json"), b.ops)
  manifest.buckets[#manifest.buckets + 1] = {chunk=ci, sequences=b.count, estimated_compiles=b.cost}
end
Util.write_json(t("grammar_chunk_manifest.json"), manifest)
io.stderr:write(string.format("[plan] %d seqs incl exact L0, arity<=%d, %d weighted chunks, est_compiles=%d, per_chunk=%d..%d, max_seq_combos=%d\n",
  #seqs, max_arity, chunks, total_cost, min_cost == math.huge and 0 or min_cost, max_bucket_cost, max_cost))
'

log "2/5 SSA + C codegen ($WORKERS workers over $CHUNKS chunks)"
seq 1 "$CHUNKS" | xargs -P "$WORKERS" -I{} luajit src/worker_compile.lua {} 2>&1

log "3/5 compile C chunks ($GCC_JOBS gcc jobs over $CHUNKS chunks)"
seq 1 "$CHUNKS" | xargs -P "$GCC_JOBS" -I{} sh -c '
    set -e
    echo "[gcc {}] START" >&2
    gcc -c -O2 -fno-ipa-icf -fomit-frame-pointer -fno-pic -no-pie \
        "$SPON_TMP/grammar_c_code_{}.c" -o "$SPON_TMP/grammar_c_{}.o" 2>"$SPON_TMP/grammar_c_{}.gcc.err"
    bytes=$(wc -c < "$SPON_TMP/grammar_c_{}.o" | tr -d " ")
    echo "[gcc {}] DONE object=${bytes}B" >&2
'

log "4/5 link chunk objects"
ld -r -o build/cp_lib/stencils.o "$SPON_TMP"/grammar_c_*.o 2>&1
log "combined object: $(wc -c < build/cp_lib/stencils.o | tr -d ' ') bytes"

log "5/5 build stencil catalog"
luajit -e '
package.path = "src/?.lua;src/?/init.lua;" .. package.path
local Util = require("src.util")
local chunks = tonumber(os.getenv("CHUNKS") or os.getenv("N") or "64") or 64
local tmp = assert(os.getenv("SPON_TMP"), "SPON_TMP unset")
local function t(name) return tmp .. "/" .. name end
local library, total = {}, 0
for ci = 1, chunks do
  local ok, holes = pcall(function() return Util.read_json(t("grammar_holes_"..ci..".json")) end)
  if not ok then goto next end
  local sf = io.popen("objdump -t " .. Util.shell_quote(t("grammar_c_"..ci..".o")) .. " 2>/dev/null")
  local syms = sf:read("*a"); sf:close()
  local sizes = {}
  for line in syms:gmatch("[^\n]+") do
    local parts = {}
    for p in line:gmatch("%S+") do parts[#parts+1] = p end
    if #parts >= 5 and parts[#parts]:match("^z_") and parts[3] == "F" then
      local name = parts[#parts]
      local sz = tonumber(parts[#parts-1], 16)
      sizes[name] = sz or 0
      if (sz or 0) > 5 then total = total + sz end
    end
  end
  for _, h in ipairs(holes or {}) do
    local sz = sizes[h.func] or 0
    library[#library + 1] = {func=h.func, size=sz, n_holes=#(h.holes or {}), holes=h.holes}
  end
  io.stderr:write(string.format("[catalog] chunk %d/%d forms=%d\n", ci, chunks, #(holes or {})))
  ::next::
end
io.stderr:write(string.format("[catalog] library: %d stencils, %d bytes\n", #library, total))
Util.write_json("build/cp_lib/stencil_library.json", library)
'

printf '%s\n' "$KEY" > "$STAMP"
log "done"
luajit -e '
local lib = require("src.util").read_json("build/cp_lib/stencil_library.json")
local n, tot = 0, 0; local bins = {[50]=0,[100]=0}
for _, s in ipairs(lib) do
  n=n+1; tot=tot+s.size
  if s.size<=50 then bins[50]=bins[50]+1
  elseif s.size<=100 then bins[100]=bins[100]+1 end
end
io.stderr:write(string.format("[stencils] %d stencils, %d bytes (%.1f MB), avg %.0fB\n[stencils] <=50B: %d  <=100B: %d  >100B: %d\n",
  n, tot, tot/1e6, n > 0 and tot/n or 0, bins[50] or 0, bins[100] or 0, n-(bins[50]or 0)-(bins[100]or 0)))
'
