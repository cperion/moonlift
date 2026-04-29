local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local Mlua = T.MoonMlua

    local folding_phase = pvm.phase("moon2_editor_folding_ranges", {
        [Mlua.DocumentAnalysis] = function(analysis)
        local out = {}
        for i = 1, #analysis.parse.parts.segments do
            local seg = analysis.parse.parts.segments[i]
            if pvm.classof(seg) == Mlua.HostedIsland then
                if seg.range.stop.line > seg.range.start.line then
                    out[#out + 1] = E.FoldingRange(seg.range, "region")
                end
            elseif pvm.classof(seg) == Mlua.LuaOpaque then
                local r = seg.occurrence.range
                if r.stop.line > r.start.line then out[#out + 1] = E.FoldingRange(r, "region") end
            end
        end
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorIslandBody and a.range.stop.line > a.range.start.line then
                out[#out + 1] = E.FoldingRange(a.range, "region")
            end
        end
        table.sort(out, function(a, b)
            if a.range.start.line ~= b.range.start.line then return a.range.start.line < b.range.start.line end
            return a.range.start.utf16_col < b.range.start.utf16_col
        end)
        return pvm.seq(out)
        end,
    })

    local function ranges(analysis)
        return pvm.drain(folding_phase(analysis))
    end

    return { folding_phase = folding_phase, ranges = ranges }
end

return M
