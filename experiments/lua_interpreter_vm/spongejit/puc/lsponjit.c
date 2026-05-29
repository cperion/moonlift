#include "lsponjit.h"
#include "sponjit_runtime.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SPON_HOT_THRESHOLD 64u
#define SPON_MAX_REGION_OPS 16u

static unsigned long long spon_stat_probes = 0;
static unsigned long long spon_stat_build_attempts = 0;
static unsigned long long spon_stat_builds = 0;
static unsigned long long spon_stat_build_fails = 0;
static unsigned long long spon_stat_entries = 0;
static unsigned long long spon_stat_exits = 0;
static unsigned long long spon_stat_tail_seams = 0;
static unsigned long long spon_stat_completions = 0;
static int spon_report_registered = 0;

typedef struct SponProtoState {
  uint16_t *hot_counts;
  uint16_t *cooldowns;
  SponFactSig *last_observed;
  SponImage **images;
  uint32_t sizecode;
  int enabled;
} SponProtoState;

static void spon_report(void) {
  const char *e = getenv("SPONJIT_PRINT");
  if (e && e[0] && e[0] != '0')
    fprintf(stderr, "[sponjit] probes=%llu build_attempts=%llu builds=%llu build_fails=%llu entries=%llu completions=%llu tail_seams=%llu exits=%llu\n",
            spon_stat_probes, spon_stat_build_attempts, spon_stat_builds, spon_stat_build_fails,
            spon_stat_entries, spon_stat_completions, spon_stat_tail_seams, spon_stat_exits);
}

static int env_enabled(void) {
  const char *e = getenv("SPONJIT_ENABLE");
  if (!spon_report_registered) { atexit(spon_report); spon_report_registered = 1; }
  return e && e[0] && e[0] != '0';
}

static SponProtoState *state_for_proto(Proto *p) {
  SponProtoState *st = (SponProtoState*)p->sponjit;
  if (st) return st;
  st = (SponProtoState*)calloc(1, sizeof(SponProtoState));
  if (!st) return NULL;
  st->sizecode = (uint32_t)p->sizecode;
  st->enabled = env_enabled();
  st->hot_counts = (uint16_t*)calloc(st->sizecode ? st->sizecode : 1, sizeof(uint16_t));
  st->cooldowns = (uint16_t*)calloc(st->sizecode ? st->sizecode : 1, sizeof(uint16_t));
  st->last_observed = (SponFactSig*)calloc(st->sizecode ? st->sizecode : 1, sizeof(SponFactSig));
  st->images = (SponImage**)calloc(st->sizecode ? st->sizecode : 1, sizeof(SponImage*));
  if (!st->hot_counts || !st->cooldowns || !st->last_observed || !st->images) {
    free(st->hot_counts); free(st->cooldowns); free(st->last_observed); free(st->images); free(st); return NULL;
  }
  p->sponjit = st;
  return st;
}

void luaSponJIT_freeproto(lua_State *L, Proto *p) {
  (void)L;
  if (!p || !p->sponjit) return;
  SponProtoState *st = (SponProtoState*)p->sponjit;
  if (st->images) {
    for (uint32_t i = 0; i < st->sizecode; i++) spon_image_free(st->images[i]);
  }
  free(st->images);
  free(st->last_observed);
  free(st->cooldowns);
  free(st->hot_counts);
  free(st);
  p->sponjit = NULL;
}

static int is_region_stop(OpCode op) {
  switch (op) {
    case OP_JMP: case OP_RETURN: case OP_RETURN0: case OP_RETURN1:
    case OP_CALL: case OP_TAILCALL: case OP_TFORCALL:
    case OP_FORPREP: case OP_FORLOOP: case OP_TFORPREP: case OP_TFORLOOP:
    case OP_CLOSE: case OP_TBC: case OP_VARARGPREP:
      return 1;
    default:
      return 0;
  }
}

static int is_region_start_allowed(const Proto *p, uint32_t pc_start) {
  OpCode op;
  if (!p || pc_start >= (uint32_t)p->sizecode) return 0;
  op = GET_OPCODE(p->code[pc_start]);
  if (is_region_stop(op)) return 0;
  if (op == OP_MMBIN || op == OP_MMBINI || op == OP_MMBINK) return 0;
  return 1;
}

