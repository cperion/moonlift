-- layer_closure.lua
-- Generates L1-L4 candidates by bounded-arity closure
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.9

local M = {}
local FactSchema = require("tools.jit_harness.fact_schema")

local function node_ops(node)
    if node.ops and #node.ops > 0 then return node.ops end
    return { node.name or node.id or "unknown" }
end

local function concat_ops(nodes)
    local ops = {}
    for _, node in ipairs(nodes or {}) do
        for _, op in ipairs(node_ops(node)) do table.insert(ops, op) end
    end
    return ops
end

-- Check if two stencil nodes can be composed
function M.can_sequence(node1, node2)
    -- Semantic boundary shapes cannot have successors unless a future explicit
    -- boundary-link lowering exists.
    local shape1 = node1 and node1.shape_kind
    if shape1 == "terminal_return" or shape1 == "branch_or_control_boundary" or shape1 == "call_boundary" or shape1 == "effect_boundary" then
        return false
    end

    -- Terminating opcodes cannot have successors
    local terminating = {
        RETURN = true,
        RETURN0 = true,
        RETURN1 = true,
        TAILCALL = true,
        JMP = true,
        EQ = true,
        LT = true,
        LE = true,
        EQK = true,
        EQI = true,
        LTI = true,
        LEI = true,
        GTI = true,
        GEI = true,
        TEST = true,
        TESTSET = true,
    }

    -- Get the final opcode from node1
    local op1
    local ops1 = node_ops(node1)
    op1 = ops1[#ops1]

    if terminating[op1] then
        return false
    end

    return true
end

local function node_native_size(node)
    return tonumber(node.object_size or (node.compiled_object and node.compiled_object.size_bytes) or (node.native_artifact and node.native_artifact.size_bytes) or (node.cost and node.cost.estimated_size) or 0) or 0
end

-- Estimate cost of a candidate sequence
function M.estimate_cost(nodes)
    if not nodes then
        nodes = {}
    end

    local cost = {
        opcodes = 0,
        estimated_size = 0,
        estimated_holes = 0,
        estimated_relocs = 0,
    }

    for _, node in ipairs(nodes) do
        local node_arity = node.unit_arity or node.arity or #(node_ops(node)) or 1
        local nsize = node_native_size(node)
        cost.opcodes = cost.opcodes + node_arity
        cost.estimated_size = cost.estimated_size + (nsize > 0 and nsize or (node_arity * 50))
        cost.estimated_holes = cost.estimated_holes + ((node.cost and node.cost.estimated_holes) or #(node.holes or {}) or 0)
        cost.estimated_relocs = cost.estimated_relocs + ((node.cost and node.cost.estimated_relocs) or #(node.relocs or {}) or 0)
    end

    return cost
end

-- Check if candidate meets budget constraints
function M.meets_budget(candidate, budget)
    local default_budget = {
        max_arity = 4,
        max_opcodes = 16,
        max_size = 450,
        max_holes = 25,
        max_relocs = 20,
    }

    -- Merge passed budget with defaults
    if budget then
        for k, v in pairs(default_budget) do
            if budget[k] == nil then
                budget[k] = v
            end
        end
    else
        budget = default_budget
    end

    local cost = candidate.cost or M.estimate_cost(candidate.nodes)
    local arity = #candidate.nodes

    local opcode_ok = candidate.native_composition and true or cost.opcodes <= budget.max_opcodes
    return arity <= budget.max_arity
        and opcode_ok
        and cost.estimated_size <= budget.max_size
        and cost.estimated_holes <= budget.max_holes
        and cost.estimated_relocs <= budget.max_relocs
end

-- Generate all valid pairs from a stencil set
function M.generate_pairs(seeds, budget)
    local pairs = {}

    for i = 1, #seeds do
        for j = 1, #seeds do
            if M.can_sequence(seeds[i], seeds[j]) then
                local candidate = {
                    nodes = {seeds[i], seeds[j]},
                    arity = 2,
                    ops = concat_ops({seeds[i], seeds[j]}),
                    cost = nil,
                }

                candidate.cost = M.estimate_cost(candidate.nodes)

                if M.meets_budget(candidate, budget) then
                    table.insert(pairs, candidate)
                end
            end
        end
    end

    return pairs
end

-- Generate all valid triples from a stencil set
function M.generate_triples(seeds, budget)
    local triples = {}

    for i = 1, #seeds do
        for j = 1, #seeds do
            if M.can_sequence(seeds[i], seeds[j]) then
                for k = 1, #seeds do
                    if M.can_sequence(seeds[j], seeds[k]) then
                        local candidate = {
                            nodes = {seeds[i], seeds[j], seeds[k]},
                            arity = 3,
                            ops = concat_ops({seeds[i], seeds[j], seeds[k]}),
                            cost = nil,
                        }

                        candidate.cost = M.estimate_cost(candidate.nodes)

                        if M.meets_budget(candidate, budget) then
                            table.insert(triples, candidate)
                        end
                    end
                end
            end
        end
    end

    return triples
end

-- Generate all valid quads from a stencil set
function M.generate_quads(seeds, budget)
    local quads = {}

    for i = 1, #seeds do
        for j = 1, #seeds do
            if M.can_sequence(seeds[i], seeds[j]) then
                for k = 1, #seeds do
                    if M.can_sequence(seeds[j], seeds[k]) then
                        for l = 1, #seeds do
                            if M.can_sequence(seeds[k], seeds[l]) then
                                local candidate = {
                                    nodes = {seeds[i], seeds[j], seeds[k], seeds[l]},
                                    arity = 4,
                                    ops = concat_ops({seeds[i], seeds[j], seeds[k], seeds[l]}),
                                    cost = nil,
                                }

                                candidate.cost = M.estimate_cost(candidate.nodes)

                                if M.meets_budget(candidate, budget) then
                                    table.insert(quads, candidate)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return quads
end

local function split_pattern_key(key)
    local ops = {}
    for op in tostring(key):gmatch("[^|]+") do ops[#ops + 1] = op end
    return ops
end

local function copy_facts_from_nodes(nodes)
    local facts = {}
    for _, node in ipairs(nodes or {}) do
        for _, f in ipairs(node.facts or {}) do facts[#facts + 1] = f end
    end
    return facts
end

local function motif_entries(profile_db, max_motifs)
    local entries = {}
    for key, count in pairs((profile_db and profile_db.motif_counts) or {}) do
        entries[#entries + 1] = { key = key, count = count }
    end
    table.sort(entries, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.key < b.key
    end)
    if max_motifs and #entries > max_motifs then
        local trimmed = {}
        for i = 1, max_motifs do trimmed[i] = entries[i] end
        entries = trimmed
    end
    return entries
end

local function ops_match_at(motif_ops, pos, atom_ops)
    if pos + #atom_ops - 1 > #motif_ops then return false end
    for i = 1, #atom_ops do
        if motif_ops[pos + i - 1] ~= atom_ops[i] then return false end
    end
    return true
end

function M.generate_motif_composed_candidates(atoms, profile_db, config)
    config = config or {}
    local budget = config.budget or {}
    local max_nodes = tonumber(config.max_atom_nodes or config.max_arity or 4) or 4
    local max_opcodes = tonumber((budget and budget.max_opcodes) or config.max_opcodes or 16) or 16
    local max_motifs = tonumber(config.max_motifs or 200) or 200
    local max_generated = tonumber(config.max_generated or config.max_candidates or 10000) or 10000
    local atom_list = {}
    for _, atom in ipairs(atoms or {}) do
        if atom.ops and #atom.ops > 0 then atom_list[#atom_list + 1] = atom end
    end
    table.sort(atom_list, function(a, b)
        if #a.ops ~= #b.ops then return #a.ops > #b.ops end
        return tostring(a.id or a.name) < tostring(b.id or b.name)
    end)

    local by_first = {}
    for _, atom in ipairs(atom_list) do
        local first = atom.ops[1]
        by_first[first] = by_first[first] or {}
        by_first[first][#by_first[first] + 1] = atom
    end

    local out, seen = {}, {}
    local function add_candidate(nodes, count)
        local ops = concat_ops(nodes)
        if #ops == 0 or #ops > max_opcodes then return end
        local facts = copy_facts_from_nodes(nodes)
        local fact_key = FactSchema.fact_key(facts)
        local id = table.concat(ops, "|") .. (fact_key ~= "" and (" @ " .. fact_key) or "")
        local existing = seen[id]
        if existing then
            existing.profile_count = (existing.profile_count or 0) + count
            return
        end
        local cand = {
            nodes = nodes,
            atom_count = #nodes,
            arity = #ops,
            ops = ops,
            facts = facts,
            fact_key = fact_key ~= "" and fact_key or "generic",
            source = "motif_composed_selected_atoms",
            profile_count = count,
            cost = M.estimate_cost(nodes),
        }
        if M.meets_budget(cand, budget) then
            seen[id] = cand
            out[#out + 1] = cand
        end
    end

    for _, entry in ipairs(motif_entries(profile_db, max_motifs)) do
        if #out >= max_generated then break end
        local motif_ops = split_pattern_key(entry.key)
        for start = 1, #motif_ops do
            local function rec(pos, nodes, opcode_count)
                if #out >= max_generated then return end
                if #nodes >= 2 then add_candidate(nodes, entry.count) end
                if #nodes >= max_nodes or opcode_count >= max_opcodes then return end
                local choices = by_first[motif_ops[pos]] or {}
                for _, atom in ipairs(choices) do
                    local aops = atom.ops or {}
                    if opcode_count + #aops <= max_opcodes and ops_match_at(motif_ops, pos, aops) then
                        if #nodes == 0 or M.can_sequence(nodes[#nodes], atom) then
                            local next_nodes = {}
                            for i, n in ipairs(nodes) do next_nodes[i] = n end
                            next_nodes[#next_nodes + 1] = atom
                            rec(pos + #aops, next_nodes, opcode_count + #aops)
                        end
                    end
                end
            end
            rec(start, {}, 0)
        end
    end

    table.sort(out, function(a, b)
        if (a.profile_count or 0) ~= (b.profile_count or 0) then return (a.profile_count or 0) > (b.profile_count or 0) end
        return table.concat(a.ops, "|") < table.concat(b.ops, "|")
    end)
    return out
end

local function sequence_count_index(profile_db, max_len)
    local counts = {}
    max_len = max_len or 16
    for k, v in pairs((profile_db and profile_db.window_counts) or {}) do
        counts[k] = (counts[k] or 0) + (tonumber(v) or 0)
    end
    for k, v in pairs((profile_db and profile_db.motif_counts) or {}) do
        local ops = split_pattern_key(k)
        local count = tonumber(v) or 0
        for len = 1, math.min(max_len, #ops) do
            for i = 1, #ops - len + 1 do
                local parts = {}
                for j = 0, len - 1 do parts[#parts + 1] = ops[i + j] end
                local sub = table.concat(parts, "|")
                counts[sub] = (counts[sub] or 0) + count
            end
        end
    end
    return counts
end

local function node_layer(node)
    return tonumber(node.layer or node.layer_id or 0) or 0
end

local function source_layers(nodes)
    local set, out = {}, {}
    for _, n in ipairs(nodes or {}) do
        local l = node_layer(n)
        if not set[l] then set[l] = true; out[#out + 1] = l end
    end
    table.sort(out)
    return out
end

function M.generate_unit_closure_candidates(atoms, config)
    config = config or {}
    local budget = config.budget or {}
    local max_units = tonumber(config.max_arity or (budget and budget.max_arity) or 4) or 4
    local min_units = tonumber(config.min_unit_arity or 1) or 1
    local required_source_layer = config.required_source_layer ~= nil and tonumber(config.required_source_layer) or nil
    local native_composition = config.native_composition == true
    local max_profile_span = tonumber(config.max_profile_span or config.max_opcodes or (budget and budget.max_opcodes) or 32) or 32
    local min_frequency = tonumber(config.min_candidate_frequency or 1) or 1
    local counts = sequence_count_index(config.profile_db, max_profile_span)
    local out, enumerated, pruned_slow, pruned_budget, pruned_shape = {}, 0, 0, 0, 0

    local atom_list = {}
    for _, atom in ipairs(atoms or {}) do
        if atom.ops and #atom.ops > 0 then
            M.apply_shape_metadata(atom)
            if (not native_composition) or node_layer(atom) == 0 or atom.native_artifact or atom.compiled_object or atom.object_path or atom.object_size then
                atom_list[#atom_list + 1] = atom
            end
        end
    end
    table.sort(atom_list, function(a, b)
        local af, bf = tonumber(a.selection_score or a.priority or 0) or 0, tonumber(b.selection_score or b.priority or 0) or 0
        if af ~= bf then return af > bf end
        return tostring(a.id or a.name) < tostring(b.id or b.name)
    end)

    local function add_or_continue(nodes)
        local ops = concat_ops(nodes)
        if #ops == 0 or #ops > max_profile_span then pruned_budget = pruned_budget + 1; return false end
        local pattern = table.concat(ops, "|")
        local freq = counts[pattern] or 0
        if freq < min_frequency then pruned_slow = pruned_slow + 1; return false end
        local cost = M.estimate_cost(nodes)
        local prefix = { nodes = nodes, cost = cost, native_composition = native_composition }
        if not M.meets_budget(prefix, budget) then
            pruned_budget = pruned_budget + 1
            return false
        end
        if #nodes < min_units then
            return true
        end
        if required_source_layer ~= nil then
            local has_required = false
            for _, n in ipairs(nodes) do
                if node_layer(n) == required_source_layer then has_required = true; break end
            end
            if not has_required then return true end
        end
        local cand = {
            nodes = nodes,
            unit_arity = #nodes,
            arity = #ops,
            opcode_arity = #ops,
            ops = ops,
            facts = copy_facts_from_nodes(nodes),
            source_layers = source_layers(nodes),
            source = native_composition and "native_unit_closure" or "cumulative_unit_closure",
            native_composition = native_composition,
            kind = native_composition and "COMPOSED_NATIVE_STENCIL" or nil,
            profile_count = freq,
            cost = cost,
        }
        cand.fact_key = FactSchema.fact_key(cand.facts)
        if cand.fact_key == "" then cand.fact_key = "generic" end
        out[#out + 1] = cand
        return true
    end

    local function rec(nodes, opcode_count)
        if #nodes >= max_units then return end
        for _, atom in ipairs(atom_list) do
            enumerated = enumerated + 1
            if #nodes == 0 or M.can_sequence(nodes[#nodes], atom) then
                local aops = node_ops(atom)
                if opcode_count + #aops <= max_profile_span then
                    if native_composition and node_layer(atom) > 0 and not (atom.compiled_object or atom.native_artifact or atom.object_path or atom.object_size) then
                        pruned_budget = pruned_budget + 1
                    else
                        local next_nodes = {}
                        for i, n in ipairs(nodes) do next_nodes[i] = n end
                        next_nodes[#next_nodes + 1] = atom
                        if add_or_continue(next_nodes) then
                            rec(next_nodes, opcode_count + #aops)
                        end
                    end
                else
                    pruned_budget = pruned_budget + 1
                end
            else
                pruned_shape = pruned_shape + 1
            end
        end
    end

    rec({}, 0)
    table.sort(out, function(a, b)
        if (a.profile_count or 0) ~= (b.profile_count or 0) then return (a.profile_count or 0) > (b.profile_count or 0) end
        return table.concat(a.ops or {}, "|") < table.concat(b.ops or {}, "|")
    end)
    return out, { enumerated = enumerated, pruned_slow = pruned_slow, pruned_budget = pruned_budget, pruned_shape = pruned_shape, atom_count = #atom_list }
end

function M.generate_profile_window_candidates(profile_db, max_arity, budget)
    max_arity = max_arity or 4
    budget = budget or {}
    local out = {}
    for key, count in pairs((profile_db and profile_db.window_counts) or {}) do
        local ops = split_pattern_key(key)
        if #ops >= 1 and #ops <= max_arity then
            local candidate = {
                nodes = {},
                arity = #ops,
                ops = ops,
                source = "profile_window",
                profile_count = count,
                cost = {
                    opcodes = #ops,
                    estimated_size = #ops * 50,
                    estimated_holes = #ops * 2,
                    estimated_relocs = #ops,
                },
            }
            if M.meets_budget(candidate, budget) then out[#out + 1] = candidate end
        end
    end
    table.sort(out, function(a, b)
        if (a.profile_count or 0) ~= (b.profile_count or 0) then
            return (a.profile_count or 0) > (b.profile_count or 0)
        end
        return table.concat(a.ops, "|") < table.concat(b.ops, "|")
    end)
    return out
end

-- Generate all valid candidates up to max_arity
function M.generate_closure_candidates(seeds, max_arity, budget)
    max_arity = max_arity or 4
    budget = budget or {}

    local all_candidates = {}

    -- Generate pairs
    if max_arity >= 2 then
        local pairs = M.generate_pairs(seeds, budget)
        for _, p in ipairs(pairs) do
            table.insert(all_candidates, p)
        end
    end

    -- Generate triples
    if max_arity >= 3 then
        local triples = M.generate_triples(seeds, budget)
        for _, t in ipairs(triples) do
            table.insert(all_candidates, t)
        end
    end

    -- Generate quads
    if max_arity >= 4 then
        local quads = M.generate_quads(seeds, budget)
        for _, q in ipairs(quads) do
            table.insert(all_candidates, q)
        end
    end

    return all_candidates
end

local function fact_axes_for_op(op)
    return FactSchema.axes_for_op(op)
end

local function fact_key_for(facts)
    return FactSchema.fact_key(facts)
end

function M.enumerate_fact_sets_for_ops(ops, config)
    config = config or {}
    local max_variants = config.max_fact_variants or 16
    local sets = { {} }
    for _, op in ipairs(ops or {}) do
        local axes = fact_axes_for_op(op)
        local next_sets = {}
        for _, prefix in ipairs(sets) do
            for _, axis in ipairs(axes) do
                local copy = {}
                for i, f in ipairs(prefix) do copy[i] = f end
                copy[#copy + 1] = axis
                next_sets[#next_sets + 1] = copy
                if #next_sets >= max_variants then break end
            end
            if #next_sets >= max_variants then break end
        end
        sets = next_sets
    end
    local out = {}
    for _, facts in ipairs(sets) do
        out[#out + 1] = { facts = facts, fact_key = fact_key_for(facts) }
    end
    return out
end

local function rewrite_shape(kind)
    if kind == "op_return1" then
        return {
            shape_kind = "terminal_return",
            continuation = "return_boundary_pc_plus_2",
            effect_context = "return_boundary",
        }
    elseif kind == "op_move_final_dst" then
        return {
            shape_kind = "guarded_pure_rewrite",
            continuation = "fallthrough_pc_plus_2_or_side_exit",
            effect_context = "guarded_pure",
        }
    end
    return {
        shape_kind = "pure_rewrite",
        continuation = "fallthrough_pc_plus_2",
        effect_context = "pure",
    }
end

local function add_sequence_rewrite_variants(out, cand)
    local ops = cand.ops or {}
    local function clone_with(kind, facts, comment)
        local copy = {}
        for k, v in pairs(cand) do copy[k] = v end
        local shape = rewrite_shape(kind)
        copy.rewrite_kind = kind
        copy.lowering = kind
        copy.shape_kind = shape.shape_kind
        copy.continuation = shape.continuation
        copy.effect_context = shape.effect_context
        copy.legalization_source = "operand_fact_rewrite_schema"
        copy.requires_shape = true
        copy.facts = facts
        copy.fact_key = FactSchema.fact_key(facts)
        copy.kind = "REWRITE_STENCIL"
        copy.comments = comment
        out[#out + 1] = copy
    end

    -- These are L0 rewrite schemas instantiated over concrete L1 patterns.
    -- They require def-use/liveness facts; without those facts the generic
    -- opcode composition remains available separately.
    if #ops == 2 and ops[1] == "MOVE" and ops[2] == "MOVE" then
        clone_with("move_move_forward", {
            { op = "MOVE", kind = "move_def", effect = "pure", projection = "none", dependency = "none" },
            { op = "MOVE", kind = "move_uses_previous_def", requires = { "move1.dst == move2.src", "move1.dst_dead" }, effect = "pure_rewrite", projection = "none", dependency = "none" },
        }, "MOVE;MOVE -> direct MOVE when first destination feeds second and is dead")
        clone_with("move_move_empty", {
            { op = "MOVE", kind = "redundant_move", requires = { "src == dst" }, effect = "pure_rewrite", projection = "none", dependency = "none" },
            { op = "MOVE", kind = "redundant_move", requires = { "src == dst" }, effect = "pure_rewrite", projection = "none", dependency = "none" },
        }, "MOVE;MOVE -> empty when both moves are self moves")
    end

    if #ops == 2 and (ops[1] == "LOADK" or ops[1] == "LOADI" or ops[1] == "LOADF") and ops[2] == "MOVE" then
        clone_with("load_move_final_dst", {
            { op = ops[1], kind = "load_def", effect = "pure", projection = "none", dependency = "none" },
            { op = "MOVE", kind = "move_uses_previous_def", requires = { "load.dst == move.src", "load.dst_dead" }, effect = "pure_rewrite", projection = "none", dependency = "none" },
        }, ops[1] .. ";MOVE -> " .. ops[1] .. " to final destination")
    end

    if #ops == 2 and (ops[1] == "ADD" or ops[1] == "SUB" or ops[1] == "MUL" or ops[1] == "ADDI") and ops[2] == "MOVE" then
        clone_with("op_move_final_dst", {
            { op = ops[1], kind = "i64", requires = { "lhs_i64", "rhs_i64" }, effect = "guarded_pure", projection = "side_exit", dependency = "none" },
            { op = "MOVE", kind = "move_uses_previous_def", requires = { "op.dst == move.src", "op.dst_dead" }, effect = "pure_rewrite", projection = "none", dependency = "none" },
        }, ops[1] .. ";MOVE -> " .. ops[1] .. " to final destination")
    end

    if #ops == 2 and (ops[1] == "ADD" or ops[1] == "SUB" or ops[1] == "MUL" or ops[1] == "ADDI") and ops[2] == "RETURN1" then
        clone_with("op_return1", {
            { op = ops[1], kind = "i64", requires = { "lhs_i64", "rhs_i64" }, effect = "guarded_pure", projection = "side_exit", dependency = "none" },
            { op = "RETURN1", kind = "returns_previous_def", requires = { "op.dst == return.src" }, effect = "return_boundary", projection = "interpreter", dependency = "none" },
        }, ops[1] .. ";RETURN1 -> arithmetic-return terminal stencil")
    end
end

function M.expand_fact_variants(candidates, config)
    config = config or {}
    if config.enumerate_facts == false then return candidates end
    local expanded = {}
    for _, cand in ipairs(candidates or {}) do
        local variants = M.enumerate_fact_sets_for_ops(cand.ops or {}, config)
        for _, variant in ipairs(variants) do
            local copy = {}
            for k, v in pairs(cand) do copy[k] = v end
            copy.facts = variant.facts
            copy.fact_key = variant.fact_key ~= "" and variant.fact_key or "generic"
            expanded[#expanded + 1] = copy
        end
        add_sequence_rewrite_variants(expanded, cand)
    end
    return expanded
end

function M.apply_shape_metadata(candidate)
    if candidate.shape_kind and candidate.lowering then return candidate end
    if candidate.rewrite_kind then
        local shape = rewrite_shape(candidate.rewrite_kind)
        candidate.lowering = candidate.lowering or candidate.rewrite_kind
        candidate.shape_kind = candidate.shape_kind or shape.shape_kind
        candidate.continuation = candidate.continuation or shape.continuation
        candidate.effect_context = candidate.effect_context or shape.effect_context
        candidate.legalization_source = candidate.legalization_source or "operand_fact_rewrite_schema"
        candidate.requires_shape = candidate.requires_shape ~= false
        candidate.kind = candidate.kind or "REWRITE_STENCIL"
        return candidate
    end
    local ops = candidate.ops or {}
    local has_return, has_branch, has_call, has_effect = false, false, false, false
    local has_interpreter_boundary, has_side_exit = false, false
    for _, f in ipairs(candidate.facts or {}) do
        local kind = tostring(f.kind or "")
        local projection = tostring(f.projection or "")
        local effect = tostring(f.effect or "")
        if kind:find("generic_", 1, true) or projection == "interpreter" or effect == "boundary" then has_interpreter_boundary = true end
        if projection == "side_exit" then has_side_exit = true end
        if projection == "call_boundary" or effect == "may_call" then has_call = true end
        if projection == "barrier" or effect == "writes_heap" then has_effect = true end
    end
    for _, op in ipairs(ops) do
        if op == "RETURN0" or op == "RETURN1" or op == "RETURN" then has_return = true end
        if op == "EQ" or op == "EQK" or op == "LT" or op == "LE" or op == "TEST" or op == "TESTSET" or op == "JMP" or op == "FORPREP" or op == "FORLOOP" then has_branch = true end
        if op == "CALL" or op == "TAILCALL" then has_call = true end
        if op == "SETFIELD" or op == "SETTABLE" or op == "SETTABUP" or op == "SETI" or op == "NEWTABLE" or op == "CLOSURE" then has_effect = true end
    end
    candidate.lowering = candidate.lowering or "generic_opcode_sequence"
    candidate.requires_shape = candidate.requires_shape ~= false
    candidate.legalization_source = candidate.legalization_source or "default_opcode_shape"
    if has_return then
        candidate.shape_kind = "terminal_return"
        candidate.continuation = "return_boundary"
        candidate.effect_context = "return_boundary"
    elseif has_call then
        candidate.shape_kind = "call_boundary"
        candidate.continuation = "side_exit_or_call_boundary"
        candidate.effect_context = "may_yield_or_reenter"
    elseif has_branch then
        candidate.shape_kind = "branch_or_control_boundary"
        candidate.continuation = "branch_pc_or_side_exit"
        candidate.effect_context = "control"
    elseif has_effect or has_interpreter_boundary then
        candidate.shape_kind = "effect_boundary"
        candidate.continuation = has_interpreter_boundary and "side_exit_to_interpreter" or "side_exit_or_fallthrough"
        candidate.effect_context = has_interpreter_boundary and "interpreter_boundary" or "may_write_or_allocate"
    elseif has_side_exit then
        candidate.shape_kind = "guarded_fallthrough"
        candidate.continuation = "fallthrough_or_side_exit"
        candidate.effect_context = "guarded_pure"
    else
        candidate.shape_kind = "fallthrough"
        candidate.continuation = "fallthrough_pc_plus_arity"
        candidate.effect_context = "pure_or_guarded"
    end
    return candidate
end

-- Assign a unique key to a candidate
function M.assign_candidate_key(candidate)
    local key = table.concat(candidate.ops, "|")
    if candidate.fact_key and candidate.fact_key ~= "" and candidate.fact_key ~= "generic" then
        key = key .. " @ " .. candidate.fact_key
    end
    candidate.id = key
    candidate.key = key
    candidate.pattern_key = table.concat(candidate.ops, "|")
    return key
end

-- Build layer from seed manifest
function M.build_layer(layer_input, config)
    config = config or {}
    config.max_arity = config.max_arity or 4
    config.max_candidates = config.max_candidates or 1000
    config.budget = config.budget or {
        max_arity = 4,
        max_opcodes = 16,
        max_size = 450,
        max_holes = 25,
        max_relocs = 20,
    }

    print("\n=== Building Layer ===")
    print(string.format("Input seeds: %d", #layer_input.seeds))

    local profile_db = config.profile_db or layer_input.profile_db

    -- Generate layer closure over the cumulative atom pool. Arity means number
    -- of composed units, not resulting opcode span. Profile data is only a
    -- slow-candidate filter/scheduler; it does not define the layer semantics.
    local all_candidates
    local inherited_atom_facts = config.inherit_atom_facts == true
    if profile_db and config.profile_slow_filter ~= false then
        local stats
        all_candidates, stats = M.generate_unit_closure_candidates(layer_input.seeds, {
            max_arity = config.max_arity,
            max_opcodes = config.budget and config.budget.max_opcodes,
            max_profile_span = config.max_profile_span,
            native_composition = config.native_composition,
            min_candidate_frequency = config.min_candidate_frequency or 1,
            min_unit_arity = config.min_unit_arity or 1,
            required_source_layer = config.required_source_layer,
            budget = config.budget,
            profile_db = profile_db,
        })
        print(string.format("Generated cumulative unit-closure candidates: %d", #all_candidates))
        print(string.format("  Atom pool: %d", stats.atom_count or 0))
        print(string.format("  Enumerated tuple prefixes: %d", stats.enumerated or 0))
        print(string.format("  Pruned slow/unobserved: %d", stats.pruned_slow or 0))
        print(string.format("  Pruned budget: %d", stats.pruned_budget or 0))
        print(string.format("  Pruned shape: %d", stats.pruned_shape or 0))
    else
        all_candidates = M.generate_closure_candidates(layer_input.seeds, config.max_arity, config.budget)
        print(string.format("Generated closure candidates: %d", #all_candidates))
    end

    do
        local generated_by_opcode_arity, generated_by_unit_arity = {}, {}
        for _, cand in ipairs(all_candidates) do
            local oa, ua = #(cand.ops or {}), cand.unit_arity or #(cand.nodes or {})
            generated_by_opcode_arity[oa] = (generated_by_opcode_arity[oa] or 0) + 1
            generated_by_unit_arity[ua] = (generated_by_unit_arity[ua] or 0) + 1
        end
        local max_unit_seen, max_opcode_seen = 0, 0
        for arity in pairs(generated_by_unit_arity) do if arity > max_unit_seen then max_unit_seen = arity end end
        for arity in pairs(generated_by_opcode_arity) do if arity > max_opcode_seen then max_opcode_seen = arity end end
        print("  Generated by unit arity:")
        for arity = 1, max_unit_seen do
            if generated_by_unit_arity[arity] then print(string.format("    Unit arity %d: %d candidates", arity, generated_by_unit_arity[arity])) end
        end
        print("  Generated by opcode span:")
        for arity = 1, max_opcode_seen do
            if generated_by_opcode_arity[arity] then print(string.format("    Opcode span %d: %d candidates", arity, generated_by_opcode_arity[arity])) end
        end
    end

    if inherited_atom_facts then
        print(string.format("Inherited selected atom facts: %d", #all_candidates))
    else
        all_candidates = M.expand_fact_variants(all_candidates, config)
        if config.enumerate_facts ~= false then
            print(string.format("Fact-expanded candidates: %d", #all_candidates))
        end
    end

    -- Assign keys to candidates
    local seen_keys = {}
    local unique_candidates = {}

    for _, candidate in ipairs(all_candidates) do
        M.apply_shape_metadata(candidate)
        local key = M.assign_candidate_key(candidate)

        if not seen_keys[key] then
            seen_keys[key] = true
            table.insert(unique_candidates, candidate)
        end
    end

    print(string.format("Unique candidates: %d", #unique_candidates))

    if profile_db and profile_db.window_counts then
        table.sort(unique_candidates, function(a, b)
            local ak = a.pattern_key or table.concat(a.ops or {}, "|")
            local bk = b.pattern_key or table.concat(b.ops or {}, "|")
            local aid = a.id or (ak .. (a.fact_key and (" @ " .. a.fact_key) or ""))
            local bid = b.id or (bk .. (b.fact_key and (" @ " .. b.fact_key) or ""))
            local af = (profile_db.rewrite_fact_counts and profile_db.rewrite_fact_counts[aid]) or (profile_db.window_counts and profile_db.window_counts[ak]) or 0
            local bf = (profile_db.rewrite_fact_counts and profile_db.rewrite_fact_counts[bid]) or (profile_db.window_counts and profile_db.window_counts[bk]) or 0
            if af ~= bf then return af > bf end
            return (a.id or "") < (b.id or "")
        end)
        print("Scheduled candidates by profile frequency before cap")
    end

    -- Limit to max_candidates if needed
    if #unique_candidates > config.max_candidates then
        unique_candidates = {unpack(unique_candidates, 1, config.max_candidates)}
        print(string.format("Pruned to max_candidates: %d", config.max_candidates))
    end

    -- Break down by unit arity and opcode span after scheduling/cap.
    local by_arity, by_opcode_span = {}, {}
    for _, cand in ipairs(unique_candidates) do
        local unit_arity = cand.unit_arity or #(cand.nodes or {})
        local opcode_arity = #(cand.ops or {})
        by_arity[unit_arity] = (by_arity[unit_arity] or 0) + 1
        by_opcode_span[opcode_arity] = (by_opcode_span[opcode_arity] or 0) + 1
    end

    local max_unit_retained_seen, max_opcode_retained_seen = 0, 0
    for arity in pairs(by_arity) do if arity > max_unit_retained_seen then max_unit_retained_seen = arity end end
    for arity in pairs(by_opcode_span) do if arity > max_opcode_retained_seen then max_opcode_retained_seen = arity end end
    print("\n  Retained by unit arity:")
    for arity = 1, max_unit_retained_seen do
        if by_arity[arity] then print(string.format("    Unit arity %d: %d candidates", arity, by_arity[arity])) end
    end
    print("\n  Retained by opcode span:")
    for arity = 1, max_opcode_retained_seen do
        if by_opcode_span[arity] then print(string.format("    Opcode span %d: %d candidates", arity, by_opcode_span[arity])) end
    end

    return {
        seeds = layer_input.seeds,
        candidates = unique_candidates,
        by_arity = by_arity,
        by_opcode_span = by_opcode_span,
        total_candidates = #unique_candidates,
    }
end

-- Report layer generation results
function M.report_layer(layer_result)
    print("\n=== Layer Generation Summary ===")
    print(string.format("Input seeds: %d", #layer_result.seeds))
    print(string.format("Generated candidates: %d", layer_result.total_candidates))

    if layer_result.total_candidates > 0 then
        print("\n  Top 10 candidates by size:")
        local sorted = {}
        for _, cand in ipairs(layer_result.candidates) do
            table.insert(sorted, {
                id = cand.id,
                size = cand.cost.estimated_size,
                arity = cand.arity,
            })
        end
        table.sort(sorted, function(a, b) return a.size > b.size end)

        for i = 1, math.min(10, #sorted) do
            local c = sorted[i]
            print(string.format("    %s (arity=%d, size=%dB)",
                c.id, c.arity, c.size))
        end
    end
end

return M
