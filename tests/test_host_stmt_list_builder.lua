package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local mod = Host.eval [=[
local body = moon.stmts [[
    let y: i32 = x + 1
    return y * 2
]]

local region_body = moon.stmts [[
    yield n + 5
]]

local f = func f(x: i32): i32
    @{body...}
end

local h = func h(x: i32): i32
    let z: i32 = x + 2
    return z * 2
end

local g = func g(n: i32): i32
    return region: i32
    entry start()
        @{region_body...}
    end
    end
end

local M = moon.module("stmt_list_builder")
M:add_func(f)
M:add_func(g)
M:add_func(h)
return M
]=]

local compiled = mod:compile()
assert(compiled:get("f")(20) == 42)
assert(compiled:get("g")(37) == 42)
assert(compiled:get("h")(19) == 42)

print("moonlift host stmt list builder ok")
