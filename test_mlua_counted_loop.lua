package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Host = require("moonlift.host_quote")
local MluaParse = require("moonlift.mlua_parse")

local T = pvm.context()
A.Define(T)
local MP = MluaParse.Define(T)
local Tr = T.Moon2Tree

local parsed = MP.parse [[
export func sum(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n)
    return loop counted i: index = 0 until i >= len(v)
        state acc: i32 = 0
        yield acc
        next acc = acc + v[i]
    end
end
]]
assert(#parsed.issues == 0, tostring(parsed.issues[1]))
local f = parsed.module.items[1].func
local ret = f.body[2]
assert(pvm.classof(ret.value) == Tr.ExprControl)
assert(ret.value.region.entry.label.name == "counted_loop")
assert(#ret.value.region.entry.params == 2)

local sum = Host.eval [[
local sum = func sum(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n)
    return loop counted i: index = 0 until i >= len(v)
        state acc: i32 = 0
        yield acc
        next acc = acc + v[i]
    end
end
return sum
]]
local c_sum = sum:compile()
local xs = ffi.new("int32_t[5]", { 1, 2, 3, 4, 32 })
assert(c_sum(xs, 5) == 42)
c_sum:free()

print("moonlift mlua counted loop ok")
