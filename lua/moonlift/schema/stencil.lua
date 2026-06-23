local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonStencil {
  product. StencilId { interned, text [str], },
  product. StencilInstanceId { interned, text [str], },
  product. StencilSymbolId { interned, text [str], },
  product. StencilProviderId { interned, text [str], },

  sum. StencilProvider {
    StencilProviderC,
    StencilProviderCranelift,
    StencilProviderLuaTrace,
    StencilProviderNamed {
      variant_unique,
      field. id [MoonStencil.StencilProviderId],
      field. name [str],
    },
  },

  sum. StencilVocab {
    StencilReduceArray,
    StencilMapArray,
    StencilZipMapArray,
    StencilScanArray,
    StencilCopyArray,
    StencilFillArray,
    StencilFindArray,
    StencilPartitionArray,
  },

  sum. StencilParam {
    StencilParamType {
      variant_unique,
      field. name [str],
      field. ty [MoonCode.CodeType],
    },
    StencilParamReduction {
      variant_unique,
      field. name [str],
      reduction [MoonValue.ReductionKind],
    },
    StencilParamIntSemantics {
      variant_unique,
      field. name [str],
      semantics [MoonCode.CodeIntSemantics],
    },
    StencilParamFloatMode {
      variant_unique,
      field. name [str],
      mode [MoonCode.CodeFloatMode],
    },
    StencilParamValueExpr {
      variant_unique,
      field. name [str],
      field. expr [MoonValue.ValueExpr],
    },
    StencilParamNumber {
      variant_unique,
      field. name [str],
      field. value [number],
    },
    StencilParamText {
      variant_unique,
      field. name [str],
      field. value [str],
    },
  },

  product. StencilAbi {
    interned,
    params [many [MoonCode.CodeType]],
    result [optional [MoonCode.CodeType]],
  },

  sum. StencilShape {
    StencilShapeReduceArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      reduction [MoonValue.ReductionKind],
      int_semantics [optional [MoonCode.CodeIntSemantics]],
      float_mode [optional [MoonCode.CodeFloatMode]],
      init [MoonValue.ValueExpr],
      stride [number],
    },
    StencilShapeMapArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      op [str],
    },
    StencilShapeZipMapArray {
      variant_unique,
      lhs_ty [MoonCode.CodeType],
      rhs_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      op [str],
    },
    StencilShapeScanArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      reduction [MoonValue.ReductionKind],
    },
    StencilShapeCopyArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
    },
    StencilShapeFillArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
    },
    StencilShapeFindArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      pred [str],
    },
    StencilShapePartitionArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      pred [str],
    },
  },

  product. StencilInstance {
    interned,
    field. id [MoonStencil.StencilInstanceId],
    vocab [MoonStencil.StencilVocab],
    shape [MoonStencil.StencilShape],
    params [many [MoonStencil.StencilParam]],
    abi [MoonStencil.StencilAbi],
    proofs [many [MoonKernel.KernelProof]],
  },

  sum. StencilReject {
    StencilRejectUnsupportedVocab {
      variant_unique,
      vocab [MoonStencil.StencilVocab],
      reason [str],
    },
    StencilRejectUnsupportedType {
      variant_unique,
      field. ty [MoonCode.CodeType],
      reason [str],
    },
    StencilRejectUnsupportedReduction {
      variant_unique,
      reduction [MoonValue.ReductionKind],
      reason [str],
    },
    StencilRejectMissingProof {
      variant_unique,
      reason [str],
    },
    StencilRejectProvider {
      variant_unique,
      provider [MoonStencil.StencilProvider],
      reason [str],
    },
  },

  sum. StencilSelection {
    StencilSelected {
      variant_unique,
      instance [MoonStencil.StencilInstance],
    },
    StencilNoSelection {
      variant_unique,
      vocab [MoonStencil.StencilVocab],
      rejects [many [MoonStencil.StencilReject]],
    },
  },

  product. StencilArtifact {
    interned,
    instance [MoonStencil.StencilInstance],
    provider [MoonStencil.StencilProvider],
    symbol [MoonStencil.StencilSymbolId],
    c_signature [str],
  },

  product. StencilModulePlan {
    interned,
    field. module [MoonCode.CodeModuleId],
    kernel [MoonKernel.KernelModulePlan],
    selections [many [MoonStencil.StencilSelection]],
  },
}
