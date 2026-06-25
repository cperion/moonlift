-- Benchmark the LuaJIT C stencil vocabulary against direct GCC loops.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Measure = require("lalin.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Stencil = T.LalinStencil
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBank = require("lalin.stencil_bank")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_LJ_STENCIL_BENCH_N") or (full and "1000000" or "120000"))
local samples = tonumber(os.getenv("LALIN_LJ_STENCIL_BENCH_SAMPLES") or (full and "5" or "3"))
local rounds = tonumber(os.getenv("LALIN_LJ_STENCIL_BENCH_ROUNDS") or (full and "3" or "2"))
local cc = os.getenv("LALIN_LJ_STENCIL_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("LALIN_LJ_STENCIL_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local with_gcc = os.getenv("LALIN_LJ_STENCIL_BENCH_GCC") ~= "0"

local function stencil_object_cflags()
    return cflags .. " -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
end

local function compile_artifacts(artifacts, opts)
    opts = opts or {}
    opts.cc = opts.cc or cc
    opts.cflags = opts.cflags or stencil_object_cflags()
    local bank, bank_err, source = StencilBank.build_binary_bank(artifacts, opts)
    if bank == nil then return nil, bank_err, source end
    local realization, realize_err = StencilBank.realize_binary_artifacts(artifacts, {
        bank = bank,
        preamble = opts.preamble,
        ffi_preamble = opts.ffi_preamble,
        patch_values = opts.patch_values,
    })
    if realization == nil then return nil, realize_err, source end
    return { kind = "BinaryStencilBenchmarkBuild", bank = bank, realization = realization, symbols = realization.symbols, source = source }, nil, source
end

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function reduction(kind, init)
    return {
        kind = kind,
        init = iconst(init),
        int_semantics = sem,
        float_mode = nil,
    }
end

local reduce_add = reduction(Value.ReductionAdd, 0)
local gt0 = Stencil.StencilPredGtConst(iconst(0))
local artifacts = {
    reduce_array = StencilArtifactPlan.reduce_array_artifact(reduce_add, nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    map_array = StencilArtifactPlan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    zip_map_array = StencilArtifactPlan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1 }),
    scan_array = StencilArtifactPlan.scan_array_artifact(reduce_add, nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    copy_array = StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, step_num = 1 }),
    copy_array_memmove = StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    fill_array = StencilArtifactPlan.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1 }),
    find_array = StencilArtifactPlan.find_array_artifact(gt0, { elem_ty = i32, step_num = 1 }),
    partition_array = StencilArtifactPlan.partition_array_artifact(gt0, { elem_ty = i32, step_num = 1 }),
    cast_array = StencilArtifactPlan.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1 }),
    compare_array = StencilArtifactPlan.compare_array_artifact(gt0, { elem_ty = i32, result_ty = bool8, step_num = 1 }),
    zip_compare_array = StencilArtifactPlan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1 }),
    gather_array = StencilArtifactPlan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1 }),
    scatter_array = StencilArtifactPlan.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    in_place_map_array = StencilArtifactPlan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1 }),
    count_array = StencilArtifactPlan.count_array_artifact(gt0, { elem_ty = i32, step_num = 1 }),
    map_reduce_array = StencilArtifactPlan.map_reduce_array_artifact(Stencil.StencilUnaryNeg, reduce_add, nil, { elem_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1 }),
    zip_reduce_array = StencilArtifactPlan.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduce_add, nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1 }),
}

local artifact_list = {}
for _, artifact in pairs(artifacts) do artifact_list[#artifact_list + 1] = artifact end

local build, err, src = compile_artifacts(artifact_list, {
    stem = "bench_luajit_stencil_matrix",
    cc = cc,
    cflags = stencil_object_cflags(),
})
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))

local function sym(name)
    local artifact = assert(artifacts[name], name)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

local xs = ffi.new("int32_t[?]", n)
local ys = ffi.new("int32_t[?]", n)
local out = ffi.new("int32_t[?]", n)
local aux = ffi.new("int32_t[?]", n + 1)
local idx = ffi.new("int32_t[?]", n)
local mask = ffi.new("uint8_t[?]", n)
local dout = ffi.new("double[?]", n)

for i = 0, n - 1 do
    xs[i] = (i % 97) - 48
    ys[i] = (i % 53) + 3
    out[i] = 0
    aux[i] = xs[i]
    idx[i] = n - 1 - i
    mask[i] = 0
    dout[i] = 0
