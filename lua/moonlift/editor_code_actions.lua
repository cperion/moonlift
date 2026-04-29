local pvm = require("moonlift.pvm")
local Diagnostics = require("moonlift.editor_diagnostic_facts")
local PositionIndex = require("moonlift.source_position_index")

local M = {}

local function uri_eq(a, b)
    return a == b or (a and b and a.text == b.text)
end

local function overlaps(a, b)
    if not uri_eq(a.uri, b.uri) then return false end
    if a.start_offset == a.stop_offset then
        return a.start_offset >= b.start_offset and a.start_offset <= b.stop_offset
    end
    if b.start_offset == b.stop_offset then
        return b.start_offset >= a.start_offset and b.start_offset <= a.stop_offset
    end
    return a.start_offset < b.stop_offset and b.start_offset < a.stop_offset
end

local function range_contains(outer, inner)
    return uri_eq(outer.uri, inner.uri) and inner.start_offset >= outer.start_offset and inner.stop_offset <= outer.stop_offset
end

local function class_is(node, cls)
    return pvm.classof(node) == cls
end

function M.Define(T)
    local S = (T.MoonSource or T.Moon2Source)
    local E = (T.MoonEditor or T.Moon2Editor)
    local H = (T.MoonHost or T.Moon2Host)
    local Mlua = (T.MoonMlua or T.Moon2Mlua)
    local Diag = Diagnostics.Define(T)
    local P = PositionIndex.Define(T)

    local function struct_segment_range(analysis, type_name)
        for i = 1, #analysis.parse.parts.segments do
            local seg = analysis.parse.parts.segments[i]
            if class_is(seg, Mlua.HostedIsland) and seg.island.kind == Mlua.IslandStruct then
                if pvm.classof(seg.island.name) == Mlua.IslandNamed and seg.island.name.name == type_name then
                    return seg.range
                end
            end
        end
        return nil
    end

    local function nearest_field_type_anchor(analysis, struct_range, field_name, type_label)
        local field_anchor = nil
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorFieldName and a.label == field_name and range_contains(struct_range, a.range) then
                field_anchor = a
                break
            end
        end
        if not field_anchor then return nil end
        local next_field_start = struct_range.stop_offset
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorFieldName and range_contains(struct_range, a.range) and a.range.start_offset > field_anchor.range.start_offset and a.range.start_offset < next_field_start then
                next_field_start = a.range.start_offset
            end
        end
        local best = nil
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorScalarType and a.label == type_label and range_contains(struct_range, a.range) and a.range.start_offset >= field_anchor.range.stop_offset and a.range.start_offset < next_field_start then
                if not best or a.range.start_offset < best.range.start_offset then best = a end
            end
        end
        return best
    end

    local function packed_align_range(analysis, struct_range, align)
        local label = tostring(align)
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorPackedAlign and a.label == label and range_contains(struct_range, a.range) then
                return a.range
            end
        end
        return nil
    end

    local function candidate_diagnostics(query, analysis)
        if #query.diagnostics > 0 then return query.diagnostics end
        local all = Diag.diagnostics(analysis)
        local out = {}
        for i = 1, #all do
            if overlaps(all[i].range, query.range.range) then out[#out + 1] = all[i] end
        end
        return out
    end

    local function bool_storage_actions(diag, issue, analysis)
        local struct_range = struct_segment_range(analysis, issue.type_name)
        if not struct_range then return {} end
        local type_anchor = nearest_field_type_anchor(analysis, struct_range, issue.field_name, "bool")
        if not type_anchor then return {} end
        return {
            E.CodeAction(
                "Use bool32 storage for " .. issue.type_name .. "." .. issue.field_name,
                E.CodeActionQuickFix,
                { diag },
                E.WorkspaceEdit({ E.TextEdit(type_anchor.range, "bool32") })
            ),
            E.CodeAction(
                "Use bool8 storage for " .. issue.type_name .. "." .. issue.field_name,
                E.CodeActionQuickFix,
                { diag },
                E.WorkspaceEdit({ E.TextEdit(type_anchor.range, "bool8") })
            ),
        }
    end

    local function duplicate_field_actions(diag, issue, analysis)
        local struct_range = struct_segment_range(analysis, issue.type_name)
        if not struct_range then return {} end
        local target = nil
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorFieldName and a.label == issue.field_name and range_contains(struct_range, a.range) then
                if overlaps(a.range, diag.range) then target = a; break end
                target = a
            end
        end
        if not target then return {} end
        return {
            E.CodeAction(
                "Rename duplicate field '" .. issue.field_name .. "'",
                E.CodeActionQuickFix,
                { diag },
                E.WorkspaceEdit({ E.TextEdit(target.range, issue.field_name .. "_2") })
            ),
        }
    end

    local function duplicate_decl_actions(diag, issue)
        local name = tostring(issue.name):match("([^:]+)$") or tostring(issue.name)
        if name == "" then return {} end
        return {
            E.CodeAction(
                "Rename duplicate declaration '" .. name .. "'",
                E.CodeActionQuickFix,
                { diag },
                E.WorkspaceEdit({ E.TextEdit(diag.range, name .. "_2") })
            ),
        }
    end

    local function packed_align_actions(diag, issue, analysis)
        local struct_range = struct_segment_range(analysis, issue.type_name)
        if not struct_range then return {} end
        local r = packed_align_range(analysis, struct_range, issue.align)
        if not r then return {} end
        local out = {}
        local choices = { 1, 2, 4, 8 }
        for i = 1, #choices do
            if choices[i] ~= issue.align then
                out[#out + 1] = E.CodeAction(
                    "Use packed(" .. tostring(choices[i]) .. ") alignment for " .. issue.type_name,
                    E.CodeActionQuickFix,
                    { diag },
                    E.WorkspaceEdit({ E.TextEdit(r, tostring(choices[i])) })
                )
            end
        end
        return out
    end

    local function line_start_offset(text, offset)
        local prefix = text:sub(1, offset)
        local lua_index = prefix:match(".*\n()") or 1
        return lua_index - 1
    end

    local function unresolved_binding_actions(diag, resolution, analysis)
        if pvm.classof(resolution) ~= E.BindingUnresolved then return {} end
        local name = resolution.use.anchor.label
        if not tostring(name):match("^[_%a][_%w]*$") then return {} end
        local text = analysis.parse.parts.document.text
        local insert_offset = line_start_offset(text, diag.range.start_offset)
        local line = text:sub(insert_offset + 1, text:find("\n", insert_offset + 1, true) or #text)
        local indent = line:match("^[ \t]*") or ""
        local index = P.build_index(analysis.parse.parts.document)
        local insert_range = assert(P.range_from_offsets(index, insert_offset, insert_offset))
        return {
            E.CodeAction(
                "Declare local '" .. name .. "' as i32",
                E.CodeActionQuickFix,
                { diag },
                E.WorkspaceEdit({ E.TextEdit(insert_range, indent .. "let " .. name .. ": i32 = 0\n") })
            ),
        }
    end

    local code_actions_phase = pvm.phase("moon2_editor_code_actions", {
        [E.CodeActionQuery] = function(query, analysis)
            local out = {}
            local diagnostics = candidate_diagnostics(query, analysis)
            for i = 1, #diagnostics do
                local d = diagnostics[i]
                local origin_cls = pvm.classof(d.origin)
                if origin_cls == E.DiagFromHost then
                    local issue = d.origin.issue
                    local cls = pvm.classof(issue)
                    local actions = {}
                    if cls == H.HostIssueBareBoolInBoundaryStruct then
                        actions = bool_storage_actions(d, issue, analysis)
                    elseif cls == H.HostIssueInvalidPackedAlign then
                        actions = packed_align_actions(d, issue, analysis)
                    elseif cls == H.HostIssueDuplicateField then
                        actions = duplicate_field_actions(d, issue, analysis)
                    elseif cls == H.HostIssueDuplicateDecl then
                        actions = duplicate_decl_actions(d, issue)
                    end
                    for j = 1, #actions do out[#out + 1] = actions[j] end
                elseif origin_cls == E.DiagFromBindingResolution then
                    local actions = unresolved_binding_actions(d, d.origin.resolution, analysis)
                    for j = 1, #actions do out[#out + 1] = actions[j] end
                end
            end
            return pvm.seq(out)
        end,
    }, { args_cache = "full" })

    local function actions(query, analysis)
        return pvm.drain(code_actions_phase(query, analysis))
    end

    return { code_actions_phase = code_actions_phase, actions = actions }
end

return M
