-- tests/test_asm_pipeline.lua
-- End-to-end JIT assembler pipeline test.
-- Builds synthetic IR traces, runs the backward-scan assembler,
-- and executes the generated x64 machine code via FFI.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi  = require("ffi")
local bit  = require("bit")
local Run  = require("moonlift.mlua_run")

local asm_mv  = Run.dofile("mlua/luajitvm/asm/asm_state.mlua")
local asm_mod = asm_mv:compile()
local asm_fn  = asm_mod:get("asm_trace_test")
local ra_fn   = asm_mod:get("ra_get_test")

-- =========================================================================
-- Setup: allocate RWX memory for generated code, JitState, AsmState
-- =========================================================================
ffi.cdef([[
void *mmap(void *a, size_t l, int p, int f, int fd, long o);
int   munmap(void *a, size_t l);
]])
local PROT_RWX = 0x7
local MAP_PRIVATE_ANON = 0x22

local function alloc_rwx(size)
    local p = ffi.C.mmap(nil, size, PROT_RWX, MAP_PRIVATE_ANON, -1, 0)
    assert(p ~= nil and p ~= ffi.cast("void*", -1))
    return p
end

local MCODE_SIZE = 4096
local MCODE = alloc_rwx(MCODE_SIZE)

-- JitState buffer (64 bytes): j64[4]=mctop, j64[5]=mcbot
local J_BUF = ffi.new("uint8_t[64]")
local J_ptr = ffi.cast("void *", J_BUF)
local J_u64 = ffi.cast("uint64_t *", J_BUF)

-- AsmState buffer (272 bytes, zeroed each test)
local A_BUF = ffi.new("uint8_t[272]")
local A_ptr = ffi.cast("void *", A_BUF)

-- IR buffer: slot-indexed u64 array (256 slots)
local IR_SLOTS = 256
local IR_BUF   = ffi.new("uint64_t[256]")
local IR_ptr   = ffi.cast("void *", IR_BUF)

-- =========================================================================
-- Helpers
-- =========================================================================
local REF_BIAS = 0x8000
local IR_KINT  = 60
local IR_ADD   = 10
local IR_SUB   = 11
local IR_MUL   = 12
local IR_NOP   = 90
local IR_RETF  = 82
local IRT_INT  = 19

local function pack_ir(o, t, op1, op2)
    local u1 = ffi.cast("uint64_t", op1 % 65536)
    local u2 = ffi.cast("uint64_t", op2 % 65536)
    local ut = ffi.cast("uint64_t", t  % 256)
    local uo = ffi.cast("uint64_t", o  % 256)
    return u1 + u2 * 65536 + ut * 2^32 + uo * 2^40
end

local function pack_kint(val)
    local lo = bit.band(val, 0xFFFF)
    local hi = bit.band(bit.rshift(val, 16), 0xFFFF)
    return pack_ir(IR_KINT, IRT_INT, lo, hi)
end

local function reset(nins)
    -- Zero JitState mcode pointers
    ffi.fill(J_BUF, 64, 0)
    -- mctop = MCODE + MCODE_SIZE, mcbot = MCODE
    J_u64[4] = ffi.cast("uint64_t", MCODE) + MCODE_SIZE
    J_u64[5] = ffi.cast("uint64_t", MCODE)
    -- Zero AsmState
    ffi.fill(A_BUF, 272, 0)
    -- Zero IR buffer slots
    for i = 0, nins do IR_BUF[i] = 0 end
end

local function mc_entry()
    return ffi.cast("uint8_t *", J_u64[4])
end

local passed, failed = 0, 0
local function check(name, exp, got)
    local e, g = tonumber(exp), tonumber(got)
    if e == g then
        passed = passed + 1
        io.write(string.format("  OK   %-44s = %s\n", name, g))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-44s expected %s got %s\n", name, e, g))
    end
end

-- =========================================================================
-- Test 1: KINT 42; RETF
--   slot 1: KINT(42)
--   slot 2: RETF(op1 = REF_BIAS+1)
-- Expected: function returns 42
-- =========================================================================
print("--- Test 1: KINT + RETF ---")
reset(3)
IR_BUF[1] = pack_kint(42)
IR_BUF[2] = pack_ir(IR_RETF, IRT_INT, REF_BIAS + 1, 0)

local entry = asm_fn(A_ptr, J_ptr, IR_ptr, 3)  -- nins=3 (slots 1,2 used)
assert(entry ~= nil and ffi.cast("uint64_t", entry) ~= 0, "assembly failed")

local fn1 = ffi.cast("int64_t (*)(void)", entry)
check("KINT(42); RETF → 42", 42, fn1())

