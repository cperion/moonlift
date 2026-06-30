local S = require("lalin.schema.dsl")
S.use()

return schema. LalinLuaJIT {
  product. LJTypeId { interned, text [str], },
  product. LJFuncSigId { interned, text [str], },
  product. LJFuncId { interned, text [str], },
  product. LJBlockId { interned, text [str], },
  product. LJValueId { interned, text [str], },
  product. LJMachineId { interned, text [str], },
  product. LJHelperId { interned, text [str], },
  product. LJGlobalId { interned, text [str], },
  product. LJLocalId { interned, text [str], },
  product. LJMCBankId { interned, text [str], },
  product. LJBCBankId { interned, text [str], },
  product. LJBCStencilId { interned, text [str], },

  sum. LJCType {
    LJCTypeVoid,
    LJCTypeBool,
    LJCTypeScalar {
      variant_unique,
      scalar [LalinBack.BackScalar],
      spelling [str],
    },
    LJCTypePointer {
      variant_unique,
      pointee [optional [LalinLuaJIT.LJCType]],
      mutable [bool],
    },
    LJCTypeArray {
      variant_unique,
      elem [LalinLuaJIT.LJCType],
      count [number],
    },
    LJCTypeNamed {
      variant_unique,
      field. id [LalinLuaJIT.LJTypeId],
      spelling [str],
    },
    LJCTypeFuncPtr {
      variant_unique,
      sig [LalinLuaJIT.LJFuncSigId],
    },
  },

  product. LJCField {
    interned,
    field. name [str],
    field. ty [LalinLuaJIT.LJCType],
    offset [optional [number]],
    size [optional [number]],
    align [optional [number]],
  },

  sum. LJCDecl {
    LJCDeclTypedef {
      variant_unique,
      field. id [LalinLuaJIT.LJTypeId],
      spelling [str],
      field. ty [LalinLuaJIT.LJCType],
    },
    LJCDeclStruct {
      variant_unique,
      field. id [LalinLuaJIT.LJTypeId],
      spelling [str],
      fields [many [LalinLuaJIT.LJCField]],
      size [optional [number]],
      align [optional [number]],
    },
    LJCDeclRaw {
      variant_unique,
      source [str],
      reason [str],
    },
  },

  sum. LJRegisterRep {
    LJRegVoid,
    LJRegTraceInt32 {
      variant_unique,
      bits [number],
      signedness [LalinCode.CodeIntSignedness],
    },
    LJRegLuaNumber,
    LJRegLuaBoolean,
    LJRegLuaString,
    LJRegCData { variant_unique, field. ty [LalinLuaJIT.LJCType], },
    LJRegTuple { variant_unique, fields [many [LalinLuaJIT.LJCField]], },
  },

  product. LJPhysicalType {
    interned,
    semantic [optional [LalinCode.CodeType]],
    register [LalinLuaJIT.LJRegisterRep],
    storage [LalinLuaJIT.LJCType],
    abi [LalinLuaJIT.LJCType],
  },

  product. LJFieldExpr {
    interned,
    field. name [str],
    field. expr [LalinLuaJIT.LJExpr],
  },

  product. LJArrayExpr {
    interned,
    index [number],
    field. expr [LalinLuaJIT.LJExpr],
  },

  sum. LJPlace {
    LJPlaceLocal {
      variant_unique,
      local_id [LalinLuaJIT.LJLocalId],
      field. ty [LalinLuaJIT.LJPhysicalType],
    },
    LJPlaceGlobal {
      variant_unique,
      global [LalinLuaJIT.LJGlobalId],
      field. ty [LalinLuaJIT.LJPhysicalType],
    },
    LJPlaceData {
      variant_unique,
      data [LalinLuaJIT.LJGlobalId],
      field. ty [LalinLuaJIT.LJPhysicalType],
    },
    LJPlaceDeref {
      variant_unique,
      addr [LalinLuaJIT.LJExpr],
      field. ty [LalinLuaJIT.LJPhysicalType],
      align [optional [number]],
    },
    LJPlaceField {
      variant_unique,
      base [LalinLuaJIT.LJPlace],
      field. name [str],
      field. ty [LalinLuaJIT.LJPhysicalType],
      offset [number],
      size [optional [number]],
      align [optional [number]],
    },
    LJPlaceIndex {
      variant_unique,
      base [LalinLuaJIT.LJPlace],
      index [LalinLuaJIT.LJExpr],
      field. ty [LalinLuaJIT.LJPhysicalType],
      elem_size [number],
    },
    LJPlaceBytes {
      variant_unique,
      base [LalinLuaJIT.LJExpr],
      offset [number],
      field. ty [LalinLuaJIT.LJPhysicalType],
      size [number],
      align [number],
    },
  },

  sum. LJCallTarget {
    LJCallDirect { variant_unique, func [LalinLuaJIT.LJFuncId], },
    LJCallExtern { variant_unique, extern_name [str], },
    LJCallIndirect {
      variant_unique,
      callee [LalinLuaJIT.LJExpr],
      sig [LalinLuaJIT.LJFuncSigId],
    },
    LJCallClosure {
      variant_unique,
      closure [LalinLuaJIT.LJExpr],
      sig [LalinLuaJIT.LJFuncSigId],
    },
  },

  product. LJFuncSig {
    interned,
    field. id [LalinLuaJIT.LJFuncSigId],
    params [many [LalinLuaJIT.LJPhysicalType]],
    result [optional [LalinLuaJIT.LJPhysicalType]],
    c_sig [str],
  },

  product. LJParam {
    interned,
    field. value [LalinLuaJIT.LJValueId],
    field. name [str],
    field. ty [LalinLuaJIT.LJPhysicalType],
  },

  sum. LJTraceHint {
    LJTraceHot,
    LJTraceCold,
    LJTraceFusePreferred,
    LJTraceNoFuse { variant_unique, reason [str], },
  },

  sum. LJStateShape {
    LJStateNone,
    LJStateScalar,
    LJStateTuple { variant_unique, fields [many [LalinLuaJIT.LJCField]], },
    LJStateUpstream { variant_unique, machine [LalinLuaJIT.LJMachineId], },
    LJStateGeneric { variant_unique, reason [str], },
  },

  sum. LJExpr {
    LJExprValue { variant_unique, field. value [LalinLuaJIT.LJValueId], },
    LJExprLiteral { variant_unique, literal [LalinCore.Literal], field. ty [LalinLuaJIT.LJPhysicalType], },
    LJExprUnary {
      variant_unique,
      op [LalinCore.UnaryOp],
      field. ty [LalinLuaJIT.LJPhysicalType],
      field. value [LalinLuaJIT.LJExpr],
    },
    LJExprIntBinary {
      variant_unique,
      op [LalinCore.BinaryOp],
      field. ty [LalinLuaJIT.LJPhysicalType],
      semantics [LalinCode.CodeIntSemantics],
      lhs [LalinLuaJIT.LJExpr],
      rhs [LalinLuaJIT.LJExpr],
    },
    LJExprFloatBinary {
      variant_unique,
      op [LalinCore.BinaryOp],
      field. ty [LalinLuaJIT.LJPhysicalType],
      mode [LalinCode.CodeFloatMode],
      lhs [LalinLuaJIT.LJExpr],
      rhs [LalinLuaJIT.LJExpr],
    },
    LJExprCompare {
      variant_unique,
      op [LalinCore.CmpOp],
      operand_ty [LalinLuaJIT.LJPhysicalType],
      lhs [LalinLuaJIT.LJExpr],
      rhs [LalinLuaJIT.LJExpr],
    },
    LJExprSelect {
      variant_unique,
      field. ty [LalinLuaJIT.LJPhysicalType],
      cond [LalinLuaJIT.LJExpr],
      then_value [LalinLuaJIT.LJExpr],
      else_value [LalinLuaJIT.LJExpr],
    },
    LJExprIntrinsic {
      variant_unique,
      op [LalinCore.Intrinsic],
      field. ty [LalinLuaJIT.LJPhysicalType],
      args [many [LalinLuaJIT.LJExpr]],
    },
    LJExprCast {
      variant_unique,
      op [LalinCore.MachineCastOp],
      from [LalinLuaJIT.LJPhysicalType],
      to [LalinLuaJIT.LJPhysicalType],
      field. value [LalinLuaJIT.LJExpr],
    },
    LJExprAddrOfPlace {
      variant_unique,
      place [LalinLuaJIT.LJPlace],
      ptr_ty [LalinLuaJIT.LJPhysicalType],
    },
    LJExprGlobalRef {
      variant_unique,
      field. ref [LalinCode.CodeGlobalRef],
      ptr_ty [LalinLuaJIT.LJPhysicalType],
    },
    LJExprPtrOffset {
      variant_unique,
      ptr_ty [LalinLuaJIT.LJPhysicalType],
      base [LalinLuaJIT.LJExpr],
      index [LalinLuaJIT.LJExpr],
      elem_size [number],
      const_offset [number],
    },
    LJExprLoad {
      variant_unique,
      place [LalinLuaJIT.LJPlace],
      access [LalinCode.CodeMemoryAccess],
    },
    LJExprProjectField {
      variant_unique,
      base [LalinLuaJIT.LJExpr],
      field. name [str],
      field. ty [LalinLuaJIT.LJPhysicalType],
      hoist [bool],
    },
    LJExprRecord {
      variant_unique,
      field. ty [LalinLuaJIT.LJPhysicalType],
      fields [many [LalinLuaJIT.LJFieldExpr]],
    },
    LJExprArray {
      variant_unique,
      field. ty [LalinLuaJIT.LJPhysicalType],
      elems [many [LalinLuaJIT.LJArrayExpr]],
    },
    LJExprClosure {
      variant_unique,
      field. ty [LalinLuaJIT.LJPhysicalType],
      fn [LalinLuaJIT.LJExpr],
      ctx [LalinLuaJIT.LJExpr],
      sig [LalinLuaJIT.LJFuncSigId],
    },
    LJExprVariantCtor {
      variant_unique,
      field. ty [LalinLuaJIT.LJPhysicalType],
      variant [LalinCode.CodeVariantRef],
      payload [optional [LalinLuaJIT.LJExpr]],
    },
    LJExprVariantTag {
      variant_unique,
      tag_ty [LalinLuaJIT.LJPhysicalType],
      field. value [LalinLuaJIT.LJExpr],
    },
    LJExprVariantPayload {
      variant_unique,
      field. ty [LalinLuaJIT.LJPhysicalType],
      variant [LalinCode.CodeVariantRef],
      field. value [LalinLuaJIT.LJExpr],
    },
    LJExprCall {
      variant_unique,
      target [LalinLuaJIT.LJCallTarget],
      sig [LalinLuaJIT.LJFuncSigId],
      args [many [LalinLuaJIT.LJExpr]],
      result [optional [LalinLuaJIT.LJPhysicalType]],
    },
    LJExprAtomicLoad {
      variant_unique,
      place [LalinLuaJIT.LJPlace],
      access [LalinCode.CodeMemoryAccess],
      ordering [LalinCore.AtomicOrdering],
    },
    LJExprAtomicRmw {
      variant_unique,
      op [LalinCore.AtomicRmwOp],
      place [LalinLuaJIT.LJPlace],
      field. value [LalinLuaJIT.LJExpr],
      access [LalinCode.CodeMemoryAccess],
      ordering [LalinCore.AtomicOrdering],
      result [LalinLuaJIT.LJPhysicalType],
    },
    LJExprAtomicCas {
      variant_unique,
      place [LalinLuaJIT.LJPlace],
      expected [LalinLuaJIT.LJExpr],
      replacement [LalinLuaJIT.LJExpr],
      access [LalinCode.CodeMemoryAccess],
      ordering [LalinCore.AtomicOrdering],
      result [LalinLuaJIT.LJPhysicalType],
    },
    LJExprCDataCast {
      variant_unique,
      field. ty [LalinLuaJIT.LJCType],
      field. value [LalinLuaJIT.LJExpr],
    },
    LJExprCallHelper {
      variant_unique,
      helper [LalinLuaJIT.LJHelperId],
      args [many [LalinLuaJIT.LJExpr]],
      result [optional [LalinLuaJIT.LJPhysicalType]],
    },
  },

  sum. LJMachineOp {
    LJMachineEmpty,
    LJMachineOne { variant_unique, field. value [LalinLuaJIT.LJExpr], },
    LJMachineSourceArray {
      variant_unique,
      array [LalinLuaJIT.LJValueId],
      elem_ty [LalinLuaJIT.LJPhysicalType],
      length [optional [LalinLuaJIT.LJExpr]],
    },
    LJMachineSourceRange {
      variant_unique,
      start [LalinLuaJIT.LJExpr],
      stop [LalinLuaJIT.LJExpr],
      step [LalinLuaJIT.LJExpr],
      scalar [LalinBack.BackScalar],
    },
    LJMachineMap {
      variant_unique,
      input [LalinLuaJIT.LJMachineId],
      binding [LalinLuaJIT.LJValueId],
      field. expr [LalinLuaJIT.LJExpr],
    },
    LJMachineFilter {
      variant_unique,
      input [LalinLuaJIT.LJMachineId],
      binding [LalinLuaJIT.LJValueId],
      pred [LalinLuaJIT.LJExpr],
    },
    LJMachineConcat {
      variant_unique,
      inputs [many [LalinLuaJIT.LJMachineId]],
    },
    LJMachineFlatMap {
      variant_unique,
      input [LalinLuaJIT.LJMachineId],
      binding [LalinLuaJIT.LJValueId],
      body [LalinLuaJIT.LJMachineId],
    },
    LJMachineFold {
      variant_unique,
      input [LalinLuaJIT.LJMachineId],
      acc [LalinLuaJIT.LJValueId],
      item [LalinLuaJIT.LJValueId],
      init [LalinLuaJIT.LJExpr],
      step [LalinLuaJIT.LJExpr],
    },
    LJMachineStencilCall {
      variant_unique,
      artifact [LalinStencil.StencilArtifact],
      args [many [LalinLuaJIT.LJExpr]],
      result_ty [LalinLuaJIT.LJPhysicalType],
    },
    LJMachineStencilEffect {
      variant_unique,
      artifact [LalinStencil.StencilArtifact],
      args [many [LalinLuaJIT.LJExpr]],
    },
    LJMachinePhaseCall {
      variant_unique,
      phase [str],
      args [many [LalinLuaJIT.LJExpr]],
    },
  },

  product. LJMachine {
    interned,
    field. id [LalinLuaJIT.LJMachineId],
    op [LalinLuaJIT.LJMachineOp],
    result [optional [LalinLuaJIT.LJPhysicalType]],
    state [LalinLuaJIT.LJStateShape],
    trace [LalinLuaJIT.LJTraceHint],
  },

  product. LJStencilMachinePlan {
    interned,
    func [LalinCode.CodeFuncId],
    kernel [LalinKernel.KernelId],
    machine [LalinLuaJIT.LJMachine],
    artifact [LalinStencil.StencilArtifact],
  },

  product. LJStencilMachineModulePlan {
    interned,
    field. module [LalinCode.CodeModuleId],
    stencil [LalinStencil.StencilModulePlan],
    machines [many [LalinLuaJIT.LJStencilMachinePlan]],
  },

  sum. LJStmt {
    LJStmtLet {
      variant_unique,
      dst [LalinLuaJIT.LJValueId],
      field. ty [LalinLuaJIT.LJPhysicalType],
      field. expr [LalinLuaJIT.LJExpr],
    },
    LJStmtStore {
      variant_unique,
      place [LalinLuaJIT.LJPlace],
      field. value [LalinLuaJIT.LJExpr],
      field. ty [LalinLuaJIT.LJPhysicalType],
      access [LalinCode.CodeMemoryAccess],
    },
    LJStmtCall {
      variant_unique,
      target [LalinLuaJIT.LJCallTarget],
      sig [LalinLuaJIT.LJFuncSigId],
      args [many [LalinLuaJIT.LJExpr]],
    },
    LJStmtIntrinsic {
      variant_unique,
      op [LalinCore.Intrinsic],
      field. ty [LalinLuaJIT.LJPhysicalType],
      args [many [LalinLuaJIT.LJExpr]],
    },
    LJStmtAtomicStore {
      variant_unique,
      place [LalinLuaJIT.LJPlace],
      field. value [LalinLuaJIT.LJExpr],
      access [LalinCode.CodeMemoryAccess],
      ordering [LalinCore.AtomicOrdering],
    },
    LJStmtAtomicFence {
      variant_unique,
      ordering [LalinCore.AtomicOrdering],
    },
    LJStmtEmitMachine {
      variant_unique,
      machine [LalinLuaJIT.LJMachineId],
    },
  },

  product. LJCase {
    interned,
    literal [LalinCore.Literal],
    dest [LalinLuaJIT.LJBlockId],
    args [many [LalinLuaJIT.LJExpr]],
  },

  sum. LJTerm {
    LJTermJump {
      variant_unique,
      dest [LalinLuaJIT.LJBlockId],
      args [many [LalinLuaJIT.LJExpr]],
    },
    LJTermBranch {
      variant_unique,
      cond [LalinLuaJIT.LJExpr],
      then_dest [LalinLuaJIT.LJBlockId],
      then_args [many [LalinLuaJIT.LJExpr]],
      else_dest [LalinLuaJIT.LJBlockId],
      else_args [many [LalinLuaJIT.LJExpr]],
    },
    LJTermSwitch {
      variant_unique,
      field. value [LalinLuaJIT.LJExpr],
      cases [many [LalinLuaJIT.LJCase]],
      default_dest [LalinLuaJIT.LJBlockId],
      default_args [many [LalinLuaJIT.LJExpr]],
    },
    LJTermReturn { variant_unique, values [many [LalinLuaJIT.LJExpr]], },
    LJTermTrap { variant_unique, reason [str], },
  },

  product. LJBlock {
    interned,
    field. id [LalinLuaJIT.LJBlockId],
    params [many [LalinLuaJIT.LJParam]],
    stmts [many [LalinLuaJIT.LJStmt]],
    term [LalinLuaJIT.LJTerm],
  },

  sum. LJTerminal {
    LJTerminalIterator,
    LJTerminalCollect,
    LJTerminalFirst { variant_unique, default [optional [LalinLuaJIT.LJExpr]], },
    LJTerminalFold { variant_unique, init [LalinLuaJIT.LJExpr], step [LalinLuaJIT.LJExpr], },
  },

  sum. LJFuncBody {
    LJBodyMachine {
      machine [LalinLuaJIT.LJMachineId],
      terminal [LalinLuaJIT.LJTerminal],
    },
    LJBodyBlocks {
      entry [LalinLuaJIT.LJBlockId],
      blocks [many [LalinLuaJIT.LJBlock]],
    },
  },

  product. LJFunc {
    interned,
    field. id [LalinLuaJIT.LJFuncId],
    source [optional [LalinCode.CodeFuncId]],
    field. name [str],
    sig [LalinLuaJIT.LJFuncSigId],
    params [many [LalinLuaJIT.LJParam]],
    cdefs [many [LalinLuaJIT.LJCDecl]],
    machines [many [LalinLuaJIT.LJMachine]],
    body [LalinLuaJIT.LJFuncBody],
    trace [LalinLuaJIT.LJTraceHint],
  },

  product. LJModule {
    interned,
    source [optional [LalinCode.CodeModuleId]],
    funcs [many [LalinLuaJIT.LJFunc]],
    sigs [many [LalinLuaJIT.LJFuncSig]],
    types [many [LalinLuaJIT.LJCDecl]],
    helpers [many [LalinLuaJIT.LJHelperId]],
    data [many [LalinCode.CodeData]],
  },

  product. LJMCTarget {
    interned,
    arch [str],
    field. os [str],
    abi [str],
    pointer_bits [number],
    endian [str],
  },

  sum. LJMCAddressPolicy {
    LJMCInstallAnyAddress,
    LJMCInstallLow32Address,
  },

  sum. LJMCProtectionPolicy {
    LJMCInstallWriteThenExec,
    LJMCInstallReadWriteExec,
  },

  product. LJMCInstallPolicy {
    interned,
    address [LalinLuaJIT.LJMCAddressPolicy],
    protection [LalinLuaJIT.LJMCProtectionPolicy],
  },

  product. LJMCStencilEntry {
    symbol [str],
    section [str],
    binary [str],
    c_signature [str],
    artifact [LalinStencil.StencilArtifact],
  },

  product. LJMCStencilBank {
    field. id [LalinLuaJIT.LJMCBankId],
    target [LalinLuaJIT.LJMCTarget],
    install [LalinLuaJIT.LJMCInstallPolicy],
    c_path [str],
    o_path [str],
    source [str],
    command [str],
    ffi_preamble [optional [str]],
    entries [many [LalinLuaJIT.LJMCStencilEntry]],
    metastencil_covers [many [LalinStencil.StencilMetastencilCandidate]],
  },

  product. LJBCTarget {
    interned,
    luajit_version [str],
    arch [str],
    field. os [str],
    pointer_bits [number],
    endian [str],
    gc64 [bool],
    dualnum [bool],
    ffi [bool],
  },

  product. LJBCStencilEntry {
    field. id [LalinLuaJIT.LJBCStencilId],
    symbol [str],
    chunk_name [str],
    source [str],
    bytecode [str],
    plan [optional [LalinLuaTrace.LTFunction]],
    artifact [optional [LalinStencil.StencilArtifact]],
  },

  product. LJBCStencilBank {
    field. id [LalinLuaJIT.LJBCBankId],
    target [LalinLuaJIT.LJBCTarget],
    entries [many [LalinLuaJIT.LJBCStencilEntry]],
    metastencil_covers [many [LalinStencil.StencilMetastencilCandidate]],
  },
}
