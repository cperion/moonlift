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
local callinfo_buf = ffi.new("uint8_t[?]", 32 * 16)
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
state_u64[14] = tonumber(ffi.cast("uintptr_t", callinfo_buf)) -- explicit CallInfo stack

local function reset_runtime(setup)
    ffi.fill(stack_buf, StackBytes, 0)
    ffi.fill(callinfo_buf, 32 * 16, 0)
    state_u64[4] = stack_uint
    state_u64[5] = stack_uint + StackBytes
    state_u64[7] = stack_uint
    state_u64[14] = tonumber(ffi.cast("uintptr_t", callinfo_buf))
    ffi.cast("uint32_t *", state_buf)[30] = 0 -- cidepth
    if setup then setup() end
end

local function run_bcptr_with_setup(run_bc_ptr, setup)
    reset_runtime(setup)
    local nresults = dispatch:get("vm_interp_run")(state_ptr, ffi.cast("void *", run_bc_ptr), 0, 0)
    local tv64 = ffi.cast("int64_t *", stack_buf)
    return tonumber(tv64[1]), nresults
end

local function run_program_with_setup(bc, nins, setup)
    -- Add RET1 at position nins to return slot 0
    bc[nins] = 76  -- RET1 with A=0
    return run_bcptr_with_setup(bc_ptr, setup)
end

local function make_proto(nbc, nconst)
    local total = 96 + nbc * 4
    local proto = ffi.new("uint8_t[?]", total)
    local k = ffi.new("uint8_t[?]", nconst * 16)
    local p64 = ffi.cast("uint64_t *", proto)
    p64[3] = tonumber(ffi.cast("uintptr_t", k))
    local bc = ffi.cast("uint32_t *", proto + 96)
    return proto, k, bc
end

local function run_program(bc, nins)
    return run_program_with_setup(bc, nins)
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
local function divvv(a, b, c) return 35 + (a * 256) + (c * 65536) + (b * 16777216) end
local function modvv(a, b, c) return 36 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tgetv(a, b, c) return 56 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tgetb(a, b, c) return 58 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tsetv(a, b, c) return 60 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tsetb(a, b, c) return 62 + (a * 256) + (c * 65536) + (b * 16777216) end

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

-- Test 6b: LOOP with expired hotcount exits through typed hot edge.
do
    local G = ffi.new("uint8_t[?]", 552)
    ffi.cast("int32_t *", G)[368 / 4] = 0
    bc_buf[0] = 85 + (0 * 256) + (0 * 65536)
    bc_buf[1] = 76
    local _, status = run_program_with_setup(bc_buf, 2, function()
        state_u64[2] = tonumber(ffi.cast("uintptr_t", G))
    end)
    check("loop_hot", -400, status)
    reset_runtime(function()
        state_u64[2] = tonumber(ffi.cast("uintptr_t", G))
        ffi.cast("int32_t *", G)[368 / 4] = 0
    end)
    local J = ffi.new("uint8_t[?]", 32)
    local rec_status = dispatch:get("vm_interp_run_record")(state_ptr, bc_ptr, 0, 0, ffi.cast("void *", J))
    check("loop_hot_record", -401, rec_status)
end

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

-- Test 9: ISLT — 3 < 5 → true, don't skip, return 1
bc_buf[0] = kshort(0, 3); bc_buf[1] = kshort(1, 5)
bc_buf[2] = 0 + (1 * 65536)                            -- ISLT B=0 C=1
bc_buf[3] = kshort(0, 1)                               -- executed
bc_buf[4] = 76
check("islt_true", 1, run_program(bc_buf, 5))

-- Test 10: ISLT — 5 < 3 → false, skip next, return 5
bc_buf[0] = kshort(0, 5); bc_buf[1] = kshort(1, 3)
bc_buf[2] = 0 + (1 * 65536)                            -- ISLT B=0 C=1
bc_buf[3] = kshort(0, 99)                              -- SKIPPED
bc_buf[4] = 76
check("islt_false", 5, run_program(bc_buf, 5))

-- Test 11: ISGE — 5 >= 3 → true, don't skip, return 1
bc_buf[0] = kshort(0, 5); bc_buf[1] = kshort(1, 3)
bc_buf[2] = 1 + (1 * 65536)
bc_buf[3] = kshort(0, 1)
bc_buf[4] = 76
check("isge_true", 1, run_program(bc_buf, 5))

