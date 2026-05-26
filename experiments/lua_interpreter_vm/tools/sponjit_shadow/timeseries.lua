-- timeseries.lua
-- Time-series / phase-change SponJIT shadow model.
-- This models what aggregate windows cannot: warmup, mode cache hits, and
-- online-vs-oracle regret over changing fact regimes.

local Sim = require("tools.sponjit_shadow.simulate")
local Facts = require("tools.sponjit_shadow.facts")
local Catalog = require("tools.sponjit_shadow.catalog")

local M = {}

local function copy_event(e, scale)
    local out = {}
    for k, v in pairs(e or {}) do out[k] = v end
    out.freq = math.max(0, (tonumber(e.freq) or 1) * scale)
    return out
end

local function scale_events(events, scale)
    local out = {}
    for i, e in ipairs(events or {}) do out[i] = copy_event(e, scale) end
    return out
end

local function event_signature(e)
    local facts = Facts.new(e.observed or e.facts or {})
    return tostring(e.op) .. "{" .. Facts.signature(facts) .. "}"
end

function M.signature(events)
    local xs = {}
    for _, e in ipairs(events or {}) do xs[#xs + 1] = event_signature(e) end
    return table.concat(xs, "|")
end

local function residual_cost(events, config)
    return Sim.plan_cost(Sim.initial_plan(events, config), config).total
end

local function simulate_epoch(events, config)
    local r = Sim.simulate({ name = "epoch", events = events }, config)
    return r.final_cost.total, r
end

function M.simulate(workload, config)
    config = Catalog.defaults(config)
    local epochs = workload.epochs or error("time-series workload requires epochs")
    local observe_fraction = tonumber(config.observe_fraction or 0.10) or 0.10
    if observe_fraction < 0 then observe_fraction = 0 end
    if observe_fraction > 1 then observe_fraction = 1 end

    local cache = {}
    local rows = {}
    local total_online, total_oracle, total_residual = 0, 0, 0
    local cache_hits, cache_misses, admitted = 0, 0, 0

    for idx, ep in ipairs(epochs) do
        local events = ep.events or {}
        local sig = M.signature(events)
        local all_resid = residual_cost(events, config)
        local oracle = Sim.oracle(events, config)
        local oracle_cost = oracle.cost.total
        local best_cost, best_result = simulate_epoch(events, config)
        local hit = cache[sig] ~= nil
        local online_cost
        local action

        if hit then
            cache_hits = cache_hits + 1
            online_cost = best_cost
            action = "cache-hit"
        else
            cache_misses = cache_misses + 1
            local warm_events = scale_events(events, observe_fraction)
            local run_events = scale_events(events, 1 - observe_fraction)
            local warm_cost = residual_cost(warm_events, config)
            local run_cost = simulate_epoch(run_events, config)
            online_cost = warm_cost + run_cost
            local gain = all_resid - best_cost
            if gain > (tonumber(config.hysteresis_margin or 0) or 0) then
                cache[sig] = { unit_ids = Sim.unit_ids(best_result.final_plan.units), cost = best_cost }
                admitted = admitted + 1
                action = "cache-miss-admit"
            else
                action = "cache-miss-residual"
            end
        end

        total_online = total_online + online_cost
        total_oracle = total_oracle + oracle_cost
        total_residual = total_residual + all_resid
        rows[#rows + 1] = {
            epoch = idx,
            name = ep.name or ("epoch_" .. idx),
            signature = sig,
            action = action,
            hit = hit,
            online_cost = online_cost,
            oracle_cost = oracle_cost,
            residual_cost = all_resid,
            online_speedup_vs_residual = all_resid / math.max(online_cost, 1),
            oracle_speedup_vs_residual = all_resid / math.max(oracle_cost, 1),
            regret = online_cost / math.max(oracle_cost, 1),
            units = oracle.unit_ids,
        }
    end

    return {
        workload = workload.name,
        description = workload.description,
        observe_fraction = observe_fraction,
        epochs = rows,
        totals = {
            online_cost = total_online,
            oracle_cost = total_oracle,
            residual_cost = total_residual,
            online_speedup_vs_residual = total_residual / math.max(total_online, 1),
            oracle_speedup_vs_residual = total_residual / math.max(total_oracle, 1),
            regret = total_online / math.max(total_oracle, 1),
            cache_hits = cache_hits,
            cache_misses = cache_misses,
            admitted = admitted,
            cache_entries = admitted,
        },
    }
end

return M
