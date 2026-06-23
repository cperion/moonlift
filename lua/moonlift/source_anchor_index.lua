local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

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
    local S = T.MoonSource

    local function build_index_phase(anchor_set)
        return S.AnchorIndex(anchor_set, sorted_copy(anchor_set.anchors))
    end

    local function lookup_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, S.AnchorQueryId) then
            return (function(query)

            local out = {}
            for i = 1, #query.index.anchors do
                local anchor = query.index.anchors[i]
                if anchor.id == query.id then
                    out[#out + 1] = anchor
                end
            end
            return erased.once(S.AnchorLookup(out))
            end)(node, ...)
        elseif schema.isa(node, S.AnchorQueryPosition) then
            return (function(query)

            local out = {}
            for i = 1, #query.index.anchors do
                local anchor = query.index.anchors[i]
                local range = anchor.range
                local zero_width = range.start_offset == range.stop_offset
                local contains = query.offset >= range.start_offset and (query.offset < range.stop_offset or (zero_width and query.offset == range.stop_offset))
                if same_uri(range.uri, query.uri) and contains then
                    out[#out + 1] = anchor
                end
            end
            table.sort(out, anchor_specificity)
            return erased.once(S.AnchorLookup(out))
            end)(node, ...)
        elseif schema.isa(node, S.AnchorQueryRange) then
            return (function(query)

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
            return erased.once(S.AnchorLookup(out))
            end)(node, ...)
        else
            error("erased phase moonlift_source_anchor_lookup: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function build_index(anchor_set)
        return build_index_phase(anchor_set)
    end

    local function lookup(query)
        return erased.one(lookup_phase(query))
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
