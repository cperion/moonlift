-- MoonC schema: C type facts produced by cimport, consumed by lower_c and typecheck
-- Defined per C_FRONTEND_DESIGN.md §7.5

return function(A)
    return A.module "MoonC" {
        A.product "CTypeId" {
            A.field "module_name" "string",
            A.field "spelling" "string",
            A.unique,
        },

        A.sum "CTypeKind" {
            A.variant "CVoid",
            A.variant "CScalar"     { A.field "scalar" "MoonBack.BackScalar",          A.variant_unique },
            A.variant "CPointer"    { A.field "pointee" "MoonC.CTypeId",             A.variant_unique },
            A.variant "CEnum"       { A.field "scalar" "MoonBack.BackScalar",          A.variant_unique },
            A.variant "CArray"      { A.field "elem" "MoonC.CTypeId", A.field "count" "number", A.variant_unique },
            A.variant "CStruct",
            A.variant "CUnion",
            A.variant "COpaque",
            A.variant "CFuncPtr"    { A.field "sig" "MoonC.CFuncSigId",              A.variant_unique },
        },

        A.product "CTypeFact" {
            A.field "id" "MoonC.CTypeId",
            A.field "kind" "MoonC.CTypeKind",
            A.field "complete" "boolean",
            A.field "size" (A.optional "number"),
            A.field "align" (A.optional "number"),
            A.unique,
        },

        A.product "CFieldLayout" {
            A.field "owner" "MoonC.CTypeId",
            A.field "name" "string",
            A.field "type" "MoonC.CTypeId",
            A.field "offset" "number",
            A.field "size" "number",
            A.field "align" "number",
            A.field "bit_offset" (A.optional "number"),
            A.field "bit_width" (A.optional "number"),
            A.unique,
        },

        A.product "CLayoutFact" {
            A.field "type" "MoonC.CTypeId",
            A.field "size" "number",
            A.field "align" "number",
            A.field "fields" (A.many "MoonC.CFieldLayout"),
            A.unique,
        },

        A.product "CFuncSigId"     { A.field "text" "string", A.unique },

        A.product "CFuncSig" {
            A.field "id" "MoonC.CFuncSigId",
            A.field "params" (A.many "MoonC.CTypeId"),
            A.field "result" "MoonC.CTypeId",
            A.unique,
        },

        A.product "CExternFunc" {
            A.field "moon_name" "string",
            A.field "symbol" "string",
            A.field "sig" "MoonC.CFuncSigId",
            A.field "library" (A.optional "string"),
            A.unique,
        },

        A.product "CLibrary" {
            A.field "name" "string",
            A.field "link_name" (A.optional "string"),
            A.field "path" (A.optional "string"),
            A.field "symbols" (A.many "string"),
            A.unique,
        },

        -- C backend side-projection ASDL.
        -- These nodes are not the parsed-C AST (`MoonCAst`) and not the
        -- Cranelift-oriented backend tape (`MoonBack`).  They describe the
        -- deliberately small C dialect produced from the typed/resolved
        -- Moonlift program layer.  See C_BACKEND_DESIGN.md.

        A.product "CBackendName" { A.field "text" "string", A.unique },
        A.product "CBackendLabel" { A.field "text" "string", A.unique },
        A.product "CBackendLocalId" { A.field "text" "string", A.unique },
        A.product "CBackendGlobalId" { A.field "text" "string", A.unique },
        A.product "CBackendHelperId" { A.field "text" "string", A.unique },
        A.product "CBackendFuncSigId" { A.field "text" "string", A.unique },

        A.sum "CBackendDialect" {
            A.variant "CBackendC99",
            A.variant "CBackendC11",
            A.variant "CBackendGnuC",
            A.variant "CBackendClangC",
        },

        A.sum "CBackendPlatform" {
            A.variant "CBackendHostedNative",
            A.variant "CBackendFreestanding",
            A.variant "CBackendWasmCapable",
            A.variant "CBackendEmbedded",
        },

        A.sum "CBackendEndian" {
            A.variant "CBackendLittleEndian",
            A.variant "CBackendBigEndian",
        },

        A.product "CBackendTarget" {
            A.field "dialect" "MoonC.CBackendDialect",
            A.field "platform" "MoonC.CBackendPlatform",
            A.field "pointer_bits" "number",
            A.field "index_bits" "number",
            A.field "endian" "MoonC.CBackendEndian",
            A.field "hosted" "boolean",
            A.unique,
        },

        A.sum "CBackendType" {
            A.variant "CBackendVoid",
            A.variant "CBackendBool8",
            A.variant "CBackendScalar" {
                A.field "scalar" "MoonCore.Scalar",
                A.variant_unique,
            },
            A.variant "CBackendIndex",
            A.variant "CBackendDataPtr" {
                A.field "pointee" (A.optional "MoonC.CBackendType"),
                A.variant_unique,
            },
            A.variant "CBackendCodePtr" {
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.variant_unique,
            },
            A.variant "CBackendNamed" {
                A.field "id" "MoonC.CTypeId",
                A.variant_unique,
            },
            A.variant "CBackendArray" {
                A.field "elem" "MoonC.CBackendType",
                A.field "count" "number",
                A.variant_unique,
            },
            A.variant "CBackendSliceDescriptor" {
                A.field "elem" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendViewDescriptor" {
                A.field "elem" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendClosureDescriptor" {
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.field "ctx" (A.optional "MoonC.CBackendType"),
                A.variant_unique,
            },
            A.variant "CBackendAbiHiddenOutPtr" {
                A.field "result" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendImportedCodePtr" {
                A.field "sig" "MoonC.CFuncSigId",
                A.variant_unique,
            },
            A.variant "CBackendVector" {
                A.field "elem" "MoonC.CBackendType",
                A.field "lanes" "number",
                A.variant_unique,
            },
        },

        A.product "CBackendParam" {
            A.field "name" "MoonC.CBackendName",
            A.field "ty" "MoonC.CBackendType",
            A.unique,
        },

        A.sum "CBackendFuncLinkage" {
            A.variant "CBackendLinkInternal",
            A.variant "CBackendLinkExport",
            A.variant "CBackendLinkExtern",
            A.variant "CBackendLinkDecl",
            A.variant "CBackendLinkWrapper",
            A.variant "CBackendLinkIndirect",
        },

        A.sum "CBackendAbiParamRole" {
            A.variant "CBackendAbiParamDirect",
            A.variant "CBackendAbiParamByAddress",
            A.variant "CBackendAbiParamDescriptor",
            A.variant "CBackendAbiParamHiddenOut",
        },

        A.sum "CBackendAbiResultRole" {
            A.variant "CBackendAbiResultVoid",
            A.variant "CBackendAbiResultDirect",
            A.variant "CBackendAbiResultByAddress",
            A.variant "CBackendAbiResultHiddenOut",
            A.variant "CBackendAbiResultDescriptor",
        },

        A.product "CBackendAbiParam" {
            A.field "name" "MoonC.CBackendName",
            A.field "source_ty" "MoonC.CBackendType",
            A.field "lowered_ty" "MoonC.CBackendType",
            A.field "role" "MoonC.CBackendAbiParamRole",
            A.unique,
        },

        A.product "CBackendAbiResult" {
            A.field "source_ty" "MoonC.CBackendType",
            A.field "lowered_ty" "MoonC.CBackendType",
            A.field "role" "MoonC.CBackendAbiResultRole",
            A.unique,
        },

        A.product "CBackendFuncAbi" {
            A.field "id" "MoonC.CBackendFuncSigId",
            A.field "linkage" "MoonC.CBackendFuncLinkage",
            A.field "params" (A.many "MoonC.CBackendAbiParam"),
            A.field "result" "MoonC.CBackendAbiResult",
            A.field "imported_sig" (A.optional "MoonC.CFuncSigId"),
            A.unique,
        },

        A.product "CBackendFuncSig" {
            A.field "id" "MoonC.CBackendFuncSigId",
            A.field "params" (A.many "MoonC.CBackendType"),
            A.field "result" "MoonC.CBackendType",
            A.unique,
        },

        A.product "CBackendField" {
            A.field "name" "MoonC.CBackendName",
            A.field "ty" "MoonC.CBackendType",
            A.field "offset" (A.optional "number"),
            A.field "size" (A.optional "number"),
            A.field "align" (A.optional "number"),
            A.unique,
        },

        A.sum "CBackendTypeDecl" {
            A.variant "CBackendTypedef" {
                A.field "id" "MoonC.CTypeId",
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendStructDecl" {
                A.field "id" "MoonC.CTypeId",
                A.field "fields" (A.many "MoonC.CBackendField"),
                A.field "size" (A.optional "number"),
                A.field "align" (A.optional "number"),
                A.variant_unique,
            },
            A.variant "CBackendUnionDecl" {
                A.field "id" "MoonC.CTypeId",
                A.field "fields" (A.many "MoonC.CBackendField"),
                A.field "size" (A.optional "number"),
                A.field "align" (A.optional "number"),
                A.variant_unique,
            },
            A.variant "CBackendOpaqueDecl" {
                A.field "id" "MoonC.CTypeId",
                A.variant_unique,
            },
        },

        A.sum "CBackendResidence" {
            A.variant "CBackendResidenceValue",
            A.variant "CBackendResidenceAddressed",
            A.variant "CBackendResidenceAggregate",
            A.variant "CBackendResidenceDescriptor",
        },

        A.sum "CBackendLocalInitState" {
            A.variant "CBackendLocalUninitialized",
            A.variant "CBackendLocalZeroInitialized",
            A.variant "CBackendLocalInitialized",
        },

        A.sum "CBackendPlace" {
            A.variant "CBackendPlaceLocal" {
                A.field "local" "MoonC.CBackendLocalId",
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendPlaceGlobal" {
                A.field "global" "MoonC.CBackendGlobalId",
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendPlaceDeref" {
                A.field "addr" "MoonC.CBackendAtom",
                A.field "ty" "MoonC.CBackendType",
                A.field "align" (A.optional "number"),
                A.variant_unique,
            },
            A.variant "CBackendPlaceField" {
                A.field "base" "MoonC.CBackendPlace",
                A.field "field" "MoonC.CBackendName",
                A.field "ty" "MoonC.CBackendType",
                A.field "offset" "number",
                A.field "size" (A.optional "number"),
                A.field "align" (A.optional "number"),
                A.variant_unique,
            },
            A.variant "CBackendPlaceIndex" {
                A.field "base" "MoonC.CBackendPlace",
                A.field "index" "MoonC.CBackendAtom",
                A.field "ty" "MoonC.CBackendType",
                A.field "elem_size" "number",
                A.variant_unique,
            },
            A.variant "CBackendPlaceBytes" {
                A.field "base" "MoonC.CBackendAtom",
                A.field "offset" "number",
                A.field "ty" "MoonC.CBackendType",
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
        },

        A.product "CBackendLocalStorage" {
            A.field "id" "MoonC.CBackendLocalId",
            A.field "name" "MoonC.CBackendName",
            A.field "ty" "MoonC.CBackendType",
            A.field "residence" "MoonC.CBackendResidence",
            A.field "init_state" "MoonC.CBackendLocalInitState",
            A.field "address_taken" "boolean",
            A.unique,
        },

        A.sum "CBackendRelocTarget" {
            A.variant "CBackendRelocGlobal" {
                A.field "global" "MoonC.CBackendGlobalId",
                A.variant_unique,
            },
            A.variant "CBackendRelocFunc" {
                A.field "func" "MoonC.CBackendName",
                A.variant_unique,
            },
            A.variant "CBackendRelocExtern" {
                A.field "extern" "MoonC.CBackendName",
                A.variant_unique,
            },
        },

        A.sum "CBackendDataInit" {
            A.variant "CBackendDataZero" {
                A.field "offset" "number",
                A.field "size" "number",
                A.variant_unique,
            },
            A.variant "CBackendDataBytes" {
                A.field "offset" "number",
                A.field "bytes" "string",
                A.variant_unique,
            },
            A.variant "CBackendDataScalar" {
                A.field "offset" "number",
                A.field "ty" "MoonC.CBackendType",
                A.field "literal" "MoonCore.Literal",
                A.variant_unique,
            },
            A.variant "CBackendDataReloc" {
                A.field "offset" "number",
                A.field "target" "MoonC.CBackendRelocTarget",
                A.field "addend" "number",
                A.variant_unique,
            },
        },

        A.product "CBackendGlobal" {
            A.field "id" "MoonC.CBackendGlobalId",
            A.field "name" "MoonC.CBackendName",
            A.field "visibility" "MoonCore.Visibility",
            A.field "ty" "MoonC.CBackendType",
            A.field "size" "number",
            A.field "align" "number",
            A.field "inits" (A.many "MoonC.CBackendDataInit"),
            A.unique,
        },

        A.product "CBackendExtern" {
            A.field "name" "MoonC.CBackendName",
            A.field "symbol" "string",
            A.field "sig" "MoonC.CBackendFuncSigId",
            A.field "header" (A.optional "string"),
            A.unique,
        },

        A.sum "CBackendAtom" {
            A.variant "CBackendAtomLocal" {
                A.field "local" "MoonC.CBackendLocalId",
                A.variant_unique,
            },
            A.variant "CBackendAtomGlobal" {
                A.field "global" "MoonC.CBackendGlobalId",
                A.variant_unique,
            },
            A.variant "CBackendAtomLiteral" {
                A.field "ty" "MoonC.CBackendType",
                A.field "literal" "MoonCore.Literal",
                A.variant_unique,
            },
            A.variant "CBackendAtomNull" {
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
        },

        A.sum "CBackendRValue" {
            A.variant "CBackendRAtom" {
                A.field "atom" "MoonC.CBackendAtom",
                A.variant_unique,
            },
            A.variant "CBackendRCompare" {
                A.field "op" "MoonCore.CmpOp",
                A.field "ty" "MoonC.CBackendType",
                A.field "lhs" "MoonC.CBackendAtom",
                A.field "rhs" "MoonC.CBackendAtom",
                A.variant_unique,
            },
            A.variant "CBackendRCast" {
                A.field "op" "MoonCore.MachineCastOp",
                A.field "to" "MoonC.CBackendType",
                A.field "value" "MoonC.CBackendAtom",
                A.variant_unique,
            },
            A.variant "CBackendRSelect" {
                A.field "ty" "MoonC.CBackendType",
                A.field "cond" "MoonC.CBackendAtom",
                A.field "then_value" "MoonC.CBackendAtom",
                A.field "else_value" "MoonC.CBackendAtom",
                A.variant_unique,
            },
            A.variant "CBackendRFuncAddr" {
                A.field "func" "MoonC.CBackendName",
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.variant_unique,
            },
            A.variant "CBackendRExternAddr" {
                A.field "extern" "MoonC.CBackendName",
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.variant_unique,
            },
            A.variant "CBackendRPtrOffset" {
                A.field "base" "MoonC.CBackendAtom",
                A.field "index" "MoonC.CBackendAtom",
                A.field "elem_size" "number",
                A.field "const_offset" "number",
                A.variant_unique,
            },
            A.variant "CBackendRAddrOfPlace" {
                A.field "place" "MoonC.CBackendPlace",
                A.variant_unique,
            },
        },

        A.sum "CBackendTrapMode" {
            A.variant "CBackendMayTrap",
            A.variant "CBackendMustNotTrap",
            A.variant "CBackendCheckedTrap",
        },

        A.product "CBackendMemoryAccess" {
            A.field "ty" "MoonC.CBackendType",
            A.field "align" "number",
            A.field "trap" "MoonC.CBackendTrapMode",
            A.field "volatile" "boolean",
            A.field "ordering" (A.optional "MoonCore.AtomicOrdering"),
            A.unique,
        },

        A.sum "CBackendIntOverflow" {
            A.variant "CBackendIntWrap",
            A.variant "CBackendIntTrapOnOverflow",
            A.variant "CBackendIntAssumeNoOverflow",
        },

        A.sum "CBackendDivMode" {
            A.variant "CBackendDivTrapOnZero",
            A.variant "CBackendDivTrapOnZeroOrOverflow",
        },

        A.sum "CBackendShiftMode" {
            A.variant "CBackendShiftMaskCount",
            A.variant "CBackendShiftTrapOutOfRange",
        },

        A.sum "CBackendTargetFeature" {
            A.variant "CBackendFeatureC11Atomics",
            A.variant "CBackendFeatureLibm",
            A.variant "CBackendFeatureBuiltinOverflow",
            A.variant "CBackendFeatureBuiltinBitops",
            A.variant "CBackendFeatureUnalignedAccess",
            A.variant "CBackendFeatureStaticAssert",
            A.variant "CBackendFeatureHostedRuntime",
        },

        A.product "CBackendLayoutAssertion" {
            A.field "id" "MoonC.CTypeId",
            A.field "size" "number",
            A.field "align" "number",
            A.unique,
        },

        A.sum "CBackendHelperKind" {
            A.variant "CBackendHelperUnary" {
                A.field "op" "MoonCore.UnaryOp",
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendHelperBoolNormalize" {
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendHelperCast" {
                A.field "op" "MoonCore.MachineCastOp",
                A.field "from" "MoonC.CBackendType",
                A.field "to" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendHelperPtrOffset" {
                A.field "pointee" "MoonC.CBackendType",
                A.field "elem_size" "number",
                A.field "checked" "boolean",
                A.variant_unique,
            },
            A.variant "CBackendHelperIntBinary" {
                A.field "op" "MoonCore.BinaryOp",
                A.field "ty" "MoonC.CBackendType",
                A.field "overflow" "MoonC.CBackendIntOverflow",
                A.variant_unique,
            },
            A.variant "CBackendHelperDivRem" {
                A.field "op" "MoonCore.BinaryOp",
                A.field "ty" "MoonC.CBackendType",
                A.field "mode" "MoonC.CBackendDivMode",
                A.variant_unique,
            },
            A.variant "CBackendHelperShift" {
                A.field "op" "MoonCore.BinaryOp",
                A.field "ty" "MoonC.CBackendType",
                A.field "mode" "MoonC.CBackendShiftMode",
                A.variant_unique,
            },
            A.variant "CBackendHelperIntrinsic" {
                A.field "intrinsic" "MoonCore.Intrinsic",
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendHelperLoad" {
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.variant_unique,
            },
            A.variant "CBackendHelperStore" {
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.variant_unique,
            },
            A.variant "CBackendHelperAtomicLoad" {
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.variant_unique,
            },
            A.variant "CBackendHelperAtomicStore" {
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.variant_unique,
            },
            A.variant "CBackendHelperAtomicRmw" {
                A.field "op" "MoonCore.AtomicRmwOp",
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.variant_unique,
            },
            A.variant "CBackendHelperAtomicCas" {
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.field "success_ordering" "MoonCore.AtomicOrdering",
                A.field "failure_ordering" "MoonCore.AtomicOrdering",
                A.variant_unique,
            },
            A.variant "CBackendHelperAtomicFence" {
                A.field "ordering" "MoonCore.AtomicOrdering",
                A.variant_unique,
            },
            A.variant "CBackendHelperMemcpy",
            A.variant "CBackendHelperTypedMemcpy" {
                A.field "ty" "MoonC.CBackendType",
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "CBackendHelperMemset",
            A.variant "CBackendHelperTypedMemset" {
                A.field "ty" "MoonC.CBackendType",
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "CBackendHelperMemcmp",
            A.variant "CBackendHelperLayoutAssert" {
                A.field "assertion" "MoonC.CBackendLayoutAssertion",
                A.variant_unique,
            },
            A.variant "CBackendHelperRequireFeature" {
                A.field "feature" "MoonC.CBackendTargetFeature",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "CBackendHelperTrap",
        },

        A.product "CBackendHelperUse" {
            A.field "id" "MoonC.CBackendHelperId",
            A.field "kind" "MoonC.CBackendHelperKind",
            A.unique,
        },

        A.product "CBackendLocal" {
            A.field "id" "MoonC.CBackendLocalId",
            A.field "name" "MoonC.CBackendName",
            A.field "ty" "MoonC.CBackendType",
            A.unique,
        },

        A.product "CBackendAggregateFieldInit" {
            A.field "field" "MoonC.CBackendName",
            A.field "value" "MoonC.CBackendAtom",
            A.field "offset" (A.optional "number"),
            A.unique,
        },

        A.product "CBackendArrayElemInit" {
            A.field "index" "number",
            A.field "value" "MoonC.CBackendAtom",
            A.unique,
        },

        A.sum "CBackendCallTarget" {
            A.variant "CBackendCallDirect" {
                A.field "func" "MoonC.CBackendName",
                A.variant_unique,
            },
            A.variant "CBackendCallExtern" {
                A.field "extern" "MoonC.CBackendName",
                A.variant_unique,
            },
            A.variant "CBackendCallIndirect" {
                A.field "callee" "MoonC.CBackendAtom",
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.variant_unique,
            },
        },

        A.sum "CBackendStmt" {
            A.variant "CBackendAssign" {
                A.field "dst" "MoonC.CBackendLocalId",
                A.field "rhs" "MoonC.CBackendRValue",
                A.variant_unique,
            },
            A.variant "CBackendHelperCall" {
                A.field "dst" (A.optional "MoonC.CBackendLocalId"),
                A.field "helper" "MoonC.CBackendHelperId",
                A.field "args" (A.many "MoonC.CBackendAtom"),
                A.variant_unique,
            },
            A.variant "CBackendLoad" {
                A.field "dst" "MoonC.CBackendLocalId",
                A.field "addr" "MoonC.CBackendAtom",
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.variant_unique,
            },
            A.variant "CBackendStore" {
                A.field "addr" "MoonC.CBackendAtom",
                A.field "value" "MoonC.CBackendAtom",
                A.field "access" "MoonC.CBackendMemoryAccess",
                A.variant_unique,
            },
            A.variant "CBackendPlaceLoad" {
                A.field "dst" "MoonC.CBackendLocalId",
                A.field "place" "MoonC.CBackendPlace",
                A.variant_unique,
            },
            A.variant "CBackendPlaceStore" {
                A.field "place" "MoonC.CBackendPlace",
                A.field "value" "MoonC.CBackendAtom",
                A.variant_unique,
            },
            A.variant "CBackendZeroInit" {
                A.field "place" "MoonC.CBackendPlace",
                A.field "ty" "MoonC.CBackendType",
                A.field "size" "number",
                A.variant_unique,
            },
            A.variant "CBackendAggregateInit" {
                A.field "place" "MoonC.CBackendPlace",
                A.field "ty" "MoonC.CBackendType",
                A.field "fields" (A.many "MoonC.CBackendAggregateFieldInit"),
                A.variant_unique,
            },
            A.variant "CBackendArrayInit" {
                A.field "place" "MoonC.CBackendPlace",
                A.field "ty" "MoonC.CBackendType",
                A.field "elems" (A.many "MoonC.CBackendArrayElemInit"),
                A.variant_unique,
            },
            A.variant "CBackendCall" {
                A.field "dst" (A.optional "MoonC.CBackendLocalId"),
                A.field "target" "MoonC.CBackendCallTarget",
                A.field "args" (A.many "MoonC.CBackendAtom"),
                A.variant_unique,
            },
            A.variant "CBackendComment" {
                A.field "text" "string",
                A.variant_unique,
            },
        },

        A.product "CBackendSwitchCase" {
            A.field "literal" "MoonCore.Literal",
            A.field "dest" "MoonC.CBackendLabel",
            A.field "args" (A.many "MoonC.CBackendAtom"),
            A.unique,
        },

        A.sum "CBackendTerminator" {
            A.variant "CBackendGoto" {
                A.field "dest" "MoonC.CBackendLabel",
                A.field "args" (A.many "MoonC.CBackendAtom"),
                A.variant_unique,
            },
            A.variant "CBackendIfGoto" {
                A.field "cond" "MoonC.CBackendAtom",
                A.field "then_dest" "MoonC.CBackendLabel",
                A.field "then_args" (A.many "MoonC.CBackendAtom"),
                A.field "else_dest" "MoonC.CBackendLabel",
                A.field "else_args" (A.many "MoonC.CBackendAtom"),
                A.variant_unique,
            },
            A.variant "CBackendSwitchGoto" {
                A.field "value" "MoonC.CBackendAtom",
                A.field "cases" (A.many "MoonC.CBackendSwitchCase"),
                A.field "default_dest" "MoonC.CBackendLabel",
                A.field "default_args" (A.many "MoonC.CBackendAtom"),
                A.variant_unique,
            },
            A.variant "CBackendReturnVoid",
            A.variant "CBackendReturn" {
                A.field "value" "MoonC.CBackendAtom",
                A.variant_unique,
            },
            A.variant "CBackendTrap",
        },

        A.product "CBackendBlockParam" {
            A.field "local" "MoonC.CBackendLocalId",
            A.field "ty" "MoonC.CBackendType",
            A.unique,
        },

        A.product "CBackendBlock" {
            A.field "label" "MoonC.CBackendLabel",
            A.field "params" (A.many "MoonC.CBackendBlockParam"),
            A.field "stmts" (A.many "MoonC.CBackendStmt"),
            A.field "term" "MoonC.CBackendTerminator",
            A.unique,
        },

        A.product "CBackendFunc" {
            A.field "name" "MoonC.CBackendName",
            A.field "symbol" "string",
            A.field "visibility" "MoonCore.Visibility",
            A.field "sig" "MoonC.CBackendFuncSigId",
            A.field "params" (A.many "MoonC.CBackendLocal"),
            A.field "locals" (A.many "MoonC.CBackendLocal"),
            A.field "blocks" (A.many "MoonC.CBackendBlock"),
            A.unique,
        },

        A.product "CBackendUnit" {
            A.field "module_name" "string",
            A.field "target" "MoonC.CBackendTarget",
            A.field "sigs" (A.many "MoonC.CBackendFuncSig"),
            A.field "types" (A.many "MoonC.CBackendTypeDecl"),
            A.field "globals" (A.many "MoonC.CBackendGlobal"),
            A.field "externs" (A.many "MoonC.CBackendExtern"),
            A.field "helpers" (A.many "MoonC.CBackendHelperUse"),
            A.field "funcs" (A.many "MoonC.CBackendFunc"),
            A.unique,
        },

        A.sum "CBackendValidationIssue" {
            A.variant "CBackendIssueDuplicateSig" { A.field "sig" "MoonC.CBackendFuncSigId", A.variant_unique },
            A.variant "CBackendIssueMissingSig" { A.field "sig" "MoonC.CBackendFuncSigId", A.variant_unique },
            A.variant "CBackendIssueDuplicateFunc" { A.field "func" "MoonC.CBackendName", A.variant_unique },
            A.variant "CBackendIssueMissingFunc" { A.field "func" "MoonC.CBackendName", A.variant_unique },
            A.variant "CBackendIssueDuplicateExtern" { A.field "extern" "MoonC.CBackendName", A.variant_unique },
            A.variant "CBackendIssueMissingExtern" { A.field "extern" "MoonC.CBackendName", A.variant_unique },
            A.variant "CBackendIssueDuplicateGlobal" { A.field "global" "MoonC.CBackendGlobalId", A.variant_unique },
            A.variant "CBackendIssueMissingGlobal" { A.field "global" "MoonC.CBackendGlobalId", A.variant_unique },
            A.variant "CBackendIssueDuplicateHelper" { A.field "helper" "MoonC.CBackendHelperId", A.variant_unique },
            A.variant "CBackendIssueMissingHelper" { A.field "helper" "MoonC.CBackendHelperId", A.variant_unique },
            A.variant "CBackendIssueDuplicateLocal" {
                A.field "func" "MoonC.CBackendName",
                A.field "local" "MoonC.CBackendLocalId",
                A.variant_unique,
            },
            A.variant "CBackendIssueMissingLocal" {
                A.field "func" "MoonC.CBackendName",
                A.field "local" "MoonC.CBackendLocalId",
                A.variant_unique,
            },
            A.variant "CBackendIssueDuplicateLabel" {
                A.field "func" "MoonC.CBackendName",
                A.field "label" "MoonC.CBackendLabel",
                A.variant_unique,
            },
            A.variant "CBackendIssueMissingLabel" {
                A.field "func" "MoonC.CBackendName",
                A.field "label" "MoonC.CBackendLabel",
                A.variant_unique,
            },
            A.variant "CBackendIssueInvalidCName" {
                A.field "site" "string",
                A.field "name" "MoonC.CBackendName",
                A.variant_unique,
            },
            A.variant "CBackendIssueDuplicateCName" {
                A.field "site" "string",
                A.field "name" "MoonC.CBackendName",
                A.variant_unique,
            },
            A.variant "CBackendIssueFuncSigMismatch" {
                A.field "func" "MoonC.CBackendName",
                A.field "expected" "MoonC.CBackendType",
                A.field "actual" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueBlockArgCount" {
                A.field "func" "MoonC.CBackendName",
                A.field "label" "MoonC.CBackendLabel",
                A.field "expected" "number",
                A.field "actual" "number",
                A.variant_unique,
            },
            A.variant "CBackendIssueBlockArgType" {
                A.field "func" "MoonC.CBackendName",
                A.field "label" "MoonC.CBackendLabel",
                A.field "index" "number",
                A.field "expected" "MoonC.CBackendType",
                A.field "actual" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueCallArgCount" {
                A.field "site" "string",
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.field "expected" "number",
                A.field "actual" "number",
                A.variant_unique,
            },
            A.variant "CBackendIssueCallArgType" {
                A.field "site" "string",
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.field "index" "number",
                A.field "expected" "MoonC.CBackendType",
                A.field "actual" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueCallResultType" {
                A.field "site" "string",
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.field "expected" "MoonC.CBackendType",
                A.field "actual" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueIndirectCallNonCodePtr" {
                A.field "site" "string",
                A.field "actual" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueDataCodePtrConfusion" {
                A.field "site" "string",
                A.field "ty" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueHelperMismatch" {
                A.field "helper" "MoonC.CBackendHelperId",
                A.field "message" "string",
                A.variant_unique,
            },
            A.variant "CBackendIssueInvalidAlignment" {
                A.field "site" "string",
                A.field "align" "number",
                A.variant_unique,
            },
            A.variant "CBackendIssueDataInitOutOfBounds" {
                A.field "global" "MoonC.CBackendGlobalId",
                A.field "offset" "number",
                A.field "size" "number",
                A.field "global_size" "number",
                A.variant_unique,
            },
            A.variant "CBackendIssueCoverageMissing" {
                A.field "sum" "string",
                A.field "variant" "string",
                A.variant_unique,
            },
            A.variant "CBackendIssueInvalidTargetFeature" {
                A.field "feature" "MoonC.CBackendTargetFeature",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "CBackendIssueLayoutAssertionMissing" {
                A.field "id" "MoonC.CTypeId",
                A.variant_unique,
            },
            A.variant "CBackendIssueLayoutAssertionMismatch" {
                A.field "id" "MoonC.CTypeId",
                A.field "expected_size" "number",
                A.field "actual_size" "number",
                A.field "expected_align" "number",
                A.field "actual_align" "number",
                A.variant_unique,
            },
            A.variant "CBackendIssuePlaceTypeMismatch" {
                A.field "site" "string",
                A.field "place" "MoonC.CBackendPlace",
                A.field "expected" "MoonC.CBackendType",
                A.field "actual" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueLoadStoreTypeMismatch" {
                A.field "site" "string",
                A.field "expected" "MoonC.CBackendType",
                A.field "actual" "MoonC.CBackendType",
                A.variant_unique,
            },
            A.variant "CBackendIssueUnmaterializedAddressTakenValue" {
                A.field "func" "MoonC.CBackendName",
                A.field "local" "MoonC.CBackendLocalId",
                A.variant_unique,
            },
            A.variant "CBackendIssueUninitializedLocal" {
                A.field "func" "MoonC.CBackendName",
                A.field "local" "MoonC.CBackendLocalId",
                A.variant_unique,
            },
            A.variant "CBackendIssueHelperSignatureMismatch" {
                A.field "helper" "MoonC.CBackendHelperId",
                A.field "expected" (A.many "MoonC.CBackendType"),
                A.field "actual" (A.many "MoonC.CBackendType"),
                A.variant_unique,
            },
            A.variant "CBackendIssueDataInitPrecisionFailure" {
                A.field "global" "MoonC.CBackendGlobalId",
                A.field "offset" "number",
                A.field "ty" "MoonC.CBackendType",
                A.field "literal" "MoonCore.Literal",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "CBackendIssueDataRelocFailure" {
                A.field "global" "MoonC.CBackendGlobalId",
                A.field "offset" "number",
                A.field "target" "MoonC.CBackendRelocTarget",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "CBackendIssueAbiMismatch" {
                A.field "site" "string",
                A.field "sig" "MoonC.CBackendFuncSigId",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "CBackendIssueUnsupportedConstruct" {
                A.field "sum" "string",
                A.field "variant" "string",
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "CBackendIssueUnreachableConstruct" {
                A.field "sum" "string",
                A.field "variant" "string",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.product "CBackendStorageRecord" {
            A.field "func" "MoonC.CBackendName",
            A.field "storage" (A.many "MoonC.CBackendLocalStorage"),
            A.unique,
        },

        A.product "CBackendValidationInput" {
            A.field "unit" "MoonC.CBackendUnit",
            A.field "storage" (A.many "MoonC.CBackendStorageRecord"),
            A.field "abi_issues" (A.many "MoonC.CBackendValidationIssue"),
            A.unique,
        },

        A.product "CBackendValidationReport" {
            A.field "issues" (A.many "MoonC.CBackendValidationIssue"),
            A.unique,
        },
    }
end
