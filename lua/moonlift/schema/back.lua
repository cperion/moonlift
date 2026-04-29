-- Clean MoonBack schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonBack" {
        A.sum "BackScalar" {
            A.variant "BackVoid",
            A.variant "BackBool",
            A.variant "BackI8",
            A.variant "BackI16",
            A.variant "BackI32",
            A.variant "BackI64",
            A.variant "BackU8",
            A.variant "BackU16",
            A.variant "BackU32",
            A.variant "BackU64",
            A.variant "BackF32",
            A.variant "BackF64",
            A.variant "BackPtr",
            A.variant "BackIndex",
        },

        A.product "BackSigId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackFuncId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackExternId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackDataId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackBlockId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackValId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackStackSlotId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackSwitchCase" {
            A.field "raw" "string",
            A.field "dest" "MoonBack.BackBlockId",
            A.unique,
        },

        A.product "BackVec" {
            A.field "elem" "MoonBack.BackScalar",
            A.field "lanes" "number",
            A.unique,
        },

        A.sum "BackShape" {
            A.variant "BackShapeScalar" {
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "BackShapeVec" {
                A.field "vec" "MoonBack.BackVec",
                A.variant_unique,
            },
        },

        A.sum "BackTarget" {
            A.variant "BackTargetNative",
            A.variant "BackTargetCraneliftJit",
            A.variant "BackTargetNamed" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "BackEndian" {
            A.variant "BackEndianLittle",
            A.variant "BackEndianBig",
        },

        A.sum "BackTargetFeature" {
            A.variant "BackFeatureSSE2",
            A.variant "BackFeatureAVX2",
            A.variant "BackFeatureAVX512F",
            A.variant "BackFeatureFMA",
            A.variant "BackFeaturePOPCNT",
            A.variant "BackFeatureBMI1",
            A.variant "BackFeatureBMI2",
            A.variant "BackFeatureUnknown" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "BackTargetFact" {
            A.variant "BackTargetPointerBits" {
                A.field "bits" "number",
                A.variant_unique,
            },
            A.variant "BackTargetIndexBits" {
                A.field "bits" "number",
                A.variant_unique,
            },
            A.variant "BackTargetEndian" {
                A.field "endian" "MoonBack.BackEndian",
                A.variant_unique,
            },
            A.variant "BackTargetCacheLineBytes" {
                A.field "bytes" "number",
                A.variant_unique,
            },
            A.variant "BackTargetFeature" {
                A.field "feature" "MoonBack.BackTargetFeature",
                A.variant_unique,
            },
            A.variant "BackTargetSupportsShape" {
                A.field "shape" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "BackTargetSupportsVectorOp" {
                A.field "vec" "MoonBack.BackVec",
                A.field "op_class" "string",
                A.variant_unique,
            },
            A.variant "BackTargetSupportsMaskedTail",
            A.variant "BackTargetPrefersUnroll" {
                A.field "shape" "MoonBack.BackShape",
                A.field "unroll" "number",
                A.field "rank" "number",
                A.variant_unique,
            },
        },

        A.product "BackTargetModel" {
            A.field "target" "MoonBack.BackTarget",
            A.field "facts" (A.many "MoonBack.BackTargetFact"),
            A.unique,
        },

        A.sum "BackAddressBase" {
            A.variant "BackAddrValue" {
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "BackAddrStack" {
                A.field "slot" "MoonBack.BackStackSlotId",
                A.variant_unique,
            },
            A.variant "BackAddrData" {
                A.field "data" "MoonBack.BackDataId",
                A.variant_unique,
            },
        },

        A.sum "BackPointerProvenance" {
            A.variant "BackProvUnknown",
            A.variant "BackProvStack" {
                A.field "slot" "MoonBack.BackStackSlotId",
                A.variant_unique,
            },
            A.variant "BackProvData" {
                A.field "data" "MoonBack.BackDataId",
                A.variant_unique,
            },
            A.variant "BackProvArg" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "BackProvView" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "BackProvDerived" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "BackPointerBounds" {
            A.variant "BackPtrBoundsUnknown",
            A.variant "BackPtrInBounds" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackPtrMayLeaveObject" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "BackAddress" {
            A.field "base" "MoonBack.BackAddressBase",
            A.field "byte_offset" "MoonBack.BackValId",
            A.field "provenance" "MoonBack.BackPointerProvenance",
            A.field "formation_bounds" "MoonBack.BackPointerBounds",
            A.unique,
        },

        A.product "BackAccessId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "BackAliasScopeId" {
            A.field "text" "string",
            A.unique,
        },

        A.sum "BackAlignment" {
            A.variant "BackAlignUnknown",
            A.variant "BackAlignKnown" {
                A.field "bytes" "number",
                A.variant_unique,
            },
            A.variant "BackAlignAtLeast" {
                A.field "bytes" "number",
                A.variant_unique,
            },
            A.variant "BackAlignAssumed" {
                A.field "bytes" "number",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "BackDereference" {
            A.variant "BackDerefUnknown",
            A.variant "BackDerefBytes" {
                A.field "bytes" "number",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackDerefAssumed" {
                A.field "bytes" "number",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "BackTrap" {
            A.variant "BackMayTrap",
            A.variant "BackNonTrapping" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackChecked" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "BackMotion" {
            A.variant "BackMayNotMove",
            A.variant "BackCanMove" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "BackAccessMode" {
            A.variant "BackAccessRead",
            A.variant "BackAccessWrite",
            A.variant "BackAccessReadWrite",
        },

        A.product "BackMemoryInfo" {
            A.field "access" "MoonBack.BackAccessId",
            A.field "alignment" "MoonBack.BackAlignment",
            A.field "dereference" "MoonBack.BackDereference",
            A.field "trap" "MoonBack.BackTrap",
            A.field "motion" "MoonBack.BackMotion",
            A.field "mode" "MoonBack.BackAccessMode",
            A.unique,
        },

        A.sum "BackAliasFact" {
            A.variant "BackAliasUnknown" {
                A.field "a" "MoonBack.BackAccessId",
                A.field "b" "MoonBack.BackAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackMayAlias" {
                A.field "a" "MoonBack.BackAccessId",
                A.field "b" "MoonBack.BackAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackNoAlias" {
                A.field "a" "MoonBack.BackAccessId",
                A.field "b" "MoonBack.BackAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackSameBaseSameIndexSafe" {
                A.field "a" "MoonBack.BackAccessId",
                A.field "b" "MoonBack.BackAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackAliasScope" {
                A.field "access" "MoonBack.BackAccessId",
                A.field "scope" "MoonBack.BackAliasScopeId",
                A.variant_unique,
            },
        },

        A.sum "BackIntOverflow" {
            A.variant "BackIntWrap",
            A.variant "BackIntNoSignedWrap" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackIntNoUnsignedWrap" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackIntNoWrap" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "BackIntExact" {
            A.variant "BackIntMayLose",
            A.variant "BackIntExact" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "BackIntSemantics" {
            A.field "overflow" "MoonBack.BackIntOverflow",
            A.field "exact" "MoonBack.BackIntExact",
            A.unique,
        },

        A.sum "BackIntOp" {
            A.variant "BackIntAdd",
            A.variant "BackIntSub",
            A.variant "BackIntMul",
            A.variant "BackIntSDiv",
            A.variant "BackIntUDiv",
            A.variant "BackIntSRem",
            A.variant "BackIntURem",
        },

        A.sum "BackBitOp" {
            A.variant "BackBitAnd",
            A.variant "BackBitOr",
            A.variant "BackBitXor",
        },

        A.sum "BackShiftOp" {
            A.variant "BackShiftLeft",
            A.variant "BackShiftLogicalRight",
            A.variant "BackShiftArithmeticRight",
        },

        A.sum "BackRotateOp" {
            A.variant "BackRotateLeft",
            A.variant "BackRotateRight",
        },

        A.sum "BackFloatSemantics" {
            A.variant "BackFloatStrict",
            A.variant "BackFloatReassoc" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "BackFloatFastMath" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "BackFloatOp" {
            A.variant "BackFloatAdd",
            A.variant "BackFloatSub",
            A.variant "BackFloatMul",
            A.variant "BackFloatDiv",
        },

        A.sum "BackLiteral" {
            A.variant "BackLitInt" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "BackLitFloat" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "BackLitBool" {
                A.field "value" "boolean",
                A.variant_unique,
            },
            A.variant "BackLitNull",
        },

        A.sum "BackUnaryOp" {
            A.variant "BackUnaryIneg",
            A.variant "BackUnaryFneg",
            A.variant "BackUnaryBnot",
            A.variant "BackUnaryBoolNot",
        },

        A.sum "BackIntrinsicOp" {
            A.variant "BackIntrinsicPopcount",
            A.variant "BackIntrinsicClz",
            A.variant "BackIntrinsicCtz",
            A.variant "BackIntrinsicBswap",
            A.variant "BackIntrinsicSqrt",
            A.variant "BackIntrinsicAbs",
            A.variant "BackIntrinsicFloor",
            A.variant "BackIntrinsicCeil",
            A.variant "BackIntrinsicTruncFloat",
            A.variant "BackIntrinsicRound",
        },

        A.sum "BackCompareOp" {
            A.variant "BackIcmpEq",
            A.variant "BackIcmpNe",
            A.variant "BackSIcmpLt",
            A.variant "BackSIcmpLe",
            A.variant "BackSIcmpGt",
            A.variant "BackSIcmpGe",
            A.variant "BackUIcmpLt",
            A.variant "BackUIcmpLe",
            A.variant "BackUIcmpGt",
            A.variant "BackUIcmpGe",
            A.variant "BackFCmpEq",
            A.variant "BackFCmpNe",
            A.variant "BackFCmpLt",
            A.variant "BackFCmpLe",
            A.variant "BackFCmpGt",
            A.variant "BackFCmpGe",
        },

        A.sum "BackVecCompareOp" {
            A.variant "BackVecIcmpEq",
            A.variant "BackVecIcmpNe",
            A.variant "BackVecSIcmpLt",
            A.variant "BackVecSIcmpLe",
            A.variant "BackVecSIcmpGt",
            A.variant "BackVecSIcmpGe",
            A.variant "BackVecUIcmpLt",
            A.variant "BackVecUIcmpLe",
            A.variant "BackVecUIcmpGt",
            A.variant "BackVecUIcmpGe",
        },

        A.sum "BackVecBinaryOp" {
            A.variant "BackVecIntAdd",
            A.variant "BackVecIntSub",
            A.variant "BackVecIntMul",
            A.variant "BackVecBitAnd",
            A.variant "BackVecBitOr",
            A.variant "BackVecBitXor",
        },

        A.sum "BackVecMaskOp" {
            A.variant "BackVecMaskNot",
            A.variant "BackVecMaskAnd",
            A.variant "BackVecMaskOr",
        },

        A.sum "BackCastOp" {
            A.variant "BackBitcast",
            A.variant "BackIreduce",
            A.variant "BackSextend",
            A.variant "BackUextend",
            A.variant "BackFpromote",
            A.variant "BackFdemote",
            A.variant "BackSToF",
            A.variant "BackUToF",
            A.variant "BackFToS",
            A.variant "BackFToU",
        },

        A.sum "BackCallTarget" {
            A.variant "BackCallDirect" {
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackCallExtern" {
                A.field "func" "MoonBack.BackExternId",
                A.variant_unique,
            },
            A.variant "BackCallIndirect" {
                A.field "callee" "MoonBack.BackValId",
                A.variant_unique,
            },
        },

        A.sum "BackCallResult" {
            A.variant "BackCallStmt",
            A.variant "BackCallValue" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.variant_unique,
            },
        },

        A.sum "Cmd" {
            A.variant "CmdTargetModel" {
                A.field "target" "MoonBack.BackTargetModel",
                A.variant_unique,
            },
            A.variant "CmdCreateSig" {
                A.field "sig" "MoonBack.BackSigId",
                A.field "params" (A.many "MoonBack.BackScalar"),
                A.field "results" (A.many "MoonBack.BackScalar"),
                A.variant_unique,
            },
            A.variant "CmdDeclareData" {
                A.field "data" "MoonBack.BackDataId",
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "CmdDataInitZero" {
                A.field "data" "MoonBack.BackDataId",
                A.field "offset" "number",
                A.field "size" "number",
                A.variant_unique,
            },
            A.variant "CmdDataInit" {
                A.field "data" "MoonBack.BackDataId",
                A.field "offset" "number",
                A.field "ty" "MoonBack.BackScalar",
                A.field "value" "MoonBack.BackLiteral",
                A.variant_unique,
            },
            A.variant "CmdDataAddr" {
                A.field "dst" "MoonBack.BackValId",
                A.field "data" "MoonBack.BackDataId",
                A.variant_unique,
            },
            A.variant "CmdFuncAddr" {
                A.field "dst" "MoonBack.BackValId",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "CmdExternAddr" {
                A.field "dst" "MoonBack.BackValId",
                A.field "func" "MoonBack.BackExternId",
                A.variant_unique,
            },
            A.variant "CmdDeclareFunc" {
                A.field "visibility" "MoonCore.Visibility",
                A.field "func" "MoonBack.BackFuncId",
                A.field "sig" "MoonBack.BackSigId",
                A.variant_unique,
            },
            A.variant "CmdDeclareExtern" {
                A.field "func" "MoonBack.BackExternId",
                A.field "symbol" "string",
                A.field "sig" "MoonBack.BackSigId",
                A.variant_unique,
            },
            A.variant "CmdBeginFunc" {
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "CmdCreateBlock" {
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "CmdSwitchToBlock" {
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "CmdSealBlock" {
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "CmdBindEntryParams" {
                A.field "block" "MoonBack.BackBlockId",
                A.field "values" (A.many "MoonBack.BackValId"),
                A.variant_unique,
            },
            A.variant "CmdAppendBlockParam" {
                A.field "block" "MoonBack.BackBlockId",
                A.field "value" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "CmdCreateStackSlot" {
                A.field "slot" "MoonBack.BackStackSlotId",
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "CmdAlias" {
                A.field "dst" "MoonBack.BackValId",
                A.field "src" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdStackAddr" {
                A.field "dst" "MoonBack.BackValId",
                A.field "slot" "MoonBack.BackStackSlotId",
                A.variant_unique,
            },
            A.variant "CmdConst" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.field "value" "MoonBack.BackLiteral",
                A.variant_unique,
            },
            A.variant "CmdUnary" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackUnaryOp",
                A.field "ty" "MoonBack.BackShape",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdIntrinsic" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackIntrinsicOp",
                A.field "ty" "MoonBack.BackShape",
                A.field "args" (A.many "MoonBack.BackValId"),
                A.variant_unique,
            },
            A.variant "CmdCompare" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackCompareOp",
                A.field "ty" "MoonBack.BackShape",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdCast" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackCastOp",
                A.field "ty" "MoonBack.BackScalar",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdPtrOffset" {
                A.field "dst" "MoonBack.BackValId",
                A.field "base" "MoonBack.BackAddressBase",
                A.field "index" "MoonBack.BackValId",
                A.field "elem_size" "number",
                A.field "const_offset" "number",
                A.field "provenance" "MoonBack.BackPointerProvenance",
                A.field "bounds" "MoonBack.BackPointerBounds",
                A.variant_unique,
            },
            A.variant "CmdLoadInfo" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackShape",
                A.field "addr" "MoonBack.BackAddress",
                A.field "memory" "MoonBack.BackMemoryInfo",
                A.variant_unique,
            },
            A.variant "CmdStoreInfo" {
                A.field "ty" "MoonBack.BackShape",
                A.field "addr" "MoonBack.BackAddress",
                A.field "value" "MoonBack.BackValId",
                A.field "memory" "MoonBack.BackMemoryInfo",
                A.variant_unique,
            },
            A.variant "CmdIntBinary" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackIntOp",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "semantics" "MoonBack.BackIntSemantics",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdBitBinary" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackBitOp",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdBitNot" {
                A.field "dst" "MoonBack.BackValId",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdShift" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackShiftOp",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdRotate" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackRotateOp",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdFloatBinary" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackFloatOp",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "semantics" "MoonBack.BackFloatSemantics",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdAliasFact" {
                A.field "fact" "MoonBack.BackAliasFact",
                A.variant_unique,
            },
            A.variant "CmdMemcpy" {
                A.field "dst" "MoonBack.BackValId",
                A.field "src" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdMemset" {
                A.field "dst" "MoonBack.BackValId",
                A.field "byte" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdSelect" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackShape",
                A.field "cond" "MoonBack.BackValId",
                A.field "then_value" "MoonBack.BackValId",
                A.field "else_value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdFma" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.field "semantics" "MoonBack.BackFloatSemantics",
                A.field "a" "MoonBack.BackValId",
                A.field "b" "MoonBack.BackValId",
                A.field "c" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdVecSplat" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackVec",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdVecBinary" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackVecBinaryOp",
                A.field "ty" "MoonBack.BackVec",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdVecCompare" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackVecCompareOp",
                A.field "ty" "MoonBack.BackVec",
                A.field "lhs" "MoonBack.BackValId",
                A.field "rhs" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdVecSelect" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackVec",
                A.field "mask" "MoonBack.BackValId",
                A.field "then_value" "MoonBack.BackValId",
                A.field "else_value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdVecMask" {
                A.field "dst" "MoonBack.BackValId",
                A.field "op" "MoonBack.BackVecMaskOp",
                A.field "ty" "MoonBack.BackVec",
                A.field "args" (A.many "MoonBack.BackValId"),
                A.variant_unique,
            },
            A.variant "CmdVecInsertLane" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackVec",
                A.field "value" "MoonBack.BackValId",
                A.field "lane_value" "MoonBack.BackValId",
                A.field "lane" "number",
                A.variant_unique,
            },
            A.variant "CmdVecExtractLane" {
                A.field "dst" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.field "value" "MoonBack.BackValId",
                A.field "lane" "number",
                A.variant_unique,
            },
            A.variant "CmdCall" {
                A.field "result" "MoonBack.BackCallResult",
                A.field "target" "MoonBack.BackCallTarget",
                A.field "sig" "MoonBack.BackSigId",
                A.field "args" (A.many "MoonBack.BackValId"),
                A.variant_unique,
            },
            A.variant "CmdJump" {
                A.field "dest" "MoonBack.BackBlockId",
                A.field "args" (A.many "MoonBack.BackValId"),
                A.variant_unique,
            },
            A.variant "CmdBrIf" {
                A.field "cond" "MoonBack.BackValId",
                A.field "then_block" "MoonBack.BackBlockId",
                A.field "then_args" (A.many "MoonBack.BackValId"),
                A.field "else_block" "MoonBack.BackBlockId",
                A.field "else_args" (A.many "MoonBack.BackValId"),
                A.variant_unique,
            },
            A.variant "CmdSwitchInt" {
                A.field "value" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.field "cases" (A.many "MoonBack.BackSwitchCase"),
                A.field "default_dest" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "CmdReturnVoid",
            A.variant "CmdReturnValue" {
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "CmdTrap",
            A.variant "CmdFinishFunc" {
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "CmdFinalizeModule",
        },

        A.sum "BackShapeRequirement" {
            A.variant "BackShapeRequiresScalar",
            A.variant "BackShapeRequiresVector",
            A.variant "BackShapeAllowsScalarOrVector",
        },

        A.sum "BackProgramFact" {
            A.variant "BackFactCreateSig" {
                A.field "index" "number",
                A.field "sig" "MoonBack.BackSigId",
                A.variant_unique,
            },
            A.variant "BackFactSigRef" {
                A.field "index" "number",
                A.field "sig" "MoonBack.BackSigId",
                A.variant_unique,
            },
            A.variant "BackFactDeclareData" {
                A.field "index" "number",
                A.field "data" "MoonBack.BackDataId",
                A.variant_unique,
            },
            A.variant "BackFactDataRef" {
                A.field "index" "number",
                A.field "data" "MoonBack.BackDataId",
                A.variant_unique,
            },
            A.variant "BackFactDeclareFunc" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackFactFuncRef" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackFactDeclareExtern" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackExternId",
                A.variant_unique,
            },
            A.variant "BackFactExternRef" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackExternId",
                A.variant_unique,
            },
            A.variant "BackFactBeginFunc" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackFactFinishFunc" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackFactFinalizeModule" {
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BackFactCreateBlock" {
                A.field "index" "number",
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "BackFactBlockRef" {
                A.field "index" "number",
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "BackFactStackSlotDef" {
                A.field "index" "number",
                A.field "slot" "MoonBack.BackStackSlotId",
                A.variant_unique,
            },
            A.variant "BackFactStackSlotRef" {
                A.field "index" "number",
                A.field "slot" "MoonBack.BackStackSlotId",
                A.variant_unique,
            },
            A.variant "BackFactValueDef" {
                A.field "index" "number",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "BackFactValueUse" {
                A.field "index" "number",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "BackFactAccessDef" {
                A.field "index" "number",
                A.field "access" "MoonBack.BackAccessId",
                A.variant_unique,
            },
            A.variant "BackFactAccessRef" {
                A.field "index" "number",
                A.field "access" "MoonBack.BackAccessId",
                A.variant_unique,
            },
            A.variant "BackFactAliasAccessRef" {
                A.field "index" "number",
                A.field "access" "MoonBack.BackAccessId",
                A.variant_unique,
            },
            A.variant "BackFactShapeUse" {
                A.field "index" "number",
                A.field "shape" "MoonBack.BackShape",
                A.field "requirement" "MoonBack.BackShapeRequirement",
                A.variant_unique,
            },
            A.variant "BackFactFunctionBodyCommand" {
                A.field "index" "number",
                A.variant_unique,
            },
        },

        A.sum "BackValidationIssue" {
            A.variant "BackIssueEmptyProgram",
            A.variant "BackIssueMissingFinalize",
            A.variant "BackIssueCommandAfterFinalize" {
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BackIssueCommandOutsideFunction" {
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BackIssueNestedFunction" {
                A.field "index" "number",
                A.field "active" "MoonBack.BackFuncId",
                A.field "next" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackIssueFinishWithoutBegin" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackIssueFinishWrongFunction" {
                A.field "index" "number",
                A.field "expected" "MoonBack.BackFuncId",
                A.field "actual" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackIssueUnfinishedFunction" {
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateSig" {
                A.field "index" "number",
                A.field "sig" "MoonBack.BackSigId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateData" {
                A.field "index" "number",
                A.field "data" "MoonBack.BackDataId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateFunc" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateExtern" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackExternId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateBlock" {
                A.field "index" "number",
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateStackSlot" {
                A.field "index" "number",
                A.field "slot" "MoonBack.BackStackSlotId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateValue" {
                A.field "index" "number",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingSig" {
                A.field "index" "number",
                A.field "sig" "MoonBack.BackSigId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingData" {
                A.field "index" "number",
                A.field "data" "MoonBack.BackDataId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingFunc" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackFuncId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingExtern" {
                A.field "index" "number",
                A.field "func" "MoonBack.BackExternId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingBlock" {
                A.field "index" "number",
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingStackSlot" {
                A.field "index" "number",
                A.field "slot" "MoonBack.BackStackSlotId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingValue" {
                A.field "index" "number",
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "BackIssueDuplicateAccess" {
                A.field "index" "number",
                A.field "access" "MoonBack.BackAccessId",
                A.variant_unique,
            },
            A.variant "BackIssueMissingAccess" {
                A.field "index" "number",
                A.field "access" "MoonBack.BackAccessId",
                A.variant_unique,
            },
            A.variant "BackIssueInvalidAlignment" {
                A.field "index" "number",
                A.field "bytes" "number",
                A.variant_unique,
            },
            A.variant "BackIssueLoadAccessMode" {
                A.field "index" "number",
                A.field "mode" "MoonBack.BackAccessMode",
                A.variant_unique,
            },
            A.variant "BackIssueStoreAccessMode" {
                A.field "index" "number",
                A.field "mode" "MoonBack.BackAccessMode",
                A.variant_unique,
            },
            A.variant "BackIssueDereferenceTooSmall" {
                A.field "index" "number",
                A.field "dereference_bytes" "number",
                A.field "access_bytes" "number",
                A.variant_unique,
            },
            A.variant "BackIssueTargetUnsupportedShape" {
                A.field "index" "number",
                A.field "shape" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "BackIssueIntScalarExpected" {
                A.field "index" "number",
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "BackIssueFloatScalarExpected" {
                A.field "index" "number",
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "BackIssueBitScalarExpected" {
                A.field "index" "number",
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "BackIssueShiftScalarExpected" {
                A.field "index" "number",
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "BackIssueNonTrappingWithoutDereference" {
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BackIssueCanMoveWithoutNonTrapping" {
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "BackIssueShapeRequiresScalar" {
                A.field "index" "number",
                A.field "shape" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "BackIssueShapeRequiresVector" {
                A.field "index" "number",
                A.field "shape" "MoonBack.BackShape",
                A.variant_unique,
            },
        },

        A.product "BackValidationReport" {
            A.field "issues" (A.many "MoonBack.BackValidationIssue"),
            A.unique,
        },

        A.product "BackCommandCount" {
            A.field "command_kind" "string",
            A.field "count" "number",
            A.unique,
        },

        A.product "BackMemoryInspection" {
            A.field "index" "number",
            A.field "access" "MoonBack.BackAccessId",
            A.field "alignment" "MoonBack.BackAlignment",
            A.field "dereference" "MoonBack.BackDereference",
            A.field "trap" "MoonBack.BackTrap",
            A.field "motion" "MoonBack.BackMotion",
            A.field "mode" "MoonBack.BackAccessMode",
            A.unique,
        },

        A.product "BackAddressInspection" {
            A.field "index" "number",
            A.field "address" "MoonBack.BackAddress",
            A.unique,
        },

        A.product "BackPointerOffsetInspection" {
            A.field "index" "number",
            A.field "dst" "MoonBack.BackValId",
            A.field "base" "MoonBack.BackAddressBase",
            A.field "index_value" "MoonBack.BackValId",
            A.field "elem_size" "number",
            A.field "const_offset" "number",
            A.field "provenance" "MoonBack.BackPointerProvenance",
            A.field "bounds" "MoonBack.BackPointerBounds",
            A.unique,
        },

        A.product "BackAliasInspection" {
            A.field "index" "number",
            A.field "fact" "MoonBack.BackAliasFact",
            A.unique,
        },

        A.product "BackIntSemanticsInspection" {
            A.field "index" "number",
            A.field "dst" "MoonBack.BackValId",
            A.field "op" "MoonBack.BackIntOp",
            A.field "scalar" "MoonBack.BackScalar",
            A.field "semantics" "MoonBack.BackIntSemantics",
            A.unique,
        },

        A.sum "BackFloatSemanticOp" {
            A.variant "BackFloatSemanticBinary" {
                A.field "op" "MoonBack.BackFloatOp",
                A.variant_unique,
            },
            A.variant "BackFloatSemanticFma",
        },

        A.product "BackFloatSemanticsInspection" {
            A.field "index" "number",
            A.field "dst" "MoonBack.BackValId",
            A.field "op" "MoonBack.BackFloatSemanticOp",
            A.field "scalar" "MoonBack.BackScalar",
            A.field "semantics" "MoonBack.BackFloatSemantics",
            A.unique,
        },

        A.product "BackInspectionReport" {
            A.field "command_counts" (A.many "MoonBack.BackCommandCount"),
            A.field "targets" (A.many "MoonBack.BackTargetModel"),
            A.field "memory" (A.many "MoonBack.BackMemoryInspection"),
            A.field "addresses" (A.many "MoonBack.BackAddressInspection"),
            A.field "pointer_offsets" (A.many "MoonBack.BackPointerOffsetInspection"),
            A.field "aliases" (A.many "MoonBack.BackAliasInspection"),
            A.field "int_semantics" (A.many "MoonBack.BackIntSemanticsInspection"),
            A.field "float_semantics" (A.many "MoonBack.BackFloatSemanticsInspection"),
            A.unique,
        },

        A.product "BackDisasmInspection" {
            A.field "func" "MoonBack.BackFuncId",
            A.field "text" "string",
            A.unique,
        },

        A.product "BackDiagnosticsReport" {
            A.field "inspection" "MoonBack.BackInspectionReport",
            A.field "vector" "MoonVec.VecInspectionReport",
            A.field "disassembly" (A.many "MoonBack.BackDisasmInspection"),
            A.unique,
        },

        A.sum "BackFlow" {
            A.variant "BackFallsThrough",
            A.variant "BackTerminates",
        },

        A.product "BackSigSpec" {
            A.field "params" (A.many "MoonBack.BackScalar"),
            A.field "results" (A.many "MoonBack.BackScalar"),
            A.unique,
        },

        A.product "BackStackSlotSpec" {
            A.field "size" "number",
            A.field "align" "number",
            A.unique,
        },

        A.sum "BackExprLowering" {
            A.variant "BackExprPlan" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.field "value" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "BackExprTerminated" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.variant_unique,
            },
        },

        A.sum "BackAddrLowering" {
            A.variant "BackAddrWrites" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.variant_unique,
            },
            A.variant "BackAddrTerminated" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.variant_unique,
            },
        },

        A.sum "BackViewLowering" {
            A.variant "BackViewPlan" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.field "data" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.field "stride" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "BackViewTerminated" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.variant_unique,
            },
        },

        A.sum "BackReturnTarget" {
            A.variant "BackReturnValue",
            A.variant "BackReturnSret" {
                A.field "addr" "MoonBack.BackValId",
                A.variant_unique,
            },
        },

        A.product "BackStmtPlan" {
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.field "flow" "MoonBack.BackFlow",
            A.unique,
        },

        A.product "BackFuncPlan" {
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.unique,
        },

        A.product "BackItemPlan" {
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.unique,
        },

        A.product "BackProgram" {
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.unique,
        },

        A.product "BackCommandTape" {
            A.field "version" "number",
            A.field "command_count" "number",
            A.field "payload" "string",
            A.unique,
        },
    }
end
