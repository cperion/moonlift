-- Moonlift vs Terra runtime benchmark kernel suite.
-- Emits machine-readable lines consumed by run_vs_terra.sh.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

local mode = arg and arg[1] or nil
local quick = mode == "quick"
local N = tonumber(os.getenv("MOONLIFT2_BENCH_N") or (quick and "1048576" or "16777216"))
local WARMUP = tonumber(os.getenv("MOONLIFT2_BENCH_WARMUP") or (quick and "1" or "1"))
local ITERS = tonumber(os.getenv("MOONLIFT2_BENCH_ITERS") or (quick and "2" or "3"))

local SRC = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func dot_i32(a: ptr(i32), b: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func prod_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 1) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc * xs[i])
    end
end

export func xor_reduce_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc ^ xs[i])
    end
end

export func fill_i32(dst: ptr(i32), n: i32, value: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = value
        jump loop(i = i + 1)
    end
end

export func copy_i32(dst: ptr(i32), src: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = src[i]
        jump loop(i = i + 1)
    end
end

export func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func sub_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] - b[i]
        jump loop(i = i + 1)
    end
end

export func scale_i32(dst: ptr(i32), xs: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end

export func inc_i32(xs: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        xs[i] = xs[i] + 1
        jump loop(i = i + 1)
    end
end

export func axpy_i32(y: ptr(i32), x: ptr(i32), a: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        y[i] = y[i] + a * x[i]
        jump loop(i = i + 1)
    end
end

export func and_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] & b[i]
        jump loop(i = i + 1)
    end
end

export func or_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] | b[i]
        jump loop(i = i + 1)
    end
end

export func xor_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] ^ b[i]
        jump loop(i = i + 1)
    end
end

export func clamp_nonneg_i32(noalias dst: ptr(i32), readonly a: ptr(i32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires disjoint(dst, a)
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = select(a[i] < 0, 0, a[i])
        jump loop(i = i + 1)
    end
end

export func max_i32(noalias dst: ptr(i32), readonly a: ptr(i32), readonly b: ptr(i32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = select(a[i] > b[i], a[i], b[i])
        jump loop(i = i + 1)
    end
end

export func in_range_i32(noalias dst: ptr(i32), readonly a: ptr(i32), n: i32, lo: i32, hi: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires disjoint(dst, a)
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = select(a[i] >= lo and a[i] <= hi, 1, 0)
        jump loop(i = i + 1)
    end
end

export func sum_i64(xs: ptr(i64), n: i32) -> i64
    return block loop(i: i32 = 0, acc: i64 = 0) -> i64
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func dot_i64(a: ptr(i64), b: ptr(i64), n: i32) -> i64
    return block loop(i: i32 = 0, acc: i64 = 0) -> i64
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func add_i64(dst: ptr(i64), a: ptr(i64), b: ptr(i64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func sub_i64(dst: ptr(i64), a: ptr(i64), b: ptr(i64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] - b[i]
        jump loop(i = i + 1)
    end
end

export func scale_i64(dst: ptr(i64), xs: ptr(i64), k: i64, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end

export func or_i64(dst: ptr(i64), a: ptr(i64), b: ptr(i64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] | b[i]
        jump loop(i = i + 1)
    end
end

export func sum_u32(xs: ptr(u32), n: i32) -> u32
    return block loop(i: i32 = 0, acc: u32 = 0) -> u32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func add_u32(dst: ptr(u32), a: ptr(u32), b: ptr(u32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func min_u32(noalias dst: ptr(u32), readonly a: ptr(u32), readonly b: ptr(u32), n: i32) -> i32
    requires bounds(dst, n)
    requires bounds(a, n)
    requires bounds(b, n)
    requires disjoint(dst, a)
    requires disjoint(dst, b)
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = select(a[i] < b[i], a[i], b[i])
        jump loop(i = i + 1)
    end
end

export func sum_u64(xs: ptr(u64), n: i32) -> u64
    return block loop(i: i32 = 0, acc: u64 = 0) -> u64
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func add_u64(dst: ptr(u64), a: ptr(u64), b: ptr(u64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func xor_u64(dst: ptr(u64), a: ptr(u64), b: ptr(u64), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] ^ b[i]
        jump loop(i = i + 1)
    end
end

export func add_view_i32(noalias dst: view(i32), readonly a: view(i32), readonly b: view(i32)) -> i32
    requires same_len(dst, a)
    requires same_len(dst, b)
    block loop(i: index = 0)
        if i >= len(dst) then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func copy_view_i32(noalias dst: view(i32), readonly src: view(i32)) -> i32
    requires same_len(dst, src)
    block loop(i: index = 0)
        if i >= len(dst) then return 0 end
        dst[i] = src[i]
        jump loop(i = i + 1)
    end
end

export func threshold_view_i32(noalias dst: view(i32), readonly a: view(i32), t: i32, lo: i32, hi: i32) -> i32
    requires same_len(dst, a)
    block loop(i: index = 0)
        if i >= len(dst) then return 0 end
        dst[i] = select(a[i] > t, hi, lo)
        jump loop(i = i + 1)
    end
end

export func max_view_prefix_window_i32(noalias dst: view(i32), readonly a: view(i32), readonly b: view(i32)) -> i32
    requires same_len(dst, a)
    requires same_len(dst, b)
    let m: index = len(dst) - 1
    let wd: view(i32) = view_window(dst, 1, m)
    let wa: view(i32) = view_window(a, 1, m)
    let wb: view(i32) = view_window(b, 1, m)
    block loop(i: index = 0)
        if i >= len(wd) then return 0 end
        wd[i] = select(wa[i] > wb[i], wa[i], wb[i])
        jump loop(i = i + 1)
    end
end
]]

local function best_of(f, ...)
    for _ = 1, WARMUP do f(...) end
    local best = math.huge
    for _ = 1, ITERS do
        local t0 = os.clock()
        f(...)
        local dt = os.clock() - t0
        if dt < best then best = dt end
    end
    return best
end

local function result_string(v)
    return (tostring(v):gsub("ULL$", ""):gsub("LL$", ""))
end

local function check_i32_map(out, a, b, n, fn)
    for i = 0, n - 1 do
        assert(out[i] == fn(a[i], b and b[i] or nil, i), "i32 map mismatch at " .. i)
    end
end

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local B2 = T.MoonBack

local compile_start = os.clock()
local parsed = P.parse_module(SRC)
assert(#parsed.issues == 0, "parse issues: " .. #parsed.issues)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0, "type issues: " .. #checked.issues)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0, "back validation issues: " .. #report.issues)
local artifact = jit_api.jit():compile(program)
local compile_time = os.clock() - compile_start

local function ptr(name)
    return artifact:getpointer(B2.BackFuncId(name))
end

local f = {
    sum_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", ptr("sum_i32")),
    dot_i32 = ffi.cast("int32_t (*)(const int32_t*, const int32_t*, int32_t)", ptr("dot_i32")),
    prod_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", ptr("prod_i32")),
    xor_reduce_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", ptr("xor_reduce_i32")),
    fill_i32 = ffi.cast("int32_t (*)(int32_t*, int32_t, int32_t)", ptr("fill_i32")),
    copy_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t)", ptr("copy_i32")),
    add_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", ptr("add_i32")),
    sub_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", ptr("sub_i32")),
    scale_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t, int32_t)", ptr("scale_i32")),
    inc_i32 = ffi.cast("int32_t (*)(int32_t*, int32_t)", ptr("inc_i32")),
    axpy_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t, int32_t)", ptr("axpy_i32")),
    and_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", ptr("and_i32")),
    or_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", ptr("or_i32")),
    xor_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", ptr("xor_i32")),
    clamp_nonneg_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t)", ptr("clamp_nonneg_i32")),
    max_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", ptr("max_i32")),
    in_range_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t, int32_t, int32_t)", ptr("in_range_i32")),
    sum_i64 = ffi.cast("int64_t (*)(const int64_t*, int32_t)", ptr("sum_i64")),
    dot_i64 = ffi.cast("int64_t (*)(const int64_t*, const int64_t*, int32_t)", ptr("dot_i64")),
    add_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, const int64_t*, int32_t)", ptr("add_i64")),
    sub_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, const int64_t*, int32_t)", ptr("sub_i64")),
    scale_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, int64_t, int32_t)", ptr("scale_i64")),
    or_i64 = ffi.cast("int32_t (*)(int64_t*, const int64_t*, const int64_t*, int32_t)", ptr("or_i64")),
    sum_u32 = ffi.cast("uint32_t (*)(const uint32_t*, int32_t)", ptr("sum_u32")),
    add_u32 = ffi.cast("int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, int32_t)", ptr("add_u32")),
    min_u32 = ffi.cast("int32_t (*)(uint32_t*, const uint32_t*, const uint32_t*, int32_t)", ptr("min_u32")),
    sum_u64 = ffi.cast("uint64_t (*)(const uint64_t*, int32_t)", ptr("sum_u64")),
    add_u64 = ffi.cast("int32_t (*)(uint64_t*, const uint64_t*, const uint64_t*, int32_t)", ptr("add_u64")),
    xor_u64 = ffi.cast("int32_t (*)(uint64_t*, const uint64_t*, const uint64_t*, int32_t)", ptr("xor_u64")),
}

ffi.cdef[[ typedef struct MoonliftBenchViewI32 { int32_t* data; intptr_t len; intptr_t stride; } MoonliftBenchViewI32; ]]
f.add_view_i32 = ffi.cast("int32_t (*)(MoonliftBenchViewI32*, MoonliftBenchViewI32*, MoonliftBenchViewI32*)", ptr("add_view_i32"))
f.copy_view_i32 = ffi.cast("int32_t (*)(MoonliftBenchViewI32*, MoonliftBenchViewI32*)", ptr("copy_view_i32"))
f.threshold_view_i32 = ffi.cast("int32_t (*)(MoonliftBenchViewI32*, MoonliftBenchViewI32*, int32_t, int32_t, int32_t)", ptr("threshold_view_i32"))
f.max_view_prefix_window_i32 = ffi.cast("int32_t (*)(MoonliftBenchViewI32*, MoonliftBenchViewI32*, MoonliftBenchViewI32*)", ptr("max_view_prefix_window_i32"))

-- Small semantic checks before large timing runs.
do
    local a = ffi.new("int32_t[8]", { 1, -2, 3, -4, 5, -6, 7, -8 })
    local b = ffi.new("int32_t[8]", { 8, 7, 6, 5, 4, 3, 2, 1 })
    local out = ffi.new("int32_t[8]")
    assert(f.sum_i32(a, 8) == -4)
    assert(f.dot_i32(a, b, 8) == 0)
    assert(f.prod_i32(b, 4) == 1680)
    assert(f.xor_reduce_i32(b, 8) == bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(8, 7), 6), 5), 4), 3), 2), 1))
    assert(f.fill_i32(out, 8, 9) == 0); check_i32_map(out, a, nil, 8, function() return 9 end)
    assert(f.copy_i32(out, a, 8) == 0); check_i32_map(out, a, nil, 8, function(x) return x end)
    assert(f.add_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return x + y end)
    assert(f.sub_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return x - y end)
    assert(f.scale_i32(out, a, 3, 8) == 0); check_i32_map(out, a, nil, 8, function(x) return x * 3 end)
    assert(f.inc_i32(out, 8) == 0)
    assert(f.axpy_i32(out, a, 2, 8) == 0)
    assert(f.and_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return bit.band(x, y) end)
    assert(f.or_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return bit.bor(x, y) end)
    assert(f.xor_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return bit.bxor(x, y) end)
    assert(f.clamp_nonneg_i32(out, a, 8) == 0); check_i32_map(out, a, nil, 8, function(x) return x < 0 and 0 or x end)
    assert(f.max_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return x > y and x or y end)
    assert(f.in_range_i32(out, a, 8, -2, 5) == 0); check_i32_map(out, a, nil, 8, function(x) return (x >= -2 and x <= 5) and 1 or 0 end)
