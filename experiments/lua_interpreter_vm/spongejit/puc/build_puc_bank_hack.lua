#!/usr/bin/env luajit
-- build_puc_bank_hack.lua — experimental PUC Lua VM hack using current libsponbank.
--
-- This is intentionally narrow: it recognizes one hot bytecode shape
--   UNM, BNOT, MUL, MMBIN, ADDI, MMBINI
-- and executes the real mixed aggregate SponBank tile for semantic ops
--   UNM, BNOT, MUL, ADDI
-- patching holes from the actual PUC instructions at that site.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/build_puc_bank_hack%.lua$") or "experiments/lua_interpreter_vm/spongejit"
local repo = spongejit:sub(1, 1) == "/" and spongejit:gsub("/experiments/lua_interpreter_vm/spongejit$", "") or "."

local function q(s) return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'" end
local function run(cmd)
  io.stderr:write("[puc-bank-hack] ", cmd, "\n")
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then error("command failed: " .. cmd) end
end
local function read(path) local f=assert(io.open(path,"rb"),path); local s=f:read("*a"); f:close(); return s end
local function write(path,s) local f=assert(io.open(path,"wb"),path); f:write(s); f:close() end
local function replace_once(s, old, new, label)
  local n; s,n=s:gsub(old:gsub("([^%w])","%%%1"), function() return new end, 1)
  if n ~= 1 then error("patch failed " .. label .. " matches=" .. tostring(n)) end
  return s
end

