-- harness.lua
-- Top-level JIT harness command dispatcher.

local source = debug.getinfo(1, "S").source
if source and source:sub(1, 1) == "@" then
    local path = source:sub(2)
    local base = path:match("^(.*)/tools/jit_harness/harness%.lua$")
    if base then
        package.path = base .. "/?.lua;" .. base .. "/?/init.lua;" .. base .. "/../../?.lua;" .. base .. "/../../?/init.lua;" .. base .. "/../../lua/?.lua;" .. base .. "/../../lua/?/init.lua;" .. package.path
    end
end

local M = {}

local function ensure_init()
    if not M.util then M.init() end
end

function M.init()
    M.util = require("tools.jit_harness.util")
    M.corpus = require("tools.jit_harness.corpus")
    M.awfy = require("tools.jit_harness.awfy")
    M.compile = require("tools.jit_harness.compile")
    M.profile_static = require("tools.jit_harness.profile_static")
    M.profile_dynamic = require("tools.jit_harness.profile_dynamic")
    M.fact_trace = require("tools.jit_harness.fact_trace")
    M.seed_l0 = require("tools.jit_harness.seed_l0")
    M.fact_schema = require("tools.jit_harness.fact_schema")
    M.layer_closure = require("tools.jit_harness.layer_closure")
    M.lowering_plan = require("tools.jit_harness.lowering_plan")
    M.candidate_emit = require("tools.jit_harness.candidate_emit")
    M.candidate_compile = require("tools.jit_harness.candidate_compile")
    M.object_mine = require("tools.jit_harness.object_mine")
    M.verify = require("tools.jit_harness.verify")
    M.bench = require("tools.jit_harness.bench")
    M.select = require("tools.jit_harness.select")
    M.export_runtime = require("tools.jit_harness.export_runtime")
    M.report = require("tools.jit_harness.report")
end

local function parse_args(argv, start)
    local opts, rest = {}, {}
    local i = start or 2
    while i <= #argv do
        local a = argv[i]
        if a:sub(1, 2) == "--" then
            local key, val = a:match("^%-%-([^=]+)=(.*)$")
            if not key then
                key = a:sub(3)
                local nxt = argv[i + 1]
                if nxt and nxt:sub(1, 1) ~= "-" then val = nxt; i = i + 1 else val = true end
            end
            key = key:gsub("-", "_")
            opts[key] = val
        else
            table.insert(rest, a)
        end
        i = i + 1
    end
    return opts, rest
end

local function load_json_or_error(path)
    local value, err = M.util.read_json(path)
    if not value then error("could not read JSON " .. tostring(path) .. ": " .. tostring(err)) end
    return value
end

local function usage()
    print([[Lua VM JIT Stencil Harness
Usage: luajit tools/jit_harness/harness.lua <command> [options]

Commands:
  profile-awfy      --awfy-root DIR --out DIR
  profile-corpus    --config FILE --out DIR        (minimal filesystem corpus)
  seed-l0           --profile FILE --manual FILE --out FILE|DIR
  build-layer       --layer N --seed-manifest FILE|--from-layer FILE --out DIR [--max-arity N]
  iterate-layers    --from FILE --profile FILE --to-layer N --out DIR [--max-arity N]
  verify-layer      --layer FILE
  bench-layer       --layer FILE --profile FILE --out FILE
  select-layer      --layer FILE --profile FILE --out DIR [--max-bench N] [--max-selected N]
  export-runtime    --layers FILE[,FILE...] --out DIR
  report            --corpus FILE --manifest FILE --layer FILE --out DIR
  clean             --out DIR
  test              --out DIR [--awfy-root DIR]
]])
end

function M.profile_awfy(awfy_root, output_dir, config)
    ensure_init()
    print("\n=== Harness: Profile AWFY ===")
    local result = M.awfy.profile_awfy(awfy_root or ".", output_dir or "build/jit/profile/awfy", config or {})
    M.profile_static.report_static_profile(result.static_profile)
    print(string.format("Compiled: %d / %d (rejects: %d, fallback: %d)", result.bundle_db.compiled, result.bundle_db.total, result.bundle_db.failed, result.bundle_db.fallback_compiled or 0))
    return result
end

