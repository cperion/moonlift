local M = {}

local function source_text_from_origin(src, origin)
    local source = origin and origin.__lalin_source
    return (source and (source.source_text or source.text)) or src or ""
end

local function uri_from_origin(origin, fallback)
    local source = origin and origin.__lalin_source
    return (source and source.uri) or fallback or "?"
end

local function base_offset_from_origin(origin)
    return (origin and origin.start_offset) or 0
end

function M.build(T, parsed, src, origin, opts)
    opts = opts or {}
    local S = T.LalinSource
    local PositionIndex = require("lalin.source_position_index")(T)

    local source_text = source_text_from_origin(src, origin)
    local uri = uri_from_origin(origin, opts.uri or opts.chunk_name or opts.name)
    local doc = S.DocumentSnapshot(S.DocUri(uri), S.DocVersion(1), S.LangLalin, source_text)
    local index = PositionIndex.build_index(doc)
    local anchors = {}

    return {
        uri = uri,
        source_text = source_text,
        source_cache = { [uri] = source_text },
        anchors = anchors,
        document = doc,
    }
end

function M.merge_into(dst, src)
    if not src then return dst end
    dst = dst or {}
    dst.source_cache = dst.source_cache or {}
    if src.source_cache then
        for uri, text in pairs(src.source_cache) do dst.source_cache[uri] = text end
    elseif src.uri and src.source_text then
        dst.source_cache[src.uri] = src.source_text
    end
    if dst.source_text == nil and src.source_text ~= nil then dst.source_text = src.source_text end
    if dst.uri == nil and src.uri ~= nil then dst.uri = src.uri end
    dst.anchors = dst.anchors or {}
    local anchors = src.anchors or {}
    for i = 1, #anchors do dst.anchors[#dst.anchors + 1] = anchors[i] end
    if dst.document == nil and src.document ~= nil then dst.document = src.document end
    if src.item_analyses then
        dst.item_analyses = dst.item_analyses or {}
        for name, analysis in pairs(src.item_analyses) do dst.item_analyses[name] = analysis end
    end
    return dst
end

return M
