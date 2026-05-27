/*
 * stencil_abi.h — SponJIT stencil ABI and copy-and-patch materialization protocol.
 *
 * This is the bridge from the foundry's stencil vocabulary to real native code.
 * Each SSA node has exactly one stencil implementation. The lowering pass in
 * stencil_model.lua maps an SSA node list to a stencil-cover plan; this header
 * defines the C-side stencil implementations and the patch-hole descriptor format.
 *
 * Build: each stencil is a small C function compiled with GCC into an object
 * file. The build system extracts the .text bytes and relocation records, which
 * become the stencil "template" and "hole" lists. At runtime, SponJIT does
 * memcpy(stencil_bytes) + patch holes = executable native code.
 *
 * DESIGN RULES (from SPONJIT_RUNTIME_DESIGN.md):
 *   - runtime does NOT run SSA, does NOT invent code shapes
 *   - runtime does memcpy (copy stencil bytes) + patch holes + link
 *   - all optimization happened in the foundry
 *   - every stencil is small, fixed, precompiled, and verified offline
 *
 * ── STENCIL VOCABULARY ──────────────────────────────────────────────────
 *
 *  guard_i64              check TValue at [slot] is i64; exit to slow_path if not
 *  guard_table            check TValue at [slot] is table
 *  guard_shape            check table shape matches [shape_id]
 *  guard_metatable_absent check table->metatable == NULL
 *  guard_call_target      check closure proto == [target_proto]
 *  guard_array_hit        check table->array != NULL && key within bounds
 *
 *  load_slot              mov rax, [base + slot_offset]
 *  store_slot             mov [base + slot_offset], rax
 *  load_const             mov rax, [constants + const_idx * sizeof(TValue)]
 *  const_i64              mov rax, IMMEDIATE_i64_tagged_value
 *  const_nil              mov rax, NIL_TAG
 *  const_bool             mov rax, (val ? TRUE_TAG : FALSE_TAG)
 *  move_value             (folded by SSA — no stencil needed at runtime)
 *
 *  box_i64                convert native i64 in rcx to tagged TValue in rax
 *  unbox_i64              convert tagged TValue in rax to native i64 in rcx
 *
 *  add_i64                (unboxed) rcx = rcx + [slot]
 *  sub_i64                (unboxed) rcx = rcx - [slot]
 *  mul_i64                (unboxed) rcx = rcx * [slot]
 *  cmp_i64                cmp rcx, [slot]; set flags for subsequent jump
 *
 *  table_field_load       rax = table->fields[field_offset]
 *  table_field_store      table->fields[field_offset] = rax
 *  table_array_load       rax = table->array[idx]  (with bounds guard)
 *  table_array_store      table->array[idx] = rax  (with barrier check)
 *
 *  call_boundary          prepare frame, push continuation, jump to target
 *  tailcall_boundary      reuse current frame, jump to target
 *  return0                return with 0 values
 *  return1                return with 1 value in rax
 *
 *  barrier_check          if gc_barrier needed, call slow-path write barrier
 *  residual_boundary      save state, jump back to interpreter at [resume_pc]
 *  jump                   unconditional jump to [target_pc]
 *
 * ── FUSED STENCILS (SSA-discovered) ─────────────────────────────────────
 *
 *  unbox_add_i64_box      unbox rhs, rcx += rhs, box rcx → rax  (fused)
 *  field_load_add_store   field_load + unbox + add_i64 + box + field_store (fused)
 *  field_load_return1     field_load + return1 (fused)
 *
 * ── RESIDENCY CONVENTION ────────────────────────────────────────────────
 *
 *  The stencil ABI uses a fixed small register set:
 *
 *    rax  = "current TValue" (what the VM slot model calls "current value")
 *    rcx  = "current native i64" (unboxed numeric accumulator)
 *    rdx  = scratch / second operand
 *    rbx  = Lua stack base pointer
 *    rsi  = constants table pointer
 *    rdi  = upvalue / table pointer (scratch)
 *    rbp  = frame pointer (C ABI)
 *    rsp  = stack pointer (C ABI)
 *
 *  Values flow through rax (tagged) and rcx (unboxed i64). Guards check rax.
 *  Arithmetic operates on rcx. Box/unbox converts between them.
 *
 * ── HOLE DESCRIPTOR FORMAT ──────────────────────────────────────────────
 *
 *  Each stencil has a fixed set of holes: named slots in the assembled code
 *  that must be patched at runtime (or at foundry publication time for static
 *  constants). Holes are described as:
 *
 *    { name, offset_in_template, size_bytes, kind }
 *
 *  Kinds:
 *    slot_offset    = byte offset from base pointer to a stack slot
 *    field_offset   = byte offset within a table's fields array
 *    array_base     = byte offset to table->array pointer
 *    const_idx      = index into constants table
 *    shape_id       = runtime shape epoch number
 *    call_target    = function pointer / closure address
 *    barrier_color  = GC barrier color state
 *    target_pc      = bytecode PC for jump/fallback
 *    exit_addr      = address of exit stub (for guard failures)
 *    resume_pc      = bytecode PC for residual boundary fallback
 *    immediate_i64  = tagged i64 constant
 *
 * ── ARTIFACT TEMPLATE FORMAT ────────────────────────────────────────────
 *
 *  An artifact template is the foundry's output for one (region, signature) pair:
 *
 *    {
 *      normal_form_hash,     // identity key
 *      template_bytes,       // concatenated stencil .text sections
 *      holes[],              // all patch holes, in template-byte offset order
 *      guards[],             // per-guard: { pc, slot, kind, exit_hole_idx }
 *      dependencies[],       // what invalidates this artifact
 *      projection,           // what to reconstruct on exit
 *    }
 *
 *  At runtime: memcpy template_bytes into executable memory, iterate holes,
 *  patch each from runtime state (slot offsets from frame, shape IDs from
 *  observed facts, etc.), then call the entry point.
 */

