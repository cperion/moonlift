-- Measure primitive LuaJIT lowering choices with real traces.
--
-- This is intentionally below the eventual LalinCode -> LuaJIT lowering:
-- candidates here model physical representation decisions and keep them
-- measurable before they become compiler defaults.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Measure = require("lalin.luajit_measure")

ffi.cdef [[
typedef struct lalin_lj_i32_view_bench {
    int32_t *data;
    intptr_t len;
    intptr_t stride;
} lalin_lj_i32_view_bench;
]]

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_LJ_BENCH_N") or (full and "2000000" or "350000"))
local samples = tonumber(os.getenv("LALIN_LJ_BENCH_SAMPLES") or (full and "11" or "5"))
local rounds = tonumber(os.getenv("LALIN_LJ_BENCH_ROUNDS") or "1")
local cc = os.getenv("LALIN_LJ_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("LALIN_LJ_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local with_gcc = os.getenv("LALIN_LJ_BENCH_GCC") ~= "0"

local i32_data = ffi.new("int32_t[?]", n)
for i = 0, n - 1 do
    i32_data[i] = bit.tobit(i * 17 + 11)
end

local view_struct = ffi.new("lalin_lj_i32_view_bench")
view_struct.data = i32_data
view_struct.len = n
view_struct.stride = 1

local u64 = ffi.typeof("uint64_t")
local u64_data = ffi.new("uint64_t[?]", n)
for i = 0, n - 1 do
    u64_data[i] = u64(i + 1)
end

local function i32_number_acc()
    local acc = 0
    for i = 0, n - 1 do
        acc = acc + i32_data[i]
    end
    return bit.tobit(acc)
end

local function i32_number_tobit_each_step()
    local acc = 0
    for i = 0, n - 1 do
        acc = bit.tobit(acc + i32_data[i])
    end
    return acc
end

local function i32_view_tuple_locals()
    local data = i32_data
    local len = n
    local stride = 1
    local acc = 0
    for i = 0, len - 1 do
        acc = acc + data[i * stride]
    end
    return bit.tobit(acc)
end

local function i32_view_cdata_struct()
    local view = view_struct
    local acc = 0
    for i = 0, tonumber(view.len) - 1 do
        acc = acc + view.data[i * tonumber(view.stride)]
    end
    return bit.tobit(acc)
end

local function u64_cdata_acc()
    local acc = u64(0)
    for i = 0, n - 1 do
        acc = acc + u64_data[i]
    end
    return tonumber(acc % u64(2147483647))
end

local function u64_low32_number_acc()
    local acc = 0
    for i = 0, n - 1 do
        acc = bit.tobit(acc + tonumber(u64_data[i] % u64(4294967296)))
    end
    return acc
end

local cases = {
    { name = "i32 number acc", fn = i32_number_acc },
    { name = "i32 tobit each step", fn = i32_number_tobit_each_step },
    { name = "view tuple locals", fn = i32_view_tuple_locals },
    { name = "view cdata struct", fn = i32_view_cdata_struct },
    { name = "u64 cdata acc", fn = u64_cdata_acc },
    { name = "u64 low32 number acc", fn = u64_low32_number_acc },
}

print(string.format("LuaJIT primitive lowering benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
print("jit opts: hotloop=3 hotexit=2")

local results = Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})

for i = 1, #results do
    print(Measure.format_result(results[i]))
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, source)
    local f = assert(io.open(path, "wb"))
    f:write(source)
    f:close()
end

local function c_source()
    return [[
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct lalin_lj_i32_view_bench {
    int32_t *data;
    intptr_t len;
    intptr_t stride;
} lalin_lj_i32_view_bench;

static double now_s(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
        return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
    }
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    return (da > db) - (da < db);
}

static double median(double *xs, int n) {
    qsort(xs, (size_t)n, sizeof(double), cmp_double);
    return xs[n / 2];
}

static int32_t double_to_i32_wrap(double value) {
    return (int32_t)(uint32_t)(uint64_t)value;
}

static int32_t c_i32_double_acc(const int32_t *data, int n) {
    double acc = 0.0;
    for (int i = 0; i < n; i++) acc += (double)data[i];
    return double_to_i32_wrap(acc);
}

static int32_t c_i32_wrap_each_step(const int32_t *data, int n) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) acc += (uint32_t)data[i];
    return (int32_t)acc;
}

static int32_t c_view_tuple_locals(const int32_t *data, int n) {
    intptr_t stride = 1;
    double acc = 0.0;
    for (int i = 0; i < n; i++) acc += (double)data[(intptr_t)i * stride];
    return double_to_i32_wrap(acc);
}

static int32_t c_view_struct(const lalin_lj_i32_view_bench *view) {
    double acc = 0.0;
    for (intptr_t i = 0; i < view->len; i++) acc += (double)view->data[i * view->stride];
    return double_to_i32_wrap(acc);
}

static uint64_t c_u64_acc(const uint64_t *data, int n) {
    uint64_t acc = 0;
    for (int i = 0; i < n; i++) acc += data[i];
    return acc % 2147483647ULL;
}

