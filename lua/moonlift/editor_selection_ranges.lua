local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local AnchorIndex = require("moonlift.source_anchor_index")

local M = {}

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local P = PositionIndex.Define(T)
    local AI = AnchorIndex.Define(T)

    local selection_phase = pvm.phase("moon2_editor_selection_ranges", function(query, analysis)
        local index = P.build_index(analysis.parse.parts.document)
        local hit = P.source_pos_to_offset(index, query.pos)
        if pvm.classof(hit) ~= S.SourceOffsetHit then return E.SelectionRange(analysis.anchors.anchors[1].range, {}) end
        local anchor_index = AI.build_index(analysis.anchors)
        local lookup = AI.lookup_by_position(anchor_index, query.uri, hit.offset)
        if #lookup.anchors == 0 then return E.SelectionRange(analysis.anchors.anchors[1].range, {}) end
        local parents = {}
        for i = 2, #lookup.anchors do parents[#parents + 1] = lookup.anchors[i].range end
        return E.SelectionRange(lookup.anchors[1].range, parents)
    end, { args_cache = "full" })

    local function selections(queries, analysis)
        local out = {}
        for i = 1, #queries do out[i] = pvm.one(selection_phase(queries[i], analysis)) end
        return out
    end

    return { selection_phase = selection_phase, selections = selections }
end

return M
