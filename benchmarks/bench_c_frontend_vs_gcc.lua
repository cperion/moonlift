-- Benchmark the Moonlift C frontend against GCC.
--
-- Same kernels compiled two ways:
--   1. C → GCC -O3 → shared library → FFI call
--   2. C → Moonlift frontend (lex/cpp/parse/cimport/lower_c) → typecheck
--      → tree_to_back → validate → back_luajit → execute
--
-- This measures how close the Moonlift C compilation pipeline gets to GCC.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local lexer = require("moonlift.c.c_lexer")
local cpp = require("moonlift.c.cpp_expand")
local vfs = require("moonlift.c.vfs")
local c_parse = require("moonlift.c.c_parse")
local cimport_mod = require("moonlift.c.cimport")
local lower_mod = require("moonlift.c.lower_c")

local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local LuaJITBack = require("moonlift.back_luajit")

local mode = arg and arg[1] or nil
local quick = mode == "quick"
local N = tonumber(os.getenv("MOONLIFT_BENCH_N") or (quick and "262144" or "1048576"))
local STRIDE = tonumber(os.getenv("MOONLIFT_BENCH_STRIDE") or "2")
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (quick and "3" or "5"))
local WARMUP = tonumber(os.getenv("MOONLIFT_BENCH_WARMUP") or (quick and "2" or "4"))

local CSRC = [[
int fib_i32(int n) {
    int a = 0, b = 1, i = 0, t = 0;
    while (i < n) {
        t = a;
        a = b;
        b = t + b;
        i++;
    }
    return a;
}

int sum_stride_i32(const int* xs, int n, int stride) {
    int acc = 0, i = 0;
    while (i < n) {
        acc += xs[i * stride];
        i++;
    }
    return acc;
}

int dot_stride_i32(const int* a, const int* b, int n, int stride) {
    int acc = 0, i = 0;
    while (i < n) {
        acc += a[i * stride] * b[i * stride];
        i++;
    }
    return acc;
}

int fill_stride_i32(int* dst, int n, int stride, int value) {
    int i = 0;
    while (i < n) {
        dst[i * stride] = value;
        i++;
    }
    return 0;
}
]]

-- Compile with GCC
local function gcc_compile(csrc, soname)
    local cfile = os.tmpname() .. ".c"
    local f = io.open(cfile, "w"); f:write(csrc); f:close()
    local cmd = string.format("gcc -O3 -fPIC -shared -o %s -x c %s 2>&1", soname, cfile)
    local h = io.popen(cmd)
    local out = h:read("*a"); h:close()
    if #out > 0 then error("gcc: " .. out) end
    os.remove(cfile)
end

-- Build GCC .so
local gcc_so = os.tmpname() .. ".so"
local gcc_t0 = os.clock()
gcc_compile(CSRC, gcc_so)
local gcc_t = os.clock() - gcc_t0

-- Load GCC .so via FFI
ffi.cdef[[
int fib_i32(int n);
int sum_stride_i32(const int* xs, int n, int stride);
int dot_stride_i32(const int* a, const int* b, int n, int stride);
int fill_stride_i32(int* dst, int n, int stride, int value);
]]
local gcc_lib = ffi.load(gcc_so)

-- Build Moonlift C frontend
local T = pvm.context()
A.Define(T)
cpp = cpp.Define(T)
c_parse = c_parse.Define(T)
cimport_mod = cimport_mod.Define(T)
lower_mod = lower_mod.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local luajit_api = LuaJITBack.Define(T)

