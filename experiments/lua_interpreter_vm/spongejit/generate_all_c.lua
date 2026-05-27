#!/usr/bin/env luajit
-- generate_all_c.lua — Full pipeline: corpus → SSA enumeration → C generation
--
--   Load corpus → enumerate opcode windows + fact combos → SSA.compile → ssa_to_c.generate
--
-- Usage:
--   luajit generate_all_c.lua [--max-forms N] [--out DIR]

local source = debug.getinfo(1, "S").source
local spongejit = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*/spongejit)") or "."
package.path = spongejit .. "/?.lua;" .. spongejit .. "/?/init.lua;" .. package.path

local Util = require("src.util")
local SSA = require("src.ssa")
local SSAtoC = require("src.ssa_to_c")
local Enum = require("src.enumerate")
local Loader = require("src.loader")

local DEFAULTS = {
    max_files = 50,
    max_regions = 10000,
    max_windows = 50000,
    max_fact_combos = 1024,
    max_arity = 4,
    max_forms = nil,  -- nil = all unique
    out_dir = spongejit .. "/build/generated_c",
    corpus_awfy = spongejit .. "/../",
    corpus_moonlift = "../../lua/moonlift",
}

local function parse_args(argv)
    local c = {}
    for k, v in pairs(DEFAULTS) do c[k] = v end
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a == "--max-forms" then c.max_forms = tonumber(argv[i + 1]); i = i + 1
        elseif a == "--max-files" then c.max_files = tonumber(argv[i + 1]); i = i + 1
        elseif a == "--max-windows" then c.max_windows = tonumber(argv[i + 1]); i = i + 1
        elseif a == "--out" then c.out_dir = argv[i + 1]; i = i + 1
        end
        i = i + 1
    end
    return c
end

