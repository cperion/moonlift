package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local moon = require("moonlift.host")

local M = moon.module("HostJitDemo")
M:export_func("add", { moon.param("a", moon.i32), moon.param("b", moon.i32) }, moon.i32, function(fn)
    return fn:param("a") + fn:param("b")
end)

M:export_func("abs_i32", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    local x = fn:param("x")
    fn:if_(x:lt(0), function(t) t:return_(-x) end, function(e) e:return_(x) end)
end)

local clamp = moon.expr_frag("clamp_nonneg_jit", { moon.param("x", moon.i32) }, moon.i32, function(f)
    local x = f:param("x")
    return x:lt(0):select(0, x)
end)
M:export_func("score", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    return moon.emit_expr(clamp, { fn:param("x") }) + 3
end)

M:export_func("sum_to", { moon.param("n", moon.i32) }, moon.i32, function(fn)
    local n = fn:param("n")
    fn:return_region(moon.i32, function(r)
        r:entry("loop", { moon.entry_param("i", moon.i32, moon.int(0)), moon.entry_param("acc", moon.i32, moon.int(0)) }, function(loop)
            local i = loop:param("i")
            local acc = loop:param("acc")
            loop:if_(i:ge(n), function(t) t:yield_(acc) end)
            loop:jump(loop.block, { i = i + 1, acc = acc + i })
        end)
    end)
end)

local compiled = M:compile()
assert(compiled:get("add")(20, 22) == 42)
assert(compiled:get("abs_i32")(-7) == 7)
assert(compiled:get("abs_i32")(9) == 9)
assert(compiled:get("score")(-5) == 3)
assert(compiled:get("score")(5) == 8)
assert(compiled:get("sum_to")(5) == 10)
compiled:free()

print("moonlift host value jit ok")
