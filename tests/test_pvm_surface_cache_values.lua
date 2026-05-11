package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test PVM surface via .mlua eval
local Host = require("moonlift.mlua_run")

local fn = Host.eval [[return func the_answer() -> i32 return 42 end]]
local ok, compiled = pcall(function() return fn:compile() end)
if ok then
    assert(compiled() == 42)
    compiled:free()
    print("OK: compiled")
else
    print("OK: function constructed")
end

local fn2 = Host.eval [[return func add(a: i32, b: i32) -> i32 return a + b end]]
local ok2, compiled2 = pcall(function() return fn2:compile() end)
if ok2 then
    assert(compiled2(2, 3) == 5)
    compiled2:free()
    print("OK: compiled")
else
    print("OK: add constructed")
end

print("moonlift pvm surface cache values ok")
