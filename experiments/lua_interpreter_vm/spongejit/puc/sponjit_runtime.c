#include "sponjit_runtime.h"
#include "lvm.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define SPON_MAX_LOGICAL_SLOTS 256
#define SPON_FACT_I64_BASE 0u

typedef void (*SponTileFn)(SponExecCtx *ctx);

static size_t page_round(size_t n) {
  long ps = sysconf(_SC_PAGESIZE);
  size_t p = ps > 0 ? (size_t)ps : 4096u;
  return (n + p - 1u) & ~(p - 1u);
}

static uint32_t get_sC(Instruction i) { return (uint32_t)GETARG_sC(i); }
static uint32_t get_sBx(Instruction i) { return (uint32_t)GETARG_sBx(i); }

static uint32_t decode_field(Instruction i, uint8_t field_kind) {
  switch (field_kind) {
    case SPON_FIELD_A: return (uint32_t)GETARG_A(i);
    case SPON_FIELD_B: return (uint32_t)GETARG_B(i);
    case SPON_FIELD_C: return (uint32_t)GETARG_C(i);
    case SPON_FIELD_DEST: return (uint32_t)GETARG_A(i); /* synthetic compare dest has no PUC storage yet */
    default: return 0;
  }
}

static int field_preference(uint16_t role_kind, uint8_t field_kind) {
  if (role_kind == SPON_HOLE_SLOT_STORE) {
    if (field_kind == SPON_FIELD_A || field_kind == SPON_FIELD_DEST) return 100;
    return 10;
  }
  if (field_kind == SPON_FIELD_B) return 100;
  if (field_kind == SPON_FIELD_C) return 90;
  if (field_kind == SPON_FIELD_A) return 80;
  if (field_kind == SPON_FIELD_DEST) return 70;
  return 0;
}

static int actual_slot_for_hole(SponTileId tid, const Proto *p, const uint32_t *actual_pcs,
                                uint32_t n_actual_pcs, const SponHoleReloc *h, uint32_t *out) {
  if (h->role_arg < 0 || h->role_arg >= SPON_MAX_LOGICAL_SLOTS) return 0;
  uint32_t n = 0;
  const SponSlotMapEntry *sms = spon_tile_slotmaps(tid, &n);
  int best = -1;
  uint32_t best_actual = (uint32_t)h->role_arg;
  for (uint32_t i = 0; i < n; i++) {
    if (sms[i].op_idx != h->op_idx || sms[i].logical_slot != (uint8_t)h->role_arg) continue;
    if (sms[i].op_idx >= n_actual_pcs) return 0;
    uint32_t pc = actual_pcs[sms[i].op_idx];
    if (pc >= (uint32_t)p->sizecode) return 0;
    int score = field_preference(h->role_kind, sms[i].field_kind);
    if (score > best) {
      best = score;
      best_actual = decode_field(p->code[pc], sms[i].field_kind);
    }
  }
  *out = best_actual;
  return 1;
}

static void add_actual_slot(SponSlotMapEntry *out, uint32_t *n, uint16_t op_idx, Instruction ins, uint8_t field_kind) {
  out[*n].op_idx = op_idx;
  out[*n].field_kind = field_kind;
  out[*n].logical_slot = (uint8_t)decode_field(ins, field_kind);
  (*n)++;
}

