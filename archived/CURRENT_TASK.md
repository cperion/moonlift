# CURRENT TASK

## Global Context
<!-- Rename all tag constants from old prefixed names to schema-verbatim names across all MOM backend .mlua files. The back_tags.lua module has already been updated to export schema-verbatim names.

The mapping is:
- CMD_* → Cmd* (e.g., CMD_TRAP → CmdTrap, CMD_CREATE_BLOCK → CmdCreateBlock)
- B_* → Back* for scalars (e.g., B_I32 → BackI32, B_BOOL → BackBool, B_F64 → BackF64, B_PTR → BackPtr, B_INDEX → BackIndex, B_VOID → BackVoid, B_F32 → BackF32, B_I8 → BackI8, B_I16 → BackI16, B_I64 → BackI64, B_U8 → BackU8, B_U16 → BackU16, B_U32 → BackU32, B_U64 → BackU64)
- BACK_* → Back* for backend ops (e.g., BACK_INT_ADD → BackIntAdd, BACK_FCMP_EQ → BackFCmpEq, BACK_SICMP_LT → BackSIcmpLt, BACK_UICMP_LT → BackUIcmpLt, BACK_UNARY_FNEG → BackUnaryFneg, BACK_UNARY_INEG → BackUnaryIneg, BACK_UNARY_BOOL_NOT → BackUnaryBoolNot, BACK_UNARY_BNOT → BackUnaryBnot, BACK_FLOAT_ADD → BackFloatAdd, BACK_BIT_AND → BackBitAnd, BACK_SHIFT_LEFT → BackShiftLeft, BACK_SHIFT_LOGICAL_RIGHT → BackShiftLogicalRight, BACK_SHIFT_ARITHMETIC_RIGHT → BackShiftArithmeticRight, BACK_INT_SUB → BackIntSub, BACK_INT_MUL → BackIntMul, BACK_INT_SDIV → BackIntSDiv, BACK_INT_SREM → BackIntSRem, BACK_BIT_OR → BackBitOr, BACK_BIT_XOR → BackBitXor, BACK_FLOAT_SUB → BackFloatSub, BACK_FLOAT_MUL → BackFloatMul, BACK_FLOAT_DIV → BackFloatDiv, BACK_BITCAST → BackBitcast, BACK_IREDUCE → BackIreduce, BACK_SEXTEND → BackSextend, BACK_UEXTEND → BackUextend, BACK_FPROMOTE → BackFpromote, BACK_FDEMOTE → BackFdemote, BACK_STOF → BackSToF, BACK_UTOF → BackUToF, BACK_FTOS → BackFToS, BACK_FTOU → BackFToU)
- BIN_* → Bin* (BIN_ADD → BinAdd, BIN_SUB → BinSub, BIN_MUL → BinMul, BIN_DIV → BinDiv, BIN_REM → BinRem, BIN_BIT_AND → BinBitAnd, BIN_BIT_OR → BinBitOr, BIN_BIT_XOR → BinBitXor, BIN_SHL → BinShl, BIN_LSHR → BinLShr, BIN_ASHR → BinAShr)
- CMP_* → Cmp* (CMP_EQ → CmpEq, CMP_NE → CmpNe, CMP_LT → CmpLt, CMP_LE → CmpLe, CMP_GT → CmpGt, CMP_GE → CmpGe)
- U_* → Unary* (U_NEG → UnaryNeg, U_NOT → UnaryNot, U_BIT_NOT → UnaryBitNot)
- C_* → Scalar* for LalinCore scalars (C_VOID → ScalarVoid, C_BOOL → ScalarBool, C_I8 → ScalarI8, C_I16 → ScalarI16, C_I32 → ScalarI32, C_I64 → ScalarI64, C_U8 → ScalarU8, C_U16 → ScalarU16, C_U32 → ScalarU32, C_U64 → ScalarU64, C_F32 → ScalarF32, C_F64 → ScalarF64, C_RAWPTR → ScalarRawPtr, C_INDEX → ScalarIndex)
- ISS_* → BackIssue* (ISS_EMPTY_PROGRAM → BackIssueEmptyProgram, ISS_MISSING_FINALIZE → BackIssueMissingFinalize, ISS_CMD_AFTER_FINALIZE → BackIssueCommandAfterFinalize, ISS_CMD_OUTSIDE_FUNC → BackIssueCommandOutsideFunction, ISS_NESTED_FUNC → BackIssueNestedFunction, ISS_FINISH_WITHOUT_BEGIN → BackIssueFinishWithoutBegin, ISS_FINISH_WRONG_FUNC → BackIssueFinishWrongFunction, ISS_UNFINISHED_FUNC → BackIssueUnfinishedFunction, ISS_DUP_SIG → BackIssueDuplicateSig, ISS_DUP_DATA → BackIssueDuplicateData, ISS_DUP_FUNC → BackIssueDuplicateFunc, ISS_DUP_EXTERN → BackIssueDuplicateExtern, ISS_DUP_BLOCK → BackIssueDuplicateBlock, ISS_DUP_SLOT → BackIssueDuplicateStackSlot, ISS_DUP_VALUE → BackIssueDuplicateValue, ISS_MISSING_SIG → BackIssueMissingSig, ISS_MISSING_DATA → BackIssueMissingData, ISS_MISSING_FUNC → BackIssueMissingFunc, ISS_MISSING_EXTERN → BackIssueMissingExtern, ISS_MISSING_BLOCK → BackIssueMissingBlock, ISS_MISSING_SLOT → BackIssueMissingStackSlot, ISS_MISSING_VALUE → BackIssueMissingValue, ISS_DUP_ACCESS → BackIssueDuplicateAccess, ISS_MISSING_ACCESS → BackIssueMissingAccess)

