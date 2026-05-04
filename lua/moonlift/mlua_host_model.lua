-- ASDL hosted program model for .mlua documents.
--
-- This phase is the replacement architectural center for host_quote.translate:
-- it turns lexical MLUA segments into explicit HostStep ASDL values.  Lua
-- snippets and hosted islands are no longer hidden in generated Lua source.

local pvm = require("moonlift.pvm")
local Lex = require("moonlift.mlua_lex")

local M = {}

local function kind_word(T, kind)
    local K = T.MoonMlua
    if kind == K.IslandStruct then return "struct" end
    if kind == K.IslandExpose then return "expose" end
    if kind == K.IslandFunc then return "func" end
    if kind == K.IslandModule then return "module" end
    if kind == K.IslandRegion then return "region" end
    if kind == K.IslandExpr then return "expr" end
    return "unknown"
end

local function find_antiquote_end(src, i)
    local depth = 1
    while i <= #src do
        local skipped = Lex.skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        else
            local c = src:sub(i, i)
            if c == "{" then depth = depth + 1; i = i + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then return i end
                i = i + 1
            else
                i = i + 1
            end
        end
    end
    return nil
end

local function expected_splice(T, src, at)
    local H = T.MoonHost
    local prefix = src:sub(1, at - 1):gsub("%s+$", "")
    if prefix:match("%f[%w_]emit%s*$") then return H.SpliceEmit end
    local line = prefix:match("([^\n]*)$") or prefix
    if line:match(":%s*[%w_%.%s%(]*$") or line:match("%-%>%s*[%w_%.%s%(]*$") or line:match("%f[%w_]as%s*%(%s*$") then return H.SpliceType end
    return H.SpliceExpr
end

local function parse_template(T, island)
    local H, S = T.MoonHost, T.MoonSource
    local src = island.source.text
    local parts = {}
    local i, literal_start, splice_i = 1, 1, 0
    while i <= #src do
        local skipped = Lex.skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        elseif src:sub(i, i + 1) == "@{" then
            if literal_start < i then
                parts[#parts + 1] = H.TemplateText(H.TemplatePartText(S.SourceSlice(src:sub(literal_start, i - 1))))
            end
            local e = find_antiquote_end(src, i + 2)
            splice_i = splice_i + 1
            local lua_src = e and src:sub(i + 2, e - 1) or src:sub(i + 2)
            parts[#parts + 1] = H.TemplateSplicePart(H.TemplateSplice(
                "splice." .. tostring(splice_i),
                expected_splice(T, src, i),
                S.SourceSlice(lua_src)))
            if not e then break end
            i = e + 1
            literal_start = i
        else
            i = i + 1
        end
    end
    if literal_start <= #src then
        parts[#parts + 1] = H.TemplateText(H.TemplatePartText(S.SourceSlice(src:sub(literal_start))))
    end
    return H.HostTemplate(kind_word(T, island.kind), parts)
end

function M.Define(T)
    local H, Mlua = T.MoonHost, T.MoonMlua

    local host_program = pvm.phase("moonlift_mlua_host_program", {
        [Mlua.DocumentParts] = function(parts)
            local steps = {}
            for i = 1, #parts.segments do
                local seg = parts.segments[i]
                local cls = pvm.classof(seg)
                if cls == Mlua.LuaOpaque then
                    steps[#steps + 1] = H.HostStepLua("lua." .. tostring(i), seg.occurrence.slice)
                elseif cls == Mlua.HostedIsland then
                    steps[#steps + 1] = H.HostStepIsland("island." .. tostring(i), seg.island, parse_template(T, seg.island))
                end
            end
            return pvm.once(H.HostProgram(H.MluaSource(parts.document.uri.text, parts.document.text), steps))
        end,
    })

    return {
        host_program = host_program,
        parse_template = function(island) return parse_template(T, island) end,
        kind_word = function(kind) return kind_word(T, kind) end,
    }
end

return M
