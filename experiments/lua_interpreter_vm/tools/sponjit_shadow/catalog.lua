-- catalog.lua
-- Abstract absorber catalogue for SponJIT shadow economics.
-- This catalogue does not emit machine code. It estimates which bytecode work
-- could be absorbed by a future executable absorber library.

local Facts = require("tools.sponjit_shadow.facts")

local M = {}

local function set(list) return Facts.new(list) end

local function min_freq(events, i, len)
    local f = math.huge
    for j = i, i + len - 1 do
        f = math.min(f, tonumber(events[j] and events[j].freq) or 1)
    end
    if f == math.huge then return 1 end
    return f
end

local function obs(event)
    if event._observed_set then return event._observed_set end
    event._observed_set = set(event.observed or event.facts or {})
    return event._observed_set
end

local function observed_all(events, i, requirements)
    for rel, facts in pairs(requirements or {}) do
        local ev = events[i + rel - 1]
        if not ev then return false end
        local ok = Facts.contains_all(obs(ev), facts)
        if not ok then return false end
    end
    return true
end

local function pattern_at(events, i, pattern)
    for j, op in ipairs(pattern) do
        if not events[i + j - 1] or events[i + j - 1].op ~= op then return false end
    end
    return true
end

local function exit_prob(events, i, len, candidate, config)
    local p = tonumber(candidate.exit_prob)
    if p then return p end
    local worst = 0
    for j = i, i + len - 1 do
        local ev = events[j]
        if ev then worst = math.max(worst, tonumber(ev.exit_prob) or 0) end
    end
    if worst > 0 then return worst end
    return tonumber(config and config.default_exit_prob) or 0.01
end

local function mk(def)
    def.kind = def.kind or "native"
    def.cost = def.cost or 10
    def.code_size = def.code_size or 16
    def.covered_len = #(def.pattern or {})
    return def
end

-- Cost numbers are intentionally rough. Validation comes from sensitivity runs.
M.DEFAULTS = {
    interpreter_cost = 80,
    crossing_cost = 55,
    exit_cost = 250,
    materialization_cost = 120,
    code_size_penalty = 0.02,
    default_exit_prob = 0.01,
}

