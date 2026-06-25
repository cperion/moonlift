-- lalin/source_map.lua
-- Canonical source/line mapping helpers for Lalin diagnostics.

local M = {}

function M.index(src)
    local starts = {1}
    local n = #src
    for i = 1, n do
        if string.byte(src, i) == 10 then
            starts[#starts + 1] = i + 1
        end
    end
    return {
        src = src,
        line_starts = starts,
    }
end

function M.line_col(index, offset)
    if not index or not index.line_starts or #index.line_starts == 0 then return 1, 1 end
    if not offset or offset < 1 then return 1, 1 end
    local starts = index.line_starts
    local lo, hi = 1, #starts
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if starts[mid] <= offset then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    local line = math.max(1, hi)
    local col = math.max(1, offset - starts[line] + 1)
    return line, col
end

function M.line_text(index, line_no)
    if not index or not index.src or not index.line_starts then return "" end
    local starts = index.line_starts
    local s = starts[line_no]
    if not s then return "" end
    local e = (starts[line_no + 1] or (#index.src + 1)) - 1
    if e >= s and string.byte(index.src, e) == 10 then e = e - 1 end
    if e >= s and string.byte(index.src, e) == 13 then e = e - 1 end
    if e < s then return "" end
    return index.src:sub(s, e)
end

function M.snippet(index, line_no, col, ctx)
    if not index or not index.src or not index.line_starts or not line_no then return nil end
    ctx = ctx or 2
    local max_line = #index.line_starts
    local from = math.max(1, line_no - ctx)
    local to = math.min(max_line, line_no + ctx)
    local out = {}
    for ln = from, to do
        local mark = (ln == line_no) and ">" or " "
        local text = M.line_text(index, ln)
        out[#out + 1] = string.format("%s %5d | %s", mark, ln, text)
        if ln == line_no and col and col > 0 then
            local pad = string.rep(" ", math.max(0, col - 1))
            out[#out + 1] = string.format("  %5s | %s^", "", pad)
        end
    end
    return table.concat(out, "\n")
end

function M.new_carrier_map(wrapper_lines)
    return {
        wrapper_lines = wrapper_lines or 0,
        line_map = {},
        next_generated_line = 1,
    }
end

function M.count_lines(text)
    local nlines = 1
    for _ in (text or ""):gmatch("\n") do nlines = nlines + 1 end
    return nlines
end

function M.carrier_emit(builder, text, map_fn)
    local nlines = M.count_lines(text)
    for i = 1, nlines do
        if map_fn then builder.line_map[builder.next_generated_line] = map_fn(i) end
        builder.next_generated_line = builder.next_generated_line + 1
    end
end

function M.lookup_generated(builder, generated_line)
    if not builder or not generated_line then return nil end
    local source_line_in_carrier = generated_line - (builder.wrapper_lines or 0)
    if source_line_in_carrier < 1 then return nil end
    return builder.line_map[source_line_in_carrier]
end

return M
