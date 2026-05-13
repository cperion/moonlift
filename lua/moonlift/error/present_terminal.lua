-- moonlift/error/present_terminal.lua
-- Terminal presenter: renders ErrorReport as beautiful terminal output.
--
-- Design rules:
--   - Maximum 3 lines of context before/after the primary line
--   - Primary underline uses ^^^, secondary uses ~~~
--   - Labels on underlines are right-aligned when possible
--   - Notes use "= note:" prefix
--   - Suggestions use "= help:" prefix
--   - Color: red/errors, yellow/warnings, blue/notes, green/help
--   - Respects NO_COLOR env var
--   - Never more than 3 secondary spans per error

local Span = require("moonlift.error.span")
local Report = require("moonlift.error.report")

local M = {}

-------------------------------------------------------------------------------
-- Color support
-------------------------------------------------------------------------------

local NO_COLOR = os.getenv("NO_COLOR")

local colors = {
    reset   = "\27[0m",
    bold    = "\27[1m",
    dim     = "\27[2m",
    red     = "\27[31m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    cyan    = "\27[36m",
    green   = "\27[32m",
    white   = "\27[37m",
}

local function color(name, text)
    if NO_COLOR then return text end
    return (colors[name] or "") .. text .. colors.reset
end

local function severity_color(severity)
    if severity == "error" then return "red"
    elseif severity == "warning" then return "yellow"
    elseif severity == "info" then return "cyan"
    elseif severity == "hint" then return "green"
    else return "white"
    end
end

-------------------------------------------------------------------------------
-- Gutter width calculation
-------------------------------------------------------------------------------

local function max_line_width(lines)
    local m = 0
    for i = 1, #lines do
        local w = #tostring(lines[i].line_no)
        if w > m then m = w end
    end
    return math.max(3, m)
end

-------------------------------------------------------------------------------
-- Snippet rendering
--
-- Takes a snippet { uri, lines, underlines } and renders it as
-- a visual display with gutters, underlines, and labels.
-------------------------------------------------------------------------------

function M.render_snippet(snippet, source_text)
    if not snippet or not snippet.lines or #snippet.lines == 0 then
        return ""
    end

    local gw = max_line_width(snippet.lines)
    local gutter_fmt = " %" .. gw .. "d │"
    local blank_gutter = string.rep(" ", gw + 1) .. " │"

    local out = {}

    -- File header
    if snippet.uri and snippet.uri ~= "?" then
        -- Find the primary underline for line/col info
        local primary_line = nil
        local primary_col = nil
        if snippet.underlines and #snippet.underlines > 0 then
            local ul = snippet.underlines[1]
            if ul then
                primary_line = snippet.lines[ul.line_idx] and snippet.lines[ul.line_idx].line_no
                primary_col = ul.start_col
            end
        end
        local loc = snippet.uri
        if primary_line then
            loc = loc .. ":" .. primary_line
            if primary_col then loc = loc .. ":" .. primary_col end
        end
        out[#out + 1] = color("dim", "  ┌─ ") .. loc
    end

    -- Source lines with underlines
    for i, l in ipairs(snippet.lines) do
        -- Source line
        out[#out + 1] = color("dim", string.format(gutter_fmt, l.line_no))
            .. " " .. l.text

        -- Check for underlines on this line
        if snippet.underlines then
            for _, ul in ipairs(snippet.underlines) do
                if ul.line_idx == i then
                    local pad = string.rep(" ", ul.start_col - 1)
                    local mark_len = math.max(1, ul.end_col - ul.start_col)
                    local mark_char = (ul.style == "secondary") and "~" or "^"
                    local mark_color = (ul.style == "secondary") and "blue" or severity_color("error")
                    local mark = string.rep(mark_char, mark_len)

                    out[#out + 1] = color("dim", blank_gutter)
                        .. " " .. color(mark_color, pad .. mark)
                        .. (ul.label and (" " .. color(mark_color, ul.label)) or "")
                end
            end
        end
    end

    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Full report rendering
-------------------------------------------------------------------------------

function M.render(report, source_text)
    if not report then return "" end

    local out = {}
    local sc = severity_color(report.severity)
    local sev_label = report.severity:upper()

    -- Header line: error[E0301]: type mismatch
    local header = color(sc, color("bold", sev_label .. "[" .. report.code .. "]"))
        .. ": " .. (report.primary.message or "unknown error")
    out[#out + 1] = header

    -- Snippet with primary span
    if report.primary.span then
        local snippet
        if report.secondary and #report.secondary > 0 then
            local secs = {}
            for i = 1, math.min(3, #report.secondary) do
                secs[#secs + 1] = {
                    span = report.secondary[i].span,
                    label = report.secondary[i].label,
                }
            end
            local ok_snip, result = pcall(Span.render_multi_snippet,
                report.primary.span, secs, source_text,
                { primary_label = report.primary.label, context = 3 })
            if ok_snip then snippet = result end
        else
            local ok_snip, result = pcall(Span.render_snippet,
                report.primary.span, source_text,
                { context = 3 })
            if ok_snip then
                snippet = result
                -- Add primary label to the last underline
                if snippet.underlines and #snippet.underlines > 0 and report.primary.label then
                    snippet.underlines[#snippet.underlines].label = report.primary.label
                end
            end
        end
        local snippet_text = M.render_snippet(snippet, source_text)
        if snippet_text ~= "" then
            out[#out + 1] = snippet_text
        end
    end

    -- Blank line between snippet and notes
    if (report.notes and #report.notes > 0) or (report.suggestions and #report.suggestions > 0) then
        out[#out + 1] = ""
    end

    -- Notes
    if report.notes then
        for i = 1, #report.notes do
            out[#out + 1] = color("blue", "  = note: ") .. report.notes[i].message
        end
    end

    -- Suggestions
    if report.suggestions then
        for i = 1, #report.suggestions do
            out[#out + 1] = color("green", "  = help: ") .. report.suggestions[i].message
        end
    end

    -- Children (cascading reports, shown more compactly)
    if report.children then
        for i = 1, #report.children do
            out[#out + 1] = ""
            out[#out + 1] = M.render(report.children[i], source_text)
        end
    end

    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Render a list of reports
-------------------------------------------------------------------------------

function M.render_all(reports, source_text)
    local out = {}
    for i = 1, #reports do
        if i > 1 then out[#out + 1] = "" end
        out[#out + 1] = M.render(reports[i], source_text)
    end
    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
-- Render with source text lookup
--
-- Given a registry that has source_cache, this looks up the right
-- source text for each report.
-------------------------------------------------------------------------------

function M.render_from_registry(reports, source_cache)
    local out = {}
    for i = 1, #reports do
        local report = reports[i]
        local text = nil
        if report.primary and report.primary.span then
            text = source_cache[report.primary.span.uri]
        end
        if i > 1 then out[#out + 1] = "" end
        out[#out + 1] = M.render(report, text)
    end
    return table.concat(out, "\n")
end

return M