static void append_actual_slots_for_opcode(SponSlotMapEntry *out, uint32_t *n, uint16_t op_idx, OpCode op, Instruction ins) {
  switch (op) {
    case OP_MOVE: add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_B); break;
    case OP_LOADI: case OP_LOADF: case OP_LOADK: case OP_LOADKX: case OP_LOADFALSE: case OP_LFALSESKIP: case OP_LOADTRUE: case OP_LOADNIL:
    case OP_GETUPVAL: case OP_SETUPVAL: case OP_NEWTABLE: case OP_CALL: case OP_TAILCALL: case OP_RETURN: case OP_RETURN1:
    case OP_FORPREP: case OP_FORLOOP: case OP_TFORPREP: case OP_TFORCALL: case OP_TFORLOOP: case OP_SETLIST: case OP_CLOSURE: case OP_VARARG: case OP_GETVARG:
    case OP_CLOSE: case OP_TBC: case OP_ERRNNIL:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); break;
    case OP_GETTABLE: case OP_SETTABLE:
    case OP_ADD: case OP_SUB: case OP_MUL: case OP_MOD: case OP_POW: case OP_DIV: case OP_IDIV:
    case OP_BAND: case OP_BOR: case OP_BXOR: case OP_SHL: case OP_SHR:
    case OP_CONCAT:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_B); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_C); break;
    case OP_GETI: case OP_GETFIELD: case OP_SELF:
    case OP_ADDI: case OP_SHLI: case OP_SHRI:
    case OP_ADDK: case OP_SUBK: case OP_MULK: case OP_MODK: case OP_POWK: case OP_DIVK: case OP_IDIVK:
    case OP_BANDK: case OP_BORK: case OP_BXORK:
    case OP_UNM: case OP_BNOT: case OP_NOT: case OP_LEN:
    case OP_TEST: case OP_TESTSET: case OP_MMBIN: case OP_MMBINK:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_B); break;
    case OP_SETI: case OP_SETFIELD:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_C); break;
    case OP_SETTABUP:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_B); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_C); break;
    case OP_EQ: case OP_LT: case OP_LE:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_B); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_DEST); break;
    case OP_EQK: case OP_MMBINI:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); break;
    case OP_EQI: case OP_LTI: case OP_LEI: case OP_GTI: case OP_GEI:
      add_actual_slot(out, n, op_idx, ins, SPON_FIELD_A); add_actual_slot(out, n, op_idx, ins, SPON_FIELD_DEST); break;
    default:
      break;
  }
}

static int build_actual_slot_stream(const Proto *p, const uint32_t *actual, uint32_t nbc, SponSlotMapEntry **out_slots, uint32_t *out_n) {
  SponSlotMapEntry *slots = (SponSlotMapEntry*)calloc(nbc ? nbc * 5 : 1, sizeof(SponSlotMapEntry));
  uint32_t n = 0;
  if (!slots) return 0;
  for (uint32_t i = 0; i < nbc; i++) {
    uint32_t pc = actual[i];
    if (pc >= (uint32_t)p->sizecode) { free(slots); return 0; }
    Instruction ins = p->code[pc];
    append_actual_slots_for_opcode(slots, &n, (uint16_t)i, GET_OPCODE(ins), ins);
  }
  *out_slots = slots;
  *out_n = n;
  return 1;
}

static uint32_t const_index_for_opcode(OpCode op, Instruction i) {
  switch (op) {
    case OP_LOADK: return (uint32_t)GETARG_Bx(i);
    case OP_GETFIELD: case OP_SETFIELD: case OP_GETI: case OP_SETI:
    case OP_ADDI: case OP_SHLI: case OP_SHRI:
      return (uint32_t)GETARG_C(i);
    default: return (uint32_t)GETARG_C(i);
  }
}

