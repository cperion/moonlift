-- report.lua
-- Markdown/JSON reports for the SponJIT shadow simulator.

local Util = require("tools.jit_harness.util")
local Sim = require("tools.sponjit_shadow.simulate")

local M = {}

local function fmt(n)
    if type(n) ~= "number" then return tostring(n) end
    if math.abs(n) >= 1000 then return string.format("%.0f", n) end
    return string.format("%.2f", n)
end

local function pct(n) return string.format("%.1f%%", 100 * (tonumber(n) or 0)) end

function M.write_run(result, output_dir, config)
    Util.mkdir_p(output_dir)
    Util.write_json(output_dir .. "/shadow_result.json", result)
    local md = {}
    md[#md + 1] = "# SponJIT Shadow Result"
    md[#md + 1] = ""
    md[#md + 1] = "Workload: `" .. tostring(result.workload or "?") .. "`"
    if result.description then md[#md + 1] = "\n" .. result.description end
    md[#md + 1] = ""
    local summary = Sim.plan_summary(result.final_plan, config)
    md[#md + 1] = "## Final plan"
    md[#md + 1] = ""
    md[#md + 1] = "```text\n" .. table.concat(summary.units, "\n") .. "\n```"
    md[#md + 1] = ""
    md[#md + 1] = string.format("Absorption density: **%s** (%d absorbed ops, %d residual ops)", pct(summary.absorption_density), summary.absorbed_ops, summary.residual_ops)
    md[#md + 1] = string.format("\nTotal cost: **%s** (local %s, seam %s)", fmt(summary.cost.total), fmt(summary.cost.local_total), fmt(summary.cost.seam_total))
    if result.oracle then
        local regret = summary.cost.total / math.max(result.oracle.cost.total, 1)
        md[#md + 1] = string.format("\nOracle cost: **%s**; online/oracle regret: **%.3fx**", fmt(result.oracle.cost.total), regret)
        md[#md + 1] = "\nOracle plan: `" .. table.concat(result.oracle.unit_ids or {}, " | ") .. "`"
    end
    md[#md + 1] = ""
    md[#md + 1] = "## Reabsorption history"
    md[#md + 1] = ""
    md[#md + 1] = "| Gen | Action | Window | Delta | Total cost | Selected |"
    md[#md + 1] = "|---:|---|---|---:|---:|---|"
    for _, h in ipairs(result.history or {}) do
        local w = h.window and (h.window.start .. ".." .. h.window.finish) or "-"
        local cost = h.cost and h.cost.total or h.after or ""
        md[#md + 1] = string.format("| %s | %s | %s | %s | %s | `%s` |",
            tostring(h.generation), tostring(h.action), w, fmt(h.delta or 0), fmt(cost), table.concat(h.selected or {}, " | "))
    end
    md[#md + 1] = ""
    md[#md + 1] = "## Event stream"
    md[#md + 1] = ""
    md[#md + 1] = "| PC | Op | Freq | Observed facts |"
    md[#md + 1] = "|---:|---|---:|---|"
    for i, e in ipairs(result.events or {}) do
        md[#md + 1] = string.format("| %d | `%s` | %s | `%s` |", i, tostring(e.op), fmt(e.freq or 1), table.concat(e.observed or e.facts or {}, ", "))
    end
    md[#md + 1] = ""
    Util.write_file(output_dir .. "/shadow_report.md", table.concat(md, "\n"))
end

function M.suite_metrics(results, config)
    local m = { count = #results, avg_density = 0, avg_regret = 0, avg_speedup_vs_residual = 0, full_residual = 0, mixed = 0, full_native = 0 }
    for _, r in ipairs(results or {}) do
        local s = Sim.plan_summary(r.final_plan, config)
        local oracle = r.oracle and r.oracle.cost.total or s.cost.total
        local residual = r.oracle and r.oracle.residual_cost and r.oracle.residual_cost.total or s.cost.total
        local regret = s.cost.total / math.max(oracle, 1)
        m.avg_density = m.avg_density + s.absorption_density
        m.avg_regret = m.avg_regret + regret
        m.avg_speedup_vs_residual = m.avg_speedup_vs_residual + residual / math.max(s.cost.total, 1)
        if s.absorbed_ops == 0 then m.full_residual = m.full_residual + 1
        elseif s.residual_ops == 0 then m.full_native = m.full_native + 1
        else m.mixed = m.mixed + 1 end
    end
    if m.count > 0 then
        m.avg_density = m.avg_density / m.count
        m.avg_regret = m.avg_regret / m.count
        m.avg_speedup_vs_residual = m.avg_speedup_vs_residual / m.count
    end
    return m
end

local function add_miss(misses, key, item)
    local m = misses[key]
    if not m then
        m = { key = key, count = 0, pressure = 0, local_total = 0, seam = 0, examples = {} }
        misses[key] = m
    end
    m.count = m.count + 1
    m.pressure = m.pressure + (item.pressure or 0)
    m.local_total = m.local_total + (item.local_total or 0)
    m.seam = m.seam + (item.seam_in or 0) + (item.seam_out or 0)
    if #m.examples < 3 then m.examples[#m.examples + 1] = item.example end
end

function M.miss_report(results, config)
    local by_op, by_window = {}, {}
    for _, r in ipairs(results or {}) do
        local plan = r.final_plan or {}
        for _, p in ipairs(Sim.residual_pressures(plan, config)) do
            local u = plan.units[p.unit_index]
            local op = u and u.pattern and u.pattern[1] or tostring(u and u.id or "?")
            p.example = tostring(r.workload or "?") .. ":pc" .. tostring(p.start)
            add_miss(by_op, op, p)

            local prev = plan.units[p.unit_index - 1]
            local nextu = plan.units[p.unit_index + 1]
            local w = table.concat({ prev and prev.pattern and prev.pattern[#prev.pattern] or "^", op, nextu and nextu.pattern and nextu.pattern[1] or "$" }, "|")
            add_miss(by_window, w, p)
        end
    end
    local function sorted(map)
        local xs = {}
        for _, v in pairs(map) do xs[#xs + 1] = v end
        table.sort(xs, function(a, b) return a.pressure > b.pressure end)
        return xs
    end
    return { by_op = sorted(by_op), by_window = sorted(by_window) }
end

function M.write_suite(results, output_dir, config)
    Util.mkdir_p(output_dir)
    Util.write_json(output_dir .. "/suite_results.json", results)
    local metrics = M.suite_metrics(results, config)
    local misses = M.miss_report(results, config)
    Util.write_json(output_dir .. "/suite_metrics.json", metrics)
    Util.write_json(output_dir .. "/miss_report.json", misses)
    local md = {}
    md[#md + 1] = "# SponJIT Shadow Suite"
    md[#md + 1] = ""
    md[#md + 1] = string.format("Regions: **%d**; avg density: **%s**; avg regret: **%.3fx**; avg speedup vs all-residual: **%.3fx**", metrics.count, pct(metrics.avg_density), metrics.avg_regret, metrics.avg_speedup_vs_residual)
    md[#md + 1] = string.format("\nPlan shapes: full residual %d, mixed %d, full native %d", metrics.full_residual, metrics.mixed, metrics.full_native)
    md[#md + 1] = ""
    md[#md + 1] = "| Workload | Density | Final cost | Oracle cost | Regret | Units |"
    md[#md + 1] = "|---|---:|---:|---:|---:|---|"
    for _, r in ipairs(results) do
        local s = Sim.plan_summary(r.final_plan, config)
        local oracle = r.oracle and r.oracle.cost.total or s.cost.total
        local regret = s.cost.total / math.max(oracle, 1)
        md[#md + 1] = string.format("| `%s` | %s | %s | %s | %.3fx | `%s` |",
            tostring(r.workload), pct(s.absorption_density), fmt(s.cost.total), fmt(oracle), regret, table.concat(s.units, " | "))
    end
    md[#md + 1] = ""
    md[#md + 1] = "## Top residual misses by opcode"
    md[#md + 1] = ""
    md[#md + 1] = "| Opcode | Count | Pressure | Local | Seam | Examples |"
    md[#md + 1] = "|---|---:|---:|---:|---:|---|"
    for i = 1, math.min(12, #misses.by_op) do
        local m = misses.by_op[i]
        md[#md + 1] = string.format("| `%s` | %d | %s | %s | %s | `%s` |", m.key, m.count, fmt(m.pressure), fmt(m.local_total), fmt(m.seam), table.concat(m.examples, ", "))
    end
    md[#md + 1] = ""
    md[#md + 1] = "## Top residual misses by neighborhood"
    md[#md + 1] = ""
    md[#md + 1] = "| Neighborhood | Count | Pressure | Local | Seam | Examples |"
    md[#md + 1] = "|---|---:|---:|---:|---:|---|"
    for i = 1, math.min(12, #misses.by_window) do
        local m = misses.by_window[i]
        md[#md + 1] = string.format("| `%s` | %d | %s | %s | %s | `%s` |", m.key, m.count, fmt(m.pressure), fmt(m.local_total), fmt(m.seam), table.concat(m.examples, ", "))
    end
    md[#md + 1] = ""
    Util.write_file(output_dir .. "/suite_report.md", table.concat(md, "\n"))
end

function M.write_sensitivity(rows, output_dir)
    Util.mkdir_p(output_dir)
    Util.write_json(output_dir .. "/sensitivity.json", rows)
    local md = { "# SponJIT Shadow Sensitivity", "" }
    md[#md + 1] = "| Fact mode | Crossing | Exit | Regions | Avg density | Avg speedup | Avg regret | Mixed | Full residual | Full native |"
    md[#md + 1] = "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    for _, r in ipairs(rows or {}) do
        local m = r.metrics or {}
        md[#md + 1] = string.format("| `%s` | %s | %s | %d | %s | %.3fx | %.3fx | %d | %d | %d |",
            tostring(r.fact_mode), fmt(r.crossing_cost), fmt(r.exit_cost), m.count or 0, pct(m.avg_density or 0),
            m.avg_speedup_vs_residual or 0, m.avg_regret or 0, m.mixed or 0, m.full_residual or 0, m.full_native or 0)
    end
    md[#md + 1] = ""
    Util.write_file(output_dir .. "/sensitivity_report.md", table.concat(md, "\n"))
end

function M.write_timeseries(result, output_dir)
    Util.mkdir_p(output_dir)
    Util.write_json(output_dir .. "/timeseries_result.json", result)
    local md = { "# SponJIT Time-Series Shadow", "" }
    md[#md + 1] = "Workload: `" .. tostring(result.workload or "?") .. "`"
    if result.description then md[#md + 1] = "\n" .. result.description end
    local t = result.totals or {}
    md[#md + 1] = ""
    md[#md + 1] = string.format("Online speedup vs residual: **%.3fx**; oracle speedup: **%.3fx**; regret: **%.3fx**", t.online_speedup_vs_residual or 0, t.oracle_speedup_vs_residual or 0, t.regret or 0)
    md[#md + 1] = string.format("\nCache hits: **%d**; misses: **%d**; admitted: **%d**", t.cache_hits or 0, t.cache_misses or 0, t.admitted or 0)
    md[#md + 1] = ""
    md[#md + 1] = "| Epoch | Action | Online | Oracle | Residual | Speedup | Regret | Units |"
    md[#md + 1] = "|---:|---|---:|---:|---:|---:|---:|---|"
    for _, e in ipairs(result.epochs or {}) do
        md[#md + 1] = string.format("| %d `%s` | %s | %s | %s | %s | %.3fx | %.3fx | `%s` |",
            e.epoch or 0, tostring(e.name or ""), tostring(e.action), fmt(e.online_cost), fmt(e.oracle_cost), fmt(e.residual_cost), e.online_speedup_vs_residual or 0, e.regret or 0, table.concat(e.units or {}, " | "))
    end
    md[#md + 1] = ""
    Util.write_file(output_dir .. "/timeseries_report.md", table.concat(md, "\n"))
end

return M
