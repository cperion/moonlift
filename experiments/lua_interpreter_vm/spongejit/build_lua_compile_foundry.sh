#!/usr/bin/env bash
# build_lua_compile_foundry.sh — maintained LuaCompile foundry builder.
#
# Maintained offline foundry pipeline:
#   LuaCompile grammar/window plan -> parallel LuaCompile workers
#   -> LalinCFG + CompileContract + Stencil.VariantKey representative dedupe
#   -> LalinCFG/Lalin source artifacts; binary StencilTemplate banks are separate object-extraction artifacts.
#
# This script builds LuaCompile representatives, indexes, alias maps, and coverage manifests.

set -euo pipefail
cd "$(dirname "$0")"

if command -v luarocks >/dev/null 2>&1; then
  eval "$(luarocks --lua-version=5.1 path 2>/dev/null || luarocks path)"
fi
export LUA_PATH LUA_CPATH PATH

log() { printf '[lua-compile-foundry] %s\n' "$*" >&2; }

CORES=$(nproc 2>/dev/null || echo 16)
CHUNKS=${CHUNKS:-8}
WORKERS=${WORKERS:-$CORES}
MAX_ARITY=${MAX_ARITY:-2}
MAX_FACT_COMBOS=${MAX_FACT_COMBOS:-32}
WORKER_PROGRESS_SEQS=${WORKER_PROGRESS_SEQS:-1000}
OUT_DIR=${OUT_DIR:-"$PWD/build/lua_compile_foundry"}
SPON_TMP=${SPON_TMP:-"$OUT_DIR"}
KEEP_LUA_COMPILE_PARTIALS=${KEEP_LUA_COMPILE_PARTIALS:-0}

export CHUNKS WORKERS MAX_ARITY MAX_FACT_COMBOS WORKER_PROGRESS_SEQS SPON_TMP

mkdir -p "$SPON_TMP"
if [ "$KEEP_LUA_COMPILE_PARTIALS" != 1 ]; then
  rm -f "$SPON_TMP"/lua_compile_chunk_*.json \
        "$SPON_TMP"/lua_compile_worker_*.json \
        "$SPON_TMP"/lua_compile_chunk_manifest.json \
        "$SPON_TMP"/lua_compile_representatives.json \
        "$SPON_TMP"/lua_compile_representatives.md \
        "$SPON_TMP"/lua_compile_representative_index.json \
        "$SPON_TMP"/lua_compile_alias_map.json \
        "$SPON_TMP"/lua_compile_grammar_coverage.json \
        "$SPON_TMP"/worker_*.log \
        "$SPON_TMP"/build_config.env
fi

cat > "$SPON_TMP/build_config.env" <<EOF
CHUNKS=$CHUNKS
WORKERS=$WORKERS
MAX_ARITY=$MAX_ARITY
MAX_FACT_COMBOS=$MAX_FACT_COMBOS
WORKER_PROGRESS_SEQS=$WORKER_PROGRESS_SEQS
SPON_TMP=$SPON_TMP
ARTIFACT_SCHEMA=sponjit.lua_compile_foundry.v3
EOF

log "config: chunks=$CHUNKS workers=$WORKERS max_arity=$MAX_ARITY max_fact_combos=$MAX_FACT_COMBOS out=$SPON_TMP"

