package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local moon = require "moonlift"
local func = moon.func

local f = func {T = moon.i32}
"(a: @{T}, b: @{T}): @{T}"
[[
    return a + b
]]

print(f(2,3))

