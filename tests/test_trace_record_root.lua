package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Run = require("moonlift.mlua_run")

local trace_mv = Run.dofile("mlua/luajitvm/jit/trace.mlua")
local trace = trace_mv:compile()

local function bc_abc(op, a, b, c)
  return op + a * 256 + c * 65536 + b * 16777216
end

local J = ffi.new("uint8_t[?]", 88)
local TR = ffi.new("uint8_t[?]", 104)
local IR = ffi.new("uint64_t[?]", 0x8000)
local SNAP = ffi.new("uint8_t[?]", 16 * 16)
local SMAP = ffi.new("int32_t[?]", 128)
local REFS = ffi.new("int32_t[?]", 32)
local A = ffi.new("uint8_t[?]", 280)
local MCODE = ffi.new("uint8_t[?]", 512)
local L = ffi.new("uint8_t[?]", 128)
local STACK = ffi.new("uint8_t[?]", 16 * 16)
local BC = ffi.new("uint32_t[?]", 4)

local J64 = ffi.cast("uint64_t *", J)
local TR64 = ffi.cast("uint64_t *", TR)
local TR16 = ffi.cast("uint16_t *", TR)
local TR32 = ffi.cast("uint32_t *", TR)
local L64 = ffi.cast("uint64_t *", L)
local S32 = ffi.cast("int32_t *", STACK)
local S64 = ffi.cast("int64_t *", STACK)

J64[0] = tonumber(ffi.cast("uintptr_t", TR))
J64[4] = tonumber(ffi.cast("uintptr_t", MCODE + 512)) -- mctop
J64[5] = tonumber(ffi.cast("uintptr_t", MCODE))       -- mcbot
J64[6] = tonumber(ffi.cast("uintptr_t", MCODE))       -- mcarea
J64[7] = tonumber(ffi.cast("uintptr_t", REFS))
J64[8] = tonumber(ffi.cast("uintptr_t", A))
TR64[3] = tonumber(ffi.cast("uintptr_t", IR))
TR64[5] = tonumber(ffi.cast("uintptr_t", SNAP))
TR64[6] = tonumber(ffi.cast("uintptr_t", SMAP))
TR16[47] = 3 -- traceno
L64[4] = tonumber(ffi.cast("uintptr_t", STACK))

S32[0] = 3; S64[1] = 10
S32[4] = 3; S64[3] = 20
BC[0] = bc_abc(32, 2, 0, 1) -- ADDVV slot2 = slot0 + slot1
BC[1] = bc_abc(76, 2, 0, 0) -- RET1 slot2

local rc = trace:get("trace_record_root_test")(ffi.cast("void *", J), ffi.cast("void *", L), ffi.cast("void *", BC))
assert(rc == 3, "root recorder should compile trace 3")
assert(tonumber(TR32[4]) == 5, "trace nins should include SLOAD,SLOAD,ADD,RETF")
assert(tonumber(TR32[8]) == 0x8000, "no KINT constants expected")
assert(tonumber(TR32[9]) == 3, "two SLOAD guards should snapshot live refs cumulatively")
assert(TR64[8] == tonumber(ffi.cast("uintptr_t", BC)), "startpc should be recorded")
assert(TR32[18] == BC[0], "startins should be recorded")
assert(TR64[10] ~= 0, "trace_commit should patch mcode entry")
assert(TR64[10] == J64[4], "trace_commit should patch assembled entry pointer")
assert(tonumber(J64[4]) < tonumber(ffi.cast("uintptr_t", MCODE + 512)), "asm_trace should emit mcode by moving mctop down")
assert(REFS[0] == 0x8001 and REFS[1] == 0x8002 and REFS[2] == 0x8003, "slot refs should be mapped")

local function op(u) return tonumber(bit.band(bit.rshift(u, 40), 0xff)) end
assert(op(IR[1]) == 31 and op(IR[2]) == 31 and op(IR[3]) == 10 and op(IR[4]) == 82,
  "IR sequence should be SLOAD,SLOAD,ADD,RETF")

trace:free()
print("trace record root ok")
