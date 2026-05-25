-- fact_trace.lua
-- Canonicalizes runtime observations into facts
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.7

local M = {}

-- Fact kinds
M.ValueFact = {
    NIL = "nil",
    FALSE = "false",
    TRUE = "true",
    INTEGER = "integer",
    FLOAT = "float",
    NUMBER = "number",
    STRING = "string",
    TABLE = "table",
    FUNCTION = "function",
    USERDATA = "userdata",
    THREAD = "thread",
}

M.TableFact = {
    UNKNOWN = "unknown",
    EMPTY = "empty",
    ARRAY = "array",
    HASH = "hash",
    MIXED = "mixed",
}

M.CallFact = {
    UNKNOWN = "unknown",
    LUA_FUNCTION = "lua_function",
    C_FUNCTION = "c_function",
    BUILTIN = "builtin",
    CLOSURE = "closure",
}

-- Observe a value and return its canonical fact
function M.observe_value_fact(value)
    if value == nil then
        return M.ValueFact.NIL
    elseif value == false then
        return M.ValueFact.FALSE
    elseif value == true then
        return M.ValueFact.TRUE
    elseif type(value) == "number" then
        if value == math.floor(value) then
            return M.ValueFact.INTEGER
        else
            return M.ValueFact.FLOAT
        end
    elseif type(value) == "string" then
        return M.ValueFact.STRING
    elseif type(value) == "table" then
        return M.ValueFact.TABLE
    elseif type(value) == "function" then
        return M.ValueFact.FUNCTION
    elseif type(value) == "userdata" then
        return M.ValueFact.USERDATA
    elseif type(value) == "thread" then
        return M.ValueFact.THREAD
    else
        return M.ValueFact.UNKNOWN
    end
end

-- Observe table structure and return fact
function M.observe_table_fact(tbl)
    if type(tbl) ~= "table" then
        return M.TableFact.UNKNOWN
    end

    local has_array_keys = false
    local has_hash_keys = false
    local count = 0

    for k, v in pairs(tbl) do
        count = count + 1
        if type(k) == "number" and k == math.floor(k) and k >= 1 then
            has_array_keys = true
        else
            has_hash_keys = true
        end
    end

    if count == 0 then
        return M.TableFact.EMPTY
    elseif has_array_keys and not has_hash_keys then
        return M.TableFact.ARRAY
    elseif has_hash_keys and not has_array_keys then
        return M.TableFact.HASH
    else
        return M.TableFact.MIXED
    end
end

-- Observe callable and return fact
function M.observe_call_fact(callee)
    local t = type(callee)

    if t == "function" then
        -- Distinguish Lua from C function
        local info = debug.getinfo(callee)
        if info.what == "Lua" then
            return M.CallFact.LUA_FUNCTION
        else
            return M.CallFact.C_FUNCTION
        end
    elseif t == "table" then
        local mt = getmetatable(callee)
        if mt and mt.__call then
            return M.CallFact.CLOSURE
        end
    end

    return M.CallFact.UNKNOWN
end

-- Canonicalize a fact set: deduplicate and normalize
function M.canonicalize_fact_set(facts)
    local seen = {}
    local canonical = {}

    for _, fact in ipairs(facts) do
        if not seen[fact] then
            seen[fact] = true
            table.insert(canonical, fact)
        end
    end

    table.sort(canonical)
    return canonical
end

-- Encode fact set into a stable hash key
function M.encode_fact_key(facts)
    local canonical = M.canonicalize_fact_set(facts)
    local key_str = table.concat(canonical, "|")

    -- Simple hash: use string itself as key for now
    -- In production, would use a proper hash function
    return key_str
end

-- Build a fact profile from opcode window observations
function M.build_window_facts(window_observations)
    local facts = {}

    for _, obs in ipairs(window_observations) do
        if obs.value_fact then
            table.insert(facts, obs.value_fact)
        end
        if obs.table_fact then
            table.insert(facts, obs.table_fact)
        end
        if obs.call_fact then
            table.insert(facts, obs.call_fact)
        end
    end

    return M.canonicalize_fact_set(facts)
end

-- Report fact distribution
function M.report_facts(facts_map)
    print("\n=== Fact Distribution ===")

    local fact_counts = {}
    for fact, count in pairs(facts_map) do
        table.insert(fact_counts, {fact = fact, count = count})
    end

    table.sort(fact_counts, function(a, b) return a.count > b.count end)

    for _, entry in ipairs(fact_counts) do
        print(string.format("  %s: %d observations", entry.fact, entry.count))
    end
end

return M
