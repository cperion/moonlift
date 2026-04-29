package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local PositionIndex = require("moonlift.source_position_index")
local AnchorIndex = require("moonlift.source_anchor_index")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local P = PositionIndex.Define(T)
local AIndex = AnchorIndex.Define(T)

local uri = S.DocUri("file:///anchors.mlua")
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, "struct User { id: i32 }")
local idx = P.build_index(doc)
local function range(a, b)
    return assert(P.range_from_offsets(idx, a, b))
end
local function anchor(id, kind, label, a, b)
    return S.AnchorSpan(S.AnchorId(id), kind, label, range(a, b))
end

local island = anchor("island.struct.User", S.AnchorHostedIsland, "struct User", 0, #doc.text)
local keyword = anchor("kw.struct", S.AnchorKeyword, "struct", 0, 6)
local name = anchor("struct.User", S.AnchorStructName, "User", 7, 11)
local field = anchor("field.User.id", S.AnchorFieldName, "id", 14, 16)
local ty = anchor("type.i32", S.AnchorScalarType, "i32", 18, 21)
local diag = anchor("diag.test", S.AnchorDiagnostic, "diagnostic", 14, 21)
local set = S.AnchorSet({ island, keyword, name, field, ty, diag })
local built = AIndex.build_index(set)
assert(#built.anchors == 6)

local by_id = AIndex.lookup_by_id(built, S.AnchorId("field.User.id"))
assert(#by_id.anchors == 1)
assert(by_id.anchors[1] == field)

local at_field = AIndex.lookup_by_position(built, uri, 15)
assert(#at_field.anchors >= 3)
assert(at_field.anchors[1] == field)
assert(at_field.anchors[2] == diag)

local at_type = AIndex.lookup_by_position(built, uri, 19)
assert(at_type.anchors[1] == ty)

local in_keyword = AIndex.lookup_by_position(built, uri, 1)
assert(in_keyword.anchors[1] == keyword)
assert(in_keyword.anchors[#in_keyword.anchors] == island)

local by_range = AIndex.lookup_by_range(built, range(13, 22))
local saw_field, saw_type, saw_diag = false, false, false
for i = 1, #by_range.anchors do
    if by_range.anchors[i] == field then saw_field = true end
    if by_range.anchors[i] == ty then saw_type = true end
    if by_range.anchors[i] == diag then saw_diag = true end
end
assert(saw_field and saw_type and saw_diag)

local wrong = AIndex.lookup_by_position(built, S.DocUri("file:///other.mlua"), 15)
assert(#wrong.anchors == 0)

local func_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, "func add(x: i32) -> i32 { }")
local func_idx = P.build_index(func_doc)
local function func_range(a, b) return assert(P.range_from_offsets(func_idx, a, b)) end
local func_set = S.AnchorSet({
    S.AnchorSpan(S.AnchorId("island.func.add"), S.AnchorHostedIsland, "func add", func_range(0, #func_doc.text)),
    S.AnchorSpan(S.AnchorId("func.add"), S.AnchorFunctionName, "add", func_range(5, 8)),
    S.AnchorSpan(S.AnchorId("param.add.x"), S.AnchorParamName, "x", func_range(9, 10)),
})
local func_built = AIndex.build_index(func_set)
local at_param = AIndex.lookup_by_position(func_built, uri, 9)
assert(at_param.anchors[1].id == S.AnchorId("param.add.x"))
assert(at_param.anchors[#at_param.anchors].id == S.AnchorId("island.func.add"))

local expose_text = "expose Users: view(User) lua"
local expose_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, expose_text)
local expose_idx = P.build_index(expose_doc)
local function expose_range(a, b) return assert(P.range_from_offsets(expose_idx, a, b)) end
local expose_set = S.AnchorSet({
    S.AnchorSpan(S.AnchorId("island.expose.Users"), S.AnchorHostedIsland, "expose Users", expose_range(0, #expose_text)),
    S.AnchorSpan(S.AnchorId("expose.Users"), S.AnchorExposeName, "Users", expose_range(7, 12)),
    S.AnchorSpan(S.AnchorId("target.lua"), S.AnchorKeyword, "lua", expose_range(25, 28)),
})
local expose_built = AIndex.build_index(expose_set)
assert(AIndex.lookup_by_position(expose_built, uri, 26).anchors[1].id == S.AnchorId("target.lua"))

print("moonlift source anchor index ok")
