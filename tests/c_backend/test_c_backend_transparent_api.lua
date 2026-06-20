package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local add = moon.func[[func api_add(a: i32, b: i32): i32
    return a + b
end]]

local c_fn = add:compile { backend = "c", runner = "libtcc" }
assert(tonumber(c_fn(20, 22)) == 42, "C/libtcc backend callable should work through same :compile API")
add:free()

local add2 = moon.func[[func api_add2(a: i32, b: i32): i32
    return a + b
end]]
local c_fn2 = add2:compile { backend = "c", runner = "tcc" }
assert(tonumber(c_fn2(10, 32)) == 42, "C/tcc runner should use libtcc callable path when available")
add2:free()

local add3 = moon.func[[func api_add3(a: i32, b: i32): i32
    return a + b
end]]
local native_fn = add3:compile()
assert(tonumber(native_fn(19, 23)) == 42, "default Cranelift backend should remain unchanged")
add3:free()

io.write("moonlift c backend transparent API ok\n")
