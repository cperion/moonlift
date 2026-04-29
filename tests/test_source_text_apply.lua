package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local SourceApply = require("moonlift.source_text_apply")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local Apply = SourceApply.Define(T)

local uri = S.DocUri("file:///edit.mlua")
local other = S.DocUri("file:///other.mlua")
local function doc(version, text)
    return S.DocumentSnapshot(uri, S.DocVersion(version), S.LangMlua, text)
end

local d1 = doc(1, "hello")
local full = Apply.apply(d1, S.DocumentEdit(uri, S.DocVersion(2), { S.ReplaceAll("world") }))
assert(pvm.classof(full) == S.SourceApplyOk)
assert(full.document.version == S.DocVersion(2))
assert(full.document.text == "world")

local r_mid = Apply.range(d1, 1, 4)
local mid = Apply.apply(d1, S.DocumentEdit(uri, S.DocVersion(2), { S.ReplaceRange(r_mid, "ipp") }))
assert(pvm.classof(mid) == S.SourceApplyOk)
assert(mid.document.text == "hippo")

local d2 = doc(1, "abcdef")
local multi = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(d2, 1, 2), "B"),
    S.ReplaceRange(Apply.range(d2, 4, 5), "E"),
}))
assert(pvm.classof(multi) == S.SourceApplyOk)
assert(multi.document.text == "aBcdEf")

local insert = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(d2, 0, 0), "<"),
    S.ReplaceRange(Apply.range(d2, 6, 6), ">"),
}))
assert(insert.document.text == "<abcdef>")

local multiline = doc(1, "a\nb\nc")
local multi_line_edit = Apply.apply(multiline, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(multiline, 2, 3), "B"),
}))
assert(multi_line_edit.document.text == "a\nB\nc")

local utf = doc(1, "βx")
local utf_edit = Apply.apply(utf, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(utf, 2, 3), "y"),
}))
assert(utf_edit.document.text == "βy")

local overlap = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(d2, 1, 4), "x"),
    S.ReplaceRange(Apply.range(d2, 3, 5), "y"),
}))
assert(pvm.classof(overlap) == S.SourceApplyRejected)
assert(pvm.classof(overlap.issues[1]) == S.SourceIssueOverlappingRanges)

local stale = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(0), { S.ReplaceAll("x") }))
assert(pvm.classof(stale) == S.SourceApplyRejected)
assert(pvm.classof(stale.issues[1]) == S.SourceIssueStaleVersion)

local wrong = Apply.apply(d2, S.DocumentEdit(other, S.DocVersion(2), { S.ReplaceAll("x") }))
assert(pvm.classof(wrong) == S.SourceApplyRejected)
assert(pvm.classof(wrong.issues[1]) == S.SourceIssueWrongDocument)

local mixed = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceAll("x"),
    S.ReplaceRange(Apply.range(d2, 0, 1), "y"),
}))
assert(pvm.classof(mixed) == S.SourceApplyRejected)
assert(mixed.issues[1] == S.SourceIssueMixedReplaceAll)

print("moonlift source text apply ok")
