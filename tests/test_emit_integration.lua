-- tests/test_emit_integration.lua
-- FFI-backed integration test for the IR emitter regions.
-- Allocates JitState + GCtrace + IR buffer, emits instructions via
-- the emit_single / emit_const_single wrappers, then reads back the
-- IR buffer to verify the packed IRIns records.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

-- =========================================================================
-- 1. Compile modules
-- =========================================================================
local emit_mv = Run.dofile("mlua/luajitvm/jit/emit.mlua")
local emit = emit_mv:compile()

-- =========================================================================
-- 2. Allocate buffers
-- =========================================================================
-- JitState: 32 bytes (offset layout from emit.mlua)
--   [0:7]  cur.trace (ptr)
--   [8:15] cur.nins  (u32/i32) + padding
--   [16:23] cur.nk   (u32/i32) + padding
--   [24:31] cur.nsnap (u32) + snapno (u32)
local J_BUF  = ffi.new("uint8_t[?]", 32)
local J_ptr  = ffi.cast("void *", J_BUF)
local J_u64  = ffi.cast("uint64_t *", J_BUF)

-- GCtrace: minimal frame. We need offset 24 (byte 3 in ptr(u64)) to hold the IR buffer ptr.
-- Size: 104 bytes from trace.mlua, but we only need the IR buf pointer field.
local TR_BUF = ffi.new("uint8_t[?]", 104)
local TR_ptr = ffi.cast("void *", TR_BUF)
local TR_u64 = ffi.cast("uint64_t *", TR_BUF)

-- IR buffer: 256 instructions * 8 bytes = 2048 bytes
local IR_CAP = 256
local IR_BUF = ffi.new("uint8_t[?]", IR_CAP * 8)
local IR_ptr = ffi.cast("void *", IR_BUF)
local IR_u64 = ffi.cast("uint64_t *", IR_BUF)

-- =========================================================================
-- 3. Wire up pointers
-- =========================================================================
-- JitState.cur.trace = TR_ptr
J_u64[0] = ffi.cast("uintptr_t", TR_ptr)
-- GCtrace.irbuf at offset 24 (byte 3 in u64)
TR_u64[3] = ffi.cast("uintptr_t", IR_ptr)

-- JitState.cur.nins = 1 (slot 0 reserved for BASE, first instruction at index 1)
J_u64[1] = 1
-- JitState.cur.nk = 0x8000 (REF_BIAS, next free constant slot, grows downward)
J_u64[2] = 0x8000

-- =========================================================================
-- 4. Emit instructions
-- =========================================================================
local emit_single    = emit:get("emit_single")
local emit_const_single = emit:get("emit_const_single")

-- Emit: IR_ADD, IRT_INT, op1=1, op2=2
local ref_add = emit_single(J_ptr, 10, 19, 1, 2, 0)
print(string.format("emit ADD  ref=%d", ref_add))
assert(ref_add == 0x8001, string.format("expected ref 0x8001, got 0x%x", ref_add))

-- Emit: IR_SUB, IRT_INT, op1=10, op2=3
local ref_sub = emit_single(J_ptr, 11, 19, 10, 3, 0)
print(string.format("emit SUB  ref=%d", ref_sub))
assert(ref_sub == 0x8002, string.format("expected ref 0x8002, got 0x%x", ref_sub))

-- Emit: IR_MUL, IRT_INT, op1=ref_add, op2=ref_sub
local ref_mul = emit_single(J_ptr, 12, 19, ref_add, ref_sub, 0)
print(string.format("emit MUL  ref=%d", ref_mul))
assert(ref_mul == 0x8003, string.format("expected ref 0x8003, got 0x%x", ref_mul))

-- =========================================================================
-- 5. Read back IR buffer and verify
-- =========================================================================
-- NOTE: bit operations must use cdata u64 directly, NOT tonumber().
-- tonumber() converts to double, losing precision in rshift on 64-bit values.
local function read_op1(raw_u64)
    return bit.band(raw_u64, 0xFFFF)
end
local function read_op2(raw_u64)
    return bit.band(bit.rshift(raw_u64, 16), 0xFFFF)
end
local function read_type(raw_u64)
    return bit.band(bit.rshift(raw_u64, 32), 0xFF)
end
local function read_op(raw_u64)
    return bit.band(bit.rshift(raw_u64, 40), 0xFF)
