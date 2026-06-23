-- Benchmark explicit MoonLuaJIT vector-reduce semantics.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Measure = require("moonlift.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local LJ = T.MoonLuaJIT
local Value = T.MoonValue
local CType = require("moonlift.luajit_ctype")(T)
local Emit = require("moonlift.luajit_emit")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("MOONLIFT_LJ_VEC_BENCH_N") or (full and "5000000" or "350000"))
local samples = tonumber(os.getenv("MOONLIFT_LJ_VEC_BENCH_SAMPLES") or (full and "9" or "5"))
local rounds = tonumber(os.getenv("MOONLIFT_LJ_VEC_BENCH_ROUNDS") or "1")
local cc = os.getenv("MOONLIFT_LJ_VEC_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("MOONLIFT_LJ_VEC_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local with_gcc = os.getenv("MOONLIFT_LJ_VEC_BENCH_GCC") ~= "0"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, source_text)
    local f = assert(io.open(path, "wb"))
    f:write(source_text)
    f:close()
end

local function helper_source()
    return [[
#include <stdint.h>

int32_t ml_lj_sum_i32_vec(const int32_t *xs, int32_t n) {
    uint32_t acc = 0;
    for (int32_t i = 0; i < n; i++) acc += (uint32_t)xs[i];
    return (int32_t)acc;
}
]]
end

local function baseline_source()
    return [[
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

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

static int32_t sum_i32(const int32_t *xs, int n) {
    uint32_t acc = 0;
    for (int i = 0; i < n; i++) acc += (uint32_t)xs[i];
    return (int32_t)acc;
}

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 350000;
    int samples = argc > 2 ? atoi(argv[2]) : 5;
    int rounds = argc > 3 ? atoi(argv[3]) : 1;
    int32_t *xs = (int32_t *)calloc((size_t)n, sizeof(int32_t));
    double *times = (double *)calloc((size_t)samples, sizeof(double));
    if (!xs || !times) abort();
    for (int i = 0; i < n; i++) xs[i] = (int32_t)(i * 17 + 11);
    int32_t first = 0;
    for (int s = 0; s < samples; s++) {
        double t0 = now_s();
        int32_t value = 0;
        for (int r = 0; r < rounds; r++) value = sum_i32(xs, n);
        times[s] = now_s() - t0;
        if (s == 0) first = value;
        if (value != first) abort();
    }
    qsort(times, (size_t)samples, sizeof(double), cmp_double);
    printf("%-28s median=%8.3fms result=%d\n", "gcc sum_i32", times[samples / 2] * 1000.0, first);
    free(times);
    free(xs);
    return 0;
}
]]
end

local function compile_c_artifacts()
    os.execute("mkdir -p target/luajit_bench")
    local helper_c = "target/luajit_bench/vector_reduce_helper.c"
    local helper_so = "target/luajit_bench/vector_reduce_helper.so"
    local baseline_c = "target/luajit_bench/vector_reduce_baseline.c"
    local baseline_exe = "target/luajit_bench/vector_reduce_baseline"
    write_file(helper_c, helper_source())
    write_file(baseline_c, baseline_source())
    local shared_cmd = table.concat({ shell_quote(cc), cflags, "-fPIC -shared", shell_quote(helper_c), "-o", shell_quote(helper_so) }, " ")
    local baseline_cmd = table.concat({ shell_quote(cc), cflags, shell_quote(baseline_c), "-o", shell_quote(baseline_exe) }, " ")
    local shared_ok = os.execute(shared_cmd)
    local baseline_ok = os.execute(baseline_cmd)
    return {
        helper_so = helper_so,
        baseline_exe = baseline_exe,
        shared_cmd = shared_cmd,
        baseline_cmd = baseline_cmd,
        shared_ok = shared_ok == true or shared_ok == 0,
        baseline_ok = baseline_ok == true or baseline_ok == 0,
    }
end

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local i32_phys = CType.physical_type(i32, {})
local ptr_i32_phys = CType.physical_type(Code.CodeTyDataPtr(i32), {})

local xs_id = LJ.LJValueId("xs")
local n_id = LJ.LJValueId("n")
local item_id = LJ.LJValueId("item")
local acc_id = LJ.LJValueId("acc")
local source_id = LJ.LJMachineId("source")
local fold_id = LJ.LJMachineId("fold")
local vec_id = LJ.LJMachineId("vec")
local native_id = LJ.LJMachineId("native_vec")
local helper_id = LJ.LJHelperId("helper:sum_i32_vec")
local zero = LJ.LJExprLiteral(Core.LitInt("0"), i32_phys)

local function params()
    return {
        LJ.LJParam(xs_id, "xs", ptr_i32_phys),
        LJ.LJParam(n_id, "n", i32_phys),
    }
end