static uint32_t region_end_for(const Proto *p, uint32_t pc_start) {
  uint32_t end = pc_start;
  while (end < (uint32_t)p->sizecode && end - pc_start < SPON_MAX_REGION_OPS) {
    OpCode op = GET_OPCODE(p->code[end]);
    end++;
    if (is_region_stop(op)) break;
  }
  return end;
}

static SponImage *build_image_for(lua_State *L, Proto *p, StkId base, uint32_t pc_start) {
  uint32_t pc_end;
  if (!is_region_start_allowed(p, pc_start)) return NULL;
  pc_end = region_end_for(p, pc_start);
  if (pc_end <= pc_start) return NULL;
  SponFactSig entry_sig = 0;  /* only predecessor/entry proven facts live here */
  SponFactSig observed_sig = spon_observe_i64_slots(base, p->maxstacksize);
  SponImage *img = NULL;
  if (!spon_image_build(L, p, pc_start, pc_end, entry_sig, observed_sig, &img)) {
    const char *tr = getenv("SPONJIT_TRACE_BUILD");
    if (tr && tr[0] && tr[0] != '0')
      fprintf(stderr, "[sponjit] build_fail pc=%u end=%u op=%u observed=0x%llx\n",
              pc_start, pc_end, (unsigned)GET_OPCODE(p->code[pc_start]), (unsigned long long)observed_sig);
    return NULL;
  }
  return img;
}

int luaSponJIT_maybe_enter(lua_State *L, CallInfo *ci, Proto *p, StkId base,
                           const Instruction **ppc, Instruction i, int trap) {
  (void)ci;
  if (trap) return 0;              /* hooks/debug/trap path stays in interpreter */
  if (!p || !ppc || !*ppc) return 0;
  if (!env_enabled()) return 0;

  const Instruction *curpc = *ppc - 1;
  if (curpc < p->code || curpc >= p->code + p->sizecode) return 0;
  uint32_t pc = (uint32_t)(curpc - p->code);

  SponProtoState *st = state_for_proto(p);
  if (!st || !st->enabled || pc >= st->sizecode) return 0;

  spon_stat_probes++;
  SponImage *img = st->images[pc];
  if (!img) {
    SponFactSig observed_now = spon_observe_i64_slots(base, p->maxstacksize);
    if (st->last_observed[pc] != observed_now) {
      st->last_observed[pc] = observed_now;
      st->hot_counts[pc] = 0;
      st->cooldowns[pc] = 0;
      return 0;
    }
    if (st->cooldowns[pc] > 0) { st->cooldowns[pc]--; return 0; }
    if (st->hot_counts[pc] < SPON_HOT_THRESHOLD) {
      st->hot_counts[pc]++;
      return 0;
    }
    spon_stat_build_attempts++;
    img = build_image_for(L, p, base, pc);
    if (!img) {
      spon_stat_build_fails++;
      st->hot_counts[pc] = 0;
      st->cooldowns[pc] = 1024;
      return 0;
    }
    st->images[pc] = img;
    spon_stat_builds++;
  }

  uint32_t resume_pc = pc;
  spon_stat_entries++;
  int r = spon_image_execute(img, base, p, &resume_pc);
  if (r == 0 || resume_pc > (uint32_t)p->sizecode || resume_pc <= pc) {
    st->images[pc] = NULL;
    spon_image_free(img);
    st->hot_counts[pc] = 0;
    st->cooldowns[pc] = 1024;
    spon_stat_exits++;
    return 0;
  }

  if (r == 2) {
    spon_stat_exits++;
    st->images[pc] = NULL;
    spon_image_free(img);
    st->hot_counts[pc] = 0;
    st->cooldowns[pc] = 256;
  }
  else if (r == 3) {
    spon_stat_tail_seams++;
  }
  else {
    spon_stat_completions++;
  }

  *ppc = p->code + resume_pc;
  (void)i;
  return 1;
}
