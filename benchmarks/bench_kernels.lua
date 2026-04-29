-- Moonlift vs Terra runtime benchmark kernels.
-- Emits machine-readable lines consumed by run_vs_terra.sh.

package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
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
local WARMUP = tonumber(os.getenv("MOONLIFT2_BENCH_WARMUP") or (quick and "1" or "3"))
local ITERS = tonumber(os.getenv("MOONLIFT2_BENCH_ITERS") or (quick and "2" or "7"))

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

export func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
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

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local B2 = T.Moon2Back

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

local sum_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sum_i32")))
local dot_i32 = ffi.cast("int32_t (*)(const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("dot_i32")))
local add_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("add_i32")))
local scale_i32 = ffi.cast("int32_t (*)(int32_t*, const int32_t*, int32_t, int32_t)", artifact:getpointer(B2.BackFuncId("scale_i32")))

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

io.write(string.format("moonlift_compile %.9f 0\n", compile_time))
io.write(string.format("moonlift_sum_i32 %.9f %s\n", sum_t, result_string(sum_i32(a, N))))
io.write(string.format("moonlift_dot_i32 %.9f %s\n", dot_t, result_string(dot_i32(a, b, N))))
io.write(string.format("moonlift_add_i32 %.9f %s\n", add_t, result_string(add_check)))
io.write(string.format("moonlift_scale_i32 %.9f %s\n", scale_t, result_string(scale_check)))

if os.getenv("MOONLIFT2_BENCH_DISASM") == "1" then
    io.stderr:write(artifact:disasm("sum_i32", { bytes = 260 }) .. "\n")
    io.stderr:write(artifact:disasm("dot_i32", { bytes = 320 }) .. "\n")
    io.stderr:write(artifact:disasm("add_i32", { bytes = 320 }) .. "\n")
    io.stderr:write(artifact:disasm("scale_i32", { bytes = 320 }) .. "\n")
end

artifact:free()
