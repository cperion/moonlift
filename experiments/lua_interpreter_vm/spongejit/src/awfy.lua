-- awfy.lua
-- Are We Fast Yet corpus integration for the Lua VM JIT harness.

local M = {}
local corpus = require("tools.jit_harness.corpus")
local compile = require("tools.jit_harness.compile")
local profile_static = require("tools.jit_harness.profile_static")
local report = require("tools.jit_harness.report")
local util = require("src.util")
local puc_bytecode = require("tools.jit_harness.puc_bytecode")

function M.discover_awfy(root)
    return {
        kind = "AWFY",
        root = root or ".",
        files = corpus.discover_awfy(root or "."),
    }
end

function M.list_awfy_benchmarks(c)
    return c.files or {}
end

function M.compile_awfy_benchmark(bench, compiler_config)
    return compile.compile_file(bench.path, compiler_config or {})
end

local function read_tsv(path)
    local rows = {}
    local text = util.read_file(path)
    if not text then return rows end
    local headers
    for line in text:gmatch("[^\n]+") do
        line = line:gsub("\r$", "")
        if line ~= "" then
            local cols = {}
            for col in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(cols, col) end
            if not headers then
                headers = cols
            else
                local row = {}
                for i, h in ipairs(headers) do row[h] = cols[i] end
                table.insert(rows, row)
            end
        end
    end
    return rows
end

local function add_window(profile, ops, count)
    if not ops or #ops == 0 then return end
    count = tonumber(count) or 0
    if count <= 0 then return end
    local key = table.concat(ops, "|")
    profile.window_counts[key] = (profile.window_counts[key] or 0) + count
    profile.total_windows = profile.total_windows + count
end

function M.find_puc_profile_root(root)
    root = root or "."
    local candidates = {
        root .. "/build/awfy_puc_profile",
        root .. "/experiments/lua_interpreter_vm/build/awfy_puc_profile",
        "experiments/lua_interpreter_vm/build/awfy_puc_profile",
        "build/awfy_puc_profile",
    }
    for _, path in ipairs(candidates) do
        if util.path_exists(path .. "/aggregate_opcode_hist.tsv") then return path end
    end
    return nil
end

function M.load_puc_static_profile(profile_root)
    if not profile_root then return nil, "no PUC profile root" end
    local profile = {
        corpus_id = "awfy-puc",
        source = "puc-profile",
        profile_root = profile_root,
        max_window = 3,
        proto_profiles = {},
        protos = {},
        total_opcodes = 0,
        total_windows = 0,
        opcode_counts = {},
        window_counts = {},
        motif_counts = {},
        rejects = {},
    }

    for _, row in ipairs(read_tsv(profile_root .. "/aggregate_opcode_hist.tsv")) do
        local name, count = row.name, tonumber(row.count) or 0
        if name then
            profile.opcode_counts[name] = (profile.opcode_counts[name] or 0) + count
            profile.total_opcodes = profile.total_opcodes + count
            add_window(profile, { name }, count)
        end
    end
    for _, row in ipairs(read_tsv(profile_root .. "/aggregate_pairs.tsv")) do
        add_window(profile, { row.name1, row.name2 }, row.count)
    end
    for _, row in ipairs(read_tsv(profile_root .. "/aggregate_triples.tsv")) do
        add_window(profile, { row.name1, row.name2, row.name3 }, row.count)
    end
    -- Some generated profiles include motif windows longer than triples. Accept
    -- either pipe-separated or whitespace-separated motif rows. Long motifs are
    -- projected into observed 4-grams so L1 can schedule opcode arity 4 without
    -- materializing the full seed^4 cross-product.
    for _, row in ipairs(read_tsv(profile_root .. "/aggregate_motifs.tsv")) do
        local pat = row.pattern or row.motif or row.window or row.sequence
        local count = tonumber(row.count) or 0
        if pat then
            local ops = {}
            if pat:find("|", 1, true) then
                for op in pat:gmatch("[^|]+") do table.insert(ops, op) end
            else
                for op in pat:gmatch("%S+") do table.insert(ops, op) end
            end
            if #ops > 0 then
                local motif_key = table.concat(ops, "|")
                profile.motif_counts[motif_key] = (profile.motif_counts[motif_key] or 0) + count
            end
            if #ops > 0 and #ops <= 4 then
                add_window(profile, ops, count)
            elseif #ops > 4 then
                for i = 1, #ops - 3 do
                    add_window(profile, { ops[i], ops[i + 1], ops[i + 2], ops[i + 3] }, count)
                end
            end
        end
    end

    return profile
