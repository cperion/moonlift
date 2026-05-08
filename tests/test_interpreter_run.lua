-- tests/test_interpreter_run.lua
-- FFI-backed test harness: compiles the interpreter and runs bytecode programs.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

-- Compile the interpreter module
local dispatch_mv = Run.dofile("mlua/luajitvm/runtime/dispatch.mlua")
local dispatch = dispatch_mv:compile()

-- Create test buffers with LuaJIT FFI
local STACK_SLOTS = 256
local TValueSize   = 16
local StackBytes   = STACK_SLOTS * TValueSize

-- ThreadState buffer (128 bytes, enough for lua_State layout)
local state_buf  = ffi.new("uint8_t[?]", 128)
local stack_buf  = ffi.new("uint8_t[?]", StackBytes)
local bc_buf     = ffi.new("uint32_t[?]", 64)
local state_ptr  = ffi.cast("void *", state_buf)
local stack_ptr  = ffi.cast("void *", stack_buf)
local bc_ptr     = ffi.cast("void *", bc_buf)

-- ThreadState layout offsets:
--   offset 32 = base  (ptr to TValue)
--   offset 40 = top   (ptr to TValue)
--   offset 56 = stack (ptr to TValue)
local state_u64 = ffi.cast("uint64_t *", state_buf)
local stack_uint = ffi.cast("uintptr_t", stack_ptr)
state_u64[4] = stack_uint                                    -- base = stack_ptr
state_u64[5] = stack_uint + StackBytes                       -- top = stack_ptr + StackBytes
state_u64[7] = stack_uint                                    -- stack = stack_ptr

local function run_program(bc, nins)
    -- Add RET1 at position nins to return slot 0
    bc[nins] = 76  -- RET1 with A=0
    -- Clear stack first
    ffi.fill(stack_buf, StackBytes, 0)
    local nresults = dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
    -- Read the TValue at slot 0 from stack: payload is i64 at offset 8
    local tv64 = ffi.cast("int64_t *", stack_buf)
    return tonumber(tv64[1])  -- payload at byte offset 8 = i64 index 1
end

-- Test results
local passed, failed = 0, 0
local function check(name, expected, actual)
    if expected == actual then
        passed = passed + 1
        print(string.format("  OK   %-20s = %d", name, actual))
    else
        failed = failed + 1
        print(string.format("  FAIL %-20s expected %d, got %d", name, expected, actual))
    end
end

-- Test 1: KSHORT 42 → return
bc_buf[0] = 41 + (0 * 256) + (42 * 65536)  -- KSHORT A=0 D=42
check("kshort_ret", 42, run_program(bc_buf, 1))

-- Test 2: MOV copy
bc_buf[0] = 41 + (0 * 256) + (99 * 65536)   -- KSHORT A=0 D=99
bc_buf[1] = 18 + (1 * 256)                    -- MOV A=1 B=0
bc_buf[2] = 76 + (1 * 256)                    -- RET1 A=1
check("mov", 99, run_program(bc_buf, 3))

local function kshort(a, d) return 41 + (a * 256) + (d * 65536) end
local function addvv(a, b, c) return 32 + (a * 256) + (c * 65536) + (b * 16777216) end

-- Test 3: Arithmetic — (3+4)*2 = 14 (all through slot 0 and slot 1)
bc_buf[0] = kshort(0, 3)                              -- slot0 = 3
bc_buf[1] = kshort(1, 4)                              -- slot1 = 4
bc_buf[2] = addvv(0, 0, 1)                            -- slot0 = slot0 + slot1 = 7
bc_buf[3] = kshort(1, 2)                              -- slot1 = 2
bc_buf[4] = 34 + (0 * 256) + (1 * 65536)              -- MULVV A=0 B=0 C=1 → slot0 *= slot1 = 14
bc_buf[5] = 76                                         -- RET1 A=0
check("arithmetic", 14, run_program(bc_buf, 6))

-- Test 4: Sum 0+1+2+3+4+5 = 15
bc_buf[0]  = kshort(0, 0)
bc_buf[1]  = kshort(1, 1);  bc_buf[2]  = addvv(0, 0, 1)
bc_buf[3]  = kshort(1, 2);  bc_buf[4]  = addvv(0, 0, 1)
bc_buf[5]  = kshort(1, 3);  bc_buf[6]  = addvv(0, 0, 1)
bc_buf[7]  = kshort(1, 4);  bc_buf[8]  = addvv(0, 0, 1)
bc_buf[9]  = kshort(1, 5);  bc_buf[10] = addvv(0, 0, 1)
bc_buf[11] = 76  -- RET1 A=0
check("sum_0_to_5", 15, run_program(bc_buf, 12))

-- Test 5: JMP skip
bc_buf[0] = kshort(0, 10)
bc_buf[1] = 88 + (0 * 256) + (2 * 65536)     -- JMP D=2 (skip 1 insn → pc+3)
bc_buf[2] = kshort(0, 99)                     -- DEAD: should be skipped
bc_buf[3] = 76                                -- RET1 A=0 → should return 10
check("jmp_skip", 10, run_program(bc_buf, 4))

-- Test 6: LOOP D=0 (no-op back-edge, just advances)
bc_buf[0] = kshort(0, 7)
bc_buf[1] = 85 + (0 * 256) + (0 * 65536)     -- LOOP D=0: jump to pc+1
bc_buf[2] = 76                                -- RET1 A=0 → return 7
check("loop_d0", 7, run_program(bc_buf, 3))

-- Test 7: LOOP back-edge (finite: loop exactly once, then use counter)
-- Program:
--   pc=0: KSHORT A=0 D=1    slot0=1
--   pc=1: KSHORT A=1 D=-1   slot1=-1 (signed)
--   pc=2: ADDVV A=2 B=0 C=1  slot2 = 1 + (-1) = 0
--   pc=3: LOOP D=-1          back to pc=3 (self-loop, infinite...)
-- Better: explicit finite program with JMP.

-- Test 7: SUBVV (10 - 3 = 7)
bc_buf[0] = kshort(0, 10)
bc_buf[1] = kshort(1, 3)
bc_buf[2] = 33 + (0 * 256) + (1 * 65536)              -- SUBVV A=0 B=0 C=1 → slot0 = 10 - 3 = 7
bc_buf[3] = 76                                         -- RET1 A=0
check("subvv", 7, run_program(bc_buf, 4))

-- Test 8: MULVV (6 * 7 = 42)
bc_buf[0] = kshort(0, 6)
bc_buf[1] = kshort(1, 7)
bc_buf[2] = 34 + (0 * 256) + (1 * 65536)              -- MULVV A=0 B=0 C=1 → slot0 = 6 * 7 = 42
bc_buf[3] = 76                                         -- RET1 A=0
check("mulvv", 42, run_program(bc_buf, 4))

-- Cleanup
dispatch:free()

if failed > 0 then
    error(string.format("%d interpreter tests FAILED", failed))
end
print(string.format("\nAll %d interpreter smoke tests passed", passed))
