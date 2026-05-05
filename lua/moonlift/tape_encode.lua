-- tape_encode.lua — Flatten MoonBack.BackProgram → tape arrays
--
-- Each BackCmd variant gets an integer tag. BackValIds become register indices.
-- BackBlockIds resolve to PC (tape position). Tags and sub-variant opcodes are
-- fully flattened — no secondary dispatch.
--
-- Output per function: { tape, entry_pc, entry_regs, reg_names }

local pvm = require("moonlift.pvm")

-- ═══════════════════════════════════════════════════════════
-- Tag constants — flat namespace, one integer per variant
-- ═══════════════════════════════════════════════════════════

local T = {
    CONST_INT = 1,    CONST_FLT = 2,    CONST_BOOL = 3,   CONST_NULL = 4,

    IADD = 10,  ISUB = 11,  IMUL = 12,  SDIV = 13,  UDIV = 14,  SREM = 15,  UREM = 16,
    BAND = 20,  BOR = 21,   BXOR = 22,  BNOT = 23,   ISHL = 24,
    SSHR = 25,  USHR = 26,  ROTL = 27,  ROTR = 28,
    FADD = 30,  FSUB = 31,  FMUL = 32,  FDIV = 33,

    ICMP_EQ = 40,  ICMP_NE = 41,
    SCMP_LT = 42,  SCMP_LE = 43,  SCMP_GT = 44,  SCMP_GE = 45,
    UCMP_LT = 46,  UCMP_LE = 47,  UCMP_GT = 48,  UCMP_GE = 49,
    FCMP_EQ = 50,  FCMP_NE = 51,  FCMP_LT = 52,  FCMP_LE = 53,
    FCMP_GT = 54,  FCMP_GE = 55,

    BITCAST = 60,  IREDUCE = 61,  SEXTEND = 62,  UEXTEND = 63,
    FPROMOTE = 64,  FDEMOTE = 65,  STOF = 66,  UTOF = 67,  FTOS = 68,  FTOU = 69,

    INEG = 70,  FNEG = 71,  BOOLNOT = 72,

    POPCOUNT = 80,  CLZ = 81,  CTZ = 82,  BSWAP = 83,
    SQRT = 84,  ABS_INT = 85,  ABS_FLT = 86,  FLOOR = 87,  CEIL = 88,
    TRUNC = 89,  ROUND = 90,

    JUMP = 100,  BR_IF = 101,  SWITCH = 102,
    RETURN_VOID = 103,  RETURN_VALUE = 104,  TRAP = 105,

    LOAD = 110,  STORE = 111,  PTR_OFFSET = 112,
    MEMCPY = 113,  MEMSET = 114,
    STACK_ADDR = 120,  DATA_ADDR = 121,

    CALL_DIR = 130,  CALL_EXT = 131,  CALL_IND = 132,
    CALL_DIR_STMT = 133,  CALL_EXT_STMT = 134,  CALL_IND_STMT = 135,

    ALIAS = 140,  SELECT = 150,  FMA = 151,  BLOCK_ARG = 160,
}

-- Narrowing masks by scalar type
local narrow_masks = {
    I8 = 0xFF, U8 = 0xFF, I16 = 0xFFFF, U16 = 0xFFFF,
    I32 = 0xFFFFFFFF, U32 = 0xFFFFFFFF,
}

local function scalar_name(s)
    local kind = pvm.classof(s).kind
    return kind and kind:gsub("^Back", "") or "I32"
end

local function id_text(id)
    if type(id) == "string" then return id end
    return id.text
end

-- ═══════════════════════════════════════════════════════════
-- Int comparison op → tag
-- ═══════════════════════════════════════════════════════════

local icmp_tags = {}
local function build_icmp_tags(Back)
    icmp_tags = {
        [Back.BackIcmpEq]  = T.ICMP_EQ,  [Back.BackIcmpNe]  = T.ICMP_NE,
        [Back.BackSIcmpLt] = T.SCMP_LT,  [Back.BackSIcmpLe] = T.SCMP_LE,
        [Back.BackSIcmpGt] = T.SCMP_GT,  [Back.BackSIcmpGe] = T.SCMP_GE,
        [Back.BackUIcmpLt] = T.UCMP_LT,  [Back.BackUIcmpLe] = T.UCMP_LE,
        [Back.BackUIcmpGt] = T.UCMP_GT,  [Back.BackUIcmpGe] = T.UCMP_GE,
    }
end

local fcmp_tags = {}
local function build_fcmp_tags(Back)
    fcmp_tags = {
        [Back.BackFCmpEq]  = T.FCMP_EQ,  [Back.BackFCmpNe]  = T.FCMP_NE,
        [Back.BackFCmpLt]  = T.FCMP_LT,  [Back.BackFCmpLe]  = T.FCMP_LE,
        [Back.BackFCmpGt]  = T.FCMP_GT,  [Back.BackFCmpGe]  = T.FCMP_GE,
    }
end

-- ═══════════════════════════════════════════════════════════
-- Encoder
-- ═══════════════════════════════════════════════════════════

function M.encode(program)
    local Back = require("moonlift.back_validate") -- just for the Back namespace
    -- Actually we get Back from T context. Let me restructure.
end

return M
