package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local InlayMod = require("moonlift.editor_inlay_hints")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local E = T.MoonEditor
local Analysis = AnalysisMod.Define(T)
local Inlay = InlayMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///inlay.mlua")
local src = [[
func add(a: i32, b: i32) -> i32
    return a
end
expr Use() -> i32
    add(1, 2)
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local idx = P.build_index(doc)
local r = assert(P.range_from_offsets(idx, 0, #src))
local hints = Inlay.hints(E.RangeQuery(uri, S.DocVersion(1), r), analysis)
assert(#hints == 2)
assert(hints[1].label == "a:")
assert(hints[2].label == "b:")
assert(hints[1].kind == "parameter")

print("moonlift editor inlay hints ok")