local BLOCK = [[
/* --- SponBank experimental hack block --- */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>

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

typedef struct { void *stack; TValue *k; TValue scratch[256]; uint32_t exit_kind; uint32_t exit_pc; uint32_t exit_op_idx; uint32_t exit_hole; } SponExecCtx;
typedef void (*SponBankHackFn)(SponExecCtx *ctx);
static SponBankHackFn sponbank_hack_fn = NULL;
static unsigned long long sponbank_hack_hits = 0;
static unsigned long long sponbank_hack_probes = 0;
static int sponbank_hack_enabled = -1;
static int sponbank_hack_inline = 0;
static int sponbank_hack_image = 0;

static void sponbank_hack_report(void) {
  if (getenv("SPONBANK_HACK_PRINT"))
    fprintf(stderr, "[sponbank-hack] probes=%llu hits=%llu\n", sponbank_hack_probes, sponbank_hack_hits);
}

static void sponbank_hack_init_flag(void) {
  if (sponbank_hack_enabled < 0) {
    const char *e = getenv("SPONBANK_HACK_ENABLE");
    const char *inl = getenv("SPONBANK_HACK_INLINE");
    const char *img = getenv("SPONBANK_HACK_IMAGE");
    sponbank_hack_enabled = (e && e[0] && e[0] != '0');
    sponbank_hack_inline = (inl && inl[0] && inl[0] != '0');
    sponbank_hack_image = (img && img[0] && img[0] != '0');
    if (sponbank_hack_enabled) atexit(sponbank_hack_report);
  }
}

static void put_u32(unsigned char *p, uint32_t off, uint32_t v) { memcpy(p + off, &v, 4); }

static uint32_t sponbank_hack_patch_value(uint16_t hid, Instruction i0, const Instruction *pc) {
  Instruction i1 = pc[0];       /* BNOT */
  Instruction i2 = pc[1];       /* MUL */
  Instruction i3 = pc[3];       /* ADDI; pc[2] is MMBIN */
  switch (hid) {
    case 0: return (uint32_t)GETARG_B(i0);   /* UNM source */
    case 2: return (uint32_t)GETARG_A(i0);   /* UNM dest */
    case 4: return (uint32_t)GETARG_A(i1);   /* BNOT dest */
    case 5: return (uint32_t)GETARG_B(i2);   /* MUL lhs */
    case 7: return (uint32_t)GETARG_C(i2);   /* MUL rhs */
    case 8: return (uint32_t)GETARG_A(i2);   /* MUL dest */
    case 9: return (uint32_t)GETARG_sC(i3);  /* ADDI immediate */
    case 10: return (uint32_t)GETARG_A(i3);  /* ADDI dest */
    default: return 0;                       /* fail exits not expected in this hack */
  }
}

static SponBankHackFn sponbank_hack_materialize(Instruction i0, const Instruction *pc) {
  uint32_t bc[4] = { OP_UNM, OP_BNOT, OP_MUL, OP_ADDI };
  uint32_t n = 0;
  SponSelectStats st;
  const SponTileChoice *ch = spon_select_greedy_stats(bc, 0, 4, ~(SponFactSig)0, &n, &st);
  if (!ch || n != 1 || !ch[0].tile_id) return NULL;
  const SponTileDesc *t = spon_get_tile(ch[0].tile_id);
  const unsigned char *src = spon_tile_data(ch[0].tile_id);
  if (!t || !src || t->size == 0) return NULL;
  size_t alloc = (t->size + 4095u) & ~4095u;
  unsigned char *mem = (unsigned char*)mmap(NULL, alloc, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANON, -1, 0);
  if (mem == MAP_FAILED) return NULL;
  memcpy(mem, src, t->size);
  uint32_t nh = 0;
  const SponHoleReloc *hs = spon_tile_holes(ch[0].tile_id, &nh);
  for (uint32_t k = 0; k < nh; k++) put_u32(mem, hs[k].code_offset, sponbank_hack_patch_value(hs[k].hole_id, i0, pc));
  return (SponBankHackFn)mem;
}

static int sponbank_hack_try(StkId base, const Instruction **ppc, Instruction i) {
  const Instruction *pc = *ppc;  /* points after i */
  sponbank_hack_init_flag();
  if (!sponbank_hack_enabled) return 0;
  sponbank_hack_probes++;
  if (GET_OPCODE(i) != OP_UNM) return 0;
  if (GET_OPCODE(pc[0]) != OP_BNOT || GET_OPCODE(pc[1]) != OP_MUL ||
      GET_OPCODE(pc[2]) != OP_MMBIN || GET_OPCODE(pc[3]) != OP_ADDI ||
      GET_OPCODE(pc[4]) != OP_MMBINI) return 0;
  if (sponbank_hack_image) {
    StkId loopra = base + GETARG_A(pc[5]);
    if (GET_OPCODE(pc[5]) != OP_FORLOOP || !ttisinteger(s2v(loopra + 1))) return 0;
    if (sponbank_hack_fn == NULL) sponbank_hack_fn = sponbank_hack_materialize(i, pc);
    if (sponbank_hack_fn == NULL) return 0;
    for (;;) {
      TValue *unm_src = s2v(base + GETARG_B(i));
      TValue *mul_l = s2v(base + GETARG_B(pc[1]));
      TValue *mul_r = s2v(base + GETARG_C(pc[1]));
      if (!ttisinteger(unm_src) || !ttisinteger(mul_l) || !ttisinteger(mul_r)) return 0;
      SponExecCtx ctx;
      memset(&ctx, 0, sizeof(ctx));
      ctx.stack = (void*)s2v(base);
      ctx.k = NULL;
      sponbank_hack_fn(&ctx);
      if (ctx.exit_kind != 0) return 0;
      sponbank_hack_hits++;
      {
        lua_Unsigned count = l_castS2U(ivalue(s2v(loopra)));
        if (count > 0) {
          lua_Integer step = ivalue(s2v(loopra + 1));
          lua_Integer idx = ivalue(s2v(loopra + 2));
          chgivalue(s2v(loopra), l_castU2S(count - 1));
          idx = intop(+, idx, step);
          chgivalue(s2v(loopra + 2), idx);
        }
        else break;
      }
    }
    *ppc = pc + 6;  /* skip through FORLOOP; continue after loop */
    return 1;
  }
  else if (sponbank_hack_inline) {
    TValue *unm_src = s2v(base + GETARG_B(i));
    TValue *unm_dst = s2v(base + GETARG_A(i));
    TValue *bnot_dst = s2v(base + GETARG_A(pc[0]));
    TValue *mul_l = s2v(base + GETARG_B(pc[1]));
    TValue *mul_r = s2v(base + GETARG_C(pc[1]));
    TValue *mul_dst = s2v(base + GETARG_A(pc[1]));
    TValue *addi_dst = s2v(base + GETARG_A(pc[3]));
    if (!ttisinteger(unm_src) || !ttisinteger(mul_l) || !ttisinteger(mul_r)) return 0;
    setivalue(unm_dst, intop(-, 0, ivalue(unm_src)));
    setivalue(bnot_dst, intop(^, ~l_castS2U(0), ivalue(unm_dst)));
    setivalue(mul_dst, intop(*, ivalue(mul_l), ivalue(mul_r)));
    setivalue(addi_dst, intop(+, ivalue(mul_dst), GETARG_sC(pc[3])));
    *ppc = pc + 5;
    sponbank_hack_hits++;
    return 1;
  }
  else {
    if (sponbank_hack_fn == NULL) sponbank_hack_fn = sponbank_hack_materialize(i, pc);
    if (sponbank_hack_fn == NULL) return 0;
    SponExecCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.stack = (void*)s2v(base);
    ctx.k = NULL;
    sponbank_hack_fn(&ctx);
    if (ctx.exit_kind != 0) return 0;
    *ppc = pc + 5;  /* skip BNOT,MUL,MMBIN,ADDI,MMBINI; next fetch sees FORLOOP */
    sponbank_hack_hits++;
    return 1;
  }
}

#define SPONBANK_HACK_TRY() \
  do { if (GET_OPCODE(i) == OP_UNM && sponbank_hack_try(base, &pc, i)) { updatetrap(ci); continue; } } while (0)
/* --- end SponBank experimental hack block --- */
]]

