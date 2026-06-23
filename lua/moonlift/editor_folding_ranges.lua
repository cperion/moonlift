local schema = require("moonlift.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end
local PositionIndex = require("moonlift.source_position_index")

local function bind_context(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local Mlua = T.MoonMlua
    local P = PositionIndex(T)

    local fold_open = {
        func = true, region = true, expr = true, struct = true, union = true, handle = true,
        block = true, ["if"] = true, switch = true,
    }

    local function add_unique(out, seen, range)
        local key = range.uri.text .. ":" .. tostring(range.start_offset) .. ":" .. tostring(range.stop_offset)
        if not seen[key] and range.stop.line > range.start.line then
            seen[key] = true
            out[#out + 1] = E.FoldingRange(range, "region")
        end
    end

    local function keyword_folds(analysis, out, seen)
        local doc = analysis.parse.parts.document
        local index = P.build_index(doc)
        local stack = {}
        for i = 1, #index.lines do
            local line = index.lines[i]
            local text = doc.text:sub(line.start_offset + 1, line.stop_offset)
            local word = text:match("^%s*([_%a][_%w]*)%f[^_%w]")
            if word == "end" then
                local open = stack[#stack]
                stack[#stack] = nil
                if open then
                    local r = P.range_from_offsets(index, open.offset, line.stop_offset)
                    if schema.classof(r) == S.SourceRange then add_unique(out, seen, r) end
                end
            elseif fold_open[word] then
                stack[#stack + 1] = { word = word, offset = line.start_offset }
            end
        end
    end

    local function folding_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Mlua.DocumentAnalysis) then
            return (function(analysis)

        local out = {}
        local seen = {}
        for i = 1, #analysis.parse.parts.segments do
            local seg = analysis.parse.parts.segments[i]
            if schema.classof(seg) == Mlua.HostedIsland then
                add_unique(out, seen, seg.range)
            elseif schema.classof(seg) == Mlua.LuaOpaque then
                local r = seg.occurrence.range
                add_unique(out, seen, r)
            end
        end
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorIslandBody and a.range.stop.line > a.range.start.line then
                add_unique(out, seen, a.range)
            end
        end
        keyword_folds(analysis, out, seen)
        table.sort(out, function(a, b)
            if a.range.start.line ~= b.range.start.line then return a.range.start.line < b.range.start.line end
            return a.range.start.utf16_col < b.range.start.utf16_col
        end)
        return as_list(out)
            end)(node, ...)
        else
            error("phase moonlift_editor_folding_ranges: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function ranges(analysis)
        return folding_phase(analysis)
    end

    return { folding_phase = folding_phase, ranges = ranges }
end

return bind_context