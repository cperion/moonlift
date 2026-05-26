#!/usr/bin/env luajit
-- harness.lua
-- CLI for SponJIT shadow economic validation.

local source = debug.getinfo(1, "S").source
local base = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*)/tools/sponjit_shadow/harness%.lua$") or "."
local root = base:gsub("/tools/sponjit_shadow$", "")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. root .. "/../../?.lua;" .. root .. "/../../?/init.lua;" .. root .. "/../../lua/?.lua;" .. root .. "/../../lua/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Util = require("tools.jit_harness.util")
local Workloads = require("tools.sponjit_shadow.workloads")
local Loader = require("tools.sponjit_shadow.loader")
local Sim = require("tools.sponjit_shadow.simulate")
local TimeSeries = require("tools.sponjit_shadow.timeseries")
local Report = require("tools.sponjit_shadow.report")
local Propose = require("tools.sponjit_shadow.propose")
local FoundryTrain = require("tools.sponjit_shadow.foundry_train")
local FoundryEnum = require("tools.sponjit_shadow.foundry_enumerate")
local Catalog = require("tools.sponjit_shadow.catalog")

local function parse(argv)
    local opts = { _ = {} }
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a:sub(1, 2) == "--" then
            local k, v = a:match("^%-%-([^=]+)=(.*)$")
            if not k then k = a:sub(3); v = argv[i + 1]; i = i + 1 end
            opts[k:gsub("-", "_")] = v
        else
            opts._[#opts._ + 1] = a
        end
        i = i + 1
    end
    return opts
end

local function load_workload(opts)
    if opts.input then
        local data = assert(Util.read_json(opts.input))
        if data.events then return data end
        return { name = opts.input, events = data }
    end
    return Workloads.get(opts.workload or opts._[2] or "method_dispatch_loop")
end

local function config_from_opts(opts)
    local cfg = Catalog.defaults({})
    for _, k in ipairs({ "interpreter_cost", "crossing_cost", "exit_cost", "materialization_cost", "code_size_penalty", "default_exit_prob", "max_window", "max_generations", "hysteresis_margin", "state_beam" }) do
        if opts[k] ~= nil then cfg[k] = tonumber(opts[k]) or opts[k] end
    end
    return cfg
end

local function write_foundry_report(result, out_dir)
    Util.mkdir_p(out_dir)
    Util.write_json(out_dir .. "/foundry_train.json", result)
    local md = { "# SponJIT Shadow Foundry Training", "" }
    md[#md + 1] = "Hypothetical recursive foundry: selected proposals become abstract atoms for the next layer."
    md[#md + 1] = ""
    md[#md + 1] = "| Layer | Extra atoms | Avg density | Avg speedup | Avg regret | Mixed | Full residual | Full native | Top proposals |"
    md[#md + 1] = "|---:|---:|---:|---:|---:|---:|---:|---:|---|"
    for _, l in ipairs(result.layers or {}) do
        local m = l.metrics or {}
        local top = {}
        for i, p in ipairs((l.proposals and l.proposals.candidates) or {}) do
            if i > 5 then break end
            top[#top + 1] = p.name
        end
        md[#md + 1] = string.format("| %d | %d | %.1f%% | %.3fx | %.3fx | %d | %d | %d | `%s` |",
            l.layer or 0, l.atom_count or 0, 100 * (m.avg_density or 0), m.avg_speedup_vs_residual or 0,
            m.avg_regret or 0, m.mixed or 0, m.full_residual or 0, m.full_native or 0, table.concat(top, " | "))
    end
    md[#md + 1] = ""
    Util.write_file(out_dir .. "/foundry_train.md", table.concat(md, "\n"))
end

local function usage()
    print([[SponJIT shadow simulator

Commands:
  run            --workload NAME --out DIR [cost flags]
  suite          --out DIR [cost flags]
  suite-profile  --profile FILE --out DIR [--max-regions N] [--fact-mode MODE]
  suite-awfy     --awfy-root DIR --out DIR [--max-regions N] [--fact-mode MODE]
  sensitivity-profile --profile FILE --out DIR [--max-regions N]
  sensitivity-awfy    --awfy-root DIR --out DIR [--max-regions N]
  profile-root   --root DIR --out FILE [--max-files N]   (PUC static bytecode profile)
  suite-initial  --awfy-root DIR --moonlift-root DIR --out DIR
  timeseries     --workload NAME --out DIR [--observe-fraction F]
  foundry-initial --awfy-root DIR --moonlift-root DIR --out DIR [--layers N] [--layer-cap N] [--enumerate-ssa false]
  enumerate-ssa  --awfy-root DIR --moonlift-root DIR --out DIR [--max-windows N] [--max-fact-combos N]
  propose        --miss-report FILE --out DIR [--max-candidates N]

Workloads: ]] .. table.concat(Workloads.names(), ", ") .. [[
Fact modes for aggregate bytecode profiles: none, conservative, balanced, optimistic

Cost flags:
  --interpreter-cost N     default 80
  --crossing-cost N        default 55
  --exit-cost N            default 250
  --materialization-cost N default 120
  --max-window N           default 4
  --max-generations N      default 8
  --hysteresis-margin N    default 0
]])
end

local function main(argv)
    local opts = parse(argv)
    local cmd = opts._[1] or opts.command or "suite"
    if cmd == "help" or opts.help then usage(); return 0 end
    local cfg = config_from_opts(opts)
    local out = opts.out or "experiments/lua_interpreter_vm/build/sponjit_shadow"
    if cmd == "run" then
        local workload = load_workload(opts)
        local result = Sim.simulate(workload, cfg)
        Report.write_run(result, out, cfg)
        local s = Sim.plan_summary(result.final_plan, cfg)
        print(string.format("[sponjit-shadow] %s density=%.1f%% cost=%.0f report=%s/shadow_report.md", result.workload or "?", 100 * s.absorption_density, s.cost.total, out))
        return 0
    elseif cmd == "suite" then
        local results = {}
        for _, name in ipairs(Workloads.names()) do
            results[#results + 1] = Sim.simulate(Workloads.get(name), cfg)
        end
        Report.write_suite(results, out, cfg)
        print("[sponjit-shadow] suite report=" .. out .. "/suite_report.md")
        return 0
    elseif cmd == "suite-profile" then
        local profile = Loader.load_profile(assert(opts.profile, "--profile required"))
        local workloads = Loader.workloads_from_profile(profile, {
            max_regions = tonumber(opts.max_regions or 20),
            max_len = tonumber(opts.max_len or opts.max_window or 8),
            min_len = tonumber(opts.min_len or 2),
            fact_mode = opts.fact_mode or "balanced",
        })
        local results = {}
        for _, w in ipairs(workloads) do results[#results + 1] = Sim.simulate(w, cfg) end
        Report.write_suite(results, out, cfg)
        print("[sponjit-shadow] profile suite regions=" .. tostring(#results) .. " report=" .. out .. "/suite_report.md")
        return 0
    elseif cmd == "suite-awfy" then
        local profile = Loader.load_awfy_profile(opts.awfy_root or ".")
        local workloads = Loader.workloads_from_profile(profile, {
            max_regions = tonumber(opts.max_regions or 20),
            max_len = tonumber(opts.max_len or opts.max_window or 8),
            min_len = tonumber(opts.min_len or 2),
            fact_mode = opts.fact_mode or "balanced",
        })
        local results = {}
        for _, w in ipairs(workloads) do results[#results + 1] = Sim.simulate(w, cfg) end
        Report.write_suite(results, out, cfg)
        print("[sponjit-shadow] AWFY suite regions=" .. tostring(#results) .. " report=" .. out .. "/suite_report.md")
        return 0
    elseif cmd == "sensitivity-profile" or cmd == "sensitivity-awfy" then
        local profile = cmd == "sensitivity-awfy" and Loader.load_awfy_profile(opts.awfy_root or ".") or Loader.load_profile(assert(opts.profile, "--profile required"))
        local rows = {}
        for _, mode in ipairs({ "none", "conservative", "balanced", "optimistic" }) do
            for _, crossing in ipairs({ 25, 55, 100 }) do
                local ccfg = {}
                for k, v in pairs(cfg) do ccfg[k] = v end
                ccfg.crossing_cost = crossing
                local workloads = Loader.workloads_from_profile(profile, {
                    max_regions = tonumber(opts.max_regions or 20),
                    max_len = tonumber(opts.max_len or opts.max_window or 8),
                    min_len = tonumber(opts.min_len or 2),
                    fact_mode = mode,
                })
                local results = {}
                for _, w in ipairs(workloads) do results[#results + 1] = Sim.simulate(w, ccfg) end
                rows[#rows + 1] = { fact_mode = mode, crossing_cost = crossing, exit_cost = ccfg.exit_cost, metrics = Report.suite_metrics(results, ccfg) }
            end
        end
        Report.write_sensitivity(rows, out)
        print("[sponjit-shadow] sensitivity report=" .. out .. "/sensitivity_report.md")
        return 0
    elseif cmd == "profile-root" then
        local profile, files = Loader.profile_lua_root(assert(opts.root, "--root required"), {
            max_files = tonumber(opts.max_files or 200),
            include = opts.include,
            exclude = opts.exclude,
            repo_root = opts.repo_root,
            lua_root = opts.lua_root,
        })
        profile.source_root = opts.root
        profile.scanned_files = #files
        Util.write_json(out, profile)
        print("[sponjit-shadow] wrote profile " .. out .. " files=" .. tostring(#files))
        return 0
    elseif cmd == "suite-initial" then
        local fact_mode = opts.fact_mode or "balanced"
        local max_regions = tonumber(opts.max_regions or 50)
        local awfy_profile = Loader.load_awfy_profile(opts.awfy_root or "experiments/lua_interpreter_vm")
        local awfy_workloads = Loader.workloads_from_profile(awfy_profile, { max_regions = max_regions, max_len = tonumber(opts.max_len or 8), min_len = tonumber(opts.min_len or 2), fact_mode = fact_mode })
        local awfy_results = {}
        for _, w in ipairs(awfy_workloads) do w.name = "awfy_" .. tostring(w.name); awfy_results[#awfy_results + 1] = Sim.simulate(w, cfg) end
        Report.write_suite(awfy_results, out .. "/awfy", cfg)

        local moon_profile, files = Loader.profile_lua_root(opts.moonlift_root or "lua/moonlift", {
            max_files = tonumber(opts.max_files or 200),
            include = opts.include,
            exclude = opts.exclude,
            repo_root = opts.repo_root,
            lua_root = opts.lua_root,
        })
        moon_profile.source_root = opts.moonlift_root or "lua/moonlift"
        moon_profile.scanned_files = #files
        Util.write_json(out .. "/moonlift_profile.json", moon_profile)
        local moon_workloads = Loader.workloads_from_profile(moon_profile, { max_regions = max_regions, max_len = tonumber(opts.max_len or 8), min_len = tonumber(opts.min_len or 2), fact_mode = fact_mode })
        local moon_results = {}
        for _, w in ipairs(moon_workloads) do w.name = "moonlift_" .. tostring(w.name); moon_results[#moon_results + 1] = Sim.simulate(w, cfg) end
        Report.write_suite(moon_results, out .. "/moonlift", cfg)

        local combined = {}
        for _, r in ipairs(awfy_results) do combined[#combined + 1] = r end
        for _, r in ipairs(moon_results) do combined[#combined + 1] = r end
        Report.write_suite(combined, out .. "/combined", cfg)
        print("[sponjit-shadow] initial corpus reports=" .. out .. "/{awfy,moonlift,combined}/suite_report.md")
        return 0
    elseif cmd == "foundry-initial" then
        local fact_mode = opts.fact_mode or "balanced"
        local max_regions = tonumber(opts.max_regions or 30)
        local awfy_profile = Loader.load_awfy_profile(opts.awfy_root or "experiments/lua_interpreter_vm")
        local workloads = Loader.workloads_from_profile(awfy_profile, { max_regions = max_regions, max_len = tonumber(opts.max_len or 8), min_len = tonumber(opts.min_len or 2), fact_mode = fact_mode })
        for _, w in ipairs(workloads) do w.name = "awfy_" .. tostring(w.name) end
        local moon_profile = Loader.profile_lua_root(opts.moonlift_root or "lua/moonlift", {
            max_files = tonumber(opts.max_files or 100), include = opts.include, exclude = opts.exclude,
            repo_root = opts.repo_root, lua_root = opts.lua_root,
        })
        local moon_workloads = Loader.workloads_from_profile(moon_profile, { max_regions = max_regions, max_len = tonumber(opts.max_len or 8), min_len = tonumber(opts.min_len or 2), fact_mode = fact_mode })
        for _, w in ipairs(moon_workloads) do w.name = "moonlift_" .. tostring(w.name); workloads[#workloads + 1] = w end
        cfg.layers = tonumber(opts.layers or 3)
        cfg.layer_cap = tonumber(opts.layer_cap or opts.max_selected or 12)
        cfg.fact_mode = fact_mode
        cfg.foundry_discount = tonumber(opts.foundry_discount or 0.70)
        cfg.foundry_ssa_discount = tonumber(opts.foundry_ssa_discount or 0.55)
        cfg.enumerate_ssa = not (opts.enumerate_ssa == "false" or opts.enumerate_ssa == "0" or opts.enumerate_ssa == "no")
        cfg.max_windows = tonumber(opts.max_windows or 80)
        cfg.max_fact_axes = tonumber(opts.max_fact_axes or 12)
        cfg.max_fact_combos = tonumber(opts.max_fact_combos or 4096)
        local result = FoundryTrain.train(workloads, cfg)
        write_foundry_report(result, out)
        print("[sponjit-shadow] foundry report=" .. out .. "/foundry_train.md")
        return 0
    elseif cmd == "enumerate-ssa" then
        local fact_mode = opts.fact_mode or "balanced"
        local max_regions = tonumber(opts.max_regions or 20)
        local awfy_profile = Loader.load_awfy_profile(opts.awfy_root or "experiments/lua_interpreter_vm")
        local workloads = Loader.workloads_from_profile(awfy_profile, { max_regions = max_regions, max_len = tonumber(opts.max_len or 8), min_len = tonumber(opts.min_len or 2), fact_mode = fact_mode })
        for _, w in ipairs(workloads) do w.name = "awfy_" .. tostring(w.name) end
        local moon_profile = Loader.profile_lua_root(opts.moonlift_root or "lua/moonlift", {
            max_files = tonumber(opts.max_files or 50), include = opts.include, exclude = opts.exclude,
            repo_root = opts.repo_root, lua_root = opts.lua_root,
        })
        local moon_workloads = Loader.workloads_from_profile(moon_profile, { max_regions = max_regions, max_len = tonumber(opts.max_len or 8), min_len = tonumber(opts.min_len or 2), fact_mode = fact_mode })
        for _, w in ipairs(moon_workloads) do w.name = "moonlift_" .. tostring(w.name); workloads[#workloads + 1] = w end
        cfg.max_arity = tonumber(opts.max_arity or 4)
        cfg.max_windows = tonumber(opts.max_windows or 80)
        cfg.max_fact_axes = tonumber(opts.max_fact_axes or 12)
        cfg.max_fact_combos = tonumber(opts.max_fact_combos or 4096)
        local result = FoundryEnum.enumerate(workloads, cfg)
        FoundryEnum.write(result, out, { max_rows = tonumber(opts.max_rows or 40) })
        print("[sponjit-shadow] SSA forms=" .. out .. "/ssa_forms.md")
        return 0
    elseif cmd == "timeseries" then
        if opts.observe_fraction then cfg.observe_fraction = tonumber(opts.observe_fraction) end
        local workload = Workloads.get(opts.workload or opts._[2] or "phase_changing_method")
        local result = TimeSeries.simulate(workload, cfg)
        Report.write_timeseries(result, out)
        print("[sponjit-shadow] timeseries report=" .. out .. "/timeseries_report.md")
        return 0
    elseif cmd == "propose" then
        local miss = assert(Util.read_json(assert(opts.miss_report, "--miss-report required")))
        local proposals = Propose.propose(miss, {
            max_candidates = tonumber(opts.max_candidates or 24),
            max_arity = tonumber(opts.max_arity or 4),
        })
        Propose.write(proposals, out)
        print("[sponjit-shadow] proposals=" .. out .. "/absorber_proposals.md")
        return 0
    else
        usage(); return 1
    end
end

if arg and arg[0] and tostring(arg[0]):match("sponjit_shadow/harness%.lua$") then
    os.exit(main(arg or {}))
end

return { main = main }
