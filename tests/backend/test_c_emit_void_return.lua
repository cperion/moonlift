package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local src = [[
local zero = func(p: ptr(u8), n: index): void
    block loop(i: index = 0)
        if i >= n then return end
        p[i] = as(u8, 0)
        jump loop(i = i + 1)
    end
end
return zero
]]

local zero = moon.loadstring(src, "test_c_emit_void_return.mlua")()
local module = moon.module("test_c_emit_void_return")
module:pack(zero)

local c = module:c_artifact({ module_id = "test_c_emit_void_return", name = "test_c_emit_void_return" }).source
assert(c:find("block_zero_if_then", 1, true), "expected if-then block label in generated C")
assert(c:find("block_zero_if_then.-return;", 1) ~= nil, "void return terminator must be emitted")

print("moonlift c_emit_void_return ok")
