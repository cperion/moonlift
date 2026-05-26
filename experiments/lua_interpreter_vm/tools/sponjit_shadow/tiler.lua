-- tiler.lua
-- Local cover DP for the non-executing SponJIT shadow simulator.

local Facts = require("tools.sponjit_shadow.facts")
local Catalog = require("tools.sponjit_shadow.catalog")

local M = {}

local function key(i, sig) return tostring(i) .. "\t" .. tostring(sig or "") end

local function clone_units(xs)
    local out = {}
    for i, u in ipairs(xs or {}) do out[i] = u end
    return out
end

local function better(a, b)
    if not b then return true end
    if a.cost ~= b.cost then return a.cost < b.cost end
    if a.native_count ~= b.native_count then return a.native_count > b.native_count end
    return #(a.units or {}) < #(b.units or {})
end

local function boundary_freq(a, b)
    return math.min(tonumber(a and a.freq) or 1, tonumber(b and b.freq) or 1)
end

local function seam_between(a, b, config)
    if not a or not b or a.kind == b.kind then return 0 end
    return boundary_freq(a, b) * (tonumber(config.crossing_cost) or Catalog.DEFAULTS.crossing_cost)
end

local function state_key(i, sig, prev_kind)
    return key(i, sig) .. "\t" .. tostring(prev_kind or "")
end

local function selected_candidate(cand, entry_facts, exit_facts)
    local sig = Facts.signature(exit_facts)
    local selected = {}
    for k, v in pairs(cand) do selected[k] = v end
    selected.entry_signature = Facts.signature(entry_facts)
    selected.exit_signature = sig
    selected.required_list = Facts.to_list(cand.required)
    selected.produced_list = Facts.to_list(cand.produced)
    selected.checked_list = Facts.to_list(cand.checked)
    return selected, sig
end

function M.cover(events, start_i, end_i, entry_facts, config)
    config = Catalog.defaults(config)
    start_i = start_i or 1
    end_i = end_i or #events
    entry_facts = Facts.new(entry_facts)

    local include_seams = not not config.include_internal_seams
    local states = {}
    local entry_sig = Facts.signature(entry_facts)
    local entry_key = include_seams and state_key(start_i, entry_sig, "start") or key(start_i, entry_sig)
    states[entry_key] = {
        pos = start_i,
        sig = entry_sig,
        prev_kind = "start",
        prev_unit = nil,
        facts = entry_facts,
        cost = 0,
        units = {},
        native_count = 0,
    }

    for i = start_i, end_i do
        local active = {}
        for _, st in pairs(states) do
            if st.pos == i then active[#active + 1] = st end
        end
        table.sort(active, function(a, b) return a.cost < b.cost end)
        local beam = tonumber(config.state_beam or 16) or 16
        for ai = 1, math.min(#active, beam) do
            local st = active[ai]
            for _, cand in ipairs(Catalog.candidates_at(events, i, st.facts, config)) do
                local j = i + cand.covered_len
                if j <= end_i + 1 then
                    local next_facts = Facts.transfer(st.facts, cand)
                    local selected, sig = selected_candidate(cand, st.facts, next_facts)
                    local units = clone_units(st.units)
                    units[#units + 1] = selected
                    local extra = include_seams and seam_between(st.prev_unit, selected, config) or 0
                    local candidate_state = {
                        pos = j,
                        sig = sig,
                        prev_kind = selected.kind,
                        prev_unit = selected,
                        facts = next_facts,
                        cost = st.cost + cand.local_total + extra,
                        units = units,
                        native_count = st.native_count + (cand.kind == "native" and 1 or 0),
                    }
                    local k = include_seams and state_key(j, sig, selected.kind) or key(j, sig)
                    if better(candidate_state, states[k]) then states[k] = candidate_state end
                end
            end
        end
    end

    local best = nil
    for _, st in pairs(states) do
        if st.pos == end_i + 1 and better(st, best) then best = st end
    end
    if not best then
        -- Should not happen because residual is always legal, but keep failure closed.
        local units, cost = {}, 0
        for i = start_i, end_i do
            local r = Catalog.residual_candidate(events, i, config)
            units[#units + 1] = r
            cost = cost + r.local_total
        end
        best = { pos = end_i + 1, sig = entry_sig, facts = entry_facts, cost = cost, units = units, native_count = 0 }
    end
    return best
end

function M.cover_with_seams(events, start_i, end_i, entry_facts, config)
    local cfg = {}
    for k, v in pairs(config or {}) do cfg[k] = v end
    cfg.include_internal_seams = true
    return M.cover(events, start_i, end_i, entry_facts, cfg)
end

return M
