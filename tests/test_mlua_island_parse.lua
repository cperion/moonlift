package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local IslandParseMod = require("moonlift.mlua_island_parse")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local Mlua = T.MoonMlua
local H = T.MoonHost
local O = T.MoonOpen
local IslandParse = IslandParseMod.Define(T)

local function island(kind, name, src)
    return Mlua.IslandText(kind, name and Mlua.IslandNamed(name) or Mlua.IslandAnonymous, S.SourceSlice(src))
end

local struct_parse = IslandParse.parse(island(Mlua.IslandStruct, "User", "struct User\n  id: i32\n  active: bool32\nend"))
assert(pvm.classof(struct_parse) == Mlua.IslandParse)
assert(#struct_parse.decls.decls == 1)
assert(pvm.classof(struct_parse.decls.decls[1]) == H.HostDeclStruct)
assert(#struct_parse.module.items == 1)
assert(#struct_parse.issues == 0)
local saw_field = false
for i = 1, #struct_parse.anchors.anchors do
    if struct_parse.anchors.anchors[i].kind == S.AnchorFieldName and struct_parse.anchors.anchors[i].label == "id" then saw_field = true end
end
assert(saw_field)

local expose_parse = IslandParse.parse(island(Mlua.IslandExpose, "Users", "expose Users: view(User)"))
assert(#expose_parse.decls.decls == 1)
assert(pvm.classof(expose_parse.decls.decls[1]) == H.HostDeclExpose)

local func_parse = IslandParse.parse(island(Mlua.IslandFunc, "User:is_active", "func User:is_active(self: ptr(User)) -> bool\n  return true\nend"))
assert(#func_parse.decls.decls == 1)
assert(pvm.classof(func_parse.decls.decls[1].decl) == H.HostAccessorMoonlift)
assert(#func_parse.module.items == 1)

local module_parse = IslandParse.parse(island(Mlua.IslandModule, nil, "module\n  export func one() -> i32\n    return 1\n  end\nend"))
assert(#module_parse.module.items == 1)

local region_parse = IslandParse.parse(island(Mlua.IslandRegion, "Done", [[region Done(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end]]))
assert(#region_parse.region_frags == 1)
assert(pvm.classof(region_parse.region_frags[1]) == O.RegionFrag)

local expr_parse = IslandParse.parse(island(Mlua.IslandExpr, "FortyTwo", [[expr FortyTwo() -> i32
    42
end]]))
assert(#expr_parse.expr_frags == 1)
assert(pvm.classof(expr_parse.expr_frags[1]) == O.ExprFrag)

local bad = IslandParse.parse(island(Mlua.IslandExpr, "Bad", [[expr Bad() -> i32
    @
end]]))
assert(#bad.issues >= 1)
assert(bad.issues[1].message:match("expected expression"))

IslandParse.island_parse_phase:reset()
local stable = island(Mlua.IslandStruct, "Stable", "struct Stable\n  id: i32\nend")
pvm.drain(IslandParse.island_parse_phase(stable))
pvm.drain(IslandParse.island_parse_phase(stable))
local report = pvm.report({ IslandParse.island_parse_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift mlua island parse ok")
