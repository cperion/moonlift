package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local dep = moon.func [[dep(x: i32): i32 return x + 1 end]]
local header = moon.func [[main(x: i32): i32]]
local main = header{ dep = dep }[[
    return @{dep}(x)
]]

local compiled = main:compile()
assert(compiled(41) == 42)
compiled:free()

return "func header body splice ok"