-- Test 12: ISEQV — 7 == 7 → true, don't skip, return 1
bc_buf[0] = kshort(0, 7); bc_buf[1] = kshort(1, 7)
bc_buf[2] = 4 + (1 * 65536)
bc_buf[3] = kshort(0, 1)
bc_buf[4] = 76
check("iseqv_true", 1, run_program(bc_buf, 5))

-- Test 13: ISNEV — 7 != 3 → true, don't skip, return 1
bc_buf[0] = kshort(0, 7); bc_buf[1] = kshort(1, 3)
bc_buf[2] = 5 + (1 * 65536)
bc_buf[3] = kshort(0, 1)
bc_buf[4] = 76
check("isnev_true", 1, run_program(bc_buf, 5))

-- Test 14: ADDVN — slot0(=3) + lit(7) = 10
bc_buf[0] = kshort(0, 3)
bc_buf[1] = 22 + (0 * 256) + (7 * 65536)
bc_buf[2] = 76
check("addvn", 10, run_program(bc_buf, 3))

-- Test 15: ADDNV — lit(3) + slot0(=7) = 10
bc_buf[0] = kshort(0, 7)
bc_buf[1] = 27 + (0 * 256) + (3 * 65536)
bc_buf[2] = 76
check("addnv", 10, run_program(bc_buf, 3))

-- Test 16: KPRI nil — read tag from stack (LUA_TNIL = 0)
bc_buf[0] = 43 + (0 * 256)                              -- KPRI A=0 D=0 (nil)
bc_buf[1] = 76
ffi.fill(stack_buf, StackBytes, 0)
dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
check("kpri_nil", 0, ffi.cast("int32_t *", stack_buf)[0])

-- Test 17: KPRI true — tag value (LUA_TTRUE = 2)
bc_buf[0] = 43 + (0 * 256) + (2 * 65536)               -- KPRI A=0 D=2 (true)
bc_buf[1] = 76
ffi.fill(stack_buf, StackBytes, 0)
dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
check("kpri_true", 2, ffi.cast("int32_t *", stack_buf)[0])

-- Test 18: DIVVV and MODVV integer fast path
bc_buf[0] = kshort(0, 22); bc_buf[1] = kshort(1, 5); bc_buf[2] = divvv(0, 0, 1); bc_buf[3] = 76
check("divvv", 4, run_program(bc_buf, 4))
bc_buf[0] = kshort(0, 22); bc_buf[1] = kshort(1, 5); bc_buf[2] = modvv(0, 0, 1); bc_buf[3] = 76
check("modvv", 2, run_program(bc_buf, 4))

-- Test 19: ISLE/ISGT
bc_buf[0] = kshort(0, 3); bc_buf[1] = kshort(1, 3); bc_buf[2] = 2 + (1 * 65536); bc_buf[3] = kshort(0, 1); bc_buf[4] = 76
check("isle_true", 1, run_program(bc_buf, 5))
bc_buf[0] = kshort(0, 5); bc_buf[1] = kshort(1, 3); bc_buf[2] = 3 + (1 * 65536); bc_buf[3] = kshort(0, 1); bc_buf[4] = 76
check("isgt_true", 1, run_program(bc_buf, 5))

-- Test 20: KNIL clears A..A+D and dispatch records current pc.
bc_buf[0] = kshort(0, 11); bc_buf[1] = kshort(1, 22); bc_buf[2] = kshort(2, 33)
bc_buf[3] = 44 + (0 * 256) + (2 * 65536) -- KNIL A=0 D=2
bc_buf[4] = 76
run_program(bc_buf, 5)
do
    local st32 = ffi.cast("int32_t *", stack_buf)
    check("knil slot0", 0, st32[0])
    check("knil slot1", 0, st32[4])
    check("knil slot2", 0, st32[8])
    check("thread pc at ret", 4, ffi.cast("int32_t *", state_buf)[23])
end

