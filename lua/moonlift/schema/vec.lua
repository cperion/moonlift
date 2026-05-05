-- Clean MoonVec schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonVec" {
        A.product "VecExprId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "VecLoopId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "VecAccessId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "VecValueId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "VecBlockId" {
            A.field "text" "string",
            A.unique,
        },

        A.sum "VecElem" {
            A.variant "VecElemBool",
            A.variant "VecElemI8",
            A.variant "VecElemI16",
            A.variant "VecElemI32",
            A.variant "VecElemI64",
            A.variant "VecElemU8",
            A.variant "VecElemU16",
            A.variant "VecElemU32",
            A.variant "VecElemU64",
            A.variant "VecElemF32",
            A.variant "VecElemF64",
            A.variant "VecElemPtr",
            A.variant "VecElemIndex",
        },

        A.sum "VecShape" {
            A.variant "VecScalarShape" {
                A.field "elem" "MoonVec.VecElem",
                A.variant_unique,
            },
            A.variant "VecVectorShape" {
                A.field "elem" "MoonVec.VecElem",
                A.field "lanes" "number",
                A.variant_unique,
            },
        },

        A.sum "VecBinOp" {
            A.variant "VecAdd",
            A.variant "VecSub",
            A.variant "VecMul",
            A.variant "VecRem",
            A.variant "VecBitAnd",
            A.variant "VecBitOr",
            A.variant "VecBitXor",
            A.variant "VecShl",
            A.variant "VecLShr",
            A.variant "VecAShr",
            A.variant "VecEq",
            A.variant "VecNe",
            A.variant "VecLt",
            A.variant "VecLe",
            A.variant "VecGt",
            A.variant "VecGe",
        },

        A.sum "VecCmpOp" {
            A.variant "VecCmpEq",
            A.variant "VecCmpNe",
            A.variant "VecCmpSLt",
            A.variant "VecCmpSLe",
            A.variant "VecCmpSGt",
            A.variant "VecCmpSGe",
            A.variant "VecCmpULt",
            A.variant "VecCmpULe",
            A.variant "VecCmpUGt",
            A.variant "VecCmpUGe",
        },

        A.sum "VecMaskOp" {
            A.variant "VecMaskNot",
            A.variant "VecMaskAnd",
            A.variant "VecMaskOr",
        },

        A.sum "VecUnaryOp" {
            A.variant "VecNeg",
            A.variant "VecNot",
            A.variant "VecBitNot",
            A.variant "VecPopcount",
            A.variant "VecClz",
            A.variant "VecCtz",
        },

        A.sum "VecReject" {
            A.variant "VecRejectUnsupportedLoop" {
                A.field "loop" "MoonVec.VecLoopId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecRejectUnsupportedExpr" {
                A.field "expr" "MoonVec.VecExprId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecRejectUnsupportedStmt" {
                A.field "stmt_id" "string",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecRejectUnsupportedMemory" {
                A.field "access" "MoonVec.VecAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecRejectDependence" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecRejectRange" {
                A.field "expr" "MoonVec.VecExprId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecRejectTarget" {
                A.field "shape" "MoonVec.VecShape",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecRejectCost" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "VecTarget" {
            A.variant "VecTargetCraneliftJit",
            A.variant "VecTargetNamed" {
                A.field "name" "string",
                A.variant_unique,
            },
        },

        A.sum "VecTargetFact" {
            A.variant "VecTargetSupportsShape" {
                A.field "shape" "MoonVec.VecShape",
                A.variant_unique,
            },
            A.variant "VecTargetSupportsBinOp" {
                A.field "shape" "MoonVec.VecShape",
                A.field "op" "MoonVec.VecBinOp",
                A.variant_unique,
            },
            A.variant "VecTargetSupportsCmpOp" {
                A.field "shape" "MoonVec.VecShape",
                A.field "op" "MoonVec.VecCmpOp",
                A.variant_unique,
            },
            A.variant "VecTargetSupportsSelect" {
                A.field "shape" "MoonVec.VecShape",
                A.variant_unique,
            },
            A.variant "VecTargetSupportsMaskOp" {
                A.field "shape" "MoonVec.VecShape",
                A.field "op" "MoonVec.VecMaskOp",
                A.variant_unique,
            },
            A.variant "VecTargetSupportsUnaryOp" {
                A.field "shape" "MoonVec.VecShape",
                A.field "op" "MoonVec.VecUnaryOp",
                A.variant_unique,
            },
            A.variant "VecTargetPrefersUnroll" {
                A.field "shape" "MoonVec.VecShape",
                A.field "unroll" "number",
                A.field "rank" "number",
                A.variant_unique,
            },
            A.variant "VecTargetPrefersReductionAccumulators" {
                A.field "shape" "MoonVec.VecShape",
                A.field "op" "MoonVec.VecBinOp",
                A.field "accumulators" "number",
                A.field "rank" "number",
                A.variant_unique,
            },
            A.variant "VecTargetPrefersScalarTail",
            A.variant "VecTargetSupportsMaskedTail",
            A.variant "VecTargetVectorBits" {
                A.field "bits" "number",
                A.variant_unique,
            },
        },

        A.product "VecTargetModel" {
            A.field "target" "MoonVec.VecTarget",
            A.field "facts" (A.many "MoonVec.VecTargetFact"),
            A.unique,
        },

        A.sum "VecExprFact" {
            A.variant "VecExprConst" {
                A.field "id" "MoonVec.VecExprId",
                A.field "expr" "MoonTree.Expr",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprInvariant" {
                A.field "id" "MoonVec.VecExprId",
                A.field "expr" "MoonTree.Expr",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprLaneIndex" {
                A.field "id" "MoonVec.VecExprId",
                A.field "binding" "MoonBind.Binding",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprLocal" {
                A.field "id" "MoonVec.VecExprId",
                A.field "binding" "MoonBind.Binding",
                A.field "value" "MoonVec.VecExprId",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprUnary" {
                A.field "id" "MoonVec.VecExprId",
                A.field "op" "MoonVec.VecUnaryOp",
                A.field "value" "MoonVec.VecExprId",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprBin" {
                A.field "id" "MoonVec.VecExprId",
                A.field "op" "MoonVec.VecBinOp",
                A.field "lhs" "MoonVec.VecExprId",
                A.field "rhs" "MoonVec.VecExprId",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprSelect" {
                A.field "id" "MoonVec.VecExprId",
                A.field "cond" "MoonVec.VecExprId",
                A.field "then_value" "MoonVec.VecExprId",
                A.field "else_value" "MoonVec.VecExprId",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprLoad" {
                A.field "id" "MoonVec.VecExprId",
                A.field "access" "MoonVec.VecAccessId",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "VecExprRejected" {
                A.field "id" "MoonVec.VecExprId",
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.product "VecExprGraph" {
            A.field "exprs" (A.many "MoonVec.VecExprFact"),
            A.unique,
        },

        A.sum "VecExprResult" {
            A.variant "VecExprResult" {
                A.field "value" "MoonVec.VecExprId",
                A.field "facts" (A.many "MoonVec.VecExprFact"),
                A.field "memory" (A.many "MoonVec.VecMemoryFact"),
                A.field "ranges" (A.many "MoonVec.VecRangeFact"),
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
        },

        A.product "VecLocalFact" {
            A.field "binding" "MoonBind.Binding",
            A.field "value" "MoonVec.VecExprId",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "VecExprEnv" {
            A.field "index" "MoonBind.Binding",
            A.field "locals" (A.many "MoonVec.VecLocalFact"),
            A.unique,
        },

        A.sum "VecStmtResult" {
            A.variant "VecStmtLocal" {
                A.field "local" "MoonVec.VecLocalFact",
                A.field "facts" (A.many "MoonVec.VecExprFact"),
                A.field "memory" (A.many "MoonVec.VecMemoryFact"),
                A.field "ranges" (A.many "MoonVec.VecRangeFact"),
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
            A.variant "VecStmtStore" {
                A.field "store" "MoonVec.VecStoreFact",
                A.field "facts" (A.many "MoonVec.VecExprFact"),
                A.field "memory" (A.many "MoonVec.VecMemoryFact"),
                A.field "ranges" (A.many "MoonVec.VecRangeFact"),
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
            A.variant "VecStmtIgnored" {
                A.field "facts" (A.many "MoonVec.VecExprFact"),
                A.field "memory" (A.many "MoonVec.VecMemoryFact"),
                A.field "ranges" (A.many "MoonVec.VecRangeFact"),
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
        },

        A.sum "VecRangeFact" {
            A.variant "VecRangeUnknown" {
                A.field "expr" "MoonVec.VecExprId",
                A.variant_unique,
            },
            A.variant "VecRangeExact" {
                A.field "expr" "MoonVec.VecExprId",
                A.field "value" "string",
                A.variant_unique,
            },
            A.variant "VecRangeUnsigned" {
                A.field "expr" "MoonVec.VecExprId",
                A.field "min" "string",
                A.field "max" "string",
                A.variant_unique,
            },
            A.variant "VecRangeBitAnd" {
                A.field "expr" "MoonVec.VecExprId",
                A.field "mask" "string",
                A.field "max_value" "string",
                A.variant_unique,
            },
            A.variant "VecRangeDerived" {
                A.field "expr" "MoonVec.VecExprId",
                A.field "min" "string",
                A.field "max" "string",
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
        },

        A.sum "VecDomain" {
            A.variant "VecDomainCounted" {
                A.field "start" "MoonTree.Expr",
                A.field "stop" "MoonTree.Expr",
                A.field "step" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "VecDomainRejected" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecInduction" {
            A.variant "VecPrimaryInduction" {
                A.field "binding" "MoonBind.Binding",
                A.field "start" "MoonTree.Expr",
                A.field "step" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "VecDerivedInduction" {
                A.field "binding" "MoonBind.Binding",
                A.field "expr" "MoonVec.VecExprId",
                A.variant_unique,
            },
        },

        A.sum "VecAccessKind" {
            A.variant "VecAccessLoad",
            A.variant "VecAccessStore",
        },

        A.sum "VecAccessPattern" {
            A.variant "VecAccessContiguous",
            A.variant "VecAccessStrided" {
                A.field "stride" "number",
                A.variant_unique,
            },
            A.variant "VecAccessGather",
            A.variant "VecAccessScatter",
            A.variant "VecAccessUnknown",
        },

        A.sum "VecAlignment" {
            A.variant "VecAlignmentKnown" {
                A.field "bytes" "number",
                A.variant_unique,
            },
            A.variant "VecAlignmentUnknown",
            A.variant "VecAlignmentAssumed" {
                A.field "bytes" "number",
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
        },

        A.sum "VecBounds" {
            A.variant "VecBoundsProven" {
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecBoundsUnknown" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecMemoryBase" {
            A.variant "VecMemoryBaseRawAddr" {
                A.field "addr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "VecMemoryBaseView" {
                A.field "view" "MoonTree.View",
                A.variant_unique,
            },
            A.variant "VecMemoryBasePlace" {
                A.field "place" "MoonTree.Place",
                A.variant_unique,
            },
        },

        A.sum "VecMemoryFact" {
            A.variant "VecMemoryAccess" {
                A.field "id" "MoonVec.VecAccessId",
                A.field "access_kind" "MoonVec.VecAccessKind",
                A.field "base" "MoonVec.VecMemoryBase",
                A.field "index" "MoonVec.VecExprId",
                A.field "elem_ty" "MoonType.Type",
                A.field "pattern" "MoonVec.VecAccessPattern",
                A.field "alignment" "MoonVec.VecAlignment",
                A.field "bounds" "MoonVec.VecBounds",
                A.variant_unique,
            },
        },

        A.sum "VecAliasFact" {
            A.variant "VecAccessSameBase" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecAccessNoAlias" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecAccessDisjointRange" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecAliasUnknown" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecDependenceFact" {
            A.variant "VecNoDependence" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecDependenceUnknown" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
            A.variant "VecLoopCarriedDependence" {
                A.field "a" "MoonVec.VecAccessId",
                A.field "b" "MoonVec.VecAccessId",
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecReassoc" {
            A.variant "VecReassocWrapping",
            A.variant "VecReassocExact",
            A.variant "VecReassocFloatFastMath",
            A.variant "VecReassocRejected" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecReductionFact" {
            A.variant "VecReductionAdd" {
                A.field "accumulator" "MoonBind.Binding",
                A.field "value" "MoonVec.VecExprId",
                A.field "reassoc" "MoonVec.VecReassoc",
                A.variant_unique,
            },
            A.variant "VecReductionMul" {
                A.field "accumulator" "MoonBind.Binding",
                A.field "value" "MoonVec.VecExprId",
                A.field "reassoc" "MoonVec.VecReassoc",
                A.variant_unique,
            },
            A.variant "VecReductionBitAnd" {
                A.field "accumulator" "MoonBind.Binding",
                A.field "value" "MoonVec.VecExprId",
                A.variant_unique,
            },
            A.variant "VecReductionBitOr" {
                A.field "accumulator" "MoonBind.Binding",
                A.field "value" "MoonVec.VecExprId",
                A.variant_unique,
            },
            A.variant "VecReductionBitXor" {
                A.field "accumulator" "MoonBind.Binding",
                A.field "value" "MoonVec.VecExprId",
                A.variant_unique,
            },
        },

        A.sum "VecStoreFact" {
            A.variant "VecStoreFact" {
                A.field "access" "MoonVec.VecMemoryFact",
                A.field "value" "MoonVec.VecExprId",
                A.variant_unique,
            },
        },

        A.sum "VecProof" {
            A.variant "VecProofDomain" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecProofRange" {
                A.field "range" "MoonVec.VecRangeFact",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecProofAlias" {
                A.field "alias" "MoonVec.VecAliasFact",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecProofNoMemoryDependence" {
                A.field "accesses" (A.many "MoonVec.VecAccessId"),
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecProofKernelSafety" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecProofReduction" {
                A.field "reduction" "MoonVec.VecReductionFact",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecProofNarrowSafe" {
                A.field "reduction" "MoonVec.VecReductionFact",
                A.field "narrow_elem" "MoonVec.VecElem",
                A.field "chunk_elems" "number",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecProofTarget" {
                A.field "fact" "MoonVec.VecTargetFact",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "VecAssumption" {
            A.variant "VecAssumeRawPtrBounds" {
                A.field "base" "MoonBind.Binding",
                A.field "stop" "MoonBind.Binding",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecAssumeRawPtrDisjointOrSameIndexSafe" {
                A.field "bases" (A.many "MoonBind.Binding"),
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecAssumeAlignment" {
                A.field "base" "MoonBind.Binding",
                A.field "bytes" "number",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "VecKernelSafety" {
            A.variant "VecKernelSafetyProven" {
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
            A.variant "VecKernelSafetyAssumed" {
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.field "assumptions" (A.many "MoonVec.VecAssumption"),
                A.variant_unique,
            },
            A.variant "VecKernelSafetyRejected" {
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
        },

        A.sum "VecKernelLenSource" {
            A.variant "VecKernelLenBinding" {
                A.field "binding" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "VecKernelLenView" {
                A.field "view" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "VecKernelLenExpr" {
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
        },

        A.sum "VecKernelMemoryUse" {
            A.variant "VecKernelRead" {
                A.field "base" "MoonBind.Binding",
                A.field "elem" "MoonVec.VecElem",
                A.field "offset" "MoonVec.VecKernelIndexOffset",
                A.field "base_len" "MoonVec.VecKernelLenSource",
                A.field "len_value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "VecKernelWrite" {
                A.field "base" "MoonBind.Binding",
                A.field "elem" "MoonVec.VecElem",
                A.field "offset" "MoonVec.VecKernelIndexOffset",
                A.field "base_len" "MoonVec.VecKernelLenSource",
                A.field "len_value" "MoonTree.Expr",
                A.variant_unique,
            },
        },

        A.sum "VecKernelBounds" {
            A.variant "VecKernelBoundsProven" {
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecKernelBoundsAssumed" {
                A.field "assumption" "MoonVec.VecAssumption",
                A.variant_unique,
            },
            A.variant "VecKernelBoundsRejected" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.product "VecWindowRangeObligation" {
            A.field "base" "MoonBind.Binding",
            A.field "base_len" "MoonVec.VecKernelLenSource",
            A.field "start" "MoonVec.VecKernelIndexOffset",
            A.field "len" "MoonBind.Binding",
            A.field "len_value" "MoonTree.Expr",
            A.unique,
        },

        A.sum "VecWindowRangeDecision" {
            A.variant "VecWindowRangeProven" {
                A.field "obligation" "MoonVec.VecWindowRangeObligation",
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecWindowRangeRejected" {
                A.field "obligation" "MoonVec.VecWindowRangeObligation",
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecKernelAlias" {
            A.variant "VecKernelAliasProven" {
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecKernelAliasAssumed" {
                A.field "assumption" "MoonVec.VecAssumption",
                A.variant_unique,
            },
            A.variant "VecKernelAliasSameIndexSafe" {
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecKernelAliasRejected" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecKernelAlignment" {
            A.variant "VecKernelAlignProven" {
                A.field "base" "MoonBind.Binding",
                A.field "elem" "MoonVec.VecElem",
                A.field "bytes" "number",
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecKernelAlignAssumed" {
                A.field "base" "MoonBind.Binding",
                A.field "elem" "MoonVec.VecElem",
                A.field "bytes" "number",
                A.field "assumption" "MoonVec.VecAssumption",
                A.variant_unique,
            },
            A.variant "VecKernelAlignUnknown" {
                A.field "base" "MoonBind.Binding",
                A.field "elem" "MoonVec.VecElem",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "VecKernelAlignRejected" {
                A.field "base" "MoonBind.Binding",
                A.field "elem" "MoonVec.VecElem",
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.product "VecNestedLoopFact" {
            A.field "facts" "MoonVec.VecLoopFacts",
            A.unique,
        },

        A.sum "VecLoopSource" {
            A.variant "VecLoopSourceControlRegion" {
                A.field "region_id" "string",
                A.field "header" "MoonTree.BlockLabel",
                A.field "backedge" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "VecLoopSourceRejected" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecLoopFacts" {
            A.variant "VecLoopFacts" {
                A.field "loop" "MoonVec.VecLoopId",
                A.field "source" "MoonVec.VecLoopSource",
                A.field "domain" "MoonVec.VecDomain",
                A.field "inductions" (A.many "MoonVec.VecInduction"),
                A.field "exprs" "MoonVec.VecExprGraph",
                A.field "memory" (A.many "MoonVec.VecMemoryFact"),
                A.field "aliases" (A.many "MoonVec.VecAliasFact"),
                A.field "dependences" (A.many "MoonVec.VecDependenceFact"),
                A.field "ranges" (A.many "MoonVec.VecRangeFact"),
                A.field "stores" (A.many "MoonVec.VecStoreFact"),
                A.field "reductions" (A.many "MoonVec.VecReductionFact"),
                A.field "nested" (A.many "MoonVec.VecNestedLoopFact"),
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
        },

        A.sum "VecTail" {
            A.variant "VecTailNone",
            A.variant "VecTailScalar",
            A.variant "VecTailMasked" {
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
        },

        A.sum "VecLoopShape" {
            A.variant "VecLoopScalar" {
                A.field "loop" "MoonVec.VecLoopId",
                A.field "vector_rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
            A.variant "VecLoopVector" {
                A.field "loop" "MoonVec.VecLoopId",
                A.field "shape" "MoonVec.VecShape",
                A.field "unroll" "number",
                A.field "tail" "MoonVec.VecTail",
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
            A.variant "VecLoopChunkedNarrowVector" {
                A.field "loop" "MoonVec.VecLoopId",
                A.field "narrow_shape" "MoonVec.VecShape",
                A.field "unroll" "number",
                A.field "chunk_elems" "number",
                A.field "tail" "MoonVec.VecTail",
                A.field "narrow_proof" "MoonVec.VecProof",
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
        },

        A.sum "VecLegality" {
            A.variant "VecLegal" {
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
            A.variant "VecIllegal" {
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
        },

        A.sum "VecReductionSchedule" {
            A.variant "VecReductionSchedule" {
                A.field "op" "MoonVec.VecBinOp",
                A.field "accumulators" "number",
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
        },

        A.sum "VecSchedule" {
            A.variant "VecScheduleScalar" {
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
            A.variant "VecScheduleVector" {
                A.field "shape" "MoonVec.VecShape",
                A.field "unroll" "number",
                A.field "interleave" "number",
                A.field "tail" "MoonVec.VecTail",
                A.field "accumulators" "number",
                A.field "reductions" (A.many "MoonVec.VecReductionSchedule"),
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
            A.variant "VecScheduleChunkedNarrowVector" {
                A.field "narrow_shape" "MoonVec.VecShape",
                A.field "unroll" "number",
                A.field "interleave" "number",
                A.field "chunk_elems" "number",
                A.field "tail" "MoonVec.VecTail",
                A.field "accumulators" "number",
                A.field "reductions" (A.many "MoonVec.VecReductionSchedule"),
                A.field "narrow_proof" "MoonVec.VecProof",
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
        },

        A.sum "VecShapeScore" {
            A.variant "VecShapeScore" {
                A.field "shape" "MoonVec.VecLoopShape",
                A.field "elems_per_iter" "number",
                A.field "rank" "number",
                A.field "rationale" "string",
                A.variant_unique,
            },
        },

        A.sum "VecLoopDecision" {
            A.variant "VecLoopDecision" {
                A.field "facts" "MoonVec.VecLoopFacts",
                A.field "legality" "MoonVec.VecLegality",
                A.field "schedule" "MoonVec.VecSchedule",
                A.field "chosen" "MoonVec.VecLoopShape",
                A.field "considered" (A.many "MoonVec.VecShapeScore"),
                A.variant_unique,
            },
        },

        A.product "VecScheduleInspection" {
            A.field "loop" "MoonVec.VecLoopId",
            A.field "legality" "MoonVec.VecLegality",
            A.field "schedule" "MoonVec.VecSchedule",
            A.field "considered" (A.many "MoonVec.VecShapeScore"),
            A.unique,
        },

        A.product "VecInspectionReport" {
            A.field "schedules" (A.many "MoonVec.VecScheduleInspection"),
            A.unique,
        },

        A.sum "VecKernelIndexOffset" {
            A.variant "VecKernelOffsetZero",
            A.variant "VecKernelOffsetExpr" {
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "VecKernelOffsetAdd" {
                A.field "lhs" "MoonVec.VecKernelIndexOffset",
                A.field "rhs" "MoonVec.VecKernelIndexOffset",
                A.variant_unique,
            },
        },

        A.product "VecKernelScalarAlias" {
            A.field "binding" "MoonBind.Binding",
            A.field "value" "MoonTree.Expr",
            A.unique,
        },

        A.sum "VecKernelCounter" {
            A.variant "VecKernelCounterI32" {
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
            A.variant "VecKernelCounterIndex" {
                A.field "proofs" (A.many "MoonVec.VecProof"),
                A.variant_unique,
            },
            A.variant "VecKernelCounterRejected" {
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.sum "VecKernelMaskExpr" {
            A.variant "VecKernelMaskCompare" {
                A.field "op" "MoonVec.VecCmpOp",
                A.field "lhs" "MoonVec.VecKernelExpr",
                A.field "rhs" "MoonVec.VecKernelExpr",
                A.variant_unique,
            },
            A.variant "VecKernelMaskNot" {
                A.field "value" "MoonVec.VecKernelMaskExpr",
                A.variant_unique,
            },
            A.variant "VecKernelMaskBin" {
                A.field "op" "MoonVec.VecMaskOp",
                A.field "lhs" "MoonVec.VecKernelMaskExpr",
                A.field "rhs" "MoonVec.VecKernelMaskExpr",
                A.variant_unique,
            },
        },

        A.sum "VecKernelExpr" {
            A.variant "VecKernelExprLoad" {
                A.field "base" "MoonBind.Binding",
                A.field "offset" "MoonVec.VecKernelIndexOffset",
                A.field "base_len" "MoonVec.VecKernelLenSource",
                A.field "len_value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "VecKernelExprInvariant" {
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "VecKernelExprBin" {
                A.field "op" "MoonVec.VecBinOp",
                A.field "lhs" "MoonVec.VecKernelExpr",
                A.field "rhs" "MoonVec.VecKernelExpr",
                A.variant_unique,
            },
            A.variant "VecKernelExprSelect" {
                A.field "cond" "MoonVec.VecKernelMaskExpr",
                A.field "then_value" "MoonVec.VecKernelExpr",
                A.field "else_value" "MoonVec.VecKernelExpr",
                A.variant_unique,
            },
        },

        A.product "VecKernelStorePlan" {
            A.field "dst" "MoonBind.Binding",
            A.field "offset" "MoonVec.VecKernelIndexOffset",
            A.field "base_len" "MoonVec.VecKernelLenSource",
            A.field "len_value" "MoonTree.Expr",
            A.field "value" "MoonVec.VecKernelExpr",
            A.unique,
        },

        A.sum "VecKernelViewStride" {
            A.variant "VecKernelStrideUnit",
            A.variant "VecKernelStrideConst" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "VecKernelStrideDynamic" {
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
        },

        A.product "VecKernelViewAlias" {
            A.field "view" "MoonBind.Binding",
            A.field "data" "MoonBind.Binding",
            A.field "len" "MoonBind.Binding",
            A.field "stride" "MoonVec.VecKernelViewStride",
            A.field "offset" "MoonVec.VecKernelIndexOffset",
            A.field "base_len" "MoonVec.VecKernelLenSource",
            A.field "len_value" "MoonTree.Expr",
            A.unique,
        },

        A.sum "VecKernelReductionPlan" {
            A.variant "VecKernelReductionBin" {
                A.field "op" "MoonVec.VecBinOp",
                A.field "elem" "MoonVec.VecElem",
                A.field "accumulator" "MoonBind.Binding",
                A.field "value" "MoonVec.VecKernelExpr",
                A.field "identity" "string",
                A.variant_unique,
            },
            A.variant "VecKernelReductionAdd" {
                A.field "elem" "MoonVec.VecElem",
                A.field "accumulator" "MoonBind.Binding",
                A.field "value" "MoonVec.VecKernelExpr",
                A.variant_unique,
            },
        },

        A.sum "VecKernelCore" {
            A.variant "VecKernelCoreReduce" {
                A.field "decision" "MoonVec.VecLoopDecision",
                A.field "elem" "MoonVec.VecElem",
                A.field "stop" "MoonBind.Binding",
                A.field "counter" "MoonVec.VecKernelCounter",
                A.field "scalars" (A.many "MoonVec.VecKernelScalarAlias"),
                A.field "reduction" "MoonVec.VecKernelReductionPlan",
                A.variant_unique,
            },
            A.variant "VecKernelCoreMap" {
                A.field "decision" "MoonVec.VecLoopDecision",
                A.field "elem" "MoonVec.VecElem",
                A.field "stop" "MoonBind.Binding",
                A.field "counter" "MoonVec.VecKernelCounter",
                A.field "scalars" (A.many "MoonVec.VecKernelScalarAlias"),
                A.field "stores" (A.many "MoonVec.VecKernelStorePlan"),
                A.variant_unique,
            },
        },

        A.product "VecKernelSafetyInput" {
            A.field "facts" "MoonVec.VecLoopFacts",
            A.field "core" "MoonVec.VecKernelCore",
            A.field "uses" (A.many "MoonVec.VecKernelMemoryUse"),
            A.field "contracts" (A.many "MoonTree.ContractFact"),
            A.unique,
        },

        A.product "VecKernelSafetyDecision" {
            A.field "safety" "MoonVec.VecKernelSafety",
            A.field "bounds" (A.many "MoonVec.VecKernelBounds"),
            A.field "alignments" (A.many "MoonVec.VecKernelAlignment"),
            A.field "aliases" (A.many "MoonVec.VecKernelAlias"),
            A.field "rejects" (A.many "MoonVec.VecReject"),
            A.unique,
        },

        A.sum "VecAlgebraicKind" {
            A.variant "VecAlgebraicSeries" {
                --- sum(a*i + b) for i in 0..n-1
                --- closed form:  a * n*(n-1)/2  +  b * n
                ---
                --- Special cases:
                ---   triangular sum  (a="1",  b="0")  →  n*(n-1)/2
                ---   constant acc.   (a="0",  b="c")  →  c*n
                ---   scaled tri.     (a="c",  b="0")  →  c*n*(n-1)/2
                A.field "coeff_a" "string",
                A.field "coeff_b" "string",
                A.variant_unique,
            },
            A.variant "VecAlgebraicQuadratic" {
                --- sum(c*i^2 + a*i + b) for i in 0..n-1
                --- closed form:  c * n*(n-1)*(2n-1)/6  +  a * n*(n-1)/2  +  b * n
                ---
                --- Common cases:
                ---   i*i       (c="1",  a="0",  b="0")  →  n*(n-1)*(2n-1)/6
                ---   scale*i*i (c="k",  a="0",  b="0")  →  k*n*(n-1)*(2n-1)/6
                --- The a and b coefficients reuse the affine formula;
                --- c=0 degrades to VecAlgebraicSeries.
                A.field "coeff_c" "string",
                A.field "coeff_a" "string",
                A.field "coeff_b" "string",
                A.variant_unique,
            },
        },

        A.sum "VecKernelPlan" {
            A.variant "VecKernelNoPlan" {
                A.field "rejects" (A.many "MoonVec.VecReject"),
                A.variant_unique,
            },
            A.variant "VecKernelReduce" {
                A.field "decision" "MoonVec.VecLoopDecision",
                A.field "elem" "MoonVec.VecElem",
                A.field "stop" "MoonBind.Binding",
                A.field "counter" "MoonVec.VecKernelCounter",
                A.field "scalars" (A.many "MoonVec.VecKernelScalarAlias"),
                A.field "reduction" "MoonVec.VecKernelReductionPlan",
                A.field "safety" "MoonVec.VecKernelSafety",
                A.field "alignments" (A.many "MoonVec.VecKernelAlignment"),
                A.field "aliases" (A.many "MoonVec.VecKernelAlias"),
                A.variant_unique,
            },
            A.variant "VecKernelMap" {
                A.field "decision" "MoonVec.VecLoopDecision",
                A.field "elem" "MoonVec.VecElem",
                A.field "stop" "MoonBind.Binding",
                A.field "counter" "MoonVec.VecKernelCounter",
                A.field "scalars" (A.many "MoonVec.VecKernelScalarAlias"),
                A.field "stores" (A.many "MoonVec.VecKernelStorePlan"),
                A.field "safety" "MoonVec.VecKernelSafety",
                A.field "alignments" (A.many "MoonVec.VecKernelAlignment"),
                A.field "aliases" (A.many "MoonVec.VecKernelAlias"),
                A.variant_unique,
            },
            A.variant "VecKernelAlgebraic" {
                --- Replace a counted reduction loop with a closed-form
                --- scalar expression.  The loop body contains zero memory
                --- loads and the accumulated value is an affine function
                --- of the induction variable.
                A.field "facts" "MoonVec.VecLoopFacts",
                A.field "kind" "MoonVec.VecAlgebraicKind",
                A.field "elem" "MoonVec.VecElem",
                A.field "stop" "MoonBind.Binding",
                A.field "accumulator" "MoonBind.Binding",
                A.variant_unique,
            },
        },

        A.sum "VecValue" {
            A.variant "VecScalarValue" {
                A.field "id" "MoonVec.VecValueId",
                A.field "elem" "MoonVec.VecElem",
                A.variant_unique,
            },
            A.variant "VecVectorValue" {
                A.field "id" "MoonVec.VecValueId",
                A.field "elem" "MoonVec.VecElem",
                A.field "lanes" "number",
                A.variant_unique,
            },
        },

        A.sum "VecParam" {
            A.variant "VecScalarParam" {
                A.field "id" "MoonVec.VecValueId",
                A.field "elem" "MoonVec.VecElem",
                A.variant_unique,
            },
            A.variant "VecVectorParam" {
                A.field "id" "MoonVec.VecValueId",
                A.field "elem" "MoonVec.VecElem",
                A.field "lanes" "number",
                A.variant_unique,
            },
        },

        A.sum "VecCmd" {
            A.variant "VecCmdConstInt" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "elem" "MoonVec.VecElem",
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "VecCmdSplat" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "shape" "MoonVec.VecShape",
                A.field "scalar" "MoonVec.VecValueId",
                A.variant_unique,
            },
            A.variant "VecCmdRamp" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "shape" "MoonVec.VecShape",
                A.field "base" "MoonVec.VecValueId",
                A.field "offsets" (A.many "string"),
                A.variant_unique,
            },
            A.variant "VecCmdBin" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "shape" "MoonVec.VecShape",
                A.field "op" "MoonVec.VecBinOp",
                A.field "lhs" "MoonVec.VecValueId",
                A.field "rhs" "MoonVec.VecValueId",
                A.variant_unique,
            },
            A.variant "VecCmdSelect" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "shape" "MoonVec.VecShape",
                A.field "cond" "MoonVec.VecValueId",
                A.field "then_value" "MoonVec.VecValueId",
                A.field "else_value" "MoonVec.VecValueId",
                A.variant_unique,
            },
            A.variant "VecCmdIreduce" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "narrow_elem" "MoonVec.VecElem",
                A.field "value" "MoonVec.VecValueId",
                A.field "proof" "MoonVec.VecProof",
                A.variant_unique,
            },
            A.variant "VecCmdUextend" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "wide_elem" "MoonVec.VecElem",
                A.field "value" "MoonVec.VecValueId",
                A.variant_unique,
            },
            A.variant "VecCmdExtractLane" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "vec" "MoonVec.VecValueId",
                A.field "lane" "number",
                A.variant_unique,
            },
            A.variant "VecCmdHorizontalReduce" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "op" "MoonVec.VecBinOp",
                A.field "vectors" (A.many "MoonVec.VecValueId"),
                A.variant_unique,
            },
            A.variant "VecCmdLoad" {
                A.field "dst" "MoonVec.VecValueId",
                A.field "shape" "MoonVec.VecShape",
                A.field "access" "MoonVec.VecMemoryFact",
                A.field "addr" "MoonVec.VecValueId",
                A.variant_unique,
            },
            A.variant "VecCmdStore" {
                A.field "access" "MoonVec.VecMemoryFact",
                A.field "shape" "MoonVec.VecShape",
                A.field "addr" "MoonVec.VecValueId",
                A.field "value" "MoonVec.VecValueId",
                A.variant_unique,
            },
        },

        A.sum "VecTerminator" {
            A.variant "VecJump" {
                A.field "dest" "MoonVec.VecBlockId",
                A.field "args" (A.many "MoonVec.VecValueId"),
                A.variant_unique,
            },
            A.variant "VecBrIf" {
                A.field "cond" "MoonVec.VecValueId",
                A.field "then_block" "MoonVec.VecBlockId",
                A.field "then_args" (A.many "MoonVec.VecValueId"),
                A.field "else_block" "MoonVec.VecBlockId",
                A.field "else_args" (A.many "MoonVec.VecValueId"),
                A.variant_unique,
            },
            A.variant "VecReturnVoid",
            A.variant "VecReturnValue" {
                A.field "value" "MoonVec.VecValueId",
                A.variant_unique,
            },
        },

        A.sum "VecBlock" {
            A.variant "VecBlock" {
                A.field "id" "MoonVec.VecBlockId",
                A.field "params" (A.many "MoonVec.VecParam"),
                A.field "cmds" (A.many "MoonVec.VecCmd"),
                A.field "terminator" "MoonVec.VecTerminator",
                A.variant_unique,
            },
        },

        A.product "VecBackValueShape" {
            A.field "id" "MoonVec.VecValueId",
            A.field "shape" "MoonVec.VecShape",
            A.unique,
        },

        A.product "VecBackEnv" {
            A.field "values" (A.many "MoonVec.VecBackValueShape"),
            A.unique,
        },

        A.sum "VecBackLowering" {
            A.variant "VecBackCmds" {
                A.field "env" "MoonVec.VecBackEnv",
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.variant_unique,
            },
            A.variant "VecBackReject" {
                A.field "env" "MoonVec.VecBackEnv",
                A.field "reject" "MoonVec.VecReject",
                A.variant_unique,
            },
        },

        A.product "VecBackFuncSpec" {
            A.field "name" "string",
            A.field "visibility" "MoonCore.Visibility",
            A.field "params" (A.many "MoonVec.VecParam"),
            A.field "results" (A.many "MoonVec.VecShape"),
            A.field "blocks" (A.many "MoonVec.VecBlock"),
            A.unique,
        },

        A.product "VecBackProgramSpec" {
            A.field "funcs" (A.many "MoonVec.VecBackFuncSpec"),
            A.unique,
        },

        A.sum "VecFunc" {
            A.variant "VecFuncScalar" {
                A.field "func" "MoonTree.Func",
                A.field "decisions" (A.many "MoonVec.VecLoopDecision"),
                A.variant_unique,
            },
            A.variant "VecFuncVector" {
                A.field "func" "MoonTree.Func",
                A.field "decisions" (A.many "MoonVec.VecLoopDecision"),
                A.field "blocks" (A.many "MoonVec.VecBlock"),
                A.variant_unique,
            },
            A.variant "VecFuncMixed" {
                A.field "func" "MoonTree.Func",
                A.field "decisions" (A.many "MoonVec.VecLoopDecision"),
                A.field "blocks" (A.many "MoonVec.VecBlock"),
                A.variant_unique,
            },
        },

        A.sum "VecModule" {
            A.variant "VecModule" {
                A.field "source" "MoonTree.Module",
                A.field "target" "MoonVec.VecTargetModel",
                A.field "funcs" (A.many "MoonVec.VecFunc"),
                A.variant_unique,
            },
        },
    }
end
