-- ssa.lua -- public facade for SpongeJIT semantic SSA + Stencil IR.
--
-- Offline foundry brain:
--   facts/opcodes -> semantic SSA -> Lua-semantic optimization ->
--   hole-parametric Stencil IR -> canonical stencil hash/form.
--
-- Runtime remains simple copy/patch/execute and never runs SSA/lowering.

local Facts = require("src.facts")
local Lift = require("src.ssa_lift")
local Opt = require("src.ssa_opt")
local Atoms = require("src.ssa_atoms")
local Validate = require("src.ssa_validate")
local Lower = require("src.ssa_to_stencil")
local StencilIR = require("src.stencil_ir")
local StencilNorm = require("src.stencil_normalize")

local M = {}

M.Facts = Facts
M.Validate = Validate
M.StencilIR = StencilIR
M.StencilNormalize = StencilNorm

local function factset(facts)
    if getmetatable(facts) == Facts.FactSet then return facts end
    return Facts.new(facts or {})
end

local function copy_array(xs)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = x end
    return out
end

local function budget_ok(g, config)
    config = config or {}
    local active = 0
    local gpr_pressure = 0
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            active = active + 1
            for _, v in ipairs(n.outputs or {}) do
                local vv = g.values[v]
                if vv and vv.residency == "gpr0" then gpr_pressure = math.max(gpr_pressure, 1) end
            end
        end
    end
    local max_nodes = tonumber(config.max_ssa_nodes or 128) or 128
    local max_gpr = tonumber(config.max_live_gpr or 4) or 4
    return active <= max_nodes and gpr_pressure <= max_gpr
end

local function active_node_specs(g)
    local out = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            local output_types = {}
            for _, v in ipairs(n.outputs or {}) do
                output_types[#output_types + 1] = g.values[v] and g.values[v].ty or "Unknown"
            end
            out[#out + 1] = {
                op = n.op,
                codegen_op = n.codegen_op,
                args = n.args or {},
                effect = n.effect,
                guard_fact = n.guard and n.guard.fact,
                deps = n.deps or {},
                inputs = n.inputs or {},
                outputs = n.outputs or {},
                output_types = output_types,
            }
        end
    end
    return out
end

local function semantic_ops(g)
    local out = {}
    for _, n in ipairs(g.nodes or {}) do if not n.removed then out[#out + 1] = n.op end end
    return out
end

local function summarize(g, source_ops, facts, config)
    local ok_validate, errors = Validate.validate(g, config)
    local st = Lower.lower(g, source_ops or {}, config)
    local ok_stencil, st_errors = StencilIR.validate(st)
    errors = errors or {}
    for _, e in ipairs(st_errors or {}) do errors[#errors + 1] = e end
    local ok = ok_validate and ok_stencil and budget_ok(g, config)
    local form = StencilNorm.form(st)
    local key = StencilNorm.key(st)
    local hash = StencilNorm.hash(st)
    return {
        ok = ok,
        errors = errors,
        graph = g,
        factset = g.factset,
        stencil = st,
        stencil_form = form,
        stencil_hash = hash,
        stencil_key = key,
        stencil_ops = StencilNorm.active_codegen_ops(st),
        stencil_holes = st.holes,
        slotmaps = st.slotmaps,
        active_node_specs = active_node_specs(g),
        semantic_ops = semantic_ops(g),
        checked_facts = StencilNorm.checked_fact_names(st),
        checked_fact_objects = StencilNorm.checked_facts(st),
        deps = StencilNorm.deps(st),
        projection = StencilNorm.projection(st),
        stats = g.stats,
        source_ops = copy_array(source_ops or {}),
    }
end

function M.expand(ops, facts, config)
    return Lift.lift(ops, factset(facts), config)
end

function M.optimize(g, config)
    return Opt.optimize(g, config)
end

function M.compile(ops, facts, config)
    local fs = factset(facts)
    local g = Lift.lift(ops or {}, fs, config)
    Opt.optimize(g, config)
    return summarize(g, ops or {}, fs, config)
end

function M.compile_nodes(node_ops, facts, config)
    local fs = factset(facts)
    local first = (node_ops or {})[1]
    assert(type(first) == "table" or first == nil, "compile_nodes accepts semantic node specs only; codegen-op reopening was removed with Stencil IR")
    local g = Atoms.reopen_node_specs(node_ops or {}, fs, config)
    Opt.optimize(g, config)
    return summarize(g, node_ops or {}, fs, config)
end

return M
