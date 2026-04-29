package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local HoverMod = require("moonlift.editor_hover")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local E = T.MoonEditor
local Analysis = AnalysisMod.Define(T)
local Hover = HoverMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///hover.mlua")
local src = [[
struct User
    id: i32
    active: bool32
end
expose Users: view(User)
func User:is_active(self: ptr(User)) -> bool
    return true
end
region Done(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
expr FortyTwo() -> i32
    42
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local idx = P.build_index(doc)
local function query_at(text)
    local s = assert(src:find(text, 1, true))
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, s - 1).pos)
end

local h_struct = Hover.hover(query_at("User"), analysis)
assert(pvm.classof(h_struct) == E.HoverInfo)
assert(h_struct.value:match("host struct"))
assert(h_struct.value:match("size:"))

local h_field = Hover.hover(query_at("id"), analysis)
assert(h_field.value:match("field `User.id`"))
assert(h_field.value:match("offset:"))

local h_scalar = Hover.hover(query_at("i32"), analysis)
assert(h_scalar.value:match("scalar"))

local h_expose = Hover.hover(query_at("Users"), analysis)
assert(h_expose.value:match("host expose"))

local h_method = Hover.hover(query_at("User:is_active"), analysis)
assert(h_method.value:match("accessor") or h_method.value:match("function"))

local h_region = Hover.hover(query_at("Done"), analysis)
assert(h_region.value:match("region fragment"))

local h_expr = Hover.hover(query_at("FortyTwo"), analysis)
assert(h_expr.value:match("expr fragment"))

local unresolved_src = "func unresolved() -> i32\n    return missing + 1\nend\n"
local unresolved_doc = S.DocumentSnapshot(uri, S.DocVersion(2), S.LangMlua, unresolved_src)
local unresolved_analysis = Analysis.analyze_document(unresolved_doc)
local unresolved_idx = P.build_index(unresolved_doc)
local missing_offset = unresolved_src:find("missing", 1, true) - 1
local h_unresolved = Hover.hover(E.PositionQuery(uri, S.DocVersion(2), P.offset_to_pos(unresolved_idx, missing_offset).pos), unresolved_analysis)
assert(pvm.classof(h_unresolved) == E.HoverInfo)
assert(h_unresolved.value:match("unresolved binding"))

Hover.hover_phase:reset()
pvm.drain(Hover.hover_phase(query_at("User"), analysis))
pvm.drain(Hover.hover_phase(query_at("User"), analysis))
local report = pvm.report({ Hover.hover_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift editor hover ok")
