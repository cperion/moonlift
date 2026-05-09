-- tests/test_fold_integration.lua
-- Integration test for the algebraic fold engine.
-- Pre-populates KINT constant slots in a JitState + IR buffer,
-- then calls fold_test to verify all three fold paths.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi  = require("ffi")
local bit  = require("bit")
local Run  = require("moonlift.mlua_run")

-- =========================================================================
-- Compile modules
-- =========================================================================
local fold_mv = Run.dofile("mlua/luajitvm/jit/fold.mlua")
local fold    = fold_mv:compile()
local fold_test_fn = fold:get("fold_test")

-- =========================================================================
-- Allocate and wire buffers
-- =========================================================================
local J_BUF  = ffi.new("uint8_t[?]", 32)
local TR_BUF = ffi.new("uint8_t[?]", 104)
-- IR buffer: full REF_BIAS+256 slots × 8 bytes (constants + instructions)
local IR_SLOTS = 0x8000 + 256  -- 32768 constants + 256 instructions
local IR_BUF = ffi.new("uint8_t[?]", IR_SLOTS * 8)
local J_ptr  = ffi.cast("void *", J_BUF)
local TR_ptr = ffi.cast("void *", TR_BUF)
local IR_ptr = ffi.cast("void *", IR_BUF)
local J_u64  = ffi.cast("uint64_t *", J_BUF)
local TR_u64 = ffi.cast("uint64_t *", TR_BUF)
local IR_u64 = ffi.cast("uint64_t *", IR_BUF)

-- Wire: J.cur.trace -> TR, TR.irbuf -> IR
J_u64[0]  = ffi.cast("uintptr_t", TR_ptr)
TR_u64[3] = ffi.cast("uintptr_t", IR_ptr)
-- J.cur.nins = 1  (slot 0 reserved; first instruction at 1)
J_u64[1] = 1
-- J.cur.nk = 0x8000 (REF_BIAS; constants grow downward from here)
J_u64[2] = 0x8000

-- IR buffer helper: ffi_u64 → read specific fields
local function fld_op(u)  return tonumber(bit.band(bit.rshift(u, 40), 0xFF)) end
local function fld_op1(u) return tonumber(bit.band(u, 0xFFFF)) end

-- Pre-populate KINT constants manually in the IR buffer (below REF_BIAS).
-- pack_kint: (val & 0xFFFF) | (IRT_INT=19 << 32) | (IR_KINT=60 << 40)
local function pack_kint(val)
    local v = ffi.cast("uint64_t", bit.band(val, 0xFFFF))
    local t = ffi.cast("uint64_t", 19) * (2^32)
    local o = ffi.cast("uint64_t", 60) * (2^40)
    return v + t + o
end

-- Slot layout (indices below REF_BIAS=0x8000):
--   0x7FFD = 32765 → KINT(3)
--   0x7FFE = 32766 → KINT(4)
--   0x7FFF = 32767 → KINT(0)   (zero for identity tests)
IR_u64[0x7FFD] = pack_kint(3)
IR_u64[0x7FFE] = pack_kint(4)
IR_u64[0x7FFF] = pack_kint(0)

-- Set nk just below the lowest pre-populated constant so alloc_kint
-- does not overwrite them.  nk=0x7FFD means the next alloc goes to 0x7FFC.
J_u64[2] = 0x7FFD

local K3    = 0x7FFD  -- KINT(3)
local K4    = 0x7FFE  -- KINT(4)
local KZERO = 0x7FFF  -- KINT(0)
local BIAS  = 0x8000  -- REF_BIAS

-- Pre-emit two instructions at slots 1 and 2 for use as non-constant operands
-- IR_NOP(0, 0) at slot 1 — any opcode is fine, we just need instruction refs
local pack_nop = ffi.cast("uint64_t",
    ffi.cast("uint64_t", 19) * (2^32) + ffi.cast("uint64_t", 90) * (2^40))
IR_u64[1] = pack_nop
IR_u64[2] = pack_nop
J_u64[1] = 3   -- nins advances past slots 1 and 2

local INSTR1 = BIAS + 1   -- 0x8001
local INSTR2 = BIAS + 2   -- 0x8002

-- =========================================================================
-- Test helpers
-- =========================================================================
local passed, failed = 0, 0
local function check(name, expected, actual)
    if expected == actual then
        passed = passed + 1
        io.write(string.format("  OK   %-36s got %d\n", name, actual))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-36s expected %d, got %d\n", name, expected, actual))
    end
