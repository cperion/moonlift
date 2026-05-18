package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local make_pair_sum = Host.eval [[
local Pair = struct x: i32; y: i32 end
return func pair_sum() -> i32
    let p: Pair = Pair{ x = 10, y = 32 }
    return p.x + p.y
end
]]
local c_pair = make_pair_sum:compile()
assert(c_pair() == 42)
c_pair:free()

local array_sum = Host.eval [[
return func array_sum() -> i32
    let xs = [10, 20, 12]
    return xs[0] + xs[1] + xs[2] + as(i32, len(xs)) - 3
end
]]
local c_array = array_sum:compile()
assert(c_array() == 42)
c_array:free()

local empty_array = Host.eval [[
return func empty_array_ok() -> i32
    let xs: [0]i32 = []
    return 7
end
]]
local c_empty = empty_array:compile()
assert(c_empty() == 7)
c_empty:free()

local addr_let = Host.eval [[
return func addr_let_ok() -> i32
    let x: i32 = 41
    let p: ptr(i32) = &x
    return *p + 1
end
]]
local c_addr = addr_let:compile()
assert(c_addr() == 42)
c_addr:free()

local nested = Host.eval [[
local Inner = struct x: i32; y: i32 end
local Outer = struct z: i32; a: Inner end
return func nested_aggregate_ok() -> i32
    let o: Outer = Outer{ z = 12, a = Inner{ x = 10, y = 20 } }
    return o.z + o.a.x + o.a.y
end
]]
local c_nested = nested:compile()
assert(c_nested() == 42)
c_nested:free()

local array_of_struct = Host.eval [[
local Pair = struct x: i32; y: i32 end
return func array_of_struct_ok() -> i32
    let xs = [Pair{ x = 1, y = 2 }, Pair{ x = 10, y = 32 }]
    return xs[1].x + xs[1].y
end
]]
local c_array_struct = array_of_struct:compile()
assert(c_array_struct() == 42)
c_array_struct:free()

local addr_arg = Host.eval [[
return func addr_arg_ok(x: i32) -> i32
    let p: ptr(i32) = &x
    return *p + 1
end
]]
local c_addr_arg = addr_arg:compile()
assert(c_addr_arg(41) == 42)
c_addr_arg:free()

local moon
local intrinsic_abs = Host.eval [[
local x = moon.ref("x", moon.i32)
local absx = moon.intrinsic("Abs", { x }, moon.i32)
return func intrinsic_abs_ok(x: i32) -> i32
    return @{absx}
end
]]
local c_intrinsic = intrinsic_abs:compile()
assert(c_intrinsic(-42) == 42)
c_intrinsic:free()

local intrinsic_fma = Host.eval [[
local a = moon.ref("a", moon.f64)
local b = moon.ref("b", moon.f64)
local c = moon.ref("c", moon.f64)
local y = moon.intrinsic("Fma", { a, b, c }, moon.f64)
return func intrinsic_fma_ok(a: f64, b: f64, c: f64) -> f64
    return @{y}
end
]]
local c_fma = intrinsic_fma:compile()
assert(c_fma(2, 20, 2) == 42)
c_fma:free()

local bad = Host.eval [[return func bad_missing_return(x: i32) -> i32 let y: i32 = x end]]
local ok_bad, err_bad = pcall(function() return bad:compile() end)
assert(not ok_bad and tostring(err_bad):match("unsupported lowering"), "unsupported lowering must fail before native code")

print("moonlift host aggregate/array literal lowering ok")
