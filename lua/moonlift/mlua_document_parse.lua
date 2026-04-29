local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local DocumentParts = require("moonlift.mlua_document_parts")
local IslandParse = require("moonlift.mlua_island_parse")
local WholeParse = require("moonlift.mlua_parse")

local M = {}

local function append_all(dst, xs)
    for i = 1, #(xs or {}) do dst[#dst + 1] = xs[i] end
end

local function remap_range(P, index, segment_range, local_range)
    local start_offset = segment_range.start_offset + local_range.start_offset
    local stop_offset = segment_range.start_offset + local_range.stop_offset
    return assert(P.range_from_offsets(index, start_offset, stop_offset))
end

local function remap_issue(S, P, Parse, index, segment_range, issue)
    local local_offset = math.max(0, (issue.offset or 1) - 1)
    local doc_offset = segment_range.start_offset + local_offset
    if doc_offset > segment_range.stop_offset then doc_offset = segment_range.stop_offset end
    local pos_result = P.offset_to_pos(index, doc_offset)
    if pvm.classof(pos_result) == S.SourcePositionHit then
        return Parse.ParseIssue(issue.message, doc_offset + 1, pos_result.pos.line + 1, pos_result.pos.byte_col + 1)
    end
    return Parse.ParseIssue(issue.message, doc_offset + 1, issue.line, issue.col)
end

function M.Define(T)
    local S = T.MoonSource
    local Mlua = T.MoonMlua
    local H = T.MoonHost
    local Tr = T.MoonTree
    local Parse = T.MoonParse
    local Parts = DocumentParts.Define(T)
    local Island = IslandParse.Define(T)
    local Whole = WholeParse.Define(T)
    local P = PositionIndex.Define(T)

    local function remap_anchor(index, segment_ordinal, segment_range, anchor)
        local range = remap_range(P, index, segment_range, anchor.range)
        return S.AnchorSpan(S.AnchorId("island." .. tostring(segment_ordinal) .. ".parse." .. anchor.id.text), anchor.kind, anchor.label, range)
    end

    local function malformed_issue(index, seg)
        local range = seg.occurrence.range
        return Parse.ParseIssue(seg.reason, range.start_offset + 1, range.start.line + 1, range.start.byte_col + 1)
    end

    local document_parse_phase = pvm.phase("moon2_mlua_document_parse", function(parts)
        local index = P.build_index(parts.document)
        local island_parses = {}
        local malformed_issues, anchors = {}, {}
        append_all(anchors, parts.anchors.anchors)
        local island_ordinal = 0
        for i = 1, #parts.segments do
            local seg = parts.segments[i]
            local cls = pvm.classof(seg)
            if cls == Mlua.HostedIsland then
                island_ordinal = island_ordinal + 1
                local parsed = Island.parse(seg.island)
                island_parses[#island_parses + 1] = parsed
                for j = 1, #parsed.anchors.anchors do
                    anchors[#anchors + 1] = remap_anchor(index, island_ordinal, seg.range, parsed.anchors.anchors[j])
                end
            elseif cls == Mlua.MalformedIsland then
                malformed_issues[#malformed_issues + 1] = malformed_issue(index, seg)
            end
        end
        local whole = Whole.parse(parts.document.text, parts.document.uri.text)
        local issues = {}
        append_all(issues, whole.issues)
        if #issues == 0 then append_all(issues, malformed_issues) end
        local combined = H.MluaParseResult(whole.decls, whole.module, whole.region_frags, whole.expr_frags, issues)
        return Mlua.DocumentParse(parts, combined, island_parses, S.AnchorSet(anchors))
    end)

    local function document_parse(parts)
        return pvm.one(document_parse_phase(parts))
    end

    local function parse_document(document)
        return document_parse(Parts.document_parts(document))
    end

    return {
        document_parse_phase = document_parse_phase,
        document_parse = document_parse,
        parse_document = parse_document,
    }
end

return M
