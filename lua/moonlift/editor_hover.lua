local pvm = require("moonlift.pvm")
local SubjectAt = require("moonlift.editor_subject_at")

local M = {}

local function scalar_name(C, scalar)
    for name, value in pairs(C) do
        if value == scalar and tostring(name):match("^Scalar") then
            return tostring(name):gsub("^Scalar", "")
        end
    end
    return tostring(scalar)
end

local function storage_text(pvm, H, storage)
    local cls = pvm.classof(storage)
    if cls == H.HostStorageSame then return "same" end
    if cls == H.HostStorageScalar then return tostring(storage.scalar) end
    if cls == H.HostStorageBool then return "bool stored as " .. tostring(storage.scalar) end
    if cls == H.HostStoragePtr then return "ptr" end
    if cls == H.HostStorageSlice then return "slice" end
    if cls == H.HostStorageView then return "view" end
    if cls == H.HostStorageOpaque then return storage.name end
    return tostring(storage)
end

local function find_layout(H, analysis, name)
    for i = 1, #analysis.host.layout_env.layouts do
        local layout = analysis.host.layout_env.layouts[i]
        if layout.name == name then return layout end
    end
    return nil
end

local function find_field_layout(layout, name)
    if not layout then return nil end
    for i = 1, #layout.fields do
        if layout.fields[i].name == name then return layout.fields[i] end
    end
    return nil
end

function M.Define(T)
    local E = T.Moon2Editor
    local C = T.Moon2Core
    local H = T.Moon2Host
    local Mlua = T.Moon2Mlua
    local Subject = SubjectAt.Define(T)

    local hover_from_pick_phase = pvm.phase("moon2_editor_hover_from_subject", function(pick, analysis)
        local subject = pick.subject
        local range = (#pick.anchors > 0 and pick.anchors[1].range) or analysis.anchors.anchors[1].range
        local cls = pvm.classof(subject)
        if cls == E.SubjectScalar then
            return E.HoverInfo(E.MarkupMarkdown, "`" .. scalar_name(C, subject.scalar) .. "` scalar", range)
        elseif cls == E.SubjectHostStruct then
            local decl = subject.decl
            local layout = find_layout(H, analysis, decl.name)
            local detail = "host struct `" .. decl.name .. "`\n\nfields: " .. tostring(#decl.fields)
            if layout then detail = detail .. "\nsize: " .. layout.size .. " align: " .. layout.align .. " repr: " .. tostring(decl.repr) end
            return E.HoverInfo(E.MarkupMarkdown, detail, range)
        elseif cls == E.SubjectHostField then
            local owner, field = subject.owner, subject.field
            local layout = find_layout(H, analysis, owner.name)
            local fl = find_field_layout(layout, field.name)
            local detail = "field `" .. owner.name .. "." .. field.name .. "`\n\nstorage: " .. storage_text(pvm, H, field.storage)
            if fl then detail = detail .. "\noffset: " .. fl.offset .. " size: " .. fl.size .. " align: " .. fl.align end
            return E.HoverInfo(E.MarkupMarkdown, detail, range)
        elseif cls == E.SubjectHostExpose then
            local ex = subject.decl
            return E.HoverInfo(E.MarkupMarkdown, "host expose `" .. ex.public_name .. "`\n\nfacets: " .. tostring(#ex.facets), range)
        elseif cls == E.SubjectHostAccessor then
            local ac = subject.decl
            return E.HoverInfo(E.MarkupMarkdown, "host accessor `" .. ac.owner_name .. ":" .. ac.name .. "`", range)
        elseif cls == E.SubjectTreeFunc then
            local f = subject.func
            return E.HoverInfo(E.MarkupMarkdown, "Moonlift function `" .. f.name .. "`\n\nparams: " .. tostring(#f.params), range)
        elseif cls == E.SubjectRegionFrag then
            return E.HoverInfo(E.MarkupMarkdown, "Moonlift region fragment\n\nparams: " .. tostring(#subject.frag.params), range)
        elseif cls == E.SubjectExprFrag then
            return E.HoverInfo(E.MarkupMarkdown, "Moonlift expr fragment\n\nparams: " .. tostring(#subject.frag.params), range)
        elseif cls == E.SubjectContinuation then
            return E.HoverInfo(E.MarkupMarkdown, "Moonlift continuation label `" .. subject.label.name .. "`", range)
        elseif cls == E.SubjectKeyword then
            return E.HoverInfo(E.MarkupPlainText, "Moonlift keyword: " .. subject.text, range)
        elseif cls == E.SubjectBuiltin then
            return E.HoverInfo(E.MarkupMarkdown, "Moonlift builtin `" .. subject.name .. "`", range)
        elseif cls == E.SubjectDiagnostic then
            return E.HoverInfo(E.MarkupMarkdown, subject.diagnostic.message, subject.diagnostic.range)
        end
        return E.HoverMissing("no hover for subject")
    end, { args_cache = "full" })

    local hover_phase = pvm.phase("moon2_editor_hover", function(query, analysis)
        local pick = Subject.subject_at(query, analysis)
        return pvm.one(hover_from_pick_phase(pick, analysis))
    end, { args_cache = "full" })

    local function hover(query, analysis)
        return pvm.one(hover_phase(query, analysis))
    end

    return {
        hover_phase = hover_phase,
        hover_from_pick_phase = hover_from_pick_phase,
        hover = hover,
    }
end

return M