local function moonlift_compile_c(csrc)
    local t0 = os.clock()
    local r = lexer.lex(csrc, "bench.c")
    assert(#r.issues == 0, r.issues[1] and r.issues[1].message)
    r = cpp.expand(r.tokens, r.spans, r.issues, vfs.mock({}))
    assert(#r.issues == 0, r.issues[1] and r.issues[1].message)
    local tu, parse_issues = c_parse.parse(r.tokens, r.spans)
    assert(#parse_issues == 0, parse_issues[1] and parse_issues[1].message)
    local tf, lf, ef = cimport_mod.cimport(tu.items, "bench_mod")
    local mm = lower_mod.lower(tu.items, tf, lf, ef, "bench_mod")
    local checked = TC.check_module(mm)
    assert(#checked.issues == 0, checked.issues[1] and tostring(pvm.classof(checked.issues[1]).kind))
    local program = Lower.module(checked.module)
    local report = V.validate(program)
    assert(#report.issues == 0, report.issues[1] and report.issues[1].message)
    local frontend_t = os.clock() - t0
    local compile_t0 = os.clock()
    local artifact = luajit_api.compile(program)
    local compile_t = os.clock() - compile_t0
    return artifact, frontend_t, compile_t, program
end

local ml_artifact, ml_frontend_t, ml_compile_t, ml_program = moonlift_compile_c(CSRC)
local ml = ml_artifact.module

-- Fill test arrays
local function fill_arrays(n, stride)
    local len = n * stride + 8
    local a = ffi.new("int32_t[?]", len)
    local b = ffi.new("int32_t[?]", len)
    local out = ffi.new("int32_t[?]", len)
    for i = 0, len - 1 do
        a[i] = ((i * 17 + 3) % 2048) - 1024
        b[i] = ((i * 31 + 7) % 2048) - 1024
        out[i] = 0
    end
    return a, b, out
end

local function best_of(fn)
    for _ = 1, WARMUP do fn() end
    local best = math.huge
    local check
    for _ = 1, ITERS do
        local t0 = os.clock()
        check = fn()
        local dt = os.clock() - t0
        if dt < best then best = dt end
    end
    return best, check
end

-- Correctness check
local a_small, b_small, out_small_g = fill_arrays(64, STRIDE)
local _, _, out_small_m = fill_arrays(64, STRIDE)
assert(gcc_lib.fib_i32(32) == ml.fib_i32(32),
       string.format("fib: gcc=%d ml=%d", gcc_lib.fib_i32(32), ml.fib_i32(32)))
assert(gcc_lib.sum_stride_i32(a_small, 64, STRIDE) == ml.sum_stride_i32(a_small, 64, STRIDE))
assert(gcc_lib.dot_stride_i32(a_small, b_small, 64, STRIDE) == ml.dot_stride_i32(a_small, b_small, 64, STRIDE))
gcc_lib.fill_stride_i32(out_small_g, 64, STRIDE, 9)
ml.fill_stride_i32(out_small_m, 64, STRIDE, 9)
assert(out_small_g[0] == out_small_m[0] and out_small_g[63*STRIDE] == out_small_m[63*STRIDE])

local a, b, out_g = fill_arrays(N, STRIDE)
local _, _, out_m = fill_arrays(N, STRIDE)

local cases = {
    { name="fib_i32",
      g=function() return gcc_lib.fib_i32(N) end,
      m=function() return ml.fib_i32(N) end },
    { name="sum_stride_i32",
      g=function() return gcc_lib.sum_stride_i32(a, N, STRIDE) end,
      m=function() return ml.sum_stride_i32(a, N, STRIDE) end },
    { name="dot_stride_i32",
      g=function() return gcc_lib.dot_stride_i32(a, b, N, STRIDE) end,
      m=function() return ml.dot_stride_i32(a, b, N, STRIDE) end },
    { name="fill_stride_i32",
      g=function() return gcc_lib.fill_stride_i32(out_g, N, STRIDE, 123) end,
      m=function() return ml.fill_stride_i32(out_m, N, STRIDE, 123) end,
      check=function() return out_g[0]+out_g[(N-1)*STRIDE], out_m[0]+out_m[(N-1)*STRIDE] end },
}

io.write("C frontend benchmark: Moonlift LuaJIT backend vs GCC -O3\n")
io.write(string.format("C_source_bytes %d\n", #CSRC))
io.write(string.format("moonlift_back_cmds %d\n", #ml_program.cmds))
io.write(string.format("N %d\nSTRIDE %d\nITERS %d\nWARMUP %d\n\n", N, STRIDE, ITERS, WARMUP))
io.write("compile_seconds\n")
io.write(string.format("  gcc_O3_compile                  %.9f\n", gcc_t))
io.write(string.format("  moonlift_frontend_parse_import  %.9f\n", ml_frontend_t))
io.write(string.format("  moonlift_backend_compile        %.9f\n", ml_compile_t))
io.write(string.format("  luajit_generated_source_bytes   %d\n\n", #ml_artifact.source))

io.write(string.format("%-18s %12s %12s %12s %12s\n", "kernel", "gcc_O3_s", "moonlift_s", "ml/gcc", "check"))
for _, case in ipairs(cases) do
    local gt = best_of(case.g)
    local mt = best_of(case.m)
    local ck_g, ck_m
    if case.check then ck_g, ck_m = case.check() else ck_g, ck_m = case.g(), case.m() end
    local ok = ck_g == ck_m and tostring(ck_m) or ("MISMATCH " .. tostring(ck_g) .. "/" .. tostring(ck_m))
    io.write(string.format("%-18s %12.9f %12.9f %12.3f %12s\n", case.name, gt, mt, mt / gt, ok))
end

os.remove(gcc_so)
