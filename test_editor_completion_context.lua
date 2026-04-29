package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local ContextMod = require("moonlift.editor_completion_context")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local Analysis = AnalysisMod.Define(T)
local Context = ContextMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///completion_context.mlua")
local src = "struct User { id: i32 active: bool32 }\nexpose Users: view(User) { lua }\n\n"
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local idx = P.build_index(doc)
local function q(offset)
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, offset).pos)
end
local function at_text(text, delta)
    local s = assert(src:find(text, 1, true))
    return q(s - 1 + (delta or 0))
end

assert(Context.context(q(#src), analysis) == E.CompletionTopLevel)
assert(Context.context(at_text("i32", 1), analysis) == E.CompletionTypePosition)
assert(Context.context(at_text("Users: ", #"Users: "), analysis) == E.CompletionExposeSubject)
local expose_start = assert(src:find("expose", 1, true))
local expose_brace = assert(src:find("{ ", expose_start, true))
local expose_lua = assert(src:find("lua", expose_start, true))
assert(Context.context(q(expose_brace - 1 + #"{ "), analysis) == E.CompletionExposeTarget)
assert(Context.context(q(expose_lua - 1 + #"lua"), analysis) == E.CompletionExposeTarget)

Context.context_phase:reset()
pvm.drain(Context.context_phase(q(#src), analysis))
pvm.drain(Context.context_phase(q(#src), analysis))
local report = pvm.report({ Context.context_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift editor completion context ok")
