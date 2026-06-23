local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonLuaJIT {
  product. LJTypeId { interned, text [str], },
  product. LJFuncSigId { interned, text [str], },
  product. LJFuncId { interned, text [str], },
  product. LJBlockId { interned, text [str], },
  product. LJValueId { interned, text [str], },
  product. LJMachineId { interned, text [str], },
  product. LJHelperId { interned, text [str], },
  product. LJGlobalId { interned, text [str], },
  product. LJLocalId { interned, text [str], },

  sum. LJCType {
    LJCTypeVoid,
    LJCTypeBool,
    LJCTypeScalar {
      variant_unique,
      scalar [MoonBack.BackScalar],
      spelling [str],
    },
    LJCTypePointer {
      variant_unique,
      pointee [optional [MoonLuaJIT.LJCType]],
      mutable [bool],
    },
    LJCTypeArray {
      variant_unique,
      elem [MoonLuaJIT.LJCType],
      count [number],
    },
    LJCTypeNamed {
      variant_unique,
      field. id [MoonLuaJIT.LJTypeId],
      spelling [str],
    },
    LJCTypeFuncPtr {
      variant_unique,
      sig [MoonLuaJIT.LJFuncSigId],
    },
  },

  product. LJCField {
    interned,
    field. name [str],
    field. ty [MoonLuaJIT.LJCType],
    offset [optional [number]],
    size [optional [number]],
    align [optional [number]],
  },

  sum. LJCDecl {
    LJCDeclTypedef {
      variant_unique,
      field. id [MoonLuaJIT.LJTypeId],
      spelling [str],
      field. ty [MoonLuaJIT.LJCType],
    },
    LJCDeclStruct {
      variant_unique,
      field. id [MoonLuaJIT.LJTypeId],
      spelling [str],
      fields [many [MoonLuaJIT.LJCField]],
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
      signedness [MoonCode.CodeIntSignedness],
    },
    LJRegLuaNumber,
    LJRegLuaBoolean,
    LJRegLuaString,
    LJRegCData { variant_unique, field. ty [MoonLuaJIT.LJCType], },
    LJRegTuple { variant_unique, fields [many [MoonLuaJIT.LJCField]], },
  },

  product. LJPhysicalType {
    interned,
    semantic [optional [MoonCode.CodeType]],
    register [MoonLuaJIT.LJRegisterRep],
    storage [MoonLuaJIT.LJCType],
    abi [MoonLuaJIT.LJCType],
  },

  product. LJFieldExpr {
    interned,
    field. name [str],
    field. expr [MoonLuaJIT.LJExpr],
  },

  product. LJArrayExpr {
    interned,
    index [number],
    field. expr [MoonLuaJIT.LJExpr],
  },

  sum. LJPlace {
    LJPlaceLocal {
      variant_unique,
      local_id [MoonLuaJIT.LJLocalId],
      field. ty [MoonLuaJIT.LJPhysicalType],
    },
    LJPlaceGlobal {
      variant_unique,
      global [MoonLuaJIT.LJGlobalId],
      field. ty [MoonLuaJIT.LJPhysicalType],
    },
    LJPlaceData {
      variant_unique,
      data [MoonLuaJIT.LJGlobalId],
      field. ty [MoonLuaJIT.LJPhysicalType],
    },
    LJPlaceDeref {
      variant_unique,
      addr [MoonLuaJIT.LJExpr],
      field. ty [MoonLuaJIT.LJPhysicalType],
      align [optional [number]],
    },
    LJPlaceField {
      variant_unique,
      base [MoonLuaJIT.LJPlace],
      field. name [str],
      field. ty [MoonLuaJIT.LJPhysicalType],
      offset [number],
      size [optional [number]],
      align [optional [number]],
    },
    LJPlaceIndex {
      variant_unique,
      base [MoonLuaJIT.LJPlace],
      index [MoonLuaJIT.LJExpr],
      field. ty [MoonLuaJIT.LJPhysicalType],
      elem_size [number],
    },
    LJPlaceBytes {
      variant_unique,
      base [MoonLuaJIT.LJExpr],
      offset [number],
      field. ty [MoonLuaJIT.LJPhysicalType],
      size [number],
      align [number],
    },
  },

  sum. LJCallTarget {
    LJCallDirect { variant_unique, func [MoonLuaJIT.LJFuncId], },
    LJCallExtern { variant_unique, extern_name [str], },
    LJCallIndirect {
      variant_unique,
      callee [MoonLuaJIT.LJExpr],
      sig [MoonLuaJIT.LJFuncSigId],
    },
    LJCallClosure {
      variant_unique,
      closure [MoonLuaJIT.LJExpr],
      sig [MoonLuaJIT.LJFuncSigId],
    },
  },

  product. LJFuncSig {
    interned,
    field. id [MoonLuaJIT.LJFuncSigId],
    params [many [MoonLuaJIT.LJPhysicalType]],
    result [optional [MoonLuaJIT.LJPhysicalType]],
    c_sig [str],
  },

  product. LJParam {
    interned,
    field. value [MoonLuaJIT.LJValueId],
    field. name [str],
    field. ty [MoonLuaJIT.LJPhysicalType],
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
    LJStateTuple { variant_unique, fields [many [MoonLuaJIT.LJCField]], },
    LJStateUpstream { variant_unique, machine [MoonLuaJIT.LJMachineId], },
    LJStateGeneric { variant_unique, reason [str], },
  },

  sum. LJExpr {
    LJExprValue { variant_unique, field. value [MoonLuaJIT.LJValueId], },
    LJExprLiteral { variant_unique, literal [MoonCore.Literal], field. ty [MoonLuaJIT.LJPhysicalType], },
    LJExprUnary {
      variant_unique,
      op [MoonCore.UnaryOp],
      field. ty [MoonLuaJIT.LJPhysicalType],
      field. value [MoonLuaJIT.LJExpr],
    },
    LJExprIntBinary {
      variant_unique,
      op [MoonCore.BinaryOp],
      field. ty [MoonLuaJIT.LJPhysicalType],
      semantics [MoonCode.CodeIntSemantics],
      lhs [MoonLuaJIT.LJExpr],
      rhs [MoonLuaJIT.LJExpr],
    },
    LJExprFloatBinary {
      variant_unique,
      op [MoonCore.BinaryOp],
      field. ty [MoonLuaJIT.LJPhysicalType],
      mode [MoonCode.CodeFloatMode],
      lhs [MoonLuaJIT.LJExpr],
      rhs [MoonLuaJIT.LJExpr],
    },
    LJExprCompare {
      variant_unique,
      op [MoonCore.CmpOp],
      operand_ty [MoonLuaJIT.LJPhysicalType],
      lhs [MoonLuaJIT.LJExpr],
      rhs [MoonLuaJIT.LJExpr],
    },
    LJExprSelect {
      variant_unique,
      field. ty [MoonLuaJIT.LJPhysicalType],
      cond [MoonLuaJIT.LJExpr],
      then_value [MoonLuaJIT.LJExpr],
      else_value [MoonLuaJIT.LJExpr],
    },
    LJExprIntrinsic {
      variant_unique,
      op [MoonCore.Intrinsic],
      field. ty [MoonLuaJIT.LJPhysicalType],
      args [many [MoonLuaJIT.LJExpr]],
    },
    LJExprCast {
      variant_unique,
      op [MoonCore.MachineCastOp],
      from [MoonLuaJIT.LJPhysicalType],
      to [MoonLuaJIT.LJPhysicalType],
      field. value [MoonLuaJIT.LJExpr],
    },
    LJExprAddrOfPlace {
      variant_unique,
      place [MoonLuaJIT.LJPlace],
      ptr_ty [MoonLuaJIT.LJPhysicalType],
    },
    LJExprGlobalRef {
      variant_unique,
      field. ref [MoonCode.CodeGlobalRef],
      ptr_ty [MoonLuaJIT.LJPhysicalType],
    },
    LJExprPtrOffset {
      variant_unique,
      ptr_ty [MoonLuaJIT.LJPhysicalType],
      base [MoonLuaJIT.LJExpr],
      index [MoonLuaJIT.LJExpr],
      elem_size [number],
      const_offset [number],
    },
    LJExprLoad {
      variant_unique,
      place [MoonLuaJIT.LJPlace],
      access [MoonCode.CodeMemoryAccess],
    },
    LJExprProjectField {
      variant_unique,
      base [MoonLuaJIT.LJExpr],
      field. name [str],
      field. ty [MoonLuaJIT.LJPhysicalType],
      hoist [bool],
    },
    LJExprRecord {
      variant_unique,
      field. ty [MoonLuaJIT.LJPhysicalType],
      fields [many [MoonLuaJIT.LJFieldExpr]],
    },
    LJExprArray {
      variant_unique,
      field. ty [MoonLuaJIT.LJPhysicalType],
      elems [many [MoonLuaJIT.LJArrayExpr]],
    },
    LJExprClosure {
      variant_unique,
      field. ty [MoonLuaJIT.LJPhysicalType],
      fn [MoonLuaJIT.LJExpr],
      ctx [MoonLuaJIT.LJExpr],
      sig [MoonLuaJIT.LJFuncSigId],
    },
    LJExprVariantCtor {
      variant_unique,
      field. ty [MoonLuaJIT.LJPhysicalType],
      variant [MoonCode.CodeVariantRef],
      payload [optional [MoonLuaJIT.LJExpr]],
    },
    LJExprVariantTag {
      variant_unique,
      tag_ty [MoonLuaJIT.LJPhysicalType],
      field. value [MoonLuaJIT.LJExpr],
    },
    LJExprVariantPayload {
      variant_unique,
      field. ty [MoonLuaJIT.LJPhysicalType],
      variant [MoonCode.CodeVariantRef],
      field. value [MoonLuaJIT.LJExpr],
    },
    LJExprCall {
      variant_unique,
      target [MoonLuaJIT.LJCallTarget],
      sig [MoonLuaJIT.LJFuncSigId],
      args [many [MoonLuaJIT.LJExpr]],
      result [optional [MoonLuaJIT.LJPhysicalType]],
    },
    LJExprAtomicLoad {
      variant_unique,
      place [MoonLuaJIT.LJPlace],
      access [MoonCode.CodeMemoryAccess],
      ordering [MoonCore.AtomicOrdering],
    },
    LJExprAtomicRmw {
      variant_unique,
      op [MoonCore.AtomicRmwOp],
      place [MoonLuaJIT.LJPlace],
      field. value [MoonLuaJIT.LJExpr],
      access [MoonCode.CodeMemoryAccess],
      ordering [MoonCore.AtomicOrdering],
      result [MoonLuaJIT.LJPhysicalType],
    },
    LJExprAtomicCas {
      variant_unique,
      place [MoonLuaJIT.LJPlace],
      expected [MoonLuaJIT.LJExpr],
      replacement [MoonLuaJIT.LJExpr],
      access [MoonCode.CodeMemoryAccess],
      ordering [MoonCore.AtomicOrdering],
      result [MoonLuaJIT.LJPhysicalType],
    },
    LJExprCDataCast {
      variant_unique,
      field. ty [MoonLuaJIT.LJCType],
      field. value [MoonLuaJIT.LJExpr],
    },
    LJExprCallHelper {
      variant_unique,
      helper [MoonLuaJIT.LJHelperId],
      args [many [MoonLuaJIT.LJExpr]],
      result [optional [MoonLuaJIT.LJPhysicalType]],
    },
  },

  sum. LJMachineKind {
    LJMachineEmpty,
    LJMachineOne { variant_unique, field. value [MoonLuaJIT.LJExpr], },
    LJMachineSourceArray {
      variant_unique,
      array [MoonLuaJIT.LJValueId],
      elem_ty [MoonLuaJIT.LJPhysicalType],
      length [optional [MoonLuaJIT.LJExpr]],
    },
    LJMachineSourceRange {
      variant_unique,
      start [MoonLuaJIT.LJExpr],
      stop [MoonLuaJIT.LJExpr],
      step [MoonLuaJIT.LJExpr],
      scalar [MoonBack.BackScalar],
    },
    LJMachineMap {
      variant_unique,
      input [MoonLuaJIT.LJMachineId],
      binding [MoonLuaJIT.LJValueId],
      field. expr [MoonLuaJIT.LJExpr],
    },
    LJMachineFilter {
      variant_unique,
      input [MoonLuaJIT.LJMachineId],
      binding [MoonLuaJIT.LJValueId],
      pred [MoonLuaJIT.LJExpr],
    },
    LJMachineConcat {
      variant_unique,
      inputs [many [MoonLuaJIT.LJMachineId]],
    },
    LJMachineFlatMap {
      variant_unique,
      input [MoonLuaJIT.LJMachineId],
      binding [MoonLuaJIT.LJValueId],
      body [MoonLuaJIT.LJMachineId],
    },
    LJMachineFold {
      variant_unique,
      input [MoonLuaJIT.LJMachineId],
      acc [MoonLuaJIT.LJValueId],
      item [MoonLuaJIT.LJValueId],
      init [MoonLuaJIT.LJExpr],
      step [MoonLuaJIT.LJExpr],
    },
    LJMachineVectorReduceArray {
      variant_unique,
      array [MoonLuaJIT.LJValueId],
      start [MoonLuaJIT.LJExpr],
      stop [MoonLuaJIT.LJExpr],
      step [MoonLuaJIT.LJExpr],
      elem_ty [MoonLuaJIT.LJPhysicalType],
      result_ty [MoonLuaJIT.LJPhysicalType],
      reduction [MoonValue.ReductionKind],
      semantics [optional [MoonCode.CodeIntSemantics]],
      init [MoonLuaJIT.LJExpr],
      lanes [number],
      unroll [number],
    },
    LJMachineStencilCall {
      variant_unique,
      artifact [MoonStencil.StencilArtifact],
      args [many [MoonLuaJIT.LJExpr]],
      result_ty [MoonLuaJIT.LJPhysicalType],
    },
    LJMachinePhaseCall {
      variant_unique,
      phase [str],
      args [many [MoonLuaJIT.LJExpr]],
    },
  },

  product. LJMachine {
    interned,
    field. id [MoonLuaJIT.LJMachineId],
    kind [MoonLuaJIT.LJMachineKind],
    result [optional [MoonLuaJIT.LJPhysicalType]],
    state [MoonLuaJIT.LJStateShape],
    trace [MoonLuaJIT.LJTraceHint],
  },

  sum. LJStmt {
    LJStmtLet {
      variant_unique,
      dst [MoonLuaJIT.LJValueId],
      field. ty [MoonLuaJIT.LJPhysicalType],
      field. expr [MoonLuaJIT.LJExpr],
    },
    LJStmtStore {
      variant_unique,
      place [MoonLuaJIT.LJPlace],
      field. value [MoonLuaJIT.LJExpr],
      field. ty [MoonLuaJIT.LJPhysicalType],
      access [MoonCode.CodeMemoryAccess],
    },
    LJStmtCall {
      variant_unique,
      target [MoonLuaJIT.LJCallTarget],
      sig [MoonLuaJIT.LJFuncSigId],
      args [many [MoonLuaJIT.LJExpr]],
    },
    LJStmtIntrinsic {
      variant_unique,
      op [MoonCore.Intrinsic],
      field. ty [MoonLuaJIT.LJPhysicalType],
      args [many [MoonLuaJIT.LJExpr]],
    },
    LJStmtAtomicStore {
      variant_unique,
      place [MoonLuaJIT.LJPlace],
      field. value [MoonLuaJIT.LJExpr],
      access [MoonCode.CodeMemoryAccess],
      ordering [MoonCore.AtomicOrdering],
    },
    LJStmtAtomicFence {
      variant_unique,
      ordering [MoonCore.AtomicOrdering],
    },
    LJStmtEmitMachine {
      variant_unique,
      machine [MoonLuaJIT.LJMachineId],
    },
  },

  product. LJCase {
    interned,
    literal [MoonCore.Literal],
    dest [MoonLuaJIT.LJBlockId],
    args [many [MoonLuaJIT.LJExpr]],
  },

  sum. LJTerm {
    LJTermJump {
      variant_unique,
      dest [MoonLuaJIT.LJBlockId],
      args [many [MoonLuaJIT.LJExpr]],
    },
    LJTermBranch {
      variant_unique,
      cond [MoonLuaJIT.LJExpr],
      then_dest [MoonLuaJIT.LJBlockId],
      then_args [many [MoonLuaJIT.LJExpr]],
      else_dest [MoonLuaJIT.LJBlockId],
      else_args [many [MoonLuaJIT.LJExpr]],
    },
    LJTermSwitch {
      variant_unique,
      field. value [MoonLuaJIT.LJExpr],
      cases [many [MoonLuaJIT.LJCase]],
      default_dest [MoonLuaJIT.LJBlockId],
      default_args [many [MoonLuaJIT.LJExpr]],
    },
    LJTermReturn { variant_unique, values [many [MoonLuaJIT.LJExpr]], },
    LJTermTrap { variant_unique, reason [str], },
  },

  product. LJBlock {
    interned,
    field. id [MoonLuaJIT.LJBlockId],
    params [many [MoonLuaJIT.LJParam]],
    stmts [many [MoonLuaJIT.LJStmt]],
    term [MoonLuaJIT.LJTerm],
  },

  sum. LJTerminal {
    LJTerminalIterator,
    LJTerminalCollect,
    LJTerminalFirst { variant_unique, default [optional [MoonLuaJIT.LJExpr]], },
    LJTerminalFold { variant_unique, init [MoonLuaJIT.LJExpr], step [MoonLuaJIT.LJExpr], },
  },

  sum. LJFuncBody {
    LJBodyMachine {
      variant_unique,
      machine [MoonLuaJIT.LJMachineId],
      terminal [MoonLuaJIT.LJTerminal],
    },
    LJBodyBlocks {
      variant_unique,
      entry [MoonLuaJIT.LJBlockId],
      blocks [many [MoonLuaJIT.LJBlock]],
    },
    LJBodySource {
      variant_unique,
      source [str],
      reason [str],
    },
  },

  product. LJFunc {
    interned,
    field. id [MoonLuaJIT.LJFuncId],
    source [optional [MoonCode.CodeFuncId]],
    field. name [str],
    sig [MoonLuaJIT.LJFuncSigId],
    params [many [MoonLuaJIT.LJParam]],
    cdefs [many [MoonLuaJIT.LJCDecl]],
    machines [many [MoonLuaJIT.LJMachine]],
    body [MoonLuaJIT.LJFuncBody],
    trace [MoonLuaJIT.LJTraceHint],
  },

  product. LJModule {
    interned,
    source [optional [MoonCode.CodeModuleId]],
    funcs [many [MoonLuaJIT.LJFunc]],
    sigs [many [MoonLuaJIT.LJFuncSig]],
    types [many [MoonLuaJIT.LJCDecl]],
    helpers [many [MoonLuaJIT.LJHelperId]],
  },
}
