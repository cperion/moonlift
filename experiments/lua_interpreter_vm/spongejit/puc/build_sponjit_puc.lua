#!/usr/bin/env luajit
-- Build reproducible vanilla and SponJIT-instrumented PUC Lua binaries.
-- The SponJIT binary includes precompiled stencil cache entries from the foundry.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/build_sponjit_puc%.lua$") or "experiments/lua_interpreter_vm/spongejit"
local repo = spongejit:sub(1, 1) == "/" and spongejit:gsub("/experiments/lua_interpreter_vm/spongejit$", "") or "."

local function q(s) return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'" end
local function run(cmd)
  io.stderr:write("[puc-build] ", cmd, "\n")
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then error("command failed: " .. cmd) end
end
local function read(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("*a"); f:close(); return s
end
local function write(path, data)
  local f = assert(io.open(path, "wb"), path)
  f:write(data); f:close()
end
local function replace_once(s, old, new, label)
  local n
  s, n = s:gsub(old:gsub("([^%w])", "%%%1"), function() return new end, 1)
  if n ~= 1 then error("patch failed: " .. label .. " matches=" .. tostring(n)) end
  return s
end

-- ── SponJIT block inserted into lvm.c after #include "lvm.h" ──────
local SPONJIT_BLOCK = read(spongejit .. "/puc/sponjit_block.h")
if not SPONJIT_BLOCK then error("missing sponjit_block.h") end

-- ── Patch functions ────────────────────────────────────────────────
local VMFETCH_OLD = [[#define vmfetch()	{ \
  if (l_unlikely(trap)) {  /* stack reallocation or hooks? */ \
    trap = luaG_traceexec(L, pc);  /* handle hooks */ \
    updatebase(ci);  /* correct stack */ \
  } \
  i = *(pc++); \
}

#define vmdispatch(o)	switch(o)]]

local VMFETCH_NEW = [[#define vmfetch()	{ \
  if (l_unlikely(trap)) {  /* stack reallocation or hooks? */ \
    trap = luaG_traceexec(L, pc);  /* handle hooks */ \
    updatebase(ci);  /* correct stack */ \
  } \
  i = *(pc++); \
}

/* Cache-first region lookup. */
#define SPONJIT_TRY_CACHE() { \
  moonlift_sponjit_init_if_needed(); \
  SPONJIT_INC(moonlift_sponjit_dispatch_entries); \
  if (moonlift_sponjit_enabled) { \
    SponJitRegionFn _sj_fn; \
    uint32_t _sj_nops; \
    SPONJIT_INC(moonlift_sponjit_cache_probes); \
    if (sponjit_cache_lookup(cl->p, pc - 1, &_sj_fn, &_sj_nops)) { \
      StencilCtx _sj_ctx; \
      (void)_sj_nops; \
      if (moonlift_sponjit_trace_left > 0) { \
        fprintf(stderr, "[sponjit-enter] pc=%d op=%d nops=%u\n", \
          (int)(pc - 1 - cl->p->code), (int)GET_OPCODE(i), (unsigned)_sj_nops); \
      } \
      _sj_ctx.base = base; _sj_ctx.k = k; _sj_ctx.pc = pc - 1; \
      _sj_ctx.current = 0; _sj_ctx.acc = 0; _sj_ctx.status = 0; \
      _sj_ctx.load_count = 0; _sj_ctx.store_count = 0; _sj_ctx.unbox_count = 0; \
      setnilvalue(&_sj_ctx.scratch); \
      _sj_fn(&_sj_ctx); \
      if (moonlift_sponjit_trace_left > 0) { \
        fprintf(stderr, "[sponjit-trace] pc=%d op=%d status=%d nops=%u ctxpc=%d\n", \
          (int)(pc - 1 - cl->p->code), (int)GET_OPCODE(i), _sj_ctx.status, (unsigned)_sj_nops, (int)(_sj_ctx.pc - cl->p->code)); \
        moonlift_sponjit_trace_left--; \
      } \
      if (_sj_ctx.status == 0) { \
        SPONJIT_INC(moonlift_sponjit_cache_hits); \
        SPONJIT_ADD(moonlift_sponjit_absorbed_ops, _sj_nops); \
        pc = pc - 1 + _sj_nops; \
        updatetrap(ci); \
        continue; \
      } \
    } \
  } \
}

#define vmdispatch(o)	switch(o)]]

local CALL_OLD = [[    lua_assert(luaP_isIT(i) || (cast_void(L->top.p = base), 1));
    vmdispatch (GET_OPCODE(i)) {]]
local CALL_NEW = [[    lua_assert(luaP_isIT(i) || (cast_void(L->top.p = base), 1));
    SPONJIT_TRY_CACHE();
    vmdispatch (GET_OPCODE(i)) {]]

local function patch_sponjit_lvm(path)
  local s = read(path)
  s = replace_once(s, '#include "lvm.h"\n', '#include "lvm.h"\n' .. SPONJIT_BLOCK, "insert sponjit block")
  s = replace_once(s, VMFETCH_OLD, VMFETCH_NEW, "replace vmfetch")
  s = replace_once(s, CALL_OLD, CALL_NEW, "insert cache-probe")
  s = replace_once(s, '  cl = ci_func(ci);\n  k = cl->p->k;\n  pc = ci->u.l.savedpc;',
    '  cl = ci_func(ci);\n  moonlift_sponjit_init_if_needed();\n  if (moonlift_sponjit_enabled > 0) sponjit_scan_proto(cl->p);\n  k = cl->p->k;\n  pc = ci->u.l.savedpc;',
    "insert proto scanner")
  -- Append generated cache data (stencil bytes + descriptors)
  local cache_data = spongejit .. "/build/sponjit_cache_data.c"
  local cache_src = read(cache_data)
  if cache_src then
    s = s .. "\n/* SponJIT GENERATED CACHE DATA */\n" .. cache_src .. "\n"
  end
  write(path, s)
end

local function patch_sponjit_jumptable(path)
  local s = read(path)
  s = replace_once(s,
    '#define vmbreak\t\tvmfetch(); vmdispatch(GET_OPCODE(i));',
    '#define vmbreak\t\tvmfetch(); SPONJIT_TRY_CACHE(); vmdispatch(GET_OPCODE(i));',
    "insert cache-probe in jumptable")
  write(path, s)
end

-- ── Build ──────────────────────────────────────────────────────────
local out = spongejit .. "/build"
local baseline = out .. "/puc_baseline"
local sponjit = out .. "/puc_sponjit"
local vendor = repo .. "/.vendor/Lua"

run("mkdir -p " .. q(out))
run("rm -rf " .. q(baseline) .. " " .. q(sponjit))
run("cp -R " .. q(vendor) .. " " .. q(baseline))
run("cp -R " .. q(vendor) .. " " .. q(sponjit))
patch_sponjit_lvm(sponjit .. "/lvm.c")
patch_sponjit_jumptable(sponjit .. "/ljumptab.h")
run("cd " .. q(baseline) .. " && make -s -j")
run("cd " .. q(sponjit) .. " && make -s -j 2> build_warnings.log")

print("baseline=" .. baseline .. "/lua")
print("sponjit=" .. sponjit .. "/lua")
