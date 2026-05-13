package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

io.stdout:setvbuf("no")

local mode = arg and arg[1] or nil
local quick = mode == "quick"

local N = tonumber(os.getenv("MOONLIFT_BENCH_N") or (quick and "262144" or "1048576"))
local STRIDE = tonumber(os.getenv("MOONLIFT_BENCH_STRIDE") or "2")

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
    { kernel = "fib", sig = "int32_t (*)(int32_t)", run = function(f) return f(N) end },
    { kernel = "sum", sig = "int32_t (*)(const int32_t*, int32_t, int32_t)", run = function(f) return f(a, N, STRIDE) end },
    { kernel = "dot", sig = "int32_t (*)(const int32_t*, const int32_t*, int32_t, int32_t)", run = function(f) return f(a, b, N, STRIDE) end },
    { kernel = "fill", sig = "int32_t (*)(int32_t*, int32_t, int32_t, int32_t)", run = function(f) return f(out, N, STRIDE, 123) end },
    { kernel = "sumsq", sig = "int32_t (*)(const int32_t*, int32_t)", run = function(f) return f(a, N) end },
    { kernel = "hash", sig = "int32_t (*)(const uint8_t*, int32_t)", run = function(f) return f(hashdata, 64) end },
    { kernel = "findmax", sig = "int32_t (*)(const int32_t*, int32_t)", run = function(f) return f(a, N) end },
}

local fn = assert(Run.loadfile("benchmarks/bench_kernels.mlua"))
local kernels = fn()

for _, c in ipairs(CASES) do
    io.write("PROBE begin " .. c.kernel .. "\n")
    local k = assert(kernels[c.kernel], "missing kernel: " .. tostring(c.kernel))
    local compiled = k:compile()
    local f = ffi.cast(c.sig, compiled.fn)
    local _ = c.run(f)
    compiled:free()
    io.write("PROBE ok " .. c.kernel .. "\n")
end

io.write("PROBE done\n")
