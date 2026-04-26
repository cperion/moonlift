package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift.host")

local M = moon.module("HostAddrLoadJit")
M:export_func("load_i32", { moon.param("p", moon.ptr(moon.i32)) }, moon.i32, function(fn)
    return moon.load(fn:param("p"), moon.i32)
end)
M:export_func("store_then_load", { moon.param("p", moon.ptr(moon.i32)), moon.param("v", moon.i32) }, moon.i32, function(fn)
    local p = fn:param("p")
    local v = fn:param("v")
    fn:set(p:index_place(0), v)
    fn:return_(moon.load(p, moon.i32))
end)

local compiled = M:compile()
local buf = ffi.new("int32_t[1]", 17)
assert(compiled:get("load_i32")(buf) == 17)
assert(compiled:get("store_then_load")(buf, 99) == 99)
assert(buf[0] == 99)
compiled:free()

print("moonlift host addr/load jit ok")
