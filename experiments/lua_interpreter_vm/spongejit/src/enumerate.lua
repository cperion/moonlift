-- foundry_enumerate.lua
-- Exhaustive-ish SSA-form enumerator for the SponJIT foundry shadow model.
--
-- This is the simple foundry loop:
--   observed opcode windows -> applicable fact powersets -> Foundry SSA -> normal forms
-- The selected normal forms are the things that can later become atoms.

local Util = require("src.util")
local SSA = require("src.ssa")
local Facts = require("src.facts")

local M = {}

local ARITH = { ADD=true, ADDI=true, SUB=true, MUL=true, LT=true, LE=true, EQ=true, EQI=true, LTI=true, LEI=true, GTI=true, GEI=true }
local TABLE = { GETTABLE=true, GETI=true, SETTABLE=true, GETFIELD=true, GETTABUP=true, SELF=true, SETFIELD=true, SETTABUP=true }
local CALL = { CALL=true, TAILCALL=true }

local function op_name(x) return type(x) == "table" and tostring(x.op or x.name or x[1] or "?") or tostring(x) end

local function event_key(x)
    if type(x) ~= "table" then return tostring(x) end
    if x.codegen_op or x.op and not x.a and not x.pc then return tostring(x.codegen_op or x.op) end
    return string.format("%s(a=%s,b=%s,c=%s,k=%s,bx=%s,sbx=%s,ax=%s)",
        op_name(x), tostring(x.a), tostring(x.b), tostring(x.c), tostring(x.k), tostring(x.bx), tostring(x.sbx), tostring(x.ax))
end

local function join(xs, sep)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = event_key(x) end
    return table.concat(out, sep or "|")
end

local function fact_label(f)
    if type(f) == "table" and f.predicate then return Facts.key(f) end
    return tostring(f)
end

local function join_facts(xs, sep)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = fact_label(x) end
    return table.concat(out, sep or "|")
end

local function copy_array(xs)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = x end
    return out
end

local function add(set, x)
    local k = type(x) == "table" and x.predicate and Facts.key(x) or tostring(x)
    set[k] = x
end

local function slot_name(n)
    if n == nil then return nil end
    return "R" .. tostring(n)
end

local function ff(kind, slot, predicate, value)
    return Facts.fact(kind, Facts.slot(slot or "cur"), predicate, value, "enumerated")
end

local function gf(kind, predicate, value)
    return Facts.fact(kind, Facts.global_subject(), predicate, value, "enumerated")
end

