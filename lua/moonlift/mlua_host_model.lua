-- ASDL hosted program model for .mlua documents.
--
-- This phase turns lexical MLUA segments into explicit HostStep ASDL values.
-- Lua snippets and hosted islands are represented directly; no template extraction.

local pvm = require("moonlift.pvm")
local Lex = require("moonlift.mlua_lex")

local M = {}

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
                    steps[#steps + 1] = H.HostStepIsland("island." .. tostring(i), seg.island, nil)
                end
            end
            return pvm.once(H.HostProgram(H.MluaSource(parts.document.uri.text, parts.document.text), steps))
        end,
    })

    return {
        host_program = host_program,
    }
end

return M