-- Test 18: TGETV array hit. stack[1]=table, stack[2]=key 1, result in stack[0].
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local arr32 = ffi.cast("int32_t *", arr_buf)
    local arr64 = ffi.cast("int64_t *", arr_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf)) -- array ptr @ offset 16
    tab32[12] = 4                                      -- asize @ offset 48
    arr32[0] = 3; arr64[1] = 1234                      -- array[1] = int 1234
    bc_buf[0] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf)) -- slot1 table
        st32[8] = 3; st64[5] = 1                                      -- slot2 key int 1
    end)
    check("tgetv_array", 1234, got)
end

-- Test 19: TSETV array hit then TGETV reads the stored value.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 4
    bc_buf[0] = tsetv(3, 1, 2) -- value slot3, table slot1, key slot2
    bc_buf[1] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8;  st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf)) -- slot1 table
        st32[8] = 3;  st64[5] = 2                                      -- slot2 key int 2
        st32[12] = 3; st64[7] = 5678                                   -- slot3 value
    end)
    check("tsetv_then_get", 5678, got)
end

-- Test 20: TGETV array miss yields nil tag in destination.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 1)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 1
    bc_buf[0] = tgetv(0, 1, 2)
    run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3; st64[5] = 2
    end)
    check("tgetv_miss_nil", 0, ffi.cast("int32_t *", stack_buf)[0])
end

-- Test 21: TGETV hash hit for an existing non-array integer key.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local node_buf = ffi.new("uint8_t[?]", 48)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local node32 = ffi.cast("int32_t *", node_buf)
    local node64 = ffi.cast("int64_t *", node_buf)
    tab64[5] = tonumber(ffi.cast("uintptr_t", node_buf)) -- node ptr @ offset 40
    tab32[13] = 0                                      -- hmask 0: one bucket
    node32[0] = 3; node64[1] = 4321                    -- val int 4321
    node32[4] = 3; node64[3] = 99                      -- key int 99
    bc_buf[0] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3; st64[5] = 99
    end)
    check("tgetv_hash", 4321, got)
end

-- Test 22: TSETV updates an existing hash node.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local node_buf = ffi.new("uint8_t[?]", 48)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local node32 = ffi.cast("int32_t *", node_buf)
    local node64 = ffi.cast("int64_t *", node_buf)
    tab64[5] = tonumber(ffi.cast("uintptr_t", node_buf))
    tab32[13] = 0
    node32[0] = 3; node64[1] = 111
    node32[4] = 3; node64[3] = 99
    bc_buf[0] = tsetv(3, 1, 2)
    bc_buf[1] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8;  st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3;  st64[5] = 99
        st32[12] = 3; st64[7] = 8765
    end)
    check("tsetv_hash", 8765, got)
end

-- Test 23: TGETB byte literal key.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local arr32 = ffi.cast("int32_t *", arr_buf)
    local arr64 = ffi.cast("int64_t *", arr_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 4
    arr32[4] = 3; arr64[3] = 2222 -- array key 2 -> slot 1
    bc_buf[0] = tgetb(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
    end)
    check("tgetb_array", 2222, got)
end

-- Test 24: TSETB byte literal key.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 4
    bc_buf[0] = tsetb(2, 1, 3) -- value slot2, table slot1, key literal 3
    bc_buf[1] = tgetb(0, 1, 3)
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3; st64[5] = 3333
    end)
    check("tsetb_then_get", 3333, got)
end

-- Test 25: TSETV collectable store triggers table back-barrier repair.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 2)
    local child_obj = ffi.new("uint8_t[?]", 48)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 2
    tab_buf[8] = 3 -- black table
    bc_buf[0] = tsetv(2, 0, 1) -- value slot2, table slot0, key slot1
    bc_buf[1] = 76
    run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[0] = 8; st64[1] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[4] = 3; st64[3] = 1
        st32[8] = 9; st64[5] = tonumber(ffi.cast("uintptr_t", child_obj))
    end)
    check("tsetv_barrier_gray", 2, tab_buf[8])
end

