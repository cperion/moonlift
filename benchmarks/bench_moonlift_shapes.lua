-- Moonlift-shaped scalar benchmarks.
--
-- This is NOT a Terra head-to-head. It compares equivalent Moonlift kernels
-- written with generic control/arithmetic against kernels written with explicit
-- Moonlift code-shape constructs (`for` domains, `switch`, `select`, intrinsics).
--
-- Run from repo root after building the shared library:
--   cargo build --manifest-path moonlift/Cargo.toml --release
--   luajit moonlift/benchmarks/bench_moonlift_shapes.lua [quick] [disasm <func>]

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
local quick = (arg and arg[1]) == "quick"
local disasm_func = nil
if arg then
    if arg[1] == "disasm" then
        disasm_func = arg[2]
    elseif arg[2] == "disasm" then
        disasm_func = arg[3]
    end
end
local WARMUP = tonumber(os.getenv("MOONLIFT_SHAPE_WARMUP") or (quick and "1" or "3"))
local ITERS = tonumber(os.getenv("MOONLIFT_SHAPE_ITERS") or (quick and "1" or "5"))

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
    return (s:gsub("ULL$", ""):gsub("LL$", ""))
end

local SOURCE = [[
export func sum_while_index(n: index) -> index
    while i < n with i: index = 0, acc: index = 0 do
        let term: index = (i * 1664525 + 1013904223) & 1023
        next i = i + 1
        next acc = acc + term
    end
    return acc
end

export func sum_for_index(n: index) -> index
    for i in 0..n with acc: index = 0 do
        let term: index = (i * 1664525 + 1013904223) & 1023
        next acc = acc + term
    end
    return acc
end

export func collatz_if(n: i64) -> i64
    while x < n with x: i64 = 1, total: i64 = 0 do
        while c ~= 1 with c: i64 = x, steps: i64 = 0 do
            let next_c: i64 = if c % 2 == 0 then c / 2 else c * 3 + 1 end
            next c = next_c
            next steps = steps + 1
        end
        next x = x + 1
        next total = total + steps
    end
    return total
end

export func collatz_select(n: i64) -> i64
    while x < n with x: i64 = 1, total: i64 = 0 do
        while c ~= 1 with c: i64 = x, steps: i64 = 0 do
            let next_c: i64 = select(c % 2 == 0, c / 2, c * 3 + 1)
            next c = next_c
            next steps = steps + 1
        end
        next x = x + 1
        next total = total + steps
    end
    return total
end

export func mandelbrot_while_i32(width: i32, height: i32, max_iter: i32) -> i64
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

export func mandelbrot_for_index(width: index, height: index, max_iter: i32) -> i64
    for py in 0..height with total: i64 = 0 do
        for px in 0..width with row_total: i64 = 0 do
            let x0: f64 = (cast<f64>(px) / cast<f64>(width)) * 3.5 - 2.5
            let y0: f64 = (cast<f64>(py) / cast<f64>(height)) * 2.0 - 1.0
            while x * x + y * y < 4.0 and iter < max_iter with x: f64 = 0.0, y: f64 = 0.0, iter: i32 = 0 do
                let xtemp: f64 = x * x - y * y + x0
                let ynext: f64 = 2.0 * x * y + y0
                next x = xtemp
                next y = ynext
                next iter = iter + 1
            end
            next row_total = row_total + cast<i64>(iter)
        end
        next total = total + row_total
    end
    return total
end

export func poly_while_i32(n: i32) -> f64
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

export func poly_for_index(n: index) -> f64
    for i in 0..n with total: f64 = 0.0 do
        let x: f64 = cast<f64>(i) / cast<f64>(n)
        for j in 0..n with row_total: f64 = 0.0 do
            let y: f64 = cast<f64>(j) / cast<f64>(n)
            let r: f64 = 3.0*x*x*x + 2.0*x*x*y - x*y*y + y*y*y
            next row_total = row_total + r
        end
        next total = total + row_total
    end
    return total
end

export func popcount_manual_sum(n: u64) -> u64
    while i < n with i: u64 = 0, total: u64 = 0 do
        while x ~= 0 with x: u64 = i, bits: u64 = 0 do
            let bit: u64 = x & 1
            next x = x >>> 1
            next bits = bits + bit
        end
        next i = i + 1
        next total = total + bits
    end
    return total
end

export func popcount_intrinsic_sum(n: u64) -> u64
    while i < n with i: u64 = 0, total: u64 = 0 do
        next i = i + 1
        next total = total + popcount(i)
    end
    return total
end

export func fib_while_i64(n: i64) -> i64
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

export func fib_for_index(n: index) -> i64
    for k in 1..n with total: i64 = 0 do
        let limit: index = k % 90
        for i in 0..limit with a: i64 = 0, b: i64 = 1 do
            let c: i64 = a + b
            next a = b
            next b = c
        end
        next total = total + b
    end
    return total
end

export func gcd_while_i64(n: i64) -> i64
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

export func gcd_for_index(n: index) -> index
    for i in 1..n with total: index = 0 do
        let j_stop: index = i + 16
        for j in i + 1..j_stop with row_total: index = 0 do
            while b ~= 0 with a: index = i, b: index = j do
                let t: index = b
                let next_b: index = a % b
                next a = t
                next b = next_b
            end
            next row_total = row_total + a
        end
        next total = total + row_total
    end
    return total
end

export func switch_if_chain(n: i64) -> i64
    while i < n with i: i64 = 0, acc: i64 = 0 do
        let r: i64 = i % 7
        var inc: i64 = 17
        if r == 0 then
            inc = 1
        end
        if r == 1 then
            inc = 3
        end
        if r == 2 then
            inc = 5
        end
        if r == 3 then
            inc = 7
        end
        if r == 4 then
            inc = 11
        end
        if r == 5 then
            inc = 13
        end
        next i = i + 1
        next acc = acc + inc
    end
    return acc
end

export func switch_expr_sum(n: i64) -> i64
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
local artifact = S.compile(SOURCE, nil, nil, nil, jit)
local Back = T.MoonliftBack

if disasm_func ~= nil then
    print(artifact:disasm(disasm_func, { bytes = tonumber(os.getenv("MOONLIFT_DISASM_BYTES") or "240") }))
    artifact:free()
    os.exit(0)
end

local function fn(name, cdecl)
    return ffi.cast(cdecl, artifact:getpointer(Back.BackFuncId(name)))
end

local n_sum = quick and 1000000 or 100000000
local n_collatz = quick and 50000LL or 5000000LL
local dims = quick and { 64, 64, 64 } or { 512, 512, 256 }
local n_poly = quick and 120 or 1000
local n_pop = quick and 200000ULL or 10000000ULL
local n_fib_i64 = quick and 20000LL or 1000000LL
local n_fib_index = quick and 20000 or 1000000
local n_gcd_i64 = quick and 20000LL or 500000LL
local n_gcd_index = quick and 20000 or 500000
local n_switch = quick and 1000000LL or 50000000LL

local groups = {
    {
        label = "sum range domain",
        base = { name = "sum_while_index", cdecl = "intptr_t (*)(intptr_t)", args = { n_sum }, float = false },
        shaped = { name = "sum_for_index", cdecl = "intptr_t (*)(intptr_t)", args = { n_sum }, float = false },
    },
    {
        label = "collatz select",
        base = { name = "collatz_if", cdecl = "int64_t (*)(int64_t)", args = { n_collatz }, float = false },
        shaped = { name = "collatz_select", cdecl = "int64_t (*)(int64_t)", args = { n_collatz }, float = false },
    },
    {
        label = "mandelbrot range",
        base = { name = "mandelbrot_while_i32", cdecl = "int64_t (*)(int32_t, int32_t, int32_t)", args = dims, float = false },
        shaped = { name = "mandelbrot_for_index", cdecl = "int64_t (*)(intptr_t, intptr_t, int32_t)", args = dims, float = false },
    },
    {
        label = "poly range",
        base = { name = "poly_while_i32", cdecl = "double (*)(int32_t)", args = { n_poly }, float = true },
        shaped = { name = "poly_for_index", cdecl = "double (*)(intptr_t)", args = { n_poly }, float = true },
    },
    {
        label = "popcount intrinsic",
        base = { name = "popcount_manual_sum", cdecl = "uint64_t (*)(uint64_t)", args = { n_pop }, float = false },
        shaped = { name = "popcount_intrinsic_sum", cdecl = "uint64_t (*)(uint64_t)", args = { n_pop }, float = false },
    },
    {
        label = "fib range domain",
        base = { name = "fib_while_i64", cdecl = "int64_t (*)(int64_t)", args = { n_fib_i64 }, float = false },
        shaped = { name = "fib_for_index", cdecl = "int64_t (*)(intptr_t)", args = { n_fib_index }, float = false },
    },
    {
        label = "gcd range domain",
        base = { name = "gcd_while_i64", cdecl = "int64_t (*)(int64_t)", args = { n_gcd_i64 }, float = false },
        shaped = { name = "gcd_for_index", cdecl = "intptr_t (*)(intptr_t)", args = { n_gcd_index }, float = false },
    },
    {
        label = "switch structure",
        base = { name = "switch_if_chain", cdecl = "int64_t (*)(int64_t)", args = { n_switch }, float = false },
        shaped = { name = "switch_expr_sum", cdecl = "int64_t (*)(int64_t)", args = { n_switch }, float = false },
    },
}

print("Moonlift-shaped scalar benchmark")
print("mode " .. (quick and "quick" or "default"))
print(string.format("%-22s %-24s %10s %-24s %10s %9s  %s", "shape", "generic", "time", "moonlift-shaped", "time", "speedup", "result"))
print(string.format("%-22s %-24s %10s %-24s %10s %9s  %s", "----------------------", "------------------------", "----------", "------------------------", "----------", "---------", "------"))

for _, group in ipairs(groups) do
    local base = group.base
    local shaped = group.shaped
    base.f = fn(base.name, base.cdecl)
    shaped.f = fn(shaped.name, shaped.cdecl)
    local tb = bench(base.f, unpack(base.args))
    local ts = bench(shaped.f, unpack(shaped.args))
    local rb = base.f(unpack(base.args))
    local rs = shaped.f(unpack(shaped.args))
    local ok = result_string(rb, base.float) == result_string(rs, shaped.float) and "ok" or (result_string(rb, base.float) .. " != " .. result_string(rs, shaped.float))
    print(string.format("%-22s %-24s %7.3f ms %-24s %7.3f ms %8.2fx  %s",
        group.label,
        base.name,
        tb * 1000,
        shaped.name,
        ts * 1000,
        tb / ts,
        ok))
end

artifact:free()
