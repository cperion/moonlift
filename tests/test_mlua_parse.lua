package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local MluaParse = require("moonlift.mlua_parse")
local HostDeclParse = require("moonlift.host_decl_parse")
local HostDeclValidate = require("moonlift.host_decl_validate")
local HostLayoutResolve = require("moonlift.host_layout_resolve")
local MluaRegionTypecheck = require("moonlift.mlua_region_typecheck")
local MluaLoopExpand = require("moonlift.mlua_loop_expand")

local T = pvm.context()
A.Define(T)
local MP = MluaParse.Define(T)
local HDP = HostDeclParse.Define(T)
local HDV = HostDeclValidate.Define(T)
local HLR = HostLayoutResolve.Define(T)
local RTC = MluaRegionTypecheck.Define(T)
local Loop = MluaLoopExpand.Define(T)
local H = T.MoonHost
local Ty = T.MoonType
local C = T.MoonCore
local Tr = T.MoonTree
local O = T.MoonOpen

local src = [[
local staging_value = 17

struct User
    id: i32
    age: i32
    active: bool32
end

expose Users: view(User)

function User:is_adult()
    return self.age >= 18
end

func User:is_active(self: ptr(User)) -> bool
    return true
end

region DoneCounter(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end

export func first(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n)
    if len(v) <= 0 then
        return 0
    end
    return v[0]
end

export func sum(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(v) then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end
]]

local result = MP.parse(src, "test.mlua")
assert(pvm.classof(result) == H.MluaParseResult)
assert(#result.issues == 0, tostring(result.issues[1]))
assert(pvm.classof(result.decls) == H.HostDeclSet)
assert(#result.decls.decls == 3)
assert(#result.module.items == 4) -- struct type item, moonlift method func, plus two funcs
assert(#result.region_frags == 1)

local decls = HDP.parse(result)
assert(decls == result.decls)
local report = HDV.validate(decls)
assert(#report.issues == 0, tostring(report.issues[1]))

local struct_decl = result.decls.decls[1].decl
local manual_struct = H.HostStructDecl(
    H.HostLayoutId("mlua.User", "User"),
    "User",
    H.HostReprC,
    {
        H.HostFieldDecl(H.HostFieldId("mlua.User.id", "id"), "id", Ty.TScalar(C.ScalarI32), H.HostStorageSame, {}),
        H.HostFieldDecl(H.HostFieldId("mlua.User.age", "age"), "age", Ty.TScalar(C.ScalarI32), H.HostStorageSame, {}),
        H.HostFieldDecl(H.HostFieldId("mlua.User.active", "active"), "active", Ty.TScalar(C.ScalarBool), H.HostStorageBool(H.HostBoolI32, C.ScalarI32), {}),
    }
)
assert(struct_decl == manual_struct)

local layout = HLR.resolve_layout(struct_decl)
assert(layout.name == "User")
assert(#layout.fields == 3)
assert(layout.fields[3].name == "active")
assert(pvm.classof(layout.fields[3].rep) == H.HostRepBool)

local expose = result.decls.decls[2].decl
assert(pvm.classof(expose.subject) == H.HostExposeView)
assert(expose.public_name == "Users")
assert(#expose.facets == 3)
assert(expose.facets[1].target == H.HostExposeLua)
assert(expose.facets[1].abi == H.HostExposeAbiDefault)
assert(expose.facets[1].mode.kind == H.HostProxyView)
assert(expose.facets[1].mode.mutability == H.HostReadonly)
assert(expose.facets[1].mode.bounds == H.HostBoundsChecked)
assert(expose.facets[2].target == H.HostExposeTerra)
assert(expose.facets[2].abi == H.HostExposeAbiDescriptor)
assert(expose.facets[2].mode.bounds == H.HostBoundsUnchecked)
assert(expose.facets[3].target == H.HostExposeC)
assert(expose.facets[3].abi == H.HostExposeAbiDescriptor)
assert(expose.facets[3].mode.bounds == H.HostBoundsUnchecked)

local explicit_targets = MP.parse("struct User\n  id: i32\n  active: bool32\nend\nexpose Users: view(User)\n  lua\n  c\nend\n", "explicit_targets.mlua")
assert(#explicit_targets.issues == 0, explicit_targets.issues[1] and explicit_targets.issues[1].message)
assert(#explicit_targets.decls.decls[2].decl.facets == 2)
assert(explicit_targets.decls.decls[2].decl.facets[2].target == H.HostExposeC)

local old_expose = MP.parse("struct User\n  id: i32\n  active: bool32\nend\nexpose view(User) as Users\n", "old_expose.mlua")
assert(#old_expose.issues >= 1)
assert(old_expose.issues[1].message:match("expected expose Name: subject"))

local braced_expose = MP.parse("struct User\n  id: i32\n  active: bool32\nend\nexpose Users: view(User) { lua }\n", "braced_expose.mlua")
assert(#braced_expose.issues >= 1)
assert(braced_expose.issues[1].message:match("expose uses keyword...end, not braces"))

local braced_struct = MP.parse("struct User { id: i32 }\n", "braced_struct.mlua")
assert(#braced_struct.issues >= 1)
assert(braced_struct.issues[1].message:match("unterminated .mlua form: struct"))

local braced_func = MP.parse("func bad() -> i32 { return 0 }\n", "braced_func.mlua")
assert(#braced_func.issues >= 1)
assert(braced_func.issues[1].message:match("unterminated .mlua form: func"))

local native_method = result.decls.decls[3].decl
assert(pvm.classof(native_method) == H.HostAccessorMoonlift)
assert(native_method.owner_name == "User")
assert(native_method.name == "is_active")
assert(native_method.func.name == "User_is_active")

local region_check = RTC.check(result.region_frags[1])
assert(pvm.classof(region_check) == H.MluaRegionTypeResult)
assert(pvm.classof(region_check.frag) == O.RegionFrag)
assert(#region_check.issues == 0)

local sum_func = result.module.items[4].func
local ret = sum_func.body[2]
assert(pvm.classof(ret.value) == Tr.ExprControl)
local loop = Loop.expand(H.MluaLoopControlExpr(ret.value.region))
assert(pvm.classof(loop) == H.MluaLoopExpandResult)
assert(loop.entry.label.name == "loop")
assert(#loop.blocks == 0)
assert(#loop.issues == 0)

print("moonlift mlua_parse ok")
