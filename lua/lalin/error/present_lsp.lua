-- lalin/error/present_lsp.lua
-- LSP presenter: renders ErrorReport as LSP Diagnostic objects.
--
-- Maps the structured ErrorReport to LSP Diagnostic with:
--   - Primary span → diagnostic range
--   - Secondary spans → relatedInformation
--   - Notes + suggestions → message text
--   - Suggestions with replacements → code action data
--   - Code → diagnostic.code

local Span = require("lalin.error.span")

local M = {}

-------------------------------------------------------------------------------
-- Severity mapping
-------------------------------------------------------------------------------

local severity_map = {
    error = 1,
    warning = 2,
    info = 3,
    hint = 4,
}

-------------------------------------------------------------------------------
-- Span → LSP Range conversion
-------------------------------------------------------------------------------

function M.span_to_lsp_range(span)
    if not span then
        return {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 1 },
        }
    end
    return {
        start = {
            line = (span.start_line or 1) - 1,
            character = (span.start_col or 1) - 1,
        },
        ["end"] = {
            line = (span.end_line or 1) - 1,
            character = (span.end_col or 1) - 1,
        },
    }
end

function M.span_to_lsp_location(span)
    if not span then return nil end
    return {
        uri = span.uri and ("file://" .. span.uri) or "",
        range = M.span_to_lsp_range(span),
    }
end

-------------------------------------------------------------------------------
-- Report → LSP Diagnostic
-------------------------------------------------------------------------------

function M.render(report)
    if not report then return nil end

    -- Build the message: primary + notes + suggestions
    local parts = { report.primary.message or "" }

    if report.notes then
        for i = 1, #report.notes do
            parts[#parts + 1] = "\n  note: " .. report.notes[i].message
        end
    end

    if report.suggestions then
        for i = 1, #report.suggestions do
            parts[#parts + 1] = "\n  help: " .. report.suggestions[i].message
        end
    end

    local diagnostic = {
        range = M.span_to_lsp_range(report.primary and report.primary.span),
        severity = severity_map[report.severity] or 1,
        code = report.code,
        source = "lalin",
        message = table.concat(parts, ""),
    }

    -- Related information from secondary spans
    if report.secondary and #report.secondary > 0 then
        local related = {}
        for i = 1, math.min(5, #report.secondary) do
            local sec = report.secondary[i]
            if sec.span then
                local loc = M.span_to_lsp_location(sec.span)
                if loc then
                    related[#related + 1] = {
                        location = loc,
                        message = sec.label or "related location",
                    }
                end
            end
        end
        if #related > 0 then
            diagnostic.relatedInformation = related
        end
    end

    -- Code action data (for LSP code action providers)
    local applicable = {}
    if report.suggestions then
        for i = 1, #report.suggestions do
            local s = report.suggestions[i]
            if s.replacement then
                applicable[#applicable + 1] = {
                    title = s.message,
                    edit = {
                        range = M.span_to_lsp_range(s.replacement.span),
                        newText = s.replacement.new_text,
                    },
                }
            end
        end
    end
    if #applicable > 0 then
        diagnostic.data = { codeActions = applicable }
    end

    return diagnostic
end

-------------------------------------------------------------------------------
-- Render a list of reports
-------------------------------------------------------------------------------

function M.render_all(reports)
    local diagnostics = {}
    for i = 1, #reports do
        local d = M.render(reports[i])
        if d then diagnostics[#diagnostics + 1] = d end
    end
    return diagnostics
end

return M