-- Test 26: TGETV miss with __index emits typed metamethod call edge.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local mt_buf = ffi.new("uint8_t[?]", 56)
    local mt_arr = ffi.new("uint8_t[?]", 16 * 16)
    local fake_fn = ffi.new("uint8_t[?]", 48)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local mt64 = ffi.cast("uint64_t *", mt_buf)
    local mt32 = ffi.cast("uint32_t *", mt_buf)
    local arr32 = ffi.cast("int32_t *", mt_arr)
    local arr64 = ffi.cast("int64_t *", mt_arr)
    tab64[4] = tonumber(ffi.cast("uintptr_t", mt_buf))
    mt64[2] = tonumber(ffi.cast("uintptr_t", mt_arr))
    mt32[12] = 16
    arr32[12 * 4] = 9
    arr64[12 * 2 + 1] = tonumber(ffi.cast("uintptr_t", fake_fn))
    bc_buf[0] = tgetv(0, 1, 2)
    bc_buf[1] = 76
    local _, status = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3; st64[5] = 999
    end)
    check("tgetv_index_meta", -509, status)
end

-- Test 27: NOT — truthy int → false (tag 1), falsy nil → true (tag 2)
bc_buf[0] = kshort(0, 7)                             -- slot0 = 7 (truthy int)
bc_buf[1] = 19 + (1 * 256) + (0 * 16777216)         -- NOT A=1 B=0
bc_buf[2] = 76 + (1 * 256)                          -- RET1 A=1
ffi.fill(stack_buf, StackBytes, 0)
dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
check("not_int", 1, ffi.cast("int32_t *", stack_buf)[4])  -- tag at slot1 = LUA_TFALSE=1

bc_buf[0] = 43 + (0 * 256)                           -- KPRI A=0 D=0 (nil)
bc_buf[1] = 19 + (1 * 256) + (0 * 16777216)         -- NOT A=1 B=0
bc_buf[2] = 76 + (1 * 256)                          -- RET1 A=1
ffi.fill(stack_buf, StackBytes, 0)
dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
check("not_nil", 2, ffi.cast("int32_t *", stack_buf)[4])  -- tag at slot1 = LUA_TTRUE=2

-- Test 26: UNM — negate integer
bc_buf[0] = kshort(0, 10)
bc_buf[1] = 20 + (1 * 256) + (0 * 16777216)         -- UNM A=1 B=0
bc_buf[2] = 18 + (0 * 256) + (1 * 16777216)         -- MOV A=0 B=1
check("unm", -10, run_program(bc_buf, 3))

-- Test 27: FORI/FORL — sum 1+2+3 = 6
-- Layout: slot0=accumulator, slot1=index, slot2=limit, slot3=step, slot4=loopvar
--   pc=0: KSHORT A=0 D=0        accumulator = 0
--   pc=1: KSHORT A=1 D=1        index = 1
--   pc=2: KSHORT A=2 D=3        limit = 3
--   pc=3: KSHORT A=3 D=1        step = 1
--   pc=4: FORI A=1 D=3          if idx > limit, jump to pc+1+3=8
--   pc=5: ADDVV A=0 B=0 C=4     acc += loopvar
--   pc=6: FORL A=1 D=-2         idx += step; if in range, jump to pc+1-2=5
--   pc=7: RET1 A=0 (return accumulator)
--   pc=8: RET1 A=0 (FORI skip target)
do
    local function fori(a, d) return 77 + (a * 256) + (d * 65536) end
    local function forl(a, d)
        local ud = d
        if ud < 0 then ud = ud + 65536 end
        return 79 + (a * 256) + (ud * 65536)
    end
    local addvv_full = function(a, b, c) return 32 + (a * 256) + (c * 65536) + (b * 16777216) end
    bc_buf[0] = kshort(0, 0)         -- accumulator = 0
    bc_buf[1] = kshort(1, 1)         -- index = 1
    bc_buf[2] = kshort(2, 3)         -- limit = 3
    bc_buf[3] = kshort(3, 1)         -- step = 1
    bc_buf[4] = fori(1, 3)           -- FORI: skip to pc=8 if 1>3 (no)
    bc_buf[5] = addvv_full(0, 0, 4)  -- acc += loopvar
    bc_buf[6] = forl(1, -2)          -- FORL: back to pc=5 if in range
    bc_buf[7] = 76                   -- RET1 A=0 (after loop exit)
    bc_buf[8] = 76                   -- RET1 A=0 (FORI skip target)
    check("for_loop_sum", 6, run_program(bc_buf, 9))
end