-- =========================================================================
-- Test 2: KINT a; KINT b; ADD c=a+b; RETF c
-- =========================================================================
print("\n--- Test 2: ADD ---")
reset(5)
IR_BUF[1] = pack_kint(10)                                        -- slot 1 = 10
IR_BUF[2] = pack_kint(20)                                        -- slot 2 = 20
IR_BUF[3] = pack_ir(IR_ADD, IRT_INT, REF_BIAS+1, REF_BIAS+2)    -- slot 3 = 10+20
IR_BUF[4] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+3, 0)

local entry2 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry2 ~= nil and ffi.cast("uint64_t", entry2) ~= 0, "assembly failed")
local fn2 = ffi.cast("int64_t (*)(void)", entry2)
check("10 + 20 = 30", 30, fn2())

-- =========================================================================
-- Test 3: KINT a; KINT b; SUB c=a-b; RETF c
-- =========================================================================
print("\n--- Test 3: SUB ---")
reset(5)
IR_BUF[1] = pack_kint(100)
IR_BUF[2] = pack_kint(37)
IR_BUF[3] = pack_ir(IR_SUB, IRT_INT, REF_BIAS+1, REF_BIAS+2)    -- 100-37=63
IR_BUF[4] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+3, 0)

local entry3 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry3 ~= nil and ffi.cast("uint64_t", entry3) ~= 0, "assembly failed")
local fn3 = ffi.cast("int64_t (*)(void)", entry3)
check("100 - 37 = 63", 63, fn3())

-- =========================================================================
-- Test 4: KINT a; KINT b; MUL c=a*b; RETF c
-- =========================================================================
print("\n--- Test 4: MUL ---")
reset(5)
IR_BUF[1] = pack_kint(6)
IR_BUF[2] = pack_kint(7)
IR_BUF[3] = pack_ir(IR_MUL, IRT_INT, REF_BIAS+1, REF_BIAS+2)    -- 6*7=42
IR_BUF[4] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+3, 0)

local entry4 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry4 ~= nil and ffi.cast("uint64_t", entry4) ~= 0, "assembly failed")
local fn4 = ffi.cast("int64_t (*)(void)", entry4)
check("6 * 7 = 42", 42, fn4())

-- =========================================================================
-- Test 5: chained arithmetic: (a+b) * (c-d)
--   slot 1: KINT 3
--   slot 2: KINT 4
--   slot 3: KINT 10
--   slot 4: KINT 2
--   slot 5: ADD s3 = s1+s2     (3+4=7)
--   slot 6: SUB s4 = s3+s4-d  (10-2=8)
--   slot 7: MUL s7 = s5*s6    (7*8=56)
--   slot 8: RETF s7
-- =========================================================================
print("\n--- Test 5: chained (3+4)*(10-2)=56 ---")
reset(9)
IR_BUF[1] = pack_kint(3)
IR_BUF[2] = pack_kint(4)
IR_BUF[3] = pack_kint(10)
IR_BUF[4] = pack_kint(2)
IR_BUF[5] = pack_ir(IR_ADD, IRT_INT, REF_BIAS+1, REF_BIAS+2)
IR_BUF[6] = pack_ir(IR_SUB, IRT_INT, REF_BIAS+3, REF_BIAS+4)
IR_BUF[7] = pack_ir(IR_MUL, IRT_INT, REF_BIAS+5, REF_BIAS+6)
IR_BUF[8] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+7, 0)

local entry5 = asm_fn(A_ptr, J_ptr, IR_ptr, 9)
assert(entry5 ~= nil and ffi.cast("uint64_t", entry5) ~= 0, "assembly failed")
local fn5 = ffi.cast("int64_t (*)(void)", entry5)
check("(3+4)*(10-2) = 56", 56, fn5())

-- =========================================================================
-- Test 6: NOP slots are skipped cleanly
-- =========================================================================
print("\n--- Test 6: NOP slots skipped ---")
reset(7)
IR_BUF[1] = pack_kint(99)
IR_BUF[2] = pack_ir(IR_NOP, 0, 0, 0)
IR_BUF[3] = pack_ir(IR_NOP, 0, 0, 0)
IR_BUF[4] = pack_kint(1)
IR_BUF[5] = pack_ir(IR_ADD, IRT_INT, REF_BIAS+1, REF_BIAS+4)
IR_BUF[6] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+5, 0)

local entry6 = asm_fn(A_ptr, J_ptr, IR_ptr, 7)
assert(entry6 ~= nil and ffi.cast("uint64_t", entry6) ~= 0, "assembly failed")
local fn6 = ffi.cast("int64_t (*)(void)", entry6)
check("99+1 (with NOPs) = 100", 100, fn6())

-- Cleanup
ffi.C.munmap(MCODE, MCODE_SIZE)
asm_mod:free()

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All assembler pipeline tests passed")
