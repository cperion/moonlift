package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift.host")

local M = moon.module("HostExternSymbol")
M:extern_func("host_add7", { {name="x", type=moon.i32} }, moon.i32)
M:export_func("call_add7", { {name="x", type=moon.i32} }, moon.i32, function(f)
    f:return_(moon.expr[[host_add7(x)]])
end)

local cb = ffi.cast("int32_t (*)(int32_t)", function(x) return x + 7 end)
M:symbol("host_add7", cb)
local compiled = M:compile()
local call_add7 = compiled:get("call_add7")
assert(call_add7(35) == 42)
compiled:free()
cb:free()

print("moonlift host_extern_symbol ok")