local function scalar_fold_func()
    local source = LJ.LJMachine(
        source_id,
        LJ.LJMachineSourceArray(xs_id, i32_phys, LJ.LJExprValue(n_id)),
        i32_phys,
        LJ.LJStateScalar,
        LJ.LJTraceHot
    )
    local step = LJ.LJExprIntBinary(Core.BinAdd, i32_phys, sem, LJ.LJExprValue(acc_id), LJ.LJExprValue(item_id))
    local fold = LJ.LJMachine(
        fold_id,
        LJ.LJMachineFold(source_id, acc_id, item_id, zero, step),
        i32_phys,
        LJ.LJStateScalar,
        LJ.LJTraceHot
    )
    return LJ.LJFunc(
        LJ.LJFuncId("sum_i32_fold"),
        nil,
        "sum_i32_fold",
        LJ.LJFuncSigId("sig:sum_i32_fold"),
        params(),
        {},
        { source, fold },
        LJ.LJBodyMachine(fold_id, LJ.LJTerminalFirst(nil)),
        LJ.LJTraceHot
    )
end

local function vector_func(name, machine_id, helper)
    local vec = LJ.LJMachine(
        machine_id,
        LJ.LJMachineVectorReduceArray(xs_id, zero, LJ.LJExprValue(n_id), LJ.LJExprLiteral(Core.LitInt("1"), i32_phys), i32_phys, i32_phys, Value.ReductionAdd, sem, zero, 8, 1, helper),
        i32_phys,
        LJ.LJStateScalar,
        LJ.LJTraceHot
    )
    return LJ.LJFunc(
        LJ.LJFuncId(name),
        nil,
        name,
        LJ.LJFuncSigId("sig:" .. name),
        params(),
        {},
        { vec },
        LJ.LJBodyMachine(machine_id, LJ.LJTerminalFirst(nil)),
        LJ.LJTraceHot
    )
end

local artifacts = with_gcc and compile_c_artifacts() or nil
local native_helpers = {}
if artifacts and artifacts.shared_ok then
    ffi.cdef("int32_t ml_lj_sum_i32_vec(const int32_t *xs, int32_t n);")
    native_helpers[helper_id.text] = ffi.load(artifacts.helper_so).ml_lj_sum_i32_vec
end

local funcs = {
    scalar_fold_func(),
    vector_func("sum_i32_vec_fallback", vec_id, nil),
}
if native_helpers[helper_id.text] ~= nil then
    funcs[#funcs + 1] = vector_func("sum_i32_vec_native", native_id, helper_id)
end

local compiled, err, src = Emit.compile_module(LJ.LJModule(nil, funcs, {}, {}, {}), {
    chunk_name = "bench_luajit_vector_reduce",
    native_helpers = native_helpers,
})
assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))

local xs = ffi.new("int32_t[?]", n)
for i = 0, n - 1 do xs[i] = bit.tobit(i * 17 + 11) end

local function handwritten_sum()
    local acc = 0
    for i = 0, n - 1 do
        acc = bit.tobit(acc + xs[i])
    end
    return acc
end

local expected = handwritten_sum()
assert(compiled.sum_i32_fold(xs, n) == expected)
assert(compiled.sum_i32_vec_fallback(xs, n) == expected)
if compiled.sum_i32_vec_native then assert(compiled.sum_i32_vec_native(xs, n) == expected) end

print(string.format("MoonLuaJIT vector reduce benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
print("emitted source bytes " .. tostring(#src))
local cases = {
    { name = "emitted fold i32", fn = function() return compiled.sum_i32_fold(xs, n) end },
    { name = "vector fallback i32", fn = function() return compiled.sum_i32_vec_fallback(xs, n) end },
    { name = "handwritten i32", fn = handwritten_sum },
}
if compiled.sum_i32_vec_native then
    cases[#cases + 1] = { name = "vector native i32", fn = function() return compiled.sum_i32_vec_native(xs, n) end }
else
    io.stderr:write("skipping native helper; shared helper compile failed\n")
end

local results = Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})
for i = 1, #results do print(Measure.format_result(results[i])) end

if artifacts and artifacts.baseline_ok then
    local pipe = io.popen(table.concat({ shell_quote(artifacts.baseline_exe), tostring(n), tostring(samples), tostring(rounds) }, " "), "r")
    if pipe ~= nil then
        io.write("\nGCC shared helper command: " .. artifacts.shared_cmd .. "\n")
        io.write("GCC baseline command: " .. artifacts.baseline_cmd .. "\n")
        io.write(pipe:read("*a"))
        pipe:close()
    end
elseif artifacts then
    io.stderr:write("skipping GCC baseline; compile failed: " .. artifacts.baseline_cmd .. "\n")
end

if os.getenv("MOONLIFT_LJ_VEC_BENCH_SOURCE") == "1" then
    print(src)
end
