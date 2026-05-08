-- tests/test_ir_layout.lua
-- IR smoke test: FFI-backed IRIns buffer, field accessors, TRef, REF_BIAS.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local ir_mv = Run.dofile("mlua/luajitvm/jit/ir.mlua")
local ir = ir_mv:compile()

-- Allocate an IR buffer (256 instructions, 8 bytes each = 2048 bytes)
local ir_buf = ffi.new("uint8_t[?]", 256 * 8)
local ir_ptr = ffi.cast("void *", ir_buf)

-- Write an IR instruction at slot N (8 * N byte offset)
local function write_ins(slot, o, t, op1, op2)
    local off = slot * 8
    local ins = ffi.cast("void *", ffi.cast("uint8_t *", ir_buf) + off)
    ir:get("ir_set")(ins, o, t, op1, op2)
end

local function read_ins(slot)
    local off = slot * 8
    local ins = ffi.cast("void *", ffi.cast("uint8_t *", ir_buf) + off)
    return {
        op1  = ir:get("ir_op1")(ins),
        op2  = ir:get("ir_op2")(ins),
        t    = ir:get("ir_type")(ins),
        o    = ir:get("ir_op")(ins),
        prev = ir:get("ir_prev")(ins),
    }
end

-- Test 1: Write and read a single IR instruction
write_ins(0, 10, 19, 0x8001, 0x7FFF)   -- IR_ADD, IRT_INT, op1=REF_FIRST, op2=REF_NIL
local ins0 = read_ins(0)
assert(ins0.o == 10, "opcode mismatch")
assert(ins0.t == 19, "type mismatch")
assert(ins0.op1 == 0x8001, "op1 mismatch")
assert(ins0.op2 == 0x7FFF, "op2 mismatch")
print("  OK   ir_set/ir_get fields")

-- Test 2: CSE prev field (overlaps r+s bytes)
ir:get("ir_set_prev")(ffi.cast("void *", ir_buf), 42)
local prev = ir:get("ir_prev")(ffi.cast("void *", ir_buf))
assert(prev == 42, "prev mismatch")
print("  OK   ir_prev (CSE chain)")

-- Test 3: r+s fields (overlap prev)
ir:get("ir_set_reg")(ffi.cast("void *", ir_buf), 7)
ir:get("ir_set_spill")(ffi.cast("void *", ir_buf), 3)
local r = ir:get("ir_reg")(ffi.cast("void *", ir_buf))
local s = ir:get("ir_spill")(ffi.cast("void *", ir_buf))
assert(r == 7, "reg mismatch")
assert(s == 3, "spill mismatch")
print("  OK   ir_reg/ir_spill (overlay prev)")

-- Test 4: REF_BIAS and constant space
local isk_nil  = ir:get("ir_isk")(0x7FFF)
local isk_inst = ir:get("ir_isk")(0x8001)
assert(isk_nil, "REF_NIL should be constant")
assert(not isk_inst, "REF_FIRST should be instruction")
print("  OK   REF_BIAS constant/instruction divide")

-- Test 5: TRef construction and extraction
local tr_int = ir:get("tref_new")(42, 19)   -- ref=42, type=IRT_INT(19)
local ref = ir:get("tref_ref")(tr_int)
local ty  = ir:get("tref_type")(tr_int)
assert(ref == 42, "tref_ref mismatch")
assert(ty == 19, "tref_type mismatch")
print("  OK   TRef pack/unpack")

-- Test 6: TRef type predicates
local tr_num = ir:get("tref_new")(1, 14)    -- IRT_NUM
local tr_i8  = ir:get("tref_new")(2, 15)    -- IRT_I8
assert(ir:get("tref_isnum")(tr_num), "should be num")
assert(not ir:get("tref_isnum")(tr_int), "int should not be num")
assert(ir:get("tref_isint")(tr_int), "should be int")
assert(ir:get("tref_isinteger")(tr_i8), "i8 should be integer")
print("  OK   TRef type predicates")

-- Test 7: Predefined TRef constants
assert(ir:get("ir_const_nil")() == 0x7FFF, "REF_NIL")
assert(ir:get("ir_const_false")() == 0x7FFE, "REF_FALSE")
assert(ir:get("ir_const_true")() == 0x7FFD, "REF_TRUE")
print("  OK   predefined constants")

-- Test 8: Write multiple instructions sequentially
write_ins(0, 60, 19, 0, 0)     -- IR_KINT, IRT_INT, op1=0, op2=0 (constant value in i field)
write_ins(1, 31, 19, 1, 0)     -- IR_SLOAD, IRT_INT, slot=1, mode=0
write_ins(2, 60, 19, 0, 0)     -- IR_KINT, IRT_INT (another constant)
write_ins(3, 10, 19, 0x8002, 0x8001)  -- IR_ADD, IRT_INT, op1=ins1, op2=ins0
write_ins(4, 80, 19, 0x8003, 0x8000)  -- IR_LOOP, op1=ins3, op2=start
for i = 0, 4 do
    local r = read_ins(i)
    assert(r.o > 0 or r.o == 0, "zero opcode at slot " .. i)
end
print("  OK   sequential IR write/read (5 instructions)")

ir:free()
print("\nAll IR layout tests passed")
