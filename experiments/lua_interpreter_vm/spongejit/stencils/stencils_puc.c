/* PUC-Lua compatible SponJIT stencil library.
 *
 * Copy-and-patch rule: individual stencil RETs are replaced with NOP so code
 * falls through to the next stencil. Therefore stencil bodies must not use
 * early return for control flow; use `if (ctx->status == SJ_OK) { ... }`.
 */
#include <stdint.h>
#include <stddef.h>

typedef struct TValue { unsigned long long value_; unsigned char tt_; } TValue;
typedef union StackValue { TValue val; } StackValue;
typedef StackValue *StkId;
typedef unsigned int Instruction;

#define LUA_VNIL       0
#define LUA_VFALSE     1
#define LUA_VTRUE      17
#define LUA_VNUMINT    3
#define LUA_VTABLE     69

#define s2v(o) (&(o)->val)
#define rawtt(o) ((o)->tt_)
#define ttisinteger(o) (rawtt(o) == LUA_VNUMINT)
#define ttistable(o)   (rawtt(o) == LUA_VTABLE)
#define ivalue(o) ((long long)((o)->value_))
#define setivalue(o,i) do { (o)->value_ = (unsigned long long)(i); (o)->tt_ = LUA_VNUMINT; } while (0)
#define setnilvalue(o) do { (o)->value_ = 0; (o)->tt_ = LUA_VNIL; } while (0)
#define setbfvalue(o)  do { (o)->value_ = 0; (o)->tt_ = LUA_VFALSE; } while (0)
#define setbtvalue(o)  do { (o)->value_ = 0; (o)->tt_ = LUA_VTRUE; } while (0)

#define POS_OP 0
#define POS_A  7
#define POS_k  15
#define POS_B  16
#define POS_C  24
#define POS_Bx POS_k
#define SIZE_OP 7
#define SIZE_C 8
#define SIZE_Bx 17
#define MAXARG_Bx ((1 << SIZE_Bx) - 1)
#define OFFSET_sBx (MAXARG_Bx >> 1)
#define MAXARG_C  ((1 << SIZE_C) - 1)
#define OFFSET_sC (MAXARG_C >> 1)

#define GET_OPCODE(i) ((int)(((i) >> POS_OP) & ((1u << SIZE_OP) - 1)))
#define GETARG_A(i)   ((int)(((i) >> POS_A) & 0xffu))
#define GETARG_B(i)   ((int)(((i) >> POS_B) & 0xffu))
#define GETARG_C(i)   ((int)(((i) >> POS_C) & 0xffu))
#define GETARG_Bx(i)  ((int)(((i) >> POS_Bx) & ((1u << SIZE_Bx) - 1)))
#define GETARG_sBx(i) (GETARG_Bx(i) - OFFSET_sBx)
#define GETARG_sC(i)  (GETARG_C(i) - OFFSET_sC)

enum {
  OP_MOVE, OP_LOADI, OP_LOADF, OP_LOADK, OP_LOADKX, OP_LOADFALSE,
  OP_LFALSESKIP, OP_LOADTRUE, OP_LOADNIL, OP_GETUPVAL, OP_SETUPVAL,
  OP_GETTABUP, OP_GETTABLE, OP_GETI, OP_GETFIELD,
  OP_SETTABUP, OP_SETTABLE, OP_SETI, OP_SETFIELD,
  OP_NEWTABLE, OP_SELF, OP_ADDI,
  OP_ADDK, OP_SUBK, OP_MULK, OP_MODK, OP_POWK, OP_DIVK, OP_IDIVK,
  OP_BANDK, OP_BORK, OP_BXORK, OP_SHLI, OP_SHRI,
  OP_ADD, OP_SUB, OP_MUL, OP_MOD, OP_POW, OP_DIV, OP_IDIV,
  OP_BAND, OP_BOR, OP_BXOR, OP_SHL, OP_SHR,
  OP_MMBIN, OP_MMBINI, OP_MMBINK,
  OP_UNM, OP_BNOT, OP_NOT, OP_LEN, OP_CONCAT, OP_CLOSE, OP_TBC, OP_JMP,
  OP_EQ, OP_LT, OP_LE, OP_EQK, OP_EQI, OP_LTI, OP_LEI, OP_GTI, OP_GEI,
  OP_TEST, OP_TESTSET, OP_CALL, OP_TAILCALL,
  OP_RETURN, OP_RETURN0, OP_RETURN1,
  OP_FORLOOP, OP_FORPREP, OP_TFORPREP, OP_TFORCALL, OP_TFORLOOP,
  OP_SETLIST, OP_CLOSURE, OP_VARARG, OP_GETVARG, OP_ERRNNIL,
  OP_VARARGPREP, OP_EXTRAARG
};

enum { SJ_OK = 0, SJ_GUARD_FAIL = 1, SJ_UNSUPPORTED = 2, SJ_BOUNDARY = 3 };

typedef struct {
    StkId              base;
    TValue            *k;
    const Instruction *pc;
    TValue            *current;
    long long          acc;
    int                status;
    int                load_count;
    int                store_count;
    int                unbox_count;
    TValue             scratch;
} StencilCtx;

#define IF_OK if (ctx->status == SJ_OK)

static inline __attribute__((always_inline)) void side_exit(StencilCtx *ctx, int status) { ctx->status = status; }
static inline __attribute__((always_inline)) void end_opcode(StencilCtx *ctx) {
    ctx->pc++; ctx->load_count = 0; ctx->store_count = 0; ctx->unbox_count = 0;
}