end
aux[n] = 0

local mid = math.floor(n / 2)
local cases = {
    { name = "stencil reduce_array", fn = function() return sym("reduce_array")(xs, 0, n, 0) end },
    { name = "stencil map_array", fn = function() sym("map_array")(out, xs, 0, n); return out[mid] end },
    { name = "stencil zip_map_array", fn = function() sym("zip_map_array")(out, xs, ys, 0, n); return out[mid] end },
    { name = "stencil scan_array", fn = function() return sym("scan_array")(out, xs, 0, n, 0) end },
    { name = "stencil copy_array", fn = function() sym("copy_array")(out, xs, 0, n); return out[mid] end },
    { name = "stencil copy_array_memmove", fn = function() sym("copy_array_memmove")(out, xs, 0, n); return out[mid] end },
    { name = "stencil fill_array", fn = function() sym("fill_array")(out, 0, n, 7); return out[mid] end },
    { name = "stencil find_array", fn = function() return sym("find_array")(xs, 0, n) end },
    { name = "stencil partition_array", fn = function() return sym("partition_array")(out, xs, 0, n) end },
    { name = "stencil cast_array", fn = function() sym("cast_array")(dout, xs, 0, n); return dout[mid] end },
    { name = "stencil compare_array", fn = function() sym("compare_array")(mask, xs, 0, n); return mask[mid] end },
    { name = "stencil zip_compare_array", fn = function() sym("zip_compare_array")(mask, xs, ys, 0, n); return mask[mid] end },
    { name = "stencil gather_array", fn = function() sym("gather_array")(out, xs, idx, 0, n); return out[mid] end },
    { name = "stencil scatter_array", fn = function() sym("scatter_array")(out, xs, idx, 0, n); return out[mid] end },
    { name = "stencil in_place_map_array", fn = function() sym("in_place_map_array")(aux, 0, n); sym("in_place_map_array")(aux, 0, n); return aux[mid] end },
    { name = "stencil count_array", fn = function() return sym("count_array")(xs, 0, n) end },
    { name = "stencil map_reduce_array", fn = function() return sym("map_reduce_array")(xs, 0, n, 0) end },
    { name = "stencil zip_reduce_array", fn = function() return sym("zip_reduce_array")(xs, ys, 0, n, 0) end },
}

print(string.format("LuaJIT C stencil vocabulary benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
for _, result in ipairs(Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do print(Measure.format_result(result)) end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, source_text)
    local f = assert(io.open(path, "wb"))
    f:write(source_text)
    f:close()
end

if with_gcc then
    os.execute("mkdir -p target/luajit_bench")
    local c_path = "target/luajit_bench/stencil_matrix_baseline.c"
    local exe_path = "target/luajit_bench/stencil_matrix_baseline"
    local c = {}
    c[#c + 1] = [=[
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_s(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da > db) - (da < db);
}

static int32_t reduce_array(const int32_t *xs, int n) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) acc = (uint32_t)(acc + (uint32_t)xs[i]);
    return (int32_t)acc;
}

static int32_t map_array(int32_t *out, const int32_t *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = -xs[i];
    return out[mid];
}

static int32_t zip_map_array(int32_t *out, const int32_t *xs, const int32_t *ys, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = (int32_t)((uint32_t)xs[i] + (uint32_t)ys[i]);
    return out[mid];
}

static int32_t scan_array(int32_t *out, const int32_t *xs, int n) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) { acc = (uint32_t)(acc + (uint32_t)xs[i]); out[i] = (int32_t)acc; }
    return (int32_t)acc;
}

static int32_t copy_array(int32_t *out, const int32_t *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid];
}

static int32_t copy_array_memmove(int32_t *out, const int32_t *xs, int n, int mid) {
    if (n > 0) memmove(out, xs, (size_t)n * sizeof(int32_t));
    return out[mid];
}

static int32_t fill_array(int32_t *out, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = 7;
    return out[mid];
}

static int32_t find_array(const int32_t *xs, int n) {
    for (int i = 0; i < n; i++) if (xs[i] > 0) return i;
    return -1;
}

static int32_t partition_array(int32_t *out, const int32_t *xs, int n) {
    int32_t o = 0;
    for (int i = 0; i < n; i++) if (xs[i] > 0) out[o++] = xs[i];
    int32_t split = o;
    for (int i = 0; i < n; i++) if (!(xs[i] > 0)) out[o++] = xs[i];
    return split;
}

