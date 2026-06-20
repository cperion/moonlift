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
    id: i32,
    active: bool32,
end
expose Users: view(User)
extern touch(x: i32): i32 end
func User:is_active(self: ptr(User)): bool
    return true
end
region Done(n: i32; done(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
expr FortyTwo(): i32
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

local function assert_visual_split(hover)
    assert(hover.value:match("```moonlift\n.-\n```\n\n%-%-%-\n"))
end

local h_struct = Hover.hover(query_at("User"), analysis)
assert(pvm.classof(h_struct) == E.HoverInfo)
assert_visual_split(h_struct)
assert(h_struct.value:match("Host Struct"))
assert(h_struct.value:match("Layout: size"))
assert(h_struct.value:match("```moonlift"))
assert(not h_struct.value:match("storage"))
assert(h_struct.value:match("id:%s+i32%s+%-%- offset"))

local h_field = Hover.hover(query_at("id"), analysis)
assert(h_field.value:match("User%.id: i32"))
assert(h_field.value:match("host field"))
assert(h_field.value:match("layout: offset"))

local h_scalar = Hover.hover(query_at("i32"), analysis)
assert_visual_split(h_scalar)
assert(h_scalar.value:match("scalar"))
assert(h_scalar.value:match("i32"))

local h_expose = Hover.hover(query_at("Users"), analysis)
assert(h_expose.value:match("host expose"))

local h_method = Hover.hover(query_at("User:is_active"), analysis)
assert(h_method.value:match("accessor") or h_method.value:match("function"))

local h_extern = Hover.hover(query_at("touch"), analysis)
assert(h_extern.value:match("extern touch"))
assert(h_extern.value:match("imported C/host function"))

local h_region = Hover.hover(query_at("Done"), analysis)
assert(h_region.value:match("region fragment"))
assert(h_region.value:match("done%(total: i32%)"))

local h_expr = Hover.hover(query_at("FortyTwo"), analysis)
assert(h_expr.value:match("expr fragment"))
assert(h_expr.value:match("FortyTwo%(%)"))

local assigned_src = [[
local T = {}
T.ViewName = struct
    data: ptr(u8),
    len: index,
end
T.ViewAttrSpec = struct
    value: T.ViewName,
end
]]
local assigned_doc = S.DocumentSnapshot(uri, S.DocVersion(3), S.LangMlua, assigned_src)
local assigned_analysis = Analysis.analyze_document(assigned_doc)
local assigned_idx = P.build_index(assigned_doc)
local function assigned_query_at_nth(text, nth)
    local start = 1
    local s
    for _ = 1, nth do
        s = assert(assigned_src:find(text, start, true))
        start = s + #text
    end
    return E.PositionQuery(uri, S.DocVersion(3), P.offset_to_pos(assigned_idx, s - 1).pos)
end
local h_assigned_struct = Hover.hover(assigned_query_at_nth("ViewName", 1), assigned_analysis)
assert(pvm.classof(h_assigned_struct) == E.HoverInfo)
assert(h_assigned_struct.value:match("struct ViewName"))
assert(h_assigned_struct.value:match("data:%s+ptr%(u8%)%s+%-%- offset"))
local h_assigned_use = Hover.hover(assigned_query_at_nth("ViewName", 2), assigned_analysis)
assert(pvm.classof(h_assigned_use) == E.HoverInfo)
assert(h_assigned_use.value:match("struct ViewName"))
assert(h_assigned_use.value:match("len:%s+index%s+%-%- offset"))

local unresolved_src = "func unresolved(): i32\n    return missing + 1\nend\n"
local unresolved_doc = S.DocumentSnapshot(uri, S.DocVersion(2), S.LangMlua, unresolved_src)
local unresolved_analysis = Analysis.analyze_document(unresolved_doc)
local unresolved_idx = P.build_index(unresolved_doc)
local missing_offset = unresolved_src:find("missing", 1, true) - 1
local h_unresolved = Hover.hover(E.PositionQuery(uri, S.DocVersion(2), P.offset_to_pos(unresolved_idx, missing_offset).pos), unresolved_analysis)
assert(pvm.classof(h_unresolved) == E.HoverInfo)
assert(h_unresolved.value:match("unresolved binding"))

Hover.hover_phase:reset()
local user_query = query_at("User")
pvm.drain(Hover.hover_phase(user_query, analysis))
pvm.drain(Hover.hover_phase(user_query, analysis))
local report = pvm.report({ Hover.hover_phase })[1]
assert(report.calls == 2 and report.hits == 0)

print("moonlift editor hover ok")