Important notes:
- Inside @{T.XXX} splice expressions, change the reference name. E.g., @{T.CMD_TRAP} → @{T.CmdTrap}
- The MB_BIN_*, MC_*, SC_*, TK_*, EX_*, ST_*, CF_*, VF_*, VD_*, VP_*, CR_*, CD_* tags stay the same (they're already correctly named or non-schema)
- TY_* tags stay the same (LalinCyclic not derived yet)
- All files that use `local T = require("lalin.mom.back.back_tags")` keep the same import AI! -->

## Progress
<!-- KEEP THIS UPDATED: Check off items as you complete them -->
- [ ] Change T.CMD_TRAP to T.CmdTrap
- [ ] Change T.B_F32 to T.BackF32 and T.B_F64 to T.BackF64
- [ ] Change T.B_I8, T.B_I16, T.B_I32, T.B_I64 to T.BackI8, T.BackI16, T.BackI32, T.BackI64
- [ ] Change T.B_U8, T.B_U16, T.B_U32, T.B_U64, T.B_INDEX to T.BackU8, T.BackU16, T.BackU32, T.BackU64, T.BackIndex
- [ ] Change T.CMD_CREATE_SIG to T.CmdCreateSig
- [ ] Change T.CMD_DECLARE_DATA to T.CmdDeclareData
- [ ] Change T.CMD_DATA_INIT_ZERO to T.CmdDataInitZero
- [ ] Change T.CMD_DATA_INIT to T.CmdDataInit
- [ ] Change T.CMD_DATA_ADDR to T.CmdDataAddr
- [ ] Change T.CMD_FUNC_ADDR to T.CmdFuncAddr
- [ ] Change T.CMD_EXTERN_ADDR to T.CmdExternAddr
- [ ] Change T.CMD_DECLARE_FUNC to T.CmdDeclareFunc
- [ ] Change T.CMD_DECLARE_EXTERN to T.CmdDeclareExtern
- [ ] Change T.CMD_BEGIN_FUNC to T.CmdBeginFunc
- [ ] Change T.CMD_CREATE_BLOCK to T.CmdCreateBlock
- [ ] Change T.CMD_SWITCH_TO_BLOCK to T.CmdSwitchToBlock
- [ ] Change T.CMD_SEAL_BLOCK to T.CmdSealBlock
- [ ] Change T.CMD_BIND_ENTRY_PARAMS to T.CmdBindEntryParams
- [ ] Change T.CMD_APPEND_BLOCK_PARAM to T.CmdAppendBlockParam
- [ ] Change T.CMD_CREATE_STACK_SLOT to T.CmdCreateStackSlot
- [ ] Change T.CMD_ALIAS to T.CmdAlias
- [ ] Change T.CMD_STACK_ADDR to T.CmdStackAddr
- [ ] Change T.CMD_CONST to T.CmdConst
- [ ] Change T.CMD_INTRINSIC to T.CmdIntrinsic
- [ ] Change T.CMD_PTR_OFFSET to T.CmdPtrOffset
- [ ] Change T.CMD_INT_BINARY to T.CmdIntBinary
- [ ] Change T.CMD_FLOAT_BINARY to T.CmdFloatBinary
- [ ] Change T.CMD_BIT_BINARY to T.CmdBitBinary
- [ ] Change T.CMD_BIT_NOT to T.CmdBitNot
- [ ] Change T.CMD_SHIFT to T.CmdShift
- [ ] Change T.CMD_ROTATE to T.CmdRotate
- [ ] Change T.CMD_UNARY to T.CmdUnary
- [ ] Change T.CMD_COMPARE to T.CmdCompare
- [ ] Change T.CMD_CAST to T.CmdCast
- [ ] Change T.CMD_LOAD_INFO to T.CmdLoadInfo
- [ ] Change T.CMD_STORE_INFO to T.CmdStoreInfo
- [ ] Change T.CMD_MEMCPY to T.CmdMemcpy
- [ ] Change T.CMD_MEMSET to T.CmdMemset
- [ ] Change T.CMD_SELECT to T.CmdSelect
- [ ] Change T.CMD_FMA to T.CmdFma
- [ ] Change T.CMD_CALL to T.CmdCall
- [ ] Change T.CMD_JUMP to T.CmdJump
- [ ] Change T.CMD_BR_IF to T.CmdBrIf
- [ ] Change T.CMD_SWITCH_INT to T.CmdSwitchInt
- [ ] Change T.CMD_RETURN_VOID to T.CmdReturnVoid
- [ ] Change T.CMD_RETURN_VALUE to T.CmdReturnValue
- [ ] Change T.CMD_FINISH_FUNC to T.CmdFinishFunc
- [ ] Change T.CMD_FINALIZE_MODULE to T.CmdFinalizeModule
- [ ] Change T.CMD_TARGET_MODEL to T.CmdTargetModel
- [ ] Change T.BIN_ADD to T.BinAdd
- [ ] Change T.BACK_FLOAT_ADD to T.BackFloatAdd
- [ ] Change T.BACK_INT_ADD to T.BackIntAdd
- [ ] Change T.BIN_SUB to T.BinSub
- [ ] Change T.BACK_FLOAT_SUB to T.BackFloatSub
- [ ] Change T.BACK_INT_SUB to T.BackIntSub
- [ ] Change T.BIN_MUL to T.BinMul
- [ ] Change T.BACK_FLOAT_MUL to T.BackFloatMul
- [ ] Change T.BACK_INT_MUL to T.BackIntMul
- [ ] Change T.BIN_DIV to T.BinDiv
- [ ] Change T.BACK_FLOAT_DIV to T.BackFloatDiv
- [ ] Change T.BACK_INT_SDIV to T.BackIntSDiv
- [ ] Change T.BIN_REM to T.BinRem
- [ ] Change T.BACK_INT_SREM to T.BackIntSRem
- [ ] Change T.BIN_BIT_AND to T.BinBitAnd
- [ ] Change T.BACK_BIT_AND to T.BackBitAnd
- [ ] Change T.BIN_BIT_OR to T.BinBitOr
- [ ] Change T.BACK_BIT_OR to T.BackBitOr
- [ ] Change T.BIN_BIT_XOR to T.BinBitXor
- [ ] Change T.BACK_BIT_XOR to T.BackBitXor
- [ ] Change T.BIN_SHL to T.BinShl
- [ ] Change T.BACK_SHIFT_LEFT to T.BackShiftLeft
- [ ] Change T.BIN_LSHR to T.BinLShr
- [ ] Change T.BACK_SHIFT_LOGICAL_RIGHT to T.BackShiftLogicalRight
- [ ] Change T.BIN_ASHR to T.BinAShr
- [ ] Change T.BACK_SHIFT_ARITHMETIC_RIGHT to T.BackShiftArithmeticRight
- [ ] Change T.U_NEG to T.UnaryNeg
- [ ] Change T.BACK_UNARY_FNEG to T.BackUnaryFneg, T.BACK_UNARY_INEG to T.BackUnaryIneg
- [ ] Change T.U_NOT to T.UnaryNot
- [ ] Change T.BACK_UNARY_BOOL_NOT to T.BackUnaryBoolNot
- [ ] Change T.U_BIT_NOT to T.UnaryBitNot
- [ ] Change T.CMP_EQ to T.CmpEq
- [ ] Change T.BACK_FCMP_EQ to T.BackFCmpEq, T.BACK_ICMP_EQ to T.BackIcmpEq
- [ ] Change T.CMP_NE to T.CmpNe
- [ ] Change T.BACK_FCMP_NE to T.BackFCmpNe, T.BACK_ICMP_NE to T.BackIcmpNe
- [ ] Change T.CMP_LT to T.CmpLt
- [ ] Change T.BACK_FCMP_LT to T.BackFCmpLt, T.BACK_SICMP_LT to T.BackSIcmpLt, T.BACK_UICMP_LT to T.BackUIcmpLt
- [ ] Change T.CMP_LE to T.CmpLe
- [ ] Change T.BACK_FCMP_LE to T.BackFCmpLe, T.BACK_SICMP_LE to T.BackSIcmpLe, T.BACK_UICMP_LE to T.BackUIcmpLe
- [ ] Change T.CMP_GT to T.CmpGt
- [ ] Change T.BACK_FCMP_GT to T.BackFCmpGt, T.BACK_SICMP_GT to T.BackSIcmpGt, T.BACK_UICMP_GT to T.BackUIcmpGt
- [ ] Change T.CMP_GE to T.CmpGe
- [ ] Change T.BACK_FCMP_GE to T.BackFCmpGe, T.BACK_SICMP_GE to T.BackSIcmpGe, T.BACK_UICMP_GE to T.BackUIcmpGe
- [ ] Change T.MC_BITCAST to T.MC_BITCAST (MC_ stays same), T.BACK_BITCAST to T.BackBitcast
- [ ] Change T.MC_IREDUCE to T.MC_IREDUCE, T.BACK_IREDUCE to T.BackIreduce
- [ ] Change T.MC_SEXTEND to T.MC_SEXTEND, T.BACK_SEXTEND to T.BackSextend
- [ ] Change T.MC_UEXTEND to T.MC_UEXTEND, T.BACK_UEXTEND to T.BackUextend
- [ ] Change T.MC_FPROMOTE to T.MC_FPROMOTE, T.BACK_FPROMOTE to T.BackFpromote
- [ ] Change T.MC_FDEMOTE to T.MC_FDEMOTE, T.BACK_FDEMOTE to T.BackFdemote
- [ ] Change T.MC_STOF to T.MC_STOF, T.BACK_STOF to T.BackSToF
- [ ] Change T.MC_UTOF to T.MC_UTOF, T.BACK_UTOF to T.BackUToF
- [ ] Change T.MC_FTOS to T.MC_FTOS, T.BACK_FTOS to T.BackFToS
- [ ] Change T.MC_FTOU to T.MC_FTOU, T.BACK_FTOU to T.BackFToU

## Files Being Edited
- lua/lalin/mom/back/cmd.mlua

## Context Files
- lua/lalin/mom/back/cmd.mlua
- lua/lalin/mom/back/ops.mlua
- lua/lalin/mom/back/expr_lower.mlua
- lua/lalin/mom/back/stmt_lower.mlua
- lua/lalin/mom/back/validate.mlua
- lua/lalin/mom/back/control.mlua
- lua/lalin/mom/vec/vec_facts.mlua
- lua/lalin/mom/vec/vec_decide.mlua
- lua/lalin/mom/vec/vec_plan.mlua
- lua/lalin/mom/vec/vec_lower.mlua
