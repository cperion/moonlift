package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)

local expr_frag = P.parse_expr_frag [[
expr id<T>(x: T) -> T
    x
end
]]
assert(#expr_frag.issues > 0, "source expr generics must stay rejected; use Lua hosted values/templates")

local region_frag = P.parse_region_frag [[
region route<T>(x: T; out: cont(v: T))
entry start()
    jump out(v = x)
end
end
]]
assert(#region_frag.issues > 0, "source region generics must stay rejected; use Lua hosted values/templates")

local parsed = P.parse_module [[
export func f(x: i32) -> i32
    return emit id<i32>(x)
end
]]
assert(#parsed.issues > 0, "source generic instantiation must stay rejected; use Lua hosted values/templates")

print("moonlift host source no generics ok")
