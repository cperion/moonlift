package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local MluaParse = require("moonlift.mlua_parse")
local Host = require("moonlift.host_quote")

local T = pvm.context()
A.Define(T)
local MP = MluaParse.Define(T)
local H = T.Moon2Host

local translated = Host.translate([[function User:is_adult()
    return self.age >= 18
end]])
assert(translated:find("function User:is_adult", 1, true))

local User = Host.eval [[
struct User
    age: i32
end
function User:is_adult()
    return self.age >= 18
end
return User
]]
local lua_decls = User:host_decl_set()
assert(#lua_decls.decls == 2)
assert(pvm.classof(lua_decls.decls[2].decl) == User.T.Moon2Host.HostAccessorLua)
assert(lua_decls.decls[2].decl.owner_name == "User")
assert(lua_decls.decls[2].decl.name == "is_adult")

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