static double cast_array(double *out, const int32_t *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = (double)xs[i];
    return out[mid];
}

static int32_t compare_array(uint8_t *mask, const int32_t *xs, int n, int mid) {
    for (int i = 0; i < n; i++) mask[i] = xs[i] > 0 ? 1 : 0;
    return mask[mid];
}

static int32_t zip_compare_array(uint8_t *mask, const int32_t *xs, const int32_t *ys, int n, int mid) {
    for (int i = 0; i < n; i++) mask[i] = xs[i] < ys[i] ? 1 : 0;
    return mask[mid];
}

static int32_t gather_array(int32_t *out, const int32_t *xs, const int32_t *idx, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[idx[i]];
    return out[mid];
}

static int32_t scatter_array(int32_t *out, const int32_t *xs, const int32_t *idx, int n, int mid) {
    for (int i = 0; i < n; i++) out[idx[i]] = xs[i];
    return out[mid];
}

static int32_t in_place_map_array(int32_t *aux, int n, int mid) {
    for (int i = 0; i < n; i++) aux[i] = -aux[i];
    return aux[mid];
}

static int32_t count_array(const int32_t *xs, int n) {
    int32_t count = 0;
    for (int i = 0; i < n; i++) if (xs[i] > 0) count++;
    return count;
}

static int32_t map_reduce_array(const int32_t *xs, int n) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) acc = (uint32_t)(acc + (uint32_t)(-xs[i]));
    return (int32_t)acc;
}

static int32_t zip_reduce_array(const int32_t *xs, const int32_t *ys, int n) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) acc = (uint32_t)(acc + (uint32_t)((uint32_t)xs[i] + (uint32_t)ys[i]));
    return (int32_t)acc;
}

typedef struct BenchCase BenchCase;
typedef union BenchValue BenchValue;
union BenchValue {
    int32_t i;
    double f;
};
struct BenchCase {
    const char *name;
    double is_float;
    BenchValue (*run)(int32_t *, int32_t *, int32_t *, int32_t *, uint8_t *, double *, int, int);
};

