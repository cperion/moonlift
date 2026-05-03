package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local DocMod = require("moonlift.mlua_document")
local MluaParse = require("moonlift.mlua_parse")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local Mlua = T.MoonMlua
local H = T.MoonHost
local O = T.MoonOpen
local Parts = DocMod.Define(T)
local DocParse = Parts
local Whole = MluaParse.Define(T)

local uri = S.DocUri("file:///doc_parse.mlua")
local src = [[
local lua_value = 1
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
export func first(xs: ptr(i32), n: index) -> i32
    return 0
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local parts = Parts.document_parts(doc)
local parsed = DocParse.document_parse(parts)
assert(pvm.classof(parsed) == Mlua.DocumentParse)
assert(#parsed.islands == 6)
assert(#parsed.combined.issues == 0)
assert(#parsed.combined.decls.decls == 3) -- struct, expose, Moonlift method accessor
assert(#parsed.combined.module.items == 3) -- struct type item, method func, top-level func
assert(#parsed.combined.region_frags == 1)
assert(#parsed.combined.expr_frags == 1)
assert(pvm.classof(parsed.combined.decls.decls[1]) == H.HostDeclStruct)
assert(pvm.classof(parsed.combined.region_frags[1]) == O.RegionFrag)
assert(pvm.classof(parsed.combined.expr_frags[1]) == O.ExprFrag)

local whole = Whole.parse(src, "doc_parse.mlua")
assert(#whole.issues == #parsed.combined.issues)
assert(#whole.decls.decls == #parsed.combined.decls.decls)
assert(#whole.module.items == #parsed.combined.module.items)
assert(#whole.region_frags == #parsed.combined.region_frags)
assert(#whole.expr_frags == #parsed.combined.expr_frags)
for i = 1, #whole.decls.decls do
    assert(whole.decls.decls[i] == parsed.combined.decls.decls[i])
end
for i = 1, #whole.module.items do
    if whole.module.items[i].func then
        assert(whole.module.items[i].func.name == parsed.combined.module.items[i].func.name)
    end
end

local saw_remapped_field = false
for i = 1, #parsed.anchors.anchors do
    local a = parsed.anchors.anchors[i]
    if a.kind == S.AnchorFieldName and a.label == "id" and a.range.uri == uri then
        saw_remapped_field = true
    end
end
assert(saw_remapped_field)

local bad_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, "local x=1\nexpr Bad() -> i32\n @\nend\n")
local bad = DocParse.parse_document(bad_doc)
assert(#bad.combined.issues >= 1)
assert(bad.combined.issues[1].offset > 1)
assert(bad.combined.issues[1].line >= 2)

local malformed_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, "local x=1\nstruct Broken\n  id: i32\n")
local malformed = DocParse.parse_document(malformed_doc)
assert(#malformed.combined.issues == 1)
assert(malformed.combined.issues[1].message:match("unterminated"))

local old_expose_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, "struct User\n  id: i32\n  active: bool32\nend\nexpose view(User) as Users\n")
local old_expose = DocParse.parse_document(old_expose_doc)
assert(#old_expose.combined.issues >= 1)
assert(old_expose.combined.issues[1].message:match("expected expose Name: subject"))

print("moonlift mlua document parse ok")