static int patch_value(SponTileId tid, const Proto *p, const uint32_t *actual_pcs, uint32_t n_actual_pcs, const SponHoleReloc *h,
                       uint32_t *out) {
  if (h->op_idx >= n_actual_pcs) return 0;
  uint32_t pc = actual_pcs[h->op_idx];
  Instruction ins = pc < (uint32_t)p->sizecode ? p->code[pc] : 0;
  OpCode op = GET_OPCODE(ins);
  switch (h->role_kind) {
    case SPON_HOLE_SLOT:
    case SPON_HOLE_SLOT_STORE:
      return actual_slot_for_hole(tid, p, actual_pcs, n_actual_pcs, h, out);
    case SPON_HOLE_IMM:
      if (op == OP_LOADI || op == OP_LOADF || op == OP_JMP || op == OP_FORPREP || op == OP_FORLOOP)
        *out = get_sBx(ins);
      else
        *out = get_sC(ins);
      return 1;
    case SPON_HOLE_CONST:
      *out = const_index_for_opcode(op, ins);
      return 1;
    case SPON_HOLE_BOOL:
      *out = (op == OP_LOADTRUE || op == OP_LFALSESKIP) ? 1u : 0u;
      return 1;
    case SPON_HOLE_EXIT:
    case SPON_HOLE_FAIL:
      *out = pc;
      return 1;
    case SPON_HOLE_UNKNOWN:
      *out = 0;
      return 1;
    default:
      /* Shape/table/call-target/barrier holes require dependency epochs and
         payload leases. Refuse the tile unless the runtime can patch them. */
      return 0;
  }
}

static int patch_reloc(unsigned char *base, const SponHoleReloc *h, uint32_t value) {
  unsigned char *loc = base + h->code_offset;
  switch (h->reloc_kind) {
    case SPON_RELOC_ABS32:
    case SPON_RELOC_ABS32S:
      memcpy(loc, &value, sizeof(value));
      return 1;
    case SPON_RELOC_PC32: {
      int32_t rel = (int32_t)((int64_t)(int32_t)value - (int64_t)(intptr_t)(loc + 4));
      memcpy(loc, &rel, sizeof(rel));
      return 1;
    }
    case SPON_RELOC_PLT32:
      return 0; /* generated stencils should not need PLT relocations in images */
    default:
      return 0;
  }
}

