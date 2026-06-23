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

local function valid_identifier(name)
    return type(name) == "string" and name:match("^[_%a][_%w]*$") ~= nil
end

local function add_unique(out, seen, E, range, new_name)
    local key = range.uri.text .. ":" .. range.start_offset .. ":" .. range.stop_offset
    if not seen[key] then seen[key] = true; out[#out + 1] = E.RenameEdit(range, new_name) end
end

local function first_anchor_label(anchors)
    return anchors and anchors[1] and anchors[1].label or ""
end

local function bind_context(T)
    local E = T.MoonEditor
    local Subject = SubjectAt(T)
    local Bindings = BindingFacts(T)

    local function rename_subject_id(subject)
        local cls = schema.classof(subject)
        if cls == E.SubjectMissing or cls == E.SubjectKeyword or cls == E.SubjectDiagnostic then return nil end
        if cls == E.SubjectScalar or cls == E.SubjectBuiltin then return nil end
        return Bindings.subject_key(subject)
    end

    local function covered_ranges(id, analysis)
        local ranges, seen = {}, {}
        local facts = Bindings.facts(analysis)
        for i = 1, #facts do
            if facts[i].id == E.SymbolId(id) then
                local r = facts[i].anchor.range
                local key = r.uri.text .. ":" .. r.start_offset .. ":" .. r.stop_offset
                if not seen[key] then seen[key] = true; ranges[#ranges + 1] = r end
            end
        end
        return ranges
    end

    local function prepare_rename_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, E.PositionQuery) then
            return (function(query, analysis)

            local pick = Subject.subject_at(query, analysis)
            local id = rename_subject_id(pick.subject)
            if not id then return single(E.PrepareRenameRejected("subject cannot be renamed")) end
            local ranges = covered_ranges(id, analysis)
            if #ranges == 0 then return single(E.PrepareRenameRejected("rename has no covered edits")) end
            local anchor = pick.anchors[1]
            if not anchor then return single(E.PrepareRenameRejected("rename has no source anchor")) end
            return single(E.PrepareRenameOk(anchor.range, first_anchor_label(pick.anchors)))
            end)(node, ...)
        else
            error("phase moonlift_editor_prepare_rename: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function rename_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, E.RenameQuery) then
            return (function(query, analysis)

            if not valid_identifier(query.new_name) then return single(E.RenameRejected("invalid identifier")) end
            local prepared = only(prepare_rename_phase(query.position, analysis))
            if schema.classof(prepared) ~= E.PrepareRenameOk then return single(E.RenameRejected(prepared.reason)) end
            local pick = Subject.subject_at(query.position, analysis)
            local id = rename_subject_id(pick.subject)
            if not id then return single(E.RenameRejected("unsupported rename subject")) end
            local edits, seen = {}, {}
            local facts = Bindings.facts(analysis)
            for i = 1, #facts do
                if facts[i].id == E.SymbolId(id) then
                    add_unique(edits, seen, E, facts[i].anchor.range, query.new_name)
                end
            end
            if #edits == 0 then return single(E.RenameRejected("rename has no covered edits")) end
            return single(E.RenameOk(edits))
            end)(node, ...)
        else
            error("phase moonlift_editor_rename: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function prepare_rename(query, analysis)
        return only(prepare_rename_phase(query, analysis))
    end

    local function rename(query, analysis)
        return only(rename_phase(query, analysis))
    end

    return { prepare_rename_phase = prepare_rename_phase, rename_phase = rename_phase, prepare_rename = prepare_rename, rename = rename }
end

return bind_context