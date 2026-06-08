package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

local M = Host.eval [[
local strlen = extern strlen(s: ptr(u8)): index end
local add7 = extern add7(x: i32): i32 as "host_add7" end

local len = func len(s: ptr(u8)): index
    return strlen(s)
end

local plus7 = func plus7(x: i32): i32
    return add7(x)
end

local M = moon.module("extern_island")
M:add_func(strlen)
M:add_func(add7)
M:add_func(len)
M:add_func(plus7)
return M
]]

local cb = ffi.cast("int32_t (*)(int32_t)", function(x) return x + 7 end)
M:symbol("host_add7", cb)

local compiled = M:compile()
local buf = ffi.new("uint8_t[6]", { string.byte("h"), string.byte("e"), string.byte("l"), string.byte("l"), string.byte("o"), 0 })
assert(tonumber(compiled:get("len")(buf)) == 5)
assert(compiled:get("plus7")(35) == 42)
compiled:free()
cb:free()

local standalone = Host.eval [[
local strlen = extern strlen(s: ptr(u8)): index end
return func len2(s: ptr(u8)): index
    return strlen(s)
end
]]
local compiled_standalone = standalone:compile()
assert(tonumber(compiled_standalone(buf)) == 5)
compiled_standalone:free()

print("moonlift mlua extern island ok")
