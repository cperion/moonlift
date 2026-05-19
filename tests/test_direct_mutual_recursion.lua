package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift.host")

local M = moon.module("MutualRecursion")

M:func("even", { {name="n", type=moon.i32} }, moon.i32, function(f)
    local n = f:param("n")
    f:if_(n:eq(0), function(t)
        t:return_(1)
    end, function(e)
        e:return_(moon.expr[[odd(n - 1)]])
    end)
end)

M:func("odd", { {name="n", type=moon.i32} }, moon.i32, function(f)
    local n = f:param("n")
    f:if_(n:eq(0), function(t)
        t:return_(0)
    end, function(e)
        e:return_(moon.expr[[even(n - 1)]])
    end)
end)

M:export_func("call_even", { {name="n", type=moon.i32} }, moon.i32, function(f)
    f:return_(moon.expr[[even(n)]])
end)

local compiled = M:compile()
local call_even = compiled:get("call_even")
for i = 0, 10 do
    assert(call_even(i) == (i % 2 == 0 and 1 or 0))
end
compiled:free()

print("moonlift direct_mutual_recursion ok")
