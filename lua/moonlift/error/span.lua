-- moonlift/error/span.lua
-- SourceSpan: a lightweight, renderable source range for error reporting.
--
-- This builds on MoonSource.SourceRange but adds rendering logic
-- independent of the ASDL/PVM layer. Error reporting needs to be
-- able to render spans without depending on the full schema stack.

local M = {}

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

function M.from_source_range(range)
    return {
        uri = range.uri and range.uri.text or "?",
        start_offset = range.start_offset or 0,
        end_offset = range.stop_offset or 0,
        start_line = range.start and range.start.line or 1,
        start_col = range.start and range.start.utf16_col or 1,
        end_line = range.stop and range.stop.line or 1,
        end_col = range.stop and range.stop.utf16_col or 1,
    }
end

function M.from_offsets(uri, start_offset, end_offset, start_line, start_col, end_line, end_col)
    return {
        uri = uri or "?",
        start_offset = start_offset or 0,
        end_offset = end_offset or start_offset or 0,
        start_line = start_line or 1,
        start_col = start_col or 1,
        end_line = end_line or start_line or 1,
        end_col = end_col or start_col or 1,
    }
end

function M.from_token(tok, uri)
    return {
        uri = uri or "?",
        start_offset = (tok.start or 1) - 1,   -- convert 1-based to 0-based
        end_offset = tok.stop or 0,
        start_line = tok.line or 1,
        start_col = tok.col or 1,
        end_line = tok.line or 1,
        end_col = (tok.col or 1) + ((tok.stop or 0) - (tok.start or 1)),
    }
end

function M.point(uri, offset, line, col)
    return {
        uri = uri or "?",
        start_offset = offset or 0,
        end_offset = offset or 0,
        start_line = line or 1,
        start_col = col or 1,
        end_line = line or 1,
        end_col = col or 1,
    }
end

-------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------

function M.is_point(span)
    return span.start_offset == span.end_offset
end

function M.length(span)
    return span.end_offset - span.start_offset
end

function M.contains(span, offset)
    return offset >= span.start_offset and offset < span.end_offset
end

function M.overlaps(a, b)
    return a.uri == b.uri
        and a.start_offset < b.end_offset
        and b.start_offset < a.end_offset
end

function M.same_span(a, b)
    if a.uri ~= b.uri then return false end
    if a.start_offset ~= b.start_offset then return false end
    if a.end_offset ~= b.end_offset then return false end
    return true
end

function M.key(span)
    return span.uri .. ":" .. span.start_offset .. "-" .. span.end_offset
end

-------------------------------------------------------------------------------
-- Source text access
-------------------------------------------------------------------------------

