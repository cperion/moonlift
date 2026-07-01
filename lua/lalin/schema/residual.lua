local S = require("lalin.schema.dsl")
S.use()

return schema. LalinResidual {
  product. ResidualReason { interned, code [str], message [str], },

  sum. ResidualLoweringTarget {
    ResidualTargetNativeTcc,
    ResidualTargetAotC,
    ResidualTargetLuaTraceDebug,
  },

  sum. ResidualStorageRequirement {
    ResidualStorageAllowExactOrPatchTemplate,
    ResidualStorageRequireExact,
    ResidualStorageRequirePatchTemplate,
    ResidualStorageForbidStencilStorage,
  },

  product. ResidualModuleRequest {
    interned,
    field. module [LalinCode.CodeModule],
    target [LalinResidual.ResidualLoweringTarget],
    storage [LalinResidual.ResidualStorageRequirement],
  },

  product. ResidualLuaJITModuleRequest {
    interned,
    field. module [LalinLuaJIT.LJModule],
    target [LalinResidual.ResidualLoweringTarget],
    storage [LalinResidual.ResidualStorageRequirement],
  },

  sum. ResidualRelocPatch {
    ResidualRelocPatchRel32 {
      variant_unique,
      offset [number],
      reloc_type [str],
      symbol [str],
      addend [number],
    },
    ResidualRelocPatchUnsupported {
      variant_unique,
      offset [number],
      reloc_type [str],
      symbol [optional [str]],
      addend [number],
      reason [str],
    },
  },

  sum. StencilPatchTemplateSpine {
    StencilSpineStoreNRange1D,
    StencilSpineReduceNRange1D,
    StencilSpineScanRange1D,
    StencilSpineFindRange1D,
    StencilSpinePartitionRange1D,
    StencilSpineScatterReduceRange1D,
    StencilSpineRangeND { variant_unique, rank [number], },
    StencilSpineWindowND { variant_unique, rank [number], },
    StencilSpineTiledND { variant_unique, rank [number], },
    StencilSpinePointExprApplyChain { variant_unique, depth [number], arity [number], },
    StencilSpineFieldProjectionChain { variant_unique, depth [number], },
    StencilSpineSoAComponentChain { variant_unique, depth [number], },
    StencilSpineLayoutAffine { variant_unique, rank [number], },
  },

  sum. StencilPatchTemplateAxis {
    StencilTemplateSink { variant_unique, sink [LalinStencil.StencilSink], },
    StencilTemplateProducer { variant_unique, producer [LalinStencil.StencilProducer], },
    StencilTemplateAccessLayout { variant_unique, layout [LalinStencil.StencilAccessLayout], },
    StencilTemplateAccessLayoutShape { variant_unique, shape [LalinResidual.StencilAccessLayoutShape], },
    StencilTemplatePointExpr { variant_unique, field. expr [LalinStencil.StencilPointExpr], },
    StencilTemplatePointExprShape { variant_unique, shape [LalinResidual.StencilPointExprShape], },
    StencilTemplateScalarType { variant_unique, field. ty [LalinCode.CodeType], },
    StencilTemplateSchedule { variant_unique, schedule [LalinStencil.StencilSchedule], },
    StencilTemplateProof { variant_unique, proof [LalinKernel.KernelProof], },
    StencilTemplateTarget { variant_unique, target [LalinLuaJIT.LJMCTarget], },
    StencilTemplateAbi { variant_unique, abi [LalinStencil.StencilAbi], },
  },

  product. StencilPatchTemplateFamily {
    interned,
    spine [LalinResidual.StencilPatchTemplateSpine],
    fixed_axes [many [LalinResidual.StencilPatchTemplateAxis]],
  },

  sum. StencilAccessLayoutShape {
    StencilLayoutShapeScalar,
    StencilLayoutShapeContiguous,
    StencilLayoutShapeIndexed {
      variant_unique,
      parent [LalinResidual.StencilAccessLayoutShape],
      index_ty [LalinCode.CodeType],
    },
    StencilLayoutShapeAffine1D {
      variant_unique,
      parent [LalinResidual.StencilAccessLayoutShape],
      scale [number],
    },
    StencilLayoutShapeAffineND {
      variant_unique,
      parent [LalinResidual.StencilAccessLayoutShape],
      rank [number],
    },
    StencilLayoutShapeFieldProjection {
      variant_unique,
      parent [LalinResidual.StencilAccessLayoutShape],
      record_ty [LalinCode.CodeType],
      field_name [str],
    },
    StencilLayoutShapeSoAComponent {
      variant_unique,
      parent [LalinResidual.StencilAccessLayoutShape],
      record_ty [LalinCode.CodeType],
      field_name [str],
    },
    StencilLayoutShapeSliceDescriptor,
    StencilLayoutShapeByteSpanDescriptor,
    StencilLayoutShapeViewDescriptor,
  },

  sum. StencilPredicateShape {
    StencilPredShapeNonZero,
    StencilPredShapeCompareConst {
      variant_unique,
      cmp [LalinCore.CmpOp],
      operand_ty [LalinCode.CodeType],
    },
    StencilPredShapeRange {
      variant_unique,
      operand_ty [LalinCode.CodeType],
      lower_cmp [LalinCore.CmpOp],
      upper_cmp [LalinCore.CmpOp],
    },
    StencilPredShapeAnd { variant_unique, terms [many [LalinResidual.StencilPredicateShape]], },
    StencilPredShapeOr { variant_unique, terms [many [LalinResidual.StencilPredicateShape]], },
    StencilPredShapeNot { variant_unique, term [LalinResidual.StencilPredicateShape], },
    StencilPredShapeIsNaN { variant_unique, operand_ty [LalinCode.CodeType], },
    StencilPredShapeIsInf { variant_unique, operand_ty [LalinCode.CodeType], },
    StencilPredShapeIsFinite { variant_unique, operand_ty [LalinCode.CodeType], },
  },

  sum. StencilPointExprShape {
    StencilPointShapeInput,
    StencilPointShapeWindowInput { variant_unique, offset_count [number], },
    StencilPointShapeConst { variant_unique, field. ty [LalinCode.CodeType], },
    StencilPointShapeUnary {
      variant_unique,
      op [LalinStencil.StencilUnaryOp],
      field. arg [LalinResidual.StencilPointExprShape],
      result_ty [optional [LalinCode.CodeType]],
    },
    StencilPointShapeBinary {
      variant_unique,
      op [LalinStencil.StencilBinaryOp],
      left [LalinResidual.StencilPointExprShape],
      right [LalinResidual.StencilPointExprShape],
      result_ty [optional [LalinCode.CodeType]],
    },
    StencilPointShapeCast {
      variant_unique,
      op [LalinCore.MachineCastOp],
      field. arg [LalinResidual.StencilPointExprShape],
      from [LalinCode.CodeType],
      to [LalinCode.CodeType],
    },
    StencilPointShapePredicate {
      variant_unique,
      pred [LalinResidual.StencilPredicateShape],
      field. arg [LalinResidual.StencilPointExprShape],
      result_ty [LalinCode.CodeType],
    },
    StencilPointShapeCompare {
      variant_unique,
      cmp [LalinCore.CmpOp],
      left [LalinResidual.StencilPointExprShape],
      right [LalinResidual.StencilPointExprShape],
      result_ty [LalinCode.CodeType],
    },
    StencilPointShapeSelect {
      variant_unique,
      pred [LalinResidual.StencilPredicateShape],
      cond [LalinResidual.StencilPointExprShape],
      then_expr [LalinResidual.StencilPointExprShape],
      else_expr [LalinResidual.StencilPointExprShape],
      result_ty [LalinCode.CodeType],
    },
  },

  sum. StencilPatchCoordinate {
    StencilPatchCoordScalarConst {
      variant_unique,
      field. value [LalinValue.ValueExpr],
      field. ty [LalinCode.CodeType],
    },
    StencilPatchCoordAffineOffset { variant_unique, offset [LalinValue.ValueExpr], },
    StencilPatchCoordAffineTerm {
      variant_unique,
      axis_index [number],
      coeff [LalinValue.ValueExpr],
    },
    StencilPatchCoordStride { variant_unique, stride [number], },
    StencilPatchCoordFieldOffset {
      variant_unique,
      field_name [str],
      offset [number],
    },
    StencilPatchCoordComponentIndex {
      variant_unique,
      field_name [str],
      component_index [number],
    },
    StencilPatchCoordWindowOffset {
      variant_unique,
      axis_index [number],
      offset [number],
    },
    StencilPatchCoordSymbolAddress { variant_unique, symbol [LalinStencil.StencilSymbolId], },
    StencilPatchCoordImmediateI32 { variant_unique, field. value [number], },
    StencilPatchCoordImmediateI64 { variant_unique, field. value [number], },
    StencilPatchCoordRel32Target { variant_unique, symbol [LalinStencil.StencilSymbolId], },
    StencilPatchCoordPointExprConst {
      variant_unique,
      field. value [LalinValue.ValueExpr],
      field. ty [LalinCode.CodeType],
    },
  },

  product. StencilPatchHoleId { interned, text [str], },

  sum. StencilPatchEndian {
    PatchEndianTarget,
    PatchEndianLittle,
    PatchEndianBig,
  },

  sum. StencilPatchHole {
    PatchImm32 {
      variant_unique,
      field. id [LalinResidual.StencilPatchHoleId],
      offset [number],
      signed [bool],
      endian [LalinResidual.StencilPatchEndian],
    },
    PatchImm64 {
      variant_unique,
      field. id [LalinResidual.StencilPatchHoleId],
      offset [number],
      signed [bool],
      endian [LalinResidual.StencilPatchEndian],
    },
    PatchRel32 {
      variant_unique,
      field. id [LalinResidual.StencilPatchHoleId],
      offset [number],
      pc_bias [number],
      addend [number],
      endian [LalinResidual.StencilPatchEndian],
    },
    PatchPtr {
      variant_unique,
      field. id [LalinResidual.StencilPatchHoleId],
      offset [number],
      pointer_bits [number],
      endian [LalinResidual.StencilPatchEndian],
    },
    PatchScalarConst {
      variant_unique,
      field. id [LalinResidual.StencilPatchHoleId],
      offset [number],
      signed [bool],
      bits [number],
      endian [LalinResidual.StencilPatchEndian],
    },
    PatchFieldOffset {
      variant_unique,
      field. id [LalinResidual.StencilPatchHoleId],
      offset [number],
      signed [bool],
      bits [number],
      endian [LalinResidual.StencilPatchEndian],
    },
    PatchStride {
      variant_unique,
      field. id [LalinResidual.StencilPatchHoleId],
      offset [number],
      signed [bool],
      bits [number],
      endian [LalinResidual.StencilPatchEndian],
    },
  },

  product. StencilPatchBinding {
    interned,
    field. hole [LalinResidual.StencilPatchHole],
    coordinate [LalinResidual.StencilPatchCoordinate],
  },

  product. StencilPatchTemplate {
    interned,
    symbol [LalinStencil.StencilSymbolId],
    family [LalinResidual.StencilPatchTemplateFamily],
    target [LalinLuaJIT.LJMCTarget],
    c_signature [str],
    code_blob [str],
    holes [many [LalinResidual.StencilPatchHole]],
  },

  product. StencilPatchExpansionPlan {
    interned,
    descriptor [LalinStencil.StencilDescriptor],
    family [LalinResidual.StencilPatchTemplateFamily],
    template [LalinResidual.StencilPatchTemplate],
    bindings [many [LalinResidual.StencilPatchBinding]],
    target [LalinLuaJIT.LJMCTarget],
  },

  product. StencilPatchProjectionInput {
    interned,
    target [LalinLuaJIT.LJMCTarget],
    storage [LalinResidual.ResidualStorageRequirement],
  },

  sum. StencilPatchTemplateSelection {
	    StencilPatchTemplateSelected {
	      variant_unique,
	      instance [LalinStencil.StencilInstance],
	      family [LalinResidual.StencilPatchTemplateFamily],
	      coordinates [many [LalinResidual.StencilPatchCoordinate]],
	      runtime_params [many [LalinCode.CodeType]],
	    },
    StencilPatchTemplateRejected {
      variant_unique,
      instance [LalinStencil.StencilInstance],
      reason [LalinResidual.ResidualReason],
    },
  },

  sum. StencilArtifactStorage {
    StencilStoredExactMC {
      variant_unique,
      descriptor [LalinStencil.StencilDescriptor],
      artifact [LalinStencil.StencilArtifact],
    },
    StencilStoredPatchTemplateMC {
      variant_unique,
      descriptor [LalinStencil.StencilDescriptor],
      family [LalinResidual.StencilPatchTemplateFamily],
      template [LalinResidual.StencilPatchTemplate],
    },
    StencilRequiresCompile {
      variant_unique,
      descriptor [LalinStencil.StencilDescriptor],
      reason [LalinResidual.ResidualReason],
    },
  },

  sum. MaterializedStencil {
    MaterializedExactStencil {
      variant_unique,
      artifact [LalinStencil.StencilArtifact],
    },
    MaterializedPatchedStencil {
      variant_unique,
      descriptor [LalinStencil.StencilDescriptor],
      family [LalinResidual.StencilPatchTemplateFamily],
      symbol [LalinStencil.StencilSymbolId],
      c_signature [str],
    },
  },

  product. CResidualCapture {
    interned,
    field. name [str],
    field. ty [LalinLuaJIT.LJPhysicalType],
    field. value [LalinLuaJIT.LJValueId],
  },

  sum. CResidualCallResult {
    CResidualCallReturnsVoid,
    CResidualCallReturnsValue {
      variant_unique,
      field. ty [LalinLuaJIT.LJPhysicalType],
    },
  },

  product. CResidualCallToStencil {
    interned,
    stencil [LalinResidual.MaterializedStencil],
    args [many [LalinLuaJIT.LJExpr]],
    result [LalinResidual.CResidualCallResult],
  },

  product. CResidualFunctionDescriptor {
    interned,
    func [LalinLuaJIT.LJFunc],
    wrapper_symbol [str],
    wrapper_ctype [str],
    captures [many [LalinResidual.CResidualCapture]],
    stencil_calls [many [LalinResidual.CResidualCallToStencil]],
  },

  product. CResidualHostSymbol {
    interned,
    field. name [str],
    stencil [LalinResidual.MaterializedStencil],
  },

  product. CResidualWrapper {
    interned,
    func_name [str],
    wrapper_symbol [str],
    wrapper_ctype [str],
  },

  product. CResidualCUnit {
    interned,
    source [str],
    wrappers [many [LalinResidual.CResidualWrapper]],
    host_symbols [many [LalinResidual.CResidualHostSymbol]],
  },

  product. CResidualCompileRequest {
    interned,
    unit [LalinResidual.CResidualCUnit],
    libraries [many [str]],
  },

  sum. CResidualCompileResult {
    CResidualMaterializedFunction {
      variant_unique,
      request [LalinResidual.CResidualCompileRequest],
      wrappers [many [LalinResidual.CResidualWrapper]],
    },
    CResidualRejected {
      variant_unique,
      request [LalinResidual.CResidualCompileRequest],
      reason [LalinResidual.ResidualReason],
    },
  },

  sum. ResidualFunctionPlan {
    ResidualFunctionExactStencil {
      variant_unique,
      func [LalinLuaJIT.LJFunc],
      descriptor [LalinStencil.StencilDescriptor],
      artifact [LalinStencil.StencilArtifact],
    },
    ResidualFunctionPatchTemplate {
      variant_unique,
      func [LalinLuaJIT.LJFunc],
      descriptor [LalinStencil.StencilDescriptor],
      family [LalinResidual.StencilPatchTemplateFamily],
      coordinates [many [LalinResidual.StencilPatchCoordinate]],
      expansion_plan [LalinResidual.StencilPatchExpansionPlan],
    },
    ResidualFunctionC {
      variant_unique,
      func [LalinLuaJIT.LJFunc],
      descriptor [LalinResidual.CResidualFunctionDescriptor],
      unit [LalinResidual.CResidualCUnit],
    },
    ResidualFunctionRejected {
      variant_unique,
      func [LalinLuaJIT.LJFunc],
      reason [LalinResidual.ResidualReason],
    },
  },

  product. ResidualModulePlan {
    interned,
    request [LalinResidual.ResidualLuaJITModuleRequest],
    functions [many [LalinResidual.ResidualFunctionPlan]],
    c_units [many [LalinResidual.CResidualCUnit]],
  },

  product. StencilPatchTemplateEntry {
    interned,
    selection [LalinResidual.StencilPatchTemplateSelection],
    family [LalinResidual.StencilPatchTemplateFamily],
    template_instance [LalinStencil.StencilInstance],
    estimated_template_bytes [number],
    coordinate_count [number],
  },

  product. StencilPatchTemplateBank {
    interned,
    entries [many [LalinResidual.StencilPatchTemplateEntry]],
    template_count [number],
    estimated_template_bytes [number],
    coordinate_count [number],
  },

  sum. StencilTemplateProducerSeed {
    StencilTemplateProducerRange1D,
    StencilTemplateProducerRangeND { variant_unique, rank [number], },
    StencilTemplateProducerTiledND { variant_unique, rank [number], tile_size [number], },
    StencilTemplateProducerWindowND {
      variant_unique,
      rank [number],
      radius [number],
      boundary [LalinStencil.StencilWindowBoundary],
    },
  },

  sum. StencilTemplateLayoutSeed {
    StencilTemplateLayoutContiguous,
    StencilTemplateLayoutAffine1D { variant_unique, scale [number], },
    StencilTemplateLayoutView,
    StencilTemplateLayoutSlice,
    StencilTemplateLayoutByteSpan,
    StencilTemplateLayoutFieldProjection {
      variant_unique,
      record_ty [LalinCode.CodeType],
      field_name [str],
      field_offset [number],
    },
    StencilTemplateLayoutSoAComponent {
      variant_unique,
      record_ty [LalinCode.CodeType],
      field_name [str],
      component_index [number],
    },
    StencilTemplateLayoutIndexed {
      variant_unique,
      index_ty [LalinCode.CodeType],
      stride [number],
    },
    StencilTemplateLayoutScalar,
  },

  sum. StencilTemplatePointSeed {
    StencilTemplatePointInput {
      variant_unique,
      input_index [number],
      field. ty [LalinCode.CodeType],
    },
    StencilTemplatePointConst { variant_unique, field. ty [LalinCode.CodeType], },
    StencilTemplatePointUnary {
      variant_unique,
      op [LalinStencil.StencilUnaryOp],
      field. arg [LalinResidual.StencilTemplatePointSeed],
      result_ty [LalinCode.CodeType],
    },
    StencilTemplatePointBinary {
      variant_unique,
      op [LalinStencil.StencilBinaryOp],
      left [LalinResidual.StencilTemplatePointSeed],
      right [LalinResidual.StencilTemplatePointSeed],
      result_ty [LalinCode.CodeType],
    },
    StencilTemplatePointCompare {
      variant_unique,
      cmp [LalinCore.CmpOp],
      left [LalinResidual.StencilTemplatePointSeed],
      right [LalinResidual.StencilTemplatePointSeed],
      result_ty [LalinCode.CodeType],
    },
    StencilTemplatePointSelect {
      variant_unique,
      cond [LalinResidual.StencilTemplatePointSeed],
      then_expr [LalinResidual.StencilTemplatePointSeed],
      else_expr [LalinResidual.StencilTemplatePointSeed],
      result_ty [LalinCode.CodeType],
    },
  },

  sum. StencilTemplateSinkSeed {
    StencilTemplateSinkStoreN,
    StencilTemplateSinkReduceN { variant_unique, op [LalinValue.ReductionOp], },
    StencilTemplateSinkScanN { variant_unique, op [LalinValue.ReductionOp], },
    StencilTemplateSinkScatterReduceN { variant_unique, op [LalinValue.ReductionOp], },
  },

  sum. StencilTemplateScheduleSeed {
    StencilTemplateScheduleScalar,
    StencilTemplateScheduleVector { variant_unique, lanes [number], },
  },

  product. StencilTemplateScalarSeed {
    interned,
    label [str],
    field. ty [LalinCode.CodeType],
    numeric [bool],
    bitwise [bool],
    signed [bool],
    floating [bool],
  },

  product. StencilTemplateSeed {
    interned,
    producer [LalinResidual.StencilTemplateProducerSeed],
    layout [LalinResidual.StencilTemplateLayoutSeed],
    point [LalinResidual.StencilTemplatePointSeed],
    sink [LalinResidual.StencilTemplateSinkSeed],
    schedule [LalinResidual.StencilTemplateScheduleSeed],
    input_count [number],
    scalar [LalinResidual.StencilTemplateScalarSeed],
  },

  sum. StencilTemplateLimit {
    StencilTemplateUnbounded,
    StencilTemplateLimited { variant_unique, count [number], },
  },

  sum. StencilTemplateShard {
    StencilTemplateUnsharded,
    StencilTemplateShardSlice {
      variant_unique,
      index [number],
      count [number],
    },
  },

  product. StencilTemplateBankRequest {
    interned,
    limit [LalinResidual.StencilTemplateLimit],
    input_count_max [number],
    batch_size [number],
    shard [LalinResidual.StencilTemplateShard],
  },

  product. StencilPatchTemplateBatch {
    interned,
    batch_index [number],
    entries [many [LalinResidual.StencilPatchTemplateEntry]],
  },

  product. StencilArtifactBatch {
    interned,
    batch_index [number],
    artifacts [many [LalinStencil.StencilArtifact]],
  },

}
