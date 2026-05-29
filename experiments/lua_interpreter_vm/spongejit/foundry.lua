#!/usr/bin/env luajit
-- foundry.lua — SponJIT absorber foundry (the real thing).
--
-- This is the production entry point. It:
--   1. Loads real bytecode from PUC Lua programs (AWFY + Moonlift corpus)
--   2. Extracts opcode windows
--   3. Enumerates fact combinations
--   4. Runs semantic SSA + Stencil IR lowering to discover canonical forms
--   5. Uses native-fragment metadata directly for foundry atoms/templates
--   6. Selects the best absorbers under a metadata budget
--   7. Emits the artifact pack
--
-- Scoring uses metadata-derived estimates until executable native-fragment
-- measurements exist. The removed C-function tile benchmarks are not a fallback.
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
local Grammar = require("src.grammar_enum")
-- Stencil IR is now the materialization shape; no legacy active-op stencil model.
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
    layer_cap = 16,
    max_layers = 3,
    max_pack_bytes = 50 * 1024 * 1024,  -- 50 MB budget
    summary_only = false,
    corpus_mode = false,
}

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

-- ── Stencil IR form enumeration ────────────────────────────────────────────────

local function enumerate_forms(workloads, atoms, config)
    if config.corpus_mode then
        print("[foundry] enumerating Stencil IR forms from corpus...")
        local result = Enum.enumerate(workloads, {
            max_arity = config.max_arity,
            max_windows = config.max_windows,
            max_fact_axes = 12,
            max_fact_combos = config.max_fact_combos,
        }, atoms)
        local s = result.stats
        print(string.format("[foundry] %d windows → %d compiles → %d unique Stencil IR forms",
            s.windows or 0, s.compiles or 0, s.unique_forms or 0))
        return result
    else
        print("[foundry] enumerating Stencil IR forms from grammar...")
        local result = Grammar.enumerate_grammar({
            max_arity = config.max_arity,
            max_fact_combos = config.max_fact_combos,
        })
        local s = result.stats
        print(string.format("[foundry] %d sequences → %d unique Stencil IR forms (%d OK, %d failed)",
            s.sequences or 0, s.unique_forms or 0, s.ok or 0, (s.compiles or 0) - (s.ok or 0)))
        return result
    end
end

-- ── lowering to abstract fragment templates ─────────────────────────────

local function lower_forms(stencil_forms)
    print("[foundry] selecting abstract native-fragment forms directly...")
    local templates = {}
    for _, f in ipairs(stencil_forms.forms or {}) do
        local ops_n = #(f.stencil_ops or {})
        local holes_n = #(f.stencil_holes or {})
        templates[#templates + 1] = {
            source_key = f.source_key,
            source_ops = f.ops,
            changed = f.changed,
            count = f.count,
            checked_facts = f.checked_facts,
            deps = f.deps,
            active_node_specs = f.active_node_specs,
            stencil_hash = f.stencil_hash or f.hash or f.key,
            stencil_form = f.stencil_form,
            stencil_ops = f.stencil_ops,
            stencil_slotmaps = f.stencil_slotmaps,
            total_size = 32 + ops_n * 16 + holes_n * 8,
            estimated_cycles = ops_n,
            cycles_saved = f.score or 0,
        }
    end
    table.sort(templates, function(a, b) return (a.cycles_saved or 0) > (b.cycles_saved or 0) end)
    print(string.format("[foundry] %d Stencil IR templates", #templates))
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

    local stencil_forms = enumerate_forms(workloads, atoms, config)
    local templates = lower_forms(stencil_forms)
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
            active_node_specs = s.active_node_specs,  -- typed SSA node specs for semantic reopening
            stencil_form = s.stencil_form,
            stencil_hash = s.stencil_hash,
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
            windows = stencil_forms.stats and stencil_forms.stats.windows or 0,
            compiles = stencil_forms.stats and stencil_forms.stats.compiles or 0,
            unique_forms = stencil_forms.stats and stencil_forms.stats.unique_forms or 0,
            templates_generated = #templates,
            templates_selected = #selected,
            selected_bytes = selected_bytes,
        },
        new_atoms = new_atoms,
    }
    if not config.summary_only then
        result.forms = stencil_forms
        result.templates = selected
    end
    return result
end

-- ── multi-layer orchestration ───────────────────────────────────────────

local function run_all_layers(workloads, config)
    local atoms = {}
    local all_layers = {}
    for l = 0, config.max_layers do
        local result = run_layer(workloads, atoms, l, config)
        all_layers[#all_layers + 1] = result
        if l < config.max_layers then
            for _, na in ipairs(result.new_atoms) do
                if #atoms < config.layer_cap * (l + 1) then
                    atoms[#atoms + 1] = na
                end
            end
        end
    end

    Util.write_json(config.out_dir .. "/foundry_layers.json", all_layers)

    print("\n[foundry] ========== DONE ==========")
    for _, l in ipairs(all_layers) do
        print(string.format("  Layer %d: %d atoms → %d templates (%d bytes selected)",
            l.layer, l.atom_count_before, l.templates_selected, l.selected_bytes))
    end
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
        elseif a == "--corpus-mode" then config.corpus_mode = true
        end
        i = i + 1
    end

    Util.mkdir_p(config.out_dir)
    if config.corpus_mode then
        local workloads = load_corpus(config)
        run_all_layers(workloads, config)
    else
        run_all_layers(nil, config)
    end
end

if arg and arg[0] and tostring(arg[0]):match("foundry%.lua$") then
    main(arg)
end

return { main = main }
