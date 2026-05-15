package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

-- Each func island used to start region_seq at 0, so two `block loop()`
-- islands produced the same region_id (`control.loop.1`). PVM/lowering then
-- reused control lowering across functions and emitted `arg:a:p` inside `b`.
local loader = assert(Host.loadstring([[
local M = moon.module("control_region_id_collision")

local a = func(p: ptr(i32))
    block loop()
        let k: i32 = p[0]
        if k == 0 then yield end
        p[0] = k - 1
        jump loop()
    end
end

local b = func(p: ptr(i32))
    block loop()
        let k: i32 = p[0]
        if k == 0 then yield end
        p[0] = k - 1
        jump loop()
    end
end

M:add_func(a)
M:add_func(b)
return M
]], "control_region_id_collision.mlua"))

local mod = loader()
local unit = mod:compile()
unit.artifact:free()

print("moonlift control_region_id_collision ok")
