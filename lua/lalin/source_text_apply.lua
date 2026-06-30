local schema = require("lalin.schema_runtime")
local PositionIndex = require("lalin.source_position_index")

local M = {}

local function append_issue(issues, issue)
    issues[#issues + 1] = issue
end

local function copy_changes(changes)
    local out = {}
    for i = 1, #changes do out[i] = changes[i] end
    return out
end

local function sort_by_range_start(a, b)
    return a.range.start_offset < b.range.start_offset
end

local function bind_context(T)
    local S = T.LalinSource
    local P = PositionIndex(T)

    local function apply_phase(document, edit)
        local issues = {}
        if document.uri ~= edit.uri then
            append_issue(issues, S.SourceIssueWrongDocument(document.uri, edit.uri))
        end
        if edit.version.value < document.version.value then
            append_issue(issues, S.SourceIssueStaleVersion(document.version, edit.version))
        end
        if #issues > 0 then
            return S.SourceApplyRejected(document, issues)
        end

        local changes = edit.changes
        if #changes == 0 then
            return S.SourceApplyOk(S.DocumentSnapshot(document.uri, edit.version, document.language, document.text))
        end

        local first_cls = schema.classof(changes[1])
        if first_cls == S.ReplaceAll then
            if #changes ~= 1 then
                return S.SourceApplyRejected(document, { S.SourceIssueMixedReplaceAll })
            end
            return S.SourceApplyOk(S.DocumentSnapshot(document.uri, edit.version, document.language, changes[1].text))
        end

        local text_len = #document.text
        local range_changes = copy_changes(changes)
        for i = 1, #range_changes do
            local ch = range_changes[i]
            if schema.classof(ch) ~= S.ReplaceRange then
                return S.SourceApplyRejected(document, { S.SourceIssueMixedReplaceAll })
            end
            if ch.range.uri ~= document.uri then
                append_issue(issues, S.SourceIssueWrongDocument(document.uri, ch.range.uri))
            end
            if ch.range.start_offset < 0 or ch.range.stop_offset < ch.range.start_offset or ch.range.stop_offset > text_len then
                append_issue(issues, S.SourceIssueInvalidRange("range outside document"))
            end
        end
        if #issues > 0 then
            return S.SourceApplyRejected(document, issues)
        end

        table.sort(range_changes, sort_by_range_start)
        for i = 2, #range_changes do
            local prev = range_changes[i - 1].range
            local cur = range_changes[i].range
            if cur.start_offset < prev.stop_offset or (cur.start_offset == prev.start_offset and cur.stop_offset == prev.stop_offset) then
                append_issue(issues, S.SourceIssueOverlappingRanges(prev, cur))
            end
        end
        if #issues > 0 then
            return S.SourceApplyRejected(document, issues)
        end

        local pieces = {}
        local n = 0
        local cursor = 0
        for i = 1, #range_changes do
            local ch = range_changes[i]
            local range = ch.range
            n = n + 1
            pieces[n] = document.text:sub(cursor + 1, range.start_offset)
            n = n + 1
            pieces[n] = ch.text
            cursor = range.stop_offset
        end
        n = n + 1
        pieces[n] = document.text:sub(cursor + 1)
        local new_text = table.concat(pieces)
        return S.SourceApplyOk(S.DocumentSnapshot(document.uri, edit.version, document.language, new_text))
    end

    local function apply(document, edit)
        return apply_phase(document, edit)
    end

    local function range(document, start_offset, stop_offset)
        local index = P.build_index(document)
        local r, reason = P.range_from_offsets(index, start_offset, stop_offset)
        if not r then error(reason, 2) end
        return r
    end

    return {
        apply_phase = apply_phase,
        apply = apply,
        range = range,
    }
end

-----------------------------------------------------------------------------
-- explain_source_issue: explains a single SourceApplyIssue
-----------------------------------------------------------------------------

function M.explain_source_issue(issue, analysis)
    local schema = require("lalin.schema_runtime")
    local cls = schema.classof(issue)
    if not cls then
        return { code = "E9999", severity = "error", primary = { span = nil, message = tostring(issue) } }
    end
    local kind = schema.class_basename(issue)

    if kind == "SourceIssueWrongDocument" then
        local expected = issue.expected and issue.expected.text or "?"
        local actual = issue.actual and issue.actual.text or "?"
        return {
            code = "E1101", severity = "error", phase_context = "while applying text edits",
            primary = { span = nil, message = "edit applied to wrong document: expected `" .. expected .. "`, got `" .. actual .. "`" },
        }
    elseif kind == "SourceIssueStaleVersion" then
        return {
            code = "E1102", severity = "error", phase_context = "while applying text edits",
            primary = { span = nil, message = "stale document version: expected after " .. tostring(issue.expected_after or "?") .. ", got " .. tostring(issue.actual or "?") },
        }
    elseif kind == "SourceIssueInvalidRange" then
        return {
            code = "E1103", severity = "error", phase_context = "while applying text edits",
            primary = { span = nil, message = "invalid source range: " .. tostring(issue.reason or "?") },
        }
    elseif kind == "SourceIssueOverlappingRanges" then
        local function range_str(r)
            if not r then return "?" end
            return tostring(r.start_offset or 0) .. "-" .. tostring(r.stop_offset or 0)
        end
        return {
            code = "E1104", severity = "error", phase_context = "while applying text edits",
            primary = { span = nil, message = "overlapping edit ranges: " .. range_str(issue.previous) .. " overlaps " .. range_str(issue.current) },
        }
    elseif kind == "SourceIssueMixedReplaceAll" then
        return {
            code = "E1105", severity = "error", phase_context = "while applying text edits",
            primary = { span = nil, message = "mixed `ReplaceAll` and `ReplaceRange` in the same edit" },
        }
    else
        return { code = "E9999", severity = "error", primary = { span = nil, message = kind or tostring(issue) } }
    end
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
