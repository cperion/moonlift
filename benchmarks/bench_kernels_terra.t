-- Terra side of the Moonlift benchmark kernel suite.
-- Emits machine-readable lines consumed by run_vs_terra.sh.

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[ typedef struct MoonliftBenchViewI32 { int32_t* data; intptr_t len; intptr_t stride; } MoonliftBenchViewI32; ]]

local mode = arg and arg[1] or nil
local quick = mode == "quick"
local N = tonumber(os.getenv("TERRA_MOONLIFT2_BENCH_N") or os.getenv("MOONLIFT2_BENCH_N") or (quick and "1048576" or "16777216"))
local WARMUP = tonumber(os.getenv("TERRA_MOONLIFT2_BENCH_WARMUP") or os.getenv("MOONLIFT2_BENCH_WARMUP") or (quick and "1" or "1"))
local ITERS = tonumber(os.getenv("TERRA_MOONLIFT2_BENCH_ITERS") or os.getenv("MOONLIFT2_BENCH_ITERS") or (quick and "2" or "3"))

struct MoonliftBenchViewI32 {
    data: &int32;
    len: intptr;
    stride: intptr;
}

local terra sum_i32(xs: &int32, n: int32): int32
    var i: int32 = 0
    var acc: int32 = 0
    while i < n do
        acc = acc + xs[i]
        i = i + 1
    end
    return acc
end