#ifndef SPONJIT_STENCIL_ABI_H
#define SPONJIT_STENCIL_ABI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* ── VM value representation (Lua 5.x compatible) ─────────────────────── */

typedef uint64_t TValue;  /* tagged union: low 48 bits = value, high 16 = tag */

#define TAG_NIL      0x0000ULL
#define TAG_FALSE    0x0100ULL
#define TAG_TRUE     0x0200ULL
#define TAG_INTEGER  0x0300ULL
#define TAG_NUMBER   0x0400ULL
#define TAG_STRING   0x0500ULL
#define TAG_TABLE    0x0600ULL
#define TAG_CLOSURE  0x0700ULL

static inline int tvalue_tag(TValue v)  { return (int)((v >> 48) & 0xFFFF); }
static inline int64_t tvalue_i64(TValue v) { return (int64_t)(v & 0xFFFFFFFFFFFFULL); }
static inline TValue tagged_i64(int64_t i) { return ((uint64_t)TAG_INTEGER << 48) | ((uint64_t)i & 0xFFFFFFFFFFFFULL); }

/* ── VM structures (opaque for now; minimal for stencils) ─────────────── */

typedef struct Table {
    TValue *fields;        /* shape-keyed field array */
    TValue *array;         /* integer-keyed array part */
    uint64_t shape_epoch;  /* shape identity */
    struct Table *metatable;
    uint8_t gc_color;
    /* ... */
} Table;

typedef struct Closure {
    void *proto;           /* prototype for call-target checks */
    /* ... */
} Closure;

typedef struct LuaFrame {
    TValue *stack;         /* base of current Lua stack frame */
    TValue *constants;     /* proto constants table */
    /* ... */
} LuaFrame;

/* ── hole descriptor ──────────────────────────────────────────────────── */

enum HoleKind {
    HOLE_SLOT_OFFSET = 0,
    HOLE_FIELD_OFFSET,
    HOLE_ARRAY_BASE,
    HOLE_CONST_IDX,
    HOLE_SHAPE_ID,
    HOLE_CALL_TARGET,
    HOLE_BARRIER_COLOR,
    HOLE_TARGET_PC,
    HOLE_EXIT_ADDR,
    HOLE_RESUME_PC,
    HOLE_IMMEDIATE_I64,
};

typedef struct PatchHole {
    const char *name;
    uint32_t offset;          /* byte offset within template_bytes */
    uint8_t  size;            /* 1, 2, 4, or 8 bytes */
    uint8_t  kind;            /* HoleKind enum */
} PatchHole;

/* ── guard / exit descriptor ──────────────────────────────────────────── */

typedef struct GuardDesc {
    uint16_t pc;              /* original bytecode PC for debugging */
    uint16_t slot;            /* which stack slot was guarded */
    uint16_t kind;            /* guard_i64, guard_shape, etc. (as enum) */
    uint16_t exit_hole_idx;   /* index into holes[] for exit address */
} GuardDesc;

/* ── artifact template ────────────────────────────────────────────────── */

typedef struct ArtifactTemplate {
    /* identity */
    char     normal_form_hash[16];

    /* code */
    uint8_t *template_bytes;
    uint32_t template_size;

    /* holes to patch at runtime */
    PatchHole *holes;
    uint16_t   hole_count;

    /* guard metadata */
    GuardDesc *guards;
    uint16_t   guard_count;

    /* dependencies (epochs / values that invalidate this artifact) */
    uint32_t *deps;
    uint16_t   dep_count;

    /* projection metadata for exits */
    uint16_t *live_slots;
    uint16_t  live_slot_count;

    /* estimated cost */
    uint32_t estimated_cycles;
    uint32_t estimated_size;
} ArtifactTemplate;

