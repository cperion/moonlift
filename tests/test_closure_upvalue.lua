package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local mv = Run.dofile("mlua/luajitvm/runtime/closure.mlua")
local clos = mv:compile()

local state = ffi.new("uint8_t[?]", 128)
local stack = ffi.new("uint8_t[?]", 256 * 16)
local proto = ffi.new("uint8_t[?]", 96 + 8)
local uvdesc = ffi.new("uint16_t[?]", 2)
local fn = ffi.new("uint8_t[?]", 40 + 2 * 8 + 2 * 48)

local su64 = ffi.cast("uint64_t *", state)
local st32 = ffi.cast("int32_t *", stack)
local st64 = ffi.cast("int64_t *", stack)
local p64 = ffi.cast("uint64_t *", proto)
local f64 = ffi.cast("uint64_t *", fn)

su64[4] = tonumber(ffi.cast("uintptr_t", stack)) -- base
su64[7] = tonumber(ffi.cast("uintptr_t", stack)) -- stack
proto[52] = 2 -- sizeuv
p64[4] = tonumber(ffi.cast("uintptr_t", uvdesc)) -- proto.uv
uvdesc[0] = 0x8000 + 1 -- local slot 1
uvdesc[1] = 0x8000 + 1 -- same local slot; should dedup to same open upvalue

st32[4] = 3; st64[3] = 777 -- stack slot 1 captured by both upvalues
local ins = 51 + (0 * 256) + (0 * 65536) -- FNEW A=0 D=0
local rc = clos:get("fnew_finish_test")(ffi.cast("void *", state), ins, 10, ffi.cast("void *", fn), ffi.cast("void *", proto))
assert(rc == 11, "fnew_finish should advance ip")
assert(st32[0] == 9, "slot0 tag should be function")
assert(st64[1] == tonumber(ffi.cast("uintptr_t", fn)), "slot0 payload should be fn")
assert(fn[10] == 0, "ffid should be Lua")
assert(fn[11] == 2, "nupvalues should be set")
assert(f64[4] == tonumber(ffi.cast("uintptr_t", proto + 96)), "fn pc should point to proto bytecode")
assert(f64[5] ~= 0, "uvptr[0] should be set")
assert(f64[6] == f64[5], "duplicate local captures should reuse open upvalue")
local uv = ffi.cast("uint8_t *", tonumber(f64[5]))
local uv64 = ffi.cast("uint64_t *", uv)
assert(uv[10] == 0, "upvalue should be open")
assert(uv64[4] == tonumber(ffi.cast("uintptr_t", stack)) + 16, "upvalue v should point to stack slot 1")
assert(su64[8] == f64[5], "openupval head should point to created upvalue")

clos:free()
print("closure upvalue binding ok")