M.ABSORBERS = {
    mk { id = "MOVE_copy", pattern = {"MOVE"}, cost = 8, code_size = 12, produced = {"last_value", "residency:last_slot"} },
    mk { id = "LOADK_const", pattern = {"LOADK"}, cost = 7, code_size = 12, produced = {"last_value", "const_value", "residency:last_gpr"} },
    mk { id = "LOADI_i64", pattern = {"LOADI"}, cost = 5, code_size = 10, produced = {"last_i64", "fresh_result", "residency:last_gpr"} },
    mk { id = "LOADTRUE_bool", pattern = {"LOADTRUE"}, cost = 5, code_size = 10, produced = {"last_bool", "fresh_result"} },
    mk { id = "LOADFALSE_bool", pattern = {"LOADFALSE"}, cost = 5, code_size = 10, produced = {"last_bool", "fresh_result"} },
    mk { id = "LOADNIL_nil", pattern = {"LOADNIL"}, cost = 5, code_size = 10, produced = {"last_nil", "fresh_result"} },
    mk { id = "RETURN1", pattern = {"RETURN1"}, cost = 12, code_size = 14 },
    mk { id = "RETURN1_reg", pattern = {"RETURN1"}, required = {"residency:last_gpr"}, cost = 5, code_size = 10 },
    mk { id = "JMP_direct", pattern = {"JMP"}, cost = 4, code_size = 8 },
    mk { id = "TEST_truthy", pattern = {"TEST"}, cost = 8, code_size = 12, observed = { [1] = {"truthy_stable"} }, checked = {"truthy"} },

    mk { id = "ADD_i64", pattern = {"ADD"}, cost = 7, code_size = 18,
        observed = { [1] = {"lhs_i64", "rhs_i64"} }, checked = {"lhs_i64", "rhs_i64"},
        produced = {"last_i64", "fresh_result", "residency:last_gpr"}, killed = {"last_value"} },
    mk { id = "SUB_i64", pattern = {"SUB"}, cost = 7, code_size = 18,
        observed = { [1] = {"lhs_i64", "rhs_i64"} }, checked = {"lhs_i64", "rhs_i64"},
        produced = {"last_i64", "fresh_result", "residency:last_gpr"}, killed = {"last_value"} },
    mk { id = "MUL_i64", pattern = {"MUL"}, cost = 9, code_size = 22,
        observed = { [1] = {"lhs_i64", "rhs_i64"} }, checked = {"lhs_i64", "rhs_i64"},
        produced = {"last_i64", "fresh_result", "residency:last_gpr"}, killed = {"last_value"} },
    mk { id = "ADDI_i64", pattern = {"ADDI"}, cost = 6, code_size = 16,
        observed = { [1] = {"lhs_i64"} }, checked = {"lhs_i64"},
        produced = {"last_i64", "fresh_result", "residency:last_gpr"}, killed = {"last_value"} },
    mk { id = "LT_i64", pattern = {"LT"}, cost = 7, code_size = 18,
        observed = { [1] = {"lhs_i64", "rhs_i64"} }, checked = {"lhs_i64", "rhs_i64"},
        produced = {"last_bool", "cmp_result"} },
    mk { id = "LE_i64", pattern = {"LE"}, cost = 7, code_size = 18,
        observed = { [1] = {"lhs_i64", "rhs_i64"} }, checked = {"lhs_i64", "rhs_i64"},
        produced = {"last_bool", "cmp_result"} },
    mk { id = "EQ_i64", pattern = {"EQ"}, cost = 7, code_size = 18,
        observed = { [1] = {"lhs_i64", "rhs_i64"} }, checked = {"lhs_i64", "rhs_i64"},
        produced = {"last_bool", "cmp_result"} },
    mk { id = "EQI_i64", pattern = {"EQI"}, cost = 6, code_size = 16,
        observed = { [1] = {"lhs_i64"} }, checked = {"lhs_i64"},
        produced = {"last_bool", "cmp_result"} },

    mk { id = "ADD_i64_RETURN1", pattern = {"ADD", "RETURN1"}, cost = 9, code_size = 24,
        observed = { [1] = {"lhs_i64", "rhs_i64"}, [2] = {"returns_prev"} },
        checked = {"lhs_i64", "rhs_i64"}, produced = {"terminal_return"} },
    mk { id = "LT_i64_BRANCH", pattern = {"LT", "JMP"}, cost = 9, code_size = 24,
        observed = { [1] = {"lhs_i64", "rhs_i64"}, [2] = {"branch_consumes_prev"} },
        checked = {"lhs_i64", "rhs_i64"}, produced = {"branch_resolved"} },
    mk { id = "TEST_JMP", pattern = {"TEST", "JMP"}, cost = 7, code_size = 18,
        observed = { [2] = {"branch_consumes_prev"} }, produced = {"branch_resolved"} },
    mk { id = "FORLOOP_i64", pattern = {"FORLOOP"}, cost = 16, code_size = 38,
        observed = { [1] = {"loop_i64"} }, checked = {"loop_i64"}, produced = {"loop_backedge"} },

    mk { id = "GETTABLE_array_guarded", pattern = {"GETTABLE"}, cost = 14, code_size = 34,
        observed = { [1] = {"table", "key_i64", "array_hit", "metatable_absent"} },
        checked = {"table", "key_i64", "array_hit", "metatable_absent"},
        produced = {"last_value", "table_shape_checked"}, killed = {"last_i64", "residency:last_gpr"} },
    mk { id = "GETTABLE_array_i64", pattern = {"GETTABLE"}, cost = 15, code_size = 36,
        observed = { [1] = {"table", "key_i64", "array_hit", "metatable_absent", "result_i64"} },
        checked = {"table", "key_i64", "array_hit", "metatable_absent"},
        produced = {"last_i64", "fresh_result", "table_shape_checked", "residency:last_gpr"} },
    mk { id = "GETTABLE_array_i64_ADD_i64", pattern = {"GETTABLE", "ADD"}, cost = 21, code_size = 52,
        observed = { [1] = {"table", "key_i64", "array_hit", "metatable_absent", "result_i64"}, [2] = {"rhs_i64", "lhs_from_prev"} },
        checked = {"table", "key_i64", "array_hit", "metatable_absent", "rhs_i64"},
        produced = {"last_i64", "fresh_result", "residency:last_gpr"} },
    mk { id = "GETTABLE_array_i64_ADD_i64_RETURN1", pattern = {"GETTABLE", "ADD", "RETURN1"}, cost = 24, code_size = 62,
        observed = { [1] = {"table", "key_i64", "array_hit", "metatable_absent", "result_i64"}, [2] = {"rhs_i64", "lhs_from_prev"}, [3] = {"returns_prev"} },
        checked = {"table", "key_i64", "array_hit", "metatable_absent", "rhs_i64"},
        produced = {"terminal_return"} },

    mk { id = "GETFIELD_shape_guarded", pattern = {"GETFIELD"}, cost = 12, code_size = 30,
        observed = { [1] = {"table", "shape_known", "metatable_absent", "key_const"} },
        checked = {"table", "shape_known", "metatable_absent"},
        produced = {"last_value", "shape_checked"} },
    mk { id = "GETFIELD_shape_known_call", pattern = {"GETFIELD"}, cost = 13, code_size = 34,
        observed = { [1] = {"table", "shape_known", "metatable_absent", "key_const", "result_known_call"} },
        checked = {"table", "shape_known", "metatable_absent"},
        produced = {"known_call_target", "residency:last_gpr"} },
    mk { id = "GETUPVAL", pattern = {"GETUPVAL"}, cost = 9, code_size = 20,
        produced = {"last_value", "residency:last_gpr"} },
    mk { id = "GETTABUP_shape_known", pattern = {"GETTABUP"}, cost = 15, code_size = 36,
        observed = { [1] = {"table", "shape_known", "metatable_absent", "key_const"} },
        checked = {"table", "shape_known", "metatable_absent"}, produced = {"last_value", "shape_checked"} },
    mk { id = "SELF_shape_known_call", pattern = {"SELF"}, cost = 16, code_size = 44,
        observed = { [1] = {"table", "shape_known", "metatable_absent", "key_const", "result_known_call"} },
        checked = {"table", "shape_known", "metatable_absent"}, produced = {"known_call_target", "residency:last_gpr"} },
    mk { id = "SETTABLE_raw", pattern = {"SETTABLE"}, cost = 18, code_size = 44,
        observed = { [1] = {"table", "key_i64", "metatable_absent", "barrier_clean"} },
        checked = {"table", "key_i64", "metatable_absent"}, killed = {"table_shape_checked"} },
    mk { id = "SETFIELD_raw", pattern = {"SETFIELD"}, cost = 16, code_size = 40,
        observed = { [1] = {"table", "shape_known", "metatable_absent", "key_const", "barrier_clean"} },
        checked = {"table", "shape_known", "metatable_absent"}, killed = {"shape_checked"} },
    mk { id = "CALL_known_boundary", pattern = {"CALL"}, cost = 28, code_size = 42,
        required = {"known_call_target"}, checked = {"known_call_target"},
        killed = {"last_i64", "last_value", "residency:last_gpr"}, produced = {"call_returned"} },
    mk { id = "TAILCALL_known_boundary", pattern = {"TAILCALL"}, cost = 26, code_size = 40,
        observed = { [1] = {"known_call_target"} }, checked = {"known_call_target"},
        killed = {"last_i64", "last_value", "residency:last_gpr"}, produced = {"terminal_return"} },
    mk { id = "GETFIELD_shape_CALL_known", pattern = {"GETFIELD", "CALL"}, cost = 34, code_size = 72,
        observed = { [1] = {"table", "shape_known", "metatable_absent", "key_const", "result_known_call"}, [2] = {"known_call_target", "callee_from_prev"} },
        checked = {"table", "shape_known", "metatable_absent", "known_call_target"},
        killed = {"last_i64", "last_value", "residency:last_gpr"}, produced = {"call_returned"} },
}

