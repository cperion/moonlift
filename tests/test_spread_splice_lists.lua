package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local f = Host.eval [=[
local params = moon.params[[ a: i32, b: i32 ]]
return func spread_params(@{params...}): i32
    return a + b
end
]=]
assert(#f.func.params == 2)
assert(f.func.params[1].name == "a")
assert(f.func.params[2].name == "b")

local Pair = Host.eval [=[
local fields = moon.fields{ T = moon.i32 }[[ x: @{T}; y: @{T} ]]
return struct Pair
    @{fields...}
end
]=]
assert(Pair.decl.fields[1].field_name == "x")
assert(Pair.decl.fields[2].field_name == "y")

local U = Host.eval [=[
local variants = moon.variants{ A = moon.i32 }[[ a(@{A}) | b(i64) ]]
return union U
    @{variants...}
end
]=]
assert(#U.decl.variants == 2)
assert(U.decl.variants[1].name == "a")
assert(U.decl.variants[2].name == "b")

local M = Host.eval [[
local args = { 20, 22 }
local add = func add(a: i32, b: i32): i32
    return a + b
end
local main = func main(): i32
    return add(@{args...})
end
local M = moon.module("spread_exprs")
M:add_func(add)
M:add_func(main)
return M
]]
local compiled = M:compile()
assert(compiled:get("main")() == 42)

print("moonlift spread splice lists ok")
