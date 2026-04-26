-- Terra side of the Moonlift benchmark kernels.
-- Emits machine-readable lines consumed by run_vs_terra.sh.

local ffi = require("ffi")

local mode = arg and arg[1] or nil
local quick = mode == "quick"
local N = tonumber(os.getenv("TERRA_MOONLIFT2_BENCH_N") or os.getenv("MOONLIFT2_BENCH_N") or (quick and "1048576" or "16777216"))
local WARMUP = tonumber(os.getenv("TERRA_MOONLIFT2_BENCH_WARMUP") or os.getenv("MOONLIFT2_BENCH_WARMUP") or (quick and "1" or "3"))
local ITERS = tonumber(os.getenv("TERRA_MOONLIFT2_BENCH_ITERS") or os.getenv("MOONLIFT2_BENCH_ITERS") or (quick and "2" or "7"))

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

local terra add_i32(dst: &int32, a: &int32, b: &int32, n: int32): int32
    var i: int32 = 0
    while i < n do
        dst[i] = a[i] + b[i]
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

local function fill_i32_arrays(n)
    local a = ffi.new("int32_t[?]", n)
    local b = ffi.new("int32_t[?]", n)
    local out = ffi.new("int32_t[?]", n)
    for i = 0, n - 1 do
        a[i] = (i * 17 + 3) % 1009
        b[i] = (i * 31 + 7) % 997
        out[i] = 0
    end
    return a, b, out
end

local compile_start = os.clock()
sum_i32:compile()
dot_i32:compile()
add_i32:compile()
scale_i32:compile()
local compile_time = os.clock() - compile_start

local a, b, out = fill_i32_arrays(N)
assert(sum_i32(a, 8) == 500)
assert(dot_i32(a, b, 8) == 79884)
assert(add_i32(out, a, b, 8) == 0)
for i = 0, 7 do assert(out[i] == a[i] + b[i]) end
assert(scale_i32(out, a, 3, 8) == 0)
for i = 0, 7 do assert(out[i] == a[i] * 3) end

local sum_t = best_of(sum_i32, a, N)
local dot_t = best_of(dot_i32, a, b, N)
local add_t = best_of(add_i32, out, a, b, N)
local add_check = out[0] + out[N - 1]
local scale_t = best_of(scale_i32, out, a, 3, N)
local scale_check = out[0] + out[N - 1]

io.write(string.format("terra_compile %.9f 0\n", compile_time))
io.write(string.format("terra_sum_i32 %.9f %s\n", sum_t, result_string(sum_i32(a, N))))
io.write(string.format("terra_dot_i32 %.9f %s\n", dot_t, result_string(dot_i32(a, b, N))))
io.write(string.format("terra_add_i32 %.9f %s\n", add_t, result_string(add_check)))
io.write(string.format("terra_scale_i32 %.9f %s\n", scale_t, result_string(scale_check)))
