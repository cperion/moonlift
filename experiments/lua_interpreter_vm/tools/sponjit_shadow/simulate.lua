-- simulate.lua
-- Non-executing SponJIT economic simulator: mixed plans, residual pressure,
-- local reabsorption, seam tax, and oracle comparison.

local Catalog = require("tools.sponjit_shadow.catalog")
local Tiler = require("tools.sponjit_shadow.tiler")
local Facts = require("tools.sponjit_shadow.facts")

local M = {}

local function deepcopy_unit(u)
    local v = {}
    for k, x in pairs(u or {}) do v[k] = x end
    return v
end

function M.initial_plan(events, config)
    config = Catalog.defaults(config)
    local units = {}
    for i = 1, #events do units[#units + 1] = Catalog.residual_candidate(events, i, config) end
    return { units = units, generation = 0, history = {} }
end

local function boundary_freq(a, b)
    return math.min(tonumber(a and a.freq) or 1, tonumber(b and b.freq) or 1)
end

function M.seam_cost_between(a, b, config)
    if not a or not b then return 0 end
    if a.kind == b.kind then return 0 end
    return boundary_freq(a, b) * (tonumber(config.crossing_cost) or Catalog.DEFAULTS.crossing_cost)
end

function M.plan_cost(plan, config)
    config = Catalog.defaults(config)
    local local_total, seam_total, native_units, residual_units = 0, 0, 0, 0
    for i, u in ipairs(plan.units or {}) do
        local_total = local_total + (tonumber(u.local_total) or ((tonumber(u.cost_per_hit) or 0) * (tonumber(u.freq) or 1)))
        if u.kind == "native" then native_units = native_units + 1 else residual_units = residual_units + 1 end
        seam_total = seam_total + M.seam_cost_between(u, plan.units[i + 1], config)
    end
    return {
        total = local_total + seam_total,
        local_total = local_total,
        seam_total = seam_total,
        native_units = native_units,
        residual_units = residual_units,
    }
end

function M.residual_pressures(plan, config)
    config = Catalog.defaults(config)
    local out = {}
    for i, u in ipairs(plan.units or {}) do
        if u.kind == "residual" then
            local seam_in = M.seam_cost_between(plan.units[i - 1], u, config)
            local seam_out = M.seam_cost_between(u, plan.units[i + 1], config)
            local local_total = tonumber(u.local_total) or 0
            out[#out + 1] = {
                unit_index = i,
                start = u.start,
                finish = u.finish,
                id = u.id,
                local_total = local_total,
                seam_in = seam_in,
                seam_out = seam_out,
                pressure = local_total + seam_in + seam_out,
                interior = (seam_in > 0 and seam_out > 0),
            }
        end
    end
    table.sort(out, function(a, b)
        if a.interior ~= b.interior then return a.interior end
        return a.pressure > b.pressure
    end)
    return out
end

local function find_unit_covering(plan, pc)
    for idx, u in ipairs(plan.units or {}) do
        if (u.start or 0) <= pc and pc <= (u.finish or 0) then return idx, u end
    end
    return nil, nil
end

local function replace_window(plan, start_pc, end_pc, new_units)
    local out = { units = {}, generation = (plan.generation or 0) + 1, history = plan.history or {} }
    local inserted = false
    for _, u in ipairs(plan.units or {}) do
        if (u.finish or 0) < start_pc or (u.start or 0) > end_pc then
            out.units[#out.units + 1] = u
        elseif not inserted then
            for _, nu in ipairs(new_units or {}) do out.units[#out.units + 1] = nu end
            inserted = true
        end
    end
    if not inserted then for _, nu in ipairs(new_units or {}) do out.units[#out.units + 1] = nu end end
    table.sort(out.units, function(a, b) return (a.start or 0) < (b.start or 0) end)
    return out
end

function M.window_bounds_around(plan, pressure, events, config)
    local max_ops = tonumber(config.max_window or 4) or 4
    local center = pressure.start
    local start_pc = math.max(1, center - math.floor((max_ops - 1) / 2))
    local end_pc = math.min(#events, start_pc + max_ops - 1)
    start_pc = math.max(1, end_pc - max_ops + 1)
    -- Prefer not to split already-materialized multi-op native units: expand to unit edges.
    local si, su = find_unit_covering(plan, start_pc)
    local ei, eu = find_unit_covering(plan, end_pc)
    if su then start_pc = su.start end
    if eu then end_pc = eu.finish end
    return start_pc, end_pc
end

function M.simulate(workload, config)
    config = Catalog.defaults(config)
    local events = workload.events or workload
    local plan = M.initial_plan(events, config)
    local history = {}
    local max_generations = tonumber(config.max_generations or 8) or 8
    local hysteresis = tonumber(config.hysteresis_margin or 0) or 0

    history[#history + 1] = { generation = 0, action = "initial", cost = M.plan_cost(plan, config) }

    for gen = 1, max_generations do
        local pressures = M.residual_pressures(plan, config)
        if #pressures == 0 then
            history[#history + 1] = { generation = gen, action = "saturated", cost = M.plan_cost(plan, config) }
            break
        end
        local p = pressures[1]
        local start_pc, end_pc = M.window_bounds_around(plan, p, events, config)
        local before = M.plan_cost(plan, config).total
        local cover = Tiler.cover(events, start_pc, end_pc, {}, config)
        local candidate = replace_window(plan, start_pc, end_pc, cover.units)
        local after = M.plan_cost(candidate, config).total
        local delta = before - after
        local accepted = delta > hysteresis
        history[#history + 1] = {
            generation = gen,
            action = accepted and "absorb" or "reject",
            spot = p,
            window = { start = start_pc, finish = end_pc },
            selected = M.unit_ids(cover.units),
            before = before,
            after = after,
            delta = delta,
            cost = accepted and M.plan_cost(candidate, config) or M.plan_cost(plan, config),
        }
        if accepted then plan = candidate else break end
    end

    plan.history = history
    return {
        workload = workload.name,
        description = workload.description,
        events = events,
        final_plan = plan,
        history = history,
        final_cost = M.plan_cost(plan, config),
        oracle = M.oracle(events, config),
    }
end

function M.oracle(events, config)
    config = Catalog.defaults(config)
    local all_residual = M.initial_plan(events, config)
    local cover = Tiler.cover_with_seams(events, 1, #events, {}, config)
    local plan = { units = cover.units, generation = "oracle", history = {} }
    local residual_cost = M.plan_cost(all_residual, config)
    local oracle_cost = M.plan_cost(plan, config)
    return {
        plan = plan,
        unit_ids = M.unit_ids(plan.units),
        residual_cost = residual_cost,
        cost = oracle_cost,
        speedup_vs_residual = residual_cost.total / math.max(oracle_cost.total, 1),
    }
end

function M.unit_ids(units)
    local xs = {}
    for _, u in ipairs(units or {}) do xs[#xs + 1] = u.id end
    return xs
end

function M.plan_summary(plan, config)
    local cost = M.plan_cost(plan, config)
    local ids = M.unit_ids(plan.units)
    local absorbed_ops = 0
    local residual_ops = 0
    for _, u in ipairs(plan.units or {}) do
        if u.kind == "native" then absorbed_ops = absorbed_ops + (u.covered_len or 1)
        else residual_ops = residual_ops + (u.covered_len or 1) end
    end
    return {
        units = ids,
        absorbed_ops = absorbed_ops,
        residual_ops = residual_ops,
        absorption_density = absorbed_ops / math.max(absorbed_ops + residual_ops, 1),
        cost = cost,
    }
end

return M
