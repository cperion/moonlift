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
local Value = T.MoonValue
local Lower = require("moonlift.luajit_lower")(T)
local Emit = require("moonlift.luajit_emit")(T)
local StencilC = require("moonlift.stencil_c")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("MOONLIFT_LJ_REDUCE_BENCH_N") or (full and "1000000" or "120000"))
local samples = tonumber(os.getenv("MOONLIFT_LJ_REDUCE_BENCH_SAMPLES") or (full and "5" or "3"))
local rounds = tonumber(os.getenv("MOONLIFT_LJ_REDUCE_BENCH_ROUNDS") or (full and "2" or "1"))
local cc = os.getenv("MOONLIFT_LJ_REDUCE_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("MOONLIFT_LJ_REDUCE_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local with_gcc = os.getenv("MOONLIFT_LJ_REDUCE_BENCH_GCC") ~= "0"

local origin = Code.CodeOriginGenerated("bench_luajit_lower_reductions")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local type_cases = {
    { suffix = "i8", bits = 8, signed = true, ctype = "int8_t", fill = "(i * 17 + 11) & 255" },
    { suffix = "u8", bits = 8, signed = false, ctype = "uint8_t", fill = "(i * 17 + 11) & 255" },
    { suffix = "i16", bits = 16, signed = true, ctype = "int16_t", fill = "(i * 17 + 11) & 65535" },
    { suffix = "u16", bits = 16, signed = false, ctype = "uint16_t", fill = "(i * 17 + 11) & 65535" },
    { suffix = "i32", bits = 32, signed = true, ctype = "int32_t", fill = "i * 17 + 11" },
    { suffix = "u32", bits = 32, signed = false, ctype = "uint32_t", fill = "i * 17u + 11u" },
    { suffix = "i64", bits = 64, signed = true, ctype = "int64_t", fill = "i * 17 + 11" },
    { suffix = "u64", bits = 64, signed = false, ctype = "uint64_t", fill = "i * 17ull + 11ull" },
    { suffix = "f32", bits = 32, signed = true, float = true, ctype = "float", fill = "((float)((i % 97) - 48) * 0.25f)" },
    { suffix = "f64", bits = 64, signed = true, float = true, ctype = "double", fill = "((double)((i % 97) - 48) * 0.25)" },
}

local reductions = {
    { suffix = "add", reduction = Value.ReductionAdd, op = Core.BinAdd, init = "0", cinit = "0", cop = "add" },
    { suffix = "mul", reduction = Value.ReductionMul, op = Core.BinMul, init = "1", cinit = "1", cop = "mul" },
    { suffix = "and", reduction = Value.ReductionAnd, op = Core.BinBitAnd, init = "-1", cinit = "~0u", cop = "and" },
    { suffix = "or", reduction = Value.ReductionOr, op = Core.BinBitOr, init = "0", cinit = "0", cop = "or" },
    { suffix = "xor", reduction = Value.ReductionXor, op = Core.BinBitXor, init = "0", cinit = "0", cop = "xor" },
    { suffix = "min", reduction = Value.ReductionMin, cop = "min" },
    { suffix = "max", reduction = Value.ReductionMax, cop = "max" },
}

local function min_init(t)
    if t.float then return "1.0e30" end
    if t.signed then
        if t.bits == 8 then return "127" end
        if t.bits == 16 then return "32767" end
        if t.bits == 64 then return "9223372036854775807" end
        return "2147483647"
    end
    if t.bits == 8 then return "255" end
    if t.bits == 16 then return "65535" end
    if t.bits == 64 then return "18446744073709551615" end
    return "4294967295"
end

local function max_init(t)
    if t.float then return "-1.0e30" end
    if t.signed then
        if t.bits == 8 then return "-128" end
        if t.bits == 16 then return "-32768" end
        if t.bits == 64 then return "-9223372036854775807" end
        return "-2147483648"
    end
    return "0"
end

local function init_for(t, r)
    if r.reduction == Value.ReductionMin then return min_init(t) end
    if r.reduction == Value.ReductionMax then return max_init(t) end
    return r.init
end

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function shell_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function ty_for_case(t)
    if t.float then return Code.CodeTyFloat(t.bits) end
    return Code.CodeTyInt(t.bits, t.signed and Code.CodeSigned or Code.CodeUnsigned)
end

local function literal_for(case, raw)
    if case.type_case.float then return Core.LitFloat(tostring(raw)) end
    return Core.LitInt(tostring(raw))
end

local function reductions_for(t)
    if not t.float then return reductions end
    local out = {}
    for _, r in ipairs(reductions) do
        if r.reduction == Value.ReductionAdd or r.reduction == Value.ReductionMul
            or r.reduction == Value.ReductionMin or r.reduction == Value.ReductionMax then
            out[#out + 1] = r
        end
    end
    return out
end

local function build_module(case)
    local ty = case.ty
    local ptr_ty = Code.CodeTyDataPtr(ty)
    local elem_size = math.max(1, case.bits / 8)
    local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, ty, elem_size, Code.CodeMustNotTrap, false, nil)
    local xs = param("xs", ptr_ty)
    local len = param("n", i32)
    local zero, init, one = Code.CodeValueId("v:zero"), Code.CodeValueId("v:init"), Code.CodeValueId("v:one")
    local i, acc = Code.CodeValueId("v:i"), Code.CodeValueId("v:acc")
    local cond, item, sel_cond = Code.CodeValueId("v:cond"), Code.CodeValueId("v:item"), Code.CodeValueId("v:sel_cond")
    local next_i, next_acc = Code.CodeValueId("v:next_i"), Code.CodeValueId("v:next_acc")
    local out = Code.CodeValueId("v:out")
    local entry_id, header_id = Code.CodeBlockId("block:" .. case.name .. ":entry"), Code.CodeBlockId("block:" .. case.name .. ":header")
    local body_id, exit_id = Code.CodeBlockId("block:" .. case.name .. ":body"), Code.CodeBlockId("block:" .. case.name .. ":exit")
    local sig_id, func_id = Code.CodeSigId("sig:" .. case.name), Code.CodeFuncId("fn:" .. case.name)

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(case.name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(case.name .. ":init", Code.CodeInstConst(init, Code.CodeConstLiteral(ty, literal_for(case, case.init)))),
        inst(case.name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(case.name .. ":entry", Code.CodeTermJump(header_id, { zero, init })), origin)
    local header = Code.CodeBlock(header_id, "header", {
        Code.CodeParam(i, "i", i32, origin),
        Code.CodeParam(acc, "acc", ty, origin),
    }, {
        inst(case.name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, len.value)),
    }, term(case.name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
    local body_insts = {
        inst(case.name .. ":load", Code.CodeInstLoad(item, Code.CodePlaceIndex(Code.CodePlaceDeref(xs.value, ty, elem_size), i, i32, elem_size), access)),
    }
    if case.reduction == Value.ReductionMin or case.reduction == Value.ReductionMax then
        local cmp = case.reduction == Value.ReductionMin and Core.CmpLe or Core.CmpGe
        body_insts[#body_insts + 1] = inst(case.name .. ":sel_cond", Code.CodeInstCompare(sel_cond, cmp, ty, acc, item))
        body_insts[#body_insts + 1] = inst(case.name .. ":reduce", Code.CodeInstSelect(next_acc, ty, sel_cond, acc, item))
    else
        if case.type_case.float then
            body_insts[#body_insts + 1] = inst(case.name .. ":reduce", Code.CodeInstFloatBinary(next_acc, case.op, ty, Code.CodeFloatStrict, acc, item))
        else
            body_insts[#body_insts + 1] = inst(case.name .. ":reduce", Code.CodeInstBinary(next_acc, case.op, ty, sem, acc, item))
        end
    end
    body_insts[#body_insts + 1] = inst(case.name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))
    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(case.name .. ":body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", ty, origin) }, {}, term(case.name .. ":exit", Code.CodeTermReturn({ out })), origin)
    local func = Code.CodeFunc(func_id, case.name, Code.CodeLinkageExport, sig_id, { xs, len }, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. case.name), { Code.CodeSig(sig_id, { ptr_ty, i32 }, { ty }) }, {}, {}, {}, {}, { func }, origin)
    local contracts = Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, len.value), origin),
    })
    return module, contracts
end

local function compile_case(case)
    local module, contracts = build_module(case)
    local rejects = {}
    local artifacts = {}
    local lj_module, facts = Lower.lower_module(module, {
        contracts = contracts,
        collect_rejects = rejects,
        stencil_reduce_artifact_for = function(func, vocab, op, reduction, plan, info)
            local artifact = StencilC.reduce_array_artifact(reduction, plan, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end,
    })
    assert(#rejects == 0, case.name .. " rejected: " .. tostring(rejects[1] and rejects[1].reason))
    assert(#facts.value.reductions == 1 and facts.value.reductions[1].kind == case.reduction, case.name .. " should derive expected ReductionKind")
    local stencil_build, stencil_err = StencilC.compile_artifacts(artifacts, {
        stem = "bench_luajit_lower_reductions_" .. sanitize(case.name),
        cc = cc,
        cflags = cflags .. " -fPIC -shared",
    })
    assert(stencil_build ~= nil, tostring(stencil_err))
    local compiled, err, src = Emit.compile_module(lj_module, {
        chunk_name = "bench_luajit_lower_reductions_" .. case.name,
        stencil_symbols = stencil_build.symbols,
    })
    assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
    return compiled[case.name], src, artifacts, stencil_build
end

local function lua_fill_expr(t, i)
    if t.float then return ((i % 97) - 48) * 0.25 end
    local x = i * 17 + 11
    if t.bits == 8 then x = bit.band(x, 255); if t.signed and x >= 128 then x = x - 256 end
    elseif t.bits == 16 then x = bit.band(x, 65535); if t.signed and x >= 32768 then x = x - 65536 end
    elseif not t.signed then x = x % 4294967296 end
    return x
end

local bench_cases, compiled_cases, arrays, stencil_builds = {}, {}, {}, {}
local total_source_bytes = 0
for _, t in ipairs(type_cases) do
    local ty = ty_for_case(t)
    local xs = ffi.new(t.ctype .. "[?]", n)
    for i = 0, n - 1 do xs[i] = lua_fill_expr(t, i) end
    arrays[t.suffix] = xs
    for _, r in ipairs(reductions_for(t)) do
        local case = {
            name = r.suffix .. "_" .. t.suffix,
            ty = ty,
            bits = t.bits,
            signed = t.signed,
            reduction = r.reduction,
            op = r.op,
            init = init_for(t, r),
            type_case = t,
            red_case = r,
        }
        local lowered, src, _, stencil_build = compile_case(case)
        total_source_bytes = total_source_bytes + #src
        compiled_cases[#compiled_cases + 1] = case
        stencil_builds[#stencil_builds + 1] = stencil_build
        bench_cases[#bench_cases + 1] = { name = "lowered " .. case.name, fn = function() return lowered(xs, n) end }
    end
end

print(string.format("MoonCode -> LuaJIT lower reduction benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
print("supported cells " .. tostring(#compiled_cases) .. ", emitted source bytes " .. tostring(total_source_bytes))
for _, result in ipairs(Measure.measure(bench_cases, {
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

local function c_unsigned(t)
    if t.bits == 8 then return "uint8_t" end
    if t.bits == 16 then return "uint16_t" end
    if t.bits == 64 then return "uint64_t" end
    return "uint32_t"
end

local function c_func(case)
    local t, r = case.type_case, case.red_case
    local ct, ut = t.ctype, c_unsigned(t)
    local acc_ty = (t.float or r.cop == "min" or r.cop == "max") and ct or ut
    local init = case.init
    if r.cop == "and" then init = "((" .. acc_ty .. ")~(" .. acc_ty .. ")0)" end
    if r.cop == "min" and t.bits == 64 and not t.signed and not t.float then init = "UINT64_MAX" end
    local out = {}
    out[#out + 1] = "static " .. ct .. " " .. case.name .. "(const " .. ct .. " *xs, int n) {"
    out[#out + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")(" .. init .. ");"
    out[#out + 1] = "    for (int i = 0; i < n; i++) {"
    if r.cop == "add" then out[#out + 1] = "        acc = (" .. acc_ty .. ")(acc + (" .. acc_ty .. ")xs[i]);"
    elseif r.cop == "mul" then out[#out + 1] = "        acc = (" .. acc_ty .. ")(acc * (" .. acc_ty .. ")xs[i]);"
    elseif r.cop == "and" then out[#out + 1] = "        acc = (" .. acc_ty .. ")(acc & (" .. acc_ty .. ")xs[i]);"
    elseif r.cop == "or" then out[#out + 1] = "        acc = (" .. acc_ty .. ")(acc | (" .. acc_ty .. ")xs[i]);"
    elseif r.cop == "xor" then out[#out + 1] = "        acc = (" .. acc_ty .. ")(acc ^ (" .. acc_ty .. ")xs[i]);"
    elseif r.cop == "min" then out[#out + 1] = "        if (xs[i] < acc) acc = xs[i];"
    elseif r.cop == "max" then out[#out + 1] = "        if (xs[i] > acc) acc = xs[i];" end
    out[#out + 1] = "    }"
    out[#out + 1] = "    return (" .. ct .. ")acc;"
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

if with_gcc then
    os.execute("mkdir -p target/luajit_bench")
    local c_path = "target/luajit_bench/lower_reduction_matrix_baseline.c"
    local exe_path = "target/luajit_bench/lower_reduction_matrix_baseline"
    local c = {}
    c[#c + 1] = [[
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
]]
    for _, case in ipairs(compiled_cases) do c[#c + 1] = c_func(case) end
    c[#c + 1] = "int main(int argc, char **argv) {"
    c[#c + 1] = "    int n = argc > 1 ? atoi(argv[1]) : 120000;"
    c[#c + 1] = "    int samples = argc > 2 ? atoi(argv[2]) : 3;"
    c[#c + 1] = "    int rounds = argc > 3 ? atoi(argv[3]) : 1;"
    for _, t in ipairs(type_cases) do
        c[#c + 1] = "    " .. t.ctype .. " *xs_" .. t.suffix .. " = (" .. t.ctype .. " *)calloc((size_t)n, sizeof(" .. t.ctype .. "));"
        c[#c + 1] = "    if (!xs_" .. t.suffix .. ") abort();"
        c[#c + 1] = "    for (int i = 0; i < n; i++) xs_" .. t.suffix .. "[i] = (" .. t.ctype .. ")(" .. t.fill .. ");"
    end
    c[#c + 1] = "    double *times = (double *)calloc((size_t)samples, sizeof(double)); if (!times) abort();"
    for _, case in ipairs(compiled_cases) do
        local t = case.type_case
        c[#c + 1] = "    { " .. t.ctype .. " first = 0;"
        c[#c + 1] = "      for (int s = 0; s < samples; s++) { double t0 = now_s(); " .. t.ctype .. " value = 0;"
        c[#c + 1] = "        for (int r = 0; r < rounds; r++) value = " .. case.name .. "(xs_" .. t.suffix .. ", n);"
        c[#c + 1] = "        times[s] = now_s() - t0; if (s == 0) first = value; if (value != first) abort(); }"
        c[#c + 1] = "      qsort(times, (size_t)samples, sizeof(double), cmp_double);"
        if t.float then
            c[#c + 1] = "      printf(\"%-28s median=%8.3fms result=%.9g\\n\", \"gcc " .. case.name .. "\", times[samples / 2] * 1000.0, (double)first); }"
        else
            c[#c + 1] = "      printf(\"%-28s median=%8.3fms result=%lld\\n\", \"gcc " .. case.name .. "\", times[samples / 2] * 1000.0, (long long)first); }"
        end
    end
    c[#c + 1] = "    return 0;"
    c[#c + 1] = "}"
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
