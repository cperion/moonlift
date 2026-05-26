-- report.lua
-- Produces human reports
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.17

local M = {}

-- Write corpus analysis report
function M.write_corpus_report(profile, path)
    local report = "# Corpus Analysis Report\n\n"
    report = report .. "## Summary\n\n"

    if profile.files then
        report = report .. string.format("Total files: %d\n", #profile.files)
    end

    if profile.total_bytes then
        report = report .. string.format("Total bytecode: %d bytes\n", profile.total_bytes)
    end

    report = report .. "\n## Files\n\n"
    report = report .. "| File | Size (bytes) |\n"
    report = report .. "|------|------|\n"

    if profile.files then
        for _, file in ipairs(profile.files) do
            report = report .. string.format("| %s | %d |\n", file.id, file.size_bytes or 0)
        end
    end

    local f = io.open(path, "w")
    if not f then
        return false, "cannot write to " .. path
    end

    f:write(report)
    f:close()
    return true
end

-- Write L0 seed report
function M.write_l0_seed_report(manifest, path)
    local report = "# L0 Seed Manifest Report\n\n"
    report = report .. "## Summary\n\n"
    report = report .. string.format("Total seeds: %d\n", #manifest.seeds)
    report = report .. string.format("Manual seeds: %d\n", manifest.manual_seed_count)
    report = report .. string.format("Corpus-derived seeds: %d\n", manifest.corpus_seed_count)

    report = report .. "\n## Seeds by Source\n\n"

    local by_source = {}
    for _, seed in ipairs(manifest.seeds) do
        local source = seed.source or "unknown"
        by_source[source] = (by_source[source] or 0) + 1
    end

    for source, count in pairs(by_source) do
        report = report .. string.format("- %s: %d\n", source, count)
    end

    report = report .. "\n## Top 50 Seeds by Priority\n\n"
    report = report .. "| # | Seed | Source | Priority | Arity |\n"
    report = report .. "|---|------|--------|----------|-------|\n"

    for i = 1, math.min(50, #manifest.seeds) do
        local seed = manifest.seeds[i]
        report = report .. string.format("| %d | %s | %s | %d | %d |\n",
            i, seed.name, seed.source or "unknown", seed.priority or 0, seed.arity or 1)
    end

    local f = io.open(path, "w")
    if not f then
        return false, "cannot write to " .. path
    end

    f:write(report)
    f:close()
    return true
end

-- Write layer generation report
function M.write_layer_report(layer, path)
    local report = "# Layer Generation Report\n\n"
    report = report .. "## Summary\n\n"
    report = report .. string.format("Generated candidates: %d\n", layer.total_candidates or 0)
    report = report .. string.format("Input seeds: %d\n", #(layer.seeds or {}))

    report = report .. "\n## Candidates by Unit Arity\n\n"

    if layer.by_arity then
        local keys = {}
        for k in pairs(layer.by_arity) do keys[#keys + 1] = tonumber(k) or k end
        table.sort(keys)
        for _, arity in ipairs(keys) do
            report = report .. string.format("- Unit arity %s: %d candidates\n", tostring(arity), layer.by_arity[arity] or layer.by_arity[tostring(arity)])
        end
    end

    report = report .. "\n## Candidates by Opcode Span\n\n"
    if layer.by_opcode_span then
        local keys = {}
        for k in pairs(layer.by_opcode_span) do keys[#keys + 1] = tonumber(k) or k end
        table.sort(keys)
        for _, arity in ipairs(keys) do
            report = report .. string.format("- Opcode span %s: %d candidates\n", tostring(arity), layer.by_opcode_span[arity] or layer.by_opcode_span[tostring(arity)])
        end
    end

    report = report .. "\n## Top 50 Candidates\n\n"
    report = report .. "| # | Candidate | Arity | Estimated Size | Holes | Relocs |\n"
    report = report .. "|---|-----------|-------|-----------------|-------|--------|\n"

    if layer.candidates then
        local sorted = {}
        for _, cand in ipairs(layer.candidates) do
            table.insert(sorted, cand)
        end

        table.sort(sorted, function(a, b)
            return (a.cost and a.cost.estimated_size or 0) > (b.cost and b.cost.estimated_size or 0)
        end)

        for i = 1, math.min(50, #sorted) do
            local c = sorted[i]
            report = report .. string.format("| %d | %s | %d | %d | %d | %d |\n",
                i, c.id or c.name or "unknown", c.arity or 0,
                c.cost and c.cost.estimated_size or 0,
                c.cost and c.cost.estimated_holes or 0,
                c.cost and c.cost.estimated_relocs or 0)
        end
    end

    local f = io.open(path, "w")
    if not f then
        return false, "cannot write to " .. path
    end

    f:write(report)
    f:close()
    return true
end

-- Write coverage report
function M.write_coverage_report(layers, corpus, path)
    local report = "# Stencil Library Coverage Report\n\n"
    report = report .. "## Summary\n\n"
    report = report .. string.format("Layers: %d\n", #layers)

    local total_candidates = 0
    for _, layer in ipairs(layers) do
        total_candidates = total_candidates + (layer.total_candidates or 0)
    end
    report = report .. string.format("Total candidates: %d\n", total_candidates)

    report = report .. "\n## Coverage by Layer\n\n"
    report = report .. "| Layer | Candidates | Top Patterns |\n"
    report = report .. "|-------|------------|---------------|\n"

    for i, layer in ipairs(layers) do
        local patterns = {}
        if layer.candidates then
            for _, c in ipairs(layer.candidates) do
                if c.id then
                    table.insert(patterns, c.id)
                end
            end
        end

        local pattern_str = table.concat(patterns, ", ")
        if #pattern_str > 50 then
            pattern_str = string.sub(pattern_str, 1, 47) .. "..."
        end

        report = report .. string.format("| L%d | %d | %s |\n", i, layer.total_candidates or 0, pattern_str)
    end

    local f = io.open(path, "w")
    if not f then
        return false, "cannot write to " .. path
    end

    f:write(report)
    f:close()
    return true
end

-- Write speed report
function M.write_speed_report(results, path)
    local report = "# Speed Report\n\n"
    report = report .. "## Summary\n\n"

    if results.summary then
        report = report .. string.format("Average cycles: %d\n", results.summary.avg_time or 0)
        if results.summary.fastest then
            report = report .. string.format("Fastest: %s\n", results.summary.fastest)
        end
        if results.summary.slowest then
            report = report .. string.format("Slowest: %s\n", results.summary.slowest)
        end
    end

    report = report .. "\n## Top Performers\n\n"
    report = report .. "| Candidate | Cycles | Improvement |\n"
    report = report .. "|-----------|--------|-------------|\n"

    if results.benchmark_results then
        local sorted = {}
        for _, bench in ipairs(results.benchmark_results) do
            table.insert(sorted, bench)
        end

        table.sort(sorted, function(a, b) return a.avg_cycles < b.avg_cycles end)

        for i = 1, math.min(20, #sorted) do
            local b = sorted[i]
            report = report .. string.format("| %s | %d | %d%%\n",
                b.candidate_id, b.avg_cycles or 0, 0)  -- Placeholder for improvement
        end
    end

    local f = io.open(path, "w")
    if not f then
        return false, "cannot write to " .. path
    end

    f:write(report)
    f:close()
    return true
end

function M.write_selection_report(selection, bench, path)
    local report = "# Stencil Selection Report\n\n"
    report = report .. "## Summary\n\n"
    report = report .. string.format("Benchmarked: %d\n", selection.benchmarked or 0)
    report = report .. string.format("Profitable winners before quota: %d\n", selection.winner_candidates or 0)
    report = report .. string.format("Selected: %d\n", selection.selected_count or 0)
    if bench and bench.summary then
        report = report .. string.format("Compiled: %d\n", bench.summary.compiled or 0)
        report = report .. string.format("Profitable: %d\n", bench.summary.profitable or 0)
        if bench.summary.best then
            report = report .. string.format("Best: `%s` score=%.0f\n", bench.summary.best.candidate_id, bench.summary.best.score or 0)
        end
    end

    report = report .. "\n## Selected by unit arity\n\n"
    for arity = 1, 8 do
        local n = selection.by_arity and (selection.by_arity[arity] or selection.by_arity[tostring(arity)])
        if n then report = report .. string.format("- %d: %d\n", arity, n) end
    end

    report = report .. "\n## Selected by shape\n\n"
    if selection.by_shape then
        local keys = {}
        for k in pairs(selection.by_shape) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do report = report .. string.format("- %s: %d\n", k, selection.by_shape[k]) end
    end

    report = report .. "\n## Top selected\n\n"
    report = report .. "| # | Candidate | Score | Freq | Saved/call | Unit arity | Opcode span | Shape | Lowering |\n"
    report = report .. "|---:|---|---:|---:|---:|---:|---:|---|---|\n"
    for i, c in ipairs(selection.selected or {}) do
        if i > 50 then break end
        report = report .. string.format("| %d | `%s` | %.0f | %d | %d | %d | %d | %s | %s |\n",
            i, c.id or c.name or "unknown", c.selection_score or 0, c.frequency or 0,
            c.cycles_saved or 0, c.unit_arity or #(c.nodes or {}), #(c.ops or {}), c.shape_kind or "", c.lowering or c.rewrite_kind or "")
    end

    local f = io.open(path, "w")
    if not f then return false, "cannot write to " .. path end
    f:write(report)
    f:close()
    return true
end

-- Generate all reports
function M.generate_all_reports(corpus, manifest, layers, output_dir)
    output_dir = output_dir or "build/harness_output/reports"
    os.execute("mkdir -p " .. output_dir)

    print("\n=== Generating Reports ===")

    if corpus then
        M.write_corpus_report(corpus, output_dir .. "/corpus.md")
        print("✓ Corpus report")
    end

    if manifest then
        M.write_l0_seed_report(manifest, output_dir .. "/l0_seeds.md")
        print("✓ L0 seed report")
    end

    if layers then
        for i, layer in ipairs(layers) do
            M.write_layer_report(layer, output_dir .. string.format("/l%d.md", i))
        end
        print(string.format("✓ Layer reports (%d)", #layers))

        M.write_coverage_report(layers, nil, output_dir .. "/coverage.md")
        print("✓ Coverage report")
    end
end

return M
