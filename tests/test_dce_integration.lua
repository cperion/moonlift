-- tests/test_dce_integration.lua
-- Integration test for the DCE optimizer pass.
-- Builds a synthetic IR buffer with live + dead instructions,
-- runs dce_pass, and verifies dead ones become IR_NOP.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Run = require("moonlift.mlua_run")

local dce_mv = Run.dofile("mlua/luajitvm/jit/opt_dce.mlua")
local dce    = dce_mv:compile()
local dce_fn = dce:get("dce_test")

local REF_BIAS = 0x8000
local IR_NOP   = 90
local IR_ADD   = 10
local IR_SLOAD = 31
local IR_KINT  = 60
local IRT_INT  = 19
local IRT_GUARD = 0x80

-- Allocate IR buffer (REF_BIAS+256 slots × 8 bytes)
local IR_SLOTS = REF_BIAS + 256
local IR_BUF = ffi.new("uint8_t[?]", IR_SLOTS * 8)
local IR_ptr = ffi.cast("void *", IR_BUF)
local IR_u64 = ffi.cast("uint64_t *", IR_BUF)

-- Mark scratch buffer
local MARKS = ffi.new("uint8_t[256]")
local MARKS_ptr = ffi.cast("void *", MARKS)

local function fld_op(u)   return tonumber(bit.band(bit.rshift(u, 40), 0xFF)) end
local function fld_type(u) return tonumber(bit.band(bit.rshift(u, 32), 0xFF)) end
local function fld_op1(u)  return tonumber(bit.band(u, 0xFFFF)) end
local function fld_op2(u)  return tonumber(bit.band(bit.rshift(u, 16), 0xFFFF)) end

-- Pack an IRIns as u64
local function pack_ir(o, t, op1, op2)
    local m16 = ffi.cast("uint64_t", 0xFFFF)
    local m8  = ffi.cast("uint64_t", 0xFF)
    return (ffi.cast("uint64_t", op1) % (2^16))
         + (ffi.cast("uint64_t", op2) % (2^16)) * (2^16)
         + (ffi.cast("uint64_t", t)   % (2^8))  * (2^32)
         + (ffi.cast("uint64_t", o)   % (2^8))  * (2^40)
end

local passed, failed = 0, 0
local function check(name, expected, actual)
    local e, a = tonumber(expected), tonumber(actual)
    if e == a then
        passed = passed + 1
        io.write(string.format("  OK   %-44s = %d\n", name, a))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-44s expected %d got %d\n", name, e, a))
    end
end

-- =========================================================================
-- Build IR trace:
--   slot 1: SLOAD(0, 0)  IRT_INT|IRT_GUARD  → live (side effect)
--   slot 2: ADD(r1, r1)  IRT_INT             → DEAD (only used by dead slot 4)
--   slot 3: SLOAD(1, 0)  IRT_INT|IRT_GUARD  → live (side effect)
--   slot 4: ADD(r2, r3)  IRT_INT             → DEAD (not used, no side effect)
--   slot 5: ADD(r1, r3)  IRT_INT             → live (used by slot 6's op2)
--   slot 6: SLOAD(2, r5) IRT_INT|IRT_GUARD  → live (side effect, uses r5)
-- nins = 7 (next free slot)
-- After DCE: slots 2 and 4 become NOP; slots 1,3,5,6 stay.
-- =========================================================================

ffi.fill(IR_BUF, IR_SLOTS * 8, 0)
ffi.fill(MARKS, 256, 0)

local R1 = REF_BIAS + 1  -- 0x8001
local R2 = REF_BIAS + 2  -- 0x8002
local R3 = REF_BIAS + 3  -- 0x8003
local R4 = REF_BIAS + 4  -- 0x8004 (dead)
local R5 = REF_BIAS + 5  -- 0x8005

IR_u64[1] = pack_ir(IR_SLOAD, IRT_INT + IRT_GUARD, 0, 0)       -- R1: live (guard)
IR_u64[2] = pack_ir(IR_ADD,   IRT_INT,             R1, R1)     -- R2: live (used by R5)
IR_u64[3] = pack_ir(IR_SLOAD, IRT_INT + IRT_GUARD, 1, 0)       -- R3: live (guard)
IR_u64[4] = pack_ir(IR_ADD,   IRT_INT,             R2, R3)     -- R4: DEAD
IR_u64[5] = pack_ir(IR_ADD,   IRT_INT,             R1, R3)     -- R5: live (used by R6)
IR_u64[6] = pack_ir(IR_SLOAD, IRT_INT + IRT_GUARD, 2, R5)     -- R6: live (guard, uses R5)

local nins = 7
local removed = dce_fn(IR_ptr, MARKS_ptr, nins)
check("removed count = 2",  2, removed)

-- Slots 2 and 4 should be NOP
check("slot2 is NOP",       IR_NOP,   fld_op(IR_u64[2]))
check("slot4 is NOP",       IR_NOP,   fld_op(IR_u64[4]))
-- Slots 1,3,5,6 should be unchanged
check("slot1 = SLOAD",      IR_SLOAD, fld_op(IR_u64[1]))
check("slot3 = SLOAD",      IR_SLOAD, fld_op(IR_u64[3]))
check("slot5 = ADD",        IR_ADD,   fld_op(IR_u64[5]))
check("slot6 = SLOAD",      IR_SLOAD, fld_op(IR_u64[6]))

-- Marks: slots 1,3,5,6 live; slots 2 and 4 not live
check("mark[1]=1", 1, MARKS[1])
check("mark[2]=0", 0, MARKS[2])
check("mark[3]=1", 1, MARKS[3])
check("mark[4]=0", 0, MARKS[4])
check("mark[5]=1", 1, MARKS[5])
check("mark[6]=1", 1, MARKS[6])

-- =========================================================================
-- Second scenario: all instructions dead except a guard at slot 3
-- =========================================================================
ffi.fill(IR_BUF, IR_SLOTS * 8, 0)
ffi.fill(MARKS, 256, 0)

IR_u64[1] = pack_ir(IR_ADD,   IRT_INT, 0, 0)                   -- dead
IR_u64[2] = pack_ir(IR_ADD,   IRT_INT, R1, R1)                 -- dead
IR_u64[3] = pack_ir(IR_SLOAD, IRT_INT + IRT_GUARD, 0, 0)       -- live (guard)

local removed2 = dce_fn(IR_ptr, MARKS_ptr, 4)
check("scenario2 removed=2", 2, removed2)
check("s2 slot1=NOP",  IR_NOP,   fld_op(IR_u64[1]))
check("s2 slot2=NOP",  IR_NOP,   fld_op(IR_u64[2]))
check("s2 slot3=SLOAD", IR_SLOAD, fld_op(IR_u64[3]))

dce:free()
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All DCE integration tests passed")
