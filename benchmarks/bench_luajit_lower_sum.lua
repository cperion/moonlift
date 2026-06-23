-- Benchmark MoonCode -> kernel facts -> MoonLuaJIT vector-reduce lowering.

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
local Lower = require("moonlift.luajit_lower")(T)
local Emit = require("moonlift.luajit_emit")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("MOONLIFT_LJ_LOWER_BENCH_N") or (full and "5000000" or "350000"))
local samples = tonumber(os.getenv("MOONLIFT_LJ_LOWER_BENCH_SAMPLES") or (full and "9" or "5"))
local rounds = tonumber(os.getenv("MOONLIFT_LJ_LOWER_BENCH_ROUNDS") or "1")
local cc = os.getenv("MOONLIFT_LJ_LOWER_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("MOONLIFT_LJ_LOWER_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local with_gcc = os.getenv("MOONLIFT_LJ_LOWER_BENCH_GCC") ~= "0"

local origin = Code.CodeOriginGenerated("bench_luajit_lower_sum")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function shell_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function build_module()
    local xs = param("xs", ptr_i32)
    local len = param("n", i32)
    local zero, one = Code.CodeValueId("v:zero"), Code.CodeValueId("v:one")
    local i, acc = Code.CodeValueId("v:i"), Code.CodeValueId("v:acc")
    local cond, item = Code.CodeValueId("v:cond"), Code.CodeValueId("v:item")
    local next_i, next_acc = Code.CodeValueId("v:next_i"), Code.CodeValueId("v:next_acc")
    local out = Code.CodeValueId("v:out")
    local entry_id, header_id = Code.CodeBlockId("block:entry"), Code.CodeBlockId("block:header")
    local body_id, exit_id = Code.CodeBlockId("block:body"), Code.CodeBlockId("block:exit")
    local sig_id, func_id = Code.CodeSigId("sig:sum_i32"), Code.CodeFuncId("fn:sum_i32")

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst("zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst("one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term("entry", Code.CodeTermJump(header_id, { zero, zero })), origin)
    local header = Code.CodeBlock(header_id, "header", {
        Code.CodeParam(i, "i", i32, origin),
        Code.CodeParam(acc, "acc", i32, origin),
    }, {
        inst("cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, len.value)),
    }, term("header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
    local body = Code.CodeBlock(body_id, "body", {}, {
        inst("load", Code.CodeInstLoad(item, Code.CodePlaceIndex(Code.CodePlaceDeref(xs.value, i32, 4), i, i32, 4), access)),
        inst("sum", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
        inst("inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    }, term("body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term("exit", Code.CodeTermReturn({ out })), origin)
    local func = Code.CodeFunc(func_id, "sum_i32", Code.CodeLinkageExport, sig_id, { xs, len }, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:bench_luajit_lower_sum"), { Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    local contracts = Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, len.value), origin),
    })
    return module, contracts
end

local module, contracts = build_module()
local rejects = {}
local lj_module = Lower.lower_module(module, { contracts = contracts, collect_rejects = rejects })
assert(#rejects == 0, rejects[1] and rejects[1].reason or "unexpected LuaJIT lower reject")
local compiled, err, src = Emit.compile_module(lj_module, { chunk_name = "bench_luajit_lower_sum" })
assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))

local xs = ffi.new("int32_t[?]", n)
for i = 0, n - 1 do xs[i] = bit.tobit(i * 17 + 11) end

local function lowered_sum() return compiled.sum_i32(xs, n) end
local function handwritten_sum()
    local acc = 0
    for i = 0, n - 1 do acc = bit.tobit(acc + xs[i]) end
    return acc
end
assert(lowered_sum() == handwritten_sum())

print(string.format("MoonCode -> LuaJIT lower sum benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
print("emitted source bytes " .. tostring(#src))
for _, result in ipairs(Measure.measure({
    { name = "lowered kernel sum_i32", fn = lowered_sum },
    { name = "handwritten sum_i32", fn = handwritten_sum },
}, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do print(Measure.format_result(result)) end

local function write_file(path, source_text)
    local f = assert(io.open(path, "wb"))
    f:write(source_text)
    f:close()
end

if with_gcc then
    os.execute("mkdir -p target/luajit_bench")
    local c_path = "target/luajit_bench/lower_sum_baseline.c"
    local exe_path = "target/luajit_bench/lower_sum_baseline"
    write_file(c_path, [[
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
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
    return 0;
}
]])
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

if os.getenv("MOONLIFT_LJ_LOWER_BENCH_SOURCE") == "1" then print(src) end
