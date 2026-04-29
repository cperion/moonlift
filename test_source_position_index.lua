package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local P = PositionIndex.Define(T)

local function doc(text)
    return S.DocumentSnapshot(S.DocUri("file:///test.mlua"), S.DocVersion(1), S.LangMlua, text)
end

local d = doc("a\nb")
local idx = P.build_index(d)
assert(#idx.lines == 2)
assert(idx.lines[1].line == 0 and idx.lines[1].start_offset == 0 and idx.lines[1].stop_offset == 1 and idx.lines[1].next_offset == 2)
assert(idx.lines[2].line == 1 and idx.lines[2].start_offset == 2 and idx.lines[2].stop_offset == 3 and idx.lines[2].next_offset == 3)

local p0 = P.offset_to_pos(idx, 0)
assert(pvm.classof(p0) == S.SourcePositionHit)
assert(p0.pos.line == 0 and p0.pos.byte_col == 0 and p0.pos.utf16_col == 0)
local p1 = P.offset_to_pos(idx, 1)
assert(p1.pos.line == 0 and p1.pos.byte_col == 1 and p1.pos.utf16_col == 1)
local p2 = P.offset_to_pos(idx, 2)
assert(p2.pos.line == 1 and p2.pos.byte_col == 0 and p2.pos.utf16_col == 0)
local p3 = P.offset_to_pos(idx, 3)
assert(p3.pos.line == 1 and p3.pos.byte_col == 1 and p3.pos.utf16_col == 1)
assert(pvm.classof(P.offset_to_pos(idx, 4)) == S.SourcePositionMiss)

local crlf = P.build_index(doc("a\r\nb"))
assert(#crlf.lines == 2)
assert(crlf.lines[1].start_offset == 0 and crlf.lines[1].stop_offset == 1 and crlf.lines[1].next_offset == 3)
assert(P.offset_to_pos(crlf, 2).pos.line == 0)
assert(P.offset_to_pos(crlf, 2).pos.byte_col == 1)
assert(P.offset_to_pos(crlf, 3).pos.line == 1)

local utf = P.build_index(doc("β😀x"))
assert(P.offset_to_pos(utf, 0).pos.utf16_col == 0)
assert(P.offset_to_pos(utf, 2).pos.utf16_col == 1)
assert(P.offset_to_pos(utf, 6).pos.utf16_col == 3)
assert(P.offset_to_pos(utf, 7).pos.utf16_col == 4)
assert(P.byte_offset_at_utf16_col(utf, 0, 0).offset == 0)
assert(P.byte_offset_at_utf16_col(utf, 0, 1).offset == 2)
assert(pvm.classof(P.byte_offset_at_utf16_col(utf, 0, 2)) == S.SourceOffsetMiss)
assert(P.byte_offset_at_utf16_col(utf, 0, 3).offset == 6)
assert(P.byte_offset_at_utf16_col(utf, 0, 4).offset == 7)
assert(P.byte_offset_at_byte_col(utf, 0, 6).offset == 6)
assert(P.source_pos_to_offset(utf, S.SourcePos(0, 6, 3)).offset == 6)
assert(pvm.classof(P.source_pos_to_offset(utf, S.SourcePos(0, 6, 2))) == S.SourceOffsetMiss)
assert(pvm.classof(P.byte_offset_at_byte_col(utf, 0, 8)) == S.SourceOffsetMiss)

local empty = P.build_index(doc(""))
assert(#empty.lines == 1)
assert(P.offset_to_pos(empty, 0).pos.line == 0)

local trailing = P.build_index(doc("a\n"))
assert(#trailing.lines == 2)
assert(trailing.lines[2].start_offset == 2 and trailing.lines[2].stop_offset == 2)
assert(P.offset_to_pos(trailing, 2).pos.line == 1)

local bad = P.build_index(doc(string.char(0xff) .. "x"))
assert(P.offset_to_pos(bad, 1).pos.utf16_col == 1)
assert(P.offset_to_pos(bad, 2).pos.utf16_col == 2)

local r = assert(P.range_from_offsets(idx, 0, 3))
assert(r.start.line == 0 and r.stop.line == 1 and r.stop.byte_col == 1)

print("moonlift source position index ok")
