local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")
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

    local function highlight_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, E.PositionQuery) then
            return (function(query, analysis)

            local pick = Subject.subject_at(query, analysis)
            local id = Bindings.subject_key(pick.subject)
            if not id then return erased.empty() end
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
            return erased.seq(out)
            end)(node, ...)
        else
            error("erased phase moonlift_editor_document_highlight: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function highlights(query, analysis)
        return highlight_phase(query, analysis)
    end

    return { highlight_phase = highlight_phase, highlights = highlights }
end

return M
