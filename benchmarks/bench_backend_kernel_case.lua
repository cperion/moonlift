package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

io.stdout:setvbuf("no")

local kernel = assert(arg and arg[1], "usage: luajit bench_backend_kernel_case.lua <kernel> [quick|full]")
local mode = arg and arg[2] or nil
local quick = mode == "quick"

local N = tonumber(os.getenv("MOONLIFT_BENCH_N") or (quick and "262144" or "1048576"))
local STRIDE = tonumber(os.getenv("MOONLIFT_BENCH_STRIDE") or "2")
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (quick and "3" or "5"))
local WARMUP = tonumber(os.getenv("MOONLIFT_BENCH_WARMUP") or (quick and "2" or "4"))

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

local a, b, out = fill_arrays(N, STRIDE)
local hashdata = ffi.new("uint8_t[64]")
for i = 0, 63 do hashdata[i] = (i * 7 + 13) % 256 end

local CASES = {
    fib = {
        key = "fib", sig = "int32_t (*)(int32_t)",
        run = function(f) return f(N) end,
    },
    sum = {
        key = "sum", sig = "int32_t (*)(const int32_t*, int32_t, int32_t)",
        run = function(f) return f(a, N, STRIDE) end,
    },
    dot = {
        key = "dot", sig = "int32_t (*)(const int32_t*, const int32_t*, int32_t, int32_t)",
        run = function(f) return f(a, b, N, STRIDE) end,
    },
    fill = {
        key = "fill", sig = "int32_t (*)(int32_t*, int32_t, int32_t, int32_t)",
        run = function(f)
            local _ = f(out, N, STRIDE, 123)
            return out[0] + out[(N - 1) * STRIDE]
        end,
    },
    sumsq = {
        key = "sumsq", sig = "int32_t (*)(const int32_t*, int32_t)",
        run = function(f) return f(a, N) end,
    },
    hash = {
        key = "hash", sig = "int32_t (*)(const uint8_t*, int32_t)",
        run = function(f) return f(hashdata, 64) end,
    },
    findmax = {
        key = "findmax", sig = "int32_t (*)(const int32_t*, int32_t)",
        run = function(f) return f(a, N) end,
    },
}

local case = assert(CASES[kernel], "unknown kernel: " .. tostring(kernel))

local fn, runtime = Run.loadfile("benchmarks/bench_kernels.mlua")
local kernels = fn()
local k = assert(kernels[case.key], "missing kernel in module: " .. case.key)

local t0 = os.clock()
local compiled = k:compile()
local compile_t = os.clock() - t0

local f = ffi.cast(case.sig, compiled.fn)
local runtime_t, check = best_of(function() return case.run(f) end)

compiled:free()

io.write(string.format("RESULT kernel=%s compile=%.9f runtime=%.9f check=%s\n",
    kernel, compile_t, runtime_t, tostring(check)))
