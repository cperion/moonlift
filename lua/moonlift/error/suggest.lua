-- moonlift/error/suggest.lua
-- "Did you mean?" candidate search for error suggestions.
--
-- Uses Levenshtein distance and prefix matching to suggest likely
-- corrections for unresolved names, unknown continuations, etc.

local M = {}

-------------------------------------------------------------------------------
-- Levenshtein distance
-------------------------------------------------------------------------------

function M.levenshtein(a, b)
    if a == b then return 0 end
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end

    -- Optimize: strip common prefix
    local start = 1
    while start <= la and start <= lb and string.byte(a, start) == string.byte(b, start) do
        start = start + 1
    end

    if start > 1 then
        a = a:sub(start)
        b = b:sub(start)
        la = #a
        lb = #b
    end

    -- Strip common suffix
    local ea, eb = la, lb
    while ea > 0 and eb > 0 and string.byte(a, ea) == string.byte(b, eb) do
        ea = ea - 1
        eb = eb - 1
    end

    if ea < la then
        a = a:sub(1, ea)
        b = b:sub(1, eb)
        la = ea
        lb = eb
    end

    -- Standard Wagner-Fischer
    local prev = {}
    local curr = {}

    for j = 0, lb do prev[j] = j end

    for i = 1, la do
        curr[0] = i
        for j = 1, lb do
            local cost = (string.byte(a, i) == string.byte(b, j)) and 0 or 1
            curr[j] = math.min(
                curr[j - 1] + 1,       -- insert
                prev[j] + 1,           -- delete
                prev[j - 1] + cost     -- replace
            )
        end
        prev, curr = curr, prev
    end

    return prev[lb]
end

-------------------------------------------------------------------------------
-- Candidate search
--
-- Given a misspelled name and a list of candidates, return the best
-- matches sorted by relevance.
--
-- Relevance criteria:
--   - Levenshtein distance <= threshold (default: 2)
--   - Name must be at least 2 characters long
--   - Prefix matches get a bonus
-------------------------------------------------------------------------------

function M.suggest(name, candidates, opts)
    opts = opts or {}
    local threshold = opts.threshold or 2
    local min_len = opts.min_len or 2

    if #name < min_len then return {} end

    local scored = {}
    for i = 1, #candidates do
        local cand = candidates[i]
        if type(cand) == "string" then
            local dist = M.levenshtein(name, cand)
            if dist <= threshold then
                -- Bonus for prefix match
                local prefix_len = 0
                local min_len_prefix = math.min(#name, #cand)
                for j = 1, min_len_prefix do
                    if string.byte(name, j) == string.byte(cand, j) then
                        prefix_len = j
                    else
                        break
                    end
                end

                local score = dist - (prefix_len * 0.3)
                scored[#scored + 1] = { name = cand, score = score, dist = dist }
            end
        end
    end

    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.name < b.name
    end)

    local out = {}
    local max = opts.max or 3
    for i = 1, math.min(max, #scored) do
        out[i] = scored[i].name
    end
    return out
end

-------------------------------------------------------------------------------
-- "Did you mean?" message construction
-------------------------------------------------------------------------------

function M.did_you_mean(name, candidates, opts)
    local hits = M.suggest(name, candidates, opts)
    if #hits == 0 then return nil end
    if #hits == 1 then
        return "did you mean `" .. hits[1] .. "`?"
    end
    local parts = {}
    for i = 1, #hits do parts[i] = "`" .. hits[i] .. "`" end
    return "did you mean one of: " .. table.concat(parts, ", ") .. "?"
end

-------------------------------------------------------------------------------
-- Scoped candidate extraction
--
-- Extract candidate names from various compiler structures for suggestion.
-------------------------------------------------------------------------------

function M.names_from_bindings(bindings)
    local out = {}
    for i = 1, #bindings do
        if bindings[i].name then out[#out + 1] = bindings[i].name end
    end
    return out
end

function M.names_from_params(params)
    local out = {}
    for i = 1, #params do
        if params[i].name then out[#out + 1] = params[i].name end
    end
    return out
end

function M.names_from_cont_slots(slots)
    local out = {}
    if type(slots) ~= "table" then return out end
    -- slots can be an array or a name→slot map
    for k, v in pairs(slots) do
        local name = type(v) == "table" and v.name or (type(k) == "string" and k or nil)
        if name then out[#out + 1] = name end
    end
    return out
end

function M.names_from_blocks(blocks)
    local out = {}
    for i = 1, #blocks do
        if blocks[i].label and blocks[i].label.name then
            out[#out + 1] = blocks[i].label.name
        end
    end
    return out
end

function M.names_from_fields(fields)
    local out = {}
    for i = 1, #fields do
        if fields[i].field_name then out[#out + 1] = fields[i].field_name end
        if fields[i].name then out[#out + 1] = fields[i].name end
    end
    return out
end

return M
