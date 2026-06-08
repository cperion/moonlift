package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local addr_var = Host.eval [[
return func addr_var(v: i32): i32
    var x: i32 = v
    let p: ptr(i32) = &x
    p[0] = v + 1
    return x
end
]]

local compiled = addr_var:compile()
assert(compiled(41) == 42)
assert(compiled(-2) == -1)
compiled:free()

print("moonlift addr_of_var_stack ok")
