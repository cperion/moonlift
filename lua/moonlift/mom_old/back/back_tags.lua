-- MOM backend tag constants.
--
-- Single source of truth: all schema-derived tags come from protocol_variants.
-- Tags = variant array index - 1 (self-variant at index 1 is tag 0, unused).
-- Schema variant names are used verbatim — they are unique across all unions.
--
-- Naming convention preserves schema names exactly:
--   Cmd variants:     CmdTargetModel, CmdCreateSig, CmdTrap, ...
--   BackScalar:       BackVoid, BackBool, BackI32, BackF64, BackPtr, ...
--   BackIntOp:        BackIntAdd, BackIntSub, ...
--   BackCompareOp:    BackIcmpEq, BackSICmpLt, BackFCmpGe, ...
--   BackCastOp:       BackBitcast, BackIreduce, BackSextend, ...
--   BackValidationIssue: BackIssueEmptyProgram, BackIssueMissingFinalize, ...
--   MoonCore Scalars: ScalarVoid, ScalarBool, ScalarI32, ...
--   MoonCore BinaryOp: BinAdd, BinSub, BinMul, ...
--   MoonCore CmpOp:   CmpEq, CmpNe, CmpLt, ...
--   MoonCore UnaryOp: UnaryNeg, UnaryNot, UnaryBitNot
--
-- Non-schema enums (MachineCastOp, SurfaceCastOp, tokens, etc.) are explicit
-- with documentation of their authoritative source.

local M = {}

local Host = require("moonlift.mlua_run")
local MB = Host.dofile("lua/moonlift/mom/schema/MoonBack.mlua")
local MC = Host.dofile("lua/moonlift/mom/schema/MoonCore.mlua")

local function derive(union)
    local t = {}
    local variants = union.protocol_variants
    for i, v in ipairs(variants) do
        local tag = i - 1
        if tag > 0 then
            t[v.name] = tag
        end
    end
    return t
end

-- ── BackCmd tags (from MoonBack.Cmd) ─────────────────────────────────

for k, v in pairs(derive(MB.Cmd)) do M[k] = v end

-- ── BackScalar tags (from MoonBack.BackScalar) ────────────────────────

for k, v in pairs(derive(MB.BackScalar)) do M[k] = v end

-- ── Back op tags (from MoonBack op unions) ───────────────────────────

for k, v in pairs(derive(MB.BackIntOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackBitOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackShiftOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackRotateOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackFloatOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackUnaryOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackCompareOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackCastOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackShape)) do M[k] = v end
for k, v in pairs(derive(MB.BackIntrinsicOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackVecBinaryOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackVecCompareOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackVecMaskOp)) do M[k] = v end
for k, v in pairs(derive(MB.BackValidationIssue)) do M[k] = v end

-- ── MoonCore tags ─────────────────────────────────────────────────────

for k, v in pairs(derive(MC.Scalar)) do M[k] = v end
for k, v in pairs(derive(MC.BinaryOp)) do M[k] = v end
for k, v in pairs(derive(MC.CmpOp)) do M[k] = v end
for k, v in pairs(derive(MC.UnaryOp)) do M[k] = v end
for k, v in pairs(derive(MC.AtomicOrdering)) do M[k] = v end
for k, v in pairs(derive(MC.AtomicRmwOp)) do M[k] = v end

-- ── MachineCastOp tags (surface→machine cast lowering) ───────────────
-- Authoritative source: lua/moonlift/mom/back/ops.mlua mb_lower_surface_cast_op

M.MC_IDENTITY = 1
M.MC_BITCAST = 2
M.MC_IREDUCE = 3
M.MC_SEXTEND = 4
M.MC_UEXTEND = 5
M.MC_FPROMOTE = 6
M.MC_FDEMOTE = 7
M.MC_STOF = 8
M.MC_UTOF = 9
M.MC_FTOS = 10
M.MC_FTOU = 11

-- ── Binary command class tags (dispatch helper) ──────────────────────
-- Authoritative source: lua/moonlift/mom/back/ops.mlua mb_binary_class

M.MB_BIN_INVALID = 0
M.MB_BIN_INT = 1
M.MB_BIN_FLOAT = 2
M.MB_BIN_BIT = 3
M.MB_BIN_SHIFT = 4

-- ── SurfaceCastOp tags ────────────────────────────────────────────────
-- Authoritative source: lua/moonlift/mom/back/ops.mlua mb_lower_surface_cast_op

M.SC_SURFACE_CAST = 1
M.SC_TRUNC = 2
M.SC_ZEXT = 3
M.SC_SEXT = 4
M.SC_BITCAST = 5
M.SC_SAT_CAST = 6

