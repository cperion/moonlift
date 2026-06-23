local schema = require("moonlift.schema_runtime")
local SubjectAt = require("moonlift.editor_subject_at")
local BindingFacts = require("moonlift.editor_binding_facts")

local function add_unique_range(out, seen, range)
    local key = range.uri.text .. ":" .. tostring(range.start_offset) .. ":" .. tostring(range.stop_offset)
    if not seen[key] then
        seen[key] = true
        out[#out + 1] = range
    end
end

local function bind_context(T)
    local E = T.MoonEditor
    local Subject = SubjectAt(T)
    local Bindings = BindingFacts(T)

    local function definition_phase(query, analysis)
        local pick = Subject.subject_at(query, analysis)
        local cls = schema.classof(pick.subject)
        if cls == E.SubjectMissing or cls == E.SubjectKeyword or cls == E.SubjectDiagnostic then
            return E.DefinitionMiss("subject has no definition")
        end
        local id = Bindings.subject_key(pick.subject)
        if not id then return E.DefinitionMiss("unsupported definition subject") end
        local ranges, seen = {}, {}
        local facts = Bindings.facts(analysis)
        for i = 1, #facts do
            if facts[i].id == E.SymbolId(id) and facts[i].role == E.BindingDef then
                add_unique_range(ranges, seen, facts[i].anchor.range)
            end
        end
        if #ranges == 0 then return E.DefinitionMiss("definition not found") end
        return E.DefinitionHit(pick.subject, ranges)
    end

    local function definition(query, analysis)
        return definition_phase(query, analysis)
    end

    return { definition_phase = definition_phase, definition = definition }
end

return bind_context