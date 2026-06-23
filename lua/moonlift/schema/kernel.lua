local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonKernel {
  product. KernelId { interned, text [str], },
  product. KernelValueId { interned, text [str], },
  product. KernelStreamId { interned, text [str], },
  sum. KernelSubject {
    KernelSubjectFunction { variant_unique, func [MoonCode.CodeFuncId], },
    KernelSubjectLoop { variant_unique, loop [MoonGraph.GraphLoopId], },
    KernelSubjectDomain { variant_unique, domain [MoonFlow.FlowDomain], },
    KernelSubjectFragment {
      variant_unique,
      func [MoonCode.CodeFuncId],
      entry [MoonCode.CodeBlockId],
      exit [MoonCode.CodeBlockId],
    },
  },
  sum. KernelReject {
    KernelRejectNoFacts { variant_unique, subject [MoonKernel.KernelSubject], reason [str], },
    KernelRejectUnsupportedSubject {
      variant_unique,
      subject [MoonKernel.KernelSubject],
      reason [str],
    },
    KernelRejectUnsupportedExpr {
      variant_unique,
      field. value [MoonCode.CodeValueId],
      reason [str],
    },
    KernelRejectUnsupportedMemory {
      variant_unique,
      access [MoonMem.MemAccessId],
      reason [str],
    },
    KernelRejectEffect { variant_unique, effect [MoonEffect.OpEffect], reason [str], },
    KernelRejectIncompleteFunction {
      variant_unique,
      func [MoonCode.CodeFuncId],
      reason [str],
    },
  },
  sum. KernelProof {
    KernelProofFlow { variant_unique, domain [MoonFlow.FlowDomain], reason [str], },
    KernelProofValue { variant_unique, proof [MoonValue.AlgebraProof], reason [str], },
    KernelProofMemory { variant_unique, proof [MoonMem.MemProof], reason [str], },
    KernelProofEffect { variant_unique, effect [MoonEffect.OpEffect], reason [str], },
    KernelProofFunctionEquivalence { variant_unique, reason [str], },
  },
  sum. KernelDomain {
    KernelDomainFlow {
      variant_unique,
      domain [MoonFlow.FlowDomain],
      trip_count [MoonFlow.FlowTripCount],
      counter [optional [MoonCode.CodeValueId]],
    },
  },
  product. KernelStream {
    interned,
    field. id [MoonKernel.KernelStreamId],
    object [MoonMem.MemObjectId],
    accesses [many [MoonMem.MemAccessId]],
    base [MoonMem.MemBase],
    elem_ty [MoonCode.CodeType],
    pattern [MoonMem.MemAccessPattern],
    backend_info [many [MoonMem.MemBackendAccessInfo]],
  },
  sum. KernelExpr {
    KernelExprValue { variant_unique, field. value [MoonCode.CodeValueId], },
    KernelExprAlgebra { variant_unique, field. expr [MoonValue.ValueExpr], },
    KernelExprLoad {
      variant_unique,
      stream [MoonKernel.KernelStream],
      index [MoonValue.ValueExpr],
    },
    KernelExprKernelValue { variant_unique, field. value [MoonKernel.KernelValueId], },
  },
  product. KernelBinding {
    interned,
    field. id [MoonKernel.KernelValueId],
    field. ty [MoonCode.CodeType],
    field. expr [MoonKernel.KernelExpr],
  },
  sum. KernelEffect {
    KernelEffectStore {
      variant_unique,
      dst [MoonKernel.KernelStream],
      index [MoonValue.ValueExpr],
      field. value [MoonKernel.KernelExpr],
    },
    KernelEffectFold { variant_unique, reduction [MoonValue.ReductionFact], },
    KernelEffectCall { variant_unique, call [MoonEffect.CallSummary], },
  },
  sum. KernelResult {
    KernelResultVoid,
    KernelResultValue { variant_unique, field. expr [MoonKernel.KernelExpr], },
    KernelResultReduction { variant_unique, reduction [MoonValue.ReductionFact], },
    KernelResultClosedForm { variant_unique, closed_form [MoonValue.ClosedFormFact], },
    KernelResultOriginalControl { variant_unique, reason [str], },
  },
  sum. KernelEquivalence {
    KernelEquivalenceProof { variant_unique, proofs [many [MoonKernel.KernelProof]], },
    KernelEquivalenceRejected { variant_unique, rejects [many [MoonKernel.KernelReject]], },
  },
  product. KernelBody {
    interned,
    domain [MoonKernel.KernelDomain],
    streams [many [MoonKernel.KernelStream]],
    bindings [many [MoonKernel.KernelBinding]],
    effects [many [MoonKernel.KernelEffect]],
    result [MoonKernel.KernelResult],
    equivalence [MoonKernel.KernelEquivalence],
  },
  sum. KernelPlan {
    KernelNoPlan {
      variant_unique,
      subject [MoonKernel.KernelSubject],
      rejects [many [MoonKernel.KernelReject]],
    },
    KernelPlanned {
      variant_unique,
      field. id [MoonKernel.KernelId],
      subject [MoonKernel.KernelSubject],
      body [MoonKernel.KernelBody],
    },
  },
  product. KernelModulePlan {
    interned,
    field. module [MoonCode.CodeModuleId],
    flow [MoonFlow.FlowFactSet],
    field. value [MoonValue.ValueFactSet],
    mem [MoonMem.MemSemanticFactSet],
    effect [MoonEffect.EffectFactSet],
    plans [many [MoonKernel.KernelPlan]],
  },
}
