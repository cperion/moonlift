#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "mlui_c_api.h"

enum {
    KIND_WIDTH = 40,
    KIND_HEIGHT = 41,
    KIND_BG = 61,
    KIND_BORDER_WIDTH = 63,
    KIND_ROUNDED = 64,
    KIND_OPACITY = 65,
    KIND_CURSOR = 90,
    LEN_FIXED = 3,
    ROLE_HIT_TARGET = 1,
    ROLE_FOCUS_TARGET = 2,
    ROLE_ACTIVATE_TARGET = 3,
    AXIS_Y = 1
};

typedef enum bench_shape {
    BENCH_CHAIN,
    BENCH_FLAT,
    BENCH_BALANCED,
    BENCH_INTERACTIVE,
    BENCH_INPUT,
    BENCH_CLICK
} bench_shape;

typedef enum bench_raw_mode {
    RAW_NONE,
    RAW_MOVE,
    RAW_CLICK
} bench_raw_mode;

typedef struct bench_case {
    const char* name;
    bench_shape shape;
    bench_raw_mode raw_mode;
} bench_case;

typedef struct bench_program {
    mlui_program program;
    mlui_auth_buffer* auth;
    mlui_auth_node* nodes;
    uint32_t* children;
    mlui_style_token* tokens;
} bench_program;

typedef struct sample_result {
    double validate_ms;
    double load_ms;
    double frame_us;
    double ns_per_node;
    double ops_per_frame;
    double events_per_frame;
} sample_result;

typedef enum bench_run_mode {
    RUN_LOADED,
    RUN_REBUILD
} bench_run_mode;

static void* g_kernel_slot_ptrs[16];
static uint32_t g_kernel_slot_gens[16];

void* default_malloc(size_t n) { return malloc(n); }
void* default_realloc(void* p, size_t n) { return realloc(p, n); }
void default_free(void* p) { free(p); }

void* mlui_kernel_get_ptr(uint32_t slot)
{
    if (slot >= 16u) return NULL;
    return g_kernel_slot_ptrs[slot];
}

uint32_t mlui_kernel_get_gen(uint32_t slot)
{
    if (slot >= 16u) return 0u;
    return g_kernel_slot_gens[slot];
}

void mlui_kernel_set_ptr(uint32_t slot, void* p)
{
    if (slot >= 16u) return;
    g_kernel_slot_ptrs[slot] = p;
}

void mlui_kernel_set_gen(uint32_t slot, uint32_t g)
{
    if (slot >= 16u) return;
    g_kernel_slot_gens[slot] = g;
}

