-- lisle/decision.lua
--
-- Build a decision tree for rule dispatch.
--
-- Current strategy: split on top-level discriminants (constructor tags and
-- literal atoms), but with better heuristics than naive first-match ordering.
--
-- Semantics are preserved by:
--   * preserving rule order inside subsets,
--   * including wildcard/non-discriminating rules in keyed buckets,
--   * maintaining explicit fallback paths.

local M = {}

local function unwrap_bind(p)
    while p and p.tag == "bind" do p = p.pat end
    return p
end

local function pat_key(p)
    p = unwrap_bind(p)
    if not p then return nil end

    if p.tag == "ctor" then
        return { kind = "ctor", name = p.ctor }
    elseif p.tag == "num" then
        return { kind = "num", value = p.value }
    elseif p.tag == "str" then
        return { kind = "str", value = p.value }
    elseif p.tag == "bool" then
        return { kind = "bool", value = p.value }
    elseif p.tag == "nil" then
        return { kind = "nil" }
    end

    return nil
end

local function key_id(k)
    if not k then return nil end
    if k.kind == "ctor" then return "ctor:" .. tostring(k.name) end
    if k.kind == "num" then return "num:" .. tostring(k.value) end
    if k.kind == "str" then return "str:" .. tostring(k.value) end
    if k.kind == "bool" then return "bool:" .. tostring(k.value) end
    if k.kind == "nil" then return "nil" end
    return nil
end

local function same_key(a, b)
    if not a or not b or a.kind ~= b.kind then return false end
    if a.kind == "ctor" then return a.name == b.name end
    if a.kind == "num" or a.kind == "str" or a.kind == "bool" then return a.value == b.value end
    if a.kind == "nil" then return true end
    return false
end

local function rule_may_match_key(rule, arg_i, k)
    local rk = pat_key(rule.patterns[arg_i])
    if rk == nil then return true end
    return same_key(rk, k)
end

local function gather_stats_for_arg(rules, ai)
    local keyed, wild = 0, 0
    local by_id = {}

    for ri = 1, #rules do
        local k = pat_key(rules[ri].patterns[ai])
        if k then
            keyed = keyed + 1
            local id = key_id(k)
            local s = by_id[id]
            if not s then
                s = { key = k, id = id, count = 0 }
                by_id[id] = s
            end
            s.count = s.count + 1
        else
            wild = wild + 1
        end
    end

    local distinct = 0
    local worst_bucket = 0
    for _, s in pairs(by_id) do
        distinct = distinct + 1
        local bucket_size = s.count + wild
        if bucket_size > worst_bucket then worst_bucket = bucket_size end
    end

    return {
        keyed = keyed,
        wild = wild,
        distinct = distinct,
        worst_bucket = worst_bucket,
        by_id = by_id,
    }
end

local function choose_split_arg(term, rules)
    local best_i, best_score = nil, -1

    for ai = 1, #term.args do
        local st = gather_stats_for_arg(rules, ai)

        if st.keyed >= 2 and st.distinct >= 2 then
            local reduction = #rules - st.worst_bucket
            if reduction > 0 then
                local score = reduction * 100 + st.keyed * 10 + st.distinct
                if score > best_score then
                    best_i, best_score = ai, score
                end
            end
        end
    end

    return best_i
end

