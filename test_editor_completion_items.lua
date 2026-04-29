package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local ContextMod = require("moonlift.editor_completion_context")
local ItemsMod = require("moonlift.editor_completion_items")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local Analysis = AnalysisMod.Define(T)
local Context = ContextMod.Define(T)
local Items = ItemsMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///completion_items.mlua")
local src = "struct User\n  id: i32\n  active: bool32\nend\nexpose Users: view(User)\n\n"
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local idx = P.build_index(doc)
local function query(offset)
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, offset).pos)
end
local function has(items, label)
    for i = 1, #items do if items[i].label == label then return true end end
    return false
end

local top = Items.complete(query(#src), analysis)
assert(has(top, "struct") and has(top, "func") and has(top, "region"))

local type_items = Items.items(E.CompletionQuery(query((src:find("i32", 1, true) - 1) + 1), E.CompletionTypePosition), analysis)
assert(has(type_items, "i32") and has(type_items, "ptr") and has(type_items, "view") and has(type_items, "User"))

local expose_subject = Items.items(E.CompletionQuery(query(0), E.CompletionExposeSubject), analysis)
assert(has(expose_subject, "view") and has(expose_subject, "ptr") and has(expose_subject, "User"))

local targets = Items.items(E.CompletionQuery(query(0), E.CompletionExposeTarget), analysis)
assert(has(targets, "lua") and has(targets, "terra") and has(targets, "c"))

local modes = Items.items(E.CompletionQuery(query(0), E.CompletionExposeMode), analysis)
assert(has(modes, "proxy") and has(modes, "descriptor") and has(modes, "readonly") and has(modes, "mutable") and has(modes, "checked") and has(modes, "unchecked"))

local builtins = Items.items(E.CompletionQuery(query(0), E.CompletionBuiltinPath), analysis)
assert(has(builtins, "json") and has(builtins, "builtins"))

local none = Items.items(E.CompletionQuery(query(0), E.CompletionLuaOpaque), analysis)
assert(#none == 0)

Items.completion_phase:reset()
pvm.drain(Items.completion_phase(query(#src), analysis))
pvm.drain(Items.completion_phase(query(#src), analysis))
local report = pvm.report({ Items.completion_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift editor completion items ok")
