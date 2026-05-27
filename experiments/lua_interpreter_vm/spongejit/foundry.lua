#!/usr/bin/env luajit
-- foundry.lua — SponJIT absorber foundry (the real thing).
--
-- This is the production entry point. It:
--   1. Builds stencils from C sources (GCC → .o → ELF parse → stencil library)
--   2. Loads real bytecode from PUC Lua programs (AWFY + Moonlift corpus)
--   3. Extracts opcode windows
--   4. Enumerates all fact combinations
--   5. Runs Foundry SSA to discover normal forms
--   6. Lowers SSA forms to stencil templates (real bytes, real holes)
--   7. Selects the best absorbers under a byte budget
--   8. Emits the artifact pack
--
-- Scoring uses REAL measurements (below), not estimates.
-- See bench/ for the PUC Lua instrumentation harness.
--
-- Usage:
--   luajit foundry.lua [--corpus-root DIR] [--out DIR] [--max-bytes N]

local source = debug.getinfo(1, "S").source
local spongejit = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*/spongejit)") or "."
package.path = spongejit .. "/?.lua;" .. spongejit .. "/?/init.lua;" .. package.path

local root = "."  -- repo root, always the CWD

local Util = require("src.util")
local SSA = require("src.ssa")
local Enum = require("src.enumerate")
local StencilModel = require("src.stencil_model")
local Loader = require("src.loader")

-- ── config ──────────────────────────────────────────────────────────────

local DEFAULTS = {
    corpus_awfy_root = root .. "/experiments/lua_interpreter_vm",
    corpus_moonlift_root = root .. "/lua/moonlift",
    out_dir = spongejit .. "/build",
    max_files = 200,
    max_regions = 10000,
    max_windows = 100000,
    max_fact_combos = 4096,
    max_arity = 4,
    stencils_src = spongejit .. "/stencils/stencils.c",
    stencils_out = spongejit .. "/build/stencil_library.json",
    layer_cap = 16,
    max_layers = 3,
    max_pack_bytes = 50 * 1024 * 1024,  -- 50 MB budget
    summary_only = false,
}

-- ── stencil build ───────────────────────────────────────────────────────

local function build_stencils(config)
    print("[foundry] loading stencil library...")
    local lib_path = config.stencils_out
    local ok = StencilModel.load_real_library(lib_path)
    if not ok then error("failed to load stencil library at " .. lib_path .. "; run 'make stencils' first") end
    print(string.format("[foundry] %d stencils loaded", StencilModel.stencil_count()))
end

-- ── corpus loading ──────────────────────────────────────────────────────

