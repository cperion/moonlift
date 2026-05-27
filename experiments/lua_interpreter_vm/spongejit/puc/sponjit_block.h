/* SponJIT VM orchestration: cache-first region execution.
 *
 * Env:
 *   SPONJIT_ENABLE=1          enable probes/scanner
 *   SPONJIT_STATS=/path       write counters
 *   SPONJIT_PRINT=1           print counters at exit
 *   SPONJIT_UNSAFE_EXECUTE=1  execute generated stencil cache entries
 *
 * Important safety boundary:
 * Foundry/cache data may contain SSA stencil chains that are useful for
 * discovery but are not yet complete PUC-opcode implementations. By default
 * we do not install executable cache entries. This keeps the patched VM
 * correct while preserving generated data for inspection and future lowering.
 */

#include "lopnames.h"
#include <sys/mman.h>

#define SPONJIT_CACHE_SIZE 128
#define SPONJIT_CACHE_MASK (SPONJIT_CACHE_SIZE - 1)

/* Must match stencils/stencils_puc.c. */
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

typedef void (*SponJitRegionFn)(StencilCtx *ctx);

typedef struct {
    void            *proto;
    uint32_t         pc_offset;
    uint32_t         nops;
    SponJitRegionFn  entry;
} SponJitCacheEntry;

typedef struct { uint32_t offset, size, kind; } SponJitHole;
typedef struct {
    OpCode         opcodes[8];
    int            nops;
    unsigned char *code;
    int            code_size;
    SponJitHole   *holes;
    int            nholes;
} SponJitCacheDesc;

extern SponJitCacheDesc sponjit_cache_descs[];
extern int sponjit_cache_desc_count;
extern int sponjit_cache_unsafe;

static SponJitCacheEntry sponjit_cache[SPONJIT_CACHE_SIZE];

static int moonlift_sponjit_enabled = -1;
static int moonlift_sponjit_print = 0;
static int moonlift_sponjit_collect = 0;
static int moonlift_sponjit_unsafe_execute = 0;
static int moonlift_sponjit_trace = 0;
static int moonlift_sponjit_trace_left = 0;
static unsigned long long moonlift_sponjit_cache_probes;
static unsigned long long moonlift_sponjit_cache_hits;
static unsigned long long moonlift_sponjit_dispatch_entries;
static unsigned long long moonlift_sponjit_absorbed_ops;

#define SPONJIT_INC(x) do { if (moonlift_sponjit_collect) (x)++; } while (0)
#define SPONJIT_ADD(x,n) do { if (moonlift_sponjit_collect) (x) += (n); } while (0)

static void moonlift_sponjit_dump_stats(void) {
    const char *path = getenv("SPONJIT_STATS");
    FILE *f = (path && path[0]) ? fopen(path, "w") : NULL;
    if (f) {
        fprintf(f, "# dispatch_entries\t%llu\n# cache_probes\t%llu\n# cache_hits\t%llu\n# absorbed_ops\t%llu\n",
                moonlift_sponjit_dispatch_entries,
                moonlift_sponjit_cache_probes,
                moonlift_sponjit_cache_hits,
                moonlift_sponjit_absorbed_ops);
        fclose(f);
    }
    if (moonlift_sponjit_print) {
        double hit_rate = moonlift_sponjit_cache_probes
            ? (100.0 * (double)moonlift_sponjit_cache_hits / (double)moonlift_sponjit_cache_probes)
            : 0.0;
        fprintf(stderr,
                "[sponjit] enabled=%d unsafe_execute=%d dispatch=%llu cache_hits=%llu absorbed=%llu hit_rate=%.2f%%\n",
                moonlift_sponjit_enabled,
                moonlift_sponjit_unsafe_execute,
                moonlift_sponjit_dispatch_entries,
                moonlift_sponjit_cache_hits,
                moonlift_sponjit_absorbed_ops,
                hit_rate);
    }
}