local function op_names(ops)
    local out = {}
    for _, o in ipairs(ops or {}) do
        out[#out + 1] = type(o) == "table" and (o.op or o.name or "?") or tostring(o)
    end
    return out
end

local function ops_to_string(ops)
    return table.concat(op_names(ops), " ")
end

local function facts_to_string(facts)
    if not facts or #facts == 0 then return "" end
    local out = {}
    for _, f in ipairs(facts) do
        if type(f) == "table" then
            out[#out + 1] = f.predicate or f[1] or tostring(f)
        else
            out[#out + 1] = tostring(f)
        end
    end
    return table.concat(out, ",")
end

local function main(argv)
    local function op_name(o) return type(o) == "table" and (o.op or o.name or "?") or tostring(o) end
    local config = parse_args(argv or arg or {})
    Util.mkdir_p(config.out_dir)

    -- ── 1. Load corpus ──────────────────────────────────────────────────
    print("[gen_c] loading corpus...")
    local workloads = {}
    for _, spec in ipairs({
        { root = config.corpus_awfy, prefix = "awfy_" },
        { root = config.corpus_moonlift, prefix = "moonlift_" },
    }) do
        local ok, profile = pcall(Loader.profile_lua_root, spec.root,
            { max_files = config.max_files })
        if ok and profile then
            for _, w in ipairs(Loader.workloads_from_profile(profile, {
                max_regions = config.max_regions, max_len = 8, min_len = 2,
                fact_mode = "balanced",
            })) do
                w.name = spec.prefix .. w.name
                workloads[#workloads + 1] = w
            end
        end
    end
    print(string.format("[gen_c] %d workload regions", #workloads))

    -- ── 2. Enumerate SSA forms ──────────────────────────────────────────
    print("[gen_c] enumerating SSA forms...")
    local ssa_forms = Enum.enumerate(workloads, {
        max_arity = config.max_arity,
        max_windows = config.max_windows,
        max_fact_axes = 12,
        max_fact_combos = config.max_fact_combos,
    })
    print(string.format("[gen_c] %d windows → %d compiles → %d unique forms",
        ssa_forms.stats.windows or 0,
        ssa_forms.stats.compiles or 0,
        ssa_forms.stats.unique_forms or 0))

    -- ── 3. Generate C for each unique form ──────────────────────────────
    local forms = ssa_forms.forms or {}
    if config.max_forms then
        local capped = {}
        for i = 1, math.min(config.max_forms, #forms) do capped[i] = forms[i] end
        forms = capped
    end
    print(string.format("[gen_c] generating C for %d forms...", #forms))

    local generated, failed = 0, 0
    local total_bytes, total_holes, total_nodes = 0, 0, 0
    local largest_bytes, largest_name = 0, ""
    local by_first_op = {}

    -- Also write an index mapping hash → file
    local index_entries = {}

    local t0 = os.clock()
    for idx, form in ipairs(forms) do
        -- Re-derive SSA graph from ops + facts
        local ssa_result = SSA.compile(form.ops or {}, form.facts or {})

        if not ssa_result or not ssa_result.ok then
            failed = failed + 1
            goto continue
        end

        local c_result = SSAtoC.generate(ssa_result)
        if not c_result then
            failed = failed + 1
            goto continue
        end

        -- Safe filename
        local nf = form.normal_form or form.ops or {}
        local name = table.concat(nf, "_"):gsub("[^%w_]", "_"):sub(1, 70)
        local hash = (form.hash or form.normal_form_hash or ""):sub(1, 8)
        local fname = string.format("%05d_%s_%s.c", generated + 1, name, hash)
        local out_path = config.out_dir .. "/" .. fname

        Util.write_file(out_path, c_result.c_code)

        generated = generated + 1
        local sz = #c_result.c_code
        total_bytes = total_bytes + sz
        total_holes = total_holes + c_result.hole_count
        total_nodes = total_nodes + c_result.node_count

        if sz > largest_bytes then
            largest_bytes = sz; largest_name = fname
        end

        local first_op = op_name(form.ops[1]) or "?"
        by_first_op[first_op] = (by_first_op[first_op] or 0) + 1

        index_entries[#index_entries + 1] = {
            file = fname,
            hash = hash,
            nf = table.concat(nf, "|"),
            ops = ops_to_string(form.ops),
            facts = facts_to_string(form.facts),
            size = sz,
            holes = c_result.hole_count,
            nodes = c_result.node_count,
        }

        if generated % 1000 == 0 then
            local r = os.clock() - t0
            print(string.format("[gen_c] %d/%d  (%.0f/s)  last: %s",
                generated, #forms, generated / math.max(r, 0.001), fname))
        end

        ::continue::
    end

    local elapsed = os.clock() - t0

    -- ── 4. Write summary ────────────────────────────────────────────────
    local summary = {
        total = #forms, generated = generated, failed = failed,
        elapsed = elapsed, rate = generated / math.max(elapsed, 0.001),
        c_bytes = total_bytes, c_mb = total_bytes / 1048576,
        avg_c_bytes = generated > 0 and math.floor(total_bytes / generated) or 0,
        largest = { file = largest_name, bytes = largest_bytes },
        total_holes = total_holes, avg_holes = generated > 0 and (total_holes / generated) or 0,
        total_nodes = total_nodes, avg_nodes = generated > 0 and (total_nodes / generated) or 0,
        by_first_op = by_first_op,
    }

    Util.write_json(config.out_dir .. "/summary.json", summary)

    -- Markdown
    local md = {
        "# SponJIT SSA → C Generation",
        "",
        "| Metric | Value |",
        "|---|---|",
        string.format("| Forms | %d generated / %d failed / %d total |", generated, failed, #forms),
        string.format("| Time | %.1f sec (%.0f forms/s) |", elapsed, summary.rate),
        string.format("| C bytes | %d (%.1f MB) |", total_bytes, total_bytes / 1048576),
        string.format("| Avg C bytes | %d |", summary.avg_c_bytes),
        string.format("| Largest | %s (%d bytes) |", largest_name, largest_bytes),
        string.format("| Total holes | %d (avg %.1f) |", total_holes, summary.avg_holes),
        string.format("| Total SSA nodes | %d (avg %.1f) |", total_nodes, summary.avg_nodes),
        "",
        "## By first opcode",
        "",
        "| Opcode | Count |",
        "|---|---|",
    }
    local ops_sorted = {}
    for op, n in pairs(by_first_op) do ops_sorted[#ops_sorted + 1] = { op = op, n = n } end
    table.sort(ops_sorted, function(a, b) return a.n > b.n end)
    for _, e in ipairs(ops_sorted) do
        md[#md + 1] = string.format("| %s | %d |", e.op, e.n)
    end
    Util.write_file(config.out_dir .. "/summary.md", table.concat(md, "\n"))

    -- Index CSV (for tooling)
    local csv = { "file,hash,normal_form,ops,facts,size,holes,nodes" }
    for _, e in ipairs(index_entries) do
        csv[#csv + 1] = string.format("%s,%s,%s,%s,%s,%d,%d,%d",
            e.file, e.hash, e.nf, e.ops, e.facts, e.size, e.holes, e.nodes)
    end
    Util.write_file(config.out_dir .. "/index.csv", table.concat(csv, "\n"))

    print(string.format([[
[gen_c] DONE — %d generated, %d failed in %.1f sec
  C bytes: %d (%.1f MB)  avg: %d bytes/form
  Holes:   %d total  avg: %.1f/form
  Nodes:   %d total  avg: %.1f/form
  Largest: %s (%d bytes)
  Output:  %s]], generated, failed, elapsed, total_bytes, total_bytes / 1048576,
        summary.avg_c_bytes, total_holes, summary.avg_holes, total_nodes, summary.avg_nodes,
        largest_name, largest_bytes, config.out_dir))
end

if arg and arg[0] and tostring(arg[0]):match("generate_all_c") then
    main(arg)
end

return { main = main }
