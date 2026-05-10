-- tests/test_trace_recorder_expanded.lua
-- Tests for the expanded recorder: comparisons, DIV/MOD, ADDVN, FORI/FORL, RET0, KPRI.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Run = require("moonlift.mlua_run")

local trace_mv = Run.dofile("mlua/luajitvm/jit/trace.mlua")
local trace = trace_mv:compile()

local function setup_J(nslots)
    local J     = ffi.new("uint8_t[?]", 88)
    local TR    = ffi.new("uint8_t[?]", 104)
    local IR    = ffi.new("uint64_t[?]", 0x8000)
    local SNAP  = ffi.new("uint8_t[?]", 16 * 32)
    local SMAP  = ffi.new("int32_t[?]", 256)
    local REFS  = ffi.new("int32_t[?]", 32)
    local A     = ffi.new("uint8_t[?]", 256)
    local L     = ffi.new("uint8_t[?]", 128)
    local STACK = ffi.new("uint8_t[?]", 16 * (nslots or 16))
    local J64   = ffi.cast("uint64_t *", J)
    local TR64  = ffi.cast("uint64_t *", TR)
    local TR16  = ffi.cast("uint16_t *", TR)
    J64[0] = tonumber(ffi.cast("uintptr_t", TR))
    J64[4] = 0  -- no mcode (no asm)
    J64[7] = tonumber(ffi.cast("uintptr_t", REFS))
    J64[8] = tonumber(ffi.cast("uintptr_t", A))
    TR64[3] = tonumber(ffi.cast("uintptr_t", IR))
    TR64[5] = tonumber(ffi.cast("uintptr_t", SNAP))
    TR64[6] = tonumber(ffi.cast("uintptr_t", SMAP))
    TR16[47] = 1
    ffi.cast("uint64_t *", L)[4] = tonumber(ffi.cast("uintptr_t", STACK))
    return J, L, STACK, IR, REFS, TR
end

local function bc_abc(op, a, b, c)  return op + a*256 + c*65536 + b*16777216 end
local function bc_asd(op, a, d)     local ud = d; if ud < 0 then ud = ud+65536 end; return op + a*256 + ud*65536 end
local function set_int(STACK, slot, v)
    ffi.cast("int32_t *", STACK)[slot*4] = 3
    ffi.cast("int64_t *", STACK)[slot*2+1] = v
end

local passed, failed = 0, 0
local function check(name, exp, got)
    if exp == got then passed = passed + 1; io.write(("  OK   %-28s = %s\n"):format(name, tostring(got)))
    else failed = failed + 1; io.write(("  FAIL %-28s expected %s got %s\n"):format(name, tostring(exp), tostring(got))) end
end

-- -----------------------------------------------------------------------
-- 1. Comparison guard records IR_LT
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(4)
    set_int(STACK, 0, 3)
    set_int(STACK, 1, 10)
    local BC = ffi.new("uint32_t[?]", 4)
    BC[0] = bit.bor(0, bit.lshift(0, 24), bit.lshift(1, 16))  -- ISLT B=0 C=1
    BC[1] = 85  -- LOOP (end trace)
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("islt_record rc", 1, rc)
-- Fix islt nins check: TR_OFF_NINS is at byte 16 (u32[4]) = u16[8]
    check("islt nins", 5, ffi.cast("uint16_t *", TR)[8])
end

-- -----------------------------------------------------------------------
-- 2. ADDVN recorder: slot + literal constant
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(4)
    set_int(STACK, 0, 7)
    local BC = ffi.new("uint32_t[?]", 4)
    -- ADDVN A=1 B=0 D=5  (slot1 = slot0 + 5)
    BC[0] = 22 + (1*256) + (0*16777216) + (5*65536)
    BC[1] = bc_abc(76, 1, 0, 0)  -- RET1 A=1
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("addvn_record rc", 1, rc)
end

-- -----------------------------------------------------------------------
-- 3. DIVVV recorder
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(4)
    set_int(STACK, 0, 20)
    set_int(STACK, 1, 4)
    local BC = ffi.new("uint32_t[?]", 4)
    BC[0] = bc_abc(35, 2, 0, 1)  -- DIVVV A=2 B=0 C=1
    BC[1] = bc_abc(76, 2, 0, 0)  -- RET1 A=2
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("divvv_record rc", 1, rc)
end

