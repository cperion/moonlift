-- moonlift/editor_code_actions.lua
-- Code action providers for the LSP.
--
-- Refactored to use the Issue Stream pipeline: reads ResolvedIssue[]
-- from the document-analysis resolved issue side table instead of the old
-- editor_diagnostic_facts path.

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
local PositionIndex = require("moonlift.source_position_index")
local AnalysisStore = require("moonlift.mlua_document_analysis")

local function uri_eq(a, b)
    return a == b or (a and b and a.text == b.text)
end

local function uri_text(uri)
    if type(uri) == "table" then return uri.text or tostring(uri) end
    return tostring(uri or "")
end

local function span_overlaps(span_a, span_b)
    local a_uri = uri_text(span_a.uri)
    local b_uri = uri_text(span_b.uri)
    local a_start = span_a.start_offset or 0
    local a_stop = span_a.end_offset or span_a.stop_offset or span_a.start_offset or 0
    local b_start = span_b.start_offset or 0
    local b_stop = span_b.end_offset or span_b.stop_offset or span_b.start_offset or 0
    if a_uri ~= b_uri then return false end
    if a_start == a_stop then
        return a_start >= b_start and a_start <= b_stop
    end
    if b_start == b_stop then
        return b_start >= a_start and b_start <= a_stop
    end
    return a_start < b_stop and b_start < a_stop
end

local function range_contains(outer, inner)
    local outer_uri = outer.uri and outer.uri.text or ""
    local inner_uri = inner.uri and inner.uri.text or ""
    return outer_uri == inner_uri and (inner.start_offset or 0) >= (outer.start_offset or 0) and (inner.stop_offset or 0) <= (outer.stop_offset or 0)
end

local function class_is(node, cls)
    return schema.classof(node) == cls
end

local function bind_context(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local H = T.MoonHost
    local Tr = T.MoonTree
    local Mlua = T.MoonMlua
    local P = PositionIndex(T)

    local function struct_segment_range(analysis, type_name)
        for i = 1, #analysis.parse.parts.segments do
            local seg = analysis.parse.parts.segments[i]
            if class_is(seg, Mlua.HostedIsland) and seg.island.kind == Mlua.IslandStruct then
                if schema.classof(seg.island.name) == Mlua.IslandNamed and seg.island.name.name == type_name then
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

    local function diagnostic_code_for_issue(issue, fallback)
        local cls = schema.classof(issue)
        if cls == H.HostIssueBareBoolInBoundaryStruct then return "host.bareBoolBoundary" end
        if cls == H.HostIssueInvalidPackedAlign then return "host.invalidPackedAlign" end
        if cls == H.HostIssueDuplicateField then return "host.duplicateField" end
        if cls == H.HostIssueDuplicateDecl then return "host.duplicateDecl" end
        if cls == E.BindingUnresolved or cls == Tr.TypeIssueUnresolvedValue then return "binding.unresolved" end
        return fallback or "E"
    end

    -- Get diagnostics at the query position from resolved issues
    local function candidate_diagnostics(query, analysis)
        if #query.diagnostics > 0 then return query.diagnostics end
        local resolved = AnalysisStore.resolved_issues(analysis)
        local out = {}
        local doc = analysis.parse.parts.document
        local index = P.build_index(doc)
        for i = 1, #resolved do
            local ri = resolved[i]
            if ri.span then
                if span_overlaps(ri.span, query.range.range) then
                    local start_offset = ri.span.start_offset or 0
                    local stop_offset = ri.span.end_offset or ri.span.stop_offset or start_offset
                    local range = assert(P.range_from_offsets(index, start_offset, stop_offset))
                    local cls = schema.classof(ri.issue)
                    local origin = E.DiagFromTransport(ri.code or "E", tostring(ri.issue))
                    if cls then
                        if tostring(cls.kind or ""):match("^HostIssue") then origin = E.DiagFromHost(ri.issue)
                        elseif tostring(cls.kind or ""):match("^TypeIssue") then origin = E.DiagFromType(ri.issue) end
                    end
                    local code = diagnostic_code_for_issue(ri.issue, ri.code or "E")
                    local d = E.DiagnosticFact(E.DiagnosticError, origin, code, tostring(ri.issue), range, {})
                    out[#out + 1] = d
                end
            end
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
                if span_overlaps(diag.range, a.range) then target = a; break end
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

    local function unresolved_binding_actions(diag, issue, analysis)
        local name = issue.name or (issue.use and issue.use.anchor and issue.use.anchor.label)
        if not name or not tostring(name):match("^[_%a][_%w]*$") then return {} end
        local text = analysis.parse.parts.document.text
        local insert_offset = line_start_offset(text, diag.range.start_offset or 0)
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

    local function origin_issue(origin)
        local cls = schema.classof(origin)
        if cls == E.DiagFromHost or cls == E.DiagFromType or cls == E.DiagFromParse or cls == E.DiagFromOpen or cls == E.DiagFromBack or cls == E.DiagFromSource then
            return origin.issue
        elseif cls == E.DiagFromBindingResolution then
            return origin.resolution
        end
        return origin
    end

    local function code_actions_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, E.CodeActionQuery) then
            return (function(query, analysis)

            local out = {}
            local diagnostics = candidate_diagnostics(query, analysis)
            for i = 1, #diagnostics do
                local d = diagnostics[i]
                local issue = origin_issue(d.origin)
                local cls = schema.classof(issue)
                local actions = {}
                if cls == H.HostIssueBareBoolInBoundaryStruct then
                    actions = bool_storage_actions(d, issue, analysis)
                elseif cls == H.HostIssueInvalidPackedAlign then
                    actions = packed_align_actions(d, issue, analysis)
                elseif cls == H.HostIssueDuplicateField then
                    actions = duplicate_field_actions(d, issue, analysis)
                elseif cls == H.HostIssueDuplicateDecl then
                    actions = duplicate_decl_actions(d, issue)
                elseif cls == E.BindingUnresolved or cls == Tr.TypeIssueUnresolvedValue then
                    actions = unresolved_binding_actions(d, issue, analysis)
                end
                for j = 1, #actions do out[#out + 1] = actions[j] end
            end
            return as_list(out)
            end)(node, ...)
        else
            error("phase moonlift_editor_code_actions: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function actions(query, analysis)
        return code_actions_phase(query, analysis)
    end

    return { code_actions_phase = code_actions_phase, actions = actions }
end

return bind_context