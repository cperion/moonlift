local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonFlow {
  product. FlowDomainId { interned, text [str], },
  sum. FlowDomain {
    FlowDomainLoop { variant_unique, loop [MoonGraph.GraphLoopId], },
    FlowDomainBlockRange {
      variant_unique,
      func [MoonCode.CodeFuncId],
      entry [MoonCode.CodeBlockId],
      exit [MoonCode.CodeBlockId],
    },
    FlowDomainFunction { variant_unique, func [MoonCode.CodeFuncId], },
  },
  sum. FlowTripCount {
    FlowTripCountExact {
      variant_unique,
      count [MoonCode.CodeValueId],
      proof [optional [MoonMem.MemProof]],
    },
    FlowTripCountNonNegative {
      variant_unique,
      count [MoonCode.CodeValueId],
      proof [optional [MoonMem.MemProof]],
    },
    FlowTripCountUnknown { variant_unique, reason [str], },
  },
  product. FlowEdgeArg {
    interned,
    src [MoonCode.CodeValueId],
    dst_param [MoonCode.CodeValueId],
  },
  product. FlowEdgeFact {
    interned,
    edge [MoonGraph.GraphEdge],
    args [many [MoonFlow.FlowEdgeArg]],
  },
  sum. FlowReject {
    FlowRejectIrreducible { variant_unique, func [MoonCode.CodeFuncId], reason [str], },
    FlowRejectNotCounted { variant_unique, loop [MoonGraph.GraphLoopId], reason [str], },
    FlowRejectUnsupportedTerminator {
      variant_unique,
      block [MoonGraph.GraphBlockId],
      term [MoonCode.CodeTermKind],
    },
    FlowRejectUnsupportedInduction {
      variant_unique,
      loop [MoonGraph.GraphLoopId],
      field. value [MoonCode.CodeValueId],
      reason [str],
    },
    FlowRejectUnknownValue {
      variant_unique,
      field. value [MoonCode.CodeValueId],
      reason [str],
    },
  },
  sum. FlowBound {
    FlowBoundUnknown,
    FlowBoundConst { variant_unique, raw [str], },
    FlowBoundValue { variant_unique, field. value [MoonCode.CodeValueId], },
    FlowBoundDerived { variant_unique, key [str], deps [many [MoonCode.CodeValueId]], },
  },
  sum. FlowValueRange {
    FlowRangeUnknown { variant_unique, field. value [MoonCode.CodeValueId], },
    FlowRangeExact {
      variant_unique,
      field. value [MoonCode.CodeValueId],
      bound [MoonFlow.FlowBound],
    },
    FlowRangeUnsigned {
      variant_unique,
      field. value [MoonCode.CodeValueId],
      min [MoonFlow.FlowBound],
      max [MoonFlow.FlowBound],
    },
    FlowRangeSigned {
      variant_unique,
      field. value [MoonCode.CodeValueId],
      min [MoonFlow.FlowBound],
      max [MoonFlow.FlowBound],
    },
    FlowRangeDerived {
      variant_unique,
      field. value [MoonCode.CodeValueId],
      min [MoonFlow.FlowBound],
      max [MoonFlow.FlowBound],
      reason [str],
    },
  },
  product. FlowCountedDomain {
    interned,
    start [MoonCode.CodeValueId],
    stop [MoonCode.CodeValueId],
    step [MoonCode.CodeValueId],
    stop_exclusive [bool],
  },
  sum. FlowLoopDirection { FlowLoopIncreasing, FlowLoopDecreasing, FlowLoopDirectionUnknown, },
  sum. FlowInductionKind {
    FlowPrimaryInduction,
    FlowDerivedInduction { variant_unique, base [MoonCode.CodeValueId], },
    FlowPointerInduction { variant_unique, base [MoonCode.CodeValueId], elem_size [number], },
  },
  product. FlowInduction {
    interned,
    field. value [MoonCode.CodeValueId],
    field. ty [MoonCode.CodeType],
    init [MoonCode.CodeValueId],
    step [MoonCode.CodeValueId],
    kind [MoonFlow.FlowInductionKind],
    range [MoonFlow.FlowValueRange],
  },
  product. FlowLoopExit {
    interned,
    from [MoonGraph.GraphBlockId],
    to [MoonGraph.GraphBlockId],
    condition [optional [MoonCode.CodeValueId]],
  },
  product. FlowLoopFacts {
    interned,
    loop [MoonGraph.GraphLoopId],
    domain [MoonFlow.FlowDomain],
    counted [optional [MoonFlow.FlowCountedDomain]],
    body_blocks [many [MoonGraph.GraphBlockId]],
    inductions [many [MoonFlow.FlowInduction]],
    exits [many [MoonFlow.FlowLoopExit]],
    rejects [many [MoonFlow.FlowReject]],
  },
  product. FlowInductionRangeFact {
    interned,
    loop [MoonGraph.GraphLoopId],
    field. value [MoonCode.CodeValueId],
    min [MoonFlow.FlowBound],
    max [MoonFlow.FlowBound],
    max_exclusive [bool],
    reason [str],
  },
  sum. FlowLoopSemanticFact {
    FlowLoopNormalizedCounted {
      variant_unique,
      loop [MoonGraph.GraphLoopId],
      domain [MoonFlow.FlowCountedDomain],
      direction [MoonFlow.FlowLoopDirection],
      trip_count [MoonFlow.FlowTripCount],
    },
    FlowLoopInductionRange { variant_unique, range [MoonFlow.FlowInductionRangeFact], },
    FlowLoopInductionNoWrap {
      variant_unique,
      loop [MoonGraph.GraphLoopId],
      field. value [MoonCode.CodeValueId],
      reason [str],
    },
  },
  product. FlowSemanticFactSet {
    interned,
    field. module [MoonCode.CodeModuleId],
    facts [many [MoonFlow.FlowLoopSemanticFact]],
  },
  product. FlowFactSet {
    interned,
    field. module [MoonCode.CodeModuleId],
    domains [many [MoonFlow.FlowDomain]],
    edges [many [MoonFlow.FlowEdgeFact]],
    loops [many [MoonFlow.FlowLoopFacts]],
    ranges [many [MoonFlow.FlowValueRange]],
    rejects [many [MoonFlow.FlowReject]],
  },
}
