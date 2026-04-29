package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local TokensMod = require("moonlift.editor_semantic_tokens")
local AdaptMod = require("moonlift.lsp_payload_adapt")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local Analysis = AnalysisMod.Define(T)
local Tokens = TokensMod.Define(T)
local Adapt = AdaptMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///tokens.mlua")
local src = [[
struct User
    id: i32
    active: bool32
end
expose Users: view(User)
func User:is_active(self: ptr(User)) -> bool
    return true
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local tokens = Tokens.tokens(analysis)
assert(#tokens > 0)
local saw_keyword, saw_struct, saw_field, saw_type, saw_func = false, false, false, false, false
for i = 1, #tokens do
    local t = tokens[i]
    if t.token_type == E.TokKeyword then saw_keyword = true end
    if t.token_type == E.TokStruct then saw_struct = true end
    if t.token_type == E.TokProperty then saw_field = true end
    if t.token_type == E.TokType then saw_type = true end
    if t.token_type == E.TokFunction then saw_func = true end
end
assert(saw_keyword and saw_struct and saw_field and saw_type and saw_func)

local idx = P.build_index(doc)
local r = assert(P.range_from_offsets(idx, src:find("expose", 1, true) - 1, #src))
local range_tokens = Tokens.range_tokens(E.RangeQuery(uri, S.DocVersion(1), r), analysis)
assert(#range_tokens < #tokens)

local encoded = Adapt.semantic_tokens(tokens)
assert(pvm.classof(encoded) == T.Moon2Lsp.SemanticTokens)
assert(#encoded.data > 0 and #encoded.data % 5 == 0)

print("moonlift editor semantic tokens ok")
