-- bench.lua
-- Profitability benchmarking for stencil candidates.
--
-- This module intentionally benchmarks the *candidate contract* rather than
-- pretending that object compilation is enough. Native execution benchmarking
-- can be plugged in later; today the harness produces a deterministic
-- VM-shaped profitability estimate using:
--   - observed profile frequency
--   - opcode baseline cost
--   - candidate shape/lowering
--   - emitted object size
--   - guard / side-exit risk
--   - compile success

local M = {}
local util = require("tools.jit_harness.util")
local lowering_plan = require("tools.jit_harness.lowering_plan")

local OPCODE_COST = {
    MOVE = 8, LOADI = 9, LOADF = 10, LOADK = 12, LOADFALSE = 8, LOADTRUE = 8, LOADNIL = 8,
    GETUPVAL = 12, SETUPVAL = 16,
    GETFIELD = 45, GETTABLE = 55, GETTABUP = 58, SELF = 60,
    SETFIELD = 70, SETTABLE = 78, SETTABUP = 82, SETI = 65,
    ADDI = 18, ADD = 22, SUB = 22, MUL = 26, DIV = 38, MOD = 42,
    ADDK = 20, SUBK = 20, MULK = 24, DIVK = 36, MODK = 40,
    EQ = 24, EQK = 22, EQI = 22, LT = 24, LE = 24, TEST = 18, TESTSET = 20, JMP = 10,
    CALL = 120, TAILCALL = 125, RETURN = 35, RETURN0 = 18, RETURN1 = 20,
    FORPREP = 36, FORLOOP = 34, NEWTABLE = 80, CLOSURE = 95,
}

local DISPATCH_COST = 18

