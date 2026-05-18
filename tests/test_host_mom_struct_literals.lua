package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = dofile("init.lua")

local compiled = moon.native_loadstring([[
struct Pair
    x: i32
    y: i32
end
func main() -> i32
    let p: Pair = Pair{ x = 10, y = 32 }
    return p.x + p.y
end
]], "host_mom_struct_literals.mlua")

local main = ffi.cast("int32_t (*)()", compiled:get("main"))
assert(main() == 42)
compiled:free()

local nested = moon.native_loadstring([[
struct Outer
    z: i32
    a: Inner
end
struct Inner
    x: i32
    y: i32
end
func main() -> i32
    let o: Outer = Outer{ z = 12, a = Inner{ x = 10, y = 20 } }
    return o.z + o.a.x + o.a.y
end
]], "host_mom_nested_struct_literals.mlua")

local nested_main = ffi.cast("int32_t (*)()", nested:get("main"))
assert(nested_main() == 42)
nested:free()

print("moonlift host_mom struct literal lowering ok")
