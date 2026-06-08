package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

local compiled = moon.native_loadstring([[
func ret7(): i32
  return 7
end
func add(x: i32, y: i32): i32
  return x + y
end
]], "mom_source_to_binary.mlua")

local ret7 = ffi.cast("int32_t (*)()", compiled:get("ret7"))
assert(ret7() == 7)
local add = ffi.cast("int32_t (*)(int32_t, int32_t)", compiled:get("add"))
assert(add(20, 22) == 42)
compiled:free()

local wire = moon.host_mom.wire([[func f(): i32 return 9 end]])
assert(type(wire) == "string" and #wire > 16)

print("mom source to binary ok")
