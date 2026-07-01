local S = require("lalin.schema.dsl")
S.use()

return schema. LalinLuaTrace {
  product. LTModuleId { interned, text [str], },
  product. LTFuncId { interned, text [str], },
  product. LTLocalId { interned, text [str], },

  sum. LTExpr {
    LTExprText {
      variant_unique,
      text [str],
      reason [str],
    },
  },

  product. LTParam {
    interned,
    field. name [str],
  },

  product. LTAccessPlanEntry {
    interned,
    field. name [str],
    role [LalinStencil.StencilAccessRole],
    ty [LalinCode.CodeType],
    layout [LalinStencil.StencilAccessLayout],
    readonly [bool],
    readwrite [bool],
    alignment_fact [LalinStencil.StencilAlignmentFact],
    unit_stride [bool],
    dynamic_stride_arg [optional [str]],
    stride_const [optional [number]],
    field_name [optional [str]],
    field_offset [optional [number]],
    component_index [optional [number]],
    index_name [optional [str]],
    index_stride [optional [number]],
    element_bytes [optional [number]],
    parent [optional [LalinLuaTrace.LTAccessPlanEntry]],
    can_pointer_bump [bool],
    can_bulk_copy [bool],
    can_bulk_fill [bool],
  },

  product. LTAccessPlanSet {
    interned,
    entries [many [LalinLuaTrace.LTAccessPlanEntry]],
  },

  sum. LTPredicatePolicy {
    LTPredicateNone,
    LTPredicateLuaSelect {
      variant_unique,
      rejected [optional [str]],
    },
    LTPredicateNumericStore {
      variant_unique,
      rejected [optional [str]],
    },
    LTPredicateBranch {
      variant_unique,
      rejected [optional [str]],
    },
    LTPredicateMultiCounterBranch {
      variant_unique,
      counters [number],
      rejected [optional [str]],
    },
  },

  sum. LTPrimitivePolicy {
    LTPrimitiveNone,
    LTPrimitiveFfiCopy {
      variant_unique,
      bytes_per_element [number],
      dst_name [str],
      src_name [str],
      no_overlap_source [str],
    },
    LTPrimitiveFfiFill {
      variant_unique,
      bytes_per_element [number],
      dst_name [str],
      value_name [str],
    },
  },

  sum. LTScatterPolicy {
    LTScatterNone,
    LTScatterUniqueIndices,
    LTScatterOrderedLastWrite,
    LTScatterConflictUndefined,
    LTScatterUnknown { variant_unique, reason [str], },
  },

  sum. LTReductionPolicy {
    LTReductionNone,
    LTReductionOrderedSingleAccumulator {
      variant_unique,
      reassociation_required [bool],
      reassociable [bool],
      multi_accumulator [bool],
      multi_accumulator_rejected [str],
    },
  },

  product. LTPlanSummary {
    interned,
    reason [str],
    group [number],
    tail_strategy [str],
    primitive [LalinLuaTrace.LTPrimitivePolicy],
    predicate [LalinLuaTrace.LTPredicatePolicy],
    scatter [LalinLuaTrace.LTScatterPolicy],
    reduction [LalinLuaTrace.LTReductionPolicy],
  },

  product. LTLoopPlan {
    interned,
    domain_stride [number],
    group [number],
    reason [str],
    tail_strategy [str],
    loop_shape [str],
  },

  product. LTKernelPlan {
    interned,
    primitive [LalinLuaTrace.LTPrimitivePolicy],
    predicate [LalinLuaTrace.LTPredicatePolicy],
    scatter [LalinLuaTrace.LTScatterPolicy],
    reduction [LalinLuaTrace.LTReductionPolicy],
  },

  product. LTArtifactPlan {
    interned,
    artifact [LalinStencil.StencilArtifact],
    descriptor [LalinStencil.StencilDescriptor],
    shape [LalinStencil.StencilArtifactShape],
    schedule [LalinStencil.StencilSchedule],
    facts [optional [LalinStencil.StencilVectorizationFacts]],
    access_plans [LalinLuaTrace.LTAccessPlanSet],
    loop_plan [LalinLuaTrace.LTLoopPlan],
    kernel_plan [LalinLuaTrace.LTKernelPlan],
    source_name [str],
  },

  sum. LTOp {
    LTOpComment {
      variant_unique,
      text [str],
    },
    LTOpLocal {
      variant_unique,
      field. name [str],
      field. expr [optional [LalinLuaTrace.LTExpr]],
    },
    LTOpAssign {
      variant_unique,
      lhs [LalinLuaTrace.LTExpr],
      rhs [LalinLuaTrace.LTExpr],
    },
    LTOpIf {
      variant_unique,
      cond [LalinLuaTrace.LTExpr],
      then_ops [many [LalinLuaTrace.LTOp]],
      else_ops [many [LalinLuaTrace.LTOp]],
    },
    LTOpForRange {
      variant_unique,
      var [str],
      start [LalinLuaTrace.LTExpr],
      stop [LalinLuaTrace.LTExpr],
      step [LalinLuaTrace.LTExpr],
      body [many [LalinLuaTrace.LTOp]],
    },
    LTOpWhile {
      variant_unique,
      cond [LalinLuaTrace.LTExpr],
      body [many [LalinLuaTrace.LTOp]],
    },
    LTOpFfiCopy {
      variant_unique,
      dst [LalinLuaTrace.LTExpr],
      src [LalinLuaTrace.LTExpr],
      bytes [LalinLuaTrace.LTExpr],
    },
    LTOpFfiFill {
      variant_unique,
      dst [LalinLuaTrace.LTExpr],
      bytes [LalinLuaTrace.LTExpr],
      field. value [LalinLuaTrace.LTExpr],
    },
    LTOpReturn {
      variant_unique,
      values [many [LalinLuaTrace.LTExpr]],
    },
  },

  product. LTFunction {
    interned,
    field. id [LalinLuaTrace.LTFuncId],
    symbol [LalinStencil.StencilSymbolId],
    params [many [LalinLuaTrace.LTParam]],
    plan [LalinLuaTrace.LTPlanSummary],
    body [many [LalinLuaTrace.LTOp]],
  },

  product. LTModule {
    interned,
    field. id [LalinLuaTrace.LTModuleId],
    funcs [many [LalinLuaTrace.LTFunction]],
  },
}