local pwd_f = assert(io.popen("pwd", "r")); local cwd = (pwd_f:read("*l")); pwd_f:close()
local abs_spongejit = spongejit:sub(1,1) == "/" and spongejit or (cwd .. "/" .. spongejit)
local out = spongejit .. "/build/puc_bank_hack"
local vendor = repo .. "/.vendor/Lua"
local bank = abs_spongejit .. "/build/cp_lib"
run("rm -rf " .. q(out))
run("mkdir -p " .. q(out))
run("cp -R " .. q(vendor) .. "/* " .. q(out) .. "/")
local lvm = out .. "/lvm.c"
local s = read(lvm)
s = replace_once(s, '#include "lvm.h"\n', '#include "lvm.h"\n' .. BLOCK, "insert block")
s = replace_once(s, '    lua_assert(luaP_isIT(i) || (cast_void(L->top.p = base), 1));\n    vmdispatch (GET_OPCODE(i)) {',
                   '    lua_assert(luaP_isIT(i) || (cast_void(L->top.p = base), 1));\n    SPONBANK_HACK_TRY();\n    vmdispatch (GET_OPCODE(i)) {', "initial dispatch")
write(lvm, s)
local jt = out .. "/ljumptab.h"
local ok_jt, js = pcall(read, jt)
if ok_jt then
  js = replace_once(js, '#define vmbreak\t\tvmfetch(); vmdispatch(GET_OPCODE(i));',
                    '#define vmbreak\t\tvmfetch(); SPONBANK_HACK_TRY(); vmdispatch(GET_OPCODE(i));', "jumptable vmbreak")
  write(jt, js)
end
run("cd " .. q(out) .. " && make -s -j liblua.a lua.o")
run(table.concat({
  "cd " .. q(out) .. " && gcc -O2 -o lua lua.o liblua.a",
  "-L" .. q(bank),
  "-Wl,-rpath," .. q(bank),
  "-lsponbank -lm -ldl",
}, " "))
print("hack_lua=" .. out .. "/lua")
