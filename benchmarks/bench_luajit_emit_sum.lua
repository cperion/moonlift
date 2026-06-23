-- Benchmark emitted MoonLuaJIT ASDL against hand-written LuaJIT and GCC.

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
local CType = require("moonlift.luajit_ctype")(T)
local Expr = require("moonlift.luajit_expr")(T)
local Emit = require("moonlift.luajit_emit")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("MOONLIFT_LJ_EMIT_BENCH_N") or (full and "5000000" or "350000"))
local samples = tonumber(os.getenv("MOONLIFT_LJ_EMIT_BENCH_SAMPLES") or (full and "9" or "5"))
local rounds = tonumber(os.getenv("MOONLIFT_LJ_EMIT_BENCH_ROUNDS") or "1")
local cc = os.getenv("MOONLIFT_LJ_EMIT_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("MOONLIFT_LJ_EMIT_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local with_gcc = os.getenv("MOONLIFT_LJ_EMIT_BENCH_GCC") ~= "0"

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

local source = LJ.LJMachine(
    source_id,
    LJ.LJMachineSourceArray(xs_id, i32_phys, LJ.LJExprValue(n_id)),
    i32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local code_acc = Code.CodeValueId(acc_id.text)
local code_item = Code.CodeValueId(item_id.text)
local lower_ctx = {
    value_types = {
        [code_acc.text] = i32,
        [code_item.text] = i32,
    },
}
local step = Expr.inst_expr(lower_ctx, Code.CodeInstBinary(Code.CodeValueId("sum"), Core.BinAdd, i32, sem, code_acc, code_item))
local fold = LJ.LJMachine(
    fold_id,
    LJ.LJMachineFold(source_id, acc_id, item_id, LJ.LJExprLiteral(Core.LitInt("0"), i32_phys), step),
    i32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local fn = LJ.LJFunc(
    LJ.LJFuncId("sum_i32"),
    nil,
    "sum_i32",
    LJ.LJFuncSigId("sig:sum_i32"),
    {
        LJ.LJParam(xs_id, "xs", ptr_i32_phys),
        LJ.LJParam(n_id, "n", i32_phys),
    },
    {},
    { source, fold },
    LJ.LJBodyMachine(fold_id, LJ.LJTerminalFirst(nil)),
    LJ.LJTraceHot
)
local compiled, err, src = Emit.compile_module(LJ.LJModule(nil, { fn }, {}, {}, {}), {
    chunk_name = "bench_luajit_emit_sum",
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

local function emitted_sum()
    return compiled.sum_i32(xs, n)
end

assert(emitted_sum() == handwritten_sum())

print(string.format("MoonLuaJIT emitted sum benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
print("emitted source bytes " .. tostring(#src))
local results = Measure.measure({
    { name = "emitted LJ sum_i32", fn = emitted_sum },
    { name = "handwritten sum_i32", fn = handwritten_sum },
}, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})
for i = 1, #results do print(Measure.format_result(results[i])) end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, source_text)
    local f = assert(io.open(path, "wb"))
    f:write(source_text)
    f:close()
end

local function c_source()
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

local function run_gcc()
    os.execute("mkdir -p target/luajit_bench")
    local src_path = "target/luajit_bench/emit_sum_baseline.c"
    local exe_path = "target/luajit_bench/emit_sum_baseline"
    write_file(src_path, c_source())
    local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(src_path), "-o", shell_quote(exe_path) }, " ")
    local ok = os.execute(cmd)
    if ok ~= true and ok ~= 0 then
        io.stderr:write("skipping GCC baseline; compile failed: " .. cmd .. "\n")
        return
    end
    local pipe = io.popen(table.concat({ shell_quote(exe_path), tostring(n), tostring(samples), tostring(rounds) }, " "), "r")
    if pipe == nil then return end
    io.write("\nGCC command: " .. cmd .. "\n")
    io.write(pipe:read("*a"))
    pipe:close()
end

if with_gcc then run_gcc() end

if os.getenv("MOONLIFT_LJ_EMIT_BENCH_SOURCE") == "1" then
    print(src)
end