static int32_t c_u64_low32_acc(const uint64_t *data, int n) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) acc += (uint32_t)data[i];
    return (int32_t)acc;
}

typedef int64_t (*bench_fn)(void *);

typedef struct bench_case {
    const char *name;
    bench_fn fn;
    void *ctx;
} bench_case;

typedef struct bench_ctx {
    int n;
    int32_t *i32_data;
    uint64_t *u64_data;
    lalin_lj_i32_view_bench view;
} bench_ctx;

static int64_t run_i32_double(void *p) {
    bench_ctx *ctx = (bench_ctx *)p;
    return c_i32_double_acc(ctx->i32_data, ctx->n);
}

static int64_t run_i32_wrap(void *p) {
    bench_ctx *ctx = (bench_ctx *)p;
    return c_i32_wrap_each_step(ctx->i32_data, ctx->n);
}

static int64_t run_view_tuple(void *p) {
    bench_ctx *ctx = (bench_ctx *)p;
    return c_view_tuple_locals(ctx->i32_data, ctx->n);
}

static int64_t run_view_struct(void *p) {
    bench_ctx *ctx = (bench_ctx *)p;
    return c_view_struct(&ctx->view);
}

static int64_t run_u64_acc(void *p) {
    bench_ctx *ctx = (bench_ctx *)p;
    return (int64_t)c_u64_acc(ctx->u64_data, ctx->n);
}

static int64_t run_u64_low32(void *p) {
    bench_ctx *ctx = (bench_ctx *)p;
    return c_u64_low32_acc(ctx->u64_data, ctx->n);
}

static void measure_case(const bench_case *c, int samples, int rounds) {
    double *times = (double *)calloc((size_t)samples, sizeof(double));
    if (!times) abort();
    int64_t first = 0;
    for (int s = 0; s < samples; s++) {
        double t0 = now_s();
        int64_t value = 0;
        for (int r = 0; r < rounds; r++) value = c->fn(c->ctx);
        times[s] = now_s() - t0;
        if (s == 0) first = value;
        if (value != first) {
            fprintf(stderr, "unstable C benchmark result for %s\n", c->name);
            exit(2);
        }
    }
    double med = median(times, samples);
    printf("%-28s median=%8.3fms result=%lld\n", c->name, med * 1000.0, (long long)first);
    free(times);
}

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 350000;
    int samples = argc > 2 ? atoi(argv[2]) : 5;
    int rounds = argc > 3 ? atoi(argv[3]) : 1;

    bench_ctx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.n = n;
    ctx.i32_data = (int32_t *)calloc((size_t)n, sizeof(int32_t));
    ctx.u64_data = (uint64_t *)calloc((size_t)n, sizeof(uint64_t));
    if (!ctx.i32_data || !ctx.u64_data) abort();

    for (int i = 0; i < n; i++) {
        ctx.i32_data[i] = (int32_t)(i * 17 + 11);
        ctx.u64_data[i] = (uint64_t)i + 1ULL;
    }
    ctx.view.data = ctx.i32_data;
    ctx.view.len = n;
    ctx.view.stride = 1;

    bench_case cases[] = {
        { "gcc i32 double acc", run_i32_double, &ctx },
        { "gcc i32 wrap each step", run_i32_wrap, &ctx },
        { "gcc view tuple locals", run_view_tuple, &ctx },
        { "gcc view c struct", run_view_struct, &ctx },
        { "gcc u64 acc", run_u64_acc, &ctx },
        { "gcc u64 low32 acc", run_u64_low32, &ctx },
    };

    printf("GCC primitive baseline n=%d samples=%d rounds=%d\n", n, samples, rounds);
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        measure_case(&cases[i], samples, rounds);
    }

    free(ctx.i32_data);
    free(ctx.u64_data);
    return 0;
}
]]
end

local function run_gcc_baseline()
    os.execute("mkdir -p target/luajit_bench")
    local src = "target/luajit_bench/primitive_baseline.c"
    local exe = "target/luajit_bench/primitive_baseline"
    write_file(src, c_source())
    local cmd = table.concat({
        shell_quote(cc),
        cflags,
        shell_quote(src),
        "-o",
        shell_quote(exe),
    }, " ")
    local ok = os.execute(cmd)
    if ok ~= true and ok ~= 0 then
        io.stderr:write("skipping GCC baseline; compile failed: " .. cmd .. "\n")
        return
    end
    local run = table.concat({ shell_quote(exe), tostring(n), tostring(samples), tostring(rounds) }, " ")
    local pipe = io.popen(run, "r")
    if pipe == nil then
        io.stderr:write("skipping GCC baseline; could not run " .. exe .. "\n")
        return
    end
    local out = pipe:read("*a")
    pipe:close()
    io.write("\n")
    io.write("GCC command: " .. cmd .. "\n")
    io.write(out)
end

if with_gcc then
    run_gcc_baseline()
end
