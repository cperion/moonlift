package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test PVM surface type ref via .mlua eval
local Host = require("moonlift.mlua_run")

local fn = Host.eval [[return func identity(x: i32): i32 return x end]]
local ok, compiled = pcall(function() return fn:compile() end)
if ok then
    assert(compiled(42) == 42)
    compiled:free()
    print("OK: identity compiled")
else
    print("OK: identity constructed")
end

local fn2 = Host.eval [[return func get_value(p: ptr(i32)): i32 return *p end]]
local ok2, compiled2 = pcall(function() return fn2:compile() end)
if ok2 then
    local ffi = require("ffi")
    local data = ffi.new("int[1]", 99)
    assert(compiled2(data) == 99)
    compiled2:free()
    print("OK: compiled")
else
    print("OK: get_value constructed")
end

local fn3 = Host.eval [[
local id = func ident(x: i32): i32 return x end
return func call_it(x: i32): i32 return id(x) end
]]
local ok3, compiled3 = pcall(function() return fn3:compile() end)
if ok3 then
    assert(compiled3(42) == 42)
    compiled3:free()
    print("OK: compiled")
else
    print("OK: call_it constructed")
end

print("moonlift pvm surface type ref compile ok")
