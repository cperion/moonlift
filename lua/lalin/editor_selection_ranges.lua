local schema = require("lalin.schema_runtime")
local PositionIndex = require("lalin.source_position_index")
local AnchorIndex = require("lalin.source_anchor_index")

local function bind_context(T)
    local S = T.LalinSource
    local E = T.LalinEditor
    local P = PositionIndex(T)
    local AI = AnchorIndex(T)

    local function range_key(r)
        return r.uri.text .. ":" .. tostring(r.start_offset) .. ":" .. tostring(r.stop_offset)
    end

    local function contains(outer, inner)
        return outer.uri == inner.uri and outer.start_offset <= inner.start_offset and outer.stop_offset >= inner.stop_offset
            and (outer.start_offset ~= inner.start_offset or outer.stop_offset ~= inner.stop_offset)
    end

    local function selection_phase(query, analysis)
        local index = P.build_index(analysis.parse.parts.document)
        local hit = P.source_pos_to_offset(index, query.pos)
        if schema.classof(hit) ~= S.SourceOffsetHit then return E.SelectionRange(analysis.anchors.anchors[1].range, {}) end
        local anchor_index = AI.build_index(analysis.anchors)
        local lookup = AI.lookup_by_position(anchor_index, query.uri, hit.offset)
        if #lookup.anchors == 0 then return E.SelectionRange(analysis.anchors.anchors[1].range, {}) end
        local parents, seen = {}, {}
        local current = lookup.anchors[1].range
        for i = 2, #lookup.anchors do
            local r = lookup.anchors[i].range
            local key = range_key(r)
            if not seen[key] and contains(r, current) then
                seen[key] = true
                parents[#parents + 1] = r
                current = r
            end
        end
        return E.SelectionRange(lookup.anchors[1].range, parents)
    end

    local function selections(queries, analysis)
        local out = {}
        for i = 1, #queries do out[i] = selection_phase(queries[i], analysis) end
        return out
    end

    return { selection_phase = selection_phase, selections = selections }
end

return bind_context