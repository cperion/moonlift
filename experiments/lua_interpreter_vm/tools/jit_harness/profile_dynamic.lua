-- profile_dynamic.lua
-- Dynamic profiling façade. The VM has no trace instrumentation hooks yet, so this
-- module records explicit skipped/unavailable status instead of randomized data.

local M = {}

function M.run_entrypoint(entry, config)
    return {
        run_id = tostring(os.time()) .. ":" .. tostring(entry and (entry.id or entry.path) or "unknown"),
        benchmark = entry and (entry.name or entry.path or entry.id) or "unknown",
        status = "skipped",
        elapsed_ns = 0,
        instr_executed = 0,
        trace_count = 0,
        timeout = false,
        error = "dynamic VM instrumentation not wired",
        profile = nil,
    }
end

function M.run_dynamic_profile(bundle, config)
    config = config or {}
    local result = {
        corpus_id = bundle and (bundle.corpus_id or bundle.bundle_id) or "unknown",
        run_config_hash = "unavailable",
        runs = {},
        trace_windows = {},
        fact_windows = {},
        hot_anchors = {},
        side_exits = {},
        value_facts = {},
        table_facts = {},
        call_facts = {},
        status = "skipped",
        reason = "dynamic VM instrumentation not wired",
    }
    if bundle and bundle.bundles then
        for _, b in ipairs(bundle.bundles) do
            table.insert(result.runs, M.run_entrypoint(b, config))
        end
    elseif bundle then
        table.insert(result.runs, M.run_entrypoint(bundle, config))
    end
    return result
end

function M.merge_dynamic_profiles(profiles)
    local merged = {
        runs = {}, trace_windows = {}, fact_windows = {}, hot_anchors = {}, side_exits = {},
        value_facts = {}, table_facts = {}, call_facts = {}, status = "merged",
    }
    for _, p in ipairs(profiles or {}) do
        for _, r in ipairs(p.runs or {}) do table.insert(merged.runs, r) end
    end
    return merged
end

return M
