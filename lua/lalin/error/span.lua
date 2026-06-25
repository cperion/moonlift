-- lalin/error/span.lua
-- SourceSpan: a lightweight, renderable source range for error reporting.
--
-- This builds on LalinSource.SourceRange but adds rendering logic
-- independent of the ASDL/PVM layer. Error reporting needs to be
-- able to render spans without depending on the full schema stack.

local M = {}

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

function M.from_source_range(range, uri)
    return {
        uri = uri or (range.uri and range.uri.text) or "?",
        start_offset = range.start_offset or 0,
        end_offset = range.stop_offset or range.start_offset or 0,
        -- LalinSource.SourcePos is zero-based (LSP-style); SourceSpan is
        -- one-based for terminal display and converted back by present_lsp.
        start_line = (range.start and range.start.line or 0) + 1,
        start_col = (range.start and range.start.utf16_col or 0) + 1,
        end_line = (range.stop and range.stop.line or 0) + 1,
        end_col = (range.stop and range.stop.utf16_col or 0) + 1,
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
    local start_offset = (tok.start or 1) - 1   -- parser tokens are 1-based inclusive
    local end_offset = tok.stop or start_offset -- converted to 0-based exclusive
    return {
        uri = uri or "?",
        start_offset = start_offset,
        end_offset = end_offset,
        start_line = tok.line or 1,
        start_col = tok.col or 1,
        end_line = tok.line or 1,
        end_col = (tok.col or 1) + math.max(1, end_offset - start_offset),
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
    -- offset is 1-based (Lua string index / insertion position)
    local lo, hi = 1, #line_starts
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if line_starts[mid] <= offset then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return math.max(1, math.min(#line_starts, hi))
end

local function utf8_char_len_and_cp(text, i, stop_i)
    local b1 = text:byte(i)
    if not b1 then return 0, nil end
    if b1 < 0x80 then return 1, b1 end
    if b1 >= 0xC2 and b1 <= 0xDF and i + 1 <= stop_i then
        local b2 = text:byte(i + 1)
        if b2 and b2 >= 0x80 and b2 <= 0xBF then
            return 2, (b1 - 0xC0) * 0x40 + (b2 - 0x80)
        end
    elseif b1 >= 0xE0 and b1 <= 0xEF and i + 2 <= stop_i then
        local b2, b3 = text:byte(i + 1), text:byte(i + 2)
        local ok = b2 and b3 and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF
        if ok then
            local cp = (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
            if cp >= 0x800 and not (cp >= 0xD800 and cp <= 0xDFFF) then return 3, cp end
        end
    elseif b1 >= 0xF0 and b1 <= 0xF4 and i + 3 <= stop_i then
        local b2, b3, b4 = text:byte(i + 1), text:byte(i + 2), text:byte(i + 3)
        local ok = b2 and b3 and b4 and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF and b4 >= 0x80 and b4 <= 0xBF
        if ok then
            local cp = (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80)
            if cp >= 0x10000 and cp <= 0x10FFFF then return 4, cp end
        end
    end
    return 1, b1
end

local function utf16_units(text, start_1, stop_1_excl)
    local units = 0
    local i = start_1
    local stop_i = stop_1_excl - 1
    while i <= stop_i do
        local len, cp = utf8_char_len_and_cp(text, i, stop_i)
        if len == 0 then break end
        units = units + ((cp and cp > 0xFFFF) and 2 or 1)
        i = i + len
    end
    return units
end

local function clamp_offsets(src, start_offset, end_offset)
    local n = #src
    start_offset = tonumber(start_offset) or 0
    end_offset = tonumber(end_offset) or start_offset
    if start_offset < 0 then start_offset = 0 end
    if start_offset > n then start_offset = n end
    if end_offset < start_offset then end_offset = start_offset end
    if end_offset > n then end_offset = n end
    return start_offset, end_offset
end

function M.from_source_text(uri, source_text, start_offset, end_offset)
    source_text = source_text or ""
    start_offset, end_offset = clamp_offsets(source_text, start_offset, end_offset)
    local line_starts = build_line_table(source_text)
    local start_1 = start_offset + 1
    local end_1 = end_offset + 1
    local start_line = find_line(line_starts, start_1)
    local end_line = find_line(line_starts, math.max(1, end_1))
    local start_col = utf16_units(source_text, line_starts[start_line], start_1) + 1
    local end_col = utf16_units(source_text, line_starts[end_line], end_1) + 1
    return M.from_offsets(uri or "?", start_offset, end_offset, start_line, start_col, end_line, end_col)
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

    -- Convert 0-based half-open offsets to 1-based Lua string positions.
    -- Empty ranges still render as a one-column caret.
    local start_offset, end_offset = clamp_offsets(source_text, span.start_offset or 0, span.end_offset or span.start_offset or 0)
    local start_1 = start_offset + 1
    local end_1 = end_offset + 1
    if end_1 <= start_1 then end_1 = math.min(#source_text + 1, start_1 + 1) end

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
            local line_start = line_starts[ln]
            local line_end_excl = line_start + #l.text

            local ustart = math.max(start_1, line_start) - line_start + 1
            local uend = math.min(end_1, line_end_excl) - line_start + 1
            if uend <= ustart then uend = ustart + 1 end

            underlines[#underlines + 1] = {
                line_idx = i,
                start_col = math.max(1, ustart),
                end_col = math.max(ustart + 1, uend),
                style = "primary",
                label = nil,
            }
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
        local so, eo = clamp_offsets(source_text, sp.start_offset or 0, sp.end_offset or sp.start_offset or 0)
        local s1 = so + 1
        local e1 = eo + 1
        if e1 <= s1 then e1 = math.min(#source_text + 1, s1 + 1) end
        local sl = find_line(line_starts, math.max(1, s1))
        local el = find_line(line_starts, math.max(1, e1 - 1))
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

    local underlines = {}
    -- We use the closure above but need underlines in scope
    -- Re-implement inline to avoid closure issues
    local function add_ul(span, style, label)
        local so, eo = clamp_offsets(source_text, span.start_offset or 0, span.end_offset or span.start_offset or 0)
        local s1 = so + 1
        local e1 = eo + 1
        if e1 <= s1 then e1 = math.min(#source_text + 1, s1 + 1) end
        local sl = find_line(line_starts, s1)
        local el = find_line(line_starts, math.max(1, e1 - 1))

        for i, l in ipairs(lines) do
            local ln = l.line_no
            if ln >= sl and ln <= el then
                local line_start = line_starts[ln]
                local line_end_excl = line_start + #l.text

                local ustart = math.max(s1, line_start) - line_start + 1
                local uend = math.min(e1, line_end_excl) - line_start + 1
                if uend <= ustart then uend = ustart + 1 end

                underlines[#underlines + 1] = {
                    line_idx = i,
                    start_col = math.max(1, ustart),
                    end_col = math.max(ustart + 1, uend),
                    style = style,
                    label = (ln == el) and label or nil,
                }
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