static void moonlift_sponjit_init_if_needed(void) {
    if (moonlift_sponjit_enabled < 0) {
        const char *e = getenv("SPONJIT_ENABLE");
        const char *p = getenv("SPONJIT_PRINT");
        const char *u = getenv("SPONJIT_UNSAFE_EXECUTE");
        const char *t = getenv("SPONJIT_TRACE");
        moonlift_sponjit_enabled = (e && e[0] && e[0] != '0');
        moonlift_sponjit_print = (p && p[0] && p[0] != '0');
        moonlift_sponjit_unsafe_execute = (u && u[0] && u[0] != '0');
        moonlift_sponjit_trace = (t && t[0] && t[0] != '0');
        moonlift_sponjit_trace_left = moonlift_sponjit_trace ? 200 : 0;
        moonlift_sponjit_collect = (getenv("SPONJIT_STATS") || moonlift_sponjit_print);
        if (moonlift_sponjit_collect) atexit(moonlift_sponjit_dump_stats);
    }
}

static void sponjit_install(void *proto, uint32_t pc_offset, uint32_t nops, SponJitRegionFn entry) {
    uint32_t h = (((uintptr_t)proto >> 3) ^ pc_offset) & SPONJIT_CACHE_MASK;
    for (uint32_t i = 0; i < 16; i++) {
        SponJitCacheEntry *e = &sponjit_cache[(h + i) & SPONJIT_CACHE_MASK];
        if (e->proto == NULL) {
            e->proto = proto;
            e->pc_offset = pc_offset;
            e->nops = nops;
            e->entry = entry;
            return;
        }
    }
}

static void sponjit_materialize_and_install(const Proto *p, int pc_offset, const SponJitCacheDesc *desc) {
    unsigned char *mem;
    if (sponjit_cache_unsafe && !moonlift_sponjit_unsafe_execute) return;
    if (!desc || !desc->code || desc->code_size <= 0) return;
    mem = (unsigned char *)mmap(NULL, (size_t)desc->code_size,
        PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mem == MAP_FAILED) return;
    memcpy(mem, desc->code, (size_t)desc->code_size);
    sponjit_install((void *)p, (uint32_t)pc_offset, (uint32_t)desc->nops, (SponJitRegionFn)mem);
}

static void sponjit_scan_proto(const Proto *p) {
    if (sponjit_cache_unsafe && !moonlift_sponjit_unsafe_execute) return;
    if (!p || !p->code) return;
    for (int fi = 0; fi < sponjit_cache_desc_count; fi++) {
        SponJitCacheDesc *d = &sponjit_cache_descs[fi];
        if (!d->code || d->nops < 1 || d->nops > 8) continue;
        if (p->sizecode < d->nops) continue;
        for (int pc = 0; pc <= p->sizecode - d->nops; pc++) {
            int match = 1;
            for (int j = 0; j < d->nops; j++) {
                if (GET_OPCODE(p->code[pc + j]) != d->opcodes[j]) {
                    match = 0;
                    break;
                }
            }
            if (match) sponjit_materialize_and_install(p, pc, d);
        }
    }
}

static inline int sponjit_cache_lookup(const Proto *proto, const Instruction *pc,
                                       SponJitRegionFn *ret_entry,
                                       uint32_t *ret_nops) {
    uint32_t off = (uint32_t)(pc - proto->code);
    uint32_t h = (((uintptr_t)proto >> 3) ^ off) & SPONJIT_CACHE_MASK;
    for (uint32_t i = 0; i < 16; i++) {
        SponJitCacheEntry *e = &sponjit_cache[(h + i) & SPONJIT_CACHE_MASK];
        if (e->proto == NULL) return 0;
        if (e->proto == (void *)proto && e->pc_offset == off) {
            *ret_entry = e->entry;
            *ret_nops = e->nops;
            return 1;
        }
    }
    return 0;
}
