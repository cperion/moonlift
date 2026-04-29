local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local SignatureHelp = require("moonlift.editor_signature_help")

local M = {}

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
        elseif c == "," and depth == 0 then
            local s = skip_space(text, i + 1)
            if s < close_i then out[#out + 1] = s end
        end
    end
    return out
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local P = PositionIndex.Define(T)
    local Sig = SignatureHelp.Define(T)

    local hints_phase = pvm.phase("moon2_editor_inlay_hints", {
        [E.RangeQuery] = function(query, analysis)
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
                        if pvm.classof(pos_hit) == S.SourcePositionHit then
                            local help = Sig.help(E.PositionQuery(query.uri, query.version, pos_hit.pos), analysis)
                            if pvm.classof(help) == E.SignatureHelp and #help.signatures > 0 then
                                local sig = help.signatures[help.active_signature + 1] or help.signatures[1]
                                local starts = argument_starts(doc.text, open_i, close_i)
                                local count = math.min(#starts, #sig.params)
                                for j = 1, count do
                                    local ppos = P.offset_to_pos(index, starts[j] - 1)
                                    if pvm.classof(ppos) == S.SourcePositionHit then
                                        local name = sig.params[j].label:match("^([_%a][_%w]*)%s*:") or sig.params[j].label
                                        out[#out + 1] = E.InlayHint(ppos.pos, name .. ":", "parameter")
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return pvm.seq(out)
        end,
    }, { args_cache = "full" })

    local function hints(query, analysis)
        return pvm.drain(hints_phase(query, analysis))
    end

    return { hints_phase = hints_phase, hints = hints }
end

return M