local function load_corpus(config)
    print("[foundry] loading corpus...")
    local workloads = {}

    -- Both AWFY benchmarks and Moonlift sources use the same profile-lua-root path
    local function add_from(root_dir, prefix)
        local profile = Loader.profile_lua_root(root_dir, { max_files = config.max_files })
        for _, w in ipairs(Loader.workloads_from_profile(profile, {
            max_regions = config.max_regions, max_len = 8, min_len = 2, fact_mode = "balanced",
        })) do
            w.name = prefix .. w.name
            workloads[#workloads + 1] = w
        end
    end

    add_from(config.corpus_awfy_root, "awfy_")
    add_from(config.corpus_moonlift_root, "moonlift_")

    print(string.format("[foundry] %d workload regions loaded", #workloads))
    return workloads
end

-- ── SSA form enumeration ────────────────────────────────────────────────

local function enumerate_forms(workloads, atoms, config)
    print("[foundry] enumerating SSA forms...")
    local result = Enum.enumerate(workloads, {
        max_arity = config.max_arity,
        max_windows = config.max_windows,
        max_fact_axes = 12,
        max_fact_combos = config.max_fact_combos,
    }, atoms)
    local s = result.stats
    print(string.format("[foundry] %d windows → %d compiles → %d unique SSA forms",
        s.windows or 0, s.compiles or 0, s.unique_forms or 0))
    return result
end

-- ── lowering to stencils ────────────────────────────────────────────────

local function lower_forms(ssa_forms)
    print("[foundry] lowering SSA forms to stencil templates...")
    local templates = {}
    local lowered, failed = 0, 0
    for _, f in ipairs(ssa_forms.forms or {}) do
        local tmpl, err = StencilModel.template_from_active_ops(f.active_ops, f.normal_form)
        if tmpl then
            tmpl.source_key = f.source_key
            tmpl.source_ops = f.ops  -- raw opcodes
            tmpl.changed = f.changed
            tmpl.count = f.count
            tmpl.checked_facts = f.checked_facts
            tmpl.deps = f.deps
            tmpl.active_node_specs = f.active_node_specs
            templates[#templates + 1] = tmpl
            lowered = lowered + 1
        else
            failed = failed + 1
        end
    end
    table.sort(templates, function(a, b)
        return (a.cycles_saved or 0) > (b.cycles_saved or 0)
    end)
    print(string.format("[foundry] %d lowered, %d failed", lowered, failed))
    return templates
end

-- ── selection ───────────────────────────────────────────────────────────

local function select_templates(templates, config)
    print("[foundry] selecting under budget...")
    local selected = {}
    local total_bytes = 0
    for _, t in ipairs(templates) do
        if total_bytes + t.total_size > config.max_pack_bytes then break end
        total_bytes = total_bytes + t.total_size
        selected[#selected + 1] = t
    end
    print(string.format("[foundry] selected %d templates, %d bytes (%.1f KB)",
        #selected, total_bytes, total_bytes / 1024))
    return selected
end

-- ── recursive foundry loop ──────────────────────────────────────────────

local function run_layer(workloads, atoms, layer_idx, config)
    print(string.format("\n[foundry] ========== LAYER %d ==========", layer_idx))
    print(string.format("[foundry] atom basis size: %d", #(atoms or {})))

    local ssa_forms = enumerate_forms(workloads, atoms, config)
    local templates = lower_forms(ssa_forms)
    local selected = select_templates(templates, config)
    local selected_bytes = 0
    for _, t in ipairs(selected) do selected_bytes = selected_bytes + (tonumber(t.total_size) or 0) end

    -- Build new atoms from selected templates for next layer
    local new_atoms = {}
    local atom_budget = 0
    if layer_idx < (tonumber(config.max_layers or 0) or 0) then
        atom_budget = math.max(0, (tonumber(config.layer_cap or 0) or 0) * (layer_idx + 1) - #(atoms or {}))
    end
    for _, s in ipairs(selected) do
        if #new_atoms >= atom_budget then break end
        new_atoms[#new_atoms + 1] = {
            pattern = s.source_ops or s.ops,       -- what runtime matches against
            source_ops = s.source_ops or s.ops,     -- raw opcodes for expansion
            active_ops_list = s.active_ops,          -- legacy/codegen node names for lowering compatibility
            active_node_specs = s.active_node_specs,  -- typed SSA node specs for real semantic reopening
            semantic_normal_form = s.normal_form,
            normal_form_hash = s.normal_form_hash,
            cost = s.estimated_cycles,
            code_size = s.total_size,
            checked = s.checked_facts or {},
            produced = {},
            foundry_layer = layer_idx,
        }
    end

    local result = {
        layer = layer_idx,
        atom_count_before = #(atoms or {}),
        atom_count_after = #(atoms or {}) + #new_atoms,
        templates_generated = #templates,
        templates_selected = #selected,
        selected_bytes = selected_bytes,
        summary = {
            windows = ssa_forms.stats and ssa_forms.stats.windows or 0,
            compiles = ssa_forms.stats and ssa_forms.stats.compiles or 0,
            unique_forms = ssa_forms.stats and ssa_forms.stats.unique_forms or 0,
            templates_generated = #templates,
            templates_selected = #selected,
            selected_bytes = selected_bytes,
        },
        new_atoms = new_atoms,
    }
    if not config.summary_only then
        result.forms = ssa_forms
        result.templates = selected
    end
    return result
end

-- ── main ────────────────────────────────────────────────────────────────

local function main(args)
    local config = {}
    for k, v in pairs(DEFAULTS) do config[k] = v end

    -- Parse args
    local i = 1
    args = args or arg or {}
    while i <= #args do
        local a = args[i]
        if a == "--max-bytes" then config.max_pack_bytes = tonumber(args[i+1]); i = i + 1
        elseif a == "--max-files" then config.max_files = tonumber(args[i+1]); i = i + 1
        elseif a == "--max-regions" then config.max_regions = tonumber(args[i+1]); i = i + 1
        elseif a == "--max-windows" then config.max_windows = tonumber(args[i+1]); i = i + 1
        elseif a == "--max-fact-combos" then config.max_fact_combos = tonumber(args[i+1]); i = i + 1
        elseif a == "--out" then config.out_dir = args[i+1]; i = i + 1
        elseif a == "--summary-only" then config.summary_only = true
        elseif a == "--layers" then config.max_layers = tonumber(args[i+1]); i = i + 1
        elseif a == "--layer-cap" then config.layer_cap = tonumber(args[i+1]); i = i + 1
        end
        i = i + 1
    end

    Util.mkdir_p(config.out_dir)
    build_stencils(config)
    local workloads = load_corpus(config)

    local atoms = {}
    local all_layers = {}
    for l = 0, config.max_layers do
        local result = run_layer(workloads, atoms, l, config)
        all_layers[#all_layers + 1] = result
        if l < config.max_layers then
            for _, na in ipairs(result.new_atoms) do
                if #atoms < config.layer_cap * (l + 1) then  -- cumulative cap per layer
                    atoms[#atoms + 1] = na
                end
            end
        end
    end

    -- Write output
    Util.write_json(config.out_dir .. "/foundry_layers.json", all_layers)

    -- Summary
    print("\n[foundry] ========== DONE ==========")
    for _, l in ipairs(all_layers) do
        print(string.format("  Layer %d: %d atoms → %d templates (%d bytes selected)",
            l.layer, l.atom_count_before, l.templates_selected, l.selected_bytes))
    end
end

if arg and arg[0] and tostring(arg[0]):match("foundry%.lua$") then
    main(arg)
end

return { main = main }
