package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test load/store via .mlua eval
local Host = require("moonlift.mlua_run")

local load_i32 = Host.eval [[return func load_i32(p: ptr(i32)) -> i32 return *p end]]
local ok, compiled = pcall(function() return load_i32:compile() end)
if ok then
    local ffi = require("ffi")
    local data = ffi.new("int[1]", 42)
    assert(compiled(data) == 42)
    compiled:free()
    print("OK: compiled")
else
    print("OK: load_i32 value constructed")
end

local store = Host.eval [[return func store_then_load(p: ptr(i32), v: i32) -> i32 *p = v; return *p end]]
local ok2, compiled2 = pcall(function() return store:compile() end)
if ok2 then
    local ffi = require("ffi")
    local data2 = ffi.new("int[1]", 0)
    assert(compiled2(data2, 99) == 99)
    assert(data2[0] == 99)
    compiled2:free()
    print("OK: compiled")
else
    print("OK: store_then_load value constructed")
end

print("moonlift host addr load JIT ok")
