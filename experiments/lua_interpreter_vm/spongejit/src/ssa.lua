-- ssa.lua -- public facade for the real SponJIT fact + SSA layer.
--
-- The runtime JIT remains copy/patch/link. This module is offline foundry brain:
-- typed facts -> typed SSA with explicit memory/effects/exits -> optimization ->
-- semantic normal form -> lowerable codegen op stream.

local Facts = require("src.facts")
local Lift = require("src.ssa_lift")
local Opt = require("src.ssa_opt")
local Norm = require("src.ssa_normalize")
local Atoms = require("src.ssa_atoms")
local Validate = require("src.ssa_validate")

local M = {}

M.Facts = Facts
M.Normalize = Norm
M.Validate = Validate

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

local function summarize(g, source_ops, facts, config)
    local ok_validate, errors = Validate.validate(g, config)
    local ok = ok_validate and budget_ok(g, config)
    local nf = Norm.semantic_normal_form(g)
    local active_codegen = Norm.active_codegen_ops(g)
    return {
        ok = ok,
        errors = errors,
        graph = g,
        factset = g.factset,
        normal_form = nf,
        normal_form_hash = Norm.hash(g),
        active_ops = active_codegen,
        active_node_specs = active_node_specs(g),
        semantic_ops = (function()
            local out = {}
            for _, n in ipairs(g.nodes or {}) do if not n.removed then out[#out + 1] = n.op end end
            return out
        end)(),
        checked_facts = Norm.checked_fact_names(g),
        checked_fact_objects = Norm.checked_facts(g),
        deps = Norm.deps(g),
        projection = Norm.projection(g),
        stats = g.stats,
        source_ops = copy_array(source_ops or {}),
        canonical_graph = Norm.canonical_graph_key(g),
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
    local g
    if type(first) == "table" then
        g = Atoms.reopen_node_specs(node_ops or {}, fs, config)
    else
        g = Atoms.reopen_codegen_ops(node_ops or {}, fs, config)
    end
    Opt.optimize(g, config)
    return summarize(g, node_ops or {}, fs, config)
end

function M.semantic_normal_form(ops, facts, config)
    return M.compile(ops, facts, config).normal_form
end

function M.normal_form_hash(ops, facts, config)
    local r = M.compile(ops, facts, config)
    return r.normal_form_hash, r.normal_form, r
end

return M
