package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

ffi.cdef [[
typedef struct MoonliftAbiPair { int32_t a; int32_t b; } MoonliftAbiPair;
]]

local chunk = assert(moon.loadstring([[
struct MoonliftAbiPair
    a: i32
    b: i32
end

local abi_pair_sum = func(p: MoonliftAbiPair): i32
    return p.a + p.b
end

return abi_pair_sum
]], "=(test_aggregate_param_abi)"))

local probe = chunk()
local compiled = assert(probe:compile())
local pair = ffi.new("MoonliftAbiPair[1]")
pair[0].a = 11
pair[0].b = 31
assert(compiled(pair) == 42)
compiled:free()

print("aggregate param ABI: ok")