-- -----------------------------------------------------------------------
-- 4. MODVV recorder
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(4)
    set_int(STACK, 0, 17)
    set_int(STACK, 1, 5)
    local BC = ffi.new("uint32_t[?]", 4)
    BC[0] = bc_abc(36, 2, 0, 1)  -- MODVV A=2 B=0 C=1
    BC[1] = bc_abc(76, 2, 0, 0)  -- RET1 A=2
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("modvv_record rc", 1, rc)
end

-- -----------------------------------------------------------------------
-- 5. KPRI recorder (nil as KINT 0)
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(4)
    set_int(STACK, 0, 1)
    local BC = ffi.new("uint32_t[?]", 4)
    BC[0] = bc_asd(43, 1, 0)      -- KPRI A=1 D=0 (nil)
    BC[1] = bc_abc(76, 1, 0, 0)   -- RET1 A=1
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("kpri_record rc", 1, rc)
end

-- -----------------------------------------------------------------------
-- 6. FORI/FORL loop recorder
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(8)
    set_int(STACK, 0, 1)   -- index
    set_int(STACK, 1, 10)  -- limit
    set_int(STACK, 2, 1)   -- step
    set_int(STACK, 3, 1)   -- loopvar (will be ref-copied from index)
    set_int(STACK, 4, 0)   -- accumulator slot (initialized)
    local BC = ffi.new("uint32_t[?]", 8)
    BC[0] = bc_asd(77, 0, 3)            -- FORI A=0 D=3
    BC[1] = bc_abc(32, 4, 4, 3)         -- ADDVV A=4 B=4 C=3 (acc += loopvar)
    BC[2] = bc_asd(79, 0, -2)           -- FORL A=0 D=-2
    BC[3] = bc_abc(76, 4, 0, 0)         -- RET1 A=4
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("fori_forl_record rc", 1, rc)
end

-- -----------------------------------------------------------------------
-- 7. RET0 recorder
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(4)
    local BC = ffi.new("uint32_t[?]", 4)
    BC[0] = 75  -- RET0
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("ret0_record rc", 1, rc)
end

-- -----------------------------------------------------------------------
-- 8. KNUM integer constant from current proto constants
-- -----------------------------------------------------------------------
do
    local J, L, STACK, IR, REFS, TR = setup_J(4)
    local proto = ffi.new("uint8_t[?]", 96 + 4*4)
    local k = ffi.new("uint8_t[?]", 16)
    ffi.cast("uint64_t *", proto)[3] = tonumber(ffi.cast("uintptr_t", k))
    ffi.cast("int32_t *", k)[0] = 3
    ffi.cast("int64_t *", k)[1] = 99
    local BC = ffi.cast("uint32_t *", proto + 96)
    BC[0] = bc_asd(42, 1, 0)        -- KNUM A=1 D=0
    BC[1] = bc_abc(76, 1, 0, 0)    -- RET1 A=1
    ffi.cast("uint64_t *", L)[12] = tonumber(ffi.cast("uintptr_t", BC)) -- L->curbc
    local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
    check("knum_record rc", 1, rc)
end

-- -----------------------------------------------------------------------
-- 9. More literal arithmetic variants: DIVVN/MODVN/ADDNV/SUBNV/MULNV/DIVNV/MODNV
-- -----------------------------------------------------------------------
do
    local ops = {
        {"divvn_record rc", 25}, {"modvn_record rc", 26},
        {"addnv_record rc", 27}, {"subnv_record rc", 28}, {"mulnv_record rc", 29},
        {"divnv_record rc", 30}, {"modnv_record rc", 31},
    }
    for _, it in ipairs(ops) do
        local J, L, STACK, IR, REFS, TR = setup_J(4)
        set_int(STACK, 0, 20)
        local BC = ffi.new("uint32_t[?]", 4)
        BC[0] = it[2] + (1*256) + (0*16777216) + (5*65536)
        BC[1] = bc_abc(76, 1, 0, 0)
        local rc = trace:get("trace_record_root_test")(ffi.cast("void*",J), ffi.cast("void*",L), ffi.cast("void*",BC))
        check(it[1], 1, rc)
    end
end

trace:free()

if failed > 0 then error(failed .. " recorder expansion tests FAILED") end
print(string.format("recorder expansion ok (%d passed)", passed))
