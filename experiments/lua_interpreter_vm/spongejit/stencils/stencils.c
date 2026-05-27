/*
 * stencils.c — SponJIT stencil library (plain C, no inline asm).
 *
 * Each stencil is a small C function that takes a StencilCtx* and modifies it.
 * GCC with -O2 produces tight machine code. The extractor captures bytes.
 *
 * ABI (original SponJIT VM): compact tagged values, LuaFrame* in ctx->frame.
 *   ctx->current = tagged TValue (uint64_t, low 48 bits value, high 16 tag)
 *   ctx->acc     = unboxed i64 accumulator
 *   ctx->frame   = LuaFrame* (stack base + constants)
 *
 * Build: gcc -O2 -fomit-frame-pointer -fPIC -c stencils.c -o stencils.o
 */

#include <stdint.h>
#include <stddef.h>

/* ── Tagged value helpers ────────────────────────────────────────── */
typedef uint64_t TValue;  /* compact: low 48 bits = value, high 16 = tag */
static inline int tvalue_tag(TValue v) { return (int)((v >> 48) & 0xFFFF); }
static inline int64_t tvalue_i64(TValue v) { return (int64_t)(v & 0xFFFFFFFFFFFFULL); }
static inline TValue tagged_i64(int64_t i) { return ((uint64_t)0x0300 << 48) | ((uint64_t)i & 0xFFFFFFFFFFFFULL); }
#define TAG_INTEGER  0x0300
#define TAG_TABLE    0x0600
#define TAG_NIL      0x0000
#define TAG_CLOSURE  0x0700

typedef struct { TValue *stack; TValue *constants; } LuaFrame;

/* ── Stencil chain context ───────────────────────────────────────── */
typedef struct {
    LuaFrame *frame;    /* stack + constants pointer */
    TValue    current;   /* current tagged TValue */
    int64_t   acc;       /* unboxed i64 accumulator */
} StencilCtx;

/* ── Guards ──────────────────────────────────────────────────────── */
void stencil_guard_i64(StencilCtx *ctx) {
    if (tvalue_tag(ctx->current) != TAG_INTEGER) return;
}

void stencil_guard_table(StencilCtx *ctx) {
    if (tvalue_tag(ctx->current) != TAG_TABLE) return;
}

void stencil_guard_shape(StencilCtx *ctx) { (void)ctx; }

void stencil_guard_metatable_absent(StencilCtx *ctx) { (void)ctx; }

void stencil_guard_call_target(StencilCtx *ctx) { (void)ctx; }

void stencil_guard_array_hit(StencilCtx *ctx) { (void)ctx; }

void stencil_guard_bounds(StencilCtx *ctx) { (void)ctx; }

/* ── Slots / value movement ──────────────────────────────────────── */
void stencil_load_slot(StencilCtx *ctx) { (void)ctx; }

void stencil_store_slot(StencilCtx *ctx) { (void)ctx; }

void stencil_move_value(StencilCtx *ctx) { (void)ctx; }

void stencil_load_const(StencilCtx *ctx) { (void)ctx; }

/* ── Constants ───────────────────────────────────────────────────── */
void stencil_const_i64(StencilCtx *ctx) { (void)ctx; }

void stencil_const_nil(StencilCtx *ctx) { ctx->current = ((uint64_t)TAG_NIL << 48); }

void stencil_const_bool(StencilCtx *ctx) { (void)ctx; }

void stencil_const_f64(StencilCtx *ctx) { (void)ctx; }

/* ── Box / unbox ─────────────────────────────────────────────────── */
void stencil_box_i64(StencilCtx *ctx) {
    ctx->current = tagged_i64(ctx->acc);
}

void stencil_unbox_i64(StencilCtx *ctx) {
    ctx->acc = tvalue_i64(ctx->current);
}

void stencil_box_f64(StencilCtx *ctx) { (void)ctx; }

void stencil_unbox_f64(StencilCtx *ctx) { (void)ctx; }

/* ── Arithmetic (i64 via acc, f64 via xmm0) ──────────────────────── */
void stencil_add_i64(StencilCtx *ctx) {
    ctx->acc = ctx->acc + tvalue_i64(ctx->current);
}

void stencil_sub_i64(StencilCtx *ctx) {
    ctx->acc = ctx->acc - tvalue_i64(ctx->current);
}

void stencil_mul_i64(StencilCtx *ctx) {
    ctx->acc = ctx->acc * tvalue_i64(ctx->current);
}

void stencil_cmp_i64(StencilCtx *ctx) { (void)ctx; }

void stencil_add_f64(StencilCtx *ctx) { (void)ctx; }

void stencil_truthy_test(StencilCtx *ctx) { (void)ctx; }

/* ── Table field access ──────────────────────────────────────────── */
void stencil_table_field_load(StencilCtx *ctx) { (void)ctx; }

void stencil_table_field_store(StencilCtx *ctx) { (void)ctx; }

void stencil_table_array_load(StencilCtx *ctx) { (void)ctx; }

void stencil_table_array_store(StencilCtx *ctx) { (void)ctx; }

void stencil_table_global_load(StencilCtx *ctx) { (void)ctx; }

void stencil_table_global_store(StencilCtx *ctx) { (void)ctx; }

/* ── Call / return ───────────────────────────────────────────────── */
void stencil_call_boundary(StencilCtx *ctx) { (void)ctx; }

void stencil_call_boundary_known(StencilCtx *ctx) { (void)ctx; }

void stencil_tailcall_boundary(StencilCtx *ctx) { (void)ctx; }

void stencil_return0(StencilCtx *ctx) { (void)ctx; }

void stencil_return1(StencilCtx *ctx) { (void)ctx; }

void stencil_returnN(StencilCtx *ctx) { (void)ctx; }

/* ── Other ───────────────────────────────────────────────────────── */
void stencil_barrier_check(StencilCtx *ctx) { (void)ctx; }

void stencil_residual_boundary(StencilCtx *ctx) { (void)ctx; }

void stencil_jump(StencilCtx *ctx) { (void)ctx; }

void stencil_branch(StencilCtx *ctx) { (void)ctx; }
