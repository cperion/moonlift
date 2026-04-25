-- Moonlift scalar kernel benchmark for comparison against Terra.
-- Run from repo root after building the shared library:
--   cargo build --manifest-path moonlift/Cargo.toml --release
--   luajit moonlift/benchmarks/bench_moonlift.lua [quick]

package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local Source = require("moonlift.source")
local Jit = require("moonlift.jit")

local unpack = unpack or table.unpack
local mode = arg and arg[1] or nil
local quick = mode == "quick"

local WARMUP = tonumber(os.getenv("MOONLIFT_BENCH_WARMUP") or (quick and "1" or "3"))
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (quick and "1" or "5"))

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
    local s = tostring(v)
    s = s:gsub("ULL$", ""):gsub("LL$", "")
    return s
end

local SOURCE = [[
export func sum_loop(n: i64) -> i64
    while i < n with i: i64 = 0, acc: i64 = 0 do
        let ip1: i64 = i + 1
        let term: i64 = (ip1 * 1664525 + 1013904223) & 1023
        next i = ip1
        next acc = acc + term
    end
    return acc
end

export func collatz_sum(n: i64) -> i64
    while x < n with x: i64 = 1, total: i64 = 0 do
        while c ~= 1 with c: i64 = x, steps: i64 = 0 do
            let even: bool = (c % 2) == 0
            let next_c: i64 = if even then c / 2 else c * 3 + 1 end
            next c = next_c
            next steps = steps + 1
        end
        next x = x + 1
        next total = total + steps
    end
    return total
end

export func mandelbrot_sum(width: i32, height: i32, max_iter: i32) -> i64
    while py < height with py: i32 = 0, total: i64 = 0 do
        while px < width with px: i32 = 0, row_total: i64 = 0 do
            let x0: f64 = (cast<f64>(px) / cast<f64>(width)) * 3.5 - 2.5
            let y0: f64 = (cast<f64>(py) / cast<f64>(height)) * 2.0 - 1.0
            while x * x + y * y < 4.0 and iter < max_iter with x: f64 = 0.0, y: f64 = 0.0, iter: i32 = 0 do
                let xtemp: f64 = x * x - y * y + x0
                let ynext: f64 = 2.0 * x * y + y0
                next x = xtemp
                next y = ynext
                next iter = iter + 1
            end
            next px = px + 1
            next row_total = row_total + cast<i64>(iter)
        end
        next py = py + 1
        next total = total + row_total
    end
    return total
end

export func poly_eval_grid(n: i32) -> f64
    while i < n with i: i32 = 0, total: f64 = 0.0 do
        let x: f64 = cast<f64>(i) / cast<f64>(n)
        while j < n with j: i32 = 0, row_total: f64 = 0.0 do
            let y: f64 = cast<f64>(j) / cast<f64>(n)
            let r: f64 = 3.0*x*x*x + 2.0*x*x*y - x*y*y + y*y*y
            next j = j + 1
            next row_total = row_total + r
        end
        next i = i + 1
        next total = total + row_total
    end
    return total
end

export func popcount_sum(n: i64) -> i64
    while i < n with i: i64 = 0, total: i64 = 0 do
        while x ~= 0 with x: i64 = i, bits: i64 = 0 do
            let bit: i64 = x & 1
            next x = x >>> 1
            next bits = bits + bit
        end
        next i = i + 1
        next total = total + bits
    end
    return total
end

export func fib_sum(n: i64) -> i64
    while k < n with k: i64 = 1, total: i64 = 0 do
        let limit: i64 = k % 90
        while i < limit with a: i64 = 0, b: i64 = 1, i: i64 = 0 do
            let c: i64 = a + b
            next a = b
            next b = c
            next i = i + 1
        end
        next k = k + 1
        next total = total + b
    end
    return total
end

export func gcd_sum(n: i64) -> i64
    while i < n with i: i64 = 1, total: i64 = 0 do
        let j_stop: i64 = i + 16
        while j < j_stop with j: i64 = i + 1, row_total: i64 = 0 do
            while b ~= 0 with a: i64 = i, b: i64 = j do
                let t: i64 = b
                let next_b: i64 = a % b
                next a = t
                next b = next_b
            end
            next j = j + 1
            next row_total = row_total + a
        end
        next i = i + 1
        next total = total + row_total
    end
    return total
end

export func switch_sum(n: i64) -> i64
    while i < n with i: i64 = 0, acc: i64 = 0 do
        let r: i64 = i % 7
        let inc: i64 = switch r do
        case 0 then
            1
        case 1 then
            3
        case 2 then
            5
        case 3 then
            7
        case 4 then
            11
        case 5 then
            13
        default then
            17
        end
        next i = i + 1
        next acc = acc + inc
    end
    return acc
end
]]

local T = pvm.context()
A.Define(T)
local S = Source.Define(T)
local jit = Jit.Define(T).jit()

local t_compile0 = os.clock()
local artifact = S.compile(SOURCE, nil, nil, nil, jit)
local t_compile1 = os.clock()

local Back = T.MoonliftBack
local function fn(name, cdecl)
    return ffi.cast(cdecl, artifact:getpointer(Back.BackFuncId(name)))
end

local cases = {
    { name = "sum_loop",       cdecl = "int64_t (*)(int64_t)",                    args = { quick and 1000000LL or 100000000LL }, float = false },
    { name = "collatz_sum",    cdecl = "int64_t (*)(int64_t)",                    args = { quick and 50000LL or 5000000LL }, float = false },
    { name = "mandelbrot_sum", cdecl = "int64_t (*)(int32_t, int32_t, int32_t)",   args = quick and { 64, 64, 64 } or { 512, 512, 256 }, float = false },
    { name = "poly_eval_grid", cdecl = "double (*)(int32_t)",                     args = { quick and 120 or 1000 }, float = true },
    { name = "popcount_sum",   cdecl = "int64_t (*)(int64_t)",                    args = { quick and 200000LL or 10000000LL }, float = false },
    { name = "fib_sum",        cdecl = "int64_t (*)(int64_t)",                    args = { quick and 20000LL or 1000000LL }, float = false },
    { name = "gcd_sum",        cdecl = "int64_t (*)(int64_t)",                    args = { quick and 20000LL or 500000LL }, float = false },
    { name = "switch_sum",     cdecl = "int64_t (*)(int64_t)",                    args = { quick and 1000000LL or 50000000LL }, float = false },
}

io.write(string.format("COMPILE_ALL %.9f\n", t_compile1 - t_compile0))
for _, case in ipairs(cases) do
    case.f = fn(case.name, case.cdecl)
    local t = bench(case.f, unpack(case.args))
    local r = case.f(unpack(case.args))
    io.write(string.format("%s %.9f %s\n", case.name, t, result_string(r, case.float)))
end

artifact:free()
