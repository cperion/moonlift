package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test JIT compilation via .mlua eval
local Host = require("moonlift.mlua_run")

local add = Host.eval [[return func add(a: i32, b: i32): i32 return a + b end]]
local ok, compiled = pcall(function() return add:compile() end)
if ok then
    assert(compiled(2, 3) == 5)
    compiled:free()
end
print("OK: add" .. (ok and " compiled" or " value constructed"))

local abs32 = Host.eval [[return func abs_i32(x: i32): i32 return select(x >= 0, x, 0 - x) end]]
local ok2, compiled2 = pcall(function() return abs32:compile() end)
if ok2 then
    assert(compiled2(42) == 42)
    assert(compiled2(-42) == 42)
    compiled2:free()
end
print("OK: abs" .. (ok2 and " compiled" or " value constructed"))

local sum_to = Host.eval [[
return func sum_to(n: i32): i32
    return region: i32
    entry loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + i)
    end
    end
end
]]
local ok3, compiled3 = pcall(function() return sum_to:compile() end)
if ok3 then
    assert(compiled3(5) == 10)
    compiled3:free()
end
print("OK: sum_to" .. (ok3 and " compiled" or " value constructed"))

print("moonlift host value JIT ok")
