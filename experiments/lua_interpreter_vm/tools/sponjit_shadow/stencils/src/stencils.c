/*
 * stencils.c — SponJIT COMPLETE stencil library (GCC-generated native code).
 *
 * Every SSA node in foundry_ssa.lua has a stencil here. GCC writes the asm;
 * extract_stencils.lua captures bytes + holes from the .o file.
 *
 * Residency convention:
 *   rax  = current tagged TValue
 *   rcx  = current unboxed i64 accumulator
 *   xmm0 = current native f64 accumulator
 *   rbx  = LuaFrame*
 *
 * Build: gcc -O2 -fomit-frame-pointer -fPIC -c stencils.c -o stencils.o
 */

#include "../stencil_abi.h"

extern const int32_t  hole_slot_offset;
extern const int32_t  hole_field_offset;
extern const int32_t  hole_const_idx;
extern const uint64_t hole_shape_id;
extern void          *hole_call_target;
extern const int32_t  hole_barrier_color;
extern void          *hole_exit_addr;
extern const uint64_t hole_immediate_i64;

/* ── guards ───────────────────────────────────────────────────────────── */

void stencil_guard_i64(void) {
    uint64_t v; __asm__("mov %%rax, %0" : "=r"(v));
    if ((v >> 48) != 0x0300) __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

void stencil_guard_table(void) {
    uint64_t v; __asm__("mov %%rax, %0" : "=r"(v));
    if ((v >> 48) != 0x0600) __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

void stencil_guard_shape(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    if (t->shape_epoch != hole_shape_id) __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

void stencil_guard_metatable_absent(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    if (t->metatable) __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

void stencil_guard_call_target(void) {
    Closure *c; __asm__("mov %%rax, %0" : "=r"(c));
    if (c->proto != hole_call_target) __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

void stencil_guard_array_hit(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    if (!t->array) __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

void stencil_guard_bounds(void) {
    LuaFrame *f; __asm__("mov %%rbx, %0" : "=r"(f));
    int64_t idx; __asm__("mov %%rax, %0" : "=r"(idx));
    idx = (int64_t)(idx & 0xFFFFFFFFFFFFULL);
    int32_t len = (int32_t)hole_slot_offset;
    if (idx < 0 || idx >= len) __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

/* ── value producers → rax ────────────────────────────────────────────── */

void stencil_load_slot(void) {
    LuaFrame *f; __asm__("mov %%rbx, %0" : "=r"(f));
    TValue v = f->stack[hole_slot_offset / (int32_t)sizeof(TValue)];
    __asm__ volatile("" : : "a"(v));
}

void stencil_load_const(void) {
    LuaFrame *f; __asm__("mov %%rbx, %0" : "=r"(f));
    TValue v = f->constants[hole_const_idx];
    __asm__ volatile("" : : "a"(v));
}

void stencil_const_i64(void) {
    TValue v = hole_immediate_i64;
    __asm__ volatile("" : : "a"(v));
}

void stencil_const_nil(void) {
    TValue v = ((uint64_t)TAG_NIL << 48);
    __asm__ volatile("" : : "a"(v));
}

void stencil_const_bool(void) {
    uint64_t tag = hole_immediate_i64 ? TAG_TRUE : TAG_FALSE;
    TValue v = ((uint64_t)tag << 48);
    __asm__ volatile("" : : "a"(v));
}

void stencil_const_f64(void) {
    union { uint64_t u; double d; } c = { .u = hole_immediate_i64 };
    double v = c.d;
    __asm__ volatile("movsd %0, %%xmm0" : : "m"(v) : "xmm0");
}

void stencil_table_field_load(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    TValue v = t->fields[hole_field_offset / (int32_t)sizeof(TValue)];
    __asm__ volatile("" : : "a"(v));
}

void stencil_table_array_load(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    int32_t idx = hole_slot_offset / (int32_t)sizeof(TValue);
    TValue v = t->array[idx];
    __asm__ volatile("" : : "a"(v));
}

void stencil_table_global_load(void) {
    /* Global table lookup: table in rax (from prior node or guard), field at hole offset */
    Table *gt; __asm__("mov %%rax, %0" : "=r"(gt));
    TValue v = gt->fields[hole_field_offset / (int32_t)sizeof(TValue)];
    __asm__ volatile("" : : "a"(v));
}

void stencil_table_global_store(void) {
    Table *gt; __asm__("mov %%rax, %0" : "=r"(gt));
    TValue v; __asm__ volatile("" : "=a"(v));
    gt->fields[hole_field_offset / (int32_t)sizeof(TValue)] = v;
}

void stencil_store_slot(void) {
    LuaFrame *f; __asm__("mov %%rbx, %0" : "=r"(f));
    TValue v; __asm__("mov %%rax, %0" : "=r"(v));
    f->stack[hole_slot_offset / (int32_t)sizeof(TValue)] = v;
}

void stencil_table_field_store(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    TValue v; __asm__ volatile("" : "=a"(v));
    t->fields[hole_field_offset / (int32_t)sizeof(TValue)] = v;
}

void stencil_table_array_store(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    int32_t idx = hole_slot_offset / (int32_t)sizeof(TValue);
    TValue v; __asm__ volatile("" : "=a"(v));
    t->array[idx] = v;
}


/* ── box / unbox ──────────────────────────────────────────────────────── */

void stencil_box_i64(void) {
    int64_t i; __asm__("mov %%rcx, %0" : "=r"(i));
    TValue v = ((uint64_t)(i & 0xFFFFFFFFFFFFULL)) | ((uint64_t)TAG_INTEGER << 48);
    __asm__ volatile("" : : "a"(v));
}

void stencil_unbox_i64(void) {
    TValue v; __asm__("mov %%rax, %0" : "=r"(v));
    int64_t i = (int64_t)(v & 0xFFFFFFFFFFFFULL);
    __asm__ volatile("mov %0, %%rcx" : : "r"(i) : "rcx");
}

void stencil_box_f64(void) {
    double d;
    __asm__ volatile("movsd %%xmm0, %0" : "=m"(d));
    union { double d; uint64_t u; } c = { .d = d };
    TValue v = c.u | ((uint64_t)TAG_NUMBER << 48);
    __asm__ volatile("" : : "a"(v));
}

void stencil_unbox_f64(void) {
    TValue v; __asm__("mov %%rax, %0" : "=r"(v));
    union { uint64_t u; double d; } c = { .u = v & 0xFFFFFFFFFFFFULL };
    double d = c.d;
    __asm__ volatile("movsd %0, %%xmm0" : : "m"(d) : "xmm0");
}

/* ── arithmetic (i64: rcx accumulator; f64: xmm0 accumulator) ─────────── */

static int64_t get_rhs(void) {
    LuaFrame *f; __asm__("mov %%rbx, %0" : "=r"(f));
    TValue rhs = f->stack[hole_slot_offset / (int32_t)sizeof(TValue)];
    return (int64_t)(rhs & 0xFFFFFFFFFFFFULL);
}

void stencil_add_i64(void) {
    int64_t acc; __asm__("mov %%rcx, %0" : "=r"(acc));
    acc += get_rhs();
    __asm__ volatile("mov %0, %%rcx" : : "r"(acc) : "rcx");
}

void stencil_sub_i64(void) {
    int64_t acc; __asm__("mov %%rcx, %0" : "=r"(acc));
    acc -= get_rhs();
    __asm__ volatile("mov %0, %%rcx" : : "r"(acc) : "rcx");
}

void stencil_mul_i64(void) {
    int64_t acc; __asm__("mov %%rcx, %0" : "=r"(acc));
    acc *= get_rhs();
    __asm__ volatile("mov %0, %%rcx" : : "r"(acc) : "rcx");
}

void stencil_cmp_i64(void) {
    int64_t acc, rhs;
    __asm__("mov %%rcx, %0" : "=r"(acc));
    rhs = get_rhs();
    __asm__ volatile("cmp %1, %0" : : "r"(rhs), "r"(acc) : "cc");
}

void stencil_add_f64(void) {
    double acc; __asm__("movsd %%xmm0, %0" : "=m"(acc));
    TValue rhs_tagged; __asm__("mov %%rax, %0" : "=r"(rhs_tagged));
    union { uint64_t u; double d; } c = { .u = rhs_tagged & 0xFFFFFFFFFFFFULL };
    acc += c.d;
    __asm__ volatile("movsd %0, %%xmm0" : : "m"(acc) : "xmm0");
}

void stencil_truthy_test(void) {
    uint64_t v; __asm__("mov %%rax, %0" : "=r"(v));
    uint64_t tag = v >> 48;
    int truthy = (tag != TAG_NIL && tag != TAG_FALSE);
    __asm__ volatile("test %0, %0" : : "r"((uint64_t)truthy) : "cc");
}

/* ── call / return ────────────────────────────────────────────────────── */

void stencil_call_boundary(void)  { __asm__ volatile("jmp *%0" : : "m"(hole_call_target)); }
void stencil_tailcall_boundary(void) { __asm__ volatile("jmp *%0" : : "m"(hole_call_target)); }
void stencil_return0(void)         { __asm__ volatile("ret"); }
void stencil_return1(void)         { __asm__ volatile("ret"); }

void stencil_returnN(void) {
    /* Placeholder: multi-value return. nresults = hole_slot_offset. */
    /* In practice: copy nresults values from stack to caller frame, then ret. */
    int32_t n = hole_slot_offset;
    if (n > 0) { /* copy loop */ }
    __asm__ volatile("ret");
}

void stencil_branch(void) {
    /* Conditional branch: ZF=1 means "taken" (from prior cmp/truthy).
     * Emit: jne .skip; jmp *exit_addr; .skip:
     * Use asm goto for proper codegen. */
    __asm__ volatile goto("jne %l[skip]" : : : : skip);
    __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
    skip:;
}

/* ── misc ─────────────────────────────────────────────────────────────── */

void stencil_barrier_check(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    if (t->gc_color != (uint8_t)hole_barrier_color)
        __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr));
}

void stencil_residual_boundary(void) { __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr)); }
void stencil_jump(void)              { __asm__ volatile("jmp *%0" : : "m"(hole_exit_addr)); }

/* ── fused stencils ───────────────────────────────────────────────────── */

void stencil_unbox_add_i64_box(void) {
    TValue rhs_tagged; int64_t rhs_i, lhs_i;
    __asm__("mov %%rax, %0" : "=r"(rhs_tagged));
    __asm__("mov %%rcx, %0" : "=r"(lhs_i));
    rhs_i = (int64_t)(rhs_tagged & 0xFFFFFFFFFFFFULL);
    TValue v = ((uint64_t)((lhs_i + rhs_i) & 0xFFFFFFFFFFFFULL)) | ((uint64_t)TAG_INTEGER << 48);
    __asm__ volatile("" : : "a"(v));
}

void stencil_field_load_return1(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    TValue v = t->fields[hole_field_offset / (int32_t)sizeof(TValue)];
    __asm__ volatile("" : : "a"(v));
    __asm__ volatile("ret");
}

void stencil_field_load_add_store(void) {
    Table *t; __asm__("mov %%rax, %0" : "=r"(t));
    TValue val = t->fields[hole_field_offset / (int32_t)sizeof(TValue)];
    int64_t inc = (int64_t)(val & 0xFFFFFFFFFFFFULL);
    int64_t acc; __asm__("mov %%rcx, %0" : "=r"(acc));
    acc += inc;
    TValue result = ((uint64_t)(acc & 0xFFFFFFFFFFFFULL)) | ((uint64_t)TAG_INTEGER << 48);
    t->fields[hole_field_offset / (int32_t)sizeof(TValue)] = result;
}
