local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local AnchorIndex = require("moonlift.source_anchor_index")

local M = {}

local function line_prefix_at(text, offset)
    local start = text:sub(1, offset):match(".*\n()") or 1
    return text:sub(start, offset)
end

local function previous_word(prefix)
    return prefix:match("([_%a][_%w]*)%s*$")
end

function M.Define(T)
    local S = T.Moon2Source
    local E = T.Moon2Editor
    local P = PositionIndex.Define(T)
    local AI = AnchorIndex.Define(T)

    local context_phase = pvm.phase("moon2_editor_completion_context", function(query, analysis)
        local doc = analysis.parse.parts.document
        local index = P.build_index(doc)
        local hit = P.source_pos_to_offset(index, query.pos)
        if pvm.classof(hit) ~= S.SourceOffsetHit then
            return E.CompletionInvalid(hit.reason)
        end
        local offset = hit.offset
        local prefix = line_prefix_at(doc.text, offset)
        local anchor_index = AI.build_index(analysis.anchors)
        local lookup = AI.lookup_by_position(anchor_index, query.uri, offset)

        if prefix:match("expose%s+[_%a][_%w]*%s*:%s*[%w_%s%(%)%.]*$") then
            return E.CompletionExposeSubject
        end
        if prefix:match("expose.-[%w_]+%s*{%s*[%w_]*$") then
            return E.CompletionExposeMode
        end
        if prefix:match("expose.-{%s*[%w_]*$") then
            return E.CompletionExposeTarget
        end
        if prefix:match(":%s*[%w_]*$") or prefix:match("%-%>%s*[%w_]*$") or prefix:match("ptr%s*%(%s*[%w_]*$") or prefix:match("view%s*%(%s*[%w_]*$") then
            return E.CompletionTypePosition
        end
        if prefix:match("^%s*[%w_]*$") then
            return E.CompletionTopLevel
        end
        if prefix:match("jump%s+[%w_]*$") then
            return E.CompletionContinuationArgs
        end
        if prefix:match("moonlift%.%w*$") then
            return E.CompletionBuiltinPath
        end
        if #lookup.anchors == 0 then
            return E.CompletionLuaOpaque
        end
        local a = lookup.anchors[1]
        if a.kind == S.AnchorHostedIsland or a.kind == S.AnchorIslandBody then
            local w = previous_word(prefix)
            if w == "lua" or w == "terra" or w == "c" then return E.CompletionExposeMode end
            return E.CompletionExprPosition
        end
        return E.CompletionInvalid("no completion context")
    end, { args_cache = "full" })

    local function context(query, analysis)
        return pvm.one(context_phase(query, analysis))
    end

    return {
        context_phase = context_phase,
        context = context,
    }
end

return M