static int64_t now_ns(void)
{
    struct timespec ts = {0};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

static void fail_status(const char* where, mlui_status st)
{
    fprintf(stderr, "%s failed: code=%d detail=%d at=%zu needed=%zu\n",
            where, st.code, st.detail, st.at, st.needed);
}

static void* xcalloc(size_t n, size_t size)
{
    void* p = calloc(n, size);
    if (!p) {
        fprintf(stderr, "out of memory allocating %zu x %zu\n", n, size);
        exit(111);
    }
    return p;
}

static mlui_style_token make_token(uint16_t kind, double a, double b, uint32_t rgba)
{
    mlui_style_token t;
    memset(&t, 0, sizeof(t));
    t.atom.kind = kind;
    t.atom.a = a;
    t.atom.b = b;
    t.atom.color.rgba8 = rgba;
    return t;
}

static void set_node_base(mlui_auth_node* n, uint32_t id, uint8_t kind, uint32_t token_first, uint32_t token_count)
{
    memset(n, 0, sizeof(*n));
    n->id = id;
    n->kind = kind;
    n->token_first = token_first;
    n->token_count = token_count;
}

static void fill_box_style(mlui_style_token* tokens, uint32_t first, uint32_t i, int rich)
{
    tokens[first + 0u] = make_token(KIND_WIDTH, LEN_FIXED, rich ? 96.0 + (double)(i & 15u) : 1000.0 + (double)(i & 7u), 0);
    tokens[first + 1u] = make_token(KIND_HEIGHT, LEN_FIXED, rich ? 20.0 + (double)(i & 7u) : 28.0 + (double)(i & 3u), 0);
    if (!rich) return;
    tokens[first + 2u] = make_token(KIND_BG, 0.0, 0.0, 0xff202830u + (i & 15u));
    tokens[first + 3u] = make_token(KIND_BORDER_WIDTH, 1.0 + (double)(i & 1u), 0.0, 0);
    tokens[first + 4u] = make_token(KIND_ROUNDED, 3.0 + (double)(i & 3u), 0.0, 0);
    tokens[first + 5u] = make_token(KIND_OPACITY, 1.0, 0.0, 0);
    tokens[first + 6u] = make_token(KIND_CURSOR, 1.0 + (double)(i & 3u), 0.0, 0);
}

static void finish_program(bench_program* bp, size_t n_nodes, size_t n_children, size_t n_tokens)
{
    mlui_style_token_buffer style_buf;
    memset(&style_buf, 0, sizeof(style_buf));
    style_buf.tokens = bp->tokens;
    style_buf.n = n_tokens;
    style_buf.cap = n_tokens;

    bp->auth->nodes = bp->nodes;
    bp->auth->n_node = n_nodes;
    bp->auth->cap_node = n_nodes;
    bp->auth->children = bp->children;
    bp->auth->n_child = n_children;
    bp->auth->cap_child = n_children;
    bp->auth->styles = style_buf;

    memset(&bp->program, 0, sizeof(bp->program));
    bp->program.header.magic = MLUI_MAGIC;
    bp->program.header.abi_version = MLUI_ABI_VERSION;
    bp->program.header.root_index = 0;
    bp->program.header.root_kind = MLUI_ROOT_AUTH;
    bp->program.header.endian = MLUI_ENDIAN_LITTLE;
    bp->program.header.pointer_size = sizeof(void*);
    bp->program.header.epoch = 1;
    bp->program.auth = bp->auth;
}

static bench_program make_chain_program(uint32_t n_nodes, int rich)
{
    if (n_nodes == 0u) n_nodes = 1u;
    const uint32_t toks_per_node = rich ? 7u : 2u;
    bench_program bp;
    memset(&bp, 0, sizeof(bp));
    bp.auth = (mlui_auth_buffer*)xcalloc(1u, sizeof(*bp.auth));
    bp.nodes = (mlui_auth_node*)xcalloc(n_nodes, sizeof(*bp.nodes));
    bp.children = n_nodes > 1u ? (uint32_t*)xcalloc(n_nodes - 1u, sizeof(*bp.children)) : NULL;
    bp.tokens = (mlui_style_token*)xcalloc((size_t)n_nodes * toks_per_node, sizeof(*bp.tokens));

    for (uint32_t i = 0u; i < n_nodes; ++i) {
        set_node_base(&bp.nodes[i], 1000u + i, MLUI_AUTH_BOX, i * toks_per_node, toks_per_node);
        fill_box_style(bp.tokens, i * toks_per_node, i, rich);
        if (i + 1u < n_nodes) {
            bp.nodes[i].first_child = i;
            bp.nodes[i].n_child = 1u;
            bp.children[i] = i + 1u;
        }
    }
    finish_program(&bp, n_nodes, n_nodes > 0u ? n_nodes - 1u : 0u, (size_t)n_nodes * toks_per_node);
    return bp;
}

static bench_program make_flat_program(uint32_t n_nodes, int rich)
{
    if (n_nodes < 2u) n_nodes = 2u;
    const uint32_t toks_per_child = rich ? 7u : 2u;
    const uint32_t child_count = n_nodes - 1u;
    bench_program bp;
    memset(&bp, 0, sizeof(bp));
    bp.auth = (mlui_auth_buffer*)xcalloc(1u, sizeof(*bp.auth));
    bp.nodes = (mlui_auth_node*)xcalloc(n_nodes, sizeof(*bp.nodes));
    bp.children = (uint32_t*)xcalloc(child_count, sizeof(*bp.children));
    bp.tokens = (mlui_style_token*)xcalloc((size_t)child_count * toks_per_child, sizeof(*bp.tokens));

    set_node_base(&bp.nodes[0], 1u, MLUI_AUTH_FRAGMENT, 0u, 0u);
    bp.nodes[0].first_child = 0u;
    bp.nodes[0].n_child = child_count;
    for (uint32_t i = 0u; i < child_count; ++i) {
        uint32_t node_i = i + 1u;
        uint32_t tok = i * toks_per_child;
        bp.children[i] = node_i;
        set_node_base(&bp.nodes[node_i], 2000u + i, MLUI_AUTH_BOX, tok, toks_per_child);
        fill_box_style(bp.tokens, tok, i, rich);
    }
    finish_program(&bp, n_nodes, child_count, (size_t)child_count * toks_per_child);
    return bp;
}

static bench_program make_balanced_program(uint32_t n_nodes, int rich)
{
    if (n_nodes == 0u) n_nodes = 1u;
    const uint32_t toks_per_node = rich ? 7u : 2u;
    bench_program bp;
    memset(&bp, 0, sizeof(bp));
    bp.auth = (mlui_auth_buffer*)xcalloc(1u, sizeof(*bp.auth));
    bp.nodes = (mlui_auth_node*)xcalloc(n_nodes, sizeof(*bp.nodes));
    bp.children = n_nodes > 1u ? (uint32_t*)xcalloc(n_nodes - 1u, sizeof(*bp.children)) : NULL;
    bp.tokens = (mlui_style_token*)xcalloc((size_t)n_nodes * toks_per_node, sizeof(*bp.tokens));

    uint32_t child_write = 0u;
    for (uint32_t i = 0u; i < n_nodes; ++i) {
        set_node_base(&bp.nodes[i], 3000u + i, MLUI_AUTH_BOX, i * toks_per_node, toks_per_node);
        fill_box_style(bp.tokens, i * toks_per_node, i, rich);
        uint32_t left = i * 2u + 1u;
        uint32_t right = left + 1u;
        bp.nodes[i].first_child = child_write;
        if (left < n_nodes) {
            bp.children[child_write++] = left;
            bp.nodes[i].n_child++;
        }
        if (right < n_nodes) {
            bp.children[child_write++] = right;
            bp.nodes[i].n_child++;
        }
    }
    finish_program(&bp, n_nodes, child_write, (size_t)n_nodes * toks_per_node);
    return bp;
}

static bench_program make_interactive_program(uint32_t n_nodes)
{
    if (n_nodes < 3u) n_nodes = 3u;
    uint32_t pair_count = (n_nodes - 1u) / 2u;
    if (pair_count == 0u) pair_count = 1u;
    uint32_t actual_nodes = 1u + pair_count * 2u;
    const uint32_t toks_per_leaf = 7u;
    bench_program bp;
    memset(&bp, 0, sizeof(bp));
    bp.auth = (mlui_auth_buffer*)xcalloc(1u, sizeof(*bp.auth));
    bp.nodes = (mlui_auth_node*)xcalloc(actual_nodes, sizeof(*bp.nodes));
    bp.children = (uint32_t*)xcalloc(pair_count * 2u, sizeof(*bp.children));
    bp.tokens = (mlui_style_token*)xcalloc((size_t)pair_count * toks_per_leaf, sizeof(*bp.tokens));

    set_node_base(&bp.nodes[0], 1u, MLUI_AUTH_FRAGMENT, 0u, 0u);
    bp.nodes[0].first_child = 0u;
    bp.nodes[0].n_child = pair_count;

    uint32_t child_write = 0u;
    for (uint32_t i = 0u; i < pair_count; ++i) {
        uint32_t wrapper_i = 1u + i * 2u;
        uint32_t leaf_i = wrapper_i + 1u;
        uint8_t kind = MLUI_AUTH_WITH_INPUT;
        if ((i % 8u) == 1u) kind = MLUI_AUTH_SCROLL;
        if ((i % 8u) == 2u) kind = MLUI_AUTH_FOCUS_SCOPE;
        if ((i % 8u) == 3u) kind = MLUI_AUTH_LAYER;
        if ((i % 8u) == 4u) kind = MLUI_AUTH_OVERLAY;
        if ((i % 8u) == 5u) kind = MLUI_AUTH_MODAL;
        if ((i % 8u) == 6u) kind = MLUI_AUTH_WITH_DRAG_SOURCE;
        if ((i % 8u) == 7u) kind = MLUI_AUTH_WITH_DROP_TARGET;

        bp.children[child_write] = wrapper_i;
        set_node_base(&bp.nodes[wrapper_i], 4000u + i, kind, 0u, 0u);
        bp.nodes[wrapper_i].first_child = pair_count + i;
        bp.nodes[wrapper_i].n_child = 1u;
        bp.nodes[wrapper_i].role = (i & 1u) ? ROLE_FOCUS_TARGET : ROLE_ACTIVATE_TARGET;
        bp.nodes[wrapper_i].scroll_axis = AXIS_Y;
        bp.nodes[wrapper_i].focus_policy = 1u;
        bp.nodes[wrapper_i].layer_kind = 1u;
        bp.nodes[wrapper_i].overlay_placement = 1u;
        bp.nodes[wrapper_i].anchor_id = 4000u;
        bp.nodes[wrapper_i].order = (double)(i & 15u);
        bp.nodes[wrapper_i].modal = (i % 8u) == 4u;

        bp.children[pair_count + i] = leaf_i;
        set_node_base(&bp.nodes[leaf_i], 100000u + i, MLUI_AUTH_BOX, i * toks_per_leaf, toks_per_leaf);
        fill_box_style(bp.tokens, i * toks_per_leaf, i, 1);
        child_write++;
    }
    finish_program(&bp, actual_nodes, pair_count * 2u, (size_t)pair_count * toks_per_leaf);
    return bp;
}

static bench_program make_program(bench_shape shape, uint32_t n_nodes)
{
    switch (shape) {
    case BENCH_CHAIN: return make_chain_program(n_nodes, 0);
    case BENCH_FLAT: return make_flat_program(n_nodes, 0);
    case BENCH_BALANCED: return make_balanced_program(n_nodes, 0);
    case BENCH_INTERACTIVE:
    case BENCH_INPUT:
    case BENCH_CLICK: return make_interactive_program(n_nodes);
    }
    return make_chain_program(n_nodes, 0);
}

static void free_program(bench_program* bp)
{
    free(bp->nodes);
    free(bp->children);
    free(bp->tokens);
    free(bp->auth);
    memset(bp, 0, sizeof(*bp));
}

static int cmp_double(const void* a, const void* b)
{
    double av = *(const double*)a;
    double bv = *(const double*)b;
    return (av > bv) - (av < bv);
}

static double median_of(double* values, int n)
{
    qsort(values, (size_t)n, sizeof(values[0]), cmp_double);
    if ((n & 1) != 0) return values[n / 2];
    return (values[n / 2 - 1] + values[n / 2]) * 0.5;
}

static sample_result run_one_sample(const bench_case* bc, uint32_t node_count, int loops, int warmup,
                                    double env_w, double env_h)
{
    sample_result out;
    memset(&out, 0, sizeof(out));

    bench_program bp = make_program(bc->shape, node_count);
    mlui_kernel* kernel = NULL;
    int init_rc = mlui_kernel_init(&kernel);
    if (init_rc != 0 || kernel == NULL) {
        fprintf(stderr, "mlui_kernel_init failed: %d\n", init_rc);
        exit(2);
    }

    int64_t t0 = now_ns();
    mlui_status st = mlui_validate_program(kernel, &bp.program);
    if (st.code != MLUI_OK) {
        fail_status("mlui_validate_program", st);
        exit(3);
    }
    int64_t t1 = now_ns();

    mlui_node_ref root = MLUI_INVALID_HANDLE;
    st = mlui_load_program(kernel, &bp.program, &root);
    if (st.code != MLUI_OK) {
        fail_status("mlui_load_program", st);
        exit(4);
    }
    int64_t t2 = now_ns();

    mlui_raw_input raw;
    memset(&raw, 0, sizeof(raw));

    const mlui_view_op* ops = NULL;
    const mlui_event* events = NULL;
    size_t n_ops = 0;
    size_t n_events = 0;
    for (int i = 0; i < warmup; ++i) {
        const mlui_raw_input* rawp = NULL;
        if (bc->raw_mode == RAW_MOVE) {
            raw.kind = MLUI_RAW_POINTER_MOVED;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        } else if (bc->raw_mode == RAW_CLICK) {
            raw.kind = (i & 1) == 0 ? MLUI_RAW_POINTER_PRESSED : MLUI_RAW_POINTER_RELEASED;
            raw.button = MLUI_BUTTON_LEFT;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        }
        st = mlui_frame(kernel, root, env_w, env_h, rawp);
        if (st.code != MLUI_OK) {
            fail_status("mlui_frame warmup", st);
            exit(5);
        }
        (void)mlui_view_ops(kernel, &ops, &n_ops);
        (void)mlui_events(kernel, &events, &n_events);
    }

    size_t total_ops = 0;
    size_t total_events = 0;
    int64_t f0 = now_ns();
    for (int i = 0; i < loops; ++i) {
        const mlui_raw_input* rawp = NULL;
        if (bc->raw_mode == RAW_MOVE) {
            raw.kind = MLUI_RAW_POINTER_MOVED;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        } else if (bc->raw_mode == RAW_CLICK) {
            raw.kind = (i & 1) == 0 ? MLUI_RAW_POINTER_PRESSED : MLUI_RAW_POINTER_RELEASED;
            raw.button = MLUI_BUTTON_LEFT;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        }
        st = mlui_frame(kernel, root, env_w, env_h, rawp);
        if (st.code != MLUI_OK) {
            fail_status("mlui_frame", st);
            exit(6);
        }
        if (mlui_view_ops(kernel, &ops, &n_ops) != 0) exit(7);
        if (mlui_events(kernel, &events, &n_events) != 0) exit(8);
        total_ops += n_ops;
        total_events += n_events;
    }
    int64_t f1 = now_ns();

    out.validate_ms = (double)(t1 - t0) / 1e6;
    out.load_ms = (double)(t2 - t1) / 1e6;
    out.frame_us = ((double)(f1 - f0) / (double)loops) / 1000.0;
    out.ns_per_node = ((double)(f1 - f0) / (double)loops) / (double)bp.auth->n_node;
    out.ops_per_frame = loops == 0 ? 0.0 : (double)total_ops / (double)loops;
    out.events_per_frame = loops == 0 ? 0.0 : (double)total_events / (double)loops;

    int close_rc = mlui_kernel_close(kernel);
    if (close_rc != 0) {
        fprintf(stderr, "mlui_kernel_close failed: %d\n", close_rc);
        exit(9);
    }
    free_program(&bp);
    return out;
}

static sample_result run_one_rebuild_sample(const bench_case* bc, uint32_t node_count, int loops, int warmup,
                                            double env_w, double env_h)
{
    sample_result out;
    memset(&out, 0, sizeof(out));

    mlui_raw_input raw;
    memset(&raw, 0, sizeof(raw));

    mlui_kernel* kernel = NULL;
    int init_rc = mlui_kernel_init(&kernel);
    if (init_rc != 0 || kernel == NULL) {
        fprintf(stderr, "mlui_kernel_init failed: %d\n", init_rc);
        exit(2);
    }

    for (int i = 0; i < warmup; ++i) {
        bench_program bp = make_program(bc->shape, node_count);
        mlui_status st = mlui_validate_program(kernel, &bp.program);
        if (st.code != MLUI_OK) {
            fail_status("mlui_validate_program warmup", st);
            exit(3);
        }
        mlui_node_ref root = MLUI_INVALID_HANDLE;
        st = mlui_load_program(kernel, &bp.program, &root);
        if (st.code != MLUI_OK) {
            fail_status("mlui_load_program warmup", st);
            exit(4);
        }
        const mlui_raw_input* rawp = NULL;
        if (bc->raw_mode == RAW_MOVE) {
            raw.kind = MLUI_RAW_POINTER_MOVED;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        } else if (bc->raw_mode == RAW_CLICK) {
            raw.kind = (i & 1) == 0 ? MLUI_RAW_POINTER_PRESSED : MLUI_RAW_POINTER_RELEASED;
            raw.button = MLUI_BUTTON_LEFT;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        }
        st = mlui_frame(kernel, root, env_w, env_h, rawp);
        if (st.code != MLUI_OK) {
            fail_status("mlui_frame warmup", st);
            exit(5);
        }
        free_program(&bp);
    }

    size_t total_ops = 0;
    size_t total_events = 0;
    int64_t f0 = now_ns();
    for (int i = 0; i < loops; ++i) {
        bench_program bp = make_program(bc->shape, node_count);
        mlui_status st = mlui_validate_program(kernel, &bp.program);
        if (st.code != MLUI_OK) {
            fail_status("mlui_validate_program", st);
            exit(3);
        }
        mlui_node_ref root = MLUI_INVALID_HANDLE;
        st = mlui_load_program(kernel, &bp.program, &root);
        if (st.code != MLUI_OK) {
            fail_status("mlui_load_program", st);
            exit(4);
        }
        const mlui_raw_input* rawp = NULL;
        if (bc->raw_mode == RAW_MOVE) {
            raw.kind = MLUI_RAW_POINTER_MOVED;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        } else if (bc->raw_mode == RAW_CLICK) {
            raw.kind = (i & 1) == 0 ? MLUI_RAW_POINTER_PRESSED : MLUI_RAW_POINTER_RELEASED;
            raw.button = MLUI_BUTTON_LEFT;
            raw.x = 12.0;
            raw.y = 12.0;
            rawp = &raw;
        }
        st = mlui_frame(kernel, root, env_w, env_h, rawp);
        if (st.code != MLUI_OK) {
            fail_status("mlui_frame", st);
            exit(6);
        }
        const mlui_view_op* ops = NULL;
        const mlui_event* events = NULL;
        size_t n_ops = 0;
        size_t n_events = 0;
        if (mlui_view_ops(kernel, &ops, &n_ops) != 0) exit(7);
        if (mlui_events(kernel, &events, &n_events) != 0) exit(8);
        total_ops += n_ops;
        total_events += n_events;
        free_program(&bp);
    }
    int64_t f1 = now_ns();

    int close_rc = mlui_kernel_close(kernel);
    if (close_rc != 0) {
        fprintf(stderr, "mlui_kernel_close failed: %d\n", close_rc);
        exit(9);
    }

    bench_program shape_probe = make_program(bc->shape, node_count);
    double actual_nodes = (double)shape_probe.auth->n_node;
    free_program(&shape_probe);

    out.validate_ms = 0.0;
    out.load_ms = 0.0;
    out.frame_us = ((double)(f1 - f0) / (double)loops) / 1000.0;
    out.ns_per_node = ((double)(f1 - f0) / (double)loops) / actual_nodes;
    out.ops_per_frame = loops == 0 ? 0.0 : (double)total_ops / (double)loops;
    out.events_per_frame = loops == 0 ? 0.0 : (double)total_events / (double)loops;
    return out;
}

static void run_case(const bench_case* bc, uint32_t node_count, int loops, int warmup,
                     int samples, double env_w, double env_h, bench_run_mode mode)
{
    double* frame_us = (double*)xcalloc((size_t)samples, sizeof(double));
    double* ns_node = (double*)xcalloc((size_t)samples, sizeof(double));
    sample_result first;
    memset(&first, 0, sizeof(first));
    double min_us = 1e300;
    double max_us = 0.0;

    for (int i = 0; i < samples; ++i) {
        sample_result r = mode == RUN_REBUILD
            ? run_one_rebuild_sample(bc, node_count, loops, warmup, env_w, env_h)
            : run_one_sample(bc, node_count, loops, warmup, env_w, env_h);
        if (i == 0) first = r;
        frame_us[i] = r.frame_us;
        ns_node[i] = r.ns_per_node;
        if (r.frame_us < min_us) min_us = r.frame_us;
        if (r.frame_us > max_us) max_us = r.frame_us;
    }

    double med_us = median_of(frame_us, samples);
    double med_ns_node = median_of(ns_node, samples);
    printf("%s,%s,%u,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n",
           mode == RUN_REBUILD ? "rebuild" : "loaded",
           bc->name, node_count, loops, samples, first.validate_ms, first.load_ms,
           med_us, min_us, max_us, med_ns_node, first.ops_per_frame, first.events_per_frame);
    fflush(stdout);
    free(frame_us);
    free(ns_node);
}

static long parse_long_arg(char** argv, int argc, int index, long fallback)
{
    if (argc <= index) return fallback;
    char* end = NULL;
    errno = 0;
    long v = strtol(argv[index], &end, 10);
    if (errno == 0 && end && *end == '\0' && v > 0) return v;
    return fallback;
}

int main(int argc, char** argv)
{
    uint32_t node_count = (uint32_t)parse_long_arg(argv, argc, 1, 4096);
    int loops = (int)parse_long_arg(argv, argc, 2, 1000);
    int samples = (int)parse_long_arg(argv, argc, 3, 7);
    int warmup = (int)parse_long_arg(argv, argc, 4, 16);
    bench_run_mode mode = RUN_LOADED;
    if (argc >= 6 && strcmp(argv[5], "rebuild") == 0) {
        mode = RUN_REBUILD;
    }
    double env_w = 1280.0;
    double env_h = 720.0;

    static const bench_case cases[] = {
        {"chain_boxes", BENCH_CHAIN, RAW_NONE},
        {"flat_boxes", BENCH_FLAT, RAW_NONE},
        {"balanced_boxes", BENCH_BALANCED, RAW_NONE},
        {"interactive_wrappers", BENCH_INTERACTIVE, RAW_NONE},
        {"interactive_move", BENCH_INPUT, RAW_MOVE},
        {"interactive_click", BENCH_CLICK, RAW_CLICK}
    };

    printf("mode,scenario,nodes,loops,samples,validate_ms,load_ms,frame_us_median,frame_us_min,frame_us_max,ns_per_node_median,avg_view_ops,avg_events\n");
    fflush(stdout);
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        fprintf(stderr, "RUN %s nodes=%u loops=%d samples=%d\n", cases[i].name, node_count, loops, samples);
        fflush(stderr);
        run_case(&cases[i], node_count, loops, warmup, samples, env_w, env_h, mode);
    }
    return 0;
}
