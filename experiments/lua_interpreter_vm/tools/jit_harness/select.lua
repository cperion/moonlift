-- select.lua
-- Profitability-aware winner selection for runtime stencil layers.

local M = {}

local function candidate_key(candidate)
    return candidate.id or candidate.name or "unknown"
end

local function result_index(bench_result)
    local idx = {}
    for _, r in ipairs((bench_result and bench_result.benchmark_results) or {}) do
        idx[r.candidate_id] = r
    end
    return idx
end

local function unit_arity(candidate)
    return candidate.unit_arity or #(candidate.nodes or {}) or 1
end

local function opcode_arity(candidate)
    return #(candidate.ops or {}) > 0 and #(candidate.ops or {}) or (candidate.arity or 1)
end

function M.classify_candidate(candidate, bench, config)
    config = config or {}
    local classification = {
        candidate_id = candidate_key(candidate),
        class = "Unknown",
        reason = "",
        score = bench and bench.score or 0,
    }

    if candidate.valid == false then
        classification.class = "Invalid"
        classification.reason = "Failed verification"
        return classification
    end
    if not bench then
        classification.class = "Unbenchmarked"
        classification.reason = "No benchmark result"
        return classification
    end
    if not bench.compiled then
        classification.class = "Invalid"
        classification.reason = "Object compilation failed"
        return classification
    end
    if bench.codegen_supported == false then
        classification.class = "ResearchOnly"
        classification.reason = "No concrete codegen path: " .. tostring(bench.unsupported_reason or "unknown")
        return classification
    end
    if (bench.frequency or 0) < (config.min_frequency or 1) then
        classification.class = "Rare"
        classification.reason = string.format("Frequency %d below threshold", bench.frequency or 0)
        return classification
    end
    if (bench.cycles_saved or 0) <= 0 then
        classification.class = "Dominated"
        classification.reason = "Estimated cycles do not improve baseline"
        return classification
    end
    if (bench.score or 0) <= (config.min_score or 0) then
        classification.class = "Dominated"
        classification.reason = "Score below profitability threshold"
        return classification
    end
    if candidate.research_only then
        classification.class = "ResearchOnly"
        classification.reason = "Marked research-only"
        return classification
    end

    classification.class = "Winner"
    classification.reason = "Profitable compiled candidate"
    return classification
end

local function quota_ok(counts, candidate, config)
    local arity = unit_arity(candidate)
    local shape = candidate.shape_kind or "unknown"
    if config.max_per_arity and (counts.by_arity[arity] or 0) >= config.max_per_arity then return false end
    if config.max_per_shape and (counts.by_shape[shape] or 0) >= config.max_per_shape then return false end
    return true
end

local function bump_counts(counts, candidate)
    local arity = unit_arity(candidate)
    local opcode_span = opcode_arity(candidate)
    local shape = candidate.shape_kind or "unknown"
    counts.by_arity[arity] = (counts.by_arity[arity] or 0) + 1
    counts.by_opcode_span[opcode_span] = (counts.by_opcode_span[opcode_span] or 0) + 1
    counts.by_shape[shape] = (counts.by_shape[shape] or 0) + 1
end

function M.select_layer(layer, bench_result, config)
    config = config or {}
    local idx = result_index(bench_result)
    local candidates = {}
    local decisions = {}

    for _, cand in ipairs(layer.verified or layer.candidates or {}) do
        local bench = idx[candidate_key(cand)]
        local cls = M.classify_candidate(cand, bench, config)
        decisions[#decisions + 1] = cls
        if cls.class == "Winner" then
            local copy = {}
            for k, v in pairs(cand) do copy[k] = v end
            copy.frequency = bench.frequency
            copy.selection_score = bench.score
            copy.cycles_saved = bench.cycles_saved
            copy.weighted_cycles_saved = bench.weighted_cycles_saved
            copy.object_size = bench.object_size
            copy.side_exit_risk = bench.side_exit_risk
            candidates[#candidates + 1] = copy
        end
    end

    table.sort(candidates, function(a, b)
        if (a.selection_score or 0) ~= (b.selection_score or 0) then
            return (a.selection_score or 0) > (b.selection_score or 0)
        end
        return candidate_key(a) < candidate_key(b)
    end)

    local selected = {}
    local counts = { by_arity = {}, by_opcode_span = {}, by_shape = {} }
    local max_selected = tonumber(config.max_selected or 512) or 512
    for _, cand in ipairs(candidates) do
        if #selected >= max_selected then break end
        if quota_ok(counts, cand, config) then
            selected[#selected + 1] = cand
            bump_counts(counts, cand)
        end
    end

    local rejected = #candidates - #selected
    return {
        timestamp = os.time(),
        layer_id = layer.id,
        total_candidates = #(layer.candidates or {}),
        benchmarked = bench_result and bench_result.candidate_count or 0,
        winner_candidates = #candidates,
        selected_count = #selected,
        rejected_profitable_by_quota = rejected,
        selected = selected,
        decisions = decisions,
        by_arity = counts.by_arity,
        by_opcode_span = counts.by_opcode_span,
        by_shape = counts.by_shape,
    }
end

function M.build_selector_table(layers, config)
    config = config or {}
    local selector = { timestamp = os.time(), layers = #layers, entries = 0, by_arity = {}, by_pattern = {} }
    for _, layer in ipairs(layers) do
        for _, cand in ipairs(layer.selected or layer.candidates or {}) do
            local arity = unit_arity(cand)
            local pattern = cand.pattern_key or cand.id or "unknown"
            selector.by_arity[arity] = (selector.by_arity[arity] or 0) + 1
            selector.by_pattern[pattern] = (selector.by_pattern[pattern] or 0) + 1
            selector.entries = selector.entries + 1
        end
    end
    return selector
end

function M.write_selector_table(tbl, path)
    local util = require("tools.jit_harness.util")
    return util.write_json(path, tbl)
end

function M.report_selection(selection)
    print("\n=== Selection Report ===")
    print(string.format("Benchmarked: %d", selection.benchmarked or 0))
    print(string.format("Profitable winners before quota: %d", selection.winner_candidates or 0))
    print(string.format("Selected: %d", selection.selected_count or 0))
    print("\n  Selected by unit arity:")
    for arity = 1, 8 do
        local n = selection.by_arity and (selection.by_arity[arity] or selection.by_arity[tostring(arity)])
        if n then print(string.format("    %d: %d", arity, n)) end
    end
    print("\n  Top selected:")
    for i = 1, math.min(20, #(selection.selected or {})) do
        local c = selection.selected[i]
        print(string.format("    %2d. %s score=%.0f saved=%d freq=%d shape=%s",
            i, candidate_key(c), c.selection_score or 0, c.cycles_saved or 0, c.frequency or 0, c.shape_kind or "?"))
    end
end

return M