end

local function fill_i32_arrays(n)
    local a = ffi.new("int32_t[?]", n)
    local b = ffi.new("int32_t[?]", n)
    local out = ffi.new("int32_t[?]", n)
    local y = ffi.new("int32_t[?]", n)
    for i = 0, n - 1 do
        a[i] = ((i * 17 + 3) % 2048) - 1024
        b[i] = ((i * 31 + 7) % 2048) - 1024
        out[i] = 0
        y[i] = ((i * 13 + 11) % 1024) - 512
    end
    return a, b, out, y
end

local function fill_i64_arrays(n)
    local a = ffi.new("int64_t[?]", n)
    local b = ffi.new("int64_t[?]", n)
    local out = ffi.new("int64_t[?]", n)
    for i = 0, n - 1 do
        a[i] = (i * 17 + 3) % 1009
        b[i] = (i * 31 + 7) % 997
        out[i] = 0
    end
    return a, b, out
end

local function fill_u32_arrays(n)
    local a = ffi.new("uint32_t[?]", n)
    local b = ffi.new("uint32_t[?]", n)
    local out = ffi.new("uint32_t[?]", n)
    for i = 0, n - 1 do
        a[i] = (i * 17 + 3) % 1009
        b[i] = (i * 31 + 7) % 997
        out[i] = 0
    end
    return a, b, out
