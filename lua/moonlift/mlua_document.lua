local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local Lex = require("moonlift.mlua_lex")

local M = {}

local has_word = Lex.has_word
local skip_space = Lex.skip_space
local skip_hspace = Lex.skip_hspace
local read_ident = Lex.read_ident
local is_island_start = Lex.is_island_start
local find_next_island = Lex.find_next_island
local island_end = Lex.island_end

local function island_kind(Mlua, kind)
    if kind == "struct" then return Mlua.IslandStruct end
    if kind == "expose" then return Mlua.IslandExpose end
    if kind == "func"   then return Mlua.IslandFunc end
    if kind == "extern" then return Mlua.IslandExtern end
    if kind == "region" then return Mlua.IslandRegion end
    if kind == "expr"   then return Mlua.IslandExpr end
    if kind == "type"   then return Mlua.IslandType end
    if kind == "const"  then return Mlua.IslandConst end
    if kind == "static" then return Mlua.IslandStatic end
    error("unknown island kind: " .. tostring(kind), 2)
end

local function island_name(Mlua, src, start_i, kind)
    local j = skip_space(src, start_i + #kind)
    if kind == "expose" then
        local first, after_first = read_ident(src, j)
        if first and src:sub(skip_space(src, after_first), skip_space(src, after_first)) == ":" then return Mlua.IslandNamed(first) end
        return Mlua.IslandMalformedName("expected expose Name: subject")
    end
    if kind == "func" then
        local owner_or_name, after_first = read_ident(src, j)
        if not owner_or_name then return Mlua.IslandMalformedName("missing func name") end
        local k = skip_space(src, after_first)
        if src:sub(k, k) == ":" then
            local method, _ = read_ident(src, skip_space(src, k + 1))
            return method and Mlua.IslandNamed(owner_or_name .. ":" .. method) or Mlua.IslandMalformedName("missing method name")
        end
        return Mlua.IslandNamed(owner_or_name)
    end
    local name = read_ident(src, j)
    if name then return Mlua.IslandNamed(name) end
    if src:sub(j, j + 1) == "@{" then return Mlua.IslandAnonymous end
    return Mlua.IslandMalformedName("missing " .. kind .. " name")
end

local function add_range(P, index, start_offset, stop_offset)
    local range, reason = P.range_from_offsets(index, start_offset, stop_offset)
    if not range then error(reason, 2) end
    return range
end

local function add_anchor(S, anchors, id_text, kind, label, range)
    anchors[#anchors + 1] = S.AnchorSpan(S.AnchorId(id_text), kind, label, range)
end

function M.Define(T)
    local S = T.MoonSource
    local Mlua = T.MoonMlua
    local H = T.MoonHost
    local Tr = T.MoonTree
    local Parse = T.MoonParse
    local P = PositionIndex.Define(T)

    -- -- document_parts phase (was mlua_document_parts.lua) --

    local function make_lua_segment(index, document, segments, start_offset, stop_offset)
        if stop_offset <= start_offset then return end
        local text = document.text:sub(start_offset + 1, stop_offset)
        local range = add_range(P, index, start_offset, stop_offset)
        local occurrence = S.SourceOccurrence(S.SourceSlice(text), range)
        segments[#segments + 1] = Mlua.LuaOpaque(occurrence)
    end

    local function make_island_segment(index, document, segments, anchors, ordinal, start_i, end_i, kind_word, keyword_i)
        keyword_i = keyword_i or start_i
        local start_offset = start_i - 1
        local stop_offset = end_i
        local keyword_offset = keyword_i - 1
        local full_range = add_range(P, index, start_offset, stop_offset)
        local keyword_range = add_range(P, index, keyword_offset, keyword_offset + #kind_word)
        local kind = island_kind(Mlua, kind_word)
        local source_text = document.text:sub(start_i, end_i)
        local name = island_name(Mlua, document.text, start_i, kind_word)
        local island = Mlua.IslandText(kind, name, S.SourceSlice(source_text))
        segments[#segments + 1] = Mlua.HostedIsland(island, full_range)
        local base = "island." .. ordinal .. "." .. kind_word
        add_anchor(S, anchors, base, S.AnchorHostedIsland, kind_word, full_range)
        add_anchor(S, anchors, base .. ".keyword", S.AnchorKeyword, kind_word, keyword_range)
        local name_text = nil
        if pvm.classof(name) == Mlua.IslandNamed then name_text = name.name end
        if name_text then
            local found = document.text:find(name_text, start_i + #kind_word, true)
            if found and found <= end_i then
                local name_kind = S.AnchorFunctionName
                if kind_word == "struct" then name_kind = S.AnchorStructName
                elseif kind_word == "expose" then name_kind = S.AnchorExposeName
                elseif kind_word == "module" then name_kind = S.AnchorModuleName
                elseif kind_word == "region" then name_kind = S.AnchorRegionName
                elseif kind_word == "expr" then name_kind = S.AnchorExprName end
                add_anchor(S, anchors, base .. ".name", name_kind, name_text, add_range(P, index, found - 1, found - 1 + #name_text))
            end
        end
        local first_nl = document.text:find("\n", start_i, true)
        if first_nl and first_nl < end_i then
            add_anchor(S, anchors, base .. ".body", S.AnchorIslandBody, kind_word .. " body", add_range(P, index, first_nl, math.max(first_nl, end_i - 3)))
        end
    end

    local function make_malformed_segment(index, document, segments, anchors, ordinal, start_i, kind_word, reason)
        local start_offset = start_i - 1
        local stop_offset = #document.text
        local range = add_range(P, index, start_offset, stop_offset)
        local keyword_range = add_range(P, index, start_offset, math.min(#document.text, start_offset + #kind_word))
        local source = document.text:sub(start_i)
        local occurrence = S.SourceOccurrence(S.SourceSlice(source), range)
        segments[#segments + 1] = Mlua.MalformedIsland(island_kind(Mlua, kind_word), occurrence, reason)
        local base = "island." .. ordinal .. "." .. kind_word .. ".malformed"
        add_anchor(S, anchors, base, S.AnchorDiagnostic, reason, range)
        add_anchor(S, anchors, base .. ".keyword", S.AnchorKeyword, kind_word, keyword_range)
    end

    local document_parts_phase = pvm.phase("moonlift_mlua_document_parts", function(document)
        local index = P.build_index(document)
        local segments = {}
        local anchors = {}
        local cursor = 1
        local ordinal = 1
        add_anchor(S, anchors, "document", S.AnchorDocument, document.uri.text, add_range(P, index, 0, #document.text))
        while cursor <= #document.text do
            local start_i, kind_word, keyword_i = find_next_island(document.text, cursor)
            if not start_i then break end
            make_lua_segment(index, document, segments, cursor - 1, start_i - 1)
            local end_i, reason = island_end(document.text, start_i, kind_word)
            if not end_i then
                make_malformed_segment(index, document, segments, anchors, ordinal, start_i, kind_word, reason)
                cursor = #document.text + 1
            else
                make_island_segment(index, document, segments, anchors, ordinal, start_i, end_i, kind_word, keyword_i)
                cursor = end_i + 1
            end
            ordinal = ordinal + 1
        end
        make_lua_segment(index, document, segments, cursor - 1, #document.text)
        return Mlua.DocumentParts(document, segments, S.AnchorSet(anchors))
    end)

    local function document_parts(document)
        return pvm.one(document_parts_phase(document))
    end

    return {
        document_parts_phase = document_parts_phase,
        document_parts = document_parts,
    }
end

return M