/* ── STENCIL FUNCTION SIGNATURES ─────────────────────────────────────────
 *
 * Each stencil is a standalone C function compiled into the stencil library.
 * Input: LuaFrame* in rbx, TValue current in rax, i64 accumulator in rcx.
 * Output: next TValue in rax, i64 accumulator in rcx, or jump to exit.
 *
 * Guards set ZF=1 on match, jump to exit on mismatch.
 * Pure ops leave rax/rcx with result.
 * Store ops write to frame or heap.
 * Call/return ops set up continuation and jump.
 *
 * The C prototypes below are for documentation and GCC compilation. The
 * actual asm is what GCC emits from these functions compiled with -O2 -fomit-frame-pointer.
 */

/* ── guards ───────────────────────────────────────────────────────────── */
void stencil_guard_i64(void);            /* if tag(rax) != INTEGER -> exit */
void stencil_guard_table(void);          /* if tag(rax) != TABLE -> exit */
void stencil_guard_shape(void);          /* if table(rax)->shape_epoch != [shape_id] -> exit */
void stencil_guard_metatable_absent(void); /* if table(rax)->metatable != NULL -> exit */
void stencil_guard_call_target(void);    /* if closure(rax)->proto != [target] -> exit */
void stencil_guard_array_hit(void);      /* if table(rax)->array == NULL -> exit */

/* ── slot / value movement ────────────────────────────────────────────── */
void stencil_load_slot(void);            /* rax = frame->stack[slot_offset] */
void stencil_store_slot(void);           /* frame->stack[slot_offset] = rax */
void stencil_load_const(void);           /* rax = frame->constants[const_idx] */
void stencil_const_i64(void);            /* rax = tagged_i64(immediate) */
void stencil_const_nil(void);            /* rax = NIL */
void stencil_const_bool(void);           /* rax = bool_val ? TRUE : FALSE */

/* ── box / unbox ──────────────────────────────────────────────────────── */
void stencil_box_i64(void);              /* rax = tagged_i64(rcx) */
void stencil_unbox_i64(void);            /* rcx = tvalue_i64(rax) */

/* ── arithmetic (operates on rcx, unboxed) ────────────────────────────── */
void stencil_add_i64(void);              /* rcx = rcx + tvalue_i64(rhs_from_slot) */
void stencil_sub_i64(void);              /* rcx = rcx - tvalue_i64(rhs_from_slot) */
void stencil_mul_i64(void);              /* rcx = rcx * tvalue_i64(rhs_from_slot) */
void stencil_cmp_i64(void);              /* cmp rcx, tvalue_i64(rhs_from_slot); sets flags */

/* ── table access ─────────────────────────────────────────────────────── */
void stencil_table_field_load(void);     /* rax = table->fields[field_offset] */
void stencil_table_field_store(void);    /* table->fields[field_offset] = rax */
void stencil_table_array_load(void);     /* rax = table->array[index] */
void stencil_table_array_store(void);    /* table->array[index] = rax */

/* ── call / return ────────────────────────────────────────────────────── */
void stencil_call_boundary(void);        /* prepare call frame, jump to target */
void stencil_tailcall_boundary(void);    /* reuse frame, jump to target */
void stencil_return0(void);              /* return 0 values */
void stencil_return1(void);              /* return 1 value (rax) */

/* ── misc ─────────────────────────────────────────────────────────────── */
void stencil_barrier_check(void);        /* if gc_barrier needed: call slow path */
void stencil_residual_boundary(void);    /* save state, jump back to interpreter */
void stencil_jump(void);                 /* jmp [target_pc] */

/* ── fused ────────────────────────────────────────────────────────────── */
void stencil_unbox_add_i64_box(void);    /* unbox rhs(rax), rcx += rhs_i64, box(rcx)->rax */
void stencil_field_load_return1(void);   /* rax = table->fields[offset]; return rax */
void stencil_field_load_add_store(void); /* load + unbox + add + box + store (fused) */

/* ── runtime materialization API ──────────────────────────────────────── */

/*
 * Load a precompiled artifact template (foundry output) into executable memory.
 * Returns a callable function pointer, or NULL on failure.
 */
void *sponjit_materialize(const ArtifactTemplate *tmpl);

/*
 * Patch an artifact instance with runtime values.
 * Called once per region entry when the artifact is first used or when
 * epoch-dependent values change.
 */
void sponjit_patch(void *artifact, const LuaFrame *frame, const uint64_t *shape_epochs);

/*
 * Free an artifact instance.
 */
void sponjit_free_artifact(void *artifact);

#endif /* SPONJIT_STENCIL_ABI_H */
