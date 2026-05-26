-- foundry.lua
-- AOT foundry facade for SponJIT shadow validation.
--
-- The real intelligence lives in foundry_ssa.lua: facts specialize tuple
-- semantics, SSA simplifies them, and the resulting semantic normal form becomes
-- a candidate absorber identity. Runtime SponJIT does not use this module.

local Util = require("tools.jit_harness.util")
local SSA = require("tools.sponjit_shadow.foundry_ssa")

local M = {}

local function join(xs, sep) return table.concat(xs or {}, sep or "|") end

function M.compile(ops, facts, config)
    return SSA.compile(ops, facts, config)
end

function M.semantic_normal_form(ops, facts, config)
    return SSA.semantic_normal_form(ops, facts, config)
end

function M.normal_form_hash(ops, facts, config)
    return SSA.normal_form_hash(ops, facts, config)
end

function M.producers_for_candidate(candidate, config)
    local ops = candidate.ops or {}
    local facts = candidate.fact_axes or {}
    local direct = {
        kind = "direct_tuple",
        normal_form = ops,
        normal_form_hash = Util.stable_hash(join(ops, "|")),
        note = "direct arity composition over current atom basis",
    }
    local hash, nf, ssa = M.normal_form_hash(ops, facts, config)
    local producers = { direct }
    if ssa and ssa.ok and join(nf, "|") ~= join(ops, "|") then
        producers[#producers + 1] = {
            kind = "ssa_normalized",
            normal_form = nf,
            normal_form_hash = hash,
            checked_facts = ssa.checked_facts,
            deps = ssa.deps,
            projection = ssa.projection,
            stats = ssa.stats,
            active_ops = ssa.active_ops,
            note = "AOT SSA/fact normalization candidate; must pass projection/register-budget gates",
        }
    end
    return producers
end

return M
