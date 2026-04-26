package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local Host = require("moonlift.host_quote")

local f = Host.eval [[
local moon = require("moonlift.host")
return func id_host_type(x: @{moon.i32}) -> @{moon.i32}
    return x
end
]]

local compiled = f:compile()
assert(compiled(123) == 123)
compiled:free()

print("moonlift host quote value splice ok")
