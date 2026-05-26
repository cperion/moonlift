-- propose.lua
-- Pressure-driven absorber proposal from SponJIT shadow miss reports.
-- This does not generate code. It proposes candidate absorber specs to feed back
-- into design/codegen work.

local Util = require("tools.jit_harness.util")
local Foundry = require("tools.sponjit_shadow.foundry")

local M = {}

local CONTROL = { RETURN=true, RETURN0=true, RETURN1=true, JMP=true, FORLOOP=true, FORPREP=true, CALL=true, TAILCALL=true }
local SIMPLE = { MOVE=true, LOADK=true, LOADI=true, LOADTRUE=true, LOADFALSE=true, LOADNIL=true, GETUPVAL=true }
local ARITH = { ADD=true, ADDI=true, SUB=true, MUL=true, LT=true, LE=true, EQ=true, EQI=true }
local TABLE = { GETTABLE=true, GETFIELD=true, GETTABUP=true, SELF=true, SETTABLE=true, SETFIELD=true, SETTABUP=true }

local function split(s)
    local xs = {}
    for p in tostring(s or ""):gmatch("[^|]+") do xs[#xs + 1] = p end
    return xs
end

local function clean_ops(parts)
    local ops = {}
    for _, p in ipairs(parts or {}) do
        if p ~= "^" and p ~= "$" and p ~= "" then ops[#ops + 1] = p end
    end
    return ops
end

local function class_for_ops(ops)
    local has_call, has_table, has_arith, has_control, all_simple = false, false, false, false, true
    for _, op in ipairs(ops) do
        has_call = has_call or op == "CALL" or op == "TAILCALL"
        has_table = has_table or TABLE[op]
        has_arith = has_arith or ARITH[op]
        has_control = has_control or CONTROL[op]
        all_simple = all_simple and (SIMPLE[op] or false)
    end
    if has_call and has_table then return "method_or_table_call" end
    if has_table and has_arith then return "table_arith_update" end
    if has_table then return "table_access" end
    if has_arith and has_control then return "arith_control" end
    if has_arith then return "numeric" end
    if has_control then return "control_boundary" end
    if all_simple then return "local_value" end
    return "mixed"
end

local function fact_axes_for_ops(ops)
    local facts = {}
    local function add(x) facts[x] = true end
    for _, op in ipairs(ops) do
        if op == "ADD" or op == "SUB" or op == "MUL" or op == "LT" or op == "LE" or op == "EQ" then
            add("lhs_i64"); add("rhs_i64")
        elseif op == "ADDI" or op == "EQI" or op == "LTI" or op == "LEI" or op == "GTI" or op == "GEI" then
            add("lhs_i64")
        elseif op == "GETTABLE" or op == "SETTABLE" then
            add("table"); add("key_i64"); add("metatable_absent"); add("array_hit")
            if op == "SETTABLE" then add("barrier_clean") end
        elseif op == "GETFIELD" or op == "SELF" or op == "GETTABUP" or op == "SETFIELD" then
            add("table"); add("shape_known"); add("metatable_absent"); add("key_const")
            if op == "SETFIELD" then add("barrier_clean") end
        elseif op == "CALL" or op == "TAILCALL" then
            add("known_call_target")
        elseif op == "FORLOOP" or op == "FORPREP" then
            add("loop_i64")
        elseif op == "RETURN1" then
            add("returns_prev")
        elseif op == "JMP" then
            add("branch_consumes_prev")
        end
    end
    local out = {}
    for f in pairs(facts) do out[#out + 1] = f end
    table.sort(out)
    return out
end

local function source_kind(ops, class)
    if #ops == 1 then return "L1_one_op" end
    if class == "method_or_table_call" or class == "table_arith_update" then return "curated_compound" end
    if #ops <= 3 then return "generated_compound" end
    return "curated_supertile_candidate"
end

local function implementation_hint(ops, class)
    if class == "local_value" or class == "numeric" or class == "arith_control" then return "gcc_c_template_first; hand asm only if foundational" end
    if class == "table_access" or class == "table_arith_update" then return "gcc_c_template with explicit layout constants; consider hand asm for shape-slot load/store after measurement" end
    if class == "method_or_table_call" then return "curated C/asm boundary; likely needs call/IC glue and projection discipline" end
    if class == "control_boundary" then return "small hand asm or C template; verify projection/return ABI" end
    return "gcc_c_template_first" end

local function candidate_from_miss(m, rank, kind)
    local ops = clean_ops(split(m.key))
    if #ops == 0 then return nil end
    local class = class_for_ops(ops)
    local c = {
        rank = rank,
        source = kind,
        key = m.key,
        name = table.concat(ops, "_") .. "_absorber",
        ops = ops,
        arity = #ops,
        class = class,
        source_kind = source_kind(ops, class),
        pressure = m.pressure,
        local_total = m.local_total,
        seam = m.seam,
        count = m.count,
        fact_axes = fact_axes_for_ops(ops),
        implementation_hint = implementation_hint(ops, class),
        examples = m.examples,
    }
    c.producers = Foundry.producers_for_candidate(c)
    c.semantic_normal_form = c.producers[#c.producers].normal_form
    c.semantic_normal_form_hash = c.producers[#c.producers].normal_form_hash
    return c
end

local function dedupe(cands)
    local out, seen = {}, {}
    table.sort(cands, function(a, b) return (a.pressure or 0) > (b.pressure or 0) end)
    for _, c in ipairs(cands) do
        local k = table.concat(c.ops or {}, "|")
        if not seen[k] then out[#out + 1] = c; seen[k] = true end
    end
    return out
end

function M.propose(miss_report, config)
    config = config or {}
    local max_candidates = tonumber(config.max_candidates or 24) or 24
    local cands = {}
    for i, m in ipairs((miss_report and miss_report.by_window) or {}) do
        if i > (config.max_windows or 40) then break end
        local c = candidate_from_miss(m, i, "neighborhood")
        if c and c.arity <= (tonumber(config.max_arity or 4) or 4) then cands[#cands + 1] = c end
    end
    for i, m in ipairs((miss_report and miss_report.by_op) or {}) do
        if i > (config.max_ops or 20) then break end
        local c = candidate_from_miss(m, i, "opcode")
        if c then cands[#cands + 1] = c end
    end
    cands = dedupe(cands)
    local out = {}
    for i = 1, math.min(max_candidates, #cands) do out[i] = cands[i] end
    return { candidates = out, generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ") }
end

function M.write(proposals, out_dir)
    Util.mkdir_p(out_dir)
    Util.write_json(out_dir .. "/absorber_proposals.json", proposals)
    local md = { "# SponJIT Absorber Proposals", "" }
    md[#md + 1] = "Generated from residual-pressure miss report. These are candidate specs, not code."
    md[#md + 1] = ""
    md[#md + 1] = "| Rank | Name | Ops | SSA/NF | Class | Pressure | Seam | Facts | Implementation |"
    md[#md + 1] = "|---:|---|---|---|---|---:|---:|---|---|"
    for i, c in ipairs(proposals.candidates or {}) do
        local has_ssa = #(c.producers or {}) > 1
        local nf = table.concat(c.semantic_normal_form or c.ops or {}, " ")
        md[#md + 1] = string.format("| %d | `%s` | `%s` | `%s%s` | `%s` | %.0f | %.0f | `%s` | %s |",
            i, c.name, table.concat(c.ops or {}, " "), has_ssa and "SSA→ " or "", nf, c.class, c.pressure or 0, c.seam or 0,
            table.concat(c.fact_axes or {}, ", "), c.implementation_hint or "")
    end
    md[#md + 1] = ""
    Util.write_file(out_dir .. "/absorber_proposals.md", table.concat(md, "\n"))
end

return M