local function build_line_table(src)
    local starts = { 1 }
    local n = #src
    for i = 1, n do
        if string.byte(src, i) == 10 then
            starts[#starts + 1] = i + 1
        end
    end
    return starts
end

local function find_line(line_starts, offset)
    -- offset is 1-based (Lua string index)
    local lo, hi = 1, #line_starts
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if line_starts[mid] <= offset then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return math.max(1, hi)
end

local function get_line_text(src, line_starts, line_no)
    local s = line_starts[line_no]
    if not s then return "" end
    local e = (line_starts[line_no + 1] or (#src + 1)) - 1
    if e >= s and string.byte(src, e) == 10 then e = e - 1 end
    if e >= s and string.byte(src, e) == 13 then e = e - 1 end
    if e < s then return "" end
    return src:sub(s, e)
end

-- Visual width of a line number (for gutter alignment)
local function gutter_width(line_no)
    return math.max(3, #tostring(line_no))
end

-------------------------------------------------------------------------------
-- Snippet rendering
--
-- Returns a structured snippet that the presenter can format.
--
--   snippet = {
--     uri = string,
--     lines = {
--       { line_no = 42, text = "let x: i32 = \"hello\"", gutter = "42 │" },
--     },
--     underlines = {
--       { line_idx = 1, start_col = 12, end_col = 19,
--         style = "primary", label = "this is `string`" },
--     },
--   }
-------------------------------------------------------------------------------

function M.render_snippet(span, source_text, opts)
    opts = opts or {}
    local context = opts.context or 2
    source_text = source_text or ""

    local line_starts = build_line_table(source_text)

    -- Convert 0-based offsets to 1-based for Lua string ops
    local start_1 = span.start_offset + 1
    local end_1 = span.end_offset + 1
    if start_1 < 1 then start_1 = 1 end
    if end_1 < start_1 then end_1 = start_1 end

    local start_line = find_line(line_starts, start_1)
    local end_line = find_line(line_starts, math.max(1, end_1 - 1))
    if end_line < start_line then end_line = start_line end

    -- Clamp to context window
    local max_line = #line_starts
    local from = math.max(1, start_line - context)
    local to = math.min(max_line, end_line + context)

    local lines = {}
    for ln = from, to do
        lines[#lines + 1] = {
            line_no = ln,
            text = get_line_text(source_text, line_starts, ln),
        }
    end

    -- Compute underline positions for the primary span
    local underlines = {}
    for i, l in ipairs(lines) do
        local ln = l.line_no
        if ln >= start_line and ln <= end_line then
            local line_start_offset = line_starts[ln]
            local line_end_offset = (line_starts[ln + 1] or (#source_text + 2)) - 1

            local ustart = math.max(start_1, line_start_offset) - line_start_offset + 1
            local uend = math.min(end_1, line_end_offset) - line_start_offset

            if uend > ustart then
                underlines[#underlines + 1] = {
                    line_idx = i,
                    start_col = ustart,
                    end_col = uend,
                    style = "primary",
                    label = nil,
                }
            end
        end
    end

    return {
        uri = span.uri,
        lines = lines,
        underlines = underlines,
    }
end

-------------------------------------------------------------------------------
-- Multi-span snippet rendering
--
-- Renders multiple spans in a single snippet view. Primary span gets
-- `^^^` underlines, secondary spans get `~~~`.
-------------------------------------------------------------------------------

function M.render_multi_snippet(primary, secondaries, source_text, opts)
    opts = opts or {}
    local context = opts.context or 2
    source_text = source_text or ""
    secondaries = secondaries or {}

    local all_spans = { primary }
    for i = 1, #secondaries do all_spans[#all_spans + 1] = secondaries[i] end

    local line_starts = build_line_table(source_text)
    local max_line = #line_starts

    -- Find the line range covering all spans
    local min_line = max_line
    local max_ln = 1
    for _, sp in ipairs(all_spans) do
        local s1 = sp.start_offset + 1
        local e1 = sp.end_offset
        local sl = find_line(line_starts, math.max(1, s1))
        local el = find_line(line_starts, math.max(1, e1))
        if sl < min_line then min_line = sl end
        if el > max_ln then max_ln = el end
    end

    local from = math.max(1, min_line - context)
    local to = math.min(max_line, max_ln + context)

    local lines = {}
    for ln = from, to do
        lines[#lines + 1] = {
            line_no = ln,
            text = get_line_text(source_text, line_starts, ln),
        }
    end

    local function add_underlines(span, style, label)
        local s1 = span.start_offset + 1
        local e1 = span.end_offset + 1
        local sl = find_line(line_starts, math.max(1, s1))
        local el = find_line(line_starts, math.max(1, e1 - 1))

        for i, l in ipairs(lines) do
            local ln = l.line_no
            if ln >= sl and ln <= el then
                local line_start_offset = line_starts[ln]
                local line_end_offset = (line_starts[ln + 1] or (#source_text + 2)) - 1

                local ustart = math.max(s1, line_start_offset) - line_start_offset + 1
                local uend = math.min(e1, line_end_offset) - line_start_offset

                if uend > ustart then
                    underlines[#underlines + 1] = {
                        line_idx = i,
                        start_col = ustart,
                        end_col = uend,
                        style = style,
                        label = (ln == el) and label or nil,
                    }
                end
            end
        end
    end

    local underlines = {}
    -- We use the closure above but need underlines in scope
    -- Re-implement inline to avoid closure issues
    local function add_ul(span, style, label)
        local s1 = span.start_offset + 1
        local e1 = span.end_offset + 1
        if s1 < 1 then s1 = 1 end
        if e1 < s1 then e1 = s1 end
        local sl = find_line(line_starts, s1)
        local el = find_line(line_starts, math.max(1, e1 - 1))

        for i, l in ipairs(lines) do
            local ln = l.line_no
            if ln >= sl and ln <= el then
                local line_start_offset = line_starts[ln]
                local line_end_offset = (line_starts[ln + 1] or (#source_text + 2)) - 1

                local ustart = math.max(s1, line_start_offset) - line_start_offset + 1
                local uend = math.min(e1, line_end_offset) - line_start_offset

                if uend >= ustart then
                    underlines[#underlines + 1] = {
                        line_idx = i,
                        start_col = ustart,
                        end_col = uend,
                        style = style,
                        label = (ln == el) and label or nil,
                    }
                end
            end
        end
    end

    add_ul(primary, "primary", opts.primary_label)
    for i, sec in ipairs(secondaries) do
        local label = sec.label or opts["secondary_label_" .. i]
        add_ul(sec.span or sec, "secondary", label)
    end

    return {
        uri = primary.uri,
        lines = lines,
        underlines = underlines,
    }
end

return M
