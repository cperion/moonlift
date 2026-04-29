local pvm = require("moonlift.pvm")
local SubjectAt = require("moonlift.editor_subject_at")
local BindingFacts = require("moonlift.editor_binding_facts")

local M = {}

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

function M.Define(T)
    local E = T.Moon2Editor
    local Subject = SubjectAt.Define(T)
    local Bindings = BindingFacts.Define(T)

    local function rename_subject_id(subject)
        local cls = pvm.classof(subject)
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

    local prepare_rename_phase = pvm.phase("moon2_editor_prepare_rename", {
        [E.PositionQuery] = function(query, analysis)
            local pick = Subject.subject_at(query, analysis)
            local id = rename_subject_id(pick.subject)
            if not id then return pvm.once(E.PrepareRenameRejected("subject cannot be renamed")) end
            local ranges = covered_ranges(id, analysis)
            if #ranges == 0 then return pvm.once(E.PrepareRenameRejected("rename has no covered edits")) end
            local anchor = pick.anchors[1]
            if not anchor then return pvm.once(E.PrepareRenameRejected("rename has no source anchor")) end
            return pvm.once(E.PrepareRenameOk(anchor.range, first_anchor_label(pick.anchors)))
        end,
    }, { args_cache = "full" })

    local rename_phase = pvm.phase("moon2_editor_rename", {
        [E.RenameQuery] = function(query, analysis)
            if not valid_identifier(query.new_name) then return pvm.once(E.RenameRejected("invalid identifier")) end
            local prepared = pvm.one(prepare_rename_phase(query.position, analysis))
            if pvm.classof(prepared) ~= E.PrepareRenameOk then return pvm.once(E.RenameRejected(prepared.reason)) end
            local pick = Subject.subject_at(query.position, analysis)
            local id = rename_subject_id(pick.subject)
            if not id then return pvm.once(E.RenameRejected("unsupported rename subject")) end
            local edits, seen = {}, {}
            local facts = Bindings.facts(analysis)
            for i = 1, #facts do
                if facts[i].id == E.SymbolId(id) then
                    add_unique(edits, seen, E, facts[i].anchor.range, query.new_name)
                end
            end
            if #edits == 0 then return pvm.once(E.RenameRejected("rename has no covered edits")) end
            return pvm.once(E.RenameOk(edits))
        end,
    }, { args_cache = "full" })

    local function prepare_rename(query, analysis)
        return pvm.one(prepare_rename_phase(query, analysis))
    end

    local function rename(query, analysis)
        return pvm.one(rename_phase(query, analysis))
    end

    return { prepare_rename_phase = prepare_rename_phase, rename_phase = rename_phase, prepare_rename = prepare_rename, rename = rename }
end

return M