end
local function read_prev(raw_u64)
    return bit.band(bit.rshift(raw_u64, 48), 0xFFFF)
end

print("\n--- Reading back IR buffer ---")

-- Slot 0 is reserved/unused
-- IRIns at nins=1 (ref 0x8001) — first ADD
local ir0 = IR_u64[1]
print(string.format("IR[1]=0x%016x op=%d t=%d op1=%d op2=%d prev=%d",
    tonumber(ir0), tonumber(read_op(ir0)), tonumber(read_type(ir0)), tonumber(read_op1(ir0)), tonumber(read_op2(ir0)), tonumber(read_prev(ir0))))
assert(read_op(ir0)  == 10, "IR[0] opcode should be IR_ADD")
assert(read_type(ir0) == 19, "IR[0] type should be IRT_INT")
assert(read_op1(ir0) == 1,  "IR[0] op1 should be 1")
assert(read_op2(ir0) == 2,  "IR[0] op2 should be 2")
assert(read_prev(ir0) == 0, "IR[0] prev should be 0")

-- IRIns at nins=2 (ref 0x8002) — SUB
local ir1 = IR_u64[2]
print(string.format("IR[2]=0x%016x op=%d t=%d op1=%d op2=%d prev=%d",
    tonumber(ir1), tonumber(read_op(ir1)), tonumber(read_type(ir1)), tonumber(read_op1(ir1)), tonumber(read_op2(ir1)), tonumber(read_prev(ir1))))
assert(read_op(ir1)  == 11, "IR[1] opcode should be IR_SUB")
assert(read_type(ir1) == 19, "IR[1] type should be IRT_INT")
assert(read_op1(ir1) == 10, "IR[1] op1 should be 10")
assert(read_op2(ir1) == 3,  "IR[1] op2 should be 3")
assert(read_prev(ir1) == 0,  "IR[1] prev should be 0")

-- IRIns at nins=3 (ref 0x8003) — MUL
local ir2 = IR_u64[3]
print(string.format("IR[3]=0x%016x op=%d t=%d op1=%d op2=%d prev=%d",
    tonumber(ir2), tonumber(read_op(ir2)), tonumber(read_type(ir2)), tonumber(read_op1(ir2)), tonumber(read_op2(ir2)), tonumber(read_prev(ir2))))
assert(read_op(ir2)  == 12, "IR[2] opcode should be IR_MUL")
assert(read_type(ir2) == 19, "IR[2] type should be IRT_INT")
assert(read_op1(ir2) == ref_add, "IR[2] op1 should be ref of ADD")
assert(read_op2(ir2) == ref_sub, "IR[2] op2 should be ref of SUB")

-- =========================================================================
-- 6. Emit constant and verify
-- =========================================================================
local ref_const = emit_const_single(J_ptr, 42)
print(string.format("\nemit CONST 42 ref=%d", ref_const))
-- Constant should be stored at nk-1, which after decrement was the slot just below REF_BIAS
-- Because nk started at REF_BIAS (0x8000), first constant goes to index 0x7FFF
assert(ref_const == 0x7FFF, string.format("expected const ref 0x7FFF, got 0x%x", ref_const))

-- Read back constant from IR buffer
local ir_const = IR_u64[ref_const]  -- ptr(u64)[0x7FFF] = offset 0x7FFF * 8
print(string.format("IR[%d]=0x%016x op=%d t=%d op1=%d op2=%d",
    ref_const, tonumber(ir_const), tonumber(read_op(ir_const)), tonumber(read_type(ir_const)), tonumber(read_op1(ir_const)), tonumber(read_op2(ir_const))))
assert(read_op(ir_const)  == 60, "const opcode should be IR_KINT")
assert(read_type(ir_const) == 19, "const type should be IRT_INT")
assert(read_op1(ir_const) == 42, "const op1 should be 42")

-- =========================================================================
-- 7. Emit guard and verify need_snapshot path
-- =========================================================================
local ref_guard = emit_single(J_ptr, 31, 19 + 0x80, 0, 0, 0)  -- IR_SLOAD + IRT_GUARD
print(string.format("\nemit SLOAD (guard) ref=%d", ref_guard))
assert(ref_guard ~= -1 and ref_guard ~= -2, "guard should not fail")
-- Guard returns via need_snapshot continuation, which in our wrapper yields the ref

-- =========================================================================
-- 8. Cleanup
-- =========================================================================
emit:free()

print("\nAll IR emitter integration tests passed")
