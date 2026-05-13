package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local kernel_file = arg and arg[1] or error("usage: luajit bench_isolate_kernel.lua <kernel_file.mlua> [kernel_key]")
local kernel_key  = arg and arg[2] or "fib"

local fn, runtime = Run.loadfile(kernel_file)
local kernels = fn()

local k = kernels[kernel_key]
assert(k, "missing kernel: " .. kernel_key)

print("compiling " .. kernel_key .. " with backend " .. (os.getenv("MOONLIFT_BACKEND") or "dynasm"))
local compiled = k:compile()
print("compile ok")

local sig = "int32_t (*)(int32_t)"
local f = ffi.cast(sig, compiled.fn)
local r = f(32)
print("fib(32) = " .. tostring(r))

compiled:free()
print("done")