-- ── Type union tags (from MoonCyclic.Type) ────────────────────────────
-- Authoritative source: lua/moonlift/mom/schema/MoonCyclic.mlua

M.TY_SCALAR = 1
M.TY_PTR = 2
M.TY_ARRAY = 3
M.TY_SLICE = 4
M.TY_VIEW = 5
M.TY_FUNC = 6
M.TY_CLOSURE = 7
M.TY_NAMED = 8
M.TY_SLOT = 9
M.TY_CTYPE = 10
M.TY_CFUNC_PTR = 11

-- ── AbiClass tags (from MoonType schema) ──────────────────────────────
-- Authoritative source: lua/moonlift/schema/type.lua line 155

M.ABI_IGNORE = 1
M.ABI_DIRECT = 2
M.ABI_INDIRECT = 3
M.ABI_DESCRIPTOR = 4
M.ABI_UNKNOWN = 5

-- ── AbiParamPlan tags (from MoonType schema) ──────────────────────────
-- Authoritative source: lua/moonlift/schema/type.lua line 181

M.ABI_PARAM_SCALAR = 1
M.ABI_PARAM_VIEW = 2
M.ABI_PARAM_REJECTED = 3

-- ── AbiResultPlan tags (from MoonType schema) ─────────────────────────
-- Authoritative source: lua/moonlift/schema/type.lua line 205

M.ABI_RESULT_VOID = 1
M.ABI_RESULT_SCALAR = 2
M.ABI_RESULT_VIEW = 3
M.ABI_RESULT_REJECTED = 4

-- ── Token kind tags ──────────────────────────────────────────────────
-- Authoritative source: lua/moonlift/mom/parser/native_lexer.mlua

M.TK_EOF = 0
M.TK_NAME = 1
M.TK_INT = 2
M.TK_FLOAT = 3
M.TK_STRING = 4
M.TK_NL = 5
M.TK_HOLE = 6
M.TK_INVALID = 7
M.TK_LPAREN = 10
M.TK_RPAREN = 11
M.TK_LBRACK = 12
M.TK_RBRACK = 13
M.TK_COMMA = 16
M.TK_COLON = 17
M.TK_DOT = 18
M.TK_SEMI = 19
M.TK_PLUS = 20
M.TK_MINUS = 21
M.TK_STAR = 22
M.TK_SLASH = 23
M.TK_PERCENT = 24
M.TK_EQEQ = 27
M.TK_NE = 28
M.TK_LT = 29
M.TK_LE = 30
M.TK_GT = 31
M.TK_GE = 32
M.TK_AMP = 33
M.TK_PIPE = 34
M.TK_CARET = 35
M.TK_TILDE = 36
M.TK_SHL = 37
M.TK_LSHR = 38
M.TK_ASHR = 39
M.TK_EQ = 25
M.TK_ARROW = 26
M.TK_AND = 143
M.TK_OR = 144
M.TK_NOT = 145
M.TK_VIEW = 150
M.TK_AS = 170
M.TK_FUNC = 102
M.TK_STRUCT = 180
M.TK_UNION = 181
M.TK_EXTERN = 182
M.TK_LET = 110
M.TK_VAR = 111
M.TK_IF = 112
M.TK_THEN = 113
M.TK_ELSEIF = 114
M.TK_ELSE = 115
M.TK_SWITCH = 116
M.TK_CASE = 117
M.TK_DEFAULT = 118
M.TK_DO = 119
M.TK_END = 120
M.TK_BLOCK = 130
M.TK_JUMP = 132
M.TK_YIELD = 133
M.TK_RETURN = 134
M.TK_REGION = 135
M.TK_ENTRY = 136
M.TK_EMIT = 137
M.TK_EXPR = 138
M.TK_TRUE = 140
M.TK_FALSE = 141
M.TK_NIL = 142
M.TK_NOT = 145

-- ── Expr/Stmt tags ───────────────────────────────────────────────────
-- Authoritative source: lua/moonlift/mom/parser/native_core.mlua

M.EX_LIT = 1
M.EX_REF = 2
M.EX_UNARY = 3
M.EX_BINARY = 4
M.EX_COMPARE = 5
M.EX_LOGIC = 6
M.EX_CAST = 7
M.EX_CALL = 8
M.EX_SELECT = 9
M.EX_DOT = 10
M.EX_INDEX = 11
M.EX_DEREF = 12
M.EX_ADDR = 13
M.EX_LEN = 14
M.EX_VIEW = 15
M.EX_IF = 16
M.EX_HOLE = 17
M.EX_SWITCH = 18
M.EX_CONTROL = 19
M.EX_BAD = 0

