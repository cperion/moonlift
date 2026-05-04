package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local MluaParse = require("moonlift.mlua_parse")

local T = pvm.context(); A.Define(T)
local MP = MluaParse.Define(T)
local H = T.MoonHost

local moon_method = MP.parse([[func User:is_active(self: ptr(User)) -> bool
    return true
end]])
assert(#moon_method.issues == 0, tostring(moon_method.issues[1]))
assert(#moon_method.decls.decls == 1)
assert(pvm.classof(moon_method.decls.decls[1].decl) == H.HostAccessorMoonlift)
assert(moon_method.decls.decls[1].decl.owner_name == "User")
assert(moon_method.decls.decls[1].decl.name == "is_active")
assert(#moon_method.module.items == 1)
assert(moon_method.module.items[1].func.name == "User_is_active")

print("moonlift mlua method syntax ok")
