-- foundry_enumerate.lua
-- Exhaustive-ish SSA-form enumerator for the SponJIT foundry shadow model.
--
-- This is the simple foundry loop:
--   observed opcode windows -> applicable fact powersets -> Foundry SSA -> normal forms
-- The selected normal forms are the things that can later become atoms.

local Util = require("tools.jit_harness.util")
local SSA = require("tools.sponjit_shadow.foundry_ssa")

local M = {}

local ARITH = { ADD=true, ADDI=true, SUB=true, MUL=true, LT=true, LE=true, EQ=true, EQI=true, LTI=true, LEI=true, GTI=true, GEI=true }
local TABLE = { GETTABLE=true, GETI=true, SETTABLE=true, GETFIELD=true, GETTABUP=true, SELF=true, SETFIELD=true, SETTABUP=true }
local CALL = { CALL=true, TAILCALL=true }

local function join(xs, sep) return table.concat(xs or {}, sep or "|") end

local function copy_array(xs)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = x end
    return out
end

local function add(set, x) set[x] = true end

function M.fact_axes_for_ops(ops)
    local facts = {}
    for _, op in ipairs(ops or {}) do
        if op == "ADD" or op == "SUB" or op == "MUL" or op == "LT" or op == "LE" or op == "EQ" then
            add(facts, "lhs_i64"); add(facts, "rhs_i64")
        elseif op == "ADDI" or op == "EQI" or op == "LTI" or op == "LEI" or op == "GTI" or op == "GEI" then
            add(facts, "lhs_i64")
        elseif op == "GETTABLE" or op == "GETI" or op == "SETTABLE" then
            add(facts, "table"); add(facts, "key_i64"); add(facts, "metatable_absent"); add(facts, "array_hit")
            if op == "SETTABLE" then add(facts, "barrier_clean") end
        elseif op == "GETFIELD" or op == "SELF" or op == "GETTABUP" or op == "SETFIELD" or op == "SETTABUP" then
            add(facts, "table"); add(facts, "shape_known"); add(facts, "metatable_absent"); add(facts, "key_const")
            if op == "SETFIELD" or op == "SETTABUP" then add(facts, "barrier_clean") end
        elseif CALL[op] then
            add(facts, "known_call_target")
        elseif op == "RETURN" or op == "RETURN1" then
            add(facts, "returns_prev")
        elseif op == "JMP" then
            add(facts, "branch_consumes_prev"); add(facts, "loop_backedge")
        elseif op == "FORLOOP" or op == "FORPREP" then
            add(facts, "loop_i64")
        end
    end

    -- Sequence facts: these are not opcode-local, but they are exactly the kind of
    -- simple contextual facts the foundry should try before hand-coding patterns.
    for i = 1, #(ops or {}) - 1 do
        local a, b = ops[i], ops[i + 1]
        if TABLE[a] and (b == "CALL" or b == "TAILCALL") then add(facts, "callee_from_prev") end
        if (a == "ADD" or a == "ADDI" or a == "SUB" or a == "MUL" or a == "GETTABLE" or a == "GETFIELD") and (b == "RETURN" or b == "RETURN1") then add(facts, "returns_prev") end
        if a == "GETTABLE" and (b == "ADD" or b == "ADDI") then add(facts, "lhs_from_prev") end
        if (a == "GETFIELD" or a == "SELF") and b == "CALL" then add(facts, "result_known_call") end
    end

    local out = {}
    for f in pairs(facts) do out[#out + 1] = f end
    table.sort(out)
    return out
end

local function subset_count(n) return n >= 31 and math.huge or 2 ^ n end

function M.fact_subsets(facts, config)
    config = config or {}
    facts = copy_array(facts or {})
    local max_axes = tonumber(config.max_fact_axes or 12) or 12
    if #facts > max_axes then
        local trimmed = {}
        for i = 1, max_axes do trimmed[i] = facts[i] end
        facts = trimmed
    end
    local max_combos = tonumber(config.max_fact_combos or 4096) or 4096
    local total = math.min(subset_count(#facts), max_combos)
    local out = {}
    for mask = 0, total - 1 do
        local fs = {}
        for i, f in ipairs(facts) do
            if math.floor(mask / (2 ^ (i - 1))) % 2 == 1 then fs[#fs + 1] = f end
        end
        out[#out + 1] = fs
    end
    return out, facts
end

local function min_freq(events, start, finish)
    local f = math.huge
    for i = start, finish do f = math.min(f, tonumber(events[i] and events[i].freq or 1) or 1) end
    if f == math.huge then return 1 end
    return f
end

function M.windows_from_workloads(workloads, config)
    config = config or {}
    return M.windows_from_workloads_with_atoms(workloads, nil, config)
end

function M.windows_from_workloads_with_atoms(workloads, atoms, config)
    config = config or {}
    local max_arity = tonumber(config.max_arity or 4) or 4
    local by_key = {}
    for _, w in ipairs(workloads or {}) do
        local events = w.events or {}
        for i = 1, #events do
            local ops = {}
            for j = i, math.min(#events, i + max_arity - 1) do
                ops[#ops + 1] = events[j].op
                local key = join(ops, "|")
                local e = by_key[key]
                if not e then
                    e = { key = key, ops = copy_array(ops), count = 0, examples = {} }
                    by_key[key] = e
                end
                e.count = e.count + min_freq(events, i, j)
                if #e.examples < 3 then e.examples[#e.examples + 1] = tostring(w.name or "?") .. ":pc" .. tostring(i) end
            end
        end
    end
    local out = {}
    for _, e in pairs(by_key) do out[#out + 1] = e end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if #a.ops ~= #b.ops then return #a.ops > #b.ops end
        return a.key < b.key
    end)
    local max_windows = tonumber(config.max_windows or #out) or #out
    local clipped = {}
    for i = 1, math.min(max_windows, #out) do clipped[i] = out[i] end

    -- Expand atom-pattern matches: for each raw-op window, try replacing
    -- contiguous subsequences with expanded source ops, producing new
    -- windows for SSA to re-optimize at the next layer.
    if atoms and #atoms > 0 then
        -- Build atom index: pattern (op list) -> source_ops (the expanded ops)
        local atom_by_pat = {}
        local atom_obj_by_pat = {}
        for _, a in ipairs(atoms) do
            local pat = a.pattern or a.ops
            local src = a.source_ops or a.pattern or a.ops
            local active = a.active_ops_list or a.source_ops or a.pattern or a.ops
            if pat and #pat >= 1 and #src >= 1 then
                local k = join(pat, "|")
                atom_by_pat[k] = atom_by_pat[k] or {}
                atom_by_pat[k][#atom_by_pat[k] + 1] = src
                atom_obj_by_pat[k] = atom_obj_by_pat[k] or {}
                atom_obj_by_pat[k][#atom_obj_by_pat[k] + 1] = a
            end
        end
        -- For each clipped window, try matching atoms against sub-ranges.
        for _, w in ipairs(clipped) do
            local ops = w.ops
            local function add_expanded(ex_ops)
                if #ex_ops > max_arity then return end
                local key = join(ex_ops, "|")
                if not by_key[key] then
                    by_key[key] = { key = key, ops = copy_array(ex_ops), count = 0, examples = copy_array(w.examples) }
                end
                by_key[key].count = by_key[key].count + w.count
            end
            -- Try each sub-range [s, e] where atom pattern matches.
            for s = 1, #ops do
                for e = s, math.min(#ops, s + max_arity - 1) do
                    local sub = {}
                    for k = s, e do sub[#sub + 1] = ops[k] end
                    local sub_key = join(sub, "|")
                    local srcs = atom_by_pat[sub_key]
                    local objs = atom_obj_by_pat[sub_key]
                    if srcs then
                        for si, src_ops in ipairs(srcs) do
                            local obj = objs and objs[si]
                            -- Build expanded window with source ops: prefix + src_ops + suffix
                            local ex = {}
                            for k = 1, s - 1 do ex[#ex + 1] = ops[k] end
                            for _, so in ipairs(src_ops) do ex[#ex + 1] = so end
                            for k = e + 1, #ops do ex[#ex + 1] = ops[k] end
                            add_expanded(ex)
                            -- Also create a "compact" representation: atom's semantic normal form
                            -- as a single op token, which gets annotated with the atom's facts for
                            -- enriched SSA re-compilation.
                            if obj then
                                local nf = obj.semantic_normal_form
                                if nf and #nf >= 1 and join(nf, "|") ~= join(src_ops, "|") then
                                    local compact = {}
                                    for k = 1, s - 1 do compact[#compact + 1] = ops[k] end
                                    compact[#compact + 1] = join(nf, "_")
                                    for k = e + 1, #ops do compact[#compact + 1] = ops[k] end
                                    add_expanded(compact)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local out2 = {}
    for _, e in pairs(by_key) do out2[#out2 + 1] = e end
    table.sort(out2, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if #a.ops ~= #b.ops then return #a.ops > #b.ops end
        return a.key < b.key
    end)
    local result = {}
    for i = 1, math.min(max_windows, #out2) do result[i] = out2[i] end
    return result
end

local function op_cost(op)
    if op == "CALL" or op == "TAILCALL" then return 26 end
    if TABLE[op] then return 13 end
    if op == "RETURN" or op == "RETURN0" or op == "RETURN1" then return 8 end
    if ARITH[op] then return 7 end
    return 5
end

local function base_cost(ops)
    local n = 0
    for _, op in ipairs(ops or {}) do n = n + op_cost(op) end
    return n
end

local function active_cost(ssa)
    local n = 0
    for _, op in ipairs(ssa.active_ops or {}) do
        if op == "residual_boundary" then n = n + 30
        elseif op:match("^guard_") then n = n + 2
        elseif op == "store_slot" or op == "load_slot" then n = n + 2
        elseif op == "table_field_load" or op == "table_array_load" or op == "table_field_store" or op == "table_array_store" then n = n + 5
        elseif op == "call_boundary_known" or op == "call_boundary" then n = n + 18
        elseif op == "return1" or op == "return0" then n = n + 3
        else n = n + 1 end
    end
    return n
end

local function has_residual(ssa)
    for _, op in ipairs(ssa.active_ops or {}) do if op == "residual_boundary" then return true end end
    return false
end

local function set_from(xs)
    local out = {}
    for _, x in ipairs(xs or {}) do out[x] = true end
    return out
end

local function is_ssa_node_op(op)
    local function starts(s, prefix) return tostring(s or ""):sub(1, #prefix) == prefix end
    if starts(op, "guard_") then return true end
    local NODES = {
        load_slot = true, store_slot = true, load_const = true, const_i64 = true,
        const_nil = true, const_bool = true, const_f64 = true,
        move_value = true, box_i64 = true, unbox_i64 = true,
        add_i64 = true, sub_i64 = true, mul_i64 = true, cmp_i64 = true,
        table_field_load = true, table_field_store = true,
        table_array_load = true, table_array_store = true,
        call_boundary = true, call_boundary_known = true, tailcall_boundary = true,
        return0 = true, return1 = true, returnN = true,
        residual_boundary = true, barrier_check = true,
    }
    return NODES[op] or false
end

function M.enumerate(workloads, config, atoms)
    config = config or {}
    local windows = M.windows_from_workloads_with_atoms(workloads, atoms, config)
    local forms_by_hash = {}
    local total_compiles, total_ok = 0, 0

    -- Build atom index for compact-name expansion in the enumeration loop.
    local atoms_by_nf = {}
    if atoms and #atoms > 0 then
        for _, a in ipairs(atoms) do
            local nf = a.semantic_normal_form or {}
            if #nf >= 1 then
                local nf_name = join(nf, "_")
                -- Map compact name back to source ops + enriched facts
                atoms_by_nf[nf_name] = {
                    source_ops = a.source_ops or a.pattern or a.ops,
                    produced = a.produced or {},
                    checked = a.checked or {},
                }
            end
        end
    end

    for _, w in ipairs(windows) do
        local use_nodes = #w.ops > 0 and is_ssa_node_op(w.ops[1])
        -- Check for compact atom name: expand to source ops + enriched facts
        local expanded_ops = nil
        local enriched_facts = nil
        if not use_nodes then
            local any_atom = false
            for _, op in ipairs(w.ops) do
                if atoms_by_nf[op] then any_atom = true; break end
            end
            if any_atom then
                expanded_ops = {}
                enriched_facts = {}
                for _, op in ipairs(w.ops) do
                    local info = atoms_by_nf[op]
                    if info then
                        for _, so in ipairs(info.source_ops) do expanded_ops[#expanded_ops + 1] = so end
                        for _, p in ipairs(info.produced or {}) do enriched_facts[#enriched_facts + 1] = p end
                        for _, c in ipairs(info.checked or {}) do enriched_facts[#enriched_facts + 1] = c end
                    else
                        expanded_ops[#expanded_ops + 1] = op
                    end
                end
            end
        end
        local compile_ops = expanded_ops or w.ops
        local axes = use_nodes and {} or (expanded_ops and M.fact_axes_for_ops(compile_ops) or M.fact_axes_for_ops(w.ops))
        local subsets = use_nodes and { {} } or M.fact_subsets(axes, config)
        for _, facts in ipairs(subsets) do
            total_compiles = total_compiles + 1
            local combined_facts = facts
            if enriched_facts and #enriched_facts > 0 then
                local cf = {}
                for _, f in ipairs(facts) do cf[#cf + 1] = f end
                for _, f in ipairs(enriched_facts) do cf[#cf + 1] = f end
                combined_facts = cf
            end
            local ssa
            if use_nodes then
                ssa = SSA.compile_nodes(compile_ops, combined_facts, config)
            else
                ssa = SSA.compile(compile_ops, combined_facts, config)
            end
            if ssa.ok then
                total_ok = total_ok + 1
                local nf_key = join(ssa.normal_form, "|")
                local changed = nf_key ~= w.key
                local residual = has_residual(ssa)
                -- Keep all changed forms, plus fully-native same-shape forms that consume facts.
                if changed or (not residual and #(ssa.checked_facts or {}) > 0) then
                    local key = ssa.normal_form_hash
                    local score = (tonumber(w.count) or 1) * math.max(1, base_cost(w.ops) - active_cost(ssa))
                    if changed then score = score * 1.25 end
                    if residual then score = score * 0.25 end
                    local cur = forms_by_hash[key]
                    if not cur or score > cur.score then
                        forms_by_hash[key] = {
                            hash = key,
                            source_key = w.key,
                            ops = copy_array(w.ops),
                            facts = copy_array(facts),
                            fact_axes = axes,
                            normal_form = ssa.normal_form,
                            active_ops = ssa.active_ops,
                            checked_facts = ssa.checked_facts,
                            deps = ssa.deps,
                            projection = ssa.projection,
                            stats = ssa.stats,
                            count = w.count,
                            score = score,
                            changed = changed,
                            residual = residual,
                            examples = w.examples,
                        }
                    end
                end
            end
        end
    end

    local forms = {}
    for _, f in pairs(forms_by_hash) do forms[#forms + 1] = f end
    table.sort(forms, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.hash < b.hash
    end)

    -- Dedupe fact-subset explosions: same (source_ops, normal_form) with
    -- different fact subsets. Keep the richest-checked form per NF; drop
    -- the weaker subsets. "Richer" = superset of checked_facts.
    local nf_best = {}
    for _, f in ipairs(forms) do
        local nf_key = join(f.ops, "|") .. "::" .. join(f.normal_form, "|")
        local cur = nf_best[nf_key]
        if not cur then
            nf_best[nf_key] = f
        else
            local cur_set = set_from(cur.checked_facts)
            local new_set = set_from(f.checked_facts)
            local cur_super = true
            local new_super = true
            for _, c in ipairs(cur.checked_facts or {}) do if not new_set[c] then cur_super = false; break end end
            for _, c in ipairs(f.checked_facts or {}) do if not cur_set[c] then new_super = false; break end end
            if new_super and not cur_super then
                nf_best[nf_key] = f
            elseif cur_super and not new_super then
                -- keep cur
            elseif f.score > cur.score then
                nf_best[nf_key] = f
            end
        end
    end
    local deduped = {}
    for _, f in pairs(nf_best) do deduped[#deduped + 1] = f end
    table.sort(deduped, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.hash or "") < (b.hash or "")
    end)
    forms = deduped

    return {
        windows = windows,
        forms = forms,
        stats = { windows = #windows, compiles = total_compiles, ok = total_ok, unique_forms = #forms },
        generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

function M.write(result, out_dir, config)
    config = config or {}
    Util.mkdir_p(out_dir)
    Util.write_json(out_dir .. "/ssa_forms.json", result)
    local max_rows = tonumber(config.max_rows or 40) or 40
    local md = { "# SponJIT SSA Form Enumeration", "" }
    local s = result.stats or {}
    md[#md + 1] = string.format("Windows: **%d**; SSA compiles: **%d**; ok: **%d**; unique forms: **%d**", s.windows or 0, s.compiles or 0, s.ok or 0, s.unique_forms or 0)
    md[#md + 1] = ""
    md[#md + 1] = "These are foundry candidates from `opcode/atom tuple × applicable fact subset -> SSA normal form`."
    md[#md + 1] = ""
    md[#md + 1] = "| Rank | Score | Source ops | SSA normal form | Facts | Checked | Residual? | Examples |"
    md[#md + 1] = "|---:|---:|---|---|---|---|---|---|"
    for i, f in ipairs(result.forms or {}) do
        if i > max_rows then break end
        md[#md + 1] = string.format("| %d | %.0f | `%s` | `%s` | `%s` | `%s` | `%s` | `%s` |",
            i, f.score or 0, join(f.ops, " "), join(f.normal_form, " "), join(f.facts, ", "), join(f.checked_facts, ", "), tostring(f.residual), join(f.examples, ", "))
    end
    md[#md + 1] = ""
    Util.write_file(out_dir .. "/ssa_forms.md", table.concat(md, "\n"))
end

return M
