package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

local mode = arg and arg[1] or "quick"
local compile_reps = tonumber(os.getenv("MOONLIFT_BENCH_BACKEND_COMPILE_REPS") or (mode == "full" and "30" or "1"))
local runtime_calls = tonumber(os.getenv("MOONLIFT_BENCH_BACKEND_RUNTIME_CALLS") or (mode == "full" and "200000" or "1000"))
local inner_n = tonumber(os.getenv("MOONLIFT_BENCH_BACKEND_INNER_N") or (mode == "full" and "5000" or "100"))
local c_runner = os.getenv("MOONLIFT_BENCH_C_RUNNER") or "libtcc"
local cflags = os.getenv("MOONLIFT_BENCH_CFLAGS")

local cases = {
    {
        name = "sum_loop",
        src = [[func bench_sum_loop(n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        else
            jump loop(i = i + 1, acc = acc + i)
        end
    end
end]],
        func = "bench_sum_loop",
        args = function() return inner_n end,
    },
    {
        name = "ptr_sum",
        src = [[func bench_ptr_sum(p: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        else
            jump loop(i = i + 1, acc = acc + p[i])
        end
    end
end]],
        func = "bench_ptr_sum",
        setup = function()
            local arr = ffi.new("int32_t[?]", inner_n)
            for i = 0, inner_n - 1 do arr[i] = i % 17 end
            return arr
        end,
        args = function(arr) return arr, inner_n end,
    },
    {
        name = "view_sum",
        src = [[func bench_view_sum(p: ptr(i32), n: index) -> i32
    let v: view(i32) = view(p, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        else
            jump loop(i = i + 1, acc = acc + v[i])
        end
    end
end]],
        func = "bench_view_sum",
        setup = function()
            local arr = ffi.new("int32_t[?]", inner_n)
            for i = 0, inner_n - 1 do arr[i] = i % 19 end
            return arr
        end,
        args = function(arr) return arr, inner_n end,
    },
}

local function now()
    return os.clock()
end

local function ms(dt)
    return dt * 1000.0
end

local function compile_callable(case, backend)
    local f = moon.func(case.src)
    local opts
    if backend == "cranelift" then
        opts = { backend = "cranelift" }
    elseif backend == "c" then
        opts = { backend = "c", runner = c_runner, cflags = cflags }
    else
        error("unknown backend " .. tostring(backend))
    end
    local compiled = f:compile(opts)
    return f, compiled
end

local function bench_compile(case, backend)
    collectgarbage("collect")
    local total = 0
    for _ = 1, compile_reps do
        local t0 = now()
        local f, compiled = compile_callable(case, backend)
        total = total + (now() - t0)
        f:free()
        if compiled and compiled.free then compiled:free() end
    end
    return total / compile_reps
end

local function bench_runtime(case, backend)
    local state = case.setup and case.setup() or nil
    local f, compiled = compile_callable(case, backend)
    local args = { case.args(state) }
    local checksum = 0

    -- Warm up outside timing.
    for _ = 1, 10 do checksum = checksum + tonumber(compiled(unpack(args))) end

    collectgarbage("collect")
    local t0 = now()
    for _ = 1, runtime_calls do
        checksum = checksum + tonumber(compiled(unpack(args)))
    end
    local dt = now() - t0
    f:free()
    if compiled and compiled.free then compiled:free() end
    return dt, checksum
end

local function safe(label, fn)
    local ok, a, b = pcall(fn)
    if not ok then
        return nil, tostring(a)
    end
    return a, b
end

print(string.format("moonlift backend benchmark mode=%s compile_reps=%d runtime_calls=%d inner_n=%d c_runner=%s cflags=%s", mode, compile_reps, runtime_calls, inner_n, c_runner, tostring(cflags or "<default>")))
print("backend_compile_ms is source quote + frontend + backend compile")
print("runtime_us_per_call includes LuaJIT FFI call overhead; each call runs inner_n work in native code")
print("")

for _, case in ipairs(cases) do
    print("case " .. case.name)
    local cl_compile, cl_compile_err = safe("compile cranelift", function() return bench_compile(case, "cranelift") end)
    local c_compile, c_compile_err = safe("compile c", function() return bench_compile(case, "c") end)
    local cl_run, cl_checksum_or_err = safe("runtime cranelift", function() return bench_runtime(case, "cranelift") end)
    local c_run, c_checksum_or_err = safe("runtime c", function() return bench_runtime(case, "c") end)

    if cl_compile then
        print(string.format("  %-10s compile_ms=%9.3f", "cranelift", ms(cl_compile)))
    else
        print("  cranelift compile ERROR " .. tostring(cl_compile_err))
    end
    if c_compile then
        print(string.format("  %-10s compile_ms=%9.3f", "c/" .. c_runner, ms(c_compile)))
    else
        print("  c/" .. c_runner .. " compile ERROR " .. tostring(c_compile_err))
    end
    if cl_compile and c_compile then
        print(string.format("  compile_ratio_c_vs_cranelift=%.3f", c_compile / cl_compile))
    end

    if cl_run then
        print(string.format("  %-10s runtime_s=%9.6f us_per_call=%9.3f checksum=%d", "cranelift", cl_run, (cl_run / runtime_calls) * 1e6, cl_checksum_or_err))
    else
        print("  cranelift runtime ERROR " .. tostring(cl_checksum_or_err))
    end
    if c_run then
        print(string.format("  %-10s runtime_s=%9.6f us_per_call=%9.3f checksum=%d", "c/" .. c_runner, c_run, (c_run / runtime_calls) * 1e6, c_checksum_or_err))
    else
        print("  c/" .. c_runner .. " runtime ERROR " .. tostring(c_checksum_or_err))
    end
    if cl_run and c_run then
        print(string.format("  runtime_ratio_c_vs_cranelift=%.3f", c_run / cl_run))
    end
    print("")
end
