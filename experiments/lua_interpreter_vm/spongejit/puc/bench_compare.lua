#!/usr/bin/env luajit
-- Whole-program PUC comparison: vanilla interpreter vs SponJIT-enabled VM.

local source = debug.getinfo(1, "S").source
local this = source:sub(1, 1) == "@" and source:sub(2) or source
local spongejit = this:match("^(.*)/puc/bench_compare%.lua$") or "experiments/lua_interpreter_vm/spongejit"
local repo
if spongejit:sub(1, 1) == "/" then
    repo = spongejit:gsub("/experiments/lua_interpreter_vm/spongejit$", "")
else
    repo = "."
end

local function q(s) return "'" .. tostring(s):gsub("'", [['"'"']]) .. "'" end
local function run(cmd)
    local ok = os.execute(cmd)
    if ok ~= true and ok ~= 0 then return false end
    return true
end
local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local function write(path, data)
    local f = assert(io.open(path, "wb"), path); f:write(data); f:close()
end
local function mkdir_p(path) run("mkdir -p " .. q(path)) end

local opts = { reps = 5, build = false }
local positional = {}
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--reps" then opts.reps = tonumber(arg[i + 1]) or opts.reps; i = i + 1
    elseif a == "--build" then opts.build = true
    elseif a == "--" then
        for j = i + 1, #arg do positional[#positional + 1] = arg[j] end
        break
    else positional[#positional + 1] = a end
    i = i + 1
end

local baseline_lua = spongejit .. "/build/puc_baseline/lua"
local sponjit_lua = spongejit .. "/build/puc_sponjit/lua"
if opts.build or not read(baseline_lua) or not read(sponjit_lua) then
    assert(run("cd " .. q(repo) .. " && luajit " .. q(spongejit .. "/puc/build_sponjit_puc.lua")), "build failed")
end

local program = positional[1] or (spongejit .. "/bench/programs/int_loop.lua")
local prog_args = {}
for j = 2, #positional do prog_args[#prog_args + 1] = positional[j] end
if #prog_args == 0 and not positional[1] then prog_args[1] = "50000000" end

local out_dir = spongejit .. "/build/bench_compare"
mkdir_p(out_dir)

local function stat_parse(path)
    local s = read(path) or ""
    local totals = { seen = 0, attempts = 0, hits = 0, exits = 0, rows = {}, dispatch_entries = 0, absorbed_ops = 0, cache_probes = 0, cache_hits = 0 }
    for line in s:gmatch("[^\n]+") do
        local key, val = line:match("^#%s+([^	]+)	(%d+)")
        if key then
            totals[key] = tonumber(val) or 0
        elseif not line:match("^opcode\t") then
            local op, name, seen, attempts, hits, exits = line:match("^(%d+)	([^	]+)	(%d+)	(%d+)	(%d+)	(%d+)")
            if op then
                local row = { op = tonumber(op), name = name, seen = tonumber(seen), attempts = tonumber(attempts), hits = tonumber(hits), exits = tonumber(exits) }
                totals.rows[#totals.rows + 1] = row
                totals.seen = totals.seen + row.seen
                totals.attempts = totals.attempts + row.attempts
                totals.hits = totals.hits + row.hits
                totals.exits = totals.exits + row.exits
            end
        end
    end
    table.sort(totals.rows, function(a, b) return (a.hits or 0) > (b.hits or 0) end)
    return totals
end

local function run_one(kind, exe, rep, collect_stats)
    local tfile = string.format("%s/%s_%02d.time", out_dir, kind, rep)
    local ofile = string.format("%s/%s_%02d.out", out_dir, kind, rep)
    local efile = string.format("%s/%s_%02d.err", out_dir, kind, rep)
    local sfile = string.format("%s/%s_%02d.stats", out_dir, kind, rep)
    local env = ""
    if kind:match("^sponjit") then
        env = "SPONJIT_ENABLE=1 SPONJIT_PRINT=0 "
        if collect_stats then env = env .. "SPONJIT_STATS=" .. q(sfile) .. " " end
    end
    local cmd = env .. q(exe) .. " " .. q(program)
    for _, a in ipairs(prog_args) do cmd = cmd .. " " .. q(a) end
    local shell = string.format("/usr/bin/time -f '%%e' -o %s sh -c %s > %s 2> %s",
        q(tfile), q(cmd), q(ofile), q(efile))
    assert(run(shell), kind .. " run failed; stderr=" .. tostring(read(efile)))
    local time_s = tonumber((read(tfile) or ""):match("([%d%.]+)")) or 0
    return { time = time_s, out = read(ofile) or "", err = read(efile) or "", stats_path = sfile, stats = stat_parse(sfile) }
end

local base_runs, jit_runs = {}, {}
for r = 1, opts.reps do
    base_runs[r] = run_one("baseline", baseline_lua, r, false)
    jit_runs[r] = run_one("sponjit", sponjit_lua, r, false)
    if base_runs[r].out ~= jit_runs[r].out then
        error("output mismatch on rep " .. r .. "\nbaseline=" .. base_runs[r].out .. "\nsponjit=" .. jit_runs[r].out)
    end
end

local function stats(xs)
    local sum, min, max = 0, math.huge, 0
    for _, x in ipairs(xs) do sum = sum + x.time; if x.time < min then min = x.time end; if x.time > max then max = x.time end end
    return { avg = sum / #xs, min = min, max = max }
end
local bs, js = stats(base_runs), stats(jit_runs)
local speedup = bs.avg / js.avg

print("# SponJIT whole-program comparison")
print("program: " .. program .. (#prog_args > 0 and (" " .. table.concat(prog_args, " ")) or ""))
print(string.format("reps: %d", opts.reps))
print(string.format("baseline_avg_sec: %.6f min=%.6f max=%.6f", bs.avg, bs.min, bs.max))
print(string.format("sponjit_avg_sec:  %.6f min=%.6f max=%.6f", js.avg, js.min, js.max))
print(string.format("speedup: %.3fx", speedup))

-- Collect stats in a separate non-timed run so instrumentation counters do not
-- contaminate the timing measurement.
local stats_run = run_one("sponjit_stats", sponjit_lua, 1, true)
if base_runs[1].out ~= stats_run.out then
    error("stats run output mismatch\nbaseline=" .. base_runs[1].out .. "\nstats=" .. stats_run.out)
end
local st = stats_run.stats
local dispatch_entries = st.dispatch_entries or st.seen
print(string.format("sponjit_dispatch_entries=%d cache_probes=%d cache_hits=%d absorbed_ops=%d hit_rate=%.2f%%",
    dispatch_entries, st.cache_probes or 0, st.cache_hits or 0, st.absorbed_ops or 0,
    (st.cache_probes or 0) > 0 and (100 * (st.cache_hits or 0) / (st.cache_probes or 1)) or 0))
print("top_executed_opcodes:")
for k = 1, math.min(12, #st.rows) do
    local r = st.rows[k]
    if r.hits > 0 then
        print(string.format("  %-12s dispatch_entries=%d attempts=%d semantic_exec=%d exits=%d", r.name, r.seen, r.attempts, r.hits, r.exits))
    end
end
print("artifacts: " .. out_dir)