static inline __attribute__((always_inline)) int load_slot_index(StencilCtx *ctx) {
    Instruction ins = ctx->pc[0];
    int op = GET_OPCODE(ins);
    int n = ctx->load_count++;
    if (op == OP_MOVE || op == OP_ADDI) return GETARG_B(ins);
    if (op == OP_ADD || op == OP_SUB || op == OP_MUL) return n == 0 ? GETARG_B(ins) : GETARG_C(ins);
    if (op == OP_RETURN || op == OP_RETURN1 || op == OP_CALL || op == OP_TAILCALL) return GETARG_A(ins);
    if (op == OP_GETFIELD || op == OP_GETTABLE || op == OP_GETI || op == OP_SELF) return GETARG_B(ins);
    if (op == OP_SETFIELD || op == OP_SETTABLE || op == OP_SETI) return n == 0 ? GETARG_A(ins) : GETARG_C(ins);
    return GETARG_A(ins);
}

static inline __attribute__((always_inline)) int store_slot_index(StencilCtx *ctx) {
    Instruction ins = ctx->pc[0];
    int op = GET_OPCODE(ins);
    int n = ctx->store_count++;
    if (op == OP_SELF) return n == 0 ? GETARG_A(ins) : GETARG_A(ins) + 1;
    return GETARG_A(ins);
}

void stencil_guard_i64(StencilCtx *ctx) { IF_OK { if (!ctx->current || !ttisinteger(ctx->current)) side_exit(ctx, SJ_GUARD_FAIL); } }
void stencil_guard_table(StencilCtx *ctx) { IF_OK { if (!ctx->current || !ttistable(ctx->current)) side_exit(ctx, SJ_GUARD_FAIL); } }
void stencil_guard_shape(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_guard_metatable_absent(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_guard_call_target(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_guard_array_hit(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_guard_bounds(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }

void stencil_load_slot(StencilCtx *ctx) { IF_OK ctx->current = s2v(ctx->base + load_slot_index(ctx)); }
void stencil_store_slot(StencilCtx *ctx) { IF_OK { if (ctx->current) { *s2v(ctx->base + store_slot_index(ctx)) = *ctx->current; end_opcode(ctx); } else side_exit(ctx, SJ_UNSUPPORTED); } }
void stencil_move_value(StencilCtx *ctx) { (void)ctx; }

void stencil_load_const(StencilCtx *ctx) { IF_OK ctx->current = ctx->k + GETARG_Bx(ctx->pc[0]); }
void stencil_const_i64(StencilCtx *ctx) {
    IF_OK {
        int op = GET_OPCODE(ctx->pc[0]);
        if (op == OP_LOADI) setivalue(&ctx->scratch, GETARG_sBx(ctx->pc[0]));
        else if (op == OP_ADDI) setivalue(&ctx->scratch, GETARG_sC(ctx->pc[0]));
        else { side_exit(ctx, SJ_UNSUPPORTED); }
        if (ctx->status == SJ_OK) ctx->current = &ctx->scratch;
    }
}
void stencil_const_nil(StencilCtx *ctx) { IF_OK { setnilvalue(&ctx->scratch); ctx->current = &ctx->scratch; } }
void stencil_const_bool(StencilCtx *ctx) { IF_OK { if (GET_OPCODE(ctx->pc[0]) == OP_LOADTRUE) setbtvalue(&ctx->scratch); else setbfvalue(&ctx->scratch); ctx->current = &ctx->scratch; } }
void stencil_const_f64(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }

void stencil_box_i64(StencilCtx *ctx) { IF_OK { setivalue(&ctx->scratch, ctx->acc); ctx->current = &ctx->scratch; } }
void stencil_unbox_i64(StencilCtx *ctx) { IF_OK { if (ctx->current && ttisinteger(ctx->current)) { if (ctx->unbox_count++ == 0) ctx->acc = ivalue(ctx->current); } else side_exit(ctx, SJ_GUARD_FAIL); } }
void stencil_box_f64(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_unbox_f64(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }

void stencil_add_i64(StencilCtx *ctx) { IF_OK { if (ctx->current && ttisinteger(ctx->current)) ctx->acc += ivalue(ctx->current); else side_exit(ctx, SJ_GUARD_FAIL); } }
void stencil_sub_i64(StencilCtx *ctx) { IF_OK { if (ctx->current && ttisinteger(ctx->current)) ctx->acc -= ivalue(ctx->current); else side_exit(ctx, SJ_GUARD_FAIL); } }
void stencil_mul_i64(StencilCtx *ctx) { IF_OK { if (ctx->current && ttisinteger(ctx->current)) ctx->acc *= ivalue(ctx->current); else side_exit(ctx, SJ_GUARD_FAIL); } }
void stencil_cmp_i64(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_add_f64(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_truthy_test(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }

void stencil_table_field_load(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_table_field_store(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_table_array_load(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_table_array_store(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_table_global_load(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_table_global_store(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }

void stencil_call_boundary(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }
void stencil_call_boundary_known(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }
void stencil_tailcall_boundary(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }
void stencil_return0(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }
void stencil_return1(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }
void stencil_returnN(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }
void stencil_jump(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }
void stencil_branch(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_BOUNDARY); }

void stencil_barrier_check(StencilCtx *ctx) { IF_OK side_exit(ctx, SJ_UNSUPPORTED); }
void stencil_residual_boundary(StencilCtx *ctx) { IF_OK { int op = GET_OPCODE(ctx->pc[0]); if (op == OP_MMBIN || op == OP_MMBINI || op == OP_MMBINK) end_opcode(ctx); else side_exit(ctx, SJ_BOUNDARY); } }
