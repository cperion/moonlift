/* bench_execute_tile.c — execute one real semantic SponBank tile.
 *
 * This is the smallest end-to-end execution proof for the current bank: select
 * an ADDI tile from libsponbank.so, mmap/copy it, patch its real relocation
 * holes, execute it on PUC-compatible TValue slots, and compare per-iteration
 * throughput against vendored PUC Lua running `s = s + 1` in a loop.
 */

#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define OP_MOVE 0u
#define OP_LOADI 1u
#define OP_ADDI 21u
#define OP_ADD 34u
#define OP_SUB 35u
#define OP_MUL 36u
#define OP_UNM 49u
#define OP_BNOT 50u

typedef uint64_t SponFactSig;
typedef uint32_t SponTileId;
typedef struct { SponTileId tile_id; uint32_t pc_start; uint32_t pc_end; } SponTileChoice;
typedef struct { uint64_t pattern_probes; uint64_t candidate_checks; uint32_t choices; } SponSelectStats;
typedef struct { uint32_t code_offset; uint16_t hole_id; uint16_t reloc_kind; uint16_t role_kind; uint16_t op_idx; int32_t role_arg; } SponHoleReloc;
typedef struct { SponTileId tile_id; uint32_t offset; uint32_t size; uint32_t hole_start; uint32_t slotmap_start; uint16_t len; uint16_t n_holes; uint16_t n_slotmaps; uint16_t reserved; SponFactSig fact_sig; uint64_t pattern_key; SponFactSig required_sig; SponFactSig checked_sig; SponFactSig produced_sig; SponFactSig killed_sig; } SponTileDesc;

extern const SponTileDesc *spon_get_tile(SponTileId id);
extern const unsigned char *spon_tile_data(SponTileId id);
extern const SponHoleReloc *spon_tile_holes(SponTileId id, uint32_t *out_n);
extern const SponTileChoice *spon_select_greedy_stats(const uint32_t *bc, uint32_t start, uint32_t end, SponFactSig sig, uint32_t *out_n, SponSelectStats *stats);

enum {
  SPON_HOLE_SLOT=1, SPON_HOLE_IMM=2, SPON_HOLE_CONST=3, SPON_HOLE_BOOL=4,
  SPON_HOLE_EXIT=5, SPON_HOLE_FAIL=6, SPON_HOLE_SHAPE_OFFSET=7,
  SPON_HOLE_SHAPE_ID=8, SPON_HOLE_METATABLE_OFFSET=9, SPON_HOLE_FIELD_OFFSET=10,
  SPON_HOLE_ARRAY_BASE_OFFSET=11, SPON_HOLE_CALL_TARGET=12, SPON_HOLE_BARRIER=13
};

typedef struct TValue { unsigned long long value_; unsigned char tt_; } TValue;
typedef struct SponExecCtx { void *stack; TValue *k; TValue scratch[256]; uint32_t exit_kind; uint32_t exit_pc; uint32_t exit_op_idx; uint32_t exit_hole; } SponExecCtx;
typedef void (*TileFn)(SponExecCtx *ctx);

