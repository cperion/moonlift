package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local FoldingMod = require("moonlift.editor_folding_ranges")
local SelectionMod = require("moonlift.editor_selection_ranges")
local InlayMod = require("moonlift.editor_inlay_hints")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local E = T.MoonEditor
local Analysis = AnalysisMod.Define(T)
local Folding = FoldingMod.Define(T)
local Selection = SelectionMod.Define(T)
local Inlay = InlayMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///structure.mlua")
local src = [[
struct User
    id: i32
    active: bool32
end

region Done(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local folds = Folding.ranges(analysis)
assert(#folds >= 2)
assert(folds[1].range.stop.line >= folds[1].range.start.line)

local idx = P.build_index(doc)
local id_pos = P.offset_to_pos(idx, assert(src:find("id", 1, true)) - 1).pos
local selections = Selection.selections({ E.PositionQuery(uri, S.DocVersion(1), id_pos) }, analysis)
assert(#selections == 1)
assert(#selections[1].parents >= 1)

local all_range = assert(P.range_from_offsets(idx, 0, #src))
local hints = Inlay.hints(E.RangeQuery(uri, S.DocVersion(1), all_range), analysis)
assert(#hints == 0)

print("moonlift editor structure ranges ok")
