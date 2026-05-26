-- facts.lua
-- Tiny canonical fact-set helpers for the non-executing SponJIT shadow simulator.
-- Facts are strings in the simulator. Real SponJIT may intern parameterized facts.

local M = {}

local function add_one(out, f)
    if f ~= nil and f ~= "" then out[tostring(f)] = true end
end

function M.new(list)
    local out = {}
    if type(list) == "table" then
        for k, v in pairs(list) do
            if type(k) == "number" then add_one(out, v)
            elseif v then add_one(out, k) end
        end
    elseif list ~= nil then
        add_one(out, list)
    end
    return out
end

function M.copy(set)
    local out = {}
    for k, v in pairs(set or {}) do if v then out[k] = true end end
    return out
end

function M.add(set, list)
    set = set or {}
    for k, v in pairs(M.new(list)) do if v then set[k] = true end end
    return set
end

function M.remove(set, list)
    set = set or {}
    for k, v in pairs(M.new(list)) do if v then set[k] = nil end end
    return set
end

function M.has(set, fact)
    return not not ((set or {})[tostring(fact)])
end

function M.contains_all(set, required)
    set = set or {}
    for f, _ in pairs(M.new(required)) do
        if not set[f] then return false, f end
    end
    return true
end

function M.union(a, b)
    local out = M.copy(a)
    return M.add(out, b)
end

function M.transfer(facts, unit)
    local out = M.copy(facts)
    M.remove(out, unit.killed)
    M.add(out, unit.produced)
    M.add(out, unit.checked)
    return out
end

function M.to_list(set)
    local out = {}
    for f, v in pairs(set or {}) do if v then out[#out + 1] = f end end
    table.sort(out)
    return out
end

function M.signature(set, opts)
    opts = opts or {}
    local parts = {}
    for _, f in ipairs(M.to_list(set)) do
        -- Residency is deliberately not part of region mode identity.
        if not f:match("^residency:") and not f:match("^lease:") then
            parts[#parts + 1] = f
        end
    end
    if opts.max_parts and #parts > opts.max_parts then
        local clipped = {}
        for i = 1, opts.max_parts do clipped[i] = parts[i] end
        clipped[#clipped + 1] = "..."
        parts = clipped
    end
    return table.concat(parts, ";")
end

function M.format(set)
    local xs = M.to_list(set)
    if #xs == 0 then return "{}" end
    return "{" .. table.concat(xs, ", ") .. "}"
end

return M
