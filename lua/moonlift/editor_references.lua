local pvm = require("moonlift.pvm")
local SubjectAt = require("moonlift.editor_subject_at")
local BindingFacts = require("moonlift.editor_binding_facts")

local M = {}

local function add_unique(out, seen, range)
    local key = range.uri.text .. ":" .. range.start_offset .. ":" .. range.stop_offset
    if not seen[key] then seen[key] = true; out[#out + 1] = range end
end

function M.Define(T)
    local E = T.MoonEditor
    local Subject = SubjectAt.Define(T)
    local Bindings = BindingFacts.Define(T)

    local references_phase = pvm.phase("moonlift_editor_references", function(query, analysis)
        local pick = Subject.subject_at(query.position, analysis)
        local id = Bindings.subject_key(pick.subject)
        if not id then return E.ReferenceMiss("unsupported reference subject") end
        local ranges, seen = {}, {}
        local facts = Bindings.facts(analysis)
        for i = 1, #facts do
            if facts[i].id == E.SymbolId(id) then
                if query.include_declaration or facts[i].role ~= E.BindingDef then
                    add_unique(ranges, seen, facts[i].anchor.range)
                end
            end
        end
        if #ranges == 0 then return E.ReferenceMiss("references not found") end
        return E.ReferenceHit(pick.subject, ranges)
    end, { args_cache = "full" })

    local function references(query, analysis)
        return pvm.one(references_phase(query, analysis))
    end

    return { references_phase = references_phase, references = references }
end

return M
