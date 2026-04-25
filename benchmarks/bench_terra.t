-- Terra side of the scalar kernel benchmark.
-- Run with:
--   terra moonlift/benchmarks/bench_terra.t [quick]

local mode = arg and arg[1] or nil
local quick = mode == "quick"
local WARMUP = tonumber(os.getenv("TERRA_BENCH_WARMUP") or (quick and "1" or "3"))
local ITERS = tonumber(os.getenv("TERRA_BENCH_ITERS") or (quick and "1" or "5"))

local function bench(f, ...)
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

local function result_string(v, is_float)
    if is_float then
        return string.format("%.12g", tonumber(v))
    end
    return string.format("%d", v)
end

local terra sum_loop(n: int64): int64
    var i: int64 = 0
    var acc: int64 = 0
    while i < n do
        var ip1: int64 = i + 1
        var term: int64 = (ip1 * 1664525 + 1013904223) and 1023
        i = ip1
        acc = acc + term
    end
    return acc
end

local terra collatz_sum(n: int64): int64
    var x: int64 = 1
    var total: int64 = 0
    while x < n do
        var c: int64 = x
        var steps: int64 = 0
        while c ~= 1 do
            if c % 2 == 0 then
                c = c / 2
            else
                c = c * 3 + 1
            end
            steps = steps + 1
        end
        x = x + 1
        total = total + steps
    end
    return total
end

local terra mandelbrot_sum(width: int32, height: int32, max_iter: int32): int64
    var py: int32 = 0
    var total: int64 = 0
    while py < height do
        var px: int32 = 0
        var row_total: int64 = 0
        while px < width do
            var x0: double = ([double](px) / [double](width)) * 3.5 - 2.5
            var y0: double = ([double](py) / [double](height)) * 2.0 - 1.0
            var x: double = 0.0
            var y: double = 0.0
            var iter: int32 = 0
            while (x * x + y * y) < 4.0 and iter < max_iter do
                var xtemp: double = x * x - y * y + x0
                var ynext: double = 2.0 * x * y + y0
                x = xtemp
                y = ynext
                iter = iter + 1
            end
            px = px + 1
            row_total = row_total + iter
        end
        py = py + 1
        total = total + row_total
    end
    return total
end

local terra poly_eval_grid(n: int32): double
    var i: int32 = 0
    var total: double = 0.0
    while i < n do
        var x: double = [double](i) / [double](n)
        var j: int32 = 0
        var row_total: double = 0.0
        while j < n do
            var y: double = [double](j) / [double](n)
            var r: double = 3.0*x*x*x + 2.0*x*x*y - x*y*y + y*y*y
            j = j + 1
            row_total = row_total + r
        end
        i = i + 1
        total = total + row_total
    end
    return total
end

local terra popcount_sum(n: int64): int64
    var i: int64 = 0
    var total: int64 = 0
    while i < n do
        var x: int64 = i
        var bits: int64 = 0
        while x ~= 0 do
            bits = bits + (x and 1)
            x = [uint64](x) >> 1
        end
        i = i + 1
        total = total + bits
    end
    return total
end

local terra fib_sum(n: int64): int64
    var k: int64 = 1
    var total: int64 = 0
    while k < n do
        var limit: int64 = k % 90
        var a: int64 = 0
        var b: int64 = 1
        var i: int64 = 0
        while i < limit do
            var c: int64 = a + b
            a = b
            b = c
            i = i + 1
        end
        k = k + 1
        total = total + b
    end
    return total
end

local terra gcd_sum(n: int64): int64
    var i: int64 = 1
    var total: int64 = 0
    while i < n do
        var j_stop: int64 = i + 16
        var j: int64 = i + 1
        var row_total: int64 = 0
        while j < j_stop do
            var a: int64 = i
            var b: int64 = j
            while b ~= 0 do
                var t: int64 = b
                var next_b: int64 = a % b
                a = t
                b = next_b
            end
            j = j + 1
            row_total = row_total + a
        end
        i = i + 1
        total = total + row_total
    end
    return total
end

local terra switch_sum(n: int64): int64
    var i: int64 = 0
    var acc: int64 = 0
    while i < n do
        var r: int64 = i % 7
        var inc: int64 = 17
        if r == 0 then
            inc = 1
        elseif r == 1 then
            inc = 3
        elseif r == 2 then
            inc = 5
        elseif r == 3 then
            inc = 7
        elseif r == 4 then
            inc = 11
        elseif r == 5 then
            inc = 13
        end
        i = i + 1
        acc = acc + inc
    end
    return acc
end

local funcs = {
    sum_loop,
    collatz_sum,
    mandelbrot_sum,
    poly_eval_grid,
    popcount_sum,
    fib_sum,
    gcd_sum,
    switch_sum,
}

local t_compile0 = os.clock()
for _, f in ipairs(funcs) do
    f:compile()
end
local t_compile1 = os.clock()

local cases = {
    { name = "sum_loop",       f = sum_loop,       args = { quick and 1000000 or 100000000 }, float = false },
    { name = "collatz_sum",    f = collatz_sum,    args = { quick and 50000 or 5000000 }, float = false },
    { name = "mandelbrot_sum", f = mandelbrot_sum, args = quick and { 64, 64, 64 } or { 512, 512, 256 }, float = false },
    { name = "poly_eval_grid", f = poly_eval_grid, args = { quick and 120 or 1000 }, float = true },
    { name = "popcount_sum",   f = popcount_sum,   args = { quick and 200000 or 10000000 }, float = false },
    { name = "fib_sum",        f = fib_sum,        args = { quick and 20000 or 1000000 }, float = false },
    { name = "gcd_sum",        f = gcd_sum,        args = { quick and 20000 or 500000 }, float = false },
    { name = "switch_sum",     f = switch_sum,     args = { quick and 1000000 or 50000000 }, float = false },
}

io.write(string.format("COMPILE_ALL %.9f\n", t_compile1 - t_compile0))
for _, bench_case in ipairs(cases) do
    local t = bench(bench_case.f, unpack(bench_case.args))
    local r = bench_case.f(unpack(bench_case.args))
    io.write(string.format("%s %.9f %s\n", bench_case.name, t, result_string(r, bench_case.float)))
end
