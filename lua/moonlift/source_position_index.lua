local pvm = require("moonlift.pvm")

local M = {}

local function utf8_char_len_and_cp(text, i, stop_i)
    local b1 = text:byte(i)
    if not b1 then return 0, nil end
    if b1 < 0x80 then
        return 1, b1
    end
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
            if cp >= 0x800 and not (cp >= 0xD800 and cp <= 0xDFFF) then
                return 3, cp
            end
        end
    elseif b1 >= 0xF0 and b1 <= 0xF4 and i + 3 <= stop_i then
        local b2, b3, b4 = text:byte(i + 1), text:byte(i + 2), text:byte(i + 3)
        local ok = b2 and b3 and b4
            and b2 >= 0x80 and b2 <= 0xBF
            and b3 >= 0x80 and b3 <= 0xBF
            and b4 >= 0x80 and b4 <= 0xBF
        if ok then
            local cp = (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80)
            if cp >= 0x10000 and cp <= 0x10FFFF then
                return 4, cp
            end
        end
    end
    -- Invalid UTF-8 bytes are explicit source bytes and count as one UTF-16
    -- unit for editor-position recovery.
    return 1, b1
end

local function utf16_units(text, start_offset, stop_offset)
    local units = 0
    local i = start_offset + 1
    local stop_i = stop_offset
    while i <= stop_i do
        local len, cp = utf8_char_len_and_cp(text, i, stop_i)
        if len == 0 then break end
        units = units + ((cp and cp > 0xFFFF) and 2 or 1)
        i = i + len
    end
    return units
end

local function find_line(lines, offset)
    for i = 1, #lines do
        local line = lines[i]
        if i == #lines then
            if offset >= line.start_offset and offset <= line.next_offset then
                return line
            end
        elseif offset >= line.start_offset and offset < line.next_offset then
            return line
        end
    end
    return nil
end

local function build_lines(S, document)
    local text = document.text
    local n = #text
    local lines = {}
    local line_no = 0
    local start_offset = 0
    local i = 1
    while i <= n do
        local b = text:byte(i)
        if b == 10 then
            local lf_offset = i - 1
            local stop_offset = lf_offset
            if i > 1 and text:byte(i - 1) == 13 then
                stop_offset = lf_offset - 1
            end
            lines[#lines + 1] = S.SourceLineSpan(line_no, start_offset, stop_offset, lf_offset + 1)
            line_no = line_no + 1
            start_offset = lf_offset + 1
        end
        i = i + 1
    end
    lines[#lines + 1] = S.SourceLineSpan(line_no, start_offset, n, n)
    return lines
end

function M.Define(T)
    local S = T.MoonSource

    local build_index_phase = pvm.phase("moon2_source_position_index", function(document)
        return S.PositionIndex(document, build_lines(S, document))
    end)

    local function build_index(document)
        return pvm.one(build_index_phase(document))
    end

    local function offset_to_pos(index, offset)
        if type(offset) ~= "number" or offset < 0 or offset > #index.document.text or offset % 1 ~= 0 then
            return S.SourcePositionMiss("offset outside document")
        end
        local line = find_line(index.lines, offset)
        if not line then
            return S.SourcePositionMiss("offset has no line")
        end
        local content_offset = offset
        if content_offset > line.stop_offset then
            content_offset = line.stop_offset
        end
        local byte_col = content_offset - line.start_offset
        local utf16_col = utf16_units(index.document.text, line.start_offset, content_offset)
        return S.SourcePositionHit(S.SourcePos(line.line, byte_col, utf16_col))
    end

    local function byte_offset_at_utf16_col(index, line_no, utf16_col)
        if type(line_no) ~= "number" or line_no % 1 ~= 0 or line_no < 0 then
            return S.SourceOffsetMiss("invalid line")
        end
        if type(utf16_col) ~= "number" or utf16_col % 1 ~= 0 or utf16_col < 0 then
            return S.SourceOffsetMiss("invalid utf16 column")
        end
        local line = index.lines[line_no + 1]
        if not line then
            return S.SourceOffsetMiss("line outside document")
        end
        local text = index.document.text
        local units = 0
        local i = line.start_offset + 1
        local stop_i = line.stop_offset
        if utf16_col == 0 then
            return S.SourceOffsetHit(line.start_offset)
        end
        while i <= stop_i do
            local len, cp = utf8_char_len_and_cp(text, i, stop_i)
            if len == 0 then break end
            local add = (cp and cp > 0xFFFF) and 2 or 1
            if utf16_col == units then
                return S.SourceOffsetHit(i - 1)
            end
            if utf16_col > units and utf16_col < units + add then
                return S.SourceOffsetMiss("utf16 column splits a source character")
            end
            units = units + add
            i = i + len
            if utf16_col == units then
                return S.SourceOffsetHit(i - 1)
            end
        end
        if utf16_col == units then
            return S.SourceOffsetHit(line.stop_offset)
        end
        return S.SourceOffsetMiss("utf16 column outside line")
    end

    local function byte_offset_at_byte_col(index, line_no, byte_col)
        if type(line_no) ~= "number" or line_no % 1 ~= 0 or line_no < 0 then
            return S.SourceOffsetMiss("invalid line")
        end
        if type(byte_col) ~= "number" or byte_col % 1 ~= 0 or byte_col < 0 then
            return S.SourceOffsetMiss("invalid byte column")
        end
        local line = index.lines[line_no + 1]
        if not line then
            return S.SourceOffsetMiss("line outside document")
        end
        local offset = line.start_offset + byte_col
        if offset > line.stop_offset then
            return S.SourceOffsetMiss("byte column outside line")
        end
        return S.SourceOffsetHit(offset)
    end

    local function source_pos_to_offset(index, pos)
        local hit = byte_offset_at_byte_col(index, pos.line, pos.byte_col)
        if pvm.classof(hit) ~= S.SourceOffsetHit then
            return hit
        end
        local round = offset_to_pos(index, hit.offset)
        if pvm.classof(round) ~= S.SourcePositionHit then
            return S.SourceOffsetMiss(round.reason)
        end
        if round.pos.utf16_col ~= pos.utf16_col then
            return S.SourceOffsetMiss("source position byte/utf16 columns disagree")
        end
        return hit
    end

    local function range_from_offsets(index, start_offset, stop_offset)
        local sr = offset_to_pos(index, start_offset)
        if pvm.classof(sr) ~= S.SourcePositionHit then
            return nil, sr.reason
        end
        local er = offset_to_pos(index, stop_offset)
        if pvm.classof(er) ~= S.SourcePositionHit then
            return nil, er.reason
        end
        return S.SourceRange(index.document.uri, start_offset, stop_offset, sr.pos, er.pos)
    end

    return {
        build_index_phase = build_index_phase,
        build_index = build_index,
        offset_to_pos = offset_to_pos,
        byte_offset_at_utf16_col = byte_offset_at_utf16_col,
        byte_offset_at_byte_col = byte_offset_at_byte_col,
        source_pos_to_offset = source_pos_to_offset,
        range_from_offsets = range_from_offsets,
    }
end

return M
