package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local mv = Run.dofile("mlua/luajitvm/jit/snap.mlua")
local snap = mv:compile()

local L = ffi.new("uint8_t[?]", 128)
local stack = ffi.new("uint8_t[?]", 256 * 16)
local tr = ffi.new("uint8_t[?]", 104)
local snapbuf = ffi.new("uint8_t[?]", 16 * 4)
local smap = ffi.new("int32_t[?]", 8)
local ir = ffi.new("uint64_t[?]", 0x8000)
local ex = ffi.new("int64_t[?]", 8)
local pcbuf = ffi.new("uint8_t[?]", 4)

local L64 = ffi.cast("uint64_t *", L)
local st32 = ffi.cast("int32_t *", stack)
local st64 = ffi.cast("int64_t *", stack)
local tr64 = ffi.cast("uint64_t *", tr)
local sb32 = ffi.cast("uint32_t *", snapbuf)

L64[4] = tonumber(ffi.cast("uintptr_t", stack))
tr64[3] = tonumber(ffi.cast("uintptr_t", ir))
tr64[5] = tonumber(ffi.cast("uintptr_t", snapbuf))
tr64[6] = tonumber(ffi.cast("uintptr_t", smap))
tr64[8] = tonumber(ffi.cast("uintptr_t", pcbuf))

-- snapshot 0: mapofs=0, nslots=2, nent=2
sb32[0] = 0
sb32[1] = 2
sb32[2] = 2
-- slot0 <- KINT ref 0x7fff, slot1 <- runtime exit ref 0x8001
smap[0] = bit.bor(bit.lshift(0, 24), 0x7fff)
smap[1] = bit.bor(bit.lshift(1, 24), 0x8001)
-- IR[0x7fff] = KINT 42: op1=42, type=19, op=60
ir[0x7fff] = bit.bor(42ULL, bit.lshift(19ULL, 32), bit.lshift(60ULL, 40))
ex[1] = 99

local rc = snap:get("snap_restore_test")(ffi.cast("void *", L), ffi.cast("void *", tr), 0, ffi.cast("void *", ex))
assert(rc == 0, "snap_restore should succeed")
assert(st32[0] == 3 and st64[1] == 42, "slot0 restored from KINT")
assert(st32[4] == 3 and st64[3] == 99, "slot1 restored from exit state")
assert(L64[13] == tonumber(ffi.cast("uintptr_t", pcbuf)), "curpc restored")

snap:free()
print("snap restore ok")
