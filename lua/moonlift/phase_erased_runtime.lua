-- Tiny array-output runtime for PVM-erased dispatch phases.

local M = {}

function M.once(value)
    return { value }
end

function M.empty()
    return {}
end

function M.seq(array, n)
    if n == nil or n == #array then return array end
    local out = {}
    for i = 1, n do out[i] = array[i] end
    return out
end

function M.drain(array)
    return array
end

function M.one(array)
    if #array == 0 then error("erased phase one: expected exactly 1 element, got 0", 2) end
    if #array ~= 1 then error("erased phase one: expected exactly 1 element, got more", 2) end
    return array[1]
end

function M.append_all(out, array)
    for i = 1, #(array or {}) do out[#out + 1] = array[i] end
    return out
end

function M.concat2(a, b)
    local out = {}
    M.append_all(out, a)
    M.append_all(out, b)
    return out
end

function M.concat3(a, b, c)
    local out = {}
    M.append_all(out, a)
    M.append_all(out, b)
    M.append_all(out, c)
    return out
end

function M.concat_all(trips)
    local out = {}
    for i = 1, #(trips or {}) do M.append_all(out, trips[i]) end
    return out
end

function M.children(phase_fn, array, n)
    local out = {}
    n = n or #(array or {})
    for i = 1, n do M.append_all(out, phase_fn(array[i])) end
    return out
end

return M