local function ops(candidate)
    if candidate.ops and #candidate.ops > 0 then return candidate.ops end
    local out = {}
    for op in tostring(candidate.pattern_key or candidate.id or ""):gmatch("[^| @]+") do
        if op:match("^[A-Z][A-Z0-9_]*$") then out[#out + 1] = op end
    end
    return out
end

function M.profile_frequency(candidate, profile_db)
    local id = candidate.id or ""
    local pattern = candidate.pattern_key or table.concat(ops(candidate), "|")
    if profile_db and profile_db.rewrite_fact_counts and profile_db.rewrite_fact_counts[id] then
        return profile_db.rewrite_fact_counts[id], "rewrite_fact"
    end
    if candidate.frequency then return candidate.frequency, "candidate" end
    if candidate.profile_count then return candidate.profile_count, "candidate_profile" end
    if profile_db and profile_db.window_counts and profile_db.window_counts[pattern] then
        return profile_db.window_counts[pattern], "window"
    end
    return 0, "missing"
end

function M.baseline_cycles(candidate)
    local total = 0
    for _, op in ipairs(ops(candidate)) do
        total = total + DISPATCH_COST + (OPCODE_COST[op] or 40)
    end
    return math.max(1, total)
end

function M.codegen_supported(candidate, config)
    local ok, err_or_plan, plan = lowering_plan.codegen_supported(candidate, config or { backend = "gcc" })
    if ok then return true, nil, err_or_plan end
    return false, err_or_plan, plan
end

local function count_non_generic_facts(candidate)
    local n = 0
    for _, f in ipairs(candidate.facts or {}) do
        local k = tostring(f.kind or "generic")
        if k ~= "generic" and not k:find("boundary", 1, true) then n = n + 1 end
    end
    return n
end

local function plan_has_boundary_side_exit(plan)
    for _, op in ipairs((plan and plan.op_lowerings) or {}) do
        if op.lowering == "boundary_side_exit" or op.lowering == "newtable_allocator_boundary" then return true end
    end
    return false
end

function M.estimated_stencil_cycles(candidate, plan)
    local shape = candidate.shape_kind or "fallthrough"
    local lowering = candidate.lowering or candidate.rewrite_kind or "generic_opcode_sequence"
    local arity = #(ops(candidate))
    local guards = count_non_generic_facts(candidate)

    local supported, _, built_plan = M.codegen_supported(candidate, { backend = "gcc" })
    plan = plan or built_plan
    if not supported then return M.baseline_cycles(candidate) + 10 end
    if plan_has_boundary_side_exit(plan) then return M.baseline_cycles(candidate) + 8 end

    -- A boundary-only stencil that immediately returns to the interpreter is
    -- legal shape information, but not profitable executable work.
    if candidate.continuation == "side_exit_to_interpreter" or candidate.effect_context == "interpreter_boundary" then
        return M.baseline_cycles(candidate) + 8
    end
    if shape == "call_boundary" and lowering == "generic_opcode_sequence" then
        return M.baseline_cycles(candidate) + 12
    end

    if lowering == "move_move_empty" then return 3 end
    if lowering == "move_move_forward" then return 7 end
    if lowering == "load_move_final_dst" then return 8 end
    if lowering == "op_move_final_dst" then return 18 + guards * 3 end
    if lowering == "op_return1" then return 24 + guards * 3 end

    if shape == "pure_rewrite" then return 6 + arity * 2 end
    if shape == "guarded_pure_rewrite" then return 10 + arity * 5 + guards * 3 end
    if shape == "terminal_return" then return 12 + arity * 7 + guards * 3 end
    if shape == "guarded_fallthrough" then return 10 + arity * 8 + guards * 3 end
    if shape == "branch_or_control_boundary" then return 16 + arity * 9 + guards * 4 end
    if shape == "call_boundary" then return 28 + arity * 12 + guards * 5 end
    if shape == "effect_boundary" then return 24 + arity * 12 + guards * 5 end

    -- Generic opcode sequence: remove most dispatch overhead but keep semantic work.
    local total = 8
    for _, op in ipairs(ops(candidate)) do total = total + math.floor((OPCODE_COST[op] or 40) * 0.72) end
    return math.max(1, total + guards * 3)
end

function M.side_exit_risk(candidate)
    local shape = candidate.shape_kind or "fallthrough"
    local risk = 0.01 * count_non_generic_facts(candidate)
    if shape == "branch_or_control_boundary" then risk = risk + 0.08 end
    if shape == "call_boundary" then risk = risk + 0.18 end
    if shape == "effect_boundary" then risk = risk + 0.15 end
    if shape == "guarded_pure_rewrite" then risk = risk + 0.04 end
    if shape == "guarded_fallthrough" then risk = risk + 0.05 end
    if candidate.rewrite_kind then risk = math.max(0, risk - 0.02) end
    if risk > 0.65 then risk = 0.65 end
    return risk
end

local function compile_result_for(candidate, compile_index)
    if not compile_index then return nil end
    local kid = tostring(candidate.id or ""):gsub("[^%w_]", "_")
    return compile_index[candidate.id] or compile_index[kid] or compile_index[candidate.name]
end

function M.benchmark_candidate(candidate, config)
    config = config or {}
    local profile_db = config.profile_db
    local freq, freq_source = M.profile_frequency(candidate, profile_db)
    local compile_result = config.compile_result
    local compiled = compile_result == nil or compile_result.compiled == true
    local object_size = (compile_result and compile_result.size_bytes) or candidate.size or (candidate.cost and candidate.cost.estimated_size) or (#ops(candidate) * 50)
    local baseline = M.baseline_cycles(candidate)
    local codegen_supported, unsupported_reason, plan = M.codegen_supported(candidate, { backend = config.backend or "gcc" })
    local stencil = M.estimated_stencil_cycles(candidate, plan)
    local risk = M.side_exit_risk(candidate)
    local side_exit_penalty = math.floor(risk * baseline)
    local net_cycles = stencil + side_exit_penalty
    local saving = baseline - net_cycles
    local weighted = saving * freq
    local code_penalty = object_size * (config.code_size_weight or 1.0)
    local score = weighted - code_penalty
    if not compiled then score = -math.huge end

    return {
        candidate_id = candidate.id or "unknown",
        pattern_key = candidate.pattern_key or table.concat(ops(candidate), "|"),
        shape_kind = candidate.shape_kind,
        lowering = candidate.lowering or candidate.rewrite_kind,
        frequency = freq,
        frequency_source = freq_source,
        baseline_cycles = baseline,
        stencil_cycles = stencil,
        side_exit_risk = risk,
        side_exit_penalty = side_exit_penalty,
        net_cycles = net_cycles,
        cycles_saved = saving,
        weighted_cycles_saved = weighted,
        object_size = object_size,
        code_size_penalty = code_penalty,
        compiled = compiled,
        codegen_supported = codegen_supported,
        unsupported_reason = unsupported_reason,
        compile_error = compile_result and compile_result.error or nil,
        score = score,
        profitable = compiled and score > 0 and saving > 0 and freq > 0,
    }
end

function M.benchmark_layer(layer, corpus, config)
    config = config or {}
    local candidates = layer.verified or layer.candidates or {}
    local compile_index = config.compile_index or {}
    local result = {
        timestamp = os.time(),
        mode = "profitability_model_v1",
        candidate_count = #candidates,
        benchmark_results = {},
        summary = {
            profitable = 0,
            compiled = 0,
            total_weighted_cycles_saved = 0,
            best = nil,
            worst = nil,
        },
    }

    for i, cand in ipairs(candidates) do
        if config.progress and (i == 1 or i % (config.progress_every or 250) == 0 or i == #candidates) then
            print(string.format("[bench] %d/%d %s", i, #candidates, tostring(cand.id or cand.name)))
        end
        local bench = M.benchmark_candidate(cand, {
            profile_db = config.profile_db,
            compile_result = compile_result_for(cand, compile_index),
            code_size_weight = config.code_size_weight,
        })
        result.benchmark_results[#result.benchmark_results + 1] = bench
        if bench.compiled then result.summary.compiled = result.summary.compiled + 1 end
        if bench.profitable then result.summary.profitable = result.summary.profitable + 1 end
        result.summary.total_weighted_cycles_saved = result.summary.total_weighted_cycles_saved + math.max(0, bench.weighted_cycles_saved or 0)
        if not result.summary.best or bench.score > result.summary.best.score then result.summary.best = bench end
        if not result.summary.worst or bench.score < result.summary.worst.score then result.summary.worst = bench end
    end

    table.sort(result.benchmark_results, function(a, b) return (a.score or -math.huge) > (b.score or -math.huge) end)
    return result
end

function M.report_benchmark_results(results)
    print("\n=== Benchmark Results ===")
    print(string.format("Mode: %s", results.mode or "unknown"))
    print(string.format("Candidates benchmarked: %d", results.candidate_count or 0))
    if results.summary then
        print(string.format("Compiled: %d", results.summary.compiled or 0))
        print(string.format("Profitable: %d", results.summary.profitable or 0))
        if results.summary.best then
            print(string.format("Best: %s score=%.0f saved=%d freq=%d",
                results.summary.best.candidate_id,
                results.summary.best.score or 0,
                results.summary.best.cycles_saved or 0,
                results.summary.best.frequency or 0))
        end
    end
end

return M
