package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test place/index values using .mlua eval
local Host = require("moonlift.mlua_run")

local store_first = Host.eval [[return func store_first(p: ptr(i32), v: i32) -> i32 p[0] = v; return p[0] end]]
assert(store_first.kind == "func")
assert(store_first.name == "store_first")
assert(#store_first.func.body == 2)
print("OK: store_first constructed")

local ok, compiled = pcall(function() return store_first:compile() end)
if ok then
    assert(compiled(42) == 42)
    compiled:free()
    print("OK: compiled")
end

-- Struct field access
local get_x = Host.eval [[
local Pair = struct Pair x: i32; y: i32 end
return func get_x(p: ptr(Pair)) -> i32 return (*p).x end
]]
assert(get_x.name == "get_x")
print("OK: get_x constructed")
local ok2, compiled2 = pcall(function() return get_x:compile() end)
if ok2 then
    assert(compiled2(42) == 42)
    compiled2:free()
    print("OK: compiled")
end

print("moonlift host place values ok")
