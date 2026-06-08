package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local chunk = assert(moon.loadstring([[
local sum_region = func(n: i32): i32
    return region: i32
    entry loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + i)
    end
    end
end

local prod_region = func(n: i32): i32
    return region: i32
    entry loop(i: i32 = 0, acc: i32 = 1)
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc * i)
    end
    end
end

return sum_region, prod_region
]], "=(test_vec_algebraic_reject_correctness)"))

local sum_value, prod_value = chunk()
local sum = sum_value:compile()
local prod = prod_value:compile()

local function assert_eq(name, got, expect)
    assert(got == expect, string.format("%s: expected %d, got %d", name, expect, got))
end

assert_eq("sum negative is zero-trip", sum(-3), 0)
assert_eq("sum zero is zero-trip", sum(0), 0)
assert_eq("sum positive", sum(5), 10)

assert_eq("prod negative keeps initial accumulator", prod(-1), 1)
assert_eq("prod zero keeps initial accumulator", prod(0), 1)
assert_eq("prod positive follows loop semantics", prod(5), 0)

sum:free()
prod:free()

print("moonlift vec algebraic reject correctness ok")
