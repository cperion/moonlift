package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local PartsMod = require("moonlift.mlua_document_parts")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local Mlua = T.MoonMlua
local Parts = PartsMod.Define(T)

local uri = S.DocUri("file:///parts.mlua")
local function doc(text)
    return S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, text)
end

local src = [[
local staging_value = "struct NotIsland { x: i32 }"
-- expose Hidden: view(User)
struct User
    id: i32
end
expose Users: view(User)
func User:is_active(self: ptr(User)) -> bool
    return true
end
module Math
    export func one() -> i32
        return 1
    end
end
region Done(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
expr FortyTwo() -> i32
    return 42
end
]]

local parts = Parts.document_parts(doc(src))
assert(pvm.classof(parts) == Mlua.DocumentParts)
assert(parts.document.text == src)

local hosted = {}
local lua_segments = 0
for i = 1, #parts.segments do
    local seg = parts.segments[i]
    if pvm.classof(seg) == Mlua.HostedIsland then
        hosted[#hosted + 1] = seg
    elseif pvm.classof(seg) == Mlua.LuaOpaque then
        lua_segments = lua_segments + 1
    else
        error("unexpected segment " .. tostring(pvm.classof(seg)))
    end
end
assert(lua_segments >= 1)
assert(#hosted == 6)
assert(hosted[1].island.kind == Mlua.IslandStruct)
assert(hosted[2].island.kind == Mlua.IslandExpose)
assert(hosted[3].island.kind == Mlua.IslandFunc)
assert(hosted[4].island.kind == Mlua.IslandModule)
assert(hosted[5].island.kind == Mlua.IslandRegion)
assert(hosted[6].island.kind == Mlua.IslandExpr)
assert(pvm.classof(hosted[1].island.name) == Mlua.IslandNamed and hosted[1].island.name.name == "User")
assert(pvm.classof(hosted[2].island.name) == Mlua.IslandNamed and hosted[2].island.name.name == "Users")
assert(hosted[1].island.source.text:match("^struct User"))
assert(pvm.classof(hosted[3].island.name) == Mlua.IslandNamed and hosted[3].island.name.name == "User:is_active")
assert(hosted[3].island.source.text:match("User:is_active"))

local saw_keyword, saw_name, saw_body = false, false, false
for i = 1, #parts.anchors.anchors do
    local a = parts.anchors.anchors[i]
    if a.kind == S.AnchorKeyword and a.label == "struct" then saw_keyword = true end
    if a.kind == S.AnchorStructName and a.label == "User" then saw_name = true end
    if a.kind == S.AnchorIslandBody and a.label == "struct body" then saw_body = true end
end
assert(saw_keyword and saw_name and saw_body)

local ignored = Parts.document_parts(doc("local s = [[\nstruct Ignored { x: i32 }\n]]\n--[[\nfunc ignored() -> i32 { return 0 }\n]]\n"))
local ignored_hosted = 0
for i = 1, #ignored.segments do
    if pvm.classof(ignored.segments[i]) == Mlua.HostedIsland then ignored_hosted = ignored_hosted + 1 end
end
assert(ignored_hosted == 0)

local nested = Parts.document_parts(doc("func nested() -> i32\n    if x then\n        return 1\n    end\n    return 0\nend"))
local nested_hosted = 0
for i = 1, #nested.segments do
    if pvm.classof(nested.segments[i]) == Mlua.HostedIsland then nested_hosted = nested_hosted + 1 end
    assert(pvm.classof(nested.segments[i]) ~= Mlua.MalformedIsland)
end
assert(nested_hosted == 1)

local exported = Parts.document_parts(doc("export func public_add(x: i32) -> i32\n    return x + 1\nend\n"))
local exported_island
for i = 1, #exported.segments do
    if pvm.classof(exported.segments[i]) == Mlua.HostedIsland then exported_island = exported.segments[i].island end
end
assert(exported_island and exported_island.kind == Mlua.IslandFunc)
assert(exported_island.source.text:match("^export%s+func%s+public_add"))
assert(pvm.classof(exported_island.name) == Mlua.IslandNamed and exported_island.name.name == "public_add")

local module_local = Parts.document_parts(doc("module\nregion Inner(done: cont())\nentry start()\n    jump done()\nend\nend\nend\n"))
local module_island
for i = 1, #module_local.segments do
    if pvm.classof(module_local.segments[i]) == Mlua.HostedIsland then module_island = module_local.segments[i].island end
end
assert(module_island and module_island.kind == Mlua.IslandModule)
assert(module_island.source.text:match("region Inner"))

local malformed = Parts.document_parts(doc("local x = 1\nstruct Broken\n  id: i32\n"))
assert(#malformed.segments == 2)
assert(pvm.classof(malformed.segments[2]) == Mlua.MalformedIsland)
assert(malformed.segments[2].reason:match("unterminated"))
local saw_diag = false
for i = 1, #malformed.anchors.anchors do
    if malformed.anchors.anchors[i].kind == S.AnchorDiagnostic then saw_diag = true end
end
assert(saw_diag)

local moved_a = Parts.document_parts(doc("local a = 1\nstruct Stable\n  id: i32\nend\n"))
local moved_b = Parts.document_parts(doc("local a = 1\nlocal b = 2\nstruct Stable\n  id: i32\nend\n"))
local island_a, island_b
for i = 1, #moved_a.segments do
    if pvm.classof(moved_a.segments[i]) == Mlua.HostedIsland then island_a = moved_a.segments[i].island end
end
for i = 1, #moved_b.segments do
    if pvm.classof(moved_b.segments[i]) == Mlua.HostedIsland then island_b = moved_b.segments[i].island end
end
assert(island_a == island_b)

print("moonlift mlua document parts ok")
