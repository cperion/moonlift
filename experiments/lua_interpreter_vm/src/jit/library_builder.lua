-- Offline stencil-library generation/pruning helpers.
--
-- This module is intentionally Lua-side build tooling. It constructs promotion
-- plans and finite runtime library specs from evidence. It does not run in the
-- hot JIT and does not materialize code.

local bit = require("bit")

local M = {}

local function copy(xs)
    local out = {}
    for i, v in ipairs(xs or {}) do out[i] = v end
    return out
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function set_from(xs)
    local s = {}
    for _, x in ipairs(xs or {}) do s[x] = true end
    return s
end

local function set_to_sorted_list(s)
    local out = {}
    for k in pairs(s or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function union_lists(...)
    local s = {}
    for i = 1, select("#", ...) do
        for _, x in ipairs(select(i, ...) or {}) do s[x] = true end
    end
    return set_to_sorted_list(s)
end

local function hash_string(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.tobit(bit.bxor(h, s:byte(i)) * 16777619)
    end
    return string.format("%08x", h < 0 and h + 4294967296 or h)
end

local function stable_value(v)
    local tv = type(v)
    if tv == "table" then
        local parts = {}
        if #v > 0 then
            for i = 1, #v do parts[#parts + 1] = stable_value(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for _, k in ipairs(sorted_keys(v)) do parts[#parts + 1] = tostring(k) .. "=" .. stable_value(v[k]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

function M.pattern_key(class, ops, effects, exits, projections)
    local parts = { class or "unknown" }
    for _, op in ipairs(ops or {}) do
        parts[#parts + 1] = tostring(op.op or op) .. stable_value(op.args or {})
    end
    if effects and #effects > 0 then parts[#parts + 1] = "effects=" .. table.concat(effects, ",") end
    if exits and #exits > 0 then parts[#parts + 1] = "exits=" .. table.concat(exits, ",") end
    if projections and #projections > 0 then parts[#parts + 1] = "projections=" .. table.concat(projections, ",") end
    return table.concat(parts, "|")
end

local function json_error(s, i, msg)
    error(string.format("json decode error at byte %d: %s near %q", i, msg, s:sub(i, i + 30)), 0)
end

function M.decode_json(s)
    local i, n = 1, #s
    local parse_value

    local function skip_ws()
        while i <= n do
            local c = s:sub(i, i)
            if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then break end
            i = i + 1
        end
    end

    local function parse_string()
        if s:sub(i, i) ~= '"' then json_error(s, i, "expected string") end
        i = i + 1
        local out = {}
        while i <= n do
            local c = s:sub(i, i)
            if c == '"' then i = i + 1; return table.concat(out) end
            if c == "\\" then
                local e = s:sub(i + 1, i + 1)
                if e == '"' or e == "\\" or e == "/" then out[#out + 1] = e; i = i + 2
                elseif e == "b" then out[#out + 1] = "\b"; i = i + 2
                elseif e == "f" then out[#out + 1] = "\f"; i = i + 2
                elseif e == "n" then out[#out + 1] = "\n"; i = i + 2
                elseif e == "r" then out[#out + 1] = "\r"; i = i + 2
                elseif e == "t" then out[#out + 1] = "\t"; i = i + 2
                elseif e == "u" then
                    -- Keep JSON unicode handling simple: ASCII escapes are decoded,
                    -- non-ASCII escapes are preserved as '?' for tooling identifiers.
                    local hx = s:sub(i + 2, i + 5)
                    local cp = tonumber(hx, 16)
                    out[#out + 1] = (cp and cp < 128) and string.char(cp) or "?"
                    i = i + 6
                else json_error(s, i, "bad string escape") end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        json_error(s, i, "unterminated string")
    end

    local function parse_number()
        local j = i
        if s:sub(i, i) == "-" then i = i + 1 end
        while s:sub(i, i):match("%d") do i = i + 1 end
        if s:sub(i, i) == "." then i = i + 1; while s:sub(i, i):match("%d") do i = i + 1 end end
        local c = s:sub(i, i)
        if c == "e" or c == "E" then
            i = i + 1
            c = s:sub(i, i)
            if c == "+" or c == "-" then i = i + 1 end
            while s:sub(i, i):match("%d") do i = i + 1 end
        end
        return tonumber(s:sub(j, i - 1))
    end

    local function parse_array()
        i = i + 1
        local out = {}
        skip_ws()
        if s:sub(i, i) == "]" then i = i + 1; return out end
        while true do
            out[#out + 1] = parse_value()
            skip_ws()
            local c = s:sub(i, i)
            if c == "]" then i = i + 1; return out end
            if c ~= "," then json_error(s, i, "expected comma or ]") end
            i = i + 1
        end
    end

    local function parse_object()
        i = i + 1
        local out = {}
        skip_ws()
        if s:sub(i, i) == "}" then i = i + 1; return out end
        while true do
            skip_ws()
            local k = parse_string()
            skip_ws()
            if s:sub(i, i) ~= ":" then json_error(s, i, "expected colon") end
            i = i + 1
            out[k] = parse_value()
            skip_ws()
            local c = s:sub(i, i)
            if c == "}" then i = i + 1; return out end
            if c ~= "," then json_error(s, i, "expected comma or }") end
            i = i + 1
        end
    end

    parse_value = function()
        skip_ws()
        local c = s:sub(i, i)
        if c == '"' then return parse_string() end
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == "-" or c:match("%d") then return parse_number() end
        if s:sub(i, i + 3) == "true" then i = i + 4; return true end
        if s:sub(i, i + 4) == "false" then i = i + 5; return false end
        if s:sub(i, i + 3) == "null" then i = i + 4; return nil end
        json_error(s, i, "unexpected token")
    end

    local v = parse_value()
    skip_ws()
    if i <= n then json_error(s, i, "trailing input") end
    return v
end

function M.read_json(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return M.decode_json(s)
end

function M.default_policy(overrides)
    local p = {
        max_arity = 4,
        max_depth = 2,
        max_covered_ops = 64,
        max_code_size = 512,
        max_holes = 24,
        max_exits = 4,
        max_variants = 4,
        max_promotions_per_round = 64,
        min_hits = 1,
        min_benefit = 0,
        code_size_tax = 1,
        materialization_tax = 4,
        exit_risk_tax = 12,
        dependency_risk_tax = 6,
    }
    for k, v in pairs(overrides or {}) do p[k] = v end
    return p
end

local function exit_is_terminal(x)
    return x ~= "SIDE_EXIT" and x ~= "SLOW" and x ~= "OOM" and x ~= "ERROR"
end

local function atom_from_candidate(c, id)
    if not c or not c.score or c.score.status ~= "complete" then return nil end
    if not c.semantic_pattern then return nil end
    local pat = c.semantic_pattern
    local holes = 0
    if c.extracted and c.extracted.holes then
        for _, h in ipairs(c.extracted.holes) do if h.offsets and #h.offsets > 0 then holes = holes + 1 end end
    end
    local relocs = 0
    if c.extracted and c.extracted.relocs then
        for _, r in ipairs(c.extracted.relocs) do if r.matches and #r.matches > 0 then relocs = relocs + 1 end end
    end
    local size = (c.extracted and c.extracted.size) or (c.score and c.score.size) or 0
    local exits = copy(pat.exits)
    local atom = {
        kind = "primitive",
        id = id,
        name = c.implements or c.name,
        symbol = c.name,
        class = c.class or pat.class,
        pattern_name = pat.name,
        ops = copy(pat.ops),
        effects = copy(pat.effects),
        exits = exits,
        projections = copy(pat.projections),
        config_axes = copy(c.config_axes),
        expansion = { c.name },
        pattern_key = c.pattern_key or pat.canonical_key,
        summary = {
            covered_ops = #(pat.ops or {}),
            closure_depth = 0,
            max_arity = 1,
            effect_count = #(pat.effects or {}),
            exit_count = #exits,
            projection_count = #(pat.projections or {}),
            hole_count = holes,
            reloc_count = relocs,
            code_size = size,
            cost_score = size + holes * 4 + relocs * 8,
        },
        physical = {
            bytes_hex = c.extracted and c.extracted.bytes_hex or nil,
            size = size,
            holes = c.extracted and c.extracted.holes or {},
            relocs = c.extracted and c.extracted.relocs or {},
        },
        status = "promoted_primitive",
    }
    atom.canonical_key = M.pattern_key(atom.class, atom.ops, atom.effects, atom.exits, atom.projections)
    return atom
end

function M.atoms_from_manifest(manifest)
    local atoms = {}
    for _, c in ipairs((manifest and manifest.candidates) or {}) do
        local a = atom_from_candidate(c, #atoms + 1)
        if a then atoms[#atoms + 1] = a end
    end
    return atoms
end

local function terminal_before_end(seq)
    for i = 1, #seq - 1 do
        for _, ex in ipairs(seq[i].exits or {}) do
            if exit_is_terminal(ex) then return true, seq[i].name .. " terminal exit " .. ex end
        end
    end
    return false
end

local function compose_sequence(seq, depth, evidence_hits)
    local bad, reason = terminal_before_end(seq)
    if bad then return nil, reason end

    local ops, effects, exits, projections = {}, {}, {}, {}
    local expansion = {}
    local size, holes, relocs, cost = 0, 0, 0, 0
    local max_child_depth = 0
    for _, a in ipairs(seq) do
        for _, op in ipairs(a.ops or {}) do ops[#ops + 1] = op end
        effects = union_lists(effects, a.effects)
        exits = union_lists(exits, a.exits)
        projections = union_lists(projections, a.projections)
        for _, e in ipairs(a.expansion or { a.name }) do expansion[#expansion + 1] = e end
        local s = a.summary or {}
        size = size + (s.code_size or 0)
        holes = holes + (s.hole_count or 0)
        relocs = relocs + (s.reloc_count or 0)
        cost = cost + (s.cost_score or 0)
        if (s.closure_depth or 0) > max_child_depth then max_child_depth = s.closure_depth or 0 end
    end

    local fusion_bonus = math.max(1, math.floor(size * 0.12)) + (#seq - 1) * 4
    local estimated_size = math.max(1, size - fusion_bonus)
    local estimated_cost = math.max(1, cost - fusion_bonus)
    local class = "compound." .. table.concat((function()
        local xs = {}; for _, a in ipairs(seq) do xs[#xs + 1] = a.class or a.name end; return xs
    end)(), "+")
    local key = M.pattern_key(class, ops, effects, exits, projections)
    local hits = evidence_hits or 1
    local benefit = hits * (cost - estimated_cost) - estimated_size

    return {
        kind = "compound_candidate",
        id = 0,
        name = "compound." .. hash_string(key),
        class = class,
        ops = ops,
        effects = effects,
        exits = exits,
        projections = projections,
        expansion = expansion,
        arity = #seq,
        canonical_key = key,
        evidence_hits = hits,
        estimated_benefit = benefit,
        summary = {
            covered_ops = #ops,
            closure_depth = math.max(depth, max_child_depth + 1),
            max_arity = #seq,
            effect_count = #effects,
            exit_count = #exits,
            projection_count = #projections,
            hole_count = holes,
            reloc_count = relocs,
            code_size = estimated_size,
            expanded_code_size = size,
            cost_score = estimated_cost,
            expanded_cost_score = cost,
        },
        replacement = {
            kind = "code_stencil_needed",
            expansion = expansion,
        },
        status = "needs_physical_fixture",
    }
end

local function within_policy(c, p)
    local s = c.summary or {}
    if (c.arity or 1) > p.max_arity then return false, "arity" end
    if (s.closure_depth or 0) > p.max_depth then return false, "depth" end
    if (s.covered_ops or 0) > p.max_covered_ops then return false, "covered_ops" end
    if (s.code_size or 0) > p.max_code_size then return false, "code_size" end
    if (s.hole_count or 0) > p.max_holes then return false, "holes" end
    if (s.exit_count or 0) > p.max_exits then return false, "exits" end
    if (c.evidence_hits or 0) < p.min_hits then return false, "hits" end
    if (c.estimated_benefit or 0) < p.min_benefit then return false, "benefit" end
    return true
end

local function dominates(a, b)
    local as, bs = a.summary or {}, b.summary or {}
    local age = (a.estimated_benefit or 0) >= (b.estimated_benefit or 0)
    local ale_size = (as.code_size or 0) <= (bs.code_size or 0)
    local ale_holes = (as.hole_count or 0) <= (bs.hole_count or 0)
    local ale_exits = (as.exit_count or 0) <= (bs.exit_count or 0)
    local one_strict = (a.estimated_benefit or 0) > (b.estimated_benefit or 0)
        or (as.code_size or 0) < (bs.code_size or 0)
        or (as.hole_count or 0) < (bs.hole_count or 0)
        or (as.exit_count or 0) < (bs.exit_count or 0)
    return age and ale_size and ale_holes and ale_exits and one_strict
end

function M.prune_candidates(candidates, policy)
    local p = M.default_policy(policy)
    local hard, rejected = {}, {}
    for _, c in ipairs(candidates or {}) do
        local ok, why = within_policy(c, p)
        if ok then hard[#hard + 1] = c else c.reject_reason = why; rejected[#rejected + 1] = c end
    end

    local frontier = {}
    for i, c in ipairs(hard) do
        local dominated = false
        for j, other in ipairs(hard) do
            if i ~= j and other.canonical_key == c.canonical_key and dominates(other, c) then dominated = true; break end
        end
        if not dominated then frontier[#frontier + 1] = c end
    end

    table.sort(frontier, function(a, b)
        if (a.estimated_benefit or 0) ~= (b.estimated_benefit or 0) then return (a.estimated_benefit or 0) > (b.estimated_benefit or 0) end
        return (a.summary.code_size or 0) < (b.summary.code_size or 0)
    end)

    local by_key, kept = {}, {}
    for _, c in ipairs(frontier) do
        if #kept >= p.max_promotions_per_round then
            c.reject_reason = "round_budget"
            rejected[#rejected + 1] = c
        else
            local k = c.canonical_key or c.pattern_key or c.name
            by_key[k] = by_key[k] or 0
            if by_key[k] < p.max_variants then
                by_key[k] = by_key[k] + 1
                c.status = "promotion_candidate"
                kept[#kept + 1] = c
            else
                c.reject_reason = "variant_budget"
                rejected[#rejected + 1] = c
            end
        end
    end
    return kept, rejected
end

local function enumerate_sequences(atoms, arity, out, prefix)
    prefix = prefix or {}
    if #prefix == arity then out[#out + 1] = copy(prefix); return end
    for _, a in ipairs(atoms) do
        prefix[#prefix + 1] = a
        enumerate_sequences(atoms, arity, out, prefix)
        prefix[#prefix] = nil
    end
end

function M.generate_closure_round(atoms, policy, depth, evidence)
    local p = M.default_policy(policy)
    local sequences = {}
    for arity = 2, p.max_arity do enumerate_sequences(atoms, arity, sequences) end

    local candidates, seen = {}, {}
    local evidence_by_key = evidence or {}
    for _, seq in ipairs(sequences) do
        local tmp_ops = {}
        for _, a in ipairs(seq) do for _, op in ipairs(a.ops or {}) do tmp_ops[#tmp_ops + 1] = op end end
        local motif = table.concat((function()
            local xs = {}; for _, op in ipairs(tmp_ops) do xs[#xs + 1] = tostring(op.op or op) end; return xs
        end)(), ",")
        local hits = evidence_by_key[motif] or evidence_by_key["*"] or 1
        local c = compose_sequence(seq, depth or 1, hits)
        if c and not seen[c.canonical_key] then
            seen[c.canonical_key] = true
            candidates[#candidates + 1] = c
        end
    end
    local kept, rejected = M.prune_candidates(candidates, p)
    return {
        depth = depth or 1,
        input_count = #atoms,
        candidate_count = #candidates,
        promoted_count = #kept,
        candidates = candidates,
        promoted = kept,
        rejected = rejected,
    }
end

function M.build_promotion_plan(manifest, policy, evidence)
    local p = M.default_policy(policy)
    local atoms = M.atoms_from_manifest(manifest)
    local library = {}
    for _, a in ipairs(atoms) do library[#library + 1] = a end
    local rounds = {}
    for depth = 1, p.max_depth do
        local round = M.generate_closure_round(library, p, depth, evidence)
        rounds[#rounds + 1] = round
        for _, c in ipairs(round.promoted) do
            c.id = #library + 1
            library[#library + 1] = c
        end
        if #round.promoted == 0 then break end
    end
    return {
        kind = "StencilPromotionPlan",
        version = 1,
        generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        policy = p,
        primitive_count = #atoms,
        library_count = #library,
        primitives = atoms,
        rounds = rounds,
        library = library,
    }
end

return M
