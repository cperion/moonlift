package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local mv = Run.dofile("tests/function_pointer_module.mlua")
local mod = mv:compile()

local callee = mod:get("callee")
local call_fp = mod:get("call_fp")
local call_fp_alias = mod:get("call_fp_alias")
local call_fp_cast = mod:get("call_fp_cast")

local fp = ffi.cast("void *", callee.fn)
assert(callee(41) == 42, "direct callee should work")
assert(call_fp(fp, 41) == 42, "func(...): result parameter should be indirectly callable")
assert(call_fp_alias(fp, 9) == 10, "fn(...): result alias should be indirectly callable")
assert(call_fp_cast(fp, 123) == 124, "raw pointer cast to function pointer should be callable")

mod:free()
print("function pointer support ok")
