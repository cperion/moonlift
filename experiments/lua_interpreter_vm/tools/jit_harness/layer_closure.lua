-- layer_closure.lua
-- Generates L1-L4 candidates by bounded-arity closure
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.9

local M = {}

-- Check if two stencil nodes can be composed
function M.can_sequence(node1, node2)
    -- Terminating opcodes cannot have successors
    local terminating = {
        RETURN = true,
        RETURN0 = true,
        RETURN1 = true,
        TAILCALL = true,
    }

    -- Get the final opcode from node1
    local op1
    if node1.ops and #node1.ops > 0 then
        op1 = node1.ops[#node1.ops]
    else
        op1 = node1.name
    end

    if terminating[op1] then
        return false
    end

    -- Both nodes must have compatible arity
    if node1.arity and node2.arity then
        if node1.arity > 4 or node2.arity > 4 then
            return false
        end
    end

    return true
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
        local node_arity = node.arity or 1
        cost.opcodes = cost.opcodes + node_arity
        cost.estimated_size = cost.estimated_size + (node_arity * 50)  -- ~50B per op
        cost.estimated_holes = cost.estimated_holes + (node_arity * 2)  -- ~2 per op
        cost.estimated_relocs = cost.estimated_relocs + (node_arity * 1)  -- ~1 per op
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

    return arity <= budget.max_arity
        and cost.opcodes <= budget.max_opcodes
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
                    ops = {seeds[i].name, seeds[j].name},
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
                            ops = {seeds[i].name, seeds[j].name, seeds[k].name},
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
                                    ops = {seeds[i].name, seeds[j].name, seeds[k].name, seeds[l].name},
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

-- Assign a unique key to a candidate
function M.assign_candidate_key(candidate)
    local key = table.concat(candidate.ops, "|")
    candidate.id = key
    candidate.key = key
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

    -- Generate all valid candidates
    local all_candidates = M.generate_closure_candidates(
        layer_input.seeds,
        config.max_arity,
        config.budget
    )

    print(string.format("Generated candidates: %d", #all_candidates))

    -- Assign keys to candidates
    local seen_keys = {}
    local unique_candidates = {}

    for _, candidate in ipairs(all_candidates) do
        local key = M.assign_candidate_key(candidate)

        if not seen_keys[key] then
            seen_keys[key] = true
            table.insert(unique_candidates, candidate)
        end
    end

    print(string.format("Unique candidates: %d", #unique_candidates))

    -- Limit to max_candidates if needed
    if #unique_candidates > config.max_candidates then
        unique_candidates = {table.unpack(unique_candidates, 1, config.max_candidates)}
        print(string.format("Pruned to max_candidates: %d", config.max_candidates))
    end

    -- Break down by arity
    local by_arity = {}
    for _, cand in ipairs(unique_candidates) do
        by_arity[cand.arity] = (by_arity[cand.arity] or 0) + 1
    end

    print("\n  By arity:")
    for arity = 2, 4 do
        if by_arity[arity] then
            print(string.format("    Arity %d: %d candidates", arity, by_arity[arity]))
        end
    end

    return {
        seeds = layer_input.seeds,
        candidates = unique_candidates,
        by_arity = by_arity,
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
