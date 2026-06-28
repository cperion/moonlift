-- Terra companion for bench_lalin_source_shapes.lua.
-- Same data shapes and kernels, so numbers can be compared directly.

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
typedef long time_t;
struct timespec { time_t tv_sec; long tv_nsec; };
int clock_gettime(int clk_id, struct timespec *tp);
]]

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_SOURCE_SHAPE_N") or os.getenv("TERRA_SOURCE_SHAPE_N") or (full and "1000000" or "200000"))
local samples = tonumber(os.getenv("TERRA_SOURCE_SHAPE_RUNTIME_SAMPLES") or os.getenv("LALIN_SOURCE_SHAPE_RUNTIME_SAMPLES") or (full and "7" or "4"))
local rounds = tonumber(os.getenv("TERRA_SOURCE_SHAPE_ROUNDS") or os.getenv("LALIN_SOURCE_SHAPE_ROUNDS") or (full and "3" or "1"))

local terra terra_sum_i32(xs: &int32, n0: int32): int32
    var acc: uint32 = 0
    for i = 0, n0 do
        acc = acc + [uint32](xs[i])
    end
    return [int32](acc)
end

local terra terra_zip_add_i32(dst: &int32, lhs: &int32, rhs: &int32, n0: int32)
    for i = 0, n0 do
        dst[i] = [int32]([uint32](lhs[i]) + [uint32](rhs[i]))
    end
end

local terra terra_fused_reduce_i32(lhs: &int32, rhs: &int32, bias: &int32, n0: int32): int32
    var acc: uint32 = 0
    for i = 0, n0 do
        acc = acc + ([uint32](lhs[i]) * [uint32](rhs[i])) + [uint32](bias[i])
    end
    return [int32](acc)
end

local terra terra_scan_sum_i32(dst: &int32, xs: &int32, n0: int32)
    var acc: uint32 = 0
    for i = 0, n0 do
        acc = acc + [uint32](xs[i])
        dst[i] = [int32](acc)
    end
end

local terra terra_scatter_reduce_add_i32(dst: &int32, src: &int32, idx: &int32, n0: int32)
    for i = 0, n0 do
        var j = idx[i]
        dst[j] = [int32]([uint32](dst[j]) + [uint32](src[i]))
    end
end

local funcs = {
    terra_sum_i32,
    terra_zip_add_i32,
    terra_fused_reduce_i32,
    terra_scan_sum_i32,
    terra_scatter_reduce_add_i32,
}

local CLOCK_MONOTONIC = 1
local ts = ffi.new("struct timespec[1]")
local function now()
    if ffi.C.clock_gettime(CLOCK_MONOTONIC, ts) == 0 then
        return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) * 1e-9
    end
    return os.clock()
end

local function median(values)
    table.sort(values)
    local n0 = #values
    if n0 % 2 == 1 then return values[(n0 + 1) / 2] end
    return (values[n0 / 2] + values[n0 / 2 + 1]) / 2
end

local function stats(values)
    local min, max, sum = math.huge, -math.huge, 0
    for i = 1, #values do
        local v = values[i]
        if v < min then min = v end
        if v > max then max = v end
        sum = sum + v
    end
    return median(values), min, sum / #values, max
end

local function stats_line(name, values)
    local med, min, avg, max = stats(values)
    return string.format("%-34s median=%8.3fms min=%8.3fms avg=%8.3fms max=%8.3fms", name, med * 1000, min * 1000, avg * 1000, max * 1000)
end

local compile_start = now()
for i = 1, #funcs do funcs[i]:compile() end
local compile_time = now() - compile_start

local xs = ffi.new("int32_t[?]", n)
local ys = ffi.new("int32_t[?]", n)
local bias = ffi.new("int32_t[?]", n)
local idx = ffi.new("int32_t[?]", n)
local out = ffi.new("int32_t[?]", n)
local bins = ffi.new("int32_t[?]", n)
for i = 0, n - 1 do
    xs[i] = bit.tobit((i % 97) - 48)
    ys[i] = bit.tobit((i % 31) - 15)
    bias[i] = bit.tobit((i % 17) - 8)
    idx[i] = i
end

local function checksum(buf)
    return bit.tobit(buf[0] + buf[math.floor((n - 1) / 2)] + buf[n - 1])
end

local function clear_bins()
    ffi.fill(bins, ffi.sizeof("int32_t") * n, 0)
end

local function measure(fn)
    for _ = 1, (full and 4 or 2) do fn() end
    local values = {}
    local result
    for i = 1, samples do
        local t0 = now()
        for _ = 1, rounds do result = fn() end
        values[i] = (now() - t0) / rounds
    end
    return values, result
end

local cases = {
    { name = "terra sum", fn = function() return terra_sum_i32(xs, n) end },
    { name = "terra zip_add", fn = function() terra_zip_add_i32(out, xs, ys, n); return checksum(out) end },
    { name = "terra fused_reduce", fn = function() return terra_fused_reduce_i32(xs, ys, bias, n) end },
    { name = "terra scan", fn = function() terra_scan_sum_i32(out, xs, n); return checksum(out) end },
    { name = "terra scatter_reduce", fn = function() clear_bins(); terra_scatter_reduce_add_i32(bins, xs, idx, n); return checksum(bins) end },
}

print(string.format("Terra source-shape benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
print(string.format("%-34s median=%8.3fms", "terra compile", compile_time * 1000))
for _, item in ipairs(cases) do
    local values, result = measure(item.fn)
    print(stats_line(item.name, values) .. " result=" .. tostring(result))
end