local function collect_keys_for_arg(rules, arg_i)
    local st = gather_stats_for_arg(rules, arg_i)
    local out = {}
    for _, s in pairs(st.by_id) do out[#out + 1] = s end

    table.sort(out, function(a, b)
        local ba = a.count + st.wild
        local bb = b.count + st.wild
        if ba ~= bb then return ba > bb end
        return a.id < b.id
    end)

    local keys = {}
    for i = 1, #out do keys[i] = out[i].key end
    return keys
end

local function simple_guard_eq_constraint(rule, term, ai, aj)
    if not rule or not rule.guard or rule.guard.kind ~= "expr" then return nil end
    local ga = term.args[ai]
    local gb = term.args[aj]

    local function parse(node)
        if not node then return nil end
        if node.tag ~= "list" or #node == 0 or node[1].tag ~= "sym" then return nil end

        local h = node[1].value
        if (h == "=" or h == "~=") and #node == 3 then
            local a, b = node[2], node[3]
            if a.tag == "sym" and b.tag == "sym" then
                local ab = (a.value == ga and b.value == gb) or (a.value == gb and b.value == ga)
                if ab then return (h == "=") and "eq" or "neq" end
            end
            return nil
        end

        if h == "and" then
            local acc = nil
            for i = 2, #node do
                local c = parse(node[i])
                if c then
                    if acc and acc ~= c then return nil end
                    acc = c
                end
            end
            return acc
        end

        return nil
    end

    return parse(rule.guard.expr)
end

local function best_equal_split(term, rules)
    local best = nil

    for ai = 1, #term.args do
        for aj = ai + 1, #term.args do
            local eq, neq = 0, 0
            for ri = 1, #rules do
                local c = simple_guard_eq_constraint(rules[ri], term, ai, aj)
                if c == "eq" then eq = eq + 1
                elseif c == "neq" then neq = neq + 1 end
            end

            if eq > 0 and neq > 0 then
                local reduction = math.min(eq, neq)
                local score = reduction * 100 + eq + neq
                if (not best) or score > best.score then
                    best = { ai = ai, aj = aj, score = score }
                end
            end
        end
    end

    return best
end

local function build_node(term, rules, depth)
    depth = depth or 0

    if #rules <= 1 or depth >= 6 then
        return { kind = "leaf", rules = rules }
    end

    local eq_split = best_equal_split(term, rules)

    local key_split = nil
    local arg_i = choose_split_arg(term, rules)
    if arg_i then
        local keys = collect_keys_for_arg(rules, arg_i)
        if #keys >= 2 then
            local worst = 0
            for i = 1, #keys do
                local cnt = 0
                for ri = 1, #rules do
                    if rule_may_match_key(rules[ri], arg_i, keys[i]) then cnt = cnt + 1 end
                end
                if cnt > worst then worst = cnt end
            end
            local reduction = #rules - worst
            if reduction > 0 then
                key_split = { arg_i = arg_i, keys = keys, score = reduction * 100 + #keys }
            end
        end
    end

    if eq_split and (not key_split or eq_split.score > key_split.score) then
        local ai, aj = eq_split.ai, eq_split.aj

        local eq_rules, neq_rules = {}, {}
        for ri = 1, #rules do
            local r = rules[ri]
            local c = simple_guard_eq_constraint(r, term, ai, aj)
            if c ~= "neq" then eq_rules[#eq_rules + 1] = r end
            if c ~= "eq" then neq_rules[#neq_rules + 1] = r end
        end

        return {
            kind = "equal",
            ai = ai,
            aj = aj,
            eq_tree = build_node(term, eq_rules, depth + 1),
            neq_tree = build_node(term, neq_rules, depth + 1),
        }
    end

    if not key_split then
        return { kind = "leaf", rules = rules }
    end

    local buckets = {}
    for ki = 1, #key_split.keys do
        local k = key_split.keys[ki]
        local subset = {}
        for ri = 1, #rules do
            local r = rules[ri]
            if rule_may_match_key(r, key_split.arg_i, k) then
                subset[#subset + 1] = r
            end
        end
        buckets[#buckets + 1] = { key = k, tree = build_node(term, subset, depth + 1) }
    end

    local fallback_rules = {}
    for ri = 1, #rules do
        if pat_key(rules[ri].patterns[key_split.arg_i]) == nil then
            fallback_rules[#fallback_rules + 1] = rules[ri]
        end
    end

    local fallback = nil
    if #fallback_rules > 0 then
        fallback = build_node(term, fallback_rules, depth + 1)
    end

    return {
        kind = "split",
        arg_i = key_split.arg_i,
        buckets = buckets,
        fallback = fallback,
    }
end

function M.build(term, rules)
    return build_node(term, rules, 0)
end

return M
