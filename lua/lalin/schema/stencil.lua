local S = require("lalin.schema.dsl")
S.use()

return schema. LalinStencil {
  product. StencilId { interned, text [str], },
  product. StencilInstanceId { interned, text [str], },
  product. StencilSymbolId { interned, text [str], },
  product. StencilProviderId { interned, text [str], },

  sum. StencilProvider {
    StencilProviderC,
    StencilProviderLuaTrace,
    StencilProviderNamed {
      variant_unique,
      field. id [LalinStencil.StencilProviderId],
      field. name [str],
    },
  },

  sum. StencilVocab {
    StencilReduce,
    StencilMap,
    StencilZipMap,
    StencilScan,
    StencilCopy,
    StencilFill,
    StencilFind,
    StencilPartition,
    StencilCast,
    StencilCompare,
    StencilZipCompare,
    StencilGather,
    StencilScatter,
    StencilInPlaceMap,
    StencilCount,
    StencilMapReduce,
    StencilZipReduce,
  },

  sum. StencilUnaryOp {
    StencilUnaryIdentity,
    StencilUnaryNeg,
    StencilUnaryBitNot,
    StencilUnaryBoolNot,
  },

  sum. StencilBinaryOp {
    StencilBinaryAdd,
    StencilBinarySub,
    StencilBinaryMul,
    StencilBinaryAnd,
    StencilBinaryOr,
    StencilBinaryXor,
    StencilBinaryMin,
    StencilBinaryMax,
  },

  sum. StencilPredicate {
    StencilPredNonZero,
    StencilPredEqConst { variant_unique, field. value [LalinValue.ValueExpr], },
    StencilPredNeConst { variant_unique, field. value [LalinValue.ValueExpr], },
    StencilPredLtConst { variant_unique, field. value [LalinValue.ValueExpr], },
    StencilPredLeConst { variant_unique, field. value [LalinValue.ValueExpr], },
    StencilPredGtConst { variant_unique, field. value [LalinValue.ValueExpr], },
    StencilPredGeConst { variant_unique, field. value [LalinValue.ValueExpr], },
  },

  sum. StencilScanMode {
    StencilScanInclusive,
    StencilScanExclusive,
  },

  sum. StencilCopySemantics {
    StencilCopyNoOverlap,
    StencilCopyMayOverlapForward,
    StencilCopyMayOverlapBackward,
    StencilCopyMemMove,
  },

  sum. StencilPartitionSemantics {
    StencilPartitionStable,
    StencilPartitionUnstable,
  },

  sum. StencilScatterConflictSemantics {
    StencilScatterUniqueIndices,
    StencilScatterLastWriteWins,
    StencilScatterConflictUndefined,
  },

  sum. StencilDomainOrder {
    StencilDomainForward,
    StencilDomainBackward,
  },

  sum. StencilDomain {
    StencilDomainRange1D {
      variant_unique,
      index_ty [LalinCode.CodeType],
      start [optional [LalinValue.ValueExpr]],
      stop [optional [LalinValue.ValueExpr]],
      step [number],
      order [LalinStencil.StencilDomainOrder],
    },
  },

  sum. StencilAccessRole {
    StencilAccessRead,
    StencilAccessWrite,
    StencilAccessReadWrite,
    StencilAccessReduce,
    StencilAccessControlResult,
  },

  sum. StencilAccessTopology {
    StencilTopologyScalar {
      variant_unique,
      field. value [optional [LalinValue.ValueExpr]],
    },
    StencilTopologyContiguous {
      variant_unique,
      stride [number],
    },
    StencilTopologyIndexed {
      variant_unique,
      index_ty [LalinCode.CodeType],
      stride [number],
    },
    StencilTopologyInPlace {
      variant_unique,
      stride [number],
    },
    StencilTopologyFieldProjection {
      variant_unique,
      parent [LalinStencil.StencilAccessTopology],
      record_ty [LalinCode.CodeType],
      field_name [str],
      field_offset [number],
    },
    StencilTopologySoAComponent {
      variant_unique,
      parent [LalinStencil.StencilAccessTopology],
      record_ty [LalinCode.CodeType],
      field_name [str],
      component_index [number],
    },
    StencilTopologySliceDescriptor {
      variant_unique,
      slice [LalinCode.CodeValueId],
      data [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
    },
    StencilTopologyByteSpanDescriptor {
      variant_unique,
      span [LalinCode.CodeValueId],
      data [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
    },
    StencilTopologyViewDescriptor {
      variant_unique,
      view [LalinCode.CodeValueId],
      data [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
      stride [LalinCode.CodeValueId],
      stride_const [optional [number]],
    },
  },

  product. StencilAccess {
    interned,
    field. name [str],
    role [LalinStencil.StencilAccessRole],
    field. ty [LalinCode.CodeType],
    topology [LalinStencil.StencilAccessTopology],
  },

  sum. StencilElementOperator {
    StencilOpIdentity,
    StencilOpFill {
      variant_unique,
      field. value [LalinValue.ValueExpr],
    },
    StencilOpUnary {
      variant_unique,
      op [LalinStencil.StencilUnaryOp],
      result_ty [optional [LalinCode.CodeType]],
    },
    StencilOpBinary {
      variant_unique,
      op [LalinStencil.StencilBinaryOp],
      result_ty [optional [LalinCode.CodeType]],
    },
    StencilOpCast {
      variant_unique,
      op [LalinCore.MachineCastOp],
      from [LalinCode.CodeType],
      to [LalinCode.CodeType],
    },
    StencilOpPredicate {
      variant_unique,
      pred [LalinStencil.StencilPredicate],
      result_ty [LalinCode.CodeType],
    },
    StencilOpCompare {
      variant_unique,
      cmp [LalinCore.CmpOp],
      result_ty [LalinCode.CodeType],
    },
  },

  product. StencilReducer {
    interned,
    reduction [LalinValue.ReductionKind],
    result_ty [LalinCode.CodeType],
    init [LalinValue.ValueExpr],
    int_semantics [optional [LalinCode.CodeIntSemantics]],
    float_mode [optional [LalinCode.CodeFloatMode]],
  },

  sum. StencilSkeleton {
    StencilSkeletonApply,
    StencilSkeletonReduce,
    StencilSkeletonScan {
      variant_unique,
      mode [LalinStencil.StencilScanMode],
    },
    StencilSkeletonCopy {
      variant_unique,
      semantics [LalinStencil.StencilCopySemantics],
    },
    StencilSkeletonFind {
      variant_unique,
      not_found [LalinValue.ValueExpr],
    },
    StencilSkeletonPartition {
      variant_unique,
      semantics [LalinStencil.StencilPartitionSemantics],
    },
  },

  product. StencilMemorySemantics {
    interned,
    copy [optional [LalinStencil.StencilCopySemantics]],
    partition [optional [LalinStencil.StencilPartitionSemantics]],
    scatter [optional [LalinStencil.StencilScatterConflictSemantics]],
  },

  sum. StencilCompiler {
    StencilCompilerGcc,
    StencilCompilerClang,
    StencilCompilerSystemC,
  },

  sum. StencilOptLevel {
    StencilOptO0,
    StencilOptO1,
    StencilOptO2,
    StencilOptO3,
    StencilOptOs,
    StencilOptOz,
  },

  sum. StencilMachineTarget {
    StencilMachineNative,
    StencilMachineBaseline,
    StencilMachineNamed {
      variant_unique,
      field. name [str],
    },
  },

  product. StencilCompilerPolicy {
    interned,
    compiler [LalinStencil.StencilCompiler],
    opt_level [LalinStencil.StencilOptLevel],
    machine [LalinStencil.StencilMachineTarget],
    flags [many [str]],
  },

  sum. StencilAliasFact {
    StencilAliasUnknown,
    StencilAliasNoAlias,
    StencilAliasMayAlias,
  },

  sum. StencilAlignmentFact {
    StencilAlignmentUnknown,
    StencilAlignmentKnown {
      variant_unique,
      bytes [number],
    },
  },

  sum. StencilTripCountFact {
    StencilTripCountUnknown,
    StencilTripCountDynamic,
    StencilTripCountMultipleOf {
      variant_unique,
      factor [number],
    },
  },

  product. StencilAccessVectorFact {
    interned,
    access_name [str],
    field. alias [LalinStencil.StencilAliasFact],
    alignment [LalinStencil.StencilAlignmentFact],
    readonly [bool],
    unit_stride [bool],
  },

  product. StencilArithmeticVectorFact {
    interned,
    reduction_reassociable [bool],
    int_semantics [optional [LalinCode.CodeIntSemantics]],
    float_mode [optional [LalinCode.CodeFloatMode]],
  },

  product. StencilVectorizationFacts {
    interned,
    access_facts [many [LalinStencil.StencilAccessVectorFact]],
    trip_count [LalinStencil.StencilTripCountFact],
    arithmetic [LalinStencil.StencilArithmeticVectorFact],
  },

  sum. StencilVectorFeatureRequirement {
    StencilVectorFeatureNative,
    StencilVectorFeatureSSE2,
    StencilVectorFeatureAVX2,
    StencilVectorFeatureAVX512F,
    StencilVectorFeatureNamed {
      variant_unique,
      field. name [str],
    },
  },

  sum. StencilLanePolicy {
    StencilLaneFromTarget,
    StencilLaneNative,
    StencilLaneFixed {
      variant_unique,
      lanes [number],
    },
  },

  sum. StencilVectorAlignmentPolicy {
    StencilVectorAlignmentUnknown,
    StencilVectorUnaligned,
    StencilVectorAligned {
      variant_unique,
      bytes [number],
    },
  },

  sum. StencilVectorTailPolicy {
    StencilVectorScalarTail,
    StencilVectorMaskTail,
    StencilVectorOverreadProvenSafe,
  },

  sum. StencilVectorReductionStrategy {
    StencilVectorReductionTree,
    StencilVectorReductionHorizontal,
    StencilVectorReductionScalarFinish,
  },

  sum. StencilVectorCompilerPolicy {
    StencilVectorCompilerGccAutovec,
    StencilVectorCompilerHandwritten,
    StencilVectorCompilerCopyPatchStencil,
  },

  sum. StencilSchedule {
    StencilScheduleScalar {
      variant_unique,
      compiler [LalinStencil.StencilCompilerPolicy],
    },
    StencilScheduleAutoVector {
      variant_unique,
      compiler [LalinStencil.StencilCompilerPolicy],
      facts [LalinStencil.StencilVectorizationFacts],
    },
    StencilScheduleUnrolled {
      variant_unique,
      factor [number],
      compiler [LalinStencil.StencilCompilerPolicy],
      facts [LalinStencil.StencilVectorizationFacts],
    },
    StencilScheduleVector {
      variant_unique,
      feature [LalinStencil.StencilVectorFeatureRequirement],
      lane_policy [LalinStencil.StencilLanePolicy],
      alignment [LalinStencil.StencilVectorAlignmentPolicy],
      tail [LalinStencil.StencilVectorTailPolicy],
      reduction [LalinStencil.StencilVectorReductionStrategy],
      vector_compiler [LalinStencil.StencilVectorCompilerPolicy],
      lanes [number],
      unroll [number],
      interleave [number],
      compiler [LalinStencil.StencilCompilerPolicy],
      facts [LalinStencil.StencilVectorizationFacts],
    },
  },

  product. StencilDescriptor {
    interned,
    vocab [LalinStencil.StencilVocab],
    domain [LalinStencil.StencilDomain],
    accesses [many [LalinStencil.StencilAccess]],
    operator [optional [LalinStencil.StencilElementOperator]],
    reducer [optional [LalinStencil.StencilReducer]],
    skeleton [LalinStencil.StencilSkeleton],
    memory [LalinStencil.StencilMemorySemantics],
    result_ty [optional [LalinCode.CodeType]],
    params [many [LalinStencil.StencilParam]],
  },

  sum. StencilParam {
    StencilParamType {
      variant_unique,
      field. name [str],
      field. ty [LalinCode.CodeType],
    },
    StencilParamReduction {
      variant_unique,
      field. name [str],
      reduction [LalinValue.ReductionKind],
    },
    StencilParamIntSemantics {
      variant_unique,
      field. name [str],
      semantics [LalinCode.CodeIntSemantics],
    },
    StencilParamFloatMode {
      variant_unique,
      field. name [str],
      mode [LalinCode.CodeFloatMode],
    },
    StencilParamValueExpr {
      variant_unique,
      field. name [str],
      field. expr [LalinValue.ValueExpr],
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
    params [many [LalinCode.CodeType]],
    result [optional [LalinCode.CodeType]],
  },

  product. StencilInstance {
    interned,
    field. id [LalinStencil.StencilInstanceId],
    descriptor [LalinStencil.StencilDescriptor],
    schedule [LalinStencil.StencilSchedule],
    abi [LalinStencil.StencilAbi],
    proofs [many [LalinKernel.KernelProof]],
  },

  sum. StencilReject {
    StencilRejectUnsupportedVocab {
      variant_unique,
      vocab [LalinStencil.StencilVocab],
      reason [str],
    },
    StencilRejectUnsupportedType {
      variant_unique,
      field. ty [LalinCode.CodeType],
      reason [str],
    },
    StencilRejectUnsupportedReduction {
      variant_unique,
      reduction [LalinValue.ReductionKind],
      reason [str],
    },
    StencilRejectMissingProof {
      variant_unique,
      reason [str],
    },
    StencilRejectProvider {
      variant_unique,
      provider [LalinStencil.StencilProvider],
      reason [str],
    },
  },

  sum. StencilSelection {
    StencilSelected {
      variant_unique,
      instance [LalinStencil.StencilInstance],
    },
    StencilNoSelection {
      variant_unique,
      vocab [LalinStencil.StencilVocab],
      rejects [many [LalinStencil.StencilReject]],
    },
  },

  product. StencilPlanEntry {
    interned,
    kernel [LalinKernel.KernelId],
    selection [LalinStencil.StencilSelection],
  },

  product. StencilArtifact {
    interned,
    instance [LalinStencil.StencilInstance],
    provider [LalinStencil.StencilProvider],
    symbol [LalinStencil.StencilSymbolId],
    c_signature [str],
  },

  product. StencilModulePlan {
    interned,
    field. module [LalinCode.CodeModuleId],
    kernel [LalinKernel.KernelModulePlan],
    selections [many [LalinStencil.StencilPlanEntry]],
  },
}