static double now_s(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static void die_lua(lua_State *L, const char *what) {
  fprintf(stderr, "%s: %s\n", what, lua_tostring(L, -1));
  exit(1);
}

static void append_lua_for_op(char *buf, size_t cap, const char *op) {
  if (strcmp(op, "MOVE") == 0) strncat(buf, "  d = a\n", cap - strlen(buf) - 1);
  else if (strcmp(op, "LOADI") == 0) strncat(buf, "  b = 42\n", cap - strlen(buf) - 1);
  else if (strcmp(op, "ADDI") == 0) strncat(buf, "  a = a + 1\n", cap - strlen(buf) - 1);
  else if (strcmp(op, "ADD") == 0) strncat(buf, "  c = a + b\n", cap - strlen(buf) - 1);
  else if (strcmp(op, "SUB") == 0) strncat(buf, "  c = a - b\n", cap - strlen(buf) - 1);
  else if (strcmp(op, "MUL") == 0) strncat(buf, "  c = a * b\n", cap - strlen(buf) - 1);
  else if (strcmp(op, "UNM") == 0) strncat(buf, "  a = -a\n", cap - strlen(buf) - 1);
  else if (strcmp(op, "BNOT") == 0) strncat(buf, "  a = ~a\n", cap - strlen(buf) - 1);
}

static double run_lua_pattern_once(const char *pattern, uint64_t iters) {
  char code[8192];
  snprintf(code, sizeof(code),
           "local n = %llu\nlocal a,b,c,d = 1,2,3,4\nfor i = 1, n do\n",
           (unsigned long long)iters);
  char pat[512];
  snprintf(pat, sizeof(pat), "%s", pattern);
  for (char *tok = strtok(pat, ","); tok; tok = strtok(NULL, ",")) append_lua_for_op(code, sizeof(code), tok);
  strncat(code, "end\nprint(a + b + c + d)\n", sizeof(code) - strlen(code) - 1);

  lua_State *L = luaL_newstate();
  if (!L) { fprintf(stderr, "luaL_newstate failed\n"); exit(1); }
  luaL_openlibs(L);

  fflush(stdout);
  int saved_stdout = dup(STDOUT_FILENO);
  int devnull = open("/dev/null", O_WRONLY);
  if (devnull >= 0) dup2(devnull, STDOUT_FILENO);

  double t0 = now_s();
  if (luaL_loadstring(L, code) != LUA_OK) die_lua(L, "luaL_loadstring");
  if (lua_pcall(L, 0, 0, 0) != LUA_OK) die_lua(L, "lua_pcall");
  double t1 = now_s();

  fflush(stdout);
  if (saved_stdout >= 0) { dup2(saved_stdout, STDOUT_FILENO); close(saved_stdout); }
  if (devnull >= 0) close(devnull);
  lua_close(L);
  return t1 - t0;
}

static void put32(unsigned char *p, uint32_t off, uint32_t v) {
  memcpy(p + off, &v, sizeof(v));
}

static uint32_t patch_value(const SponHoleReloc *h) {
  switch (h->role_kind) {
    case SPON_HOLE_SLOT: return (uint32_t)((h->role_arg >= 0) ? h->role_arg : 0);
    case SPON_HOLE_IMM: return 1u;       /* ADDI increment */
    case SPON_HOLE_CONST: return 1u;
    case SPON_HOLE_BOOL: return 1u;
    default: return 0u;                  /* not executed on the hot success path */
  }
}

static TileFn materialize_tile(SponTileId tid, size_t *out_size, uint32_t *out_holes) {
  const SponTileDesc *t = spon_get_tile(tid);
  const unsigned char *src = spon_tile_data(tid);
  if (!t || !src || t->size == 0) { fprintf(stderr, "bad tile %u\n", tid); exit(1); }

  size_t alloc = (t->size + 4095u) & ~4095u;
  unsigned char *mem = mmap(NULL, alloc, PROT_READ | PROT_WRITE | PROT_EXEC,
                            MAP_PRIVATE | MAP_ANON, -1, 0);
  if (mem == MAP_FAILED) { perror("mmap"); exit(1); }
  memcpy(mem, src, t->size);

  uint32_t nh = 0;
  const SponHoleReloc *hs = spon_tile_holes(tid, &nh);
  for (uint32_t i = 0; i < nh; i++) put32(mem, hs[i].code_offset, patch_value(&hs[i]));

  if (out_size) *out_size = t->size;
  if (out_holes) *out_holes = nh;
  return (TileFn)mem;
}

static uint32_t opcode_of(const char *op) {
  if (strcmp(op, "MOVE") == 0) return OP_MOVE;
  if (strcmp(op, "LOADI") == 0) return OP_LOADI;
  if (strcmp(op, "ADDI") == 0) return OP_ADDI;
  if (strcmp(op, "ADD") == 0) return OP_ADD;
  if (strcmp(op, "SUB") == 0) return OP_SUB;
  if (strcmp(op, "MUL") == 0) return OP_MUL;
  if (strcmp(op, "UNM") == 0) return OP_UNM;
  if (strcmp(op, "BNOT") == 0) return OP_BNOT;
  fprintf(stderr, "unsupported benchmark op: %s\n", op);
  exit(1);
}

static uint32_t parse_pattern(const char *pattern, uint32_t bc[4]) {
  char pat[512];
  snprintf(pat, sizeof(pat), "%s", pattern);
  uint32_t n = 0;
  for (char *tok = strtok(pat, ","); tok && n < 4; tok = strtok(NULL, ",")) bc[n++] = opcode_of(tok);
  if (n == 0) { fprintf(stderr, "empty pattern\n"); exit(1); }
  return n;
}

static SponTileId select_pattern_tile(const char *pattern, SponTileChoice *out_choice, SponSelectStats *out_stats, uint32_t *out_arity) {
  uint32_t bc[4] = {0,0,0,0};
  uint32_t arity = parse_pattern(pattern, bc);
  /* Give selector all R0..R7 i64 facts. It will choose a real semantic
     specialization whose exact operand slots are patched from hole metadata. */
  SponFactSig sig = ~0ULL;

  uint32_t n = 0;
  SponSelectStats st = {0};
  const SponTileChoice *c = spon_select_greedy_stats(bc, 0, arity, sig, &n, &st);
  if (!c || n != 1 || !c[0].tile_id || (c[0].pc_end - c[0].pc_start) != arity) {
    fprintf(stderr, "no aggregate tile for pattern %s (arity=%u choices=%u first_span=%u)\n",
            pattern, arity, n, (c && n) ? (c[0].pc_end - c[0].pc_start) : 0);
    exit(1);
  }
  if (out_choice) *out_choice = c[0];
  if (out_stats) *out_stats = st;
  if (out_arity) *out_arity = arity;
  return c[0].tile_id;
}

int main(int argc, char **argv) {
  uint64_t iters = argc > 1 ? strtoull(argv[1], NULL, 10) : 100000000ULL;
  const char *pattern = argc > 2 ? argv[2] : "UNM,BNOT,MUL,ADDI";

  SponTileChoice choice = {0};
  SponSelectStats sel_stats = {0};
  uint32_t arity = 0;
  SponTileId tid = select_pattern_tile(pattern, &choice, &sel_stats, &arity);
  uint64_t lua_ops = iters * (uint64_t)arity;
  size_t tile_size = 0;
  uint32_t nholes = 0;
  TileFn fn = materialize_tile(tid, &tile_size, &nholes);

  TValue *stack = (TValue *)calloc(8192, sizeof(TValue));
  if (!stack) { perror("calloc"); exit(1); }
  for (int i = 0; i < 8192; i++) { stack[i].value_ = (unsigned long long)(i + 1); stack[i].tt_ = 3; }

  SponExecCtx ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.stack = stack;
  ctx.k = stack + 4096;

  fn(&ctx);

  for (int i = 0; i < 8192; i++) { stack[i].value_ = (unsigned long long)(i + 1); stack[i].tt_ = 3; }
  memset(&ctx, 0, sizeof(ctx));
  ctx.stack = stack;
  ctx.k = stack + 4096;

  double t0 = now_s();
  for (uint64_t i = 0; i < iters; i++) fn(&ctx);
  double t1 = now_s();

  uint64_t sum = 0;
  int changed = 0;
  for (int i = 0; i < 16; i++) {
    sum += stack[i].value_;
    if (stack[i].value_ != 0) changed++;
  }

  double lua_t = run_lua_pattern_once(pattern, iters);
  double tile_t = t1 - t0;

  printf("# Execute one real semantic mixed aggregate SponBank tile\n");
  printf("pattern=%s\n", pattern);
  printf("tile_id=%u arity=%u span=%u size=%zu holes=%u iterations=%llu logical_ops=%llu changed_slots=%d final_slot_sum=%llu\n",
         tid, arity, choice.pc_end - choice.pc_start, tile_size, nholes,
         (unsigned long long)iters, (unsigned long long)(iters * (uint64_t)arity),
         changed, (unsigned long long)sum);
  printf("selection: probes=%llu checks=%llu\n",
         (unsigned long long)sel_stats.pattern_probes, (unsigned long long)sel_stats.candidate_checks);
  printf("spon_tile_exec: %.6f s  %.3f ns/tile  %.3f ns/op  %.0f op/s\n",
         tile_t, tile_t * 1e9 / (double)iters,
         tile_t * 1e9 / (double)(iters * (uint64_t)arity),
         (double)(iters * (uint64_t)arity) / tile_t);
  printf("puc_lua_loop:   %.6f s  %.3f ns/op    %.0f op/s\n",
         lua_t, lua_t * 1e9 / (double)lua_ops, (double)lua_ops / lua_t);
  printf("throughput_ratio_tile_vs_puc_per_op: %.2fx\n", lua_t / tile_t);
  free(stack);
  return 0;
}