end

local function fill_u64_arrays(n)
    local a = ffi.new("uint64_t[?]", n)
    local b = ffi.new("uint64_t[?]", n)
    local out = ffi.new("uint64_t[?]", n)
    for i = 0, n - 1 do
        a[i] = (i * 17 + 3) % 1009
        b[i] = (i * 31 + 7) % 997
        out[i] = 0
    end
    return a, b, out
end

local function emit(name, seconds, check)
    io.write(string.format("moonlift_%s %.9f %s\n", name, seconds, result_string(check)))
end

local a32, b32, out32, y32 = fill_i32_arrays(N)
local a64, b64, out64 = fill_i64_arrays(N)
local a32u, b32u, out32u = fill_u32_arrays(N)
local a64u, b64u, out64u = fill_u64_arrays(N)
local av = ffi.new("MoonliftBenchViewI32[1]", { { a32, N, 1 } })
local bv = ffi.new("MoonliftBenchViewI32[1]", { { b32, N, 1 } })
local ov = ffi.new("MoonliftBenchViewI32[1]", { { out32, N, 1 } })

io.write(string.format("moonlift_compile %.9f 0\n", compile_time))

emit("sum_i32", best_of(f.sum_i32, a32, N), f.sum_i32(a32, N))
emit("dot_i32", best_of(f.dot_i32, a32, b32, N), f.dot_i32(a32, b32, N))
emit("prod_i32", best_of(f.prod_i32, a32, N), f.prod_i32(a32, N))
emit("xor_reduce_i32", best_of(f.xor_reduce_i32, a32, N), f.xor_reduce_i32(a32, N))
emit("fill_i32", best_of(f.fill_i32, out32, N, 123), out32[0] + out32[N - 1])
emit("copy_i32", best_of(f.copy_i32, out32, a32, N), out32[0] + out32[N - 1])
emit("add_i32", best_of(f.add_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("sub_i32", best_of(f.sub_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("scale_i32", best_of(f.scale_i32, out32, a32, 3, N), out32[0] + out32[N - 1])
emit("inc_i32", best_of(f.inc_i32, y32, N), y32[0] + y32[N - 1])
emit("axpy_i32", best_of(f.axpy_i32, y32, a32, 2, N), y32[0] + y32[N - 1])
emit("and_i32", best_of(f.and_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("or_i32", best_of(f.or_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("xor_i32", best_of(f.xor_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("clamp_nonneg_i32", best_of(f.clamp_nonneg_i32, out32, a32, N), out32[0] + out32[N - 1])
emit("max_i32", best_of(f.max_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("in_range_i32", best_of(f.in_range_i32, out32, a32, N, -128, 127), out32[0] + out32[N - 1])

emit("sum_i64", best_of(f.sum_i64, a64, N), f.sum_i64(a64, N))
emit("dot_i64", best_of(f.dot_i64, a64, b64, N), f.dot_i64(a64, b64, N))
emit("add_i64", best_of(f.add_i64, out64, a64, b64, N), out64[0] + out64[N - 1])
emit("sub_i64", best_of(f.sub_i64, out64, a64, b64, N), out64[0] + out64[N - 1])
emit("scale_i64", best_of(f.scale_i64, out64, a64, 3LL, N), out64[0] + out64[N - 1])
emit("or_i64", best_of(f.or_i64, out64, a64, b64, N), out64[0] + out64[N - 1])

emit("sum_u32", best_of(f.sum_u32, a32u, N), f.sum_u32(a32u, N))
emit("add_u32", best_of(f.add_u32, out32u, a32u, b32u, N), out32u[0] + out32u[N - 1])
emit("min_u32", best_of(f.min_u32, out32u, a32u, b32u, N), out32u[0] + out32u[N - 1])

emit("sum_u64", best_of(f.sum_u64, a64u, N), f.sum_u64(a64u, N))
emit("add_u64", best_of(f.add_u64, out64u, a64u, b64u, N), out64u[0] + out64u[N - 1])
emit("xor_u64", best_of(f.xor_u64, out64u, a64u, b64u, N), out64u[0] + out64u[N - 1])

emit("add_view_i32", best_of(f.add_view_i32, ov, av, bv), out32[0] + out32[N - 1])
emit("copy_view_i32", best_of(f.copy_view_i32, ov, av), out32[0] + out32[N - 1])
emit("threshold_view_i32", best_of(f.threshold_view_i32, ov, av, 0, -1, 1), out32[0] + out32[N - 1])
emit("max_view_prefix_window_i32", best_of(f.max_view_prefix_window_i32, ov, av, bv), out32[0] + out32[N - 1])

if os.getenv("MOONLIFT2_BENCH_DISASM") == "1" then
    io.stderr:write(artifact:disasm("sum_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("dot_i32", { bytes = 320 }) .. "\n")
    io.stderr:write(artifact:disasm("max_i32", { bytes = 320 }) .. "\n")
    io.stderr:write(artifact:disasm("sum_i64", { bytes = 320 }) .. "\n")
    io.stderr:write(artifact:disasm("add_view_i32", { bytes = 320 }) .. "\n")
end

artifact:free()
