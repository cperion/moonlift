package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local f = Host.eval [[
return func classify(x: i32): i32
    var y: i32 = 1
    switch x do
    case 1 then y = 10
    case 2 then y = 20
    default then y = 30
    end
    return y
end
]]

local c = f:compile()
assert(c(1) == 10)
assert(c(2) == 20)
assert(c(3) == 30)
c:free()

print("moonlift switch stmt lowering ok")
