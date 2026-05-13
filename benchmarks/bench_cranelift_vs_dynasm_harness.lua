-- Benchmark harness: Cranelift vs DynASM, kernel-by-kernel in subprocesses.
--
-- This avoids whole-harness crashes (e.g. SIGSEGV) and reports exactly which
-- backend/kernel pair failed. It also runs an in-process sequence probe to
-- isolate state-leak crashes in backend pipelines.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local mode = arg and arg[1] or nil
local quick = mode == "quick"

local N = tonumber(os.getenv("MOONLIFT_BENCH_N") or (quick and "262144" or "1048576"))
local STRIDE = tonumber(os.getenv("MOONLIFT_BENCH_STRIDE") or "2")
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (quick and "3" or "5"))
local WARMUP = tonumber(os.getenv("MOONLIFT_BENCH_WARMUP") or (quick and "2" or "4"))

local BACKENDS = { "cranelift", "dynasm" }
local KERNELS = { "fib", "sum", "dot", "fill", "sumsq", "hash", "findmax" }

local function run_command(cmd)
    local p = io.popen(cmd .. " 2>&1")
    local out = p:read("*a")
    local ok, why, code = p:close()
    return out, ok, why, code
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function run_case(backend, kernel)
    local cmd = table.concat({
        "MOONLIFT_BACKEND=" .. backend,
        "MOONLIFT_BENCH_N=" .. tostring(N),
        "MOONLIFT_BENCH_STRIDE=" .. tostring(STRIDE),
        "MOONLIFT_BENCH_ITERS=" .. tostring(ITERS),
        "MOONLIFT_BENCH_WARMUP=" .. tostring(WARMUP),
        "luajit",
        "benchmarks/bench_backend_kernel_case.lua",
        shell_quote(kernel),
        shell_quote(quick and "quick" or "full"),
    }, " ")

    local out, ok, why, code = run_command(cmd)

    local result_line
    for line in out:gmatch("[^\n]+") do
        if line:match("^RESULT%s+") then result_line = line end
    end

    if ok and result_line then
        local k, ct, rt, ck = result_line:match("kernel=(%S+)%s+compile=([%d%.]+)%s+runtime=([%d%.]+)%s+check=(%S+)")
        if k and ct and rt and ck then
            return {
                status = "ok",
                kernel = k,
                compile = tonumber(ct),
                runtime = tonumber(rt),
                check = ck,
                output = out,
            }
        end
    end

    local status
    if why == "signal" then
        status = "signal:" .. tostring(code)
    elseif why == "exit" then
        status = "exit:" .. tostring(code)
    else
        status = "failed"
    end

    return {
        status = status,
        kernel = kernel,
        output = out,
    }
end

local function run_sequence_probe(backend)
    local cmd = table.concat({
        "MOONLIFT_BACKEND=" .. backend,
        "MOONLIFT_BENCH_N=" .. tostring(N),
        "MOONLIFT_BENCH_STRIDE=" .. tostring(STRIDE),
        "luajit",
        "benchmarks/bench_backend_sequence_probe.lua",
        shell_quote(quick and "quick" or "full"),
    }, " ")

    local out, ok, why, code = run_command(cmd)

    local last_begin, last_ok
    for line in out:gmatch("[^\n]+") do
        local kb = line:match("^PROBE begin%s+(%S+)$")
        if kb then last_begin = kb end
        local ko = line:match("^PROBE ok%s+(%S+)$")
        if ko then last_ok = ko end
    end

    local status
    if ok then
        status = "ok"
    elseif why == "signal" then
        status = "signal:" .. tostring(code)
    elseif why == "exit" then
        status = "exit:" .. tostring(code)
    else
        status = "failed"
    end

    local suspected = nil
    if status ~= "ok" then
        if last_begin and last_begin ~= last_ok then
            suspected = last_begin
        elseif last_ok then
            suspected = last_ok .. " (after ok, during teardown/next step)"
        else
            suspected = "unknown (crashed before first probe marker)"
        end
    end

    return {
        status = status,
        last_begin = last_begin,
        last_ok = last_ok,
        suspected_kernel = suspected,
        output = out,
    }
end

local results = {}
for _, b in ipairs(BACKENDS) do
    results[b] = {}
    for _, k in ipairs(KERNELS) do
        results[b][k] = run_case(b, k)
    end
end

io.write("Backend comparison (subprocess-isolated per kernel)\n")
io.write(string.format("N %d  STRIDE %d  ITERS %d  WARMUP %d\n\n", N, STRIDE, ITERS, WARMUP))
io.write(string.format("%-10s %-10s %-12s %-12s %-12s %-12s\n",
    "backend", "kernel", "status", "compile_s", "runtime_s", "check"))

for _, b in ipairs(BACKENDS) do
    for _, k in ipairs(KERNELS) do
        local r = results[b][k]
        if r.status == "ok" then
            io.write(string.format("%-10s %-10s %-12s %-12.9f %-12.9f %-12s\n",
                b, k, r.status, r.compile, r.runtime, r.check))
        else
            io.write(string.format("%-10s %-10s %-12s %-12s %-12s %-12s\n",
                b, k, r.status, "-", "-", "-"))
        end
    end
end

io.write("\nCross-backend runtime ratios (dynasm/cranelift, only where both OK)\n")
io.write(string.format("%-10s %-12s %-12s %-12s\n", "kernel", "cranelift_s", "dynasm_s", "d/c"))
for _, k in ipairs(KERNELS) do
    local c = results.cranelift[k]
    local d = results.dynasm[k]
    if c.status == "ok" and d.status == "ok" then
        io.write(string.format("%-10s %-12.9f %-12.9f %-12.3f\n",
            k, c.runtime, d.runtime, d.runtime / c.runtime))
    end
end

io.write("\nCheck agreement (cranelift vs dynasm)\n")
for _, k in ipairs(KERNELS) do
    local c = results.cranelift[k]
    local d = results.dynasm[k]
    if c.status == "ok" and d.status == "ok" then
        if c.check == d.check then
            io.write(string.format("  %s: OK (%s)\n", k, c.check))
        else
            io.write(string.format("  %s: MISMATCH cranelift=%s dynasm=%s\n", k, c.check, d.check))
        end
    end
end

io.write("\nIn-process sequence crash probe\n")
for _, b in ipairs(BACKENDS) do
    local p = run_sequence_probe(b)
    io.write(string.format("%s: %s\n", b, p.status))
    if p.status ~= "ok" then
        io.write(string.format("  last_begin=%s\n", tostring(p.last_begin)))
        io.write(string.format("  last_ok=%s\n", tostring(p.last_ok)))
        io.write(string.format("  suspected_kernel=%s\n", tostring(p.suspected_kernel)))
        if p.output and #p.output > 0 then
            local last_line = nil
            for line in p.output:gmatch("[^\n]+") do last_line = line end
            if last_line then
                io.write(string.format("  last_output=%s\n", last_line))
            end
        end
    end
end