-- Test 28: CALL/RET switches to callee bytecode and resumes caller
-- Caller: CALL slot0; RET1 slot0.  Callee: returns 123 from its own bytecode.
do
    local callee_proto, ck, callee_bc = make_proto(4, 0)
    local fn_buf = ffi.new("uint8_t[?]", 48)
    local fn64 = ffi.cast("uint64_t *", fn_buf)
    fn_buf[10] = 0 -- FF_LUA
    fn64[4] = tonumber(ffi.cast("uintptr_t", callee_bc)) -- GCfunc.pc bytecode pointer
    callee_bc[0] = kshort(0, 123)
    callee_bc[1] = 76 -- RET1 A=0
    local function call(a, b, c) return 66 + (a * 256) + (c * 65536) + (b * 16777216) end
    bc_buf[0] = call(0, 1, 2) -- CALL A=0 B=1 C=2
    bc_buf[1] = 76            -- RET1 A=0 after callee resumes
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[0] = 9 -- LUA_TFUNC
        st64[1] = tonumber(ffi.cast("uintptr_t", fn_buf))
    end)
    check("lua_call_ret", 123, got)
end

-- Test 29: VARG copies extra arguments according to callee frame metadata.
do
    local callee_proto, ck, callee_bc = make_proto(8, 0)
    callee_proto[10] = 1 -- numparams: first arg is fixed, remaining are varargs
    local fn_buf = ffi.new("uint8_t[?]", 48)
    local fn64 = ffi.cast("uint64_t *", fn_buf)
    fn_buf[10] = 0
    fn64[4] = tonumber(ffi.cast("uintptr_t", callee_bc))
    local function call(a, b, c) return 66 + (a * 256) + (c * 65536) + (b * 16777216) end
    callee_bc[0] = 71 + (1 * 256) + (3 * 65536) -- VARG A=1 D=3: copy two extras
    callee_bc[1] = addvv(0, 1, 2)               -- slot0 = vararg1 + vararg2
    callee_bc[2] = 76                            -- RET1 A=0
    bc_buf[0] = call(0, 4, 2) -- function + 3 args, one result
    bc_buf[1] = 76
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[0] = 9; st64[1] = tonumber(ffi.cast("uintptr_t", fn_buf))
        st32[4] = 3; st64[3] = 10
        st32[8] = 3; st64[5] = 20
        st32[12] = 3; st64[7] = 30
    end)
    check("varg_sum", 50, got)
end

-- Test 30: Builtin native fast function returns type tag.
do
    local fn_buf = ffi.new("uint8_t[?]", 48)
    fn_buf[10] = 2 -- FF_TYPE_TAG
    local function call(a, b, c) return 66 + (a * 256) + (c * 65536) + (b * 16777216) end
    bc_buf[0] = call(0, 2, 2) -- one arg, one result
    bc_buf[1] = 76
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[0] = 9; st64[1] = tonumber(ffi.cast("uintptr_t", fn_buf))
        st32[4] = 3; st64[3] = 88
    end)
    check("base_type_tag", 3, got)
end

-- Test 31: Builtin yield fast function exits through typed yielded edge.
do
    local fn_buf = ffi.new("uint8_t[?]", 48)
    fn_buf[10] = 5 -- FF_YIELD
    local function call(a, b, c) return 66 + (a * 256) + (c * 65536) + (b * 16777216) end
    bc_buf[0] = call(0, 2, 0) -- one arg, multret wanted; yield code = nargs
    bc_buf[1] = 76
    local _, status = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[0] = 9; st64[1] = tonumber(ffi.cast("uintptr_t", fn_buf))
        st32[4] = 3; st64[3] = 88
    end)
    check("base_yield", -2, status)
end

-- Test 32: KSTR/KNUM copy constants from current proto.
do
    local proto, k, pbc = make_proto(4, 2)
    local k32 = ffi.cast("int32_t *", k)
    local k64 = ffi.cast("int64_t *", k)
    local str_obj = ffi.new("uint8_t[?]", 32)
    k32[0] = 5; k64[1] = tonumber(ffi.cast("uintptr_t", str_obj))
    k32[4] = 3; k64[3] = 2468
    pbc[0] = 42 + (0 * 256) + (1 * 65536) -- KNUM A=0 D=1
    pbc[1] = 76
    local got = run_bcptr_with_setup(pbc)
    check("knum_const", 2468, got)
