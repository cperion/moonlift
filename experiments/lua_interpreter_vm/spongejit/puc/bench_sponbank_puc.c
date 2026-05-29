/* bench_sponbank_puc.c — current PUC Lua 5.5 ↔ SponBank benchmark.
 *
 * This intentionally does not use the old patched-VM cache path. It compares:
 *   1. real execution time of a Lua program on the vendored PUC Lua runtime;
 *   2. current libsponbank selector and copy/patch materialization cost for the
 *      actual PUC opcodes extracted from that loaded program's Proto tree.
 *
 * The SponBank side measures selection/materialization, not semantic execution
 * of Lua. That is the current honest boundary until the VM bridge consumes the
 * bank's SponHoleReloc metadata directly.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "lprefix.h"
#include "lstate.h"
#include "lobject.h"
#include "lopcodes.h"

#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
#endif

typedef uint64_t SponFactSig;
typedef uint32_t SponTileId;
typedef struct { SponTileId tile_id; uint32_t pc_start; uint32_t pc_end; } SponTileChoice;
typedef struct { uint64_t pattern_probes; uint64_t candidate_checks; uint32_t choices; } SponSelectStats;
typedef struct { uint32_t code_offset; uint16_t hole_id; uint16_t reloc_kind; uint16_t role_kind; uint16_t op_idx; int32_t role_arg; } SponHoleReloc;
typedef struct { SponTileId tile_id; uint32_t offset; uint32_t size; uint32_t hole_start; uint32_t slotmap_start; uint16_t len; uint16_t n_holes; uint16_t n_slotmaps; uint16_t reserved; SponFactSig fact_sig; uint64_t pattern_key; SponFactSig required_sig; SponFactSig checked_sig; SponFactSig produced_sig; SponFactSig killed_sig; } SponTileDesc;

extern uint32_t spon_bank_tile_count(void);
extern uint32_t spon_bank_pattern_count(void);
extern uint32_t spon_bank_hole_count(void);
extern const SponTileDesc *spon_get_tile(SponTileId id);
extern const unsigned char *spon_tile_data(SponTileId id);
extern const SponHoleReloc *spon_tile_holes(SponTileId id, uint32_t *out_n);
extern SponTileId spon_l0_for_opcode(uint32_t opcode);
extern const SponTileChoice *spon_select_greedy_stats(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig sig, uint32_t *out_n, SponSelectStats *stats);

/* Keep in sync with src/build_bank.lua. */
enum {
  SPON_HOLE_UNKNOWN=0, SPON_HOLE_SLOT=1, SPON_HOLE_IMM=2, SPON_HOLE_CONST=3,
  SPON_HOLE_BOOL=4, SPON_HOLE_EXIT=5, SPON_HOLE_FAIL=6,
  SPON_HOLE_SHAPE_OFFSET=7, SPON_HOLE_SHAPE_ID=8, SPON_HOLE_METATABLE_OFFSET=9,
  SPON_HOLE_FIELD_OFFSET=10, SPON_HOLE_ARRAY_BASE_OFFSET=11,
  SPON_HOLE_CALL_TARGET=12, SPON_HOLE_BARRIER=13
};

typedef struct {
  uint32_t *v;
  size_t n, cap;
} U32Vec;

