local pvm = require("moonlift.pvm")

local M = {}

local function same_uri(a, b)
    return a == b or (a and b and a.text == b.text)
end

local function anchor_width(anchor)
    return anchor.range.stop_offset - anchor.range.start_offset
end

local function anchor_specificity(a, b)
    local aw, bw = anchor_width(a), anchor_width(b)
    if aw ~= bw then return aw < bw end
    if a.range.start_offset ~= b.range.start_offset then
        return a.range.start_offset > b.range.start_offset
    end
    return a.id.text < b.id.text
end

local function sorted_copy(anchors)
    local out = {}
    for i = 1, #anchors do out[i] = anchors[i] end
    table.sort(out, function(a, b)
        if a.range.uri.text ~= b.range.uri.text then return a.range.uri.text < b.range.uri.text end
        if a.range.start_offset ~= b.range.start_offset then return a.range.start_offset < b.range.start_offset end
        if a.range.stop_offset ~= b.range.stop_offset then return a.range.stop_offset > b.range.stop_offset end
        return a.id.text < b.id.text
    end)
    return out
end

function M.Define(T)
    local S = (T.MoonSource or T.Moon2Source)

    local build_index_phase = pvm.phase("moon2_source_anchor_index", function(anchor_set)
        return S.AnchorIndex(anchor_set, sorted_copy(anchor_set.anchors))
    end)

    local lookup_phase = pvm.phase("moon2_source_anchor_lookup", {
        [S.AnchorQueryId] = function(query)
            local out = {}
            for i = 1, #query.index.anchors do
                local anchor = query.index.anchors[i]
                if anchor.id == query.id then
                    out[#out + 1] = anchor
                end
            end
            return pvm.once(S.AnchorLookup(out))
        end,
        [S.AnchorQueryPosition] = function(query)
            local out = {}
            for i = 1, #query.index.anchors do
                local anchor = query.index.anchors[i]
                local range = anchor.range
                if same_uri(range.uri, query.uri) and query.offset >= range.start_offset and query.offset <= range.stop_offset then
                    out[#out + 1] = anchor
                end
            end
            table.sort(out, anchor_specificity)
            return pvm.once(S.AnchorLookup(out))
        end,
        [S.AnchorQueryRange] = function(query)
            local out = {}
            local q = query.range
            for i = 1, #query.index.anchors do
                local anchor = query.index.anchors[i]
                local r = anchor.range
                if same_uri(r.uri, q.uri) and r.start_offset < q.stop_offset and q.start_offset < r.stop_offset then
                    out[#out + 1] = anchor
                end
            end
            table.sort(out, anchor_specificity)
            return pvm.once(S.AnchorLookup(out))
        end,
    })

    local function build_index(anchor_set)
        return pvm.one(build_index_phase(anchor_set))
    end

    local function lookup(query)
        return pvm.one(lookup_phase(query))
    end

    local function lookup_by_id(index, id)
        return lookup(S.AnchorQueryId(index, id))
    end

    local function lookup_by_position(index, uri, offset)
        return lookup(S.AnchorQueryPosition(index, uri, offset))
    end

    local function lookup_by_range(index, range)
        return lookup(S.AnchorQueryRange(index, range))
    end

    return {
        build_index_phase = build_index_phase,
        lookup_phase = lookup_phase,
        build_index = build_index,
        lookup = lookup,
        lookup_by_id = lookup_by_id,
        lookup_by_position = lookup_by_position,
        lookup_by_range = lookup_by_range,
    }
end

return M
