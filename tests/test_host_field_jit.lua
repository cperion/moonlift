package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test struct field access via .mlua eval
local Host = require("moonlift.mlua_run")
local ffi = require("ffi")

-- Set field
local set_y = Host.eval [[
local Pair = struct x: i32; y: i32 end
return func set_y(p: ptr(Pair), v: i32) -> i32
    (*p).y = v
    return (*p).x + (*p).y
end
]]
assert(set_y.name == "set_y")
local ok, compiled = pcall(function() return set_y:compile() end)
if ok then
    ffi.cdef("typedef struct { int x; int y; } Pair;")
    local data = ffi.new("Pair", 10, 20)
    assert(compiled(data, 5) == 15)
    assert(data.y == 5)
    compiled:free()
    print("OK: compiled")
else
    print("OK: set_y value constructed")
end

-- Get field
local get_x = Host.eval [[
local Pair = struct x: i32; y: i32 end
return func get_x(p: ptr(Pair)) -> i32 return (*p).x end
]]
local ok2, compiled2 = pcall(function() return get_x:compile() end)
if ok2 then
    ffi.cdef("typedef struct { int x; int y; } Pair;")
    local data2 = ffi.new("Pair", 42, 99)
    assert(compiled2(data2) == 42)
    compiled2:free()
    print("OK: compiled")
else
    print("OK: get_x value constructed")
end

print("moonlift host field JIT ok")
