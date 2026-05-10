package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local trace_mv = Run.dofile("mlua/luajitvm/jit/trace.mlua")
local trace = trace_mv:compile()

local TR = ffi.new("uint8_t[?]", 104)
local STACK = ffi.new("uint8_t[?]", 32)
local tr64 = ffi.cast("uint64_t *", TR)
local st64 = ffi.cast("int64_t *", STACK)

st64[1] = 4242
tr64[10] = tonumber(ffi.cast("uintptr_t", trace:get("trace_entry_probe").fn))
local got = trace:get("trace_call_mcode_test")(ffi.cast("void *", TR), ffi.cast("void *", STACK))
assert(got == 4242, "trace mcode should be callable through func(ptr(u8))->i64")

trace:free()
print("trace function pointer call ok")