log "1/3 LuaCompile grammar/window plan"
luajit -e '
package.path = "../?.lua;../?/init.lua;?.lua;?/init.lua;src/?.lua;src/?/init.lua;../../../lua/?.lua;../../../lua/?/init.lua;" .. package.path
local Foundry = require("lua_compile.lua_compile_foundry")
local chunks = tonumber(os.getenv("CHUNKS") or "8") or 8
local tmp = assert(os.getenv("SPON_TMP"), "SPON_TMP unset")
local config = {
  max_arity = tonumber(os.getenv("MAX_ARITY") or "2") or 2,
  max_fact_combos = tonumber(os.getenv("MAX_FACT_COMBOS") or "32") or 32,
}
local windows = Foundry.grammar_windows(config)
local buckets = {}
for i = 1, chunks do buckets[i] = { windows = {}, estimated_compiles = 0 } end
for i, w in ipairs(windows) do
  local ci = ((i - 1) % chunks) + 1
  buckets[ci].windows[#buckets[ci].windows + 1] = w
  local bundles = Foundry.fact_bundles_for_ops(w.ops, config)
  buckets[ci].estimated_compiles = buckets[ci].estimated_compiles + #bundles
end
local manifest = { schema = "sponjit.lua_compile_foundry.plan.v1", chunks = chunks, windows = #windows, max_arity = config.max_arity, max_fact_combos = config.max_fact_combos, buckets = {} }
for ci = 1, chunks do
  Foundry.write_json(tmp .. "/lua_compile_chunk_" .. ci .. ".json", { schema = "sponjit.lua_compile_foundry.chunk.v1", chunk = ci, windows = buckets[ci].windows })
  manifest.buckets[#manifest.buckets + 1] = { chunk = ci, windows = #buckets[ci].windows, estimated_compiles = buckets[ci].estimated_compiles }
end
Foundry.write_json(tmp .. "/lua_compile_chunk_manifest.json", manifest)
io.stderr:write(string.format("[plan] windows=%d chunks=%d\n", #windows, chunks))
'

log "2/3 LuaCompile workers ($WORKERS jobs over $CHUNKS chunks)"
seq 1 "$CHUNKS" | xargs -P "$WORKERS" -I{} sh -c '
  set -e
  ci="$1"
  log="$SPON_TMP/worker_${ci}.log"
  echo "[worker ${ci}] START" >&2
  luajit src/worker_compile.lua "$ci" >"$log" 2>&1
  tail -n 3 "$log" >&2 || true
  echo "[worker ${ci}] DONE log=$log" >&2
' sh {}

log "3/3 merge semantic representatives"
luajit -e '
package.path = "../?.lua;../?/init.lua;?.lua;?/init.lua;src/?.lua;src/?/init.lua;../../../lua/?.lua;../../../lua/?/init.lua;" .. package.path
local Foundry = require("lua_compile.lua_compile_foundry")
local chunks = tonumber(os.getenv("CHUNKS") or "8") or 8
local tmp = assert(os.getenv("SPON_TMP"), "SPON_TMP unset")

local function alias_key(a)
  return tostring(a.ops_key or "")
end

local reps_by_key, reps, alias_map = {}, {}, {}
local merged = {
  schema = "sponjit.lua_compile_foundry.v3",
  representatives = reps,
  alias_map = alias_map,
  rejection_reasons = {},
  stats = { windows = 0, compiles = 0, ok = 0, rejected = 0, unique_representatives = 0 },
  generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
}

for ci = 1, chunks do
  local r = Foundry.read_json(tmp .. "/lua_compile_worker_" .. ci .. ".json")
  local s = r.stats or {}
  merged.stats.windows = merged.stats.windows + (tonumber(s.windows) or 0)
  merged.stats.compiles = merged.stats.compiles + (tonumber(s.compiles) or 0)
  merged.stats.ok = merged.stats.ok + (tonumber(s.ok) or 0)
  merged.stats.rejected = merged.stats.rejected + (tonumber(s.rejected) or 0)
  for reason, count in pairs(r.rejection_reasons or {}) do
    merged.rejection_reasons[reason] = (merged.rejection_reasons[reason] or 0) + (tonumber(count) or 0)
  end
  for _, a in ipairs(r.alias_map or {}) do alias_map[#alias_map + 1] = a end
  for _, rep in ipairs(r.representatives or {}) do
    local key = rep.representative_key
    local out = reps_by_key[key]
    if not out then
      out = {
        representative_id = #reps + 1,
        representative_key = key,
        lalin_cfg_key = rep.lalin_cfg_key,
        stencil_variant_key = rep.stencil_variant_key,
        contract_key = rep.contract_key,
        lalin_cfg_kernel = rep.lalin_cfg_kernel,
        lalin_source = rep.lalin_source,
        aliases = {},
        count = 0,
        alias_by_key = {},
      }
      reps_by_key[key] = out
      reps[#reps + 1] = out
    end
    out.count = out.count + (tonumber(rep.count) or 0)
    for _, a in ipairs(rep.aliases or {}) do
      local ak = alias_key(a)
      local oa = out.alias_by_key[ak]
      if not oa then
        oa = { ops_key = a.ops_key, source_ops = a.source_ops, count = 0, fact_bundles = {} }
        out.alias_by_key[ak] = oa
        out.aliases[#out.aliases + 1] = oa
      end
      oa.count = oa.count + (tonumber(a.count) or 0)
      for _, fb in ipairs(a.fact_bundles or {}) do
        if #oa.fact_bundles < 4 then oa.fact_bundles[#oa.fact_bundles + 1] = fb end
      end
    end
  end
end

table.sort(reps, function(a, b)
  if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
  return tostring(a.representative_key) < tostring(b.representative_key)
end)
local id_by_key = {}
for i, r in ipairs(reps) do r.representative_id = i; r.alias_by_key = nil; id_by_key[r.representative_key] = i end
for _, a in ipairs(alias_map) do if a.representative_key then a.representative_id = id_by_key[a.representative_key] end end
merged.stats.unique_representatives = #reps
Foundry.write_artifacts(merged, tmp)
io.stderr:write(string.format("[merge] reps=%d compiles=%d ok=%d rejected=%d\n", merged.stats.unique_representatives or 0, merged.stats.compiles or 0, merged.stats.ok or 0, merged.stats.rejected or 0))
'

log "done: $SPON_TMP/lua_compile_representatives.json"
