-- workloads.lua
-- Small synthetic trace/event fixtures for validating SponJIT shadow economics.

local M = {}

local function ev(op, freq, observed, extra)
    local e = { op = op, freq = freq or 1, observed = observed or {} }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

function M.numeric_array_loop()
    return {
        name = "numeric_array_loop",
        description = "s = s + t[i]; type/shape/arithmetic absorbable, bounds remains a ceiling",
        events = {
            ev("GETTABLE", 20000, { "table", "key_i64", "array_hit", "metatable_absent", "result_i64" }),
            ev("ADD",      20000, { "lhs_from_prev", "rhs_i64", "lhs_i64" }),
            ev("JMP",      20000, { "loop_backedge" }),
        },
    }
end

function M.method_dispatch_loop()
    return {
        name = "method_dispatch_loop",
        description = "obj:method(); shape fact should unlock known call target absorption",
        events = {
            ev("GETFIELD", 15000, { "table", "shape_known", "metatable_absent", "key_const", "result_known_call" }),
            ev("CALL",     15000, { "known_call_target", "callee_from_prev" }),
            ev("JMP",      15000, { "loop_backedge" }),
        },
    }
end

function M.arithmetic_return()
    return {
        name = "arithmetic_return",
        description = "ADD result immediately returned; should select ADD_i64_RETURN1",
        events = {
            ev("ADD",     12000, { "lhs_i64", "rhs_i64" }),
            ev("RETURN1", 12000, { "returns_prev" }),
        },
    }
end

function M.polymorphic_phase()
    return {
        name = "polymorphic_phase",
        description = "two absorbable islands around an unstable residual boundary",
        events = {
            ev("LOADI", 10000, {}),
            ev("ADD",  10000, { "lhs_i64", "rhs_i64" }),
            ev("GETTABLE", 10000, { "table" }, { exit_prob = 0.35 }), -- intentionally missing stable shape/metatable facts
            ev("ADD",  10000, { "lhs_i64", "rhs_i64" }),
            ev("RETURN1", 10000, { "returns_prev" }),
        },
    }
end

function M.allocation_churn()
    return {
        name = "allocation_churn",
        description = "short-lived table allocation shape; exposes no-allocation-sinking boundary",
        events = {
            ev("NEWTABLE", 9000, { "allocation" }, { exit_prob = 0.20 }),
            ev("SETFIELD", 9000, { "table", "key_const" }, { exit_prob = 0.15 }),
            ev("GETFIELD", 9000, { "table", "shape_known", "metatable_absent", "key_const", "result_i64" }),
            ev("ADD", 9000, { "lhs_from_prev", "rhs_i64", "lhs_i64" }),
            ev("RETURN1", 9000, { "returns_prev" }),
        },
    }
end

function M.phase_changing_method()
    local hot_shape = {
        ev("GETFIELD", 10000, { "table", "shape_known", "metatable_absent", "key_const", "result_known_call" }),
        ev("CALL",     10000, { "known_call_target", "callee_from_prev" }),
        ev("JMP",      10000, { "loop_backedge" }),
    }
    local generic = {
        ev("GETFIELD", 10000, { "table", "key_const" }, { exit_prob = 0.25 }),
        ev("CALL",     10000, {}, { exit_prob = 0.25 }),
        ev("JMP",      10000, { "loop_backedge" }),
    }
    return {
        name = "phase_changing_method",
        description = "shape/call mode appears, disappears, then returns; tests mode-cache value",
        epochs = {
            { name = "shape17", events = hot_shape },
            { name = "generic", events = generic },
            { name = "shape17_again", events = hot_shape },
        },
    }
end

function M.phase_changing_numeric()
    local i64 = {
        ev("ADD", 10000, { "lhs_i64", "rhs_i64" }),
        ev("RETURN1", 10000, { "returns_prev" }),
    }
    local unknown = {
        ev("ADD", 10000, {}, { exit_prob = 0.30 }),
        ev("RETURN1", 10000, { "returns_prev" }),
    }
    return {
        name = "phase_changing_numeric",
        description = "i64 arithmetic mode alternates with unknown mode",
        epochs = {
            { name = "i64", events = i64 },
            { name = "unknown", events = unknown },
            { name = "i64_again", events = i64 },
        },
    }
end

function M.get(name)
    if name == "numeric" or name == "numeric_array_loop" then return M.numeric_array_loop() end
    if name == "method" or name == "method_dispatch_loop" then return M.method_dispatch_loop() end
    if name == "arith" or name == "arithmetic_return" then return M.arithmetic_return() end
    if name == "poly" or name == "polymorphic_phase" then return M.polymorphic_phase() end
    if name == "alloc" or name == "allocation_churn" then return M.allocation_churn() end
    if name == "phase_method" or name == "phase_changing_method" then return M.phase_changing_method() end
    if name == "phase_numeric" or name == "phase_changing_numeric" then return M.phase_changing_numeric() end
    error("unknown SponJIT shadow workload " .. tostring(name))
end

function M.names()
    return { "arithmetic_return", "numeric_array_loop", "method_dispatch_loop", "polymorphic_phase", "allocation_churn" }
end

function M.timeseries_names()
    return { "phase_changing_method", "phase_changing_numeric" }
end

return M
