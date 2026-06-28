local ffi = require("ffi")

ffi.cdef [[
typedef long time_t;
struct timespec { time_t tv_sec; long tv_nsec; };
int clock_gettime(int clk_id, struct timespec *tp);
]]

local CLOCK_MONOTONIC = 1
local ts = ffi.new("struct timespec[1]")

local M = {}

function M.now()
    if ffi.C.clock_gettime(CLOCK_MONOTONIC, ts) == 0 then
        return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) * 1e-9
    end
    return os.clock()
end

function M.stats(samples)
    table.sort(samples)
    local n = #samples
    local sum = 0
    for i = 1, n do sum = sum + samples[i] end
    return {
        min = samples[1] or 0,
        median = samples[math.floor((n + 1) / 2)] or 0,
        avg = n > 0 and sum / n or 0,
        max = samples[n] or 0,
    }
end

local function empty_trace_stats()
    return {
        start = 0,
        stop = 0,
        abort = 0,
        flush = 0,
        root = 0,
        side = 0,
        abort_reasons = {},
    }
end

local function trace_callback(stats)
    return function(what, tr, func, pc, otr, oex)
        if what == "start" then
            stats.start = stats.start + 1
            if otr ~= nil then
                stats.side = stats.side + 1
            else
                stats.root = stats.root + 1
            end
        elseif what == "stop" then
            stats.stop = stats.stop + 1
        elseif what == "abort" then
            stats.abort = stats.abort + 1
            local reason = tostring(otr or oex or pc or "unknown")
            stats.abort_reasons[reason] = (stats.abort_reasons[reason] or 0) + 1
        elseif what == "flush" then
            stats.flush = stats.flush + 1
        end
    end
end

function M.measure_case(case)
    assert(type(case) == "table", "measure_case expects a case table")
    assert(type(case.name) == "string", "measure_case requires case.name")
    assert(type(case.fn) == "function", "measure_case requires case.fn")

    local sample_count = tonumber(case.samples or 7)
    local rounds = tonumber(case.rounds or 1)
    local warmup = tonumber(case.warmup or 2)
    local flush = case.flush ~= false
    local opts = case.jit_opts or { "hotloop=3", "hotexit=2" }

    jit.on()
    if opts and #opts > 0 then jit.opt.start(unpack(opts)) end
    if flush then jit.flush() end

    for _ = 1, warmup do
        case.fn()
    end
    if flush then jit.flush() end

    local trace = empty_trace_stats()
    local cb = trace_callback(trace)
    local times = {}
    local values = {}
    local run_ok, run_err

    jit.attach(cb, "trace")
    run_ok, run_err = pcall(function()
    for i = 1, sample_count do
        local t0 = M.now()
        local value
        for _ = 1, rounds do
            value = case.fn()
        end
        values[i] = value
        times[i] = (M.now() - t0) / rounds
    end
    end)
    jit.attach(cb)
    if not run_ok then error(run_err, 0) end

    local first = values[1]
    for i = 2, #values do
        assert(values[i] == first, "unstable benchmark result for " .. case.name)
    end

    return {
        name = case.name,
        seconds = M.stats(times),
        trace = trace,
        result = first,
        samples = #times,
        rounds = rounds,
        warmup = warmup,
    }
end

function M.measure(cases, opts)
    opts = opts or {}
    local out = {}
    for i = 1, #cases do
        local case = cases[i]
        if opts.samples ~= nil then case.samples = opts.samples end
        if opts.rounds ~= nil then case.rounds = opts.rounds end
        if opts.warmup ~= nil then case.warmup = opts.warmup end
        if opts.jit_opts ~= nil then case.jit_opts = opts.jit_opts end
        out[i] = M.measure_case(case)
    end
    return out
end

function M.format_result(result)
    local s = result.seconds
    local tr = result.trace
    return string.format(
        "%-28s median=%8.3fms min=%8.3fms avg=%8.3fms traces start=%d stop=%d abort=%d root=%d side=%d result=%s",
        result.name,
        s.median * 1000,
        s.min * 1000,
        s.avg * 1000,
        tr.start,
        tr.stop,
        tr.abort,
        tr.root,
        tr.side,
        tostring(result.result)
    )
end

return M
