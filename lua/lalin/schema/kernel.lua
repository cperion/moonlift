local S = require("lalin.schema.dsl")
S.use()

return schema. LalinKernel {
  product. KernelId { interned, text [str], },
  product. KernelValueId { interned, text [str], },
  product. KernelLaneId { interned, text [str], },
  sum. KernelSubject {
    KernelSubjectFunction { variant_unique, func [LalinCode.CodeFuncId], },
    KernelSubjectLoop { variant_unique, loop [LalinGraph.GraphLoopId], },
    KernelSubjectDomain { variant_unique, domain [LalinFlow.FlowDomain], },
    KernelSubjectFragment {
      variant_unique,
      func [LalinCode.CodeFuncId],
      entry [LalinCode.CodeBlockId],
      exit [LalinCode.CodeBlockId],
    },
  },
  sum. KernelReject {
    KernelRejectNoFacts { variant_unique, subject [LalinKernel.KernelSubject], reason [str], },
    KernelRejectUnsupportedSubject {
      variant_unique,
      subject [LalinKernel.KernelSubject],
      reason [str],
    },
    KernelRejectUnsupportedExpr {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      reason [str],
    },
    KernelRejectUnsupportedMemory {
      variant_unique,
      access [LalinMem.MemAccessId],
      reason [str],
    },
    KernelRejectEffect { variant_unique, effect [LalinEffect.OpEffect], reason [str], },
    KernelRejectIncompleteFunction {
      variant_unique,
      func [LalinCode.CodeFuncId],
      reason [str],
    },
  },
  sum. KernelProof {
    KernelProofFlow { variant_unique, domain [LalinFlow.FlowDomain], reason [str], },
    KernelProofValue { variant_unique, proof [LalinValue.AlgebraProof], reason [str], },
    KernelProofMemory { variant_unique, proof [LalinMem.MemProof], reason [str], },
    KernelProofEffect { variant_unique, effect [LalinEffect.OpEffect], reason [str], },
    KernelProofFunctionEquivalence { variant_unique, reason [str], },
  },
  sum. KernelDomain {
    KernelDomainFlow {
      variant_unique,
      domain [LalinFlow.FlowDomain],
      trip_count [LalinFlow.FlowTripCount],
      counter [optional [LalinCode.CodeValueId]],
    },
  },
  product. KernelLane {
    interned,
    field. id [LalinKernel.KernelLaneId],
    object [LalinMem.MemObjectId],
    accesses [many [LalinMem.MemAccessId]],
    base [LalinMem.MemBase],
    elem_ty [LalinCode.CodeType],
    pattern [LalinMem.MemAccessPattern],
    backend_info [many [LalinMem.MemBackendAccessInfo]],
  },
  sum. KernelExpr {
    KernelExprValue { variant_unique, field. value [LalinCode.CodeValueId], },
    KernelExprAlgebra { variant_unique, field. expr [LalinValue.ValueExpr], },
    KernelExprLaneLoad {
      variant_unique,
      field. lane [LalinKernel.KernelLane],
      index [LalinValue.ValueExpr],
    },
    KernelExprKernelValue { variant_unique, field. value [LalinKernel.KernelValueId], },
  },
  product. KernelBinding {
    interned,
    field. id [LalinKernel.KernelValueId],
    field. ty [LalinCode.CodeType],
    field. expr [LalinKernel.KernelExpr],
  },
  sum. KernelEffect {
    KernelEffectStore {
      variant_unique,
      dst [LalinKernel.KernelLane],
      index [LalinValue.ValueExpr],
      field. value [LalinKernel.KernelExpr],
    },
    KernelEffectScan {
      variant_unique,
      dst [LalinKernel.KernelLane],
      index [LalinValue.ValueExpr],
      reduction [LalinValue.ReductionFact],
      mode [LalinStencil.StencilScanMode],
    },
    KernelEffectPartition {
      variant_unique,
      dst [LalinKernel.KernelLane],
      src [LalinKernel.KernelExpr],
      pred [LalinStencil.StencilPredicate],
      semantics [LalinStencil.StencilPartitionSemantics],
    },
    KernelEffectCopy {
      variant_unique,
      dst [LalinKernel.KernelLane],
      src [LalinKernel.KernelExpr],
      semantics [LalinStencil.StencilCopySemantics],
    },
    KernelEffectFold { variant_unique, reduction [LalinValue.ReductionFact], },
    KernelEffectCall { variant_unique, call [LalinEffect.CallSummary], },
  },
  sum. KernelResult {
    KernelResultVoid,
    KernelResultValue { variant_unique, field. expr [LalinKernel.KernelExpr], },
    KernelResultFind {
      variant_unique,
      src [LalinKernel.KernelExpr],
      pred [LalinStencil.StencilPredicate],
      not_found [LalinValue.ValueExpr],
    },
    KernelResultReduction { variant_unique, reduction [LalinValue.ReductionFact], },
    KernelResultClosedForm { variant_unique, closed_form [LalinValue.ClosedFormFact], },
    KernelResultOriginalControl { variant_unique, reason [str], },
  },
  sum. KernelEquivalence {
    KernelEquivalenceProof { variant_unique, proofs [many [LalinKernel.KernelProof]], },
    KernelEquivalenceRejected { variant_unique, rejects [many [LalinKernel.KernelReject]], },
  },
  product. KernelBody {
    interned,
    domain [LalinKernel.KernelDomain],
    lanes [many [LalinKernel.KernelLane]],
    bindings [many [LalinKernel.KernelBinding]],
    effects [many [LalinKernel.KernelEffect]],
    result [LalinKernel.KernelResult],
    equivalence [LalinKernel.KernelEquivalence],
  },
  sum. KernelPlan {
    KernelNoPlan {
      variant_unique,
      subject [LalinKernel.KernelSubject],
      rejects [many [LalinKernel.KernelReject]],
    },
    KernelPlanned {
      variant_unique,
      field. id [LalinKernel.KernelId],
      subject [LalinKernel.KernelSubject],
      body [LalinKernel.KernelBody],
    },
  },
  product. KernelModulePlan {
    interned,
    field. module [LalinCode.CodeModuleId],
    flow [LalinFlow.FlowFactSet],
    field. value [LalinValue.ValueFactSet],
    mem [LalinMem.MemSemanticFactSet],
    effect [LalinEffect.EffectFactSet],
    plans [many [LalinKernel.KernelPlan]],
  },
}
