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
    StencilPredEqConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredNeConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredLtConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredLeConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredGtConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredGeConst { variant_unique, field. value [MoonValue.ValueExpr], },
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
      index_ty [MoonCode.CodeType],
      start [optional [MoonValue.ValueExpr]],
      stop [optional [MoonValue.ValueExpr]],
      step [number],
      order [MoonStencil.StencilDomainOrder],
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
      field. value [optional [MoonValue.ValueExpr]],
    },
    StencilTopologyContiguous {
      variant_unique,
      stride [number],
    },
    StencilTopologyIndexed {
      variant_unique,
      index_ty [MoonCode.CodeType],
      stride [number],
    },
    StencilTopologyInPlace {
      variant_unique,
      stride [number],
    },
    StencilTopologyFieldProjection {
      variant_unique,
      parent [MoonStencil.StencilAccessTopology],
      record_ty [MoonCode.CodeType],
      field_name [str],
      field_offset [number],
    },
    StencilTopologySoAComponent {
      variant_unique,
      parent [MoonStencil.StencilAccessTopology],
      record_ty [MoonCode.CodeType],
      field_name [str],
      component_index [number],
    },
    StencilTopologySliceDescriptor {
      variant_unique,
      slice [MoonCode.CodeValueId],
      data [MoonCode.CodeValueId],
      len [MoonCode.CodeValueId],
    },
    StencilTopologyByteSpanDescriptor {
      variant_unique,
      span [MoonCode.CodeValueId],
      data [MoonCode.CodeValueId],
      len [MoonCode.CodeValueId],
    },
    StencilTopologyViewDescriptor {
      variant_unique,
      view [MoonCode.CodeValueId],
      data [MoonCode.CodeValueId],
      len [MoonCode.CodeValueId],
      stride [MoonCode.CodeValueId],
      stride_const [optional [number]],
    },
  },

  product. StencilAccess {
    interned,
    field. name [str],
    role [MoonStencil.StencilAccessRole],
    field. ty [MoonCode.CodeType],
    topology [MoonStencil.StencilAccessTopology],
  },

  sum. StencilElementOperator {
    StencilOpIdentity,
    StencilOpFill {
      variant_unique,
      field. value [MoonValue.ValueExpr],
    },
    StencilOpUnary {
      variant_unique,
      op [MoonStencil.StencilUnaryOp],
      result_ty [optional [MoonCode.CodeType]],
    },
    StencilOpBinary {
      variant_unique,
      op [MoonStencil.StencilBinaryOp],
      result_ty [optional [MoonCode.CodeType]],
    },
    StencilOpCast {
      variant_unique,
      op [MoonCore.MachineCastOp],
      from [MoonCode.CodeType],
      to [MoonCode.CodeType],
    },
    StencilOpPredicate {
      variant_unique,
      pred [MoonStencil.StencilPredicate],
      result_ty [MoonCode.CodeType],
    },
    StencilOpCompare {
      variant_unique,
      cmp [MoonCore.CmpOp],
      result_ty [MoonCode.CodeType],
    },
  },

  product. StencilReducer {
    interned,
    reduction [MoonValue.ReductionKind],
    result_ty [MoonCode.CodeType],
    init [MoonValue.ValueExpr],
    int_semantics [optional [MoonCode.CodeIntSemantics]],
    float_mode [optional [MoonCode.CodeFloatMode]],
  },

  sum. StencilSkeleton {
    StencilSkeletonApply,
    StencilSkeletonReduce,
    StencilSkeletonScan {
      variant_unique,
      mode [MoonStencil.StencilScanMode],
    },
    StencilSkeletonCopy {
      variant_unique,
      semantics [MoonStencil.StencilCopySemantics],
    },
    StencilSkeletonFind {
      variant_unique,
      not_found [MoonValue.ValueExpr],
    },
    StencilSkeletonPartition {
      variant_unique,
      semantics [MoonStencil.StencilPartitionSemantics],
    },
  },

  product. StencilMemorySemantics {
    interned,
    copy [optional [MoonStencil.StencilCopySemantics]],
    partition [optional [MoonStencil.StencilPartitionSemantics]],
    scatter [optional [MoonStencil.StencilScatterConflictSemantics]],
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
    compiler [MoonStencil.StencilCompiler],
    opt_level [MoonStencil.StencilOptLevel],
    machine [MoonStencil.StencilMachineTarget],
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
    field. alias [MoonStencil.StencilAliasFact],
    alignment [MoonStencil.StencilAlignmentFact],
    readonly [bool],
    unit_stride [bool],
  },

  product. StencilArithmeticVectorFact {
    interned,
    reduction_reassociable [bool],
    int_semantics [optional [MoonCode.CodeIntSemantics]],
    float_mode [optional [MoonCode.CodeFloatMode]],
  },

  product. StencilVectorizationFacts {
    interned,
    access_facts [many [MoonStencil.StencilAccessVectorFact]],
    trip_count [MoonStencil.StencilTripCountFact],
    arithmetic [MoonStencil.StencilArithmeticVectorFact],
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
      compiler [MoonStencil.StencilCompilerPolicy],
    },
    StencilScheduleAutoVector {
      variant_unique,
      compiler [MoonStencil.StencilCompilerPolicy],
      facts [MoonStencil.StencilVectorizationFacts],
    },
    StencilScheduleUnrolled {
      variant_unique,
      factor [number],
      compiler [MoonStencil.StencilCompilerPolicy],
      facts [MoonStencil.StencilVectorizationFacts],
    },
    StencilScheduleVector {
      variant_unique,
      feature [MoonStencil.StencilVectorFeatureRequirement],
      lane_policy [MoonStencil.StencilLanePolicy],
      alignment [MoonStencil.StencilVectorAlignmentPolicy],
      tail [MoonStencil.StencilVectorTailPolicy],
      reduction [MoonStencil.StencilVectorReductionStrategy],
      vector_compiler [MoonStencil.StencilVectorCompilerPolicy],
      lanes [number],
      unroll [number],
      interleave [number],
      compiler [MoonStencil.StencilCompilerPolicy],
      facts [MoonStencil.StencilVectorizationFacts],
    },
  },

  product. StencilDescriptor {
    interned,
    vocab [MoonStencil.StencilVocab],
    domain [MoonStencil.StencilDomain],
    accesses [many [MoonStencil.StencilAccess]],
    operator [optional [MoonStencil.StencilElementOperator]],
    reducer [optional [MoonStencil.StencilReducer]],
    skeleton [MoonStencil.StencilSkeleton],
    memory [MoonStencil.StencilMemorySemantics],
    result_ty [optional [MoonCode.CodeType]],
    params [many [MoonStencil.StencilParam]],
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

  product. StencilInstance {
    interned,
    field. id [MoonStencil.StencilInstanceId],
    descriptor [MoonStencil.StencilDescriptor],
    schedule [MoonStencil.StencilSchedule],
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

  product. StencilPlanEntry {
    interned,
    kernel [MoonKernel.KernelId],
    selection [MoonStencil.StencilSelection],
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
    selections [many [MoonStencil.StencilPlanEntry]],
  },
}
