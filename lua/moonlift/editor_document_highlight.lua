local schema = require("moonlift.schema_runtime")
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
local SubjectAt = require("moonlift.editor_subject_at")
local BindingFacts = require("moonlift.editor_binding_facts")

local function highlight_kind(E, role)
    if role == E.BindingRead then return E.HighlightRead end
    if role == E.BindingWrite then return E.HighlightWrite end
    return E.HighlightText
end

local function bind_context(T)
    local E = T.MoonEditor
    local Subject = SubjectAt(T)
    local Bindings = BindingFacts(T)

    local function highlight_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, E.PositionQuery) then
            return (function(query, analysis)

            local pick = Subject.subject_at(query, analysis)
            local id = Bindings.subject_key(pick.subject)
            if not id then return {} end
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
            return as_list(out)
            end)(node, ...)
        else
            error("phase moonlift_editor_document_highlight: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function highlights(query, analysis)
        return highlight_phase(query, analysis)
    end

    return { highlight_phase = highlight_phase, highlights = highlights }
end

return bind_context