static void *materialize_tile(const Proto *p, SponTileId tid, const uint32_t *actual_pcs, uint32_t n_actual_pcs, size_t *out_size) {
  const SponTileDesc *t = spon_get_tile(tid);
  const unsigned char *src = spon_tile_data(tid);
  if (!t || !src || t->size == 0 || !actual_pcs || n_actual_pcs == 0) return NULL;

  size_t alloc = page_round(t->size);
  unsigned char *mem = (unsigned char*)mmap(NULL, alloc, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (mem == MAP_FAILED) return NULL;
  memcpy(mem, src, t->size);

  uint32_t nh = 0;
  const SponHoleReloc *hs = spon_tile_holes(tid, &nh);
  for (uint32_t i = 0; i < nh; i++) {
    uint32_t value = 0;
    if (!patch_value(tid, p, actual_pcs, n_actual_pcs, &hs[i], &value) || !patch_reloc(mem, &hs[i], value)) {
      munmap(mem, alloc);
      return NULL;
    }
  }

  if (mprotect(mem, alloc, PROT_READ | PROT_EXEC) != 0) {
    munmap(mem, alloc);
    return NULL;
  }
  if (out_size) *out_size = alloc;
  return mem;
}

SponFactSig spon_observe_i64_slots(StkId base, uint32_t max_slots) {
  SponFactSig sig = 0;
  if (max_slots > 8) max_slots = 8;
  for (uint32_t i = 0; i < max_slots; i++) {
    if (ttisinteger(s2v(base + i))) sig |= ((SponFactSig)1u << (SPON_FACT_I64_BASE + i));
  }
  return sig;
}

static int is_mmbin_family(OpCode op) {
  return op == OP_MMBIN || op == OP_MMBINI || op == OP_MMBINK;
}

static int has_mmbin_companion(OpCode op) {
  return (OP_ADD <= op && op <= OP_SHR) ||
         (OP_ADDI <= op && op <= OP_SHRI) ||
         (OP_ADDK <= op && op <= OP_BXORK);
}

static uint32_t actual_after_success(const Proto *p, uint32_t pc) {
  uint32_t next = pc + 1;
  if (next < (uint32_t)p->sizecode && has_mmbin_companion(GET_OPCODE(p->code[pc])) && is_mmbin_family(GET_OPCODE(p->code[next])))
    next++;
  return next;
}

static int build_semantic_stream(const Proto *p, uint32_t pc_start, uint32_t pc_end,
                                 uint32_t **out_bc, uint32_t **out_actual, uint32_t **out_after,
                                 uint32_t *out_n) {
  uint32_t cap = pc_end > pc_start ? pc_end - pc_start : 1;
  uint32_t *bc = (uint32_t*)calloc(cap, sizeof(uint32_t));
  uint32_t *actual = (uint32_t*)calloc(cap, sizeof(uint32_t));
  uint32_t *after = (uint32_t*)calloc(cap, sizeof(uint32_t));
  if (!bc || !actual || !after) { free(bc); free(actual); free(after); return 0; }
  uint32_t n = 0;
  for (uint32_t pc = pc_start; pc < pc_end; pc++) {
    OpCode op = GET_OPCODE(p->code[pc]);
    if (is_mmbin_family(op) && pc > pc_start && has_mmbin_companion(GET_OPCODE(p->code[pc - 1])))
      continue;
    bc[n] = (uint32_t)op;
    actual[n] = pc;
    after[n] = actual_after_success(p, pc);
    n++;
  }
  *out_bc = bc; *out_actual = actual; *out_after = after; *out_n = n;
  return n > 0;
}

int spon_image_build(lua_State *L, const Proto *p, uint32_t pc_start, uint32_t pc_end,
                     SponFactSig entry_sig, SponFactSig observed_sig,
                     SponImage **out_image) {
  (void)L;
  if (!p || !out_image || pc_start >= pc_end || pc_end > (uint32_t)p->sizecode) return 0;
  *out_image = NULL;

  uint32_t nbc = 0;
  uint32_t *bc = NULL, *actual = NULL, *after = NULL;
  if (!build_semantic_stream(p, pc_start, pc_end, &bc, &actual, &after, &nbc)) return 0;

  SponSlotMapEntry *actual_slots = NULL;
  uint32_t n_actual_slots = 0;
  if (!build_actual_slot_stream(p, actual, nbc, &actual_slots, &n_actual_slots)) { free(bc); free(actual); free(after); return 0; }

  uint32_t nchoices = 0;
  SponSelectStats stats;
  const SponTileChoice *choices = spon_select_flow_flags_slots_stats(bc, 0, nbc, entry_sig, observed_sig, SPON_TILE_PUC_PATCHABLE, actual_slots, n_actual_slots, &nchoices, &stats);
  if (!choices || nchoices == 0) { free(actual_slots); free(bc); free(actual); free(after); return 0; }

  SponImage *img = (SponImage*)calloc(1, sizeof(SponImage));
  if (!img) { free(actual_slots); free(bc); free(actual); free(after); return 0; }
  img->tiles = (SponPatchedTile*)calloc(nchoices, sizeof(SponPatchedTile));
  if (!img->tiles) { free(img); free(actual_slots); free(bc); free(actual); free(after); return 0; }
  img->pc_start = pc_start;
  img->pc_end = pc_end;
  img->entry_sig = entry_sig;
  img->observed_sig = observed_sig;

  for (uint32_t i = 0; i < nchoices; i++) {
    SponTileId tid = choices[i].tile_id;
    uint32_t sem_start = choices[i].pc_start;
    uint32_t sem_end = choices[i].pc_end;
    if (sem_start >= nbc || sem_end == 0 || sem_end > nbc || sem_end <= sem_start) { spon_image_free(img); free(actual_slots); free(bc); free(actual); free(after); return 0; }
    uint32_t abs_start = actual[sem_start];
    uint32_t abs_end = after[sem_end - 1];
    size_t code_size = 0;
    void *code = materialize_tile(p, tid, actual + sem_start, sem_end - sem_start, &code_size);
    if (!code) { spon_image_free(img); free(actual_slots); free(bc); free(actual); free(after); return 0; }
    img->tiles[img->n_tiles].tile_id = tid;
    img->tiles[img->n_tiles].pc_start = abs_start;
    img->tiles[img->n_tiles].pc_end = abs_end;
    img->tiles[img->n_tiles].code = code;
    img->tiles[img->n_tiles].code_size = code_size;
    img->n_tiles++;
  }

  if (nbc > 0) img->pc_end = after[nbc - 1];
  free(actual_slots);
  free(bc);
  free(actual);
  free(after);
  *out_image = img;
  return 1;
}

static int execute_tile_range(SponImage *img, uint32_t first, uint32_t last_exclusive, SponExecCtx *ctx, uint32_t *resume_pc) {
  for (uint32_t i = first; i < last_exclusive; i++) {
    SponTileFn fn = (SponTileFn)img->tiles[i].code;
    ctx->exit_kind = SPON_EXIT_NONE;
    ctx->exit_pc = 0;
    ctx->exit_op_idx = 0;
    ctx->exit_hole = 0;
    fn(ctx);
    if (ctx->exit_kind != SPON_EXIT_NONE) {
      *resume_pc = ctx->exit_pc;
      if (i + 1 == img->n_tiles &&
          (ctx->exit_kind == SPON_EXIT_RESIDUAL || ctx->exit_kind == SPON_EXIT_BOUNDARY))
        return 3; /* tail seam: expected transfer back to interpreter/floor */
      return 2;
    }
  }
  return 1;
}

static int try_execute_counted_loop(SponImage *img, StkId base, const Proto *p, SponExecCtx *ctx, uint32_t *resume_pc) {
  if (!p || img->pc_end == 0 || img->n_tiles < 2) return 0;
  uint32_t forpc = img->pc_end - 1;
  Instruction fi = p->code[forpc];
  if (GET_OPCODE(fi) != OP_FORLOOP) return 0;
  if ((uint32_t)(forpc + 1 - GETARG_Bx(fi)) != img->pc_start) return 0;
  if (img->tiles[img->n_tiles - 1].pc_start != forpc) return 0;

  StkId ra = base + GETARG_A(fi);
  if (!ttisinteger(s2v(ra + 1))) return 0;

  for (;;) {
    int r = execute_tile_range(img, 0, img->n_tiles - 1, ctx, resume_pc);
    if (r != 1) return r;
    if (ttisinteger(s2v(ra + 1))) {
      lua_Unsigned count = l_castS2U(ivalue(s2v(ra)));
      if (count > 0) {
        lua_Integer step = ivalue(s2v(ra + 1));
        lua_Integer idx = ivalue(s2v(ra + 2));
        chgivalue(s2v(ra), l_castU2S(count - 1));
        idx = intop(+, idx, step);
        chgivalue(s2v(ra + 2), idx);
        continue;
      }
    }
    else {
      return 0; /* let interpreter handle float loops */
    }
    *resume_pc = img->pc_end;
    return 1;
  }
}

int spon_image_execute(SponImage *img, StkId base, const Proto *p, uint32_t *resume_pc) {
  if (!img || !base || !resume_pc) return 0;
  SponExecCtx ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.stack = (void*)s2v(base);
  ctx.k = p ? (SponTValueABI*)p->k : NULL;

  {
    int lr = try_execute_counted_loop(img, base, p, &ctx, resume_pc);
    if (lr != 0) return lr;
  }

  {
    int r = execute_tile_range(img, 0, img->n_tiles, &ctx, resume_pc);
    if (r != 1) return r;
  }
  *resume_pc = img->pc_end;
  return 1;
}

void spon_image_free(SponImage *img) {
  if (!img) return;
  if (img->tiles) {
    for (uint32_t i = 0; i < img->n_tiles; i++) {
      if (img->tiles[i].code && img->tiles[i].code_size) munmap(img->tiles[i].code, img->tiles[i].code_size);
    }
    free(img->tiles);
  }
  free(img);
}