end

function M.run_awfy_benchmark(bench, runner, config)
    config = config or {}
    -- Dynamic execution is not wired into the VM yet. Return an explicit skipped
    -- status rather than synthetic success.
    return {
        benchmark = bench.name or bench.path,
        status = "skipped",
        elapsed_ns = 0,
        instr_executed = 0,
        trace_count = 0,
        timeout = false,
        error = "dynamic AWFY runner not configured",
    }
end

function M.profile_awfy(root, output, config)
    config = config or {}
    output = output or "build/jit/profile/awfy"
    util.mkdir_p(output)

    local c = M.discover_awfy(root or ".")
    local normalized = corpus.load_awfy_corpus(root or ".", { skip_syntax_check = true })

    local puc_root = config.puc_profile_root or M.find_puc_profile_root(root or ".")
    local static_profile
    local bundle_db
    if puc_root and config.use_puc_profile ~= false then
        static_profile = assert(M.load_puc_static_profile(puc_root))
        print("[puc] extracting static bytecode operands...")
        local operand_profile = puc_bytecode.profile_files(normalized.files, {
            repo_root = config.repo_root,
            awfy_root = root,
            lua_root = config.lua_root or root,
        }, static_profile)
        local dynamic_operand_profile = nil
        -- Dynamic execution of the full PUC conformance suite is dangerous:
        -- some tests intentionally stress memory/errors. Only run operand tracing
        -- when explicitly requested by the caller.
        if config.trace_operands == true then
            print(string.format("[puc] tracing dynamic operands (limit=%d, max_files=%d)...", tonumber(config.trace_limit or 20000), tonumber(config.trace_max_files or 3)))
            dynamic_operand_profile = puc_bytecode.profile_dynamic_files(normalized.files, {
                repo_root = config.repo_root,
                awfy_root = root,
                lua_root = config.lua_root or root,
                trace_limit = config.trace_limit or 20000,
                trace_dir = config.keep_operand_traces and (output .. "/operand_traces") or nil,
                max_files = config.trace_max_files or 3,
                include = config.trace_include,
                timeout_seconds = config.trace_timeout_seconds or 5,
            })
        end
        print(string.format("[puc] static operand extraction: files=%d instructions=%d rejects=%d", operand_profile.files or 0, operand_profile.instructions or 0, #(operand_profile.rejects or {})))
        if dynamic_operand_profile then
            print(string.format("[puc] dynamic operand tracing: files=%d instructions=%d rejects=%d", dynamic_operand_profile.files or 0, dynamic_operand_profile.instructions or 0, #(dynamic_operand_profile.rejects or {})))
        end
        static_profile.operand_profile = operand_profile
        static_profile.dynamic_operand_profile = dynamic_operand_profile
        static_profile.operand_shape_counts = operand_profile.operand_shape_counts
        static_profile.rewrite_fact_static_counts = operand_profile.rewrite_fact_static_counts
        if dynamic_operand_profile and next(dynamic_operand_profile.rewrite_fact_counts or {}) then
            static_profile.rewrite_fact_counts = dynamic_operand_profile.rewrite_fact_counts
            static_profile.dynamic_window_counts = dynamic_operand_profile.dynamic_window_counts
        else
            static_profile.rewrite_fact_counts = operand_profile.rewrite_fact_counts
        end
        bundle_db = {
            source = "puc-profile",
            profile_root = puc_root,
            bundles = {}, rejects = {},
            total = normalized.normalized_count or #(normalized.files or {}),
            compiled = normalized.normalized_count or #(normalized.files or {}),
            failed = 0,
            fallback_compiled = 0,
        }
    else
        bundle_db = compile.compile_units(normalized.files, config.compile or {})
        static_profile = profile_static.profile_bundle_db(bundle_db, config.static_profile or { max_arity = 4 })
    end
    local result = {
        corpus = normalized,
        bundle_db = bundle_db,
        static_profile = static_profile,
        output = output,
    }

    util.write_json(output .. "/corpus_db.json", normalized)
    util.write_json(output .. "/proto_bundle_db.json", bundle_db)
    util.write_json(output .. "/static_profile.json", static_profile)
    report.write_corpus_report(corpus.build_corpus_profile(normalized), output .. "/corpus_report.md")

    return result
end

return M
