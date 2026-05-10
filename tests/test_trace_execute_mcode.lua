package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Run = require("moonlift.mlua_run")

ffi.cdef[[
void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
int munmap(void *addr, size_t length);
]]

local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
local MAP_PRIVATE, MAP_ANON = 2, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local function exec_alloc(size)
  local p = ffi.C.mmap(nil, size, bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC), bit.bor(MAP_PRIVATE, MAP_ANON), -1, 0)
  assert(p ~= MAP_FAILED, "mmap RWX mcode arena failed")
  return ffi.cast("uint8_t *", p)
end

local function bc_abc(op, a, b, c)
  return op + a * 256 + c * 65536 + b * 16777216
end

local trace_mv = Run.dofile("mlua/luajitvm/jit/trace.mlua")
local trace = trace_mv:compile()

local MCODE_SIZE = 4096
local MCODE = exec_alloc(MCODE_SIZE)
local J = ffi.new("uint8_t[?]", 88)
local TR = ffi.new("uint8_t[?]", 104)
local IR = ffi.new("uint64_t[?]", 0x8000)
local SNAP = ffi.new("uint8_t[?]", 16 * 16)
local SMAP = ffi.new("int32_t[?]", 128)
local EX = ffi.new("int64_t[?]", 16)
local REFS = ffi.new("int32_t[?]", 32)
local A = ffi.new("uint8_t[?]", 280)
local L = ffi.new("uint8_t[?]", 128)
local STACK = ffi.new("uint8_t[?]", 16 * 16)
local BC = ffi.new("uint32_t[?]", 4)

local J64 = ffi.cast("uint64_t *", J)
local TR64 = ffi.cast("uint64_t *", TR)
local TR16 = ffi.cast("uint16_t *", TR)
local L64 = ffi.cast("uint64_t *", L)
local S32 = ffi.cast("int32_t *", STACK)
local S64 = ffi.cast("int64_t *", STACK)

J64[0] = tonumber(ffi.cast("uintptr_t", TR))
J64[4] = tonumber(ffi.cast("uintptr_t", MCODE + MCODE_SIZE)) -- mctop
J64[5] = tonumber(ffi.cast("uintptr_t", MCODE + 16))         -- mcbot guard
J64[6] = tonumber(ffi.cast("uintptr_t", MCODE))              -- mcarea
J64[7] = tonumber(ffi.cast("uintptr_t", REFS))
J64[8] = tonumber(ffi.cast("uintptr_t", A))
TR64[3] = tonumber(ffi.cast("uintptr_t", IR))
TR64[5] = tonumber(ffi.cast("uintptr_t", SNAP))
TR64[6] = tonumber(ffi.cast("uintptr_t", SMAP))
TR16[47] = 11 -- traceno
L64[4] = tonumber(ffi.cast("uintptr_t", STACK))

S32[0] = 3; S64[1] = 10
S32[4] = 3; S64[3] = 20
BC[0] = bc_abc(32, 2, 0, 1) -- ADDVV slot2 = slot0 + slot1
BC[1] = bc_abc(76, 2, 0, 0) -- RET1 slot2

local rc = trace:get("trace_record_root_test")(ffi.cast("void *", J), ffi.cast("void *", L), ffi.cast("void *", BC))
assert(rc == 11, "root recorder should compile trace 11")
assert(TR64[10] == J64[4], "committed mcode should be assembled entry")

local ok_result = trace:get("trace_call_mcode_test")(ffi.cast("void *", TR), ffi.cast("void *", STACK))
assert(ok_result == 30, "executed trace should return slot0 + slot1")

S32[0] = 0 -- guard failure: slot0 is no longer an integer
local fail_result = trace:get("trace_call_mcode_test")(ffi.cast("void *", TR), ffi.cast("void *", STACK))
assert(fail_result == -1, "first guard failure should branch to exit stub 0")
EX[1] = 10
local restored = trace:get("trace_execute_test")(ffi.cast("void *", L), ffi.cast("void *", TR), ffi.cast("void *", STACK), ffi.cast("void *", EX))
assert(restored == -1, "typed trace execute should restore on guard failure")
assert(S32[0] == 3 and S64[1] == 10, "snapshot restore should repair slot0 from exit state")
assert(L64[13] == tonumber(ffi.cast("uintptr_t", BC)), "snapshot restore should restore curpc to trace start")

ffi.C.munmap(MCODE, MCODE_SIZE)
trace:free()
print("trace executable mcode ok")