M.ST_LET = 1
M.ST_VAR = 2
M.ST_SET = 3
M.ST_EXPR = 4
M.ST_IF = 5
M.ST_RETURN_VOID = 6
M.ST_RETURN_VALUE = 7
M.ST_SWITCH = 8
M.ST_JUMP = 9
M.ST_YIELD = 10
M.ST_EMIT = 11

M.CF_ENTRY_BLOCK = 1
M.CF_BLOCK = 2
M.CF_ENTRY_PARAM = 3
M.CF_BLOCK_PARAM = 4
M.CF_JUMP = 5
M.CF_JUMP_ARG = 6
M.CF_YIELD_VOID = 7
M.CF_YIELD_VALUE = 8
M.CF_RETURN = 9
M.CF_BACKEDGE = 10

-- ── VecFact/VecDecision/VecPlan tags ─────────────────────────────────
-- Authoritative source: lua/moonlift/mom/vec/*.mlua

M.VF_DOMAIN_COUNTED = 1
M.VF_PRIMARY_INDUCTION = 2
M.VF_REDUCTION_ADD = 10
M.VF_REDUCTION_MUL = 11
M.VF_REDUCTION_XOR = 14
M.VF_MEMORY_LOAD = 20
M.VF_MEMORY_STORE = 21
M.VF_REJECT = 99

M.VD_LEGAL = 1
M.VD_ILLEGAL = 2

M.VP_NO_PLAN = 1
M.VP_REDUCE = 2
M.VP_MAP = 3
M.VP_ALGEBRAIC = 4

-- ── Control reject/decision tags ──────────────────────────────────────
-- Authoritative source: lua/moonlift/mom/back/control.mlua

M.CR_DUPLICATE_LABEL = 1
M.CR_MISSING_LABEL = 2
M.CR_MISSING_JUMP_ARG = 3
M.CR_EXTRA_JUMP_ARG = 4
M.CR_DUPLICATE_JUMP_ARG = 5
M.CR_JUMP_TYPE = 6
M.CR_YIELD_OUTSIDE = 7
M.CR_YIELD_TYPE = 8
M.CR_UNTERMINATED_BLOCK = 9

M.CD_REDUCIBLE = 1
M.CD_IRREDUCIBLE = 2

-- ── Type arena tags (from native_tree.mlua MomTreeOut) ─────────────────
-- These are stable semantic-node tags matching the MomTreeOut parallel arrays.

M.MT_BAD = 0
M.MT_SCALAR = 1
M.MT_NAMED = 2
M.MT_PTR = 3
M.MT_VIEW = 4
M.MT_FUNC = 5
M.MT_CLOSURE = 6
M.MT_SLOT = 7

-- ── Expr arena tags (from native_tree.mlua ME_* constants) ──────────────

M.ME_BAD = 0
M.ME_LIT = 1
M.ME_REF = 2
M.ME_UNARY = 3
M.ME_BINARY = 4
M.ME_COMPARE = 5
M.ME_LOGIC = 6
M.ME_CAST = 7
M.ME_CALL = 8
M.ME_SELECT = 9
M.ME_DOT = 10
M.ME_INDEX = 11
M.ME_DEREF = 12
M.ME_ADDR_OF = 13
M.ME_LEN = 14
M.ME_VIEW = 15
M.ME_IF = 16
M.ME_HOLE = 17
M.ME_SWITCH = 18
M.ME_CONTROL = 19

-- ── Stmt arena tags (from native_tree.mlua MS_* constants) ──────────────

M.MS_BAD = 0
M.MS_LET = 1
M.MS_VAR = 2
M.MS_SET = 3
M.MS_EXPR = 4
M.MS_IF = 5
M.MS_RETURN_VOID = 6
M.MS_RETURN_VALUE = 7
M.MS_YIELD_VOID = 8
M.MS_YIELD_VALUE = 9
M.MS_JUMP = 10
M.MS_CONTROL = 11
M.MS_USE_REGION = 12
M.MS_SWITCH = 13

-- ── Item arena tags (from native_tree.mlua IT_* constants) ──────────────

M.IT_FUNC = 1
M.IT_EXTERN = 2
M.IT_STRUCT = 3
M.IT_UNION = 4
M.IT_REGION = 5
M.IT_EXPR_FRAG = 6

-- ── Type union tags (from MoonCyclic.Type, MoonBack.TY_*) ─────────────
-- (already defined above at line 108)

return M