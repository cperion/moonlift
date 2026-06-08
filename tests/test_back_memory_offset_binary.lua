package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

local chunk = assert(moon.loadstring([[
local weighted_sum = func(xs: ptr(i32)): i32
    return xs[0] + xs[1] * 10 + xs[2] * 100
end

local write_three = func(xs: ptr(i32)): void
    xs[0] = 1
    xs[1] = 2
    xs[2] = 3
    return
end

return weighted_sum, write_three
]], "=(test_back_memory_offset_binary)"))

local weighted_sum_value, write_three_value = chunk()
local weighted_sum = weighted_sum_value:compile()
local write_three = write_three_value:compile()

local xs = ffi.new("int32_t[3]", { 1, 2, 3 })
assert(weighted_sum(xs) == 321, "load byte offsets must be applied")

local ys = ffi.new("int32_t[3]", { 0, 0, 0 })
write_three(ys)
assert(ys[0] == 1 and ys[1] == 2 and ys[2] == 3, "store byte offsets must be applied")

weighted_sum:free()
write_three:free()

print("moonlift back memory offset binary ok")