static double now_s(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static void die_lua(lua_State *L, const char *what) {
  fprintf(stderr, "%s: %s\n", what, lua_tostring(L, -1));
  exit(1);
}

static void push_u32(U32Vec *xs, uint32_t x) {
  if (xs->n == xs->cap) {
    xs->cap = xs->cap ? xs->cap * 2 : 256;
    xs->v = (uint32_t *)realloc(xs->v, xs->cap * sizeof(uint32_t));
    if (!xs->v) { perror("realloc"); exit(1); }
  }
  xs->v[xs->n++] = x;
}

static void collect_proto_ops(const Proto *p, U32Vec *ops, size_t *proto_count) {
  if (!p) return;
  (*proto_count)++;
  for (int i = 0; i < p->sizecode; i++) push_u32(ops, (uint32_t)GET_OPCODE(p->code[i]));
  for (int i = 0; i < p->sizep; i++) collect_proto_ops(p->p[i], ops, proto_count);
}

static Proto *loaded_proto(lua_State *L) {
  TValue *o = s2v(L->top.p - 1);
  if (!ttisLclosure(o)) return NULL;
  return clLvalue(o)->p;
}

static void install_arg(lua_State *L, const char *script, const char *narg) {
  lua_createtable(L, 2, 0);
  lua_pushstring(L, script); lua_rawseti(L, -2, 0);
  lua_pushstring(L, narg);   lua_rawseti(L, -2, 1);
  lua_setglobal(L, "arg");
}

static double run_lua_once(const char *script, const char *narg) {
  lua_State *L = luaL_newstate();
  if (!L) { fprintf(stderr, "luaL_newstate failed\n"); exit(1); }
  luaL_openlibs(L);
  install_arg(L, script, narg);

  fflush(stdout);
  int saved_stdout = dup(STDOUT_FILENO);
  int devnull = open("/dev/null", O_WRONLY);
  if (devnull >= 0) dup2(devnull, STDOUT_FILENO);

  double t0 = now_s();
  if (luaL_loadfile(L, script) != LUA_OK) die_lua(L, "luaL_loadfile");
  if (lua_pcall(L, 0, 0, 0) != LUA_OK) die_lua(L, "lua_pcall");
  double t1 = now_s();

  fflush(stdout);
  if (saved_stdout >= 0) { dup2(saved_stdout, STDOUT_FILENO); close(saved_stdout); }
  if (devnull >= 0) close(devnull);
  lua_close(L);
  return t1 - t0;
}

static void extract_ops(const char *script, U32Vec *ops, size_t *proto_count) {
  lua_State *L = luaL_newstate();
  if (!L) { fprintf(stderr, "luaL_newstate failed\n"); exit(1); }
  luaL_openlibs(L);
  if (luaL_loadfile(L, script) != LUA_OK) die_lua(L, "luaL_loadfile");
  Proto *p = loaded_proto(L);
  if (!p) { fprintf(stderr, "loaded chunk is not an LClosure\n"); exit(1); }
  collect_proto_ops(p, ops, proto_count);
  lua_close(L);
}

static uint32_t *make_region(const U32Vec *ops, uint32_t region_ops) {
  if (ops->n == 0) { fprintf(stderr, "no PUC opcodes extracted\n"); exit(1); }
  uint32_t *bc = (uint32_t *)malloc((size_t)region_ops * sizeof(uint32_t));
  if (!bc) { perror("malloc"); exit(1); }
  for (uint32_t i = 0; i < region_ops; i++) bc[i] = ops->v[i % ops->n];
  return bc;
}

static uint64_t patch_value(const SponHoleReloc *h, uint32_t pc) {
  switch (h->role_kind) {
    case SPON_HOLE_SLOT: return (uint64_t)((h->role_arg >= 0) ? h->role_arg : 0);
    case SPON_HOLE_IMM: return 1;
    case SPON_HOLE_CONST: return 0;
    case SPON_HOLE_BOOL: return 1;
    case SPON_HOLE_EXIT: return 0;
    case SPON_HOLE_FAIL: return 0;
    case SPON_HOLE_SHAPE_OFFSET: return 0;
    case SPON_HOLE_SHAPE_ID: return 0;
    case SPON_HOLE_METATABLE_OFFSET: return 0;
    case SPON_HOLE_FIELD_OFFSET: return 0;
    case SPON_HOLE_ARRAY_BASE_OFFSET: return 0;
    case SPON_HOLE_CALL_TARGET: return 0;
    case SPON_HOLE_BARRIER: return 0;
    default: return (uint64_t)pc;
  }
}

static void put32(unsigned char *p, uint32_t off, uint32_t v) {
  memcpy(p + off, &v, sizeof(v));
}

static size_t materialize_once(const SponTileChoice *choices, uint32_t nchoices, unsigned char *dst, size_t cap, uint64_t *hole_writes) {
  size_t off = 0;
  for (uint32_t i = 0; i < nchoices; i++) {
    const SponTileDesc *t = spon_get_tile(choices[i].tile_id);
    const unsigned char *src = spon_tile_data(choices[i].tile_id);
    if (!t || !src) continue;
    if (off + t->size > cap) { fprintf(stderr, "materialization buffer too small\n"); exit(1); }
    memcpy(dst + off, src, t->size);
    uint32_t nh = 0;
    const SponHoleReloc *hs = spon_tile_holes(choices[i].tile_id, &nh);
    for (uint32_t j = 0; j < nh; j++) {
      uint32_t loc = (uint32_t)off + hs[j].code_offset;
      put32(dst, loc, (uint32_t)patch_value(&hs[j], choices[i].pc_start + hs[j].op_idx));
      (*hole_writes)++;
    }
    off += t->size;
  }
  return off;
}

static int cmp_double(const void *a, const void *b) {
  double da = *(const double *)a, db = *(const double *)b;
  return (da > db) - (da < db);
}

int main(int argc, char **argv) {
  const char *script = argc > 1 ? argv[1] : "experiments/lua_interpreter_vm/spongejit/bench/programs/int_loop.lua";
  const char *narg = argc > 2 ? argv[2] : "50000000";
  uint32_t region_ops = argc > 3 ? (uint32_t)strtoul(argv[3], NULL, 10) : 4096;
  uint32_t select_iters = argc > 4 ? (uint32_t)strtoul(argv[4], NULL, 10) : 200000;
  uint32_t mat_iters = argc > 5 ? (uint32_t)strtoul(argv[5], NULL, 10) : 20000;
  uint32_t lua_reps = argc > 6 ? (uint32_t)strtoul(argv[6], NULL, 10) : 5;

  U32Vec ops = {0};
  size_t proto_count = 0;
  extract_ops(script, &ops, &proto_count);
  uint32_t *bc = make_region(&ops, region_ops);

  uint32_t missing_l0 = 0;
  for (uint32_t i = 0; i < 85; i++) if (spon_l0_for_opcode(i) == 0) missing_l0++;

  double *lua_times = (double *)calloc(lua_reps, sizeof(double));
  if (!lua_times) { perror("calloc"); exit(1); }
  for (uint32_t r = 0; r < lua_reps; r++) lua_times[r] = run_lua_once(script, narg);
  qsort(lua_times, lua_reps, sizeof(double), cmp_double);
  double lua_sum = 0.0;
  for (uint32_t r = 0; r < lua_reps; r++) lua_sum += lua_times[r];

  uint32_t nchoices = 0;
  SponSelectStats st = {0};
  const SponTileChoice *choices = spon_select_greedy_stats(bc, 0, region_ops, 0, &nchoices, &st);

  size_t image_size = 0, image_holes = 0;
  uint32_t arity_hist[5] = {0,0,0,0,0};
  for (uint32_t i = 0; i < nchoices; i++) {
    const SponTileDesc *t = spon_get_tile(choices[i].tile_id);
    if (!t) continue;
    image_size += t->size;
    image_holes += t->n_holes;
    uint32_t len = choices[i].pc_end - choices[i].pc_start;
    if (len <= 4) arity_hist[len]++;
  }

  volatile uint64_t sink = 0;
  double t0 = now_s();
  for (uint32_t i = 0; i < select_iters; i++) {
    uint32_t n = 0;
    SponSelectStats s = {0};
    const SponTileChoice *c = spon_select_greedy_stats(bc, 0, region_ops, 0, &n, &s);
    sink += n + s.pattern_probes + s.candidate_checks + c[0].tile_id;
  }
  double t1 = now_s();

  unsigned char *buf = (unsigned char *)malloc(image_size ? image_size : 1);
  if (!buf) { perror("malloc"); exit(1); }
  uint64_t hole_writes = 0;
  double t2 = now_s();
  for (uint32_t i = 0; i < mat_iters; i++) {
    sink += materialize_once(choices, nchoices, buf, image_size, &hole_writes);
  }
  double t3 = now_s();

  printf("# PUC Lua 5.5 vs current SponBank selector/materializer\n");
  printf("program: %s %s\n", script, narg);
  printf("bank: tiles=%u patterns=%u holes=%u l0_missing=%u\n", spon_bank_tile_count(), spon_bank_pattern_count(), spon_bank_hole_count(), missing_l0);
  printf("proto_count=%zu extracted_opcodes=%zu region_ops=%u\n", proto_count, ops.n, region_ops);
  printf("puc_lua: reps=%u avg=%.6f s median=%.6f s min=%.6f s max=%.6f s\n", lua_reps, lua_sum / lua_reps, lua_times[lua_reps / 2], lua_times[0], lua_times[lua_reps - 1]);
  printf("sponbank_cover: choices=%u avg_arity=%.2f arity=[%u,%u,%u,%u] image_bytes=%zu image_holes=%zu probes=%llu checks=%llu\n",
         nchoices, nchoices ? (double)region_ops / (double)nchoices : 0.0,
         arity_hist[1], arity_hist[2], arity_hist[3], arity_hist[4], image_size, image_holes,
         (unsigned long long)st.pattern_probes, (unsigned long long)st.candidate_checks);
  printf("sponbank_select: %.3f ns/op %.3f ns/tile %.0f ops/s\n",
         (t1 - t0) * 1e9 / ((double)select_iters * region_ops),
         (t1 - t0) * 1e9 / ((double)select_iters * (nchoices ? nchoices : 1)),
         ((double)select_iters * region_ops) / (t1 - t0));
  printf("sponbank_copy_patch: %.3f ns/image %.3f ns/tile %.3f ns/hole %.2f GB/s\n",
         (t3 - t2) * 1e9 / (double)mat_iters,
         (t3 - t2) * 1e9 / ((double)mat_iters * (nchoices ? nchoices : 1)),
         image_holes ? ((t3 - t2) * 1e9 / ((double)mat_iters * image_holes)) : 0.0,
         image_size ? (((double)mat_iters * image_size) / (t3 - t2) / 1e9) : 0.0);
  printf("sink=%llu hole_writes=%llu\n", (unsigned long long)sink, (unsigned long long)hole_writes);

  free(buf); free(lua_times); free(bc); free(ops.v);
  return 0;
}