function M.fact_axes_for_ops(ops)
    local facts = {}
    for _, ev in ipairs(ops or {}) do
        local op = op_name(ev)
        local A, B, C = type(ev) == "table" and ev.a, type(ev) == "table" and ev.b, type(ev) == "table" and ev.c
        if op == "ADD" or op == "SUB" or op == "MUL" or op == "LT" or op == "LE" or op == "EQ" then
            add(facts, B ~= nil and ff("type", slot_name(B), "is_i64") or "lhs_i64")
            add(facts, C ~= nil and ff("type", slot_name(C), "is_i64") or "rhs_i64")
        elseif op == "ADDI" or op == "EQI" or op == "LTI" or op == "LEI" or op == "GTI" or op == "GEI" then
            add(facts, B ~= nil and ff("type", slot_name(B), "is_i64") or "lhs_i64")
        elseif op == "GETTABLE" or op == "GETI" then
            add(facts, B ~= nil and ff("type", slot_name(B), "is_table") or "table")
            add(facts, C ~= nil and ff("type", slot_name(C), "key_i64") or "key_i64")
            add(facts, B ~= nil and ff("metatable", slot_name(B), "metatable_absent", true) or "metatable_absent")
            add(facts, B ~= nil and ff("array", slot_name(B), "array_hit", true) or "array_hit")
            add(facts, B ~= nil and ff("array", slot_name(B), "bounds_ok", true) or "array_bounds_known")
        elseif op == "SETTABLE" then
            add(facts, A ~= nil and ff("type", slot_name(A), "is_table") or "table")
            add(facts, B ~= nil and ff("type", slot_name(B), "key_i64") or "key_i64")
            add(facts, A ~= nil and ff("metatable", slot_name(A), "metatable_absent", true) or "metatable_absent")
            add(facts, A ~= nil and ff("array", slot_name(A), "array_hit", true) or "array_hit")
            add(facts, gf("gc", "barrier_clean", true))
        elseif op == "GETFIELD" or op == "GETTABUP" then
            add(facts, B ~= nil and ff("type", slot_name(B), "is_table") or "table")
            add(facts, B ~= nil and ff("shape", slot_name(B), "shape_known", true) or "shape_known")
            add(facts, B ~= nil and ff("metatable", slot_name(B), "metatable_absent", true) or "metatable_absent")
            add(facts, Facts.fact("constant", Facts.value("K" .. tostring(C or "key")), "key_const", true, "enumerated"))
        elseif op == "SELF" then
            add(facts, B ~= nil and ff("type", slot_name(B), "is_table") or "table")
            add(facts, B ~= nil and ff("shape", slot_name(B), "shape_known", true) or "shape_known")
            add(facts, B ~= nil and ff("metatable", slot_name(B), "metatable_absent", true) or "metatable_absent")
            add(facts, Facts.fact("constant", Facts.value("K" .. tostring(C or "key")), "key_const", true, "enumerated"))
        elseif op == "SETFIELD" or op == "SETTABUP" then
            add(facts, A ~= nil and ff("type", slot_name(A), "is_table") or "table")
            add(facts, A ~= nil and ff("shape", slot_name(A), "shape_known", true) or "shape_known")
            add(facts, A ~= nil and ff("metatable", slot_name(A), "metatable_absent", true) or "metatable_absent")
            add(facts, Facts.fact("constant", Facts.value("K" .. tostring(B or "key")), "key_const", true, "enumerated"))
            add(facts, gf("gc", "barrier_clean", true))
        elseif CALL[op] then
            add(facts, A ~= nil and ff("call", slot_name(A), "known_call_target", true) or "known_call_target")
        elseif op == "RETURN" or op == "RETURN1" then
            add(facts, A ~= nil and ff("liveness", slot_name(A), "returned", true) or "returns_prev")
        elseif op == "JMP" then
            add(facts, "branch_consumes_prev"); add(facts, "loop_backedge")
        elseif op == "FORLOOP" or op == "FORPREP" then
            add(facts, A ~= nil and ff("type", slot_name(A), "is_i64") or "loop_i64")
        end
    end

    for i = 1, #(ops or {}) - 1 do
        local a, b = op_name(ops[i]), op_name(ops[i + 1])
        if TABLE[a] and (b == "CALL" or b == "TAILCALL") then add(facts, "callee_from_prev") end
        if (a == "ADD" or a == "ADDI" or a == "SUB" or a == "MUL" or a == "GETTABLE" or a == "GETFIELD") and (b == "RETURN" or b == "RETURN1") then add(facts, "returns_prev") end
        if a == "GETTABLE" and (b == "ADD" or b == "ADDI") then add(facts, "lhs_from_prev") end
        if (a == "GETFIELD" or a == "SELF") and b == "CALL" then add(facts, "result_known_call") end
    end

    local out = {}
    for _, f in pairs(facts) do out[#out + 1] = f end
    table.sort(out, function(a, b) return fact_label(a) < fact_label(b) end)
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
                ops[#ops + 1] = events[j]
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
            local active = a.active_node_specs or a.source_ops or a.pattern or a.ops
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
                                local nf = obj.stencil_form
                                -- Always create compact representation for cross-atom optimization
                                if nf and #nf >= 1 then
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
    op = op_name(op)
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
    for _, op in ipairs(ssa.stencil_ops or {}) do
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
    for _, op in ipairs(ssa.stencil_ops or {}) do if op == "residual_boundary" or op == "unlowered_boundary" then return true end end
    return false
end

local function set_from(xs)
    local out = {}
    for _, x in ipairs(xs or {}) do out[x] = true end
    return out
end

local function is_ssa_node_op(op)
    if type(op) == "table" then return op.codegen_op ~= nil or op.output_types ~= nil or op.effect ~= nil or op.outputs ~= nil end
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
            local nf = a.stencil_form or {}
            if #nf >= 1 then
                local nf_name = join(nf, "_")
                atoms_by_nf[nf_name] = {
                    source_ops = a.source_ops or a.pattern or a.ops,
                    active_node_specs = a.active_node_specs,
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
        local expanded_nodes = nil  -- SSA internal nodes for cross-atom optimization
        local enriched_facts = nil
        if not use_nodes then
            local any_atom = false
            local all_atoms = true
            for _, op in ipairs(w.ops) do
                if atoms_by_nf[event_key(op)] then any_atom = true
                else all_atoms = false end
            end
            if any_atom then
                expanded_ops = {}
                enriched_facts = {}
                for _, op in ipairs(w.ops) do
                    local info = atoms_by_nf[event_key(op)]
                    if info then
                        for _, so in ipairs(info.source_ops) do expanded_ops[#expanded_ops + 1] = so end
                        for _, p in ipairs(info.produced or {}) do enriched_facts[#enriched_facts + 1] = p end
                        for _, c in ipairs(info.checked or {}) do enriched_facts[#enriched_facts + 1] = c end
                    else
                        expanded_ops[#expanded_ops + 1] = op
                    end
                end
                -- Also try active-ops expansion (SSA internal nodes) for cross-atom optimization
                if all_atoms then
                    expanded_nodes = {}
                    for _, op in ipairs(w.ops) do
                        local info = atoms_by_nf[event_key(op)]
                        if info and info.active_node_specs then
                            for _, ao in ipairs(info.active_node_specs) do expanded_nodes[#expanded_nodes + 1] = ao end
                        end
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
                local nf_key = join(ssa.stencil_form, "|")
                local changed = nf_key ~= w.key
                local residual = has_residual(ssa)
                -- Keep all changed forms, plus fully-native same-shape forms that consume facts.
                if changed or (not residual and #(ssa.checked_facts or {}) > 0) then
                    local key = ssa.stencil_hash
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
                            stencil_hash = ssa.stencil_hash,
                            stencil_form = ssa.stencil_form,
                            stencil_ops = ssa.stencil_ops,
                            stencil_slotmaps = ssa.slotmaps,
                            active_node_specs = ssa.active_node_specs,
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

    -- Cross-atom optimization pass: for windows containing compact atom names,
    -- expand to SSA internal nodes and run compile_nodes for cross-boundary
    -- optimization (guard dedup, value forwarding, etc.)
    if atoms and #atoms > 0 then
        local atoms_by_nf_nodes = {}
        for _, a in ipairs(atoms) do
            local nf = a.stencil_form or {}
            local active = a.active_node_specs or {}
            if #nf >= 1 and #active > 0 then
                local nf_name = join(nf, "_")
                atoms_by_nf_nodes[nf_name] = active
            end
        end
        if next(atoms_by_nf_nodes) then
            for _, w in ipairs(windows) do
                -- Check if ALL ops in this window are compact atom names with semantic node specs
                local all_have_nodes = true
                local node_seq = {}
                for _, op in ipairs(w.ops) do
                    local nodes = atoms_by_nf_nodes[event_key(op)]
                    if nodes then
                        for _, n in ipairs(nodes) do node_seq[#node_seq + 1] = n end
                    else
                        all_have_nodes = false; break
                    end
                end
                if all_have_nodes and #node_seq > 0 then
                    local nodes_ssa = SSA.compile_nodes(node_seq, {}, config)
                    total_compiles = total_compiles + 1
                    if nodes_ssa.ok then
                        total_ok = total_ok + 1
                        local nf_key = join(nodes_ssa.stencil_form, "|")
                        local changed = nf_key ~= w.key
                        local residual = has_residual(nodes_ssa)
                        if changed or (not residual and #(nodes_ssa.checked_facts or {}) > 0) then
                            local key = nodes_ssa.stencil_hash
                            local score = (tonumber(w.count) or 1) * math.max(1, base_cost(w.ops) - active_cost(nodes_ssa))
                            if changed then score = score * 1.25 end
                            if residual then score = score * 0.25 end
                            local cur = forms_by_hash[key]
                            if not cur or score > cur.score then
                                forms_by_hash[key] = {
                                    hash = key, source_key = "cross:" .. w.key,
                                    ops = copy_array(w.ops),
                                    facts = {},
                                    fact_axes = {},
                                    stencil_hash = nodes_ssa.stencil_hash,
                                    stencil_form = nodes_ssa.stencil_form,
                                    stencil_ops = nodes_ssa.stencil_ops,
                                    stencil_slotmaps = nodes_ssa.slotmaps,
                                    active_node_specs = nodes_ssa.active_node_specs,
                                    checked_facts = nodes_ssa.checked_facts,
                                    deps = nodes_ssa.deps,
                                    projection = nodes_ssa.projection,
                                    stats = nodes_ssa.stats,
                                    count = w.count, score = score,
                                    changed = changed, residual = residual,
                                    examples = copy_array(w.examples),
                                }
                            end
                        end
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

    -- Dedupe fact-subset explosions: same (source_ops, stencil_form) with
    -- different fact subsets. Keep the richest-checked form per NF; drop
    -- the weaker subsets. "Richer" = superset of checked_facts.
    local nf_best = {}
    for _, f in ipairs(forms) do
        local nf_key = join(f.ops, "|") .. "::" .. join(f.stencil_form, "|")
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
    Util.write_json(out_dir .. "/stencil_forms.json", result)
    local max_rows = tonumber(config.max_rows or 40) or 40
    local md = { "# SponJIT Stencil Form Enumeration", "" }
    local s = result.stats or {}
    md[#md + 1] = string.format("Windows: **%d**; compiles: **%d**; ok: **%d**; unique stencil forms: **%d**", s.windows or 0, s.compiles or 0, s.ok or 0, s.unique_forms or 0)
    md[#md + 1] = ""
    md[#md + 1] = "These are foundry candidates from `opcode/atom tuple × applicable fact subset -> Stencil IR form`."
    md[#md + 1] = ""
    md[#md + 1] = "| Rank | Score | Source ops | Stencil form | Facts | Checked | Residual? | Examples |"
    md[#md + 1] = "|---:|---:|---|---|---|---|---|---|"
    for i, f in ipairs(result.forms or {}) do
        if i > max_rows then break end
        md[#md + 1] = string.format("| %d | %.0f | `%s` | `%s` | `%s` | `%s` | `%s` | `%s` |",
            i, f.score or 0, join(f.ops, " "), join(f.stencil_form, " "), join_facts(f.facts, ", "), join_facts(f.checked_facts, ", "), tostring(f.residual), join(f.examples, ", "))
    end
    md[#md + 1] = ""
    Util.write_file(out_dir .. "/stencil_forms.md", table.concat(md, "\n"))
end

return M