function M.profile_corpus(config_path, output_dir)
    ensure_init()
    local cfg = config_path and load_json_or_error(config_path) or {}
    output_dir = output_dir or cfg.output_dir or "build/jit/profile/corpus"
    M.util.mkdir_p(output_dir)
    local root = cfg.root or "."
    local files = {}
    local cmd = "find " .. M.util.shell_quote(root) .. " -type f -name '*.lua' 2>/dev/null"
    local ok, out = M.util.run_capture(cmd)
    if ok then
        for path in out:gmatch("[^\n]+") do
            local unit = M.corpus.normalize_lua_file(path, { store_source_copy = false })
            if unit then table.insert(files, unit) end
        end
    end
    local db = { kind = "CORPUS", root = root, files = files, normalized_count = #files, error_count = 0 }
    local bundle_db = M.compile.compile_units(files, { repo_root = cfg.repo_root, allow_fallback = cfg.allow_fallback ~= false })
    local static_profile = M.profile_static.profile_bundle_db(bundle_db, cfg.static_profile or {})
    M.util.write_json(output_dir .. "/corpus_db.json", db)
    M.util.write_json(output_dir .. "/proto_bundle_db.json", bundle_db)
    M.util.write_json(output_dir .. "/static_profile.json", static_profile)
    return { corpus = db, bundle_db = bundle_db, static_profile = static_profile, output = output_dir }
end

function M.seed_l0_manifest(profile, output, manual_path)
    ensure_init()
    print("\n=== Harness: Build L0 Seed Manifest ===")
    local manual = M.seed_l0.load_manual_l0_seeds(manual_path and { path = manual_path } or { manual_priority = 100 })
    local corpus_seeds = {}
    if profile and profile.window_counts then
        corpus_seeds = M.seed_l0.derive_corpus_l0_seeds(profile, { min_frequency = 2, max_seeds = 50 })
    end
    local manifest = M.seed_l0.build_l0_seed_manifest(manual, corpus_seeds)
    local validation = M.seed_l0.validate_l0_seed_manifest(manifest)
    if not validation.valid then error("invalid L0 seed manifest") end
    local path = output or "build/jit/layers/l0_seed_manifest.json"
    if path:match("/$") or not path:match("%.json$") then path = path:gsub("/$", "") .. "/l0_seed_manifest.json" end
    M.seed_l0.write_l0_seed_manifest(manifest, path)
    M.seed_l0.report_l0_seeds(manifest)
    return manifest, path
end

local function layer_from_l0(manifest)
    local candidates = {}
    for _, seed in ipairs(manifest.seeds or {}) do
        local c = {
            id = seed.id or seed.name,
            name = seed.name or seed.id,
            layer = 0,
            arity = seed.arity or 1,
            ops = seed.ops or { seed.name or seed.id },
            source = seed.source or "manual",
            priority = seed.priority or 0,
            cost = { opcodes = seed.arity or 1, estimated_size = 50, estimated_holes = 0, estimated_relocs = 0 },
        }
        table.insert(candidates, c)
    end
    return { id = 0, name = "L0", seeds = manifest.seeds, candidates = candidates, selected = candidates, by_arity = {}, total_candidates = #candidates }
end

function M.build_layer(input, config)
    ensure_init()
    config = config or {}
    local layer_id = tonumber(config.layer or input.layer_id or 1) or 1
    local layer
    if layer_id == 0 then
        layer = layer_from_l0(input.manifest or input)
    else
        local budget = config.budget
        if config.max_opcodes or config.max_size or config.max_holes or config.max_relocs then
            budget = budget or {}
            if config.max_opcodes then budget.max_opcodes = tonumber(config.max_opcodes) end
            if config.max_size then budget.max_size = tonumber(config.max_size) end
            if config.max_holes then budget.max_holes = tonumber(config.max_holes) end
            if config.max_relocs then budget.max_relocs = tonumber(config.max_relocs) end
        end
        layer = M.layer_closure.build_layer({
            seeds = input.seeds or (input.manifest and input.manifest.seeds) or input.candidates or {},
            profile_db = input.profile_db,
        }, {
            max_arity = tonumber(config.max_arity) or 4,
            max_candidates = tonumber(config.max_candidates) or 1000,
            max_fact_variants = tonumber(config.max_fact_variants) or nil,
            enumerate_facts = config.enumerate_facts ~= false,
            profile_db = input.profile_db,
            budget = budget,
            compose_selected_atoms = config.compose_selected_atoms,
            max_motifs = tonumber(config.max_motifs),
            max_generated = tonumber(config.max_generated),
            max_atom_nodes = tonumber(config.max_atom_nodes),
            max_opcodes = tonumber(config.max_opcodes),
            max_profile_span = tonumber(config.max_profile_span),
            native_composition = config.native_composition,
            min_candidate_frequency = tonumber(config.min_candidate_frequency),
            min_unit_arity = tonumber(config.min_unit_arity),
            required_source_layer = config.required_source_layer ~= nil and tonumber(config.required_source_layer) or nil,
            inherit_atom_facts = config.inherit_atom_facts,
        })
        layer.id = layer_id
        layer.name = "L" .. tostring(layer_id)
    end
    return layer
end

function M.write_layer(layer, output_dir)
    ensure_init()
    M.util.mkdir_p(output_dir)
    local path = output_dir .. "/layer.json"
    M.util.write_json(path, layer)
    M.report.write_layer_report(layer, output_dir .. "/layer_report.md")
    return path
end

function M.verify_layer(layer)
    ensure_init()
    local results = {}
    local valid = {}
    for _, cand in ipairs(layer.candidates or {}) do
        if not cand.shape_kind and M.layer_closure and M.layer_closure.apply_shape_metadata then
            M.layer_closure.apply_shape_metadata(cand)
        end
        local r = M.verify.verify_candidate(cand, {})
        table.insert(results, r)
        if r.valid then table.insert(valid, cand) end
    end
    layer.verified = valid
    layer.verification = { results = results, valid = #valid, total = #(layer.candidates or {}) }
    M.verify.report_verification(results)
    return layer.verification
end

function M.bench_layer(layer, output, config)
    ensure_init()
    config = config or {}
    local result = M.bench.benchmark_layer({ candidates = layer.verified or layer.candidates or {} }, { awfy = true }, {
        profile_db = config.profile_db,
        compile_index = config.compile_index,
        code_size_weight = config.code_size_weight,
        progress = config.progress,
    })
    if output then M.util.write_json(output, result) end
    M.bench.report_benchmark_results(result)
    return result
end

local function benchmark_candidate_subset(M, layer, profile_db, max_bench)
    local candidates = layer.verified or layer.candidates or {}
    local ranked = {}
    for _, cand in ipairs(candidates) do
        local freq = M.bench.profile_frequency(cand, profile_db)
        ranked[#ranked + 1] = { cand = cand, freq = freq }
    end
    table.sort(ranked, function(a, b)
        if a.freq ~= b.freq then return a.freq > b.freq end
        return tostring(a.cand.id or a.cand.name) < tostring(b.cand.id or b.cand.name)
    end)
    local out = {}
    local limit = math.min(#ranked, tonumber(max_bench or #ranked) or #ranked)
    for i = 1, limit do out[#out + 1] = ranked[i].cand end
    return out
end

local function attach_compile_artifacts(candidates, emission, compile_result)
    local by_kernel = {}
    for _, k in ipairs((emission and emission.kernels) or {}) do by_kernel[k.id] = k end
    for _, r in ipairs((compile_result and compile_result.results) or {}) do
        local k = by_kernel[r.id]
        if k and k.candidate_id then
            for _, c in ipairs(candidates or {}) do
                if c.id == k.candidate_id then
                    c.compiled_object = r
                    c.object_path = r.object_path
                    c.object_size = r.size_bytes
                    c.native_artifact = { backend = r.backend or "unknown", object_path = r.object_path, size_bytes = r.size_bytes, symbol = r.symbol }
                    break
                end
            end
        end
    end
end

function M.benchmark_and_select_layer(layer, output_dir, config)
    ensure_init()
    config = config or {}
    output_dir = output_dir or "build/jit/selection"
    M.util.mkdir_p(output_dir)

    print("\n=== Verify before selection ===")
    M.verify_layer(layer)

    local raw_bench_candidates = benchmark_candidate_subset(M, layer, config.profile_db, config.max_bench or 512)
    local bench_candidates, rejected_lowering = {}, 0
    local backend = config.backend or "lalin"
    local native_composition = layer.native_composition or (raw_bench_candidates[1] and raw_bench_candidates[1].native_composition)
    for _, cand in ipairs(raw_bench_candidates) do
        local ok = true
        if (backend == "gcc" or backend == "c") and not native_composition then
            ok = M.lowering_plan.codegen_supported(cand, { backend = "gcc" })
        end
        if ok then bench_candidates[#bench_candidates + 1] = cand else rejected_lowering = rejected_lowering + 1 end
    end
    if rejected_lowering > 0 then print(string.format("[lowering] rejected unsupported %s candidates: %d", backend, rejected_lowering)) end
    local emission, compile_result
    if native_composition then
        print(string.format("\n=== Native composition benchmark set: %d candidates ===", #bench_candidates))
        emission = { kernels = {}, emitted = 0, written = 0, native_composition = true }
        compile_result = { results = {}, total = #bench_candidates, succeeded = #bench_candidates, failed = 0, native_composition = true }
        for _, cand in ipairs(bench_candidates) do
            local size = cand.cost and cand.cost.estimated_size or 0
            cand.native_artifact = { backend = "composed-native", size_bytes = size, units = cand.unit_arity or #(cand.nodes or {}) }
            cand.object_size = size
            compile_result.results[#compile_result.results + 1] = { id = cand.id, compiled = true, backend = "composed-native", size_bytes = size, symbol = "composed_" .. tostring(cand.id):gsub("[^%w_]", "_") }
        end
    else
        print(string.format("\n=== Emitting/compiling benchmark set: %d candidates ===", #bench_candidates))
        emission = M.candidate_emit.emit_kernel_batch(bench_candidates, { output_dir = output_dir .. "/kernels", backend = backend })
        M.candidate_emit.report_emission(emission)
        compile_result = M.candidate_compile.compile_kernel_batch(emission.kernels or {}, { output_dir = output_dir .. "/objects", repo_root = config.repo_root or M.util.find_repo_root("."), backend = backend, cc = config.cc, cflags = config.cflags })
        M.candidate_compile.report_compilation(compile_result)
        attach_compile_artifacts(bench_candidates, emission, compile_result)
    end

    local kernel_to_candidate = {}
    for _, k in ipairs(emission.kernels or {}) do kernel_to_candidate[k.id] = k.candidate_id end
    local compile_index = {}
    for _, r in ipairs(compile_result.results or {}) do
        compile_index[r.id] = r
        if kernel_to_candidate[r.id] then compile_index[kernel_to_candidate[r.id]] = r end
    end

    print("\n=== Profitability benchmark ===")
    local bench = M.bench.benchmark_layer({ candidates = bench_candidates }, nil, {
        profile_db = config.profile_db,
        compile_index = compile_index,
        backend = backend,
        code_size_weight = tonumber(config.code_size_weight) or 1.0,
        progress = true,
        progress_every = tonumber(config.progress_every) or 250,
    })
    M.bench.report_benchmark_results(bench)

    print("\n=== Selecting winners ===")
    local selection = M.select.select_layer({ id = layer.id, candidates = bench_candidates }, bench, {
        max_selected = tonumber(config.max_selected) or 512,
        min_frequency = tonumber(config.min_frequency) or 1,
        min_score = tonumber(config.min_score) or 0,
        max_per_arity = tonumber(config.max_per_arity),
        max_per_shape = tonumber(config.max_per_shape),
    })
    M.select.report_selection(selection)

    local selected_layer = {}
    for k, v in pairs(layer) do selected_layer[k] = v end
    for _, c in ipairs(selection.selected or {}) do c.layer = layer.id end
    selected_layer.selected = selection.selected
    selected_layer.selection = {
        selected_count = selection.selected_count,
        winner_candidates = selection.winner_candidates,
        benchmarked = selection.benchmarked,
        by_arity = selection.by_arity,
        by_shape = selection.by_shape,
    }

    M.util.write_json(output_dir .. "/emission.json", emission)
    M.util.write_json(output_dir .. "/compile.json", compile_result)
    M.util.write_json(output_dir .. "/bench.json", bench)
    M.util.write_json(output_dir .. "/selection.json", selection)
    M.util.write_json(output_dir .. "/selected_layer.json", selected_layer)
    M.report.write_selection_report(selection, bench, output_dir .. "/selection_summary.md")
    return selected_layer, selection, bench
end

function M.export_runtime_library(layers, output_dir)
    ensure_init()
    local selector = M.select.build_selector_table(layers, {})
    local lib = M.export_runtime.export_runtime_library(layers, selector, { version = "0.1", source = "jit-harness" })
    local result = M.export_runtime.write_runtime_library(lib, output_dir or "build/jit/runtime_stencils")
    M.export_runtime.report_export(result)
    return result
end

function M.run_test_pipeline(output_dir, awfy_root)
    ensure_init()
    output_dir = output_dir or "build/harness_output"
    M.util.mkdir_p(output_dir)
    local prof = M.profile_awfy(awfy_root or ".", output_dir .. "/profile", { compile = { repo_root = M.util.find_repo_root(".") } })
    local manifest = M.seed_l0_manifest(prof.static_profile, output_dir .. "/l0_seed_manifest.json")
    local l1 = M.build_layer({ manifest = manifest }, { layer = 1, max_arity = 2, max_candidates = 25 })
    M.write_layer(l1, output_dir .. "/L1")
    local emit = M.candidate_emit.emit_kernel_batch(l1.candidates, { output_dir = output_dir .. "/kernels" })
    M.candidate_emit.report_emission(emit)
    local compile_result = M.candidate_compile.compile_kernel_batch(emit.kernels or {}, { output_dir = output_dir .. "/objects", repo_root = M.util.find_repo_root(".") })
    M.candidate_compile.report_compilation(compile_result)
    local mined = {}
    for _, obj in ipairs(compile_result.results or {}) do table.insert(mined, M.object_mine.mine_object(obj, {}, {})) end
    M.verify_layer(l1)
    M.bench_layer(l1, output_dir .. "/bench_L1.json")
    M.export_runtime_library({ l1 }, output_dir .. "/runtime")
    M.report.generate_all_reports(prof.corpus, manifest, { l1 }, output_dir .. "/reports")
    print("\n=== Harness test pipeline complete: " .. output_dir .. " ===")
    return 0
end

function M.main(argv)
    M.init()
    argv = argv or arg or {}
    local command = argv[1] or "help"
    if command == "help" or command == "--help" or command == "-h" then usage(); return 0 end

    local ok, err = pcall(function()
        if command == "profile-awfy" then
            local opts = parse_args(argv, 2)
            M.profile_awfy(opts.awfy_root or ".", opts.out, {
                repo_root = opts.repo_root or M.util.find_repo_root("."),
                trace_operands = opts.trace_operands == true or opts.trace_operands == "true",
                trace_limit = tonumber(opts.trace_limit),
                trace_max_files = tonumber(opts.trace_max_files),
                trace_include = opts.trace_include,
                keep_operand_traces = opts.keep_operand_traces == true or opts.keep_operand_traces == "true",
                trace_timeout_seconds = tonumber(opts.trace_timeout_seconds),
                compile = { repo_root = opts.repo_root or M.util.find_repo_root(".") },
            })
        elseif command == "profile-corpus" then
            local opts = parse_args(argv, 2)
            M.profile_corpus(opts.config, opts.out)
        elseif command == "seed-l0" then
            local opts = parse_args(argv, 2)
            local profile = opts.profile and load_json_or_error(opts.profile) or nil
            M.seed_l0_manifest(profile, opts.out, opts.manual)
        elseif command == "build-layer" then
            local opts = parse_args(argv, 2)
            local profile = opts.profile and load_json_or_error(opts.profile) or nil
            local atoms = {}
            if opts.seed_manifest then
                local manifest = load_json_or_error(opts.seed_manifest)
                for _, c in ipairs(layer_from_l0(manifest).selected or {}) do atoms[#atoms + 1] = c end
            elseif not opts.from_layer and not opts.from_layers then
                for _, c in ipairs(layer_from_l0({ seeds = M.seed_l0.load_manual_l0_seeds({}) }).selected or {}) do atoms[#atoms + 1] = c end
            end
            local layer_paths = tostring(opts.from_layers or opts.from_layer or "")
            for path in layer_paths:gmatch("[^,]+") do
                if path ~= "" then
                    local prev = load_json_or_error(path)
                    for _, c in ipairs(prev.selected or {}) do
                        if c.layer == nil then c.layer = tonumber(prev.id or prev.layer_id or 0) or 0 end
                        atoms[#atoms + 1] = c
                    end
                end
            end
            opts.inherit_atom_facts = layer_paths ~= ""
            if layer_paths ~= "" and not opts.min_unit_arity then opts.min_unit_arity = 2 end
            if layer_paths ~= "" and not opts.required_source_layer then opts.required_source_layer = (tonumber(opts.layer or 1) or 1) - 1 end
            if layer_paths ~= "" then opts.native_composition = opts.native_composition ~= false and opts.native_composition ~= "false" end
            local layer = M.build_layer({ candidates = atoms, profile_db = profile }, opts)
            layer.atom_pool_count = #atoms
            M.write_layer(layer, opts.out or ("build/jit/layers/L" .. tostring(opts.layer or 0)))
        elseif command == "iterate-layers" then
            local opts = parse_args(argv, 2)
            local from = opts.from and load_json_or_error(opts.from) or layer_from_l0({ seeds = M.seed_l0.load_manual_l0_seeds({}) })
            local profile = opts.profile and load_json_or_error(opts.profile) or nil
            local out = opts.out or "build/jit/layers"
            local max = tonumber(opts.to_layer or 4)
            local current = from
            for i = (tonumber(current.id or 0) + 1), max do
                current = M.build_layer({ candidates = current.selected or current.verified or current.candidates or {}, profile_db = profile }, {
                    layer = i,
                    max_arity = tonumber(opts.max_arity) or 4,
                    max_candidates = tonumber(opts.max_candidates) or 1000,
                    compose_selected_atoms = i > 1,
                    max_motifs = tonumber(opts.max_motifs),
                    max_generated = tonumber(opts.max_generated),
                    max_atom_nodes = tonumber(opts.max_atom_nodes),
                })
                M.write_layer(current, out .. "/L" .. i)
            end
        elseif command == "verify-layer" then
            local opts = parse_args(argv, 2)
            M.verify_layer(load_json_or_error(opts.layer or opts[1]))
        elseif command == "bench-layer" then
            local opts = parse_args(argv, 2)
            local profile = opts.profile and load_json_or_error(opts.profile) or nil
            M.bench_layer(load_json_or_error(opts.layer), opts.out, { profile_db = profile, progress = true })
        elseif command == "select-layer" then
            local opts = parse_args(argv, 2)
            local profile = opts.profile and load_json_or_error(opts.profile) or nil
            M.benchmark_and_select_layer(load_json_or_error(opts.layer), opts.out or "build/jit/selection", {
                profile_db = profile,
                repo_root = opts.repo_root or M.util.find_repo_root("."),
                max_bench = tonumber(opts.max_bench) or 512,
                max_selected = tonumber(opts.max_selected) or 256,
                min_frequency = tonumber(opts.min_frequency) or 1,
                min_score = tonumber(opts.min_score) or 0,
                max_per_arity = tonumber(opts.max_per_arity),
                max_per_shape = tonumber(opts.max_per_shape),
                code_size_weight = tonumber(opts.code_size_weight) or 1.0,
                backend = opts.backend or "lalin",
                cc = opts.cc,
                cflags = opts.cflags,
            })
        elseif command == "export-runtime" then
            local opts = parse_args(argv, 2)
            local layers = {}
            for path in tostring(opts.layers or ""):gmatch("[^,]+") do table.insert(layers, load_json_or_error(path)) end
            M.export_runtime_library(layers, opts.out)
        elseif command == "report" then
            local opts = parse_args(argv, 2)
            M.report.generate_all_reports(opts.corpus and load_json_or_error(opts.corpus) or nil, opts.manifest and load_json_or_error(opts.manifest) or nil, opts.layer and { load_json_or_error(opts.layer) } or nil, opts.out or "build/jit/reports")
        elseif command == "clean" then
            local opts = parse_args(argv, 2)
            os.execute("rm -rf " .. M.util.shell_quote(opts.out or "build/harness_output"))
        elseif command == "test" then
            local opts = parse_args(argv, 2)
            return M.run_test_pipeline(opts.out, opts.awfy_root or ".")
        else
            error("unknown command: " .. tostring(command))
        end
    end)
    if not ok then io.stderr:write(tostring(err), "\n"); return 1 end
    return 0
end

if arg and arg[0] and (arg[0]:match("tools/jit_harness/harness%.lua$") or arg[0]:match("tools\\jit_harness\\harness%.lua$")) then
    os.exit(M.main(arg))
end

return M