local by_first = nil
local function index()
    if by_first then return by_first end
    by_first = {}
    for _, a in ipairs(M.ABSORBERS) do
        local first = a.pattern[1]
        by_first[first] = by_first[first] or {}
        by_first[first][#by_first[first] + 1] = a
    end
    return by_first
end

local function candidate_from_absorber(abs, events, i, facts, config)
    local len = #abs.pattern
    local freq = min_freq(events, i, len)
    local p = exit_prob(events, i, len, abs, config)
    local exit_cost = tonumber(config.exit_cost) or M.DEFAULTS.exit_cost
    local size_penalty = tonumber(config.code_size_penalty) or M.DEFAULTS.code_size_penalty
    local materialization = tonumber(config.materialization_cost) or M.DEFAULTS.materialization_cost
    local mat_amort = materialization / math.max(freq, 1)
    local local_cost = abs.cost + p * exit_cost + (abs.code_size or 0) * size_penalty + mat_amort
    return {
        id = abs.id,
        kind = "native",
        start = i,
        finish = i + len - 1,
        covered_len = len,
        pattern = abs.pattern,
        required = set(abs.required),
        checked = set(abs.checked),
        produced = set(abs.produced),
        killed = set(abs.killed),
        code_size = abs.code_size or 0,
        exit_prob = p,
        cost_per_hit = local_cost,
        freq = freq,
        local_total = local_cost * freq,
    }
end

function M.residual_candidate(events, i, config)
    config = config or M.DEFAULTS
    local ev = events[i]
    local freq = tonumber(ev and ev.freq) or 1
    local interp = tonumber(config.interpreter_cost) or M.DEFAULTS.interpreter_cost
    return {
        id = "RESIDUAL_" .. tostring(ev and ev.op or "?"),
        kind = "residual",
        start = i,
        finish = i,
        covered_len = 1,
        pattern = { ev and ev.op or "?" },
        required = {}, checked = {}, produced = {}, killed = {},
        code_size = 0,
        exit_prob = 0,
        cost_per_hit = interp,
        freq = freq,
        local_total = interp * freq,
    }
end

function M.candidates_at(events, i, facts, config)
    config = config or M.DEFAULTS
    facts = facts or {}
    local ev = events[i]
    if not ev then return {} end
    local out = { M.residual_candidate(events, i, config) }
    local pools = { (index()[ev.op]) or {} }
    if config.extra_absorbers_by_first and config.extra_absorbers_by_first[ev.op] then
        pools[#pools + 1] = config.extra_absorbers_by_first[ev.op]
    elseif config.extra_absorbers then
        local xs = {}
        for _, a in ipairs(config.extra_absorbers or {}) do
            if a.pattern and a.pattern[1] == ev.op then xs[#xs + 1] = a end
        end
        pools[#pools + 1] = xs
    end
    for _, pool in ipairs(pools) do
        for _, abs in ipairs(pool) do
            if pattern_at(events, i, abs.pattern) then
                local req_ok = Facts.contains_all(facts, abs.required)
                local obs_ok = observed_all(events, i, abs.observed)
                if req_ok and obs_ok then
                    out[#out + 1] = candidate_from_absorber(abs, events, i, facts, config)
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.covered_len ~= b.covered_len then return a.covered_len > b.covered_len end
        return a.local_total < b.local_total
    end)
    return out
end

function M.defaults(config)
    local out = {}
    for k, v in pairs(M.DEFAULTS) do out[k] = v end
    for k, v in pairs(config or {}) do out[k] = v end
    return out
end

return M