end

-- Test 31: FNEW exposes typed closure allocation suspension.
do
    local parent, k, pbc = make_proto(3, 1)
    local child, ck, cbc = make_proto(2, 0)
    child[52] = 2 -- sizeuv
    local k32 = ffi.cast("int32_t *", k)
    local k64 = ffi.cast("int64_t *", k)
    k32[0] = 0; k64[1] = tonumber(ffi.cast("uintptr_t", child))
    pbc[0] = 51 + (0 * 256) + (0 * 65536) -- FNEW A=0 D=0
    pbc[1] = 76
    local got, status = run_bcptr_with_setup(pbc)
    check("fnew_need_alloc", -302, status)
end

-- Test 32: GGET — read env table by string constant key.
do
    local proto, k, pbc = make_proto(4, 1)
    local k32 = ffi.cast("int32_t *", k)
    local k64 = ffi.cast("int64_t *", k)
    local key_str = ffi.new("uint8_t[?]", 32)
    k32[0] = 5; k64[1] = tonumber(ffi.cast("uintptr_t", key_str))
    local env_buf = ffi.new("uint8_t[?]", 56)
    local node_buf = ffi.new("uint8_t[?]", 48)
    local env64 = ffi.cast("uint64_t *", env_buf)
    local env32 = ffi.cast("uint32_t *", env_buf)
    local node32 = ffi.cast("int32_t *", node_buf)
    local node64 = ffi.cast("int64_t *", node_buf)
    env64[5] = tonumber(ffi.cast("uintptr_t", node_buf))
    env32[13] = 0
    node32[0] = 3; node64[1] = 7777
    node32[4] = 5; node64[3] = tonumber(ffi.cast("uintptr_t", key_str))
    pbc[0] = 54 + (0 * 256) + (0 * 65536) -- GGET A=0 D=0
    pbc[1] = 76
    local got = run_bcptr_with_setup(pbc, function()
        state_u64[9] = tonumber(ffi.cast("uintptr_t", env_buf))
    end)
    check("gget", 7777, got)
end

-- Test 32: GSET — write env table by string constant key.
do
    local proto, k, pbc = make_proto(5, 1)
    local k32 = ffi.cast("int32_t *", k)
    local k64 = ffi.cast("int64_t *", k)
    local key_str = ffi.new("uint8_t[?]", 32)
    k32[0] = 5; k64[1] = tonumber(ffi.cast("uintptr_t", key_str))
    local env_buf = ffi.new("uint8_t[?]", 56)
    local node_buf = ffi.new("uint8_t[?]", 48)
    local env64 = ffi.cast("uint64_t *", env_buf)
    local env32 = ffi.cast("uint32_t *", env_buf)
    local node32 = ffi.cast("int32_t *", node_buf)
    local node64 = ffi.cast("int64_t *", node_buf)
    env64[5] = tonumber(ffi.cast("uintptr_t", node_buf))
    env32[13] = 0
    node32[0] = 0; node64[1] = 0
    node32[4] = 5; node64[3] = tonumber(ffi.cast("uintptr_t", key_str))
    pbc[0] = kshort(0, 5555)
    pbc[1] = 55 + (0 * 256) + (0 * 65536) -- GSET A=0 D=0
    pbc[2] = 54 + (0 * 256) + (0 * 65536) -- GGET A=0 D=0
    pbc[3] = 76
    local got = run_bcptr_with_setup(pbc, function()
        state_u64[9] = tonumber(ffi.cast("uintptr_t", env_buf))
    end)
    check("gset", 5555, got)
end

-- Test 31: TNEW exposes typed need_alloc suspension (asize=4)
do
    bc_buf[0] = 52 + (0 * 256) + (4 * 65536)  -- TNEW A=0 D=4
    bc_buf[1] = 76                              -- RET1 A=0 (unreachable)
    ffi.fill(stack_buf, StackBytes, 0)
    local nresults = dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
    check("tnew_need_alloc", -204, nresults)  -- -200 - asize
end

-- Cleanup
dispatch:free()

if failed > 0 then
    error(string.format("%d interpreter tests FAILED", failed))
end
print(string.format("\nAll %d interpreter smoke tests passed", passed))
