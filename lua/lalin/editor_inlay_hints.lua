local schema = require("lalin.schema_runtime")
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
local PositionIndex = require("lalin.source_position_index")
local SignatureHelp = require("lalin.editor_signature_help")

local function uri_eq(a, b)
    return a == b or (a and b and a.text == b.text)
end

local function overlaps(a, b)
    return uri_eq(a.uri, b.uri) and a.start_offset < b.stop_offset and b.start_offset < a.stop_offset
end

local function skip_space(text, i)
    while i <= #text do
        local c = text:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then break end
        i = i + 1
    end
    return i
end

local function find_matching_paren(text, open_i)
    local depth = 0
    for i = open_i, #text do
        local c = text:sub(i, i)
        if c == "(" then depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
            if depth == 0 then return i end
        end
    end
    return nil
end

local function argument_starts(text, open_i, close_i)
    local out = {}
    local depth = 0
    local arg_start = skip_space(text, open_i + 1)
    if arg_start >= close_i then return out end
    out[#out + 1] = arg_start
    for i = open_i + 1, close_i - 1 do
        local c = text:sub(i, i)
        if c == "(" or c == "[" or c == "{" then depth = depth + 1
        elseif c == ")" or c == "]" or c == "}" then if depth > 0 then depth = depth - 1 end
        elseif (c == "," or c == ";") and depth == 0 then
            local s = skip_space(text, i + 1)
            if s < close_i then out[#out + 1] = s end
        end
    end
    return out
end

local function bind_context(T)
    local S = T.LalinSource
    local E = T.LalinEditor
    local P = PositionIndex(T)
    local Sig = SignatureHelp(T)

    local function hints_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, E.RangeQuery) then
            return (function(query, analysis)

        local doc = analysis.parse.parts.document
        local index = P.build_index(doc)
        local out = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorFunctionUse and overlaps(a.range, query.range) then
                local open_i = doc.text:find("(", a.range.stop_offset + 1, true)
                if open_i then
                    local close_i = find_matching_paren(doc.text, open_i)
                    if close_i then
                        local pos_hit = P.offset_to_pos(index, open_i)
                        if schema.classof(pos_hit) == S.SourcePositionHit then
                            local help = Sig.help(E.PositionQuery(query.uri, query.version, pos_hit.pos), analysis)
                            if schema.classof(help) == E.SignatureHelp and #help.signatures > 0 then
                                local sig = help.signatures[help.active_signature + 1] or help.signatures[1]
                                local starts = argument_starts(doc.text, open_i, close_i)
                                local count = math.min(#starts, #sig.params)
                                for j = 1, count do
                                    local ppos = P.offset_to_pos(index, starts[j] - 1)
                                    if schema.classof(ppos) == S.SourcePositionHit then
                                        local name = sig.params[j].label:match("^([_%a][_%w]*)%s*:") or sig.params[j].label:match("^([_%a][_%w]*)%s*=") or sig.params[j].label
                                        out[#out + 1] = E.InlayHint(ppos.pos, name .. ":", "parameter")
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return as_list(out)
            end)(node, ...)
        else
            error("phase lalin_editor_inlay_hints: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function hints(query, analysis)
        return hints_phase(query, analysis)
    end

    return { hints_phase = hints_phase, hints = hints }
end

return bind_context