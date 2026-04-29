local pvm = require("moonlift.pvm")
local SubjectAt = require("moonlift.editor_subject_at")
local BindingFacts = require("moonlift.editor_binding_facts")

local M = {}

local function highlight_kind(E, role)
    if role == E.BindingRead then return E.HighlightRead end
    if role == E.BindingWrite then return E.HighlightWrite end
    return E.HighlightText
end

function M.Define(T)
    local E = T.MoonEditor
    local Subject = SubjectAt.Define(T)
    local Bindings = BindingFacts.Define(T)

    local highlight_phase = pvm.phase("moon2_editor_document_highlight", {
        [E.PositionQuery] = function(query, analysis)
            local pick = Subject.subject_at(query, analysis)
            local id = Bindings.subject_key(pick.subject)
            if not id then return pvm.empty() end
            local out, seen = {}, {}
            local facts = Bindings.facts(analysis)
            for i = 1, #facts do
                local f = facts[i]
                if f.id == E.SymbolId(id) then
                    local r = f.anchor.range
                    local key = r.uri.text .. ":" .. r.start_offset .. ":" .. r.stop_offset
                    if not seen[key] then
                        seen[key] = true
                        out[#out + 1] = E.DocumentHighlight(r, highlight_kind(E, f.role))
                    end
                end
            end
            return pvm.seq(out)
        end,
    }, { args_cache = "full" })

    local function highlights(query, analysis)
        return pvm.drain(highlight_phase(query, analysis))
    end

    return { highlight_phase = highlight_phase, highlights = highlights }
end

return M
