-- Benchmark equivalent Moonlift source through two executable backends:
--   1. Rust/Cranelift back_jit
--   2. Pure LuaJIT source backend back_luajit
--
-- Starts from the same Moonlift text, shares parse/typecheck/tree_to_back/
-- validation, then compares backend compile time and runtime. The kernels are
-- intentionally stride/recurrence-shaped so this benchmark compares backend
-- execution without triggering Moonlift's current vector-kernel lowering, which
-- can exceed LuaJIT's 200-local function limit before local allocation is added.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Cranelift = require("moonlift.back_jit")
local LuaJITBack = require("moonlift.back_luajit")

local mode = arg and arg[1] or nil
local quick = mode == "quick"
local N = tonumber(os.getenv("MOONLIFT_BENCH_N") or (quick and "262144" or "1048576"))
local STRIDE = tonumber(os.getenv("MOONLIFT_BENCH_STRIDE") or "2")
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (quick and "3" or "5"))
local WARMUP = tonumber(os.getenv("MOONLIFT_BENCH_WARMUP") or (quick and "2" or "4"))

local SRC = [[
export func fib_i32(n: i32) -> i32
    return block loop(i: i32 = 0, a: i32 = 0, b: i32 = 1) -> i32
        if i >= n then yield a end
        jump loop(i = i + 1, a = b, b = a + b)
    end
end

export func sum_stride_i32(xs: ptr(i32), n: i32, stride: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i * stride])
    end
end

export func dot_stride_i32(a: ptr(i32), b: ptr(i32), n: i32, stride: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i * stride] * b[i * stride])
    end
end

export func fill_stride_i32(dst: ptr(i32), n: i32, stride: i32, value: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i * stride] = value
        jump loop(i = i + 1)
    end
end
]]

local unpack_ = table.unpack or unpack
local function timed(fn)
    local t0 = os.clock()
    local r = { fn() }
    return os.clock() - t0, unpack_(r)
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

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local cranelift_api = Cranelift.Define(T)
local luajit_api = LuaJITBack.Define(T)
local B = T.MoonBack

local common_t, program = timed(function()
    local parsed = P.parse_module(SRC)
    assert(#parsed.issues == 0, "parse issues: " .. tostring(parsed.issues[1] and parsed.issues[1].message))
    local checked = TC.check_module(parsed.module)
    assert(#checked.issues == 0, "type issues: " .. tostring(checked.issues[1] and checked.issues[1].message))
    local program = Lower.module(checked.module)
    local report = V.validate(program)
    assert(#report.issues == 0, "back validation issues: " .. tostring(report.issues[1] and report.issues[1].message))
    return program
end)

local cranelift_compile_t, cranelift_artifact, cranelift_jit = timed(function()
    local jit = cranelift_api.jit()
    return jit:compile(program), jit
end)

local luajit_compile_t, luajit_artifact = timed(function()
    return luajit_api.compile(program)
end)

local function cptr(name) return cranelift_artifact:getpointer(B.BackFuncId(name)) end
local c = {
    fib_i32 = ffi.cast("int32_t (*)(int32_t)", cptr("fib_i32")),
    sum_stride_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t, int32_t)", cptr("sum_stride_i32")),
    dot_stride_i32 = ffi.cast("int32_t (*)(const int32_t*, const int32_t*, int32_t, int32_t)", cptr("dot_stride_i32")),
    fill_stride_i32 = ffi.cast("int32_t (*)(int32_t*, int32_t, int32_t, int32_t)", cptr("fill_stride_i32")),
}
local l = luajit_artifact.module

-- Correctness on a small fixture.
do
    local a, b, out_c = fill_arrays(64, STRIDE)
    local _, _, out_l = fill_arrays(64, STRIDE)
    assert(c.fib_i32(32) == l.fib_i32(32))
    assert(c.sum_stride_i32(a, 64, STRIDE) == l.sum_stride_i32(a, 64, STRIDE))
    assert(c.dot_stride_i32(a, b, 64, STRIDE) == l.dot_stride_i32(a, b, 64, STRIDE))
    assert(c.fill_stride_i32(out_c, 64, STRIDE, 9) == l.fill_stride_i32(out_l, 64, STRIDE, 9))
    assert(out_c[0] == out_l[0] and out_c[(63 * STRIDE)] == out_l[(63 * STRIDE)])
end

local a, b, out_c = fill_arrays(N, STRIDE)
local _, _, out_l = fill_arrays(N, STRIDE)

local cases = {
    { name="fib_i32", c=function() return c.fib_i32(N) end, l=function() return l.fib_i32(N) end },
    { name="sum_stride_i32", c=function() return c.sum_stride_i32(a, N, STRIDE) end, l=function() return l.sum_stride_i32(a, N, STRIDE) end },
    { name="dot_stride_i32", c=function() return c.dot_stride_i32(a, b, N, STRIDE) end, l=function() return l.dot_stride_i32(a, b, N, STRIDE) end },
    { name="fill_stride_i32", c=function() return c.fill_stride_i32(out_c, N, STRIDE, 123) end, l=function() return l.fill_stride_i32(out_l, N, STRIDE, 123) end,
      check=function() return out_c[0]+out_c[(N-1)*STRIDE], out_l[0]+out_l[(N-1)*STRIDE] end },
}

io.write("Moonlift source benchmark: LuaJIT backend vs Cranelift\n")
io.write(string.format("source_bytes %d\n", #SRC))
io.write(string.format("back_cmds %d\n", #program.cmds))
io.write(string.format("N %d\nSTRIDE %d\nITERS %d\nWARMUP %d\n\n", N, STRIDE, ITERS, WARMUP))
io.write("compile_seconds\n")
io.write(string.format("  common_parse_type_lower_validate %.9f\n", common_t))
io.write(string.format("  cranelift_backend_compile        %.9f\n", cranelift_compile_t))
io.write(string.format("  luajit_backend_compile           %.9f\n", luajit_compile_t))
io.write(string.format("  luajit_generated_source_bytes    %d\n\n", #luajit_artifact.source))

io.write(string.format("%-18s %12s %12s %12s %12s\n", "kernel", "cranelift_s", "luajit_s", "lj/cl", "check"))
for _, case in ipairs(cases) do
    local ct = best_of(case.c)
    local lt = best_of(case.l)
    local ck_c, ck_l
    if case.check then ck_c, ck_l = case.check() else ck_c, ck_l = case.c(), case.l() end
    local ok = ck_c == ck_l and tostring(ck_l) or ("MISMATCH " .. tostring(ck_c) .. "/" .. tostring(ck_l))
    io.write(string.format("%-18s %12.9f %12.9f %12.3f %12s\n", case.name, ct, lt, lt / ct, ok))
end

cranelift_artifact:free()
cranelift_jit:free()
