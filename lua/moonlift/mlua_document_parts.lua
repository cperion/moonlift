local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")

local M = {}

local function starts_ident_char(c)
    return c and c:match("[%w_]") ~= nil
end

local function is_boundary(src, i, n)
    local before = i > 1 and src:sub(i - 1, i - 1) or ""
    local after = src:sub(i + n, i + n)
    return not starts_ident_char(before) and not starts_ident_char(after)
end

local function has_word(src, i, word)
    return src:sub(i, i + #word - 1) == word and is_boundary(src, i, #word)
end

local function skip_space(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then break end
        i = i + 1
    end
    return i
end

local function skip_hspace(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" then break end
        i = i + 1
    end
    return i
end

local function read_ident(src, i)
    if not src:sub(i, i):match("[A-Za-z_]") then return nil, i end
    local s = i
    i = i + 1
    while i <= #src and src:sub(i, i):match("[%w_]") do i = i + 1 end
    return src:sub(s, i - 1), i
end

local function skip_string(src, i, quote)
    i = i + 1
    while i <= #src do
        local c = src:sub(i, i)
        if c == "\\" then i = i + 2
        elseif c == quote then return i + 1
        else i = i + 1 end
    end
    return i
end

local function skip_long_bracket(src, i)
    local eq = src:match("^%[(=*)%[", i)
    if not eq then return nil end
    local close = "]" .. eq .. "]"
    local j = src:find(close, i + 2 + #eq, true)
    return j and (j + #close) or (#src + 1)
end

local function skip_comment_or_string(src, i)
    local c = src:sub(i, i)
    local n = src:sub(i, i + 1)
    if n == "--" then
        local lb = skip_long_bracket(src, i + 2)
        if lb then return lb end
        local j = src:find("\n", i + 2, true)
        return j or (#src + 1)
    end
    if c == '"' or c == "'" then return skip_string(src, i, c) end
    if c == "[" then return skip_long_bracket(src, i) end
    return nil
end

local open_words = {
    struct = true, expose = true, func = true, module = true, region = true, expr = true,
    ["if"] = true, switch = true, block = true, entry = true, control = true,
}

local function line_prefix_has_word(src, i, word)
    local line_start = src:sub(1, i - 1):match(".*\n()") or 1
    local prefix = src:sub(line_start, i - 1)
    return prefix:match("%f[%w_]" .. word .. "%f[^%w_]") ~= nil
end

local function find_matching_end(src, start_i)
    local depth, i = 0, start_i
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        elseif src:sub(i, i):match("[A-Za-z_]") then
            local word, j = read_ident(src, i)
            if is_boundary(src, i, #word) then
                if word == "end" then
                    depth = depth - 1
                    if depth == 0 then return j - 1 end
                elseif open_words[word] then
                    depth = depth + 1
                elseif word == "do" then
                    if not line_prefix_has_word(src, i, "switch") then depth = depth + 1 end
                elseif word == "loop" then
                    local next_word = read_ident(src, skip_space(src, j))
                    if next_word == "counted" then depth = depth + 1 end
                end
            end
            i = j
        else
            i = i + 1
        end
    end
    return nil, "unterminated hosted Moonlift island"
end

local function is_island_start(src, i, kind)
    if not has_word(src, i, kind) then return false end
    local j = skip_space(src, i + #kind)
    if kind == "struct" or kind == "func" or kind == "region" or kind == "expr" then
        return read_ident(src, j) ~= nil
    end
    if kind == "expose" then
        return read_ident(src, j) ~= nil
    end
    if kind == "module" then
        local item_words = { export = true, extern = true, func = true, const = true, static = true, import = true, type = true, region = true, expr = true, ["end"] = true }
        local p = i - 1
        while p >= 1 do
            local c = src:sub(p, p)
            if c ~= " " and c ~= "\t" and c ~= "\r" then break end
            p = p - 1
        end
        local prev = p >= 1 and src:sub(p, p) or "\n"
        local word_end = p
        while p >= 1 and src:sub(p, p):match("[%w_]") do p = p - 1 end
        local prev_word = word_end >= p + 1 and src:sub(p + 1, word_end) or ""
        local from_return = prev_word == "return"
        local prefix_ok = prev == "\n" or prev == "="
        if not prefix_ok and not from_return then return false end
        local k = skip_hspace(src, i + #kind)
        local ch = src:sub(k, k)
        if ch == "" then return prefix_ok end
        if ch == "\n" then
            if not from_return then return true end
            local next_word = read_ident(src, skip_space(src, k + 1))
            return item_words[next_word] == true
        end
        local word, after_word = read_ident(src, k)
        if not word then return false end
        if item_words[word] then return true end
        local next_i = skip_hspace(src, after_word)
        local next_ch = src:sub(next_i, next_i)
        if from_return then return next_ch == "\n" end
        return next_ch == "" or next_ch == "\n"
    end
    return false
end

local island_order = { "struct", "expose", "func", "module", "region", "expr" }

local function find_next_island(src, i)
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        else
            for k = 1, #island_order do
                local kind = island_order[k]
                if is_island_start(src, i, kind) then return i, kind end
            end
            i = i + 1
        end
    end
    return nil, nil
end

local function island_end(src, start_i, kind)
    if kind == "expose" then
        local nl = src:find("\n", start_i, true)
        if not nl then return #src end
        local next_word = read_ident(src, skip_space(src, nl + 1))
        if next_word == "end" or next_word == "lua" or next_word == "terra" or next_word == "c" or next_word == "moonlift" then
            return find_matching_end(src, start_i)
        end
        return nl - 1
    end
    return find_matching_end(src, start_i)
end

local function island_kind(Mlua, kind)
    if kind == "struct" then return Mlua.IslandStruct end
    if kind == "expose" then return Mlua.IslandExpose end
    if kind == "func" then return Mlua.IslandFunc end
    if kind == "module" then return Mlua.IslandModule end
    if kind == "region" then return Mlua.IslandRegion end
    if kind == "expr" then return Mlua.IslandExpr end
    error("unknown island kind: " .. tostring(kind), 2)
end

local function island_name(Mlua, src, start_i, kind)
    local j = skip_space(src, start_i + #kind)
    if kind == "expose" then
        local first, after_first = read_ident(src, j)
        if first and src:sub(skip_space(src, after_first), skip_space(src, after_first)) == ":" then return Mlua.IslandNamed(first) end
        return Mlua.IslandMalformedName("expected expose Name: subject")
    end
    if kind == "module" then
        local name = read_ident(src, j)
        if name and name ~= "export" and name ~= "extern" and name ~= "func" and name ~= "const" and name ~= "static" and name ~= "import" and name ~= "type" and name ~= "region" and name ~= "expr" and name ~= "end" then
            return Mlua.IslandNamed(name)
        end
        return Mlua.IslandAnonymous
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
    return name and Mlua.IslandNamed(name) or Mlua.IslandMalformedName("missing " .. kind .. " name")
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
    local S = (T.MoonSource or T.Moon2Source)
    local Mlua = (T.MoonMlua or T.Moon2Mlua)
    local P = PositionIndex.Define(T)

    local function make_lua_segment(index, document, segments, start_offset, stop_offset)
        if stop_offset <= start_offset then return end
        local text = document.text:sub(start_offset + 1, stop_offset)
        local range = add_range(P, index, start_offset, stop_offset)
        local occurrence = S.SourceOccurrence(S.SourceSlice(text), range)
        segments[#segments + 1] = Mlua.LuaOpaque(occurrence)
    end

    local function make_island_segment(index, document, segments, anchors, ordinal, start_i, end_i, kind_word)
        local start_offset = start_i - 1
        local stop_offset = end_i
        local full_range = add_range(P, index, start_offset, stop_offset)
        local keyword_range = add_range(P, index, start_offset, start_offset + #kind_word)
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

    local document_parts_phase = pvm.phase("moon2_mlua_document_parts", function(document)
        local index = P.build_index(document)
        local segments = {}
        local anchors = {}
        local cursor = 1
        local ordinal = 1
        add_anchor(S, anchors, "document", S.AnchorDocument, document.uri.text, add_range(P, index, 0, #document.text))
        while cursor <= #document.text do
            local start_i, kind_word = find_next_island(document.text, cursor)
            if not start_i then break end
            make_lua_segment(index, document, segments, cursor - 1, start_i - 1)
            local end_i, reason = island_end(document.text, start_i, kind_word)
            if not end_i then
                make_malformed_segment(index, document, segments, anchors, ordinal, start_i, kind_word, reason)
                cursor = #document.text + 1
            else
                make_island_segment(index, document, segments, anchors, ordinal, start_i, end_i, kind_word)
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