local terra dot_i32(a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    var acc: int32 = 0
    while i < n do
        acc = acc + a[i] * b[i]
        i = i + 1
    end
    return acc
end

local terra prod_i32(xs: &int32, n: int32): int32
    var i: int32 = 0
    var acc: int32 = 1
    while i < n do
        acc = acc * xs[i]
        i = i + 1
    end
    return acc
end

local terra xor_reduce_i32(xs: &int32, n: int32): int32
    var i: int32 = 0
    var acc: int32 = 0
    while i < n do
        acc = acc ^ xs[i]
        i = i + 1
    end
    return acc
end

local terra fill_i32(dst: &int32, n: int32, value: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = value
        i = i + 1
    end
    return 0
end

local terra copy_i32(dst: &int32, src: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = src[i]
        i = i + 1
    end
    return 0
end

local terra add_i32(dst: &int32, a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] + b[i]
        i = i + 1
    end
    return 0
end

local terra sub_i32(dst: &int32, a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] - b[i]
        i = i + 1
    end
    return 0
end

local terra scale_i32(dst: &int32, xs: &int32, k: int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = xs[i] * k
        i = i + 1
    end
    return 0
end

local terra inc_i32(xs: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        xs[i] = xs[i] + 1
        i = i + 1
    end
    return 0
end

local terra axpy_i32(y: &int32, x: &int32, a: int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        y[i] = y[i] + a * x[i]
        i = i + 1
    end
    return 0
end

local terra band_i32(dst: &int32, a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] and b[i]
        i = i + 1
    end
    return 0
end

local terra bor_i32(dst: &int32, a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] or b[i]
        i = i + 1
    end
    return 0
end

local terra xor_i32(dst: &int32, a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] ^ b[i]
        i = i + 1
    end
    return 0
end

local terra clamp_nonneg_i32(dst: &int32, a: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        if a[i] < 0 then
            dst[i] = 0
        else
            dst[i] = a[i]
        end
        i = i + 1
    end
    return 0
end

local terra max_i32(dst: &int32, a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        if a[i] > b[i] then
            dst[i] = a[i]
        else
            dst[i] = b[i]
        end
        i = i + 1
    end
    return 0
end

local terra in_range_i32(dst: &int32, a: &int32, n: int32, lo: int32, hi: int32): int32
    var i: int32 = 0
    while i < n do
        if a[i] >= lo and a[i] <= hi then
            dst[i] = 1
        else
            dst[i] = 0
        end
        i = i + 1
    end
    return 0
end

local terra sum_i64(xs: &int64, n: int32): int64
    var i: int32 = 0
    var acc: int64 = 0
    while i < n do
        acc = acc + xs[i]
        i = i + 1
    end
    return acc
end

local terra dot_i64(a: &int64, b: &int64, n: int32): int64
    var i: int32 = 0
    var acc: int64 = 0
    while i < n do
        acc = acc + a[i] * b[i]
        i = i + 1
    end
    return acc
end

local terra add_i64(dst: &int64, a: &int64, b: &int64, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] + b[i]
        i = i + 1
    end
    return 0
end

local terra sub_i64(dst: &int64, a: &int64, b: &int64, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] - b[i]
        i = i + 1
    end
    return 0
end

local terra scale_i64(dst: &int64, xs: &int64, k: int64, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = xs[i] * k
        i = i + 1
    end
    return 0
end

local terra bor_i64(dst: &int64, a: &int64, b: &int64, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] or b[i]
        i = i + 1
    end
    return 0
end

local terra sum_u32(xs: &uint32, n: int32): uint32
    var i: int32 = 0
    var acc: uint32 = 0
    while i < n do
        acc = acc + xs[i]
        i = i + 1
    end
    return acc
end

local terra add_u32(dst: &uint32, a: &uint32, b: &uint32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] + b[i]
        i = i + 1
    end
    return 0
end

local terra min_u32(dst: &uint32, a: &uint32, b: &uint32, n: int32): int32
    var i: int32 = 0
    while i < n do
        if a[i] < b[i] then
            dst[i] = a[i]
        else
            dst[i] = b[i]
        end
        i = i + 1
    end
    return 0
end

local terra sum_u64(xs: &uint64, n: int32): uint64
    var i: int32 = 0
    var acc: uint64 = 0
    while i < n do
        acc = acc + xs[i]
        i = i + 1
    end
    return acc
end

local terra add_u64(dst: &uint64, a: &uint64, b: &uint64, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] + b[i]
        i = i + 1
    end
    return 0
end

local terra xor_u64(dst: &uint64, a: &uint64, b: &uint64, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] ^ b[i]
        i = i + 1
    end
    return 0
end

local terra add_view_i32(dst: &MoonliftBenchViewI32, a: &MoonliftBenchViewI32, b: &MoonliftBenchViewI32): int32
    var i: intptr = 0
    while i < dst.len do
        dst.data[i * dst.stride] = a.data[i * a.stride] + b.data[i * b.stride]
        i = i + 1
    end
    return 0
end

local terra copy_view_i32(dst: &MoonliftBenchViewI32, src: &MoonliftBenchViewI32): int32
    var i: intptr = 0
    while i < dst.len do
        dst.data[i * dst.stride] = src.data[i * src.stride]
        i = i + 1
    end
    return 0
end

local terra threshold_view_i32(dst: &MoonliftBenchViewI32, a: &MoonliftBenchViewI32, t: int32, lo: int32, hi: int32): int32
    var i: intptr = 0
    while i < dst.len do
        if a.data[i * a.stride] > t then
            dst.data[i * dst.stride] = hi
        else
            dst.data[i * dst.stride] = lo
        end
        i = i + 1
    end
    return 0
end

local terra max_view_prefix_window_i32(dst: &MoonliftBenchViewI32, a: &MoonliftBenchViewI32, b: &MoonliftBenchViewI32): int32
    var i: intptr = 0
    var m: intptr = dst.len - 1
    while i < m do
        var j: intptr = i + 1
        var av = a.data[j * a.stride]
        var bv = b.data[j * b.stride]
        if av > bv then
            dst.data[j * dst.stride] = av
        else
            dst.data[j * dst.stride] = bv
        end
        i = i + 1
    end
    return 0
end

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

local funcs = {
    sum_i32, dot_i32, prod_i32, xor_reduce_i32, fill_i32, copy_i32, add_i32,
    sub_i32, scale_i32, inc_i32, axpy_i32, band_i32, bor_i32, xor_i32,
    clamp_nonneg_i32, max_i32, in_range_i32,
    sum_i64, dot_i64, add_i64, sub_i64, scale_i64, bor_i64,
    sum_u32, add_u32, min_u32, sum_u64, add_u64, xor_u64,
    add_view_i32, copy_view_i32, threshold_view_i32, max_view_prefix_window_i32,
}

local compile_start = os.clock()
for i = 1, #funcs do funcs[i]:compile() end
local compile_time = os.clock() - compile_start

-- Small semantic checks before large timing runs.
do
    local a = ffi.new("int32_t[8]", { 1, -2, 3, -4, 5, -6, 7, -8 })
    local b = ffi.new("int32_t[8]", { 8, 7, 6, 5, 4, 3, 2, 1 })
    local out = ffi.new("int32_t[8]")
    assert(sum_i32(a, 8) == -4)
    assert(dot_i32(a, b, 8) == 0)
    assert(prod_i32(b, 4) == 1680)
    assert(xor_reduce_i32(b, 8) == bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(bit.bxor(8, 7), 6), 5), 4), 3), 2), 1))
    assert(fill_i32(out, 8, 9) == 0); check_i32_map(out, a, nil, 8, function() return 9 end)
    assert(copy_i32(out, a, 8) == 0); check_i32_map(out, a, nil, 8, function(x) return x end)
    assert(add_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return x + y end)
    assert(sub_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return x - y end)
    assert(scale_i32(out, a, 3, 8) == 0); check_i32_map(out, a, nil, 8, function(x) return x * 3 end)
    assert(inc_i32(out, 8) == 0)
    assert(axpy_i32(out, a, 2, 8) == 0)
    assert(band_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return bit.band(x, y) end)
    assert(bor_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return bit.bor(x, y) end)
    assert(xor_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return bit.bxor(x, y) end)
    assert(clamp_nonneg_i32(out, a, 8) == 0); check_i32_map(out, a, nil, 8, function(x) return x < 0 and 0 or x end)
    assert(max_i32(out, a, b, 8) == 0); check_i32_map(out, a, b, 8, function(x, y) return x > y and x or y end)
    assert(in_range_i32(out, a, 8, -2, 5) == 0); check_i32_map(out, a, nil, 8, function(x) return (x >= -2 and x <= 5) and 1 or 0 end)
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
    io.write(string.format("terra_%s %.9f %s\n", name, seconds, result_string(check)))
end

local a32, b32, out32, y32 = fill_i32_arrays(N)
local a64, b64, out64 = fill_i64_arrays(N)
local a32u, b32u, out32u = fill_u32_arrays(N)
local a64u, b64u, out64u = fill_u64_arrays(N)
local av = ffi.new("MoonliftBenchViewI32[1]", { { a32, N, 1 } })
local bv = ffi.new("MoonliftBenchViewI32[1]", { { b32, N, 1 } })
local ov = ffi.new("MoonliftBenchViewI32[1]", { { out32, N, 1 } })

io.write(string.format("terra_compile %.9f 0\n", compile_time))

emit("sum_i32", best_of(sum_i32, a32, N), sum_i32(a32, N))
emit("dot_i32", best_of(dot_i32, a32, b32, N), dot_i32(a32, b32, N))
emit("prod_i32", best_of(prod_i32, a32, N), prod_i32(a32, N))
emit("xor_reduce_i32", best_of(xor_reduce_i32, a32, N), xor_reduce_i32(a32, N))
emit("fill_i32", best_of(fill_i32, out32, N, 123), out32[0] + out32[N - 1])
emit("copy_i32", best_of(copy_i32, out32, a32, N), out32[0] + out32[N - 1])
emit("add_i32", best_of(add_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("sub_i32", best_of(sub_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("scale_i32", best_of(scale_i32, out32, a32, 3, N), out32[0] + out32[N - 1])
emit("inc_i32", best_of(inc_i32, y32, N), y32[0] + y32[N - 1])
emit("axpy_i32", best_of(axpy_i32, y32, a32, 2, N), y32[0] + y32[N - 1])
emit("and_i32", best_of(band_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("or_i32", best_of(bor_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("xor_i32", best_of(xor_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("clamp_nonneg_i32", best_of(clamp_nonneg_i32, out32, a32, N), out32[0] + out32[N - 1])
emit("max_i32", best_of(max_i32, out32, a32, b32, N), out32[0] + out32[N - 1])
emit("in_range_i32", best_of(in_range_i32, out32, a32, N, -128, 127), out32[0] + out32[N - 1])

emit("sum_i64", best_of(sum_i64, a64, N), sum_i64(a64, N))
emit("dot_i64", best_of(dot_i64, a64, b64, N), dot_i64(a64, b64, N))
emit("add_i64", best_of(add_i64, out64, a64, b64, N), out64[0] + out64[N - 1])
emit("sub_i64", best_of(sub_i64, out64, a64, b64, N), out64[0] + out64[N - 1])
emit("scale_i64", best_of(scale_i64, out64, a64, 3LL, N), out64[0] + out64[N - 1])
emit("or_i64", best_of(bor_i64, out64, a64, b64, N), out64[0] + out64[N - 1])

emit("sum_u32", best_of(sum_u32, a32u, N), sum_u32(a32u, N))
emit("add_u32", best_of(add_u32, out32u, a32u, b32u, N), out32u[0] + out32u[N - 1])
emit("min_u32", best_of(min_u32, out32u, a32u, b32u, N), out32u[0] + out32u[N - 1])

emit("sum_u64", best_of(sum_u64, a64u, N), sum_u64(a64u, N))
emit("add_u64", best_of(add_u64, out64u, a64u, b64u, N), out64u[0] + out64u[N - 1])
emit("xor_u64", best_of(xor_u64, out64u, a64u, b64u, N), out64u[0] + out64u[N - 1])

emit("add_view_i32", best_of(add_view_i32, ov, av, bv), out32[0] + out32[N - 1])
emit("copy_view_i32", best_of(copy_view_i32, ov, av), out32[0] + out32[N - 1])
emit("threshold_view_i32", best_of(threshold_view_i32, ov, av, 0, -1, 1), out32[0] + out32[N - 1])
emit("max_view_prefix_window_i32", best_of(max_view_prefix_window_i32, ov, av, bv), out32[0] + out32[N - 1])
