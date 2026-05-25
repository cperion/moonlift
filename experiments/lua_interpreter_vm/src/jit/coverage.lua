-- Dynamic opcode coverage analysis for the baseline stencil planner.
--
-- This answers the question we should keep asking: how fast are we, and how
-- much real workload can currently reach the fast path before exiting?

local M = {}

M.sets = {
    current = {
        MOVE = true,
        LOADI = true,
        ADD = true,
        ADDI = true,
        JMP = true,
        TEST = true,
        RETURN0 = true,
        RETURN1 = true,
        LOADTRUE = true,
        LOADFALSE = true,
        LFALSESKIP = true,
        LOADNIL = true,
        LOADK = true,
        GETUPVAL = true,
        GETFIELD = true,
        SETFIELD = true,
        GETTABLE = true,
        SETTABLE = true,
        SELF = true,
        CALL = true,
    },

    cheap_next = {
        MOVE = true,
        LOADI = true,
        ADD = true,
        ADDI = true,
        JMP = true,
        TEST = true,
        RETURN0 = true,
        RETURN1 = true,
        LOADTRUE = true,
        LOADFALSE = true,
        LFALSESKIP = true,
        LOADNIL = true,
        LOADK = true,
        GETUPVAL = true,
        GETFIELD = true,
        SETFIELD = true,
        GETTABLE = true,
        SETTABLE = true,
        SELF = true,
        CALL = true,
        EQ = true,
        LT = true,
    },

    control_loop = {
        MOVE = true,
        LOADI = true,
        ADD = true,
        ADDI = true,
        JMP = true,
        TEST = true,
        RETURN0 = true,
        RETURN1 = true,
        LOADTRUE = true,
        LOADFALSE = true,
        LFALSESKIP = true,
        LOADNIL = true,
        LOADK = true,
        GETUPVAL = true,
        GETFIELD = true,
        SETFIELD = true,
        GETTABLE = true,
        SETTABLE = true,
        SELF = true,
        CALL = true,
        EQ = true,
        LT = true,
        LE = true,
        EQI = true,
        LTI = true,
        LEI = true,
        FORLOOP = true,
        FORPREP = true,
    },

    object1 = {
        MOVE = true,
        LOADI = true,
        ADD = true,
        ADDI = true,
        JMP = true,
        TEST = true,
        RETURN0 = true,
        RETURN1 = true,
        LOADTRUE = true,
        LOADFALSE = true,
        LFALSESKIP = true,
        LOADNIL = true,
        LOADK = true,
        EQ = true,
        LT = true,
        LE = true,
        EQI = true,
        LTI = true,
        LEI = true,
        FORLOOP = true,
        FORPREP = true,
        GETFIELD = true,
        SETFIELD = true,
        GETTABLE = true,
        SETTABLE = true,
        SELF = true,
        GETUPVAL = true,
        CALL = true,
    },
}

local order = { "current", "cheap_next", "control_loop", "object1" }
M.set_order = order

local function read_lines(path)
    local f = assert(io.open(path, "rb"), path)
    local rows = {}
    for line in f:lines() do rows[#rows + 1] = line end
    f:close()
    return rows
end

function M.read_opcode_hist(path)
    local rows = {}
    for i, line in ipairs(read_lines(path)) do
        if i > 1 and line ~= "" then
            local op, name, count = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)$")
            if op then rows[#rows + 1] = { opcode = tonumber(op), name = name, count = tonumber(count) } end
        end
    end
    table.sort(rows, function(a, b) return a.count > b.count end)
    return rows
end

function M.read_pairs(path)
    local rows = {}
    local f = io.open(path, "rb")
    if not f then return rows end
    local i = 0
    for line in f:lines() do
        i = i + 1
        if i > 1 and line ~= "" then
            local op1, name1, op2, name2, count = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
            if op1 then rows[#rows + 1] = { name1 = name1, name2 = name2, count = tonumber(count) } end
        end
    end
    f:close()
    table.sort(rows, function(a, b) return a.count > b.count end)
    return rows
end

function M.coverage(rows, supported)
    local total, covered = 0, 0
    local unsupported = {}
    for _, r in ipairs(rows) do
        total = total + r.count
        if supported[r.name] then
            covered = covered + r.count
        else
            unsupported[#unsupported + 1] = r
        end
    end
    return {
        total = total,
        covered = covered,
        percent = total > 0 and (covered * 100 / total) or 0,
        unsupported = unsupported,
    }
end

function M.delta(rows, from_set, to_set)
    local total, gained = 0, 0
    local ops = {}
    for _, r in ipairs(rows) do
        total = total + r.count
        if not from_set[r.name] and to_set[r.name] then
            gained = gained + r.count
            ops[#ops + 1] = r
        end
    end
    return { total = total, gained = gained, percent = total > 0 and gained * 100 / total or 0, ops = ops }
end

function M.pair_coverage(rows, supported)
    local total, both, first, none = 0, 0, 0, 0
    local unsupported_pairs = {}
    for _, r in ipairs(rows) do
        total = total + r.count
        local a, b = supported[r.name1], supported[r.name2]
        if a and b then
            both = both + r.count
        elseif a or b then
            first = first + r.count
            unsupported_pairs[#unsupported_pairs + 1] = r
        else
            none = none + r.count
            unsupported_pairs[#unsupported_pairs + 1] = r
        end
    end
    return {
        total = total,
        both = both,
        one = first,
        none = none,
        both_percent = total > 0 and both * 100 / total or 0,
        unsupported_pairs = unsupported_pairs,
    }
end

function M.analyze(hist_path, pairs_path)
    local rows = M.read_opcode_hist(hist_path)
    local pairs = pairs_path and M.read_pairs(pairs_path) or {}
    local out = { rows = rows, pairs = pairs, sets = {}, deltas = {}, pair_sets = {} }
    for _, name in ipairs(order) do
        out.sets[name] = M.coverage(rows, M.sets[name])
        out.pair_sets[name] = M.pair_coverage(pairs, M.sets[name])
    end
    for i = 1, #order - 1 do
        out.deltas[order[i] .. "->" .. order[i + 1]] = M.delta(rows, M.sets[order[i]], M.sets[order[i + 1]])
    end
    return out
end

return M
