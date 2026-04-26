package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift.host")

ffi.cdef[[ typedef struct { int32_t x; int32_t y; } host_pair_i32; ]]

local M = moon.module("HostFieldJit")
local Pair = M:struct("Pair", { moon.field("x", moon.i32), moon.field("y", moon.i32) })

M:export_func("set_y", { moon.param("p", moon.ptr(Pair)), moon.param("v", moon.i32) }, moon.i32, function(fn)
    local p = fn:param("p")
    local y_place = p:deref_place():field("y")
    fn:set(y_place, fn:param("v"))
    fn:return_(moon.load(moon.addr_of(y_place), moon.i32))
end)

local compiled = M:compile()
local pair = ffi.new("host_pair_i32[1]")
pair[0].x = 11
pair[0].y = 22
assert(compiled:get("set_y")(pair, 77) == 77)
assert(pair[0].x == 11)
assert(pair[0].y == 77)
compiled:free()

print("moonlift host field jit ok")
