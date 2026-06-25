local S = require("lalin.schema.dsl")
S.use()

return schema. LalinStencil {
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
    StencilSelect,
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
    StencilBinaryDiv,
    StencilBinaryMod,
    StencilBinaryAnd,
    StencilBinaryOr,
    StencilBinaryXor,
    StencilBinaryShl,
    StencilBinaryLShr,
    StencilBinaryAShr,
    StencilBinaryMin,
    StencilBinaryMax,
  },

  sum. StencilPredicate {
    StencilPredNonZero,
    StencilPredCompareConst {
      variant_unique,
      cmp [LalinCore.CmpOp],
      operand_ty [LalinCode.CodeType],
      field. value [LalinValue.ValueExpr],
    },
    StencilPredRange {
      variant_unique,
      operand_ty [LalinCode.CodeType],
      lower_cmp [LalinCore.CmpOp],
      lower [LalinValue.ValueExpr],
      upper_cmp [LalinCore.CmpOp],
      upper [LalinValue.ValueExpr],
    },
    StencilPredAnd {
      variant_unique,
      terms [many [LalinStencil.StencilPredicate]],
    },
    StencilPredOr {
      variant_unique,
      terms [many [LalinStencil.StencilPredicate]],
    },
    StencilPredNot {
      variant_unique,
      term [LalinStencil.StencilPredicate],
    },
    StencilPredIsNaN {
      variant_unique,
      operand_ty [LalinCode.CodeType],
    },
    StencilPredIsInf {
      variant_unique,
      operand_ty [LalinCode.CodeType],
    },
    StencilPredIsFinite {
      variant_unique,
      operand_ty [LalinCode.CodeType],
    },
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

  product. StencilDomainAxis {
    interned,
    index_ty [LalinCode.CodeType],
    start [optional [LalinValue.ValueExpr]],
    stop [optional [LalinValue.ValueExpr]],
    step [number],
    order [LalinStencil.StencilDomainOrder],
  },

  sum. StencilWindowBoundary {
    StencilWindowBoundaryReject,
    StencilWindowBoundaryClamp,
    StencilWindowBoundaryWrap,
    StencilWindowBoundaryZero,
  },

  product. StencilWindowAxis {
    interned,
    before [number],
    after [number],
    boundary [LalinStencil.StencilWindowBoundary],
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
    StencilDomainRangeND {
      variant_unique,
      axes [many [LalinStencil.StencilDomainAxis]],
    },
    StencilDomainWindowND {
      variant_unique,
      axes [many [LalinStencil.StencilDomainAxis]],
      windows [many [LalinStencil.StencilWindowAxis]],
    },
    StencilDomainTiledND {
      variant_unique,
      axes [many [LalinStencil.StencilDomainAxis]],
      tile_sizes [many [number]],
    },
  },

  sum. StencilAccessRole {
    StencilAccessRead,
    StencilAccessWrite,
    StencilAccessIndex,
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

  product. StencilAccessRef {
    interned,
    field. name [str],
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
      int_semantics [optional [LalinCode.CodeIntSemantics]],
      float_mode [optional [LalinCode.CodeFloatMode]],
    },
    StencilOpBinary {
      variant_unique,
      op [LalinStencil.StencilBinaryOp],
      result_ty [optional [LalinCode.CodeType]],
      int_semantics [optional [LalinCode.CodeIntSemantics]],
      float_mode [optional [LalinCode.CodeFloatMode]],
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
    StencilOpSelect {
      variant_unique,
      pred [LalinStencil.StencilPredicate],
      result_ty [LalinCode.CodeType],
    },
  },

  product. StencilReducer {
    interned,
    reduction [LalinValue.ReductionKind],
    result_ty [LalinCode.CodeType],
    field. identity [LalinValue.ValueExpr],
    int_semantics [optional [LalinCode.CodeIntSemantics]],
    float_mode [optional [LalinCode.CodeFloatMode]],
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
    StencilTripCountExact {
      variant_unique,
      count [number],
    },
    StencilTripCountMultipleOf {
      variant_unique,
      factor [number],
    },
  },

  sum. StencilProofOrigin {
    StencilProofCheckerDerived,
    StencilProofBoundaryContract,
    StencilProofAuthorAsserted,
  },

  sum. StencilProofObligationKind {
    StencilProofNoAlias {
      variant_unique,
      left [LalinStencil.StencilAccessRef],
      right [LalinStencil.StencilAccessRef],
    },
    StencilProofAlignment {
      variant_unique,
      access [LalinStencil.StencilAccessRef],
      alignment [LalinStencil.StencilAlignmentFact],
    },
    StencilProofTripCount {
      variant_unique,
      trip_count [LalinStencil.StencilTripCountFact],
    },
    StencilProofReductionReassociable,
    StencilProofUnitStride {
      variant_unique,
      access [LalinStencil.StencilAccessRef],
    },
  },

  product. StencilProofObligation {
    interned,
    kind [LalinStencil.StencilProofObligationKind],
    origin [LalinStencil.StencilProofOrigin],
    proof [optional [LalinKernel.KernelProof]],
  },

  product. StencilAccessVectorFact {
    interned,
    access [LalinStencil.StencilAccessRef],
    alignment [LalinStencil.StencilAlignmentFact],
    readonly [bool],
    unit_stride [bool],
  },

  product. StencilAccessAliasFact {
    interned,
    left [LalinStencil.StencilAccessRef],
    right [LalinStencil.StencilAccessRef],
    relation [LalinStencil.StencilAliasFact],
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
    alias_facts [many [LalinStencil.StencilAccessAliasFact]],
    trip_count [LalinStencil.StencilTripCountFact],
    arithmetic [LalinStencil.StencilArithmeticVectorFact],
    proof_obligations [many [LalinStencil.StencilProofObligation]],
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

  sum. StencilMaterializer {
    StencilMaterializerCopyPatchBC,
    StencilMaterializerCopyPatchMC,
    StencilMaterializerNamed {
      variant_unique,
      field. name [str],
    },
  },

  sum. StencilRealizedScheduleEvidence {
    StencilRealizedByConstruction {
      variant_unique,
      reason [str],
    },
    StencilRealizedCompilerRemark {
      variant_unique,
      remark [str],
    },
    StencilRealizedDisassembly {
      variant_unique,
      classification [str],
    },
  },

  sum. StencilRealizedSchedule {
    StencilRealizedScalar {
      variant_unique,
      materializer [LalinStencil.StencilMaterializer],
      evidence [many [LalinStencil.StencilRealizedScheduleEvidence]],
    },
    StencilRealizedUnrolled {
      variant_unique,
      factor [number],
      materializer [LalinStencil.StencilMaterializer],
      evidence [many [LalinStencil.StencilRealizedScheduleEvidence]],
    },
    StencilRealizedVector {
      variant_unique,
      feature [LalinStencil.StencilVectorFeatureRequirement],
      lanes [number],
      unroll [number],
      interleave [number],
      tail [LalinStencil.StencilVectorTailPolicy],
      materializer [LalinStencil.StencilMaterializer],
      evidence [many [LalinStencil.StencilRealizedScheduleEvidence]],
    },
  },

  sum. StencilScheduleReject {
    StencilScheduleRejectUnsupportedFeature {
      variant_unique,
      feature [LalinStencil.StencilVectorFeatureRequirement],
      compiler [LalinStencil.StencilCompilerPolicy],
      reason [str],
    },
    StencilScheduleRejectIllegalLaneCount {
      variant_unique,
      lanes [number],
      reason [str],
    },
    StencilScheduleRejectUnprovableTail {
      variant_unique,
      tail [LalinStencil.StencilVectorTailPolicy],
      reason [str],
    },
    StencilScheduleRejectUnprovableAlignment {
      variant_unique,
      access [optional [LalinStencil.StencilAccessRef]],
      alignment [LalinStencil.StencilVectorAlignmentPolicy],
      reason [str],
    },
    StencilScheduleRejectCompilerMatrix {
      variant_unique,
      compiler [LalinStencil.StencilCompilerPolicy],
      vector_compiler [LalinStencil.StencilVectorCompilerPolicy],
      reason [str],
    },
    StencilScheduleRejectRequestedRealizedMismatch {
      variant_unique,
      requested [LalinStencil.StencilSchedule],
      realized [optional [LalinStencil.StencilRealizedSchedule]],
      reason [str],
    },
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
      required_alignment [LalinStencil.StencilVectorAlignmentPolicy],
      tail [LalinStencil.StencilVectorTailPolicy],
      reduction [LalinStencil.StencilVectorReductionStrategy],
      vector_compiler [LalinStencil.StencilVectorCompilerPolicy],
      vector_unroll [number],
      interleave [number],
      compiler [LalinStencil.StencilCompilerPolicy],
      facts [LalinStencil.StencilVectorizationFacts],
    },
  },

  sum. StencilDescriptor {
    StencilDescriptorReduce {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      reducer [LalinStencil.StencilReducer],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorMap {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      operator [LalinStencil.StencilElementOperator],
    },
    StencilDescriptorZipMap {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      operator [LalinStencil.StencilElementOperator],
    },
    StencilDescriptorScan {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      reducer [LalinStencil.StencilReducer],
      mode [LalinStencil.StencilScanMode],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorCopy {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      semantics [LalinStencil.StencilCopySemantics],
    },
    StencilDescriptorFill {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      operator [LalinStencil.StencilElementOperator],
    },
    StencilDescriptorFind {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      pred [LalinStencil.StencilPredicate],
      not_found [LalinValue.ValueExpr],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorPartition {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      pred [LalinStencil.StencilPredicate],
      semantics [LalinStencil.StencilPartitionSemantics],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorCast {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      operator [LalinStencil.StencilElementOperator],
    },
    StencilDescriptorCompare {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      pred [LalinStencil.StencilPredicate],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorZipCompare {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      cmp [LalinCore.CmpOp],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorSelect {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      pred [LalinStencil.StencilPredicate],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorGather {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
    },
    StencilDescriptorScatter {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      conflicts [LalinStencil.StencilScatterConflictSemantics],
    },
    StencilDescriptorInPlaceMap {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      operator [LalinStencil.StencilElementOperator],
    },
    StencilDescriptorCount {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      pred [LalinStencil.StencilPredicate],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorMapReduce {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      operator [LalinStencil.StencilElementOperator],
      reducer [LalinStencil.StencilReducer],
      result_ty [LalinCode.CodeType],
    },
    StencilDescriptorZipReduce {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      accesses [many [LalinStencil.StencilAccess]],
      operator [LalinStencil.StencilElementOperator],
      reducer [LalinStencil.StencilReducer],
      result_ty [LalinCode.CodeType],
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
    StencilRejectUnsupportedDomain {
      variant_unique,
      domain [LalinStencil.StencilDomain],
      reason [str],
    },
    StencilRejectMissingProof {
      variant_unique,
      obligation [LalinStencil.StencilProofObligationKind],
    },
    StencilRejectProvider {
      variant_unique,
      provider [LalinStencil.StencilProvider],
      reason [str],
    },
    StencilRejectSchedule {
      variant_unique,
      reject [LalinStencil.StencilScheduleReject],
    },
  },

  sum. StencilScheduleCandidateStatus {
    StencilScheduleCandidateSelected,
    StencilScheduleCandidateViable,
    StencilScheduleCandidateRejected,
  },

  sum. StencilScheduleSelectionOrigin {
    StencilScheduleSelectionHeuristic,
    StencilScheduleSelectionCostModel,
    StencilScheduleSelectionAuthorAnnotated,
    StencilScheduleSelectionFallback,
  },

  product. StencilScheduleCandidate {
    interned,
    field. name [str],
    schedule [optional [LalinStencil.StencilSchedule]],
    cost [number],
    status [LalinStencil.StencilScheduleCandidateStatus],
    rejects [many [LalinStencil.StencilScheduleReject]],
    reason [str],
  },

  product. StencilScheduleSelectionProvenance {
    interned,
    origin [LalinStencil.StencilScheduleSelectionOrigin],
    winner [str],
    candidates [many [LalinStencil.StencilScheduleCandidate]],
    reason [str],
  },

  sum. StencilSelection {
    StencilSelected {
      variant_unique,
      instance [LalinStencil.StencilInstance],
      provenance [LalinStencil.StencilScheduleSelectionProvenance],
    },
    StencilNoSelection {
      variant_unique,
      vocab [LalinStencil.StencilVocab],
      rejects [many [LalinStencil.StencilReject]],
      provenance [LalinStencil.StencilScheduleSelectionProvenance],
    },
  },

  product. StencilPlanEntry {
    interned,
    kernel [LalinKernel.KernelId],
    selection [LalinStencil.StencilSelection],
  },

  product. StencilArtifactFingerprint {
    interned,
    text [str],
  },

  sum. StencilArtifactDiagnosticSeverity {
    StencilArtifactDiagnosticNote,
    StencilArtifactDiagnosticRemark,
    StencilArtifactDiagnosticWarning,
    StencilArtifactDiagnosticError,
  },

  product. StencilArtifactDiagnostic {
    interned,
    severity [LalinStencil.StencilArtifactDiagnosticSeverity],
    source [str],
    message [str],
  },

  product. StencilArtifact {
    interned,
    instance [LalinStencil.StencilInstance],
    provider [LalinStencil.StencilProvider],
    symbol [LalinStencil.StencilSymbolId],
    c_signature [str],
    fingerprint [LalinStencil.StencilArtifactFingerprint],
    realized [optional [LalinStencil.StencilRealizedSchedule]],
    diagnostics [many [LalinStencil.StencilArtifactDiagnostic]],
    schedule_rejects [many [LalinStencil.StencilScheduleReject]],
  },

  product. StencilModulePlan {
    interned,
    field. module [LalinCode.CodeModuleId],
    kernel [LalinKernel.KernelModulePlan],
    selections [many [LalinStencil.StencilPlanEntry]],
  },
}