end

local function check_kint(name, ref, expected_val)
    local raw = IR_u64[ref]
    local op  = fld_op(raw)
    local v   = fld_op1(raw)
    if op == 60 and v == expected_val then
        passed = passed + 1
        io.write(string.format("  OK   %-36s KINT(%d) at slot %d\n", name, v, ref))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-36s expected KINT(%d) at %d, got op=%d val=%d\n",
                               name, expected_val, ref, op, v))
    end
end

-- =========================================================================
-- 1. Constant folding
-- =========================================================================
print("--- Constant folding ---")

-- ADD(3, 4) -> KINT(7)
local ref_add34 = fold_test_fn(J_ptr, IR_ptr, K3, K4, 10)
check("ADD(KINT(3), KINT(4)) folded ref",  0x7FFC, ref_add34)
check_kint("ADD result is KINT(7)",         ref_add34, 7)

-- SUB(4, 3) -> KINT(1)
local ref_sub43 = fold_test_fn(J_ptr, IR_ptr, K4, K3, 11)
check("SUB(KINT(4), KINT(3)) folded ref",  0x7FFB, ref_sub43)
check_kint("SUB result is KINT(1)",         ref_sub43, 1)

-- MUL(3, 4) -> KINT(12)
local ref_mul34 = fold_test_fn(J_ptr, IR_ptr, K3, K4, 12)
check("MUL(KINT(3), KINT(4)) folded ref",  0x7FFA, ref_mul34)
check_kint("MUL result is KINT(12)",        ref_mul34, 12)

-- BAND(3, 4) -> KINT(0)
local ref_band = fold_test_fn(J_ptr, IR_ptr, K3, K4, 40)
check("BAND(KINT(3), KINT(4)) folded ref", 0x7FF9, ref_band)
check_kint("BAND result is KINT(0)",        ref_band, 0)

-- =========================================================================
-- 2. Identity elimination
-- =========================================================================
print("\n--- Identity elimination ---")

-- ADD(INSTR1, KZERO) -> INSTR1
local ref_add0r = fold_test_fn(J_ptr, IR_ptr, INSTR1, KZERO, 10)
check("ADD(instr, KINT(0)) -> instr",   INSTR1, ref_add0r)

-- ADD(KZERO, INSTR1) -> INSTR1
local ref_add0l = fold_test_fn(J_ptr, IR_ptr, KZERO, INSTR1, 10)
check("ADD(KINT(0), instr) -> instr",   INSTR1, ref_add0l)

-- SUB(INSTR1, KZERO) -> INSTR1  (x - 0 = x)
local ref_sub0 = fold_test_fn(J_ptr, IR_ptr, INSTR1, KZERO, 11)
check("SUB(instr, KINT(0)) -> instr",   INSTR1, ref_sub0)

-- SUB(KZERO, INSTR1) -> keep  (0 - x ≠ x, identity NOT applied to left for SUB)
local ref_sub0l = fold_test_fn(J_ptr, IR_ptr, KZERO, INSTR1, 11)
check("SUB(KINT(0), instr) -> keep",    -1, ref_sub0l)

-- =========================================================================
-- 3. Keep (no fold applicable)
-- =========================================================================
print("\n--- Keep ---")

-- ADD(INSTR1, INSTR2) -> keep (two non-const refs, not identity)
local ref_keep = fold_test_fn(J_ptr, IR_ptr, INSTR1, INSTR2, 10)
check("ADD(instr, instr) -> keep",      -1, ref_keep)

-- =========================================================================
-- 4. Commutative normalization
-- =========================================================================
print("\n--- Commutative normalization ---")

-- ADD(INSTR2, INSTR1): op1 > op2 → normalized(INSTR1, INSTR2)
-- fold_test encodes as -200000 + new_op1
local ref_norm = fold_test_fn(J_ptr, IR_ptr, INSTR2, INSTR1, 10)
check("ADD(large, small) normalized",   -200000 + INSTR1, ref_norm)

-- ADD(INSTR1, INSTR2): op1 <= op2 → keep (already in order)
local ref_norm_ok = fold_test_fn(J_ptr, IR_ptr, INSTR1, INSTR2, 10)
check("ADD(small, large) -> keep",      -1, ref_norm_ok)

-- =========================================================================
-- Results
-- =========================================================================
fold:free()
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All fold integration tests passed")
