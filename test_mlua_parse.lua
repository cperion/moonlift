package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

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
local H = T.Moon2Host
local Ty = T.Moon2Type
local C = T.Moon2Core
local Tr = T.Moon2Tree
local O = T.Moon2Open

local src = [[
local staging_value = 17

struct User {
    id: i32
    age: i32
    active: bool32
}

expose view(User) as Users {
    lua readonly checked
    terra
    c
}

function User:is_adult()
    return self.age >= 18
end

func User:is_active(self: ptr(User)) -> bool {
    return true
}

region DoneCounter(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end

export func first(xs: ptr(i32), n: index) -> i32 {
    let v: view(i32) = view(xs, n)
    if len(v) <= 0 then
        return 0
    end
    return v[0]
}

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
assert(#expose.targets == 3)
assert(expose.mode.kind == H.HostProxyView)
assert(expose.mode.mutability == H.HostReadonly)
assert(expose.mode.bounds == H.HostBoundsChecked)

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
