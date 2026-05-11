package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test splice with the session's moon API
local Host = require("moonlift.mlua_run")

local f = Host.eval [[
local T = moon.i32
return func id_host_type(x: @{T}) -> @{T}
    return x
end
]]
assert(f.name == "id_host_type")
assert(f.kind == "func")

local ok, compiled = pcall(function() return f:compile() end)
if ok then
    assert(compiled(123) == 123)
    compiled:free()
    print("OK: compiled")
else
    print("OK: splice value constructed")
end

print("moonlift host quote value splice ok")