static BenchValue run_reduce(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)out; (void)idx; (void)mask; (void)dout; (void)mid; r.i = reduce_array(xs, n); return r; }
static BenchValue run_map(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)idx; (void)mask; (void)dout; r.i = map_array(out, xs, n, mid); return r; }
static BenchValue run_zip_map(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)idx; (void)mask; (void)dout; r.i = zip_map_array(out, xs, ys, n, mid); return r; }
static BenchValue run_scan(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)idx; (void)mask; (void)dout; (void)mid; r.i = scan_array(out, xs, n); return r; }
static BenchValue run_copy(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)idx; (void)mask; (void)dout; r.i = copy_array(out, xs, n, mid); return r; }
static BenchValue run_memmove(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)idx; (void)mask; (void)dout; r.i = copy_array_memmove(out, xs, n, mid); return r; }
static BenchValue run_fill(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)xs; (void)ys; (void)idx; (void)mask; (void)dout; r.i = fill_array(out, n, mid); return r; }
static BenchValue run_find(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)out; (void)idx; (void)mask; (void)dout; (void)mid; r.i = find_array(xs, n); return r; }
static BenchValue run_partition(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)idx; (void)mask; (void)dout; (void)mid; r.i = partition_array(out, xs, n); return r; }
static BenchValue run_cast(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)out; (void)idx; (void)mask; r.f = cast_array(dout, xs, n, mid); return r; }
static BenchValue run_compare(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)out; (void)idx; (void)dout; r.i = compare_array(mask, xs, n, mid); return r; }
static BenchValue run_zip_compare(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)out; (void)idx; (void)dout; r.i = zip_compare_array(mask, xs, ys, n, mid); return r; }
static BenchValue run_gather(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)mask; (void)dout; r.i = gather_array(out, xs, idx, n, mid); return r; }
static BenchValue run_scatter(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)mask; (void)dout; r.i = scatter_array(out, xs, idx, n, mid); return r; }
static BenchValue run_in_place(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)out; (void)idx; (void)mask; (void)dout; in_place_map_array(xs, n, mid); r.i = in_place_map_array(xs, n, mid); return r; }
static BenchValue run_count(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)out; (void)idx; (void)mask; (void)dout; (void)mid; r.i = count_array(xs, n); return r; }
static BenchValue run_map_reduce(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)ys; (void)out; (void)idx; (void)mask; (void)dout; (void)mid; r.i = map_reduce_array(xs, n); return r; }
static BenchValue run_zip_reduce(int32_t *xs, int32_t *ys, int32_t *out, int32_t *idx, uint8_t *mask, double *dout, int n, int mid) { BenchValue r; (void)out; (void)idx; (void)mask; (void)dout; (void)mid; r.i = zip_reduce_array(xs, ys, n); return r; }
]=]
    c[#c + 1] = [=[
int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 120000;
    int samples = argc > 2 ? atoi(argv[2]) : 3;
    int rounds = argc > 3 ? atoi(argv[3]) : 2;
    int mid = n / 2;
    int32_t *xs = (int32_t *)calloc((size_t)n + 1, sizeof(int32_t));
    int32_t *ys = (int32_t *)calloc((size_t)n, sizeof(int32_t));
    int32_t *out = (int32_t *)calloc((size_t)n, sizeof(int32_t));
    int32_t *idx = (int32_t *)calloc((size_t)n, sizeof(int32_t));
    uint8_t *mask = (uint8_t *)calloc((size_t)n, sizeof(uint8_t));
    double *dout = (double *)calloc((size_t)n, sizeof(double));
    double *times = (double *)calloc((size_t)samples, sizeof(double));
    if (!xs || !ys || !out || !idx || !mask || !dout || !times) abort();
    for (int i = 0; i < n; i++) {
        xs[i] = (int32_t)((i % 97) - 48);
        ys[i] = (int32_t)((i % 53) + 3);
        idx[i] = n - 1 - i;
    }
    BenchCase cases[] = {
        { "gcc reduce_array", 0, run_reduce },
        { "gcc map_array", 0, run_map },
        { "gcc zip_map_array", 0, run_zip_map },
        { "gcc scan_array", 0, run_scan },
        { "gcc copy_array", 0, run_copy },
        { "gcc copy_array_memmove", 0, run_memmove },
        { "gcc fill_array", 0, run_fill },
        { "gcc find_array", 0, run_find },
        { "gcc partition_array", 0, run_partition },
        { "gcc cast_array", 1, run_cast },
        { "gcc compare_array", 0, run_compare },
        { "gcc zip_compare_array", 0, run_zip_compare },
        { "gcc gather_array", 0, run_gather },
        { "gcc scatter_array", 0, run_scatter },
        { "gcc in_place_map_array", 0, run_in_place },
        { "gcc count_array", 0, run_count },
        { "gcc map_reduce_array", 0, run_map_reduce },
        { "gcc zip_reduce_array", 0, run_zip_reduce },
    };
    int case_count = (int)(sizeof(cases) / sizeof(cases[0]));
    for (int ci = 0; ci < case_count; ci++) {
        BenchValue first = { 0 };
        for (int s = 0; s < samples; s++) {
            BenchValue value = { 0 };
            double t0 = now_s();
            for (int r = 0; r < rounds; r++) value = cases[ci].run(xs, ys, out, idx, mask, dout, n, mid);
            times[s] = now_s() - t0;
            if (s == 0) first = value;
            if ((!cases[ci].is_float && value.i != first.i) || (cases[ci].is_float && value.f != first.f)) abort();
        }
        qsort(times, (size_t)samples, sizeof(double), cmp_double);
        if (cases[ci].is_float) {
            printf("%-28s median=%8.3fms result=%.9g\n", cases[ci].name, times[samples / 2] * 1000.0, first.f);
        } else {
            printf("%-28s median=%8.3fms result=%lld\n", cases[ci].name, times[samples / 2] * 1000.0, (long long)first.i);
        }
    }
    return 0;
}
]=]
    write_file(c_path, table.concat(c, "\n"))
    local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(exe_path) }, " ")
    local ok = os.execute(cmd)
    if ok == true or ok == 0 then
        local pipe = io.popen(table.concat({ shell_quote(exe_path), tostring(n), tostring(samples), tostring(rounds) }, " "), "r")
        if pipe ~= nil then
            io.write("\nGCC command: " .. cmd .. "\n")
            io.write(pipe:read("*a"))
            pipe:close()
        end
    else
        io.stderr:write("skipping GCC baseline; compile failed: " .. cmd .. "\n")
    end
end
