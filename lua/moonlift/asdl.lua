local M = {}

M.SCHEMA = [[
module Moon2Core {
    Name = (string text) unique
    Path = (Moon2Core.Name* parts) unique
    Id = (string text) unique
    ModuleId = (string text) unique
    ItemId = (string text) unique
    FieldId = (string text) unique

    Phase = PhaseSurface | PhaseTyped | PhaseOpen | PhaseSem | PhaseCode
    Visibility = VisibilityLocal | VisibilityExport

    Scalar = ScalarVoid
           | ScalarBool
           | ScalarI8 | ScalarI16 | ScalarI32 | ScalarI64
           | ScalarU8 | ScalarU16 | ScalarU32 | ScalarU64
           | ScalarF32 | ScalarF64
           | ScalarRawPtr
           | ScalarIndex

    ScalarFamily = ScalarFamilyVoid
                 | ScalarFamilyBool
                 | ScalarFamilySignedInt
                 | ScalarFamilyUnsignedInt
                 | ScalarFamilyFloat
                 | ScalarFamilyRawPtr
                 | ScalarFamilyIndex
    ScalarBits = (number bits) unique
    ScalarInfo = (Moon2Core.ScalarFamily family, Moon2Core.ScalarBits bits) unique

    Literal = LitInt(string raw) unique
            | LitFloat(string raw) unique
            | LitBool(boolean value) unique
            | LitNil

    UnaryOp = UnaryNeg | UnaryNot | UnaryBitNot
    BinaryOp = BinAdd | BinSub | BinMul | BinDiv | BinRem
             | BinBitAnd | BinBitOr | BinBitXor
             | BinShl | BinLShr | BinAShr
    CmpOp = CmpEq | CmpNe | CmpLt | CmpLe | CmpGt | CmpGe
    LogicOp = LogicAnd | LogicOr
    SurfaceCastOp = SurfaceCast | SurfaceTrunc | SurfaceZExt | SurfaceSExt | SurfaceBitcast | SurfaceSatCast
    MachineCastOp = MachineCastIdentity
                  | MachineCastBitcast
                  | MachineCastIreduce
                  | MachineCastSextend
                  | MachineCastUextend
                  | MachineCastFpromote
                  | MachineCastFdemote
                  | MachineCastSToF
                  | MachineCastUToF
                  | MachineCastFToS
                  | MachineCastFToU

    Intrinsic = IntrinsicPopcount
              | IntrinsicClz
              | IntrinsicCtz
              | IntrinsicRotl
              | IntrinsicRotr
              | IntrinsicBswap
              | IntrinsicFma
              | IntrinsicSqrt
              | IntrinsicAbs
              | IntrinsicFloor
              | IntrinsicCeil
              | IntrinsicTruncFloat
              | IntrinsicRound
              | IntrinsicTrap
              | IntrinsicAssume

    UnaryOpClass = UnaryClassArithmetic
                 | UnaryClassLogical
                 | UnaryClassBitwise
    BinaryOpClass = BinaryClassArithmetic
                  | BinaryClassDivision
                  | BinaryClassRemainder
                  | BinaryClassBitwise
                  | BinaryClassShift
    CmpOpClass = CmpClassEquality
               | CmpClassOrdering
    IntrinsicClass = IntrinsicClassBit
                   | IntrinsicClassFloat
                   | IntrinsicClassFused
                   | IntrinsicClassControl

    TypeSym = (string key, string name) unique
    FuncSym = (string key, string name) unique
    ExternSym = (string key, string name, string symbol) unique
    ConstSym = (string key, string name) unique
    StaticSym = (string key, string name) unique
}

module Moon2Back {
    BackScalar = BackVoid
               | BackBool
               | BackI8 | BackI16 | BackI32 | BackI64
               | BackU8 | BackU16 | BackU32 | BackU64
               | BackF32 | BackF64
               | BackPtr
               | BackIndex

    BackSigId = (string text) unique
    BackFuncId = (string text) unique
    BackExternId = (string text) unique
    BackDataId = (string text) unique
    BackBlockId = (string text) unique
    BackValId = (string text) unique
    BackStackSlotId = (string text) unique
    BackSwitchCase = (string raw, Moon2Back.BackBlockId dest) unique
    BackVec = (Moon2Back.BackScalar elem, number lanes) unique
    BackShape = BackShapeScalar(Moon2Back.BackScalar scalar) unique
              | BackShapeVec(Moon2Back.BackVec vec) unique

    BackTarget = BackTargetNative
               | BackTargetCraneliftJit
               | BackTargetNamed(string name) unique
    BackEndian = BackEndianLittle | BackEndianBig
    BackTargetFeature = BackFeatureSSE2
                      | BackFeatureAVX2
                      | BackFeatureAVX512F
                      | BackFeatureFMA
                      | BackFeaturePOPCNT
                      | BackFeatureBMI1
                      | BackFeatureBMI2
                      | BackFeatureUnknown(string name) unique
    BackTargetFact = BackTargetPointerBits(number bits) unique
                   | BackTargetIndexBits(number bits) unique
                   | BackTargetEndian(Moon2Back.BackEndian endian) unique
                   | BackTargetCacheLineBytes(number bytes) unique
                   | BackTargetFeature(Moon2Back.BackTargetFeature feature) unique
                   | BackTargetSupportsShape(Moon2Back.BackShape shape) unique
                   | BackTargetSupportsVectorOp(Moon2Back.BackVec vec, string op_class) unique
                   | BackTargetSupportsMaskedTail
                   | BackTargetPrefersUnroll(Moon2Back.BackShape shape, number unroll, number rank) unique
    BackTargetModel = (Moon2Back.BackTarget target, Moon2Back.BackTargetFact* facts) unique

    BackAddressBase = BackAddrValue(Moon2Back.BackValId value) unique
                    | BackAddrStack(Moon2Back.BackStackSlotId slot) unique
                    | BackAddrData(Moon2Back.BackDataId data) unique
    BackPointerProvenance = BackProvUnknown
                          | BackProvStack(Moon2Back.BackStackSlotId slot) unique
                          | BackProvData(Moon2Back.BackDataId data) unique
                          | BackProvArg(string name) unique
                          | BackProvView(string name) unique
                          | BackProvDerived(string reason) unique
    BackPointerBounds = BackPtrBoundsUnknown
                      | BackPtrInBounds(string reason) unique
                      | BackPtrMayLeaveObject(string reason) unique
    BackAddress = (Moon2Back.BackAddressBase base, Moon2Back.BackValId byte_offset, Moon2Back.BackPointerProvenance provenance, Moon2Back.BackPointerBounds formation_bounds) unique

    BackAccessId = (string text) unique
    BackAliasScopeId = (string text) unique
    BackAlignment = BackAlignUnknown
                  | BackAlignKnown(number bytes) unique
                  | BackAlignAtLeast(number bytes) unique
                  | BackAlignAssumed(number bytes, string reason) unique
    BackDereference = BackDerefUnknown
                    | BackDerefBytes(number bytes, string reason) unique
                    | BackDerefAssumed(number bytes, string reason) unique
    BackTrap = BackMayTrap
             | BackNonTrapping(string reason) unique
             | BackChecked(string reason) unique
    BackMotion = BackMayNotMove
               | BackCanMove(string reason) unique
    BackAccessMode = BackAccessRead | BackAccessWrite | BackAccessReadWrite
    BackMemoryInfo = (Moon2Back.BackAccessId access, Moon2Back.BackAlignment alignment, Moon2Back.BackDereference dereference, Moon2Back.BackTrap trap, Moon2Back.BackMotion motion, Moon2Back.BackAccessMode mode) unique
    BackAliasFact = BackAliasUnknown(Moon2Back.BackAccessId a, Moon2Back.BackAccessId b, string reason) unique
                  | BackMayAlias(Moon2Back.BackAccessId a, Moon2Back.BackAccessId b, string reason) unique
                  | BackNoAlias(Moon2Back.BackAccessId a, Moon2Back.BackAccessId b, string reason) unique
                  | BackSameBaseSameIndexSafe(Moon2Back.BackAccessId a, Moon2Back.BackAccessId b, string reason) unique
                  | BackAliasScope(Moon2Back.BackAccessId access, Moon2Back.BackAliasScopeId scope) unique

    BackIntOverflow = BackIntWrap
                    | BackIntNoSignedWrap(string reason) unique
                    | BackIntNoUnsignedWrap(string reason) unique
                    | BackIntNoWrap(string reason) unique
    BackIntExact = BackIntMayLose
                 | BackIntExact(string reason) unique
    BackIntSemantics = (Moon2Back.BackIntOverflow overflow, Moon2Back.BackIntExact exact) unique
    BackIntOp = BackIntAdd | BackIntSub | BackIntMul
              | BackIntSDiv | BackIntUDiv
              | BackIntSRem | BackIntURem
    BackBitOp = BackBitAnd | BackBitOr | BackBitXor
    BackShiftOp = BackShiftLeft | BackShiftLogicalRight | BackShiftArithmeticRight
    BackRotateOp = BackRotateLeft | BackRotateRight
    BackFloatSemantics = BackFloatStrict
                       | BackFloatReassoc(string reason) unique
                       | BackFloatFastMath(string reason) unique
    BackFloatOp = BackFloatAdd | BackFloatSub | BackFloatMul | BackFloatDiv

    BackLiteral = BackLitInt(string raw) unique
                | BackLitFloat(string raw) unique
                | BackLitBool(boolean value) unique
                | BackLitNull

    BackUnaryOp = BackUnaryIneg
                | BackUnaryFneg
                | BackUnaryBnot
                | BackUnaryBoolNot
    BackIntrinsicOp = BackIntrinsicPopcount
                    | BackIntrinsicClz
                    | BackIntrinsicCtz
                    | BackIntrinsicBswap
                    | BackIntrinsicSqrt
                    | BackIntrinsicAbs
                    | BackIntrinsicFloor
                    | BackIntrinsicCeil
                    | BackIntrinsicTruncFloat
                    | BackIntrinsicRound
    BackCompareOp = BackIcmpEq | BackIcmpNe
                  | BackSIcmpLt | BackSIcmpLe | BackSIcmpGt | BackSIcmpGe
                  | BackUIcmpLt | BackUIcmpLe | BackUIcmpGt | BackUIcmpGe
                  | BackFCmpEq | BackFCmpNe | BackFCmpLt | BackFCmpLe | BackFCmpGt | BackFCmpGe
    BackVecCompareOp = BackVecIcmpEq | BackVecIcmpNe
                     | BackVecSIcmpLt | BackVecSIcmpLe | BackVecSIcmpGt | BackVecSIcmpGe
                     | BackVecUIcmpLt | BackVecUIcmpLe | BackVecUIcmpGt | BackVecUIcmpGe
    BackVecBinaryOp = BackVecIntAdd | BackVecIntSub | BackVecIntMul
                    | BackVecBitAnd | BackVecBitOr | BackVecBitXor
    BackVecMaskOp = BackVecMaskNot | BackVecMaskAnd | BackVecMaskOr
    BackCastOp = BackBitcast
               | BackIreduce
               | BackSextend
               | BackUextend
               | BackFpromote
               | BackFdemote
               | BackSToF
               | BackUToF
               | BackFToS
               | BackFToU

    BackCallTarget = BackCallDirect(Moon2Back.BackFuncId func) unique
                   | BackCallExtern(Moon2Back.BackExternId func) unique
                   | BackCallIndirect(Moon2Back.BackValId callee) unique
    BackCallResult = BackCallStmt
                   | BackCallValue(Moon2Back.BackValId dst, Moon2Back.BackScalar ty) unique

    Cmd = CmdTargetModel(Moon2Back.BackTargetModel target) unique
        | CmdCreateSig(Moon2Back.BackSigId sig, Moon2Back.BackScalar* params, Moon2Back.BackScalar* results) unique
        | CmdDeclareData(Moon2Back.BackDataId data, number size, number align) unique
        | CmdDataInitZero(Moon2Back.BackDataId data, number offset, number size) unique
        | CmdDataInit(Moon2Back.BackDataId data, number offset, Moon2Back.BackScalar ty, Moon2Back.BackLiteral value) unique
        | CmdDataAddr(Moon2Back.BackValId dst, Moon2Back.BackDataId data) unique
        | CmdFuncAddr(Moon2Back.BackValId dst, Moon2Back.BackFuncId func) unique
        | CmdExternAddr(Moon2Back.BackValId dst, Moon2Back.BackExternId func) unique
        | CmdDeclareFunc(Moon2Core.Visibility visibility, Moon2Back.BackFuncId func, Moon2Back.BackSigId sig) unique
        | CmdDeclareExtern(Moon2Back.BackExternId func, string symbol, Moon2Back.BackSigId sig) unique
        | CmdBeginFunc(Moon2Back.BackFuncId func) unique
        | CmdCreateBlock(Moon2Back.BackBlockId block) unique
        | CmdSwitchToBlock(Moon2Back.BackBlockId block) unique
        | CmdSealBlock(Moon2Back.BackBlockId block) unique
        | CmdBindEntryParams(Moon2Back.BackBlockId block, Moon2Back.BackValId* values) unique
        | CmdAppendBlockParam(Moon2Back.BackBlockId block, Moon2Back.BackValId value, Moon2Back.BackShape ty) unique
        | CmdCreateStackSlot(Moon2Back.BackStackSlotId slot, number size, number align) unique
        | CmdAlias(Moon2Back.BackValId dst, Moon2Back.BackValId src) unique
        | CmdStackAddr(Moon2Back.BackValId dst, Moon2Back.BackStackSlotId slot) unique
        | CmdConst(Moon2Back.BackValId dst, Moon2Back.BackScalar ty, Moon2Back.BackLiteral value) unique
        | CmdUnary(Moon2Back.BackValId dst, Moon2Back.BackUnaryOp op, Moon2Back.BackShape ty, Moon2Back.BackValId value) unique
        | CmdIntrinsic(Moon2Back.BackValId dst, Moon2Back.BackIntrinsicOp op, Moon2Back.BackShape ty, Moon2Back.BackValId* args) unique
        | CmdCompare(Moon2Back.BackValId dst, Moon2Back.BackCompareOp op, Moon2Back.BackShape ty, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdCast(Moon2Back.BackValId dst, Moon2Back.BackCastOp op, Moon2Back.BackScalar ty, Moon2Back.BackValId value) unique
        | CmdPtrOffset(Moon2Back.BackValId dst, Moon2Back.BackAddressBase base, Moon2Back.BackValId index, number elem_size, number const_offset, Moon2Back.BackPointerProvenance provenance, Moon2Back.BackPointerBounds bounds) unique
        | CmdLoadInfo(Moon2Back.BackValId dst, Moon2Back.BackShape ty, Moon2Back.BackAddress addr, Moon2Back.BackMemoryInfo memory) unique
        | CmdStoreInfo(Moon2Back.BackShape ty, Moon2Back.BackAddress addr, Moon2Back.BackValId value, Moon2Back.BackMemoryInfo memory) unique
        | CmdIntBinary(Moon2Back.BackValId dst, Moon2Back.BackIntOp op, Moon2Back.BackScalar scalar, Moon2Back.BackIntSemantics semantics, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdBitBinary(Moon2Back.BackValId dst, Moon2Back.BackBitOp op, Moon2Back.BackScalar scalar, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdBitNot(Moon2Back.BackValId dst, Moon2Back.BackScalar scalar, Moon2Back.BackValId value) unique
        | CmdShift(Moon2Back.BackValId dst, Moon2Back.BackShiftOp op, Moon2Back.BackScalar scalar, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdRotate(Moon2Back.BackValId dst, Moon2Back.BackRotateOp op, Moon2Back.BackScalar scalar, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdFloatBinary(Moon2Back.BackValId dst, Moon2Back.BackFloatOp op, Moon2Back.BackScalar scalar, Moon2Back.BackFloatSemantics semantics, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdAliasFact(Moon2Back.BackAliasFact fact) unique
        | CmdMemcpy(Moon2Back.BackValId dst, Moon2Back.BackValId src, Moon2Back.BackValId len) unique
        | CmdMemset(Moon2Back.BackValId dst, Moon2Back.BackValId byte, Moon2Back.BackValId len) unique
        | CmdSelect(Moon2Back.BackValId dst, Moon2Back.BackShape ty, Moon2Back.BackValId cond, Moon2Back.BackValId then_value, Moon2Back.BackValId else_value) unique
        | CmdFma(Moon2Back.BackValId dst, Moon2Back.BackScalar ty, Moon2Back.BackFloatSemantics semantics, Moon2Back.BackValId a, Moon2Back.BackValId b, Moon2Back.BackValId c) unique
        | CmdVecSplat(Moon2Back.BackValId dst, Moon2Back.BackVec ty, Moon2Back.BackValId value) unique
        | CmdVecBinary(Moon2Back.BackValId dst, Moon2Back.BackVecBinaryOp op, Moon2Back.BackVec ty, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdVecCompare(Moon2Back.BackValId dst, Moon2Back.BackVecCompareOp op, Moon2Back.BackVec ty, Moon2Back.BackValId lhs, Moon2Back.BackValId rhs) unique
        | CmdVecSelect(Moon2Back.BackValId dst, Moon2Back.BackVec ty, Moon2Back.BackValId mask, Moon2Back.BackValId then_value, Moon2Back.BackValId else_value) unique
        | CmdVecMask(Moon2Back.BackValId dst, Moon2Back.BackVecMaskOp op, Moon2Back.BackVec ty, Moon2Back.BackValId* args) unique
        | CmdVecInsertLane(Moon2Back.BackValId dst, Moon2Back.BackVec ty, Moon2Back.BackValId value, Moon2Back.BackValId lane_value, number lane) unique
        | CmdVecExtractLane(Moon2Back.BackValId dst, Moon2Back.BackScalar ty, Moon2Back.BackValId value, number lane) unique
        | CmdCall(Moon2Back.BackCallResult result, Moon2Back.BackCallTarget target, Moon2Back.BackSigId sig, Moon2Back.BackValId* args) unique
        | CmdJump(Moon2Back.BackBlockId dest, Moon2Back.BackValId* args) unique
        | CmdBrIf(Moon2Back.BackValId cond, Moon2Back.BackBlockId then_block, Moon2Back.BackValId* then_args, Moon2Back.BackBlockId else_block, Moon2Back.BackValId* else_args) unique
        | CmdSwitchInt(Moon2Back.BackValId value, Moon2Back.BackScalar ty, Moon2Back.BackSwitchCase* cases, Moon2Back.BackBlockId default_dest) unique
        | CmdReturnVoid
        | CmdReturnValue(Moon2Back.BackValId value) unique
        | CmdTrap
        | CmdFinishFunc(Moon2Back.BackFuncId func) unique
        | CmdFinalizeModule

    BackShapeRequirement = BackShapeRequiresScalar
                         | BackShapeRequiresVector
                         | BackShapeAllowsScalarOrVector

    BackProgramFact = BackFactCreateSig(number index, Moon2Back.BackSigId sig) unique
                    | BackFactSigRef(number index, Moon2Back.BackSigId sig) unique
                    | BackFactDeclareData(number index, Moon2Back.BackDataId data) unique
                    | BackFactDataRef(number index, Moon2Back.BackDataId data) unique
                    | BackFactDeclareFunc(number index, Moon2Back.BackFuncId func) unique
                    | BackFactFuncRef(number index, Moon2Back.BackFuncId func) unique
                    | BackFactDeclareExtern(number index, Moon2Back.BackExternId func) unique
                    | BackFactExternRef(number index, Moon2Back.BackExternId func) unique
                    | BackFactBeginFunc(number index, Moon2Back.BackFuncId func) unique
                    | BackFactFinishFunc(number index, Moon2Back.BackFuncId func) unique
                    | BackFactFinalizeModule(number index) unique
                    | BackFactCreateBlock(number index, Moon2Back.BackBlockId block) unique
                    | BackFactBlockRef(number index, Moon2Back.BackBlockId block) unique
                    | BackFactStackSlotDef(number index, Moon2Back.BackStackSlotId slot) unique
                    | BackFactStackSlotRef(number index, Moon2Back.BackStackSlotId slot) unique
                    | BackFactValueDef(number index, Moon2Back.BackValId value) unique
                    | BackFactValueUse(number index, Moon2Back.BackValId value) unique
                    | BackFactAccessDef(number index, Moon2Back.BackAccessId access) unique
                    | BackFactAccessRef(number index, Moon2Back.BackAccessId access) unique
                    | BackFactAliasAccessRef(number index, Moon2Back.BackAccessId access) unique
                    | BackFactShapeUse(number index, Moon2Back.BackShape shape, Moon2Back.BackShapeRequirement requirement) unique
                    | BackFactFunctionBodyCommand(number index) unique

    BackValidationIssue = BackIssueEmptyProgram
                        | BackIssueMissingFinalize
                        | BackIssueCommandAfterFinalize(number index) unique
                        | BackIssueCommandOutsideFunction(number index) unique
                        | BackIssueNestedFunction(number index, Moon2Back.BackFuncId active, Moon2Back.BackFuncId next) unique
                        | BackIssueFinishWithoutBegin(number index, Moon2Back.BackFuncId func) unique
                        | BackIssueFinishWrongFunction(number index, Moon2Back.BackFuncId expected, Moon2Back.BackFuncId actual) unique
                        | BackIssueUnfinishedFunction(Moon2Back.BackFuncId func) unique
                        | BackIssueDuplicateSig(number index, Moon2Back.BackSigId sig) unique
                        | BackIssueDuplicateData(number index, Moon2Back.BackDataId data) unique
                        | BackIssueDuplicateFunc(number index, Moon2Back.BackFuncId func) unique
                        | BackIssueDuplicateExtern(number index, Moon2Back.BackExternId func) unique
                        | BackIssueDuplicateBlock(number index, Moon2Back.BackBlockId block) unique
                        | BackIssueDuplicateStackSlot(number index, Moon2Back.BackStackSlotId slot) unique
                        | BackIssueDuplicateValue(number index, Moon2Back.BackValId value) unique
                        | BackIssueMissingSig(number index, Moon2Back.BackSigId sig) unique
                        | BackIssueMissingData(number index, Moon2Back.BackDataId data) unique
                        | BackIssueMissingFunc(number index, Moon2Back.BackFuncId func) unique
                        | BackIssueMissingExtern(number index, Moon2Back.BackExternId func) unique
                        | BackIssueMissingBlock(number index, Moon2Back.BackBlockId block) unique
                        | BackIssueMissingStackSlot(number index, Moon2Back.BackStackSlotId slot) unique
                        | BackIssueMissingValue(number index, Moon2Back.BackValId value) unique
                        | BackIssueDuplicateAccess(number index, Moon2Back.BackAccessId access) unique
                        | BackIssueMissingAccess(number index, Moon2Back.BackAccessId access) unique
                        | BackIssueInvalidAlignment(number index, number bytes) unique
                        | BackIssueLoadAccessMode(number index, Moon2Back.BackAccessMode mode) unique
                        | BackIssueStoreAccessMode(number index, Moon2Back.BackAccessMode mode) unique
                        | BackIssueDereferenceTooSmall(number index, number dereference_bytes, number access_bytes) unique
                        | BackIssueTargetUnsupportedShape(number index, Moon2Back.BackShape shape) unique
                        | BackIssueIntScalarExpected(number index, Moon2Back.BackScalar scalar) unique
                        | BackIssueFloatScalarExpected(number index, Moon2Back.BackScalar scalar) unique
                        | BackIssueBitScalarExpected(number index, Moon2Back.BackScalar scalar) unique
                        | BackIssueShiftScalarExpected(number index, Moon2Back.BackScalar scalar) unique
                        | BackIssueNonTrappingWithoutDereference(number index) unique
                        | BackIssueCanMoveWithoutNonTrapping(number index) unique
                        | BackIssueShapeRequiresScalar(number index, Moon2Back.BackShape shape) unique
                        | BackIssueShapeRequiresVector(number index, Moon2Back.BackShape shape) unique
    BackValidationReport = (Moon2Back.BackValidationIssue* issues) unique

    BackCommandCount = (string command_kind, number count) unique
    BackMemoryInspection = (number index, Moon2Back.BackAccessId access, Moon2Back.BackAlignment alignment, Moon2Back.BackDereference dereference, Moon2Back.BackTrap trap, Moon2Back.BackMotion motion, Moon2Back.BackAccessMode mode) unique
    BackAddressInspection = (number index, Moon2Back.BackAddress address) unique
    BackPointerOffsetInspection = (number index, Moon2Back.BackValId dst, Moon2Back.BackAddressBase base, Moon2Back.BackValId index_value, number elem_size, number const_offset, Moon2Back.BackPointerProvenance provenance, Moon2Back.BackPointerBounds bounds) unique
    BackAliasInspection = (number index, Moon2Back.BackAliasFact fact) unique
    BackIntSemanticsInspection = (number index, Moon2Back.BackValId dst, Moon2Back.BackIntOp op, Moon2Back.BackScalar scalar, Moon2Back.BackIntSemantics semantics) unique
    BackFloatSemanticOp = BackFloatSemanticBinary(Moon2Back.BackFloatOp op) unique
                        | BackFloatSemanticFma
    BackFloatSemanticsInspection = (number index, Moon2Back.BackValId dst, Moon2Back.BackFloatSemanticOp op, Moon2Back.BackScalar scalar, Moon2Back.BackFloatSemantics semantics) unique
    BackInspectionReport = (Moon2Back.BackCommandCount* command_counts, Moon2Back.BackTargetModel* targets, Moon2Back.BackMemoryInspection* memory, Moon2Back.BackAddressInspection* addresses, Moon2Back.BackPointerOffsetInspection* pointer_offsets, Moon2Back.BackAliasInspection* aliases, Moon2Back.BackIntSemanticsInspection* int_semantics, Moon2Back.BackFloatSemanticsInspection* float_semantics) unique
    BackDisasmInspection = (Moon2Back.BackFuncId func, string text) unique
    BackDiagnosticsReport = (Moon2Back.BackInspectionReport inspection, Moon2Vec.VecInspectionReport vector, Moon2Back.BackDisasmInspection* disassembly) unique

    BackFlow = BackFallsThrough | BackTerminates
    BackSigSpec = (Moon2Back.BackScalar* params, Moon2Back.BackScalar* results) unique
    BackStackSlotSpec = (number size, number align) unique
    BackExprLowering = BackExprPlan(Moon2Back.Cmd* cmds, Moon2Back.BackValId value, Moon2Back.BackScalar ty) unique
                     | BackExprTerminated(Moon2Back.Cmd* cmds) unique
    BackAddrLowering = BackAddrWrites(Moon2Back.Cmd* cmds) unique
                     | BackAddrTerminated(Moon2Back.Cmd* cmds) unique
    BackViewLowering = BackViewPlan(Moon2Back.Cmd* cmds, Moon2Back.BackValId data, Moon2Back.BackValId len, Moon2Back.BackValId stride) unique
                     | BackViewTerminated(Moon2Back.Cmd* cmds) unique
    BackReturnTarget = BackReturnValue
                     | BackReturnSret(Moon2Back.BackValId addr) unique
    BackStmtPlan = (Moon2Back.Cmd* cmds, Moon2Back.BackFlow flow) unique
    BackFuncPlan = (Moon2Back.Cmd* cmds) unique
    BackItemPlan = (Moon2Back.Cmd* cmds) unique
    BackProgram = (Moon2Back.Cmd* cmds) unique
    BackCommandTape = (number version, number command_count, string payload) unique
}

module Moon2Type {
    TypeRef = TypeRefPath(Moon2Core.Path path) unique
            | TypeRefGlobal(string module_name, string type_name) unique
            | TypeRefLocal(Moon2Core.TypeSym sym) unique
            | TypeRefSlot(Moon2Open.TypeSlot slot) unique

    ArrayLen = ArrayLenExpr(Moon2Tree.Expr expr) unique
             | ArrayLenConst(number count) unique
             | ArrayLenSlot(Moon2Open.ExprSlot slot) unique

    Type = TScalar(Moon2Core.Scalar scalar) unique
         | TPtr(Moon2Type.Type elem) unique
         | TArray(Moon2Type.ArrayLen count, Moon2Type.Type elem) unique
         | TSlice(Moon2Type.Type elem) unique
         | TView(Moon2Type.Type elem) unique
         | TFunc(Moon2Type.Type* params, Moon2Type.Type result) unique
         | TClosure(Moon2Type.Type* params, Moon2Type.Type result) unique
         | TNamed(Moon2Type.TypeRef ref) unique
         | TSlot(Moon2Open.TypeSlot slot) unique

    TypeClass = TypeClassScalar(Moon2Core.Scalar scalar) unique
              | TypeClassPointer(Moon2Type.Type elem) unique
              | TypeClassArray(Moon2Type.Type elem, number count) unique
              | TypeClassSlice(Moon2Type.Type elem) unique
              | TypeClassView(Moon2Type.Type elem) unique
              | TypeClassCallable(Moon2Type.Type* params, Moon2Type.Type result) unique
              | TypeClassClosure(Moon2Type.Type* params, Moon2Type.Type result) unique
              | TypeClassAggregate(string module_name, string type_name) unique
              | TypeClassUnknown

    TypeBackScalarResult = TypeBackScalarKnown(Moon2Back.BackScalar scalar) unique
                         | TypeBackScalarUnavailable(Moon2Type.Type ty, Moon2Type.TypeClass class) unique
    TypeMemLayoutResult = TypeMemLayoutKnown(Moon2Sem.MemLayout layout) unique
                        | TypeMemLayoutUnknown(Moon2Type.Type ty, Moon2Type.TypeClass class) unique
    AbiClass = AbiIgnore
             | AbiDirect(Moon2Back.BackScalar scalar) unique
             | AbiIndirect(Moon2Sem.MemLayout layout) unique
             | AbiDescriptor(Moon2Sem.MemLayout layout) unique
             | AbiUnknown(Moon2Type.TypeClass class) unique
    AbiDecision = (Moon2Type.Type ty, Moon2Type.AbiClass class) unique
    AbiParamPlan = AbiParamScalar(string name, Moon2Bind.Binding binding, Moon2Back.BackScalar scalar, Moon2Back.BackValId value) unique
                 | AbiParamView(string name, Moon2Bind.Binding binding, Moon2Back.BackValId data, Moon2Back.BackValId len, Moon2Back.BackValId stride) unique
                 | AbiParamRejected(string name, Moon2Type.Type ty, string reason) unique
    AbiResultPlan = AbiResultVoid
                  | AbiResultScalar(Moon2Back.BackScalar scalar) unique
                  | AbiResultView(Moon2Type.Type elem, Moon2Back.BackValId out) unique
                  | AbiResultRejected(Moon2Type.Type ty, string reason) unique
    FuncAbiPlan = (string func_name, Moon2Type.AbiParamPlan* params, Moon2Type.AbiResultPlan result) unique

    Param = (string name, Moon2Type.Type ty) unique
    FieldDecl = (string field_name, Moon2Type.Type ty) unique
    VariantDecl = (string name, Moon2Type.Type payload) unique
}

module Moon2Open {
    TypeSlot = (string key, string pretty_name) unique
    ValueSlot = (string key, string pretty_name, Moon2Type.Type ty) unique
    ExprSlot = (string key, string pretty_name, Moon2Type.Type ty) unique
    PlaceSlot = (string key, string pretty_name, Moon2Type.Type ty) unique
    DomainSlot = (string key, string pretty_name) unique
    RegionSlot = (string key, string pretty_name) unique
    ContSlot = (string key, string pretty_name, Moon2Tree.BlockParam* params) unique
    FuncSlot = (string key, string pretty_name, Moon2Type.Type fn_ty) unique
    ConstSlot = (string key, string pretty_name, Moon2Type.Type ty) unique
    StaticSlot = (string key, string pretty_name, Moon2Type.Type ty) unique
    TypeDeclSlot = (string key, string pretty_name) unique
    ItemsSlot = (string key, string pretty_name) unique
    ModuleSlot = (string key, string pretty_name) unique

    Slot = SlotType(Moon2Open.TypeSlot slot) unique
         | SlotValue(Moon2Open.ValueSlot slot) unique
         | SlotExpr(Moon2Open.ExprSlot slot) unique
         | SlotPlace(Moon2Open.PlaceSlot slot) unique
         | SlotDomain(Moon2Open.DomainSlot slot) unique
         | SlotRegion(Moon2Open.RegionSlot slot) unique
         | SlotCont(Moon2Open.ContSlot slot) unique
         | SlotFunc(Moon2Open.FuncSlot slot) unique
         | SlotConst(Moon2Open.ConstSlot slot) unique
         | SlotStatic(Moon2Open.StaticSlot slot) unique
         | SlotTypeDecl(Moon2Open.TypeDeclSlot slot) unique
         | SlotItems(Moon2Open.ItemsSlot slot) unique
         | SlotModule(Moon2Open.ModuleSlot slot) unique

    ModuleNameFacet = ModuleNameOpen | ModuleNameFixed(string module_name) unique

    OpenParam = (string key, string name, Moon2Type.Type ty) unique
    ValueImport = ImportValue(string key, string name, Moon2Type.Type ty) unique
                | ImportGlobalFunc(string key, string module_name, string item_name, Moon2Type.Type ty) unique
                | ImportGlobalConst(string key, string module_name, string item_name, Moon2Type.Type ty) unique
                | ImportGlobalStatic(string key, string module_name, string item_name, Moon2Type.Type ty) unique
                | ImportExtern(string key, string symbol, Moon2Type.Type ty) unique
    TypeImport = (string key, string local_name, Moon2Type.Type ty) unique

    OpenSet = (Moon2Open.ValueImport* value_imports, Moon2Open.TypeImport* type_imports, Moon2Sem.TypeLayout* layouts, Moon2Open.Slot* slots) unique

    SourceBinding = SourceParamBinding(Moon2Open.OpenParam param) unique
                  | SourceValueImportBinding(Moon2Open.ValueImport import) unique
                  | SourceExprSlotBinding(Moon2Open.ExprSlot slot) unique
                  | SourceFuncSlotBinding(Moon2Open.FuncSlot slot) unique
                  | SourceConstSlotBinding(Moon2Open.ConstSlot slot) unique
                  | SourceStaticSlotBinding(Moon2Open.StaticSlot slot) unique
    SourceBindingEntry = (Moon2Bind.Binding binding, Moon2Open.SourceBinding source) unique
    SourceTypeEntry = (Moon2Type.Type ty, Moon2Type.Type meta_ty) unique
    SourceEnv = (string module_name, Moon2Open.SourceBindingEntry* bindings, Moon2Open.SourceTypeEntry* types) unique
    ParamBinding = (Moon2Open.OpenParam param, Moon2Tree.Expr value) unique
    FillSet = (Moon2Open.SlotBinding* bindings) unique
    ExpandEnv = (Moon2Open.FillSet fills, Moon2Open.ParamBinding* params, string rebase_prefix) unique
    SealParamEntry = (Moon2Open.OpenParam param, number index) unique
    SealEnv = (string module_name, Moon2Open.SealParamEntry* params) unique

    ExprFrag = (Moon2Open.OpenParam* params, Moon2Open.OpenSet open, Moon2Tree.Expr body, Moon2Type.Type result) unique
    RegionFrag = (Moon2Open.OpenParam* params, Moon2Open.OpenSet open, Moon2Tree.EntryControlBlock entry, Moon2Tree.ControlBlock* blocks) unique

    SlotValue = SlotValueType(Moon2Type.Type ty) unique
              | SlotValueExpr(Moon2Tree.Expr expr) unique
              | SlotValuePlace(Moon2Tree.Place place) unique
              | SlotValueDomain(Moon2Tree.Domain domain) unique
              | SlotValueRegion(Moon2Tree.Stmt* body) unique
              | SlotValueCont(Moon2Tree.BlockLabel label) unique
              | SlotValueContSlot(Moon2Open.ContSlot slot) unique
              | SlotValueFunc(Moon2Tree.Func func) unique
              | SlotValueConst(Moon2Tree.ConstItem c) unique
              | SlotValueStatic(Moon2Tree.StaticItem s) unique
              | SlotValueTypeDecl(Moon2Tree.TypeDecl t) unique
              | SlotValueItems(Moon2Tree.Item* items) unique
              | SlotValueModule(Moon2Tree.Module module) unique
    SlotBinding = (Moon2Open.Slot slot, Moon2Open.SlotValue value) unique

    RewriteRule = RewriteType(Moon2Type.Type from, Moon2Type.Type to) unique
                | RewriteBinding(Moon2Bind.Binding from, Moon2Bind.Binding to) unique
                | RewritePlace(Moon2Tree.Place from, Moon2Tree.Place to) unique
                | RewriteDomain(Moon2Tree.Domain from, Moon2Tree.Domain to) unique
                | RewriteExpr(Moon2Tree.Expr from, Moon2Tree.Expr to) unique
                | RewriteStmt(Moon2Tree.Stmt from, Moon2Tree.Stmt* to) unique
                | RewriteItem(Moon2Tree.Item from, Moon2Tree.Item* to) unique
    RewriteSet = (Moon2Open.RewriteRule* rules) unique

    MetaFact = MetaFactSlot(Moon2Open.Slot slot) unique
             | MetaFactParamUse(Moon2Open.OpenParam param) unique
             | MetaFactValueImportUse(Moon2Open.ValueImport import) unique
             | MetaFactLocalValue(string id, string name) unique
             | MetaFactLocalCell(string id, string name) unique
             | MetaFactBlockParam(string region_id, string block_name, number index, string name) unique
             | MetaFactEntryBlockParam(string region_id, string block_name, number index, string name) unique
             | MetaFactGlobalFunc(string module_name, string item_name) unique
             | MetaFactGlobalConst(string module_name, string item_name) unique
             | MetaFactGlobalStatic(string module_name, string item_name) unique
             | MetaFactExtern(string symbol) unique
             | MetaFactExprFragUse(string use_id) unique
             | MetaFactRegionFragUse(string use_id) unique
             | MetaFactModuleUse(string use_id) unique
             | MetaFactModuleSlotUse(string use_id, Moon2Open.ModuleSlot slot) unique
             | MetaFactOpenModuleName
             | MetaFactLocalType(Moon2Core.TypeSym sym) unique
    MetaFactSet = (Moon2Open.MetaFact* facts) unique

    ValidationIssue = IssueOpenSlot(Moon2Open.Slot slot) unique
                    | IssueUnfilledTypeSlot(Moon2Open.TypeSlot slot) unique
                    | IssueUnfilledExprSlot(Moon2Open.ExprSlot slot) unique
                    | IssueUnfilledPlaceSlot(Moon2Open.PlaceSlot slot) unique
                    | IssueUnfilledDomainSlot(Moon2Open.DomainSlot slot) unique
                    | IssueUnfilledRegionSlot(Moon2Open.RegionSlot slot) unique
                    | IssueUnfilledContSlot(Moon2Open.ContSlot slot) unique
                    | IssueUnfilledFuncSlot(Moon2Open.FuncSlot slot) unique
                    | IssueUnfilledConstSlot(Moon2Open.ConstSlot slot) unique
                    | IssueUnfilledStaticSlot(Moon2Open.StaticSlot slot) unique
                    | IssueUnfilledTypeDeclSlot(Moon2Open.TypeDeclSlot slot) unique
                    | IssueUnfilledItemsSlot(Moon2Open.ItemsSlot slot) unique
                    | IssueUnfilledModuleSlot(Moon2Open.ModuleSlot slot) unique
                    | IssueUnexpandedExprFragUse(string use_id) unique
                    | IssueUnexpandedRegionFragUse(string use_id) unique
                    | IssueUnexpandedModuleUse(string use_id) unique
                    | IssueOpenModuleName
                    | IssueGenericValueImport(Moon2Open.ValueImport import) unique
    ValidationReport = (Moon2Open.ValidationIssue* issues) unique
}

module Moon2Bind {
    BindingClass = BindingClassLocalValue
                 | BindingClassLocalCell
                 | BindingClassArg(number index) unique
                 | BindingClassBlockParam(string region_id, string block_name, number index) unique
                 | BindingClassEntryBlockParam(string region_id, string block_name, number index) unique
                 | BindingClassContParam(string region_id, string cont_name, number index) unique
                 | BindingClassGlobalFunc(string module_name, string item_name) unique
                 | BindingClassGlobalConst(string module_name, string item_name) unique
                 | BindingClassGlobalStatic(string module_name, string item_name) unique
                 | BindingClassExtern(string symbol) unique
                 | BindingClassOpenParam(Moon2Open.OpenParam param) unique
                 | BindingClassImport(Moon2Open.ValueImport import) unique
                 | BindingClassFuncSym(Moon2Core.FuncSym sym) unique
                 | BindingClassExternSym(Moon2Core.ExternSym sym) unique
                 | BindingClassConstSym(Moon2Core.ConstSym sym) unique
                 | BindingClassStaticSym(Moon2Core.StaticSym sym) unique
                 | BindingClassFuncSlot(Moon2Open.FuncSlot slot) unique
                 | BindingClassConstSlot(Moon2Open.ConstSlot slot) unique
                 | BindingClassStaticSlot(Moon2Open.StaticSlot slot) unique
                 | BindingClassValueSlot(Moon2Open.ValueSlot slot) unique

    Binding = (Moon2Core.Id id, string name, Moon2Type.Type ty, Moon2Bind.BindingClass class) unique

    Residence = ResidenceUnknown | ResidenceValue | ResidenceStack | ResidenceCell
    ResidenceReason = ResidenceBecauseDefault
                    | ResidenceBecauseAddressTaken
                    | ResidenceBecauseMutableCell
                    | ResidenceBecauseNonScalarAbi
                    | ResidenceBecauseMaterializedTemporary
                    | ResidenceBecauseBackendRequired
    ResidenceFact = ResidenceFactBinding(Moon2Bind.Binding binding) unique
                  | ResidenceFactAddressTaken(Moon2Bind.Binding binding) unique
                  | ResidenceFactMutableCell(Moon2Bind.Binding binding) unique
                  | ResidenceFactNonScalarAbi(Moon2Bind.Binding binding) unique
                  | ResidenceFactMaterializedTemporary(Moon2Bind.Binding binding) unique
                  | ResidenceFactBackendRequired(Moon2Bind.Binding binding) unique
    ResidenceFactSet = (Moon2Bind.ResidenceFact* facts) unique
    ResidenceDecision = (Moon2Bind.Binding binding, Moon2Bind.Residence residence, Moon2Bind.ResidenceReason reason) unique
    ResidencePlan = (Moon2Bind.ResidenceDecision* decisions) unique
    MachineBinding = (Moon2Bind.Binding binding, Moon2Bind.Residence residence) unique
    MachineBindingSet = (Moon2Bind.MachineBinding* bindings) unique

    ValueRef = ValueRefName(string name) unique
             | ValueRefPath(Moon2Core.Path path) unique
             | ValueRefBinding(Moon2Bind.Binding binding) unique
             | ValueRefSlot(Moon2Open.ValueSlot slot) unique
             | ValueRefFuncSlot(Moon2Open.FuncSlot slot) unique
             | ValueRefConstSlot(Moon2Open.ConstSlot slot) unique
             | ValueRefStaticSlot(Moon2Open.StaticSlot slot) unique

    ValueEntry = (string name, Moon2Bind.Binding binding) unique
    TypeEntry = (string name, Moon2Type.Type ty) unique
    Env = (string module_name, Moon2Bind.ValueEntry* values, Moon2Bind.TypeEntry* types, Moon2Sem.TypeLayout* layouts) unique
    ConstEntry = (string module_name, string item_name, Moon2Type.Type ty, Moon2Tree.Expr value) unique
    ConstEnv = (Moon2Bind.ConstEntry* entries) unique

    StmtEnvEffect = StmtEnvNoBinding
                  | StmtEnvAddBinding(Moon2Bind.ValueEntry entry) unique
                  | StmtEnvAddBindings(Moon2Bind.ValueEntry* entries) unique
}

module Moon2Sem {
    FieldRef = FieldByName(string field_name, Moon2Type.Type ty) unique
             | FieldByOffset(string field_name, number offset, Moon2Type.Type ty, Moon2Host.HostFieldRep storage) unique
    FieldLayout = (string field_name, number offset, Moon2Type.Type ty) unique
    MemLayout = (number size, number align) unique
    TypeLayout = LayoutNamed(string module_name, string type_name, Moon2Sem.FieldLayout* fields, number size, number align) unique
               | LayoutLocal(Moon2Core.TypeSym sym, Moon2Sem.FieldLayout* fields, number size, number align) unique
    LayoutEnv = (Moon2Sem.TypeLayout* layouts) unique

    ConstFieldValue = (string name, Moon2Sem.ConstValue value) unique
    ConstValue = ConstInt(Moon2Type.Type ty, string raw) unique
               | ConstFloat(Moon2Type.Type ty, string raw) unique
               | ConstBool(boolean value) unique
               | ConstNil(Moon2Type.Type ty) unique
               | ConstAgg(Moon2Type.Type ty, Moon2Sem.ConstFieldValue* fields) unique
               | ConstArray(Moon2Type.Type elem_ty, Moon2Sem.ConstValue* elems) unique
    ConstLocalEntry = (Moon2Bind.Binding binding, Moon2Sem.ConstValue value) unique
    ConstLocalEnv = (Moon2Sem.ConstLocalEntry* entries) unique
    ConstStmtResult = ConstStmtFallsThrough(Moon2Sem.ConstLocalEnv local_env) unique
                    | ConstStmtReturnVoid(Moon2Sem.ConstLocalEnv local_env) unique
                    | ConstStmtReturnValue(Moon2Sem.ConstLocalEnv local_env, Moon2Sem.ConstValue value) unique
                    | ConstStmtYieldVoid(Moon2Sem.ConstLocalEnv local_env) unique
                    | ConstStmtYieldValue(Moon2Sem.ConstLocalEnv local_env, Moon2Sem.ConstValue value) unique
                    | ConstStmtJump(Moon2Sem.ConstLocalEnv local_env, string target_label) unique

    ExprExit = ExprEndOnly | ExprEndOrYieldValue
    OperandContext = OperandNeedsExpected | OperandHasNaturalType

    ValueClass = ValueUnknown | ValuePlain | ValueAddress | ValueMaterialized | ValueTerminated
    ConstClass = ConstClassUnknown | ConstClassNo | ConstClassYes(Moon2Sem.ConstValue value) unique
    CodeShapeClass = CodeShapeUnknown | CodeShapeScalar(Moon2Core.Scalar scalar) unique | CodeShapeVector(Moon2Core.Scalar elem, number lanes) unique
    AddressClass = AddressUnknown | AddressBinding | AddressStack | AddressStatic | AddressDeref | AddressProjection | AddressIndex | AddressTemporary
    FlowClass = FlowUnknown | FlowFallsThrough | FlowJumps | FlowYields | FlowReturns | FlowTerminates

    SwitchKey = SwitchKeyExpr(Moon2Tree.Expr expr) unique
              | SwitchKeyConst(Moon2Sem.ConstValue value) unique
              | SwitchKeyRaw(string raw) unique
    SwitchKeySet = (Moon2Sem.SwitchKey* keys) unique
    SwitchDecision = SwitchDecisionConstKeys(Moon2Sem.SwitchKey* keys) unique
                   | SwitchDecisionExprKeys(Moon2Sem.SwitchKey* keys) unique
                   | SwitchDecisionCompareFallback(Moon2Sem.SwitchKey* keys, string reason) unique

    CallTarget = CallUnresolved(Moon2Tree.Expr callee) unique
               | CallDirect(string module_name, string func_name, Moon2Type.Type fn_ty) unique
               | CallExtern(string symbol, Moon2Type.Type fn_ty) unique
               | CallIndirect(Moon2Tree.Expr callee, Moon2Type.Type fn_ty) unique
               | CallClosure(Moon2Tree.Expr closure, Moon2Type.Type fn_ty) unique
}

module Moon2Tree {
    ExprHeader = ExprSurface
               | ExprTyped(Moon2Type.Type ty) unique
               | ExprOpen(Moon2Type.Type ty, Moon2Open.OpenSet open) unique
               | ExprSem(Moon2Type.Type ty, Moon2Sem.ValueClass value_class, Moon2Sem.ConstClass const_class) unique
               | ExprCode(Moon2Type.Type ty, Moon2Sem.CodeShapeClass shape) unique

    PlaceHeader = PlaceSurface
                | PlaceTyped(Moon2Type.Type ty) unique
                | PlaceOpen(Moon2Type.Type ty, Moon2Open.OpenSet open) unique
                | PlaceSem(Moon2Type.Type ty, Moon2Sem.AddressClass address_class) unique

    StmtHeader = StmtSurface
               | StmtTyped
               | StmtOpen(Moon2Open.OpenSet open) unique
               | StmtSem(Moon2Sem.FlowClass flow) unique
               | StmtCode(Moon2Sem.FlowClass flow) unique

    FieldInit = (string name, Moon2Tree.Expr value) unique
    SwitchStmtArm = (Moon2Sem.SwitchKey key, Moon2Tree.Stmt* body) unique
    SwitchExprArm = (Moon2Sem.SwitchKey key, Moon2Tree.Stmt* body, Moon2Tree.Expr result) unique

    View = ViewFromExpr(Moon2Tree.Expr base, Moon2Type.Type elem) unique
         | ViewContiguous(Moon2Tree.Expr data, Moon2Type.Type elem, Moon2Tree.Expr len) unique
         | ViewStrided(Moon2Tree.Expr data, Moon2Type.Type elem, Moon2Tree.Expr len, Moon2Tree.Expr stride) unique
         | ViewRestrided(Moon2Tree.View base, Moon2Type.Type elem, Moon2Tree.Expr stride) unique
         | ViewWindow(Moon2Tree.View base, Moon2Tree.Expr start, Moon2Tree.Expr len) unique
         | ViewRowBase(Moon2Tree.View base, Moon2Tree.Expr row_offset, Moon2Type.Type elem) unique
         | ViewInterleaved(Moon2Tree.Expr data, Moon2Type.Type elem, Moon2Tree.Expr len, Moon2Tree.Expr stride, Moon2Tree.Expr lane) unique
         | ViewInterleavedView(Moon2Tree.View base, Moon2Type.Type elem, Moon2Tree.Expr stride, Moon2Tree.Expr lane) unique

    Domain = DomainRange(Moon2Tree.Expr stop) unique
           | DomainRange2(Moon2Tree.Expr start, Moon2Tree.Expr stop) unique
           | DomainZipEqValues(Moon2Tree.Expr* values) unique
           | DomainValue(Moon2Tree.Expr value) unique
           | DomainView(Moon2Tree.View view) unique
           | DomainZipEqViews(Moon2Tree.View* views) unique
           | DomainSlotValue(Moon2Open.DomainSlot slot) unique

    IndexBase = IndexBaseExpr(Moon2Tree.Expr base) unique
              | IndexBasePlace(Moon2Tree.Place base, Moon2Type.Type elem) unique
              | IndexBaseView(Moon2Tree.View view) unique

    Place = PlaceRef(Moon2Tree.PlaceHeader h, Moon2Bind.ValueRef ref) unique
          | PlaceDeref(Moon2Tree.PlaceHeader h, Moon2Tree.Expr base) unique
          | PlaceDot(Moon2Tree.PlaceHeader h, Moon2Tree.Place base, string name) unique
          | PlaceField(Moon2Tree.PlaceHeader h, Moon2Tree.Place base, Moon2Sem.FieldRef field) unique
          | PlaceIndex(Moon2Tree.PlaceHeader h, Moon2Tree.IndexBase base, Moon2Tree.Expr index) unique
          | PlaceSlotValue(Moon2Tree.PlaceHeader h, Moon2Open.PlaceSlot slot) unique

    BlockLabel = (string name) unique
    BlockParam = (string name, Moon2Type.Type ty) unique
    EntryBlockParam = (string name, Moon2Type.Type ty, Moon2Tree.Expr init) unique
    JumpArg = (string name, Moon2Tree.Expr value) unique
    FuncContract = ContractBounds(Moon2Tree.Expr base, Moon2Tree.Expr len) unique
                 | ContractWindowBounds(Moon2Tree.Expr base, Moon2Tree.Expr base_len, Moon2Tree.Expr start, Moon2Tree.Expr len) unique
                 | ContractDisjoint(Moon2Tree.Expr a, Moon2Tree.Expr b) unique
                 | ContractSameLen(Moon2Tree.Expr a, Moon2Tree.Expr b) unique
                 | ContractNoAlias(Moon2Tree.Expr base) unique
                 | ContractReadonly(Moon2Tree.Expr base) unique
                 | ContractWriteonly(Moon2Tree.Expr base) unique
    ContractFact = ContractFactBounds(Moon2Bind.Binding base, Moon2Bind.Binding len) unique
                 | ContractFactWindowBounds(Moon2Bind.Binding base, Moon2Tree.Expr base_len, Moon2Tree.Expr start, Moon2Tree.Expr len) unique
                 | ContractFactDisjoint(Moon2Bind.Binding a, Moon2Bind.Binding b) unique
                 | ContractFactSameLen(Moon2Bind.Binding a, Moon2Bind.Binding b) unique
                 | ContractFactNoAlias(Moon2Bind.Binding base) unique
                 | ContractFactReadonly(Moon2Bind.Binding base) unique
                 | ContractFactWriteonly(Moon2Bind.Binding base) unique
                 | ContractFactRejected(Moon2Tree.TypeIssue issue) unique
    ContractFactSet = (Moon2Tree.ContractFact* facts) unique
    EntryControlBlock = (Moon2Tree.BlockLabel label, Moon2Tree.EntryBlockParam* params, Moon2Tree.Stmt* body) unique
    ControlBlock = (Moon2Tree.BlockLabel label, Moon2Tree.BlockParam* params, Moon2Tree.Stmt* body) unique
    ControlStmtRegion = (string region_id, Moon2Tree.EntryControlBlock entry, Moon2Tree.ControlBlock* blocks) unique
    ControlExprRegion = (string region_id, Moon2Type.Type result_ty, Moon2Tree.EntryControlBlock entry, Moon2Tree.ControlBlock* blocks) unique

    ControlFact = ControlFactEntryBlock(string region_id, Moon2Tree.BlockLabel label) unique
                | ControlFactBlock(string region_id, Moon2Tree.BlockLabel label) unique
                | ControlFactEntryParam(string region_id, Moon2Tree.BlockLabel label, number index, string name, Moon2Type.Type ty) unique
                | ControlFactBlockParam(string region_id, Moon2Tree.BlockLabel label, number index, string name, Moon2Type.Type ty) unique
                | ControlFactJump(string region_id, Moon2Tree.BlockLabel from_label, Moon2Tree.BlockLabel to_label) unique
                | ControlFactJumpArg(string region_id, Moon2Tree.BlockLabel from_label, Moon2Tree.BlockLabel to_label, string name, Moon2Type.Type ty) unique
                | ControlFactYieldVoid(string region_id, Moon2Tree.BlockLabel from_label) unique
                | ControlFactYieldValue(string region_id, Moon2Tree.BlockLabel from_label, Moon2Type.Type ty) unique
                | ControlFactReturn(string region_id, Moon2Tree.BlockLabel from_label) unique
                | ControlFactBackedge(string region_id, Moon2Tree.BlockLabel from_label, Moon2Tree.BlockLabel to_label) unique
    ControlFactSet = (Moon2Tree.ControlFact* facts) unique
    ControlReject = ControlRejectDuplicateLabel(string region_id, Moon2Tree.BlockLabel label) unique
                  | ControlRejectMissingLabel(string region_id, Moon2Tree.BlockLabel label) unique
                  | ControlRejectMissingJumpArg(string region_id, Moon2Tree.BlockLabel label, string name) unique
                  | ControlRejectExtraJumpArg(string region_id, Moon2Tree.BlockLabel label, string name) unique
                  | ControlRejectDuplicateJumpArg(string region_id, Moon2Tree.BlockLabel label, string name) unique
                  | ControlRejectJumpType(string region_id, Moon2Tree.BlockLabel label, string name, Moon2Type.Type expected, Moon2Type.Type actual) unique
                  | ControlRejectYieldOutsideRegion(string reason) unique
                  | ControlRejectYieldType(string region_id, Moon2Type.Type expected, Moon2Type.Type actual) unique
                  | ControlRejectUnterminatedBlock(string region_id, Moon2Tree.BlockLabel label) unique
                  | ControlRejectIrreducible(string region_id, string reason) unique
    ControlDecision = ControlDecisionReducible(string region_id, Moon2Tree.ControlFact* facts) unique
                    | ControlDecisionIrreducible(string region_id, Moon2Tree.ControlReject reject) unique

    Expr = ExprLit(Moon2Tree.ExprHeader h, Moon2Core.Literal value) unique
         | ExprRef(Moon2Tree.ExprHeader h, Moon2Bind.ValueRef ref) unique
         | ExprDot(Moon2Tree.ExprHeader h, Moon2Tree.Expr base, string name) unique
         | ExprUnary(Moon2Tree.ExprHeader h, Moon2Core.UnaryOp op, Moon2Tree.Expr value) unique
         | ExprBinary(Moon2Tree.ExprHeader h, Moon2Core.BinaryOp op, Moon2Tree.Expr lhs, Moon2Tree.Expr rhs) unique
         | ExprCompare(Moon2Tree.ExprHeader h, Moon2Core.CmpOp op, Moon2Tree.Expr lhs, Moon2Tree.Expr rhs) unique
         | ExprLogic(Moon2Tree.ExprHeader h, Moon2Core.LogicOp op, Moon2Tree.Expr lhs, Moon2Tree.Expr rhs) unique
         | ExprCast(Moon2Tree.ExprHeader h, Moon2Core.SurfaceCastOp op, Moon2Type.Type ty, Moon2Tree.Expr value) unique
         | ExprMachineCast(Moon2Tree.ExprHeader h, Moon2Core.MachineCastOp op, Moon2Type.Type ty, Moon2Tree.Expr value) unique
         | ExprIntrinsic(Moon2Tree.ExprHeader h, Moon2Core.Intrinsic op, Moon2Tree.Expr* args) unique
         | ExprAddrOf(Moon2Tree.ExprHeader h, Moon2Tree.Place place) unique
         | ExprDeref(Moon2Tree.ExprHeader h, Moon2Tree.Expr value) unique
         | ExprCall(Moon2Tree.ExprHeader h, Moon2Sem.CallTarget target, Moon2Tree.Expr* args) unique
         | ExprLen(Moon2Tree.ExprHeader h, Moon2Tree.Expr value) unique
         | ExprField(Moon2Tree.ExprHeader h, Moon2Tree.Expr base, Moon2Sem.FieldRef field) unique
         | ExprIndex(Moon2Tree.ExprHeader h, Moon2Tree.IndexBase base, Moon2Tree.Expr index) unique
         | ExprAgg(Moon2Tree.ExprHeader h, Moon2Type.Type ty, Moon2Tree.FieldInit* fields) unique
         | ExprArray(Moon2Tree.ExprHeader h, Moon2Type.Type elem_ty, Moon2Tree.Expr* elems) unique
         | ExprIf(Moon2Tree.ExprHeader h, Moon2Tree.Expr cond, Moon2Tree.Expr then_expr, Moon2Tree.Expr else_expr) unique
         | ExprSelect(Moon2Tree.ExprHeader h, Moon2Tree.Expr cond, Moon2Tree.Expr then_expr, Moon2Tree.Expr else_expr) unique
         | ExprSwitch(Moon2Tree.ExprHeader h, Moon2Tree.Expr value, Moon2Tree.SwitchExprArm* arms, Moon2Tree.Expr default_expr) unique
         | ExprControl(Moon2Tree.ExprHeader h, Moon2Tree.ControlExprRegion region) unique
         | ExprBlock(Moon2Tree.ExprHeader h, Moon2Tree.Stmt* stmts, Moon2Tree.Expr result) unique
         | ExprClosure(Moon2Tree.ExprHeader h, Moon2Type.Param* params, Moon2Type.Type result, Moon2Tree.Stmt* body) unique
         | ExprView(Moon2Tree.ExprHeader h, Moon2Tree.View view) unique
         | ExprLoad(Moon2Tree.ExprHeader h, Moon2Type.Type ty, Moon2Tree.Expr addr) unique
         | ExprSlotValue(Moon2Tree.ExprHeader h, Moon2Open.ExprSlot slot) unique
         | ExprUseExprFrag(Moon2Tree.ExprHeader h, string use_id, Moon2Open.ExprFrag frag, Moon2Tree.Expr* args, Moon2Open.SlotBinding* fills) unique

    Stmt = StmtLet(Moon2Tree.StmtHeader h, Moon2Bind.Binding binding, Moon2Tree.Expr init) unique
         | StmtVar(Moon2Tree.StmtHeader h, Moon2Bind.Binding binding, Moon2Tree.Expr init) unique
         | StmtSet(Moon2Tree.StmtHeader h, Moon2Tree.Place place, Moon2Tree.Expr value) unique
         | StmtExpr(Moon2Tree.StmtHeader h, Moon2Tree.Expr expr) unique
         | StmtAssert(Moon2Tree.StmtHeader h, Moon2Tree.Expr cond) unique
         | StmtIf(Moon2Tree.StmtHeader h, Moon2Tree.Expr cond, Moon2Tree.Stmt* then_body, Moon2Tree.Stmt* else_body) unique
         | StmtSwitch(Moon2Tree.StmtHeader h, Moon2Tree.Expr value, Moon2Tree.SwitchStmtArm* arms, Moon2Tree.Stmt* default_body) unique
         | StmtJump(Moon2Tree.StmtHeader h, Moon2Tree.BlockLabel target, Moon2Tree.JumpArg* args) unique
         | StmtJumpCont(Moon2Tree.StmtHeader h, Moon2Open.ContSlot slot, Moon2Tree.JumpArg* args) unique
         | StmtYieldVoid(Moon2Tree.StmtHeader h) unique
         | StmtYieldValue(Moon2Tree.StmtHeader h, Moon2Tree.Expr value) unique
         | StmtReturnVoid(Moon2Tree.StmtHeader h) unique
         | StmtReturnValue(Moon2Tree.StmtHeader h, Moon2Tree.Expr value) unique
         | StmtControl(Moon2Tree.StmtHeader h, Moon2Tree.ControlStmtRegion region) unique
         | StmtUseRegionSlot(Moon2Tree.StmtHeader h, Moon2Open.RegionSlot slot) unique
         | StmtUseRegionFrag(Moon2Tree.StmtHeader h, string use_id, Moon2Open.RegionFrag frag, Moon2Tree.Expr* args, Moon2Open.SlotBinding* fills) unique

    Func = FuncLocal(string name, Moon2Type.Param* params, Moon2Type.Type result, Moon2Tree.Stmt* body) unique
         | FuncExport(string name, Moon2Type.Param* params, Moon2Type.Type result, Moon2Tree.Stmt* body) unique
         | FuncLocalContract(string name, Moon2Type.Param* params, Moon2Type.Type result, Moon2Tree.FuncContract* contracts, Moon2Tree.Stmt* body) unique
         | FuncExportContract(string name, Moon2Type.Param* params, Moon2Type.Type result, Moon2Tree.FuncContract* contracts, Moon2Tree.Stmt* body) unique
         | FuncOpen(Moon2Core.FuncSym sym, Moon2Core.Visibility visibility, Moon2Open.OpenParam* params, Moon2Open.OpenSet open, Moon2Type.Type result, Moon2Tree.Stmt* body) unique
    ExternFunc = ExternFunc(string name, string symbol, Moon2Type.Param* params, Moon2Type.Type result) unique
               | ExternFuncOpen(Moon2Core.ExternSym sym, Moon2Open.OpenParam* params, Moon2Type.Type result) unique
    ConstItem = ConstItem(string name, Moon2Type.Type ty, Moon2Tree.Expr value) unique
              | ConstItemOpen(Moon2Core.ConstSym sym, Moon2Open.OpenSet open, Moon2Type.Type ty, Moon2Tree.Expr value) unique
    StaticItem = StaticItem(string name, Moon2Type.Type ty, Moon2Tree.Expr value) unique
               | StaticItemOpen(Moon2Core.StaticSym sym, Moon2Open.OpenSet open, Moon2Type.Type ty, Moon2Tree.Expr value) unique
    ImportItem = (Moon2Core.Path path) unique
    TypeDecl = TypeDeclStruct(string name, Moon2Type.FieldDecl* fields) unique
             | TypeDeclUnion(string name, Moon2Type.FieldDecl* fields) unique
             | TypeDeclEnumSugar(string name, Moon2Core.Name* variants) unique
             | TypeDeclTaggedUnionSugar(string name, Moon2Type.VariantDecl* variants) unique
             | TypeDeclOpenStruct(Moon2Core.TypeSym sym, Moon2Type.FieldDecl* fields) unique
             | TypeDeclOpenUnion(Moon2Core.TypeSym sym, Moon2Type.FieldDecl* fields) unique

    Item = ItemFunc(Moon2Tree.Func func) unique
         | ItemExtern(Moon2Tree.ExternFunc func) unique
         | ItemConst(Moon2Tree.ConstItem c) unique
         | ItemStatic(Moon2Tree.StaticItem s) unique
         | ItemImport(Moon2Tree.ImportItem imp) unique
         | ItemType(Moon2Tree.TypeDecl t) unique
         | ItemUseTypeDeclSlot(Moon2Open.TypeDeclSlot slot) unique
         | ItemUseItemsSlot(Moon2Open.ItemsSlot slot) unique
         | ItemUseModule(string use_id, Moon2Tree.Module module, Moon2Open.SlotBinding* fills) unique
         | ItemUseModuleSlot(string use_id, Moon2Open.ModuleSlot slot, Moon2Open.SlotBinding* fills) unique

    ModuleHeader = ModuleSurface
                 | ModuleTyped(string module_name) unique
                 | ModuleOpen(Moon2Open.ModuleNameFacet name, Moon2Open.OpenSet open) unique
                 | ModuleSem(string module_name) unique
                 | ModuleCode(string module_name) unique
    Module = (Moon2Tree.ModuleHeader h, Moon2Tree.Item* items) unique

    TypeIssue = TypeIssueUnresolvedValue(string name) unique
              | TypeIssueUnresolvedPath(Moon2Core.Path path) unique
              | TypeIssueExpected(string site, Moon2Type.Type expected, Moon2Type.Type actual) unique
              | TypeIssueArgCount(string site, number expected, number actual) unique
              | TypeIssueNotCallable(Moon2Type.Type ty) unique
              | TypeIssueNotIndexable(Moon2Type.Type ty) unique
              | TypeIssueNotPointer(Moon2Type.Type ty) unique
              | TypeIssueInvalidUnary(string op, Moon2Type.Type ty) unique
              | TypeIssueInvalidBinary(string op, Moon2Type.Type lhs, Moon2Type.Type rhs) unique
              | TypeIssueInvalidCompare(string op, Moon2Type.Type lhs, Moon2Type.Type rhs) unique
              | TypeIssueInvalidLogic(Moon2Type.Type lhs, Moon2Type.Type rhs) unique
              | TypeIssueMissingJumpTarget(string region_id, Moon2Tree.BlockLabel label) unique
              | TypeIssueMissingJumpArg(string region_id, Moon2Tree.BlockLabel label, string name) unique
              | TypeIssueExtraJumpArg(string region_id, Moon2Tree.BlockLabel label, string name) unique
              | TypeIssueDuplicateJumpArg(string region_id, Moon2Tree.BlockLabel label, string name) unique
              | TypeIssueUnexpectedYield(string site) unique
              | TypeIssueInvalidControl(string region_id, Moon2Tree.ControlReject reject) unique
    TypeYieldMode = TypeYieldNone | TypeYieldVoid | TypeYieldValue(Moon2Type.Type ty) unique
    TypeCheckEnv = (Moon2Bind.Env env, Moon2Type.Type return_ty, Moon2Tree.TypeYieldMode yield) unique
    TypeViewResult = TypeViewResult(Moon2Tree.View view, Moon2Tree.TypeIssue* issues) unique
    TypeIndexBaseResult = TypeIndexBaseResult(Moon2Tree.IndexBase base, Moon2Type.Type elem, Moon2Tree.TypeIssue* issues) unique
    TypeControlStmtRegionResult = TypeControlStmtRegionResult(Moon2Tree.ControlStmtRegion region, Moon2Tree.TypeIssue* issues) unique
    TypeControlExprRegionResult = TypeControlExprRegionResult(Moon2Tree.ControlExprRegion region, Moon2Tree.TypeIssue* issues) unique
    TypeExprResult = TypeExprResult(Moon2Tree.Expr expr, Moon2Type.Type ty, Moon2Tree.TypeIssue* issues) unique
    TypePlaceResult = TypePlaceResult(Moon2Tree.Place place, Moon2Type.Type ty, Moon2Tree.TypeIssue* issues) unique
    TypeStmtResult = TypeStmtResult(Moon2Tree.TypeCheckEnv env, Moon2Tree.Stmt* stmts, Moon2Tree.TypeIssue* issues) unique
    TypeFuncResult = TypeFuncResult(Moon2Tree.Func func, Moon2Tree.TypeIssue* issues) unique
    TypeItemResult = TypeItemResult(Moon2Tree.Item* items, Moon2Tree.TypeIssue* issues) unique
    TypeModuleResult = TypeModuleResult(Moon2Tree.Module module, Moon2Tree.TypeIssue* issues) unique

    TreeBackLocal = TreeBackScalarLocal(Moon2Bind.Binding binding, Moon2Back.BackValId value, Moon2Back.BackScalar ty) unique
                  | TreeBackViewLocal(Moon2Bind.Binding binding, Moon2Back.BackValId data, Moon2Back.BackValId len) unique
                  | TreeBackStridedViewLocal(Moon2Bind.Binding binding, Moon2Back.BackValId data, Moon2Back.BackValId len, Moon2Back.BackValId stride) unique
    TreeBackReturn = TreeBackReturnScalar
                   | TreeBackReturnView(Moon2Back.BackValId out) unique
    TreeBackEnv = (Moon2Tree.TreeBackLocal* locals, number next_value, number next_block, Moon2Tree.TreeBackReturn ret) unique
    TreeBackExprResult = TreeBackExprValue(Moon2Tree.TreeBackEnv env, Moon2Back.Cmd* cmds, Moon2Back.BackValId value, Moon2Back.BackScalar ty) unique
                       | TreeBackExprView(Moon2Tree.TreeBackEnv env, Moon2Back.Cmd* cmds, Moon2Back.BackValId data, Moon2Back.BackValId len) unique
                       | TreeBackExprStridedView(Moon2Tree.TreeBackEnv env, Moon2Back.Cmd* cmds, Moon2Back.BackValId data, Moon2Back.BackValId len, Moon2Back.BackValId stride) unique
                       | TreeBackExprUnsupported(Moon2Tree.TreeBackEnv env, Moon2Back.Cmd* cmds, string reason) unique
    TreeBackStmtResult = TreeBackStmtResult(Moon2Tree.TreeBackEnv env, Moon2Back.Cmd* cmds, Moon2Back.BackFlow flow) unique
    TreeBackFuncResult = TreeBackFuncResult(Moon2Back.Cmd* cmds) unique
    TreeBackItemResult = TreeBackItemResult(Moon2Back.Cmd* cmds) unique
}

module Moon2Parse {
    ParseIssue = (string message, number offset, number line, number col) unique
    ParseResult = ParseResult(Moon2Tree.Module module, Moon2Parse.ParseIssue* issues) unique
}

module Moon2Vec {
    VecExprId = (string text) unique
    VecLoopId = (string text) unique
    VecAccessId = (string text) unique
    VecValueId = (string text) unique
    VecBlockId = (string text) unique

    VecElem = VecElemBool
            | VecElemI8 | VecElemI16 | VecElemI32 | VecElemI64
            | VecElemU8 | VecElemU16 | VecElemU32 | VecElemU64
            | VecElemF32 | VecElemF64
            | VecElemPtr
            | VecElemIndex

    VecShape = VecScalarShape(Moon2Vec.VecElem elem) unique
             | VecVectorShape(Moon2Vec.VecElem elem, number lanes) unique

    VecBinOp = VecAdd | VecSub | VecMul | VecRem
             | VecBitAnd | VecBitOr | VecBitXor
             | VecShl | VecLShr | VecAShr
             | VecEq | VecNe | VecLt | VecLe | VecGt | VecGe

    VecCmpOp = VecCmpEq | VecCmpNe
             | VecCmpSLt | VecCmpSLe | VecCmpSGt | VecCmpSGe
             | VecCmpULt | VecCmpULe | VecCmpUGt | VecCmpUGe
    VecMaskOp = VecMaskNot | VecMaskAnd | VecMaskOr

    VecUnaryOp = VecNeg | VecNot | VecBitNot | VecPopcount | VecClz | VecCtz

    VecReject = VecRejectUnsupportedLoop(Moon2Vec.VecLoopId loop, string reason) unique
              | VecRejectUnsupportedExpr(Moon2Vec.VecExprId expr, string reason) unique
              | VecRejectUnsupportedStmt(string stmt_id, string reason) unique
              | VecRejectUnsupportedMemory(Moon2Vec.VecAccessId access, string reason) unique
              | VecRejectDependence(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, string reason) unique
              | VecRejectRange(Moon2Vec.VecExprId expr, string reason) unique
              | VecRejectTarget(Moon2Vec.VecShape shape, string reason) unique
              | VecRejectCost(string reason) unique

    VecTarget = VecTargetCraneliftJit
              | VecTargetNamed(string name) unique
    VecTargetFact = VecTargetSupportsShape(Moon2Vec.VecShape shape) unique
                  | VecTargetSupportsBinOp(Moon2Vec.VecShape shape, Moon2Vec.VecBinOp op) unique
                  | VecTargetSupportsCmpOp(Moon2Vec.VecShape shape, Moon2Vec.VecCmpOp op) unique
                  | VecTargetSupportsSelect(Moon2Vec.VecShape shape) unique
                  | VecTargetSupportsMaskOp(Moon2Vec.VecShape shape, Moon2Vec.VecMaskOp op) unique
                  | VecTargetSupportsUnaryOp(Moon2Vec.VecShape shape, Moon2Vec.VecUnaryOp op) unique
                  | VecTargetPrefersUnroll(Moon2Vec.VecShape shape, number unroll, number rank) unique
                  | VecTargetPrefersScalarTail
                  | VecTargetSupportsMaskedTail
                  | VecTargetVectorBits(number bits) unique
    VecTargetModel = (Moon2Vec.VecTarget target, Moon2Vec.VecTargetFact* facts) unique

    VecExprFact = VecExprConst(Moon2Vec.VecExprId id, Moon2Tree.Expr expr, Moon2Type.Type ty) unique
                | VecExprInvariant(Moon2Vec.VecExprId id, Moon2Tree.Expr expr, Moon2Type.Type ty) unique
                | VecExprLaneIndex(Moon2Vec.VecExprId id, Moon2Bind.Binding binding, Moon2Type.Type ty) unique
                | VecExprLocal(Moon2Vec.VecExprId id, Moon2Bind.Binding binding, Moon2Vec.VecExprId value, Moon2Type.Type ty) unique
                | VecExprUnary(Moon2Vec.VecExprId id, Moon2Vec.VecUnaryOp op, Moon2Vec.VecExprId value, Moon2Type.Type ty) unique
                | VecExprBin(Moon2Vec.VecExprId id, Moon2Vec.VecBinOp op, Moon2Vec.VecExprId lhs, Moon2Vec.VecExprId rhs, Moon2Type.Type ty) unique
                | VecExprSelect(Moon2Vec.VecExprId id, Moon2Vec.VecExprId cond, Moon2Vec.VecExprId then_value, Moon2Vec.VecExprId else_value, Moon2Type.Type ty) unique
                | VecExprLoad(Moon2Vec.VecExprId id, Moon2Vec.VecAccessId access, Moon2Type.Type ty) unique
                | VecExprRejected(Moon2Vec.VecExprId id, Moon2Vec.VecReject reject) unique
    VecExprGraph = (Moon2Vec.VecExprFact* exprs) unique
    VecExprResult = VecExprResult(Moon2Vec.VecExprId value, Moon2Vec.VecExprFact* facts, Moon2Vec.VecMemoryFact* memory, Moon2Vec.VecRangeFact* ranges, Moon2Vec.VecReject* rejects, Moon2Type.Type ty) unique
    VecLocalFact = (Moon2Bind.Binding binding, Moon2Vec.VecExprId value, Moon2Type.Type ty) unique
    VecExprEnv = (Moon2Bind.Binding index, Moon2Vec.VecLocalFact* locals) unique
    VecStmtResult = VecStmtLocal(Moon2Vec.VecLocalFact local, Moon2Vec.VecExprFact* facts, Moon2Vec.VecMemoryFact* memory, Moon2Vec.VecRangeFact* ranges, Moon2Vec.VecReject* rejects) unique
                  | VecStmtStore(Moon2Vec.VecStoreFact store, Moon2Vec.VecExprFact* facts, Moon2Vec.VecMemoryFact* memory, Moon2Vec.VecRangeFact* ranges, Moon2Vec.VecReject* rejects) unique
                  | VecStmtIgnored(Moon2Vec.VecExprFact* facts, Moon2Vec.VecMemoryFact* memory, Moon2Vec.VecRangeFact* ranges, Moon2Vec.VecReject* rejects) unique

    VecRangeFact = VecRangeUnknown(Moon2Vec.VecExprId expr) unique
                 | VecRangeExact(Moon2Vec.VecExprId expr, string value) unique
                 | VecRangeUnsigned(Moon2Vec.VecExprId expr, string min, string max) unique
                 | VecRangeBitAnd(Moon2Vec.VecExprId expr, string mask, string max_value) unique
                 | VecRangeDerived(Moon2Vec.VecExprId expr, string min, string max, Moon2Vec.VecProof* proofs) unique

    VecDomain = VecDomainCounted(Moon2Tree.Expr start, Moon2Tree.Expr stop, Moon2Tree.Expr step) unique
              | VecDomainRejected(Moon2Vec.VecReject reject) unique
    VecInduction = VecPrimaryInduction(Moon2Bind.Binding binding, Moon2Tree.Expr start, Moon2Tree.Expr step) unique
                 | VecDerivedInduction(Moon2Bind.Binding binding, Moon2Vec.VecExprId expr) unique

    VecAccessKind = VecAccessLoad | VecAccessStore
    VecAccessPattern = VecAccessContiguous
                     | VecAccessStrided(number stride) unique
                     | VecAccessGather
                     | VecAccessScatter
                     | VecAccessUnknown
    VecAlignment = VecAlignmentKnown(number bytes) unique
                 | VecAlignmentUnknown
                 | VecAlignmentAssumed(number bytes, Moon2Vec.VecProof proof) unique
    VecBounds = VecBoundsProven(Moon2Vec.VecProof proof) unique
              | VecBoundsUnknown(Moon2Vec.VecReject reject) unique
    VecMemoryBase = VecMemoryBaseRawAddr(Moon2Tree.Expr addr) unique
                  | VecMemoryBaseView(Moon2Tree.View view) unique
                  | VecMemoryBasePlace(Moon2Tree.Place place) unique
    VecMemoryFact = VecMemoryAccess(Moon2Vec.VecAccessId id, Moon2Vec.VecAccessKind access_kind, Moon2Vec.VecMemoryBase base, Moon2Vec.VecExprId index, Moon2Type.Type elem_ty, Moon2Vec.VecAccessPattern pattern, Moon2Vec.VecAlignment alignment, Moon2Vec.VecBounds bounds) unique
    VecAliasFact = VecAccessSameBase(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, string reason) unique
                 | VecAccessNoAlias(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, string reason) unique
                 | VecAccessDisjointRange(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, string reason) unique
                 | VecAliasUnknown(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, Moon2Vec.VecReject reject) unique
    VecDependenceFact = VecNoDependence(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, Moon2Vec.VecProof proof) unique
                      | VecDependenceUnknown(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, Moon2Vec.VecReject reject) unique
                      | VecLoopCarriedDependence(Moon2Vec.VecAccessId a, Moon2Vec.VecAccessId b, Moon2Vec.VecReject reject) unique
    VecReassoc = VecReassocWrapping
               | VecReassocExact
               | VecReassocFloatFastMath
               | VecReassocRejected(Moon2Vec.VecReject reject) unique
    VecReductionFact = VecReductionAdd(Moon2Bind.Binding accumulator, Moon2Vec.VecExprId value, Moon2Vec.VecReassoc reassoc) unique
                     | VecReductionMul(Moon2Bind.Binding accumulator, Moon2Vec.VecExprId value, Moon2Vec.VecReassoc reassoc) unique
                     | VecReductionBitAnd(Moon2Bind.Binding accumulator, Moon2Vec.VecExprId value) unique
                     | VecReductionBitOr(Moon2Bind.Binding accumulator, Moon2Vec.VecExprId value) unique
                     | VecReductionBitXor(Moon2Bind.Binding accumulator, Moon2Vec.VecExprId value) unique
    VecStoreFact = VecStoreFact(Moon2Vec.VecMemoryFact access, Moon2Vec.VecExprId value) unique

    VecProof = VecProofDomain(string reason) unique
             | VecProofRange(Moon2Vec.VecRangeFact range, string reason) unique
             | VecProofAlias(Moon2Vec.VecAliasFact alias, string reason) unique
             | VecProofNoMemoryDependence(Moon2Vec.VecAccessId* accesses, string reason) unique
             | VecProofKernelSafety(string reason) unique
             | VecProofReduction(Moon2Vec.VecReductionFact reduction, string reason) unique
             | VecProofNarrowSafe(Moon2Vec.VecReductionFact reduction, Moon2Vec.VecElem narrow_elem, number chunk_elems, string reason) unique
             | VecProofTarget(Moon2Vec.VecTargetFact fact, string reason) unique
    VecAssumption = VecAssumeRawPtrBounds(Moon2Bind.Binding base, Moon2Bind.Binding stop, string reason) unique
                  | VecAssumeRawPtrDisjointOrSameIndexSafe(Moon2Bind.Binding* bases, string reason) unique
                  | VecAssumeAlignment(Moon2Bind.Binding base, number bytes, string reason) unique
    VecKernelSafety = VecKernelSafetyProven(Moon2Vec.VecProof* proofs) unique
                    | VecKernelSafetyAssumed(Moon2Vec.VecProof* proofs, Moon2Vec.VecAssumption* assumptions) unique
                    | VecKernelSafetyRejected(Moon2Vec.VecReject* rejects) unique
    VecKernelLenSource = VecKernelLenBinding(Moon2Bind.Binding binding) unique
                       | VecKernelLenView(Moon2Bind.Binding view) unique
                       | VecKernelLenExpr(Moon2Tree.Expr expr) unique
    VecKernelMemoryUse = VecKernelRead(Moon2Bind.Binding base, Moon2Vec.VecElem elem, Moon2Vec.VecKernelIndexOffset offset, Moon2Vec.VecKernelLenSource base_len, Moon2Tree.Expr len_value) unique
                       | VecKernelWrite(Moon2Bind.Binding base, Moon2Vec.VecElem elem, Moon2Vec.VecKernelIndexOffset offset, Moon2Vec.VecKernelLenSource base_len, Moon2Tree.Expr len_value) unique
    VecKernelBounds = VecKernelBoundsProven(Moon2Vec.VecProof proof) unique
                    | VecKernelBoundsAssumed(Moon2Vec.VecAssumption assumption) unique
                    | VecKernelBoundsRejected(Moon2Vec.VecReject reject) unique
    VecWindowRangeObligation = (Moon2Bind.Binding base, Moon2Vec.VecKernelLenSource base_len, Moon2Vec.VecKernelIndexOffset start, Moon2Bind.Binding len, Moon2Tree.Expr len_value) unique
    VecWindowRangeDecision = VecWindowRangeProven(Moon2Vec.VecWindowRangeObligation obligation, Moon2Vec.VecProof proof) unique
                           | VecWindowRangeRejected(Moon2Vec.VecWindowRangeObligation obligation, Moon2Vec.VecReject reject) unique
    VecKernelAlias = VecKernelAliasProven(Moon2Vec.VecProof proof) unique
                   | VecKernelAliasAssumed(Moon2Vec.VecAssumption assumption) unique
                   | VecKernelAliasSameIndexSafe(Moon2Vec.VecProof proof) unique
                   | VecKernelAliasRejected(Moon2Vec.VecReject reject) unique
    VecKernelAlignment = VecKernelAlignProven(Moon2Bind.Binding base, Moon2Vec.VecElem elem, number bytes, Moon2Vec.VecProof proof) unique
                       | VecKernelAlignAssumed(Moon2Bind.Binding base, Moon2Vec.VecElem elem, number bytes, Moon2Vec.VecAssumption assumption) unique
                       | VecKernelAlignUnknown(Moon2Bind.Binding base, Moon2Vec.VecElem elem, string reason) unique
                       | VecKernelAlignRejected(Moon2Bind.Binding base, Moon2Vec.VecElem elem, Moon2Vec.VecReject reject) unique

    VecNestedLoopFact = (Moon2Vec.VecLoopFacts facts) unique
    VecLoopSource = VecLoopSourceControlRegion(string region_id, Moon2Tree.BlockLabel header, Moon2Tree.BlockLabel backedge) unique
                  | VecLoopSourceRejected(Moon2Vec.VecReject reject) unique
    VecLoopFacts = VecLoopFacts(Moon2Vec.VecLoopId loop, Moon2Vec.VecLoopSource source, Moon2Vec.VecDomain domain, Moon2Vec.VecInduction* inductions, Moon2Vec.VecExprGraph exprs, Moon2Vec.VecMemoryFact* memory, Moon2Vec.VecAliasFact* aliases, Moon2Vec.VecDependenceFact* dependences, Moon2Vec.VecRangeFact* ranges, Moon2Vec.VecStoreFact* stores, Moon2Vec.VecReductionFact* reductions, Moon2Vec.VecNestedLoopFact* nested, Moon2Vec.VecReject* rejects) unique
    VecTail = VecTailNone | VecTailScalar | VecTailMasked(Moon2Vec.VecProof proof) unique
    VecLoopShape = VecLoopScalar(Moon2Vec.VecLoopId loop, Moon2Vec.VecReject* vector_rejects) unique
                 | VecLoopVector(Moon2Vec.VecLoopId loop, Moon2Vec.VecShape shape, number unroll, Moon2Vec.VecTail tail, Moon2Vec.VecProof* proofs) unique
                 | VecLoopChunkedNarrowVector(Moon2Vec.VecLoopId loop, Moon2Vec.VecShape narrow_shape, number unroll, number chunk_elems, Moon2Vec.VecTail tail, Moon2Vec.VecProof narrow_proof, Moon2Vec.VecProof* proofs) unique
    VecLegality = VecLegal(Moon2Vec.VecProof* proofs) unique
                | VecIllegal(Moon2Vec.VecReject* rejects) unique
    VecReductionSchedule = VecReductionSchedule(Moon2Vec.VecBinOp op, number accumulators, Moon2Vec.VecProof* proofs) unique
    VecSchedule = VecScheduleScalar(Moon2Vec.VecReject* rejects) unique
                | VecScheduleVector(Moon2Vec.VecShape shape, number unroll, number interleave, Moon2Vec.VecTail tail, number accumulators, Moon2Vec.VecReductionSchedule* reductions, Moon2Vec.VecProof* proofs) unique
                | VecScheduleChunkedNarrowVector(Moon2Vec.VecShape narrow_shape, number unroll, number interleave, number chunk_elems, Moon2Vec.VecTail tail, number accumulators, Moon2Vec.VecReductionSchedule* reductions, Moon2Vec.VecProof narrow_proof, Moon2Vec.VecProof* proofs) unique
    VecShapeScore = VecShapeScore(Moon2Vec.VecLoopShape shape, number elems_per_iter, number rank, string rationale) unique
    VecLoopDecision = VecLoopDecision(Moon2Vec.VecLoopFacts facts, Moon2Vec.VecLegality legality, Moon2Vec.VecSchedule schedule, Moon2Vec.VecLoopShape chosen, Moon2Vec.VecShapeScore* considered) unique
    VecScheduleInspection = (Moon2Vec.VecLoopId loop, Moon2Vec.VecLegality legality, Moon2Vec.VecSchedule schedule, Moon2Vec.VecShapeScore* considered) unique
    VecInspectionReport = (Moon2Vec.VecScheduleInspection* schedules) unique

    VecKernelIndexOffset = VecKernelOffsetZero
                         | VecKernelOffsetExpr(Moon2Tree.Expr expr) unique
                         | VecKernelOffsetAdd(Moon2Vec.VecKernelIndexOffset lhs, Moon2Vec.VecKernelIndexOffset rhs) unique
    VecKernelScalarAlias = (Moon2Bind.Binding binding, Moon2Tree.Expr value) unique
    VecKernelCounter = VecKernelCounterI32(Moon2Vec.VecProof* proofs) unique
                     | VecKernelCounterIndex(Moon2Vec.VecProof* proofs) unique
                     | VecKernelCounterRejected(Moon2Vec.VecReject reject) unique
    VecKernelMaskExpr = VecKernelMaskCompare(Moon2Vec.VecCmpOp op, Moon2Vec.VecKernelExpr lhs, Moon2Vec.VecKernelExpr rhs) unique
                      | VecKernelMaskNot(Moon2Vec.VecKernelMaskExpr value) unique
                      | VecKernelMaskBin(Moon2Vec.VecMaskOp op, Moon2Vec.VecKernelMaskExpr lhs, Moon2Vec.VecKernelMaskExpr rhs) unique
    VecKernelExpr = VecKernelExprLoad(Moon2Bind.Binding base, Moon2Vec.VecKernelIndexOffset offset, Moon2Vec.VecKernelLenSource base_len, Moon2Tree.Expr len_value) unique
                  | VecKernelExprInvariant(Moon2Tree.Expr expr) unique
                  | VecKernelExprBin(Moon2Vec.VecBinOp op, Moon2Vec.VecKernelExpr lhs, Moon2Vec.VecKernelExpr rhs) unique
                  | VecKernelExprSelect(Moon2Vec.VecKernelMaskExpr cond, Moon2Vec.VecKernelExpr then_value, Moon2Vec.VecKernelExpr else_value) unique
    VecKernelStorePlan = (Moon2Bind.Binding dst, Moon2Vec.VecKernelIndexOffset offset, Moon2Vec.VecKernelLenSource base_len, Moon2Tree.Expr len_value, Moon2Vec.VecKernelExpr value) unique
    VecKernelViewStride = VecKernelStrideUnit
                        | VecKernelStrideConst(string raw) unique
                        | VecKernelStrideDynamic(Moon2Tree.Expr expr) unique
    VecKernelViewAlias = (Moon2Bind.Binding view, Moon2Bind.Binding data, Moon2Bind.Binding len, Moon2Vec.VecKernelViewStride stride, Moon2Vec.VecKernelIndexOffset offset, Moon2Vec.VecKernelLenSource base_len, Moon2Tree.Expr len_value) unique
    VecKernelReductionPlan = VecKernelReductionBin(Moon2Vec.VecBinOp op, Moon2Vec.VecElem elem, Moon2Bind.Binding accumulator, Moon2Vec.VecKernelExpr value, string identity) unique
                           | VecKernelReductionAdd(Moon2Vec.VecElem elem, Moon2Bind.Binding accumulator, Moon2Vec.VecKernelExpr value) unique
    VecKernelCore = VecKernelCoreReduce(Moon2Vec.VecLoopDecision decision, Moon2Vec.VecElem elem, Moon2Bind.Binding stop, Moon2Vec.VecKernelCounter counter, Moon2Vec.VecKernelScalarAlias* scalars, Moon2Vec.VecKernelReductionPlan reduction) unique
                  | VecKernelCoreMap(Moon2Vec.VecLoopDecision decision, Moon2Vec.VecElem elem, Moon2Bind.Binding stop, Moon2Vec.VecKernelCounter counter, Moon2Vec.VecKernelScalarAlias* scalars, Moon2Vec.VecKernelStorePlan* stores) unique
    VecKernelSafetyInput = (Moon2Vec.VecLoopFacts facts, Moon2Vec.VecKernelCore core, Moon2Vec.VecKernelMemoryUse* uses, Moon2Tree.ContractFact* contracts) unique
    VecKernelSafetyDecision = (Moon2Vec.VecKernelSafety safety, Moon2Vec.VecKernelBounds* bounds, Moon2Vec.VecKernelAlignment* alignments, Moon2Vec.VecKernelAlias* aliases, Moon2Vec.VecReject* rejects) unique
    VecKernelPlan = VecKernelNoPlan(Moon2Vec.VecReject* rejects) unique
                  | VecKernelReduce(Moon2Vec.VecLoopDecision decision, Moon2Vec.VecElem elem, Moon2Bind.Binding stop, Moon2Vec.VecKernelCounter counter, Moon2Vec.VecKernelScalarAlias* scalars, Moon2Vec.VecKernelReductionPlan reduction, Moon2Vec.VecKernelSafety safety, Moon2Vec.VecKernelAlignment* alignments, Moon2Vec.VecKernelAlias* aliases) unique
                  | VecKernelMap(Moon2Vec.VecLoopDecision decision, Moon2Vec.VecElem elem, Moon2Bind.Binding stop, Moon2Vec.VecKernelCounter counter, Moon2Vec.VecKernelScalarAlias* scalars, Moon2Vec.VecKernelStorePlan* stores, Moon2Vec.VecKernelSafety safety, Moon2Vec.VecKernelAlignment* alignments, Moon2Vec.VecKernelAlias* aliases) unique

    VecValue = VecScalarValue(Moon2Vec.VecValueId id, Moon2Vec.VecElem elem) unique
             | VecVectorValue(Moon2Vec.VecValueId id, Moon2Vec.VecElem elem, number lanes) unique
    VecParam = VecScalarParam(Moon2Vec.VecValueId id, Moon2Vec.VecElem elem) unique
             | VecVectorParam(Moon2Vec.VecValueId id, Moon2Vec.VecElem elem, number lanes) unique
    VecCmd = VecCmdConstInt(Moon2Vec.VecValueId dst, Moon2Vec.VecElem elem, string raw) unique
           | VecCmdSplat(Moon2Vec.VecValueId dst, Moon2Vec.VecShape shape, Moon2Vec.VecValueId scalar) unique
           | VecCmdRamp(Moon2Vec.VecValueId dst, Moon2Vec.VecShape shape, Moon2Vec.VecValueId base, string* offsets) unique
           | VecCmdBin(Moon2Vec.VecValueId dst, Moon2Vec.VecShape shape, Moon2Vec.VecBinOp op, Moon2Vec.VecValueId lhs, Moon2Vec.VecValueId rhs) unique
           | VecCmdSelect(Moon2Vec.VecValueId dst, Moon2Vec.VecShape shape, Moon2Vec.VecValueId cond, Moon2Vec.VecValueId then_value, Moon2Vec.VecValueId else_value) unique
           | VecCmdIreduce(Moon2Vec.VecValueId dst, Moon2Vec.VecElem narrow_elem, Moon2Vec.VecValueId value, Moon2Vec.VecProof proof) unique
           | VecCmdUextend(Moon2Vec.VecValueId dst, Moon2Vec.VecElem wide_elem, Moon2Vec.VecValueId value) unique
           | VecCmdExtractLane(Moon2Vec.VecValueId dst, Moon2Vec.VecValueId vec, number lane) unique
           | VecCmdHorizontalReduce(Moon2Vec.VecValueId dst, Moon2Vec.VecBinOp op, Moon2Vec.VecValueId* vectors) unique
           | VecCmdLoad(Moon2Vec.VecValueId dst, Moon2Vec.VecShape shape, Moon2Vec.VecMemoryFact access, Moon2Vec.VecValueId addr) unique
           | VecCmdStore(Moon2Vec.VecMemoryFact access, Moon2Vec.VecShape shape, Moon2Vec.VecValueId addr, Moon2Vec.VecValueId value) unique
    VecTerminator = VecJump(Moon2Vec.VecBlockId dest, Moon2Vec.VecValueId* args) unique
                  | VecBrIf(Moon2Vec.VecValueId cond, Moon2Vec.VecBlockId then_block, Moon2Vec.VecValueId* then_args, Moon2Vec.VecBlockId else_block, Moon2Vec.VecValueId* else_args) unique
                  | VecReturnVoid
                  | VecReturnValue(Moon2Vec.VecValueId value) unique
    VecBlock = VecBlock(Moon2Vec.VecBlockId id, Moon2Vec.VecParam* params, Moon2Vec.VecCmd* cmds, Moon2Vec.VecTerminator terminator) unique
    VecBackValueShape = (Moon2Vec.VecValueId id, Moon2Vec.VecShape shape) unique
    VecBackEnv = (Moon2Vec.VecBackValueShape* values) unique
    VecBackLowering = VecBackCmds(Moon2Vec.VecBackEnv env, Moon2Back.Cmd* cmds) unique
                    | VecBackReject(Moon2Vec.VecBackEnv env, Moon2Vec.VecReject reject) unique
    VecBackFuncSpec = (string name, Moon2Core.Visibility visibility, Moon2Vec.VecParam* params, Moon2Vec.VecShape* results, Moon2Vec.VecBlock* blocks) unique
    VecBackProgramSpec = (Moon2Vec.VecBackFuncSpec* funcs) unique

    VecFunc = VecFuncScalar(Moon2Tree.Func func, Moon2Vec.VecLoopDecision* decisions) unique
            | VecFuncVector(Moon2Tree.Func func, Moon2Vec.VecLoopDecision* decisions, Moon2Vec.VecBlock* blocks) unique
            | VecFuncMixed(Moon2Tree.Func func, Moon2Vec.VecLoopDecision* decisions, Moon2Vec.VecBlock* blocks) unique
    VecModule = VecModule(Moon2Tree.Module source, Moon2Vec.VecTargetModel target, Moon2Vec.VecFunc* funcs) unique
}

module Moon2Host {
    HostIssue = HostIssueInvalidName(string site, string name) unique
              | HostIssueExpected(string site, string expected, string actual) unique
              | HostIssueDuplicateField(string type_name, string field_name) unique
              | HostIssueDuplicateType(string module_name, string type_name) unique
              | HostIssueDuplicateDecl(string name) unique
              | HostIssueDuplicateFunc(string module_name, string func_name) unique
              | HostIssueUnsealedType(string module_name, string type_name) unique
              | HostIssueSealedMutation(string type_name) unique
              | HostIssueAlreadySealed(string type_name) unique
              | HostIssueUnknownBinding(string site, string name) unique
              | HostIssueInvalidEmitFill(string fragment_name, string fill_name) unique
              | HostIssueMissingEmitFill(string fragment_name, string fill_name) unique
              | HostIssueInvalidPackedAlign(string type_name, number align) unique
              | HostIssueBareBoolInBoundaryStruct(string type_name, string field_name) unique
              | HostIssueArgCount(string site, number expected, number actual) unique
    HostReport = (Moon2Host.HostIssue* issues) unique

    HostLayoutId = (string key, string name) unique
    HostFieldId = (string key, string name) unique

    HostEndian = HostEndianLittle
               | HostEndianBig
    HostTargetModel = (number pointer_bits, number index_bits, Moon2Host.HostEndian endian) unique

    HostLayoutKind = HostLayoutStruct
                   | HostLayoutSlice
                   | HostLayoutArray
                   | HostLayoutViewDescriptor
                   | HostLayoutOpaque

    HostOwner = HostOwnerBufferView
              | HostOwnerHostSession
              | HostOwnerBorrowed
              | HostOwnerStatic
              | HostOwnerOpaque

    HostBoolEncoding = HostBoolU8
                     | HostBoolI32
                     | HostBoolNative

    HostRepr = HostReprC
             | HostReprPacked(number align) unique
             | HostReprOpaque(string name) unique

    HostFieldAttr = HostFieldReadonly
                  | HostFieldMutable
                  | HostFieldNoalias
                  | HostFieldOpaque(string name) unique

    HostStorageRep = HostStorageSame
                   | HostStorageScalar(Moon2Core.Scalar scalar) unique
                   | HostStorageBool(Moon2Host.HostBoolEncoding encoding, Moon2Core.Scalar scalar) unique
                   | HostStoragePtr(Moon2Type.Type pointee) unique
                   | HostStorageSlice(Moon2Type.Type elem) unique
                   | HostStorageView(Moon2Type.Type elem) unique
                   | HostStorageOpaque(string name) unique

    HostStructDecl = (Moon2Host.HostLayoutId id, string name, Moon2Host.HostRepr repr, Moon2Host.HostFieldDecl* fields) unique
    HostFieldDecl = (Moon2Host.HostFieldId id, string name, Moon2Type.Type expose_ty, Moon2Host.HostStorageRep storage, Moon2Host.HostFieldAttr* attrs) unique
    HostAccessorDecl = HostAccessorField(string owner_name, string name, string field_name) unique
                     | HostAccessorLua(string owner_name, string name, string lua_symbol) unique
                     | HostAccessorMoonlift(string owner_name, string name, Moon2Tree.Func func) unique
    HostDecl = HostDeclStruct(Moon2Host.HostStructDecl decl) unique
             | HostDeclExpose(Moon2Host.HostExposeDecl decl) unique
             | HostDeclAccessor(Moon2Host.HostAccessorDecl decl) unique
    HostDeclSet = (Moon2Host.HostDecl* decls) unique
    HostDeclSource = HostDeclSourceSet(Moon2Host.HostDeclSet set) unique
                   | HostDeclSourceDecls(Moon2Host.HostDecl* decls) unique

    MluaSource = (string name, string source) unique
    MluaParseResult = (Moon2Host.HostDeclSet decls, Moon2Tree.Module module, Moon2Open.RegionFrag* region_frags, Moon2Open.ExprFrag* expr_frags, Moon2Parse.ParseIssue* issues) unique
    MluaHostPipelineResult = (Moon2Host.MluaParseResult parse, Moon2Host.HostReport report, Moon2Host.HostLayoutEnv layout_env, Moon2Host.HostFactSet facts, Moon2Host.HostLuaFfiPlan lua, Moon2Host.HostTerraPlan terra, Moon2Host.HostCPlan c) unique
    MluaRegionTypeResult = (Moon2Open.RegionFrag frag, Moon2Tree.TypeIssue* issues) unique
    MluaLoopExpandResult = (Moon2Tree.EntryControlBlock entry, Moon2Tree.ControlBlock* blocks, Moon2Tree.TypeIssue* issues) unique
    MluaLoopSource = MluaLoopControlStmt(Moon2Tree.ControlStmtRegion region) unique
                   | MluaLoopControlExpr(Moon2Tree.ControlExprRegion region) unique

    HostFieldRep = HostRepScalar(Moon2Core.Scalar scalar) unique
                 | HostRepBool(Moon2Host.HostBoolEncoding encoding, Moon2Core.Scalar storage) unique
                 | HostRepPtr(Moon2Type.Type pointee) unique
                 | HostRepRef(Moon2Host.HostLayoutId layout) unique
                 | HostRepSlice(Moon2Host.HostFieldRep elem) unique
                 | HostRepView(Moon2Type.Type elem) unique
                 | HostRepStruct(Moon2Host.HostLayoutId layout) unique
                 | HostRepOpaque(string name) unique

    HostFieldLayout = (Moon2Host.HostFieldId id, string name, string cfield, Moon2Host.HostFieldRep rep, number offset, number size, number align) unique
    HostTypeLayout = (Moon2Host.HostLayoutId id, string name, string ctype, Moon2Host.HostLayoutKind kind, number size, number align, Moon2Host.HostFieldLayout* fields) unique
    HostLayoutEnv = (Moon2Host.HostTypeLayout* layouts) unique
    HostCdef = (Moon2Host.HostLayoutId layout, string source) unique
    HostLuaFfiPlan = (string module_name, Moon2Host.HostCdef* cdefs, Moon2Host.HostAccessPlan* access_plans) unique
    HostTerraPlan = (string module_name, string source, Moon2Host.HostTypeLayout* layouts, Moon2Host.HostViewDescriptor* views) unique
    HostCPlan = (string header_name, string source, Moon2Host.HostTypeLayout* layouts, Moon2Host.HostViewDescriptor* views) unique
    HostExportAbi = HostExportDescriptorPtr(Moon2Host.HostViewDescriptor descriptor) unique
                  | HostExportExpandedScalars(Moon2Type.Type ty) unique

    HostExposeSubject = HostExposeType(Moon2Type.Type ty) unique
                      | HostExposePtr(Moon2Type.Type pointee) unique
                      | HostExposeView(Moon2Type.Type elem) unique
    HostStrideUnit = HostStrideElements
                   | HostStrideBytes
    HostViewAbi = HostViewAbiContiguous(Moon2Host.HostTypeLayout elem_layout) unique
                | HostViewAbiStrided(Moon2Host.HostTypeLayout elem_layout, Moon2Host.HostStrideUnit stride_unit) unique
    HostViewDescriptor = (Moon2Host.HostLayoutId id, string name, Moon2Host.HostViewAbi abi, Moon2Host.HostTypeLayout descriptor_layout) unique

    HostExposeTarget = HostExposeLua
                     | HostExposeTerra
                     | HostExposeC
                     | HostExposeMoonlift
    HostMutability = HostReadonly
                   | HostMutable
                   | HostInteriorMutable
    HostBoundsPolicy = HostBoundsChecked
                     | HostBoundsUnchecked

    HostProxyKind = HostProxyPtr
                  | HostProxyView
                  | HostProxyBufferView
                  | HostProxyTypedRecord
                  | HostProxyOpaque
    HostProxyCachePolicy = HostProxyCacheNone
                         | HostProxyCacheLazy
                         | HostProxyCacheEager
    HostMaterializePolicy = HostMaterializeProjectedFields
                          | HostMaterializeFullCopy
                          | HostMaterializeBorrowedView
    HostExposeMode = HostExposeProxy(Moon2Host.HostProxyKind kind, Moon2Host.HostProxyCachePolicy cache, Moon2Host.HostMutability mutability, Moon2Host.HostBoundsPolicy bounds) unique
                   | HostExposeEagerTable(Moon2Host.HostMaterializePolicy policy) unique
                   | HostExposeScalar(Moon2Host.HostFieldRep rep) unique
                   | HostExposeOpaque(string reason) unique
    HostExposeAbi = HostExposeAbiDefault
                  | HostExposeAbiPointer
                  | HostExposeAbiDescriptor
                  | HostExposeAbiDataLenStride
                  | HostExposeAbiExpandedScalars
                  | HostExposeAbiOpaque(string reason) unique
    HostExposeFacet = (Moon2Host.HostExposeTarget target, Moon2Host.HostExposeAbi abi, Moon2Host.HostExposeMode mode) unique
    HostExposeDecl = (Moon2Host.HostExposeSubject subject, string public_name, Moon2Host.HostExposeFacet* facets) unique
    HostLifetime = HostLifetimeStatic
                 | HostLifetimeOwned
                 | HostLifetimeBorrowed(string owner_name) unique
                 | HostLifetimeGeneration(number session_id, number generation) unique
                 | HostLifetimeExternal(string name) unique

    HostAccessSubject = HostAccessRecord(Moon2Host.HostTypeLayout layout) unique
                      | HostAccessPtr(Moon2Host.HostTypeLayout layout) unique
                      | HostAccessView(Moon2Host.HostViewDescriptor descriptor) unique
    HostAccessKey = HostAccessField(string name) unique
                  | HostAccessIndex
                  | HostAccessLen
                  | HostAccessData
                  | HostAccessStride
                  | HostAccessMethod(string name) unique
                  | HostAccessPairs
                  | HostAccessIpairs
                  | HostAccessToTable
    HostAccessOp = HostAccessDirectField(Moon2Host.HostFieldLayout field) unique
                 | HostAccessDecodeBool(Moon2Host.HostFieldLayout field) unique
                 | HostAccessEncodeBool(Moon2Host.HostFieldLayout field) unique
                 | HostAccessViewIndex(Moon2Host.HostViewDescriptor descriptor) unique
                 | HostAccessViewFieldAt(Moon2Host.HostViewDescriptor descriptor, Moon2Host.HostFieldLayout field) unique
                 | HostAccessViewLen(Moon2Host.HostViewDescriptor descriptor) unique
                 | HostAccessViewData(Moon2Host.HostViewDescriptor descriptor) unique
                 | HostAccessViewStride(Moon2Host.HostViewDescriptor descriptor) unique
                 | HostAccessPointerCast(Moon2Host.HostTypeLayout layout) unique
                 | HostAccessIterateFields(Moon2Host.HostLayoutId layout) unique
                 | HostAccessMaterializeTable(Moon2Host.HostAccessSubject subject) unique
                 | HostAccessReject(string reason) unique
    HostAccessEntry = (Moon2Host.HostAccessKey key, Moon2Host.HostAccessOp op) unique
    HostAccessPlan = (Moon2Host.HostAccessSubject subject, Moon2Host.HostAccessEntry* entries) unique
    HostViewPlan = (Moon2Host.HostTypeLayout layout, Moon2Host.HostOwner owner, Moon2Host.HostExposeMode expose, Moon2Host.HostAccessPlan access) unique

    HostProducerKind = HostProducerLowLevelMoonlift
                     | HostProducerLuaFfi
                     | HostProducerRustTypedRecordMemory
                     | HostProducerExternal
    HostProducerPlan = (string name, Moon2Host.HostProducerKind kind, Moon2Host.HostTypeLayout* outputs) unique

    HostLayoutFact = HostFactTypeLayout(Moon2Host.HostTypeLayout layout) unique
                   | HostFactCdef(Moon2Host.HostCdef cdef) unique
                   | HostFactField(Moon2Host.HostLayoutId owner, Moon2Host.HostFieldLayout field) unique
                   | HostFactViewDescriptor(Moon2Host.HostViewDescriptor descriptor) unique
                   | HostFactExpose(string public_name, Moon2Host.HostLayoutId layout, Moon2Host.HostExposeFacet facet) unique
                   | HostFactAccessPlan(Moon2Host.HostAccessPlan plan) unique
                   | HostFactViewPlan(Moon2Host.HostViewPlan plan) unique
                   | HostFactLuaFfi(Moon2Host.HostLuaFfiPlan plan) unique
                   | HostFactTerra(Moon2Host.HostTerraPlan plan) unique
                   | HostFactC(Moon2Host.HostCPlan plan) unique
                   | HostFactProducer(Moon2Host.HostProducerPlan plan) unique
    HostFactSet = (Moon2Host.HostLayoutFact* facts) unique

    HostLayoutReject = HostRejectJsonInRust
                     | HostRejectDynamicObjectArena(string reason) unique
                     | HostRejectUnknownFieldKind(string kind) unique
                     | HostRejectInvalidLayout(string reason) unique
                     | HostRejectBareBoolInBoundaryStruct(string type_name, string field_name) unique
                     | HostRejectInvalidPackedAlign(string type_name, number align) unique
                     | HostRejectConflictingCdef(Moon2Host.HostLayoutId layout) unique
}

module Moon2Source {
    DocUri = (string text) unique
    DocVersion = (number value) unique
    LanguageId = LangMlua
               | LangMoonlift
               | LangLua
               | LangUnknown(string name) unique
    DocumentSnapshot = (Moon2Source.DocUri uri, Moon2Source.DocVersion version, Moon2Source.LanguageId language, string text) unique

    PositionEncoding = PosUtf8Bytes
                     | PosUtf16CodeUnits
                     | PosUtf32Codepoints
    SourcePos = (number line, number byte_col, number utf16_col) unique
    SourceRange = (Moon2Source.DocUri uri, number start_offset, number stop_offset, Moon2Source.SourcePos start, Moon2Source.SourcePos stop) unique
    TextChange = ReplaceAll(string text) unique
               | ReplaceRange(Moon2Source.SourceRange range, string text) unique
    DocumentEdit = (Moon2Source.DocUri uri, Moon2Source.DocVersion version, Moon2Source.TextChange* changes) unique

    SourceSlice = (string text) unique
    SourceOccurrence = (Moon2Source.SourceSlice slice, Moon2Source.SourceRange range) unique

    AnchorId = (string text) unique
    AnchorKind = AnchorDocument
               | AnchorLuaOpaque
               | AnchorHostedIsland
               | AnchorIslandBody
               | AnchorKeyword
               | AnchorScalarType
               | AnchorStructName
               | AnchorFieldName
               | AnchorFieldUse
               | AnchorFunctionName
               | AnchorFunctionUse
               | AnchorMethodName
               | AnchorParamName
               | AnchorLocalName
               | AnchorBindingDef
               | AnchorBindingUse
               | AnchorRegionName
               | AnchorExprName
               | AnchorContinuationName
               | AnchorContinuationUse
               | AnchorBuiltinName
               | AnchorPackedAlign
               | AnchorDiagnostic
               | AnchorExposeName
               | AnchorModuleName
               | AnchorOpaque(string name) unique
    Anchor = (Moon2Source.AnchorId id, Moon2Source.AnchorKind kind, string label) unique
    AnchorSpan = (Moon2Source.AnchorId id, Moon2Source.AnchorKind kind, string label, Moon2Source.SourceRange range) unique
    AnchorSet = (Moon2Source.AnchorSpan* anchors) unique

    SourceLineSpan = (number line, number start_offset, number stop_offset, number next_offset) unique
    PositionIndex = (Moon2Source.DocumentSnapshot document, Moon2Source.SourceLineSpan* lines) unique
    SourceApplyIssue = SourceIssueWrongDocument(Moon2Source.DocUri expected, Moon2Source.DocUri actual) unique
                     | SourceIssueStaleVersion(Moon2Source.DocVersion expected_after, Moon2Source.DocVersion actual) unique
                     | SourceIssueInvalidRange(string reason) unique
                     | SourceIssueOverlappingRanges(Moon2Source.SourceRange previous, Moon2Source.SourceRange current) unique
                     | SourceIssueMixedReplaceAll
    SourceApplyResult = SourceApplyOk(Moon2Source.DocumentSnapshot document) unique
                      | SourceApplyRejected(Moon2Source.DocumentSnapshot document, Moon2Source.SourceApplyIssue* issues) unique
    SourcePositionResult = SourcePositionHit(Moon2Source.SourcePos pos) unique
                         | SourcePositionMiss(string reason) unique
    SourceOffsetResult = SourceOffsetHit(number offset) unique
                       | SourceOffsetMiss(string reason) unique

    AnchorIndex = (Moon2Source.AnchorSet set, Moon2Source.AnchorSpan* anchors) unique
    AnchorQuery = AnchorQueryPosition(Moon2Source.AnchorIndex index, Moon2Source.DocUri uri, number offset) unique
                | AnchorQueryRange(Moon2Source.AnchorIndex index, Moon2Source.SourceRange range) unique
                | AnchorQueryId(Moon2Source.AnchorIndex index, Moon2Source.AnchorId id) unique
    AnchorLookupResult = AnchorLookup(Moon2Source.AnchorSpan* anchors) unique
}

module Moon2Mlua {
    IslandKind = IslandStruct
               | IslandExpose
               | IslandFunc
               | IslandModule
               | IslandRegion
               | IslandExpr
    IslandName = IslandNamed(string name) unique
               | IslandAnonymous
               | IslandMalformedName(string text) unique
    IslandText = (Moon2Mlua.IslandKind kind, Moon2Mlua.IslandName name, Moon2Source.SourceSlice source) unique
    Segment = LuaOpaque(Moon2Source.SourceOccurrence occurrence) unique
            | HostedIsland(Moon2Mlua.IslandText island, Moon2Source.SourceRange range) unique
            | MalformedIsland(Moon2Mlua.IslandKind kind, Moon2Source.SourceOccurrence occurrence, string reason) unique
    DocumentParts = (Moon2Source.DocumentSnapshot document, Moon2Mlua.Segment* segments, Moon2Source.AnchorSet anchors) unique
    IslandParse = (Moon2Mlua.IslandText island, Moon2Host.HostDeclSet decls, Moon2Tree.Module module, Moon2Open.RegionFrag* region_frags, Moon2Open.ExprFrag* expr_frags, Moon2Parse.ParseIssue* issues, Moon2Source.AnchorSet anchors) unique
    DocumentParse = (Moon2Mlua.DocumentParts parts, Moon2Host.MluaParseResult combined, Moon2Mlua.IslandParse* islands, Moon2Source.AnchorSet anchors) unique
    DocumentAnalysis = (Moon2Mlua.DocumentParse parse, Moon2Host.MluaHostPipelineResult host, Moon2Open.ValidationReport open_report, Moon2Tree.TypeIssue* type_issues, Moon2Tree.ControlFact* control_facts, Moon2Vec.VecLoopDecision* vector_decisions, Moon2Vec.VecReject* vector_rejects, Moon2Back.BackValidationReport back_report, Moon2Source.AnchorSet anchors) unique
}

module Moon2Editor {
    ServerMode = ServerCreated
               | ServerInitializing
               | ServerReady
               | ServerShutdownRequested
               | ServerStopped
    ClientCapability = ClientCapability(string name, string value) unique
    WorkspaceRoot = (Moon2Source.DocUri uri) unique
    WorkspaceState = (Moon2Editor.ServerMode mode, Moon2Editor.WorkspaceRoot* roots, Moon2Editor.ClientCapability* capabilities, Moon2Source.DocumentSnapshot* open_docs) unique

    RpcId = RpcIdNone
          | RpcIdNumber(number value) unique
          | RpcIdString(string value) unique
    PositionQuery = (Moon2Source.DocUri uri, Moon2Source.DocVersion version, Moon2Source.SourcePos pos) unique
    RangeQuery = (Moon2Source.DocUri uri, Moon2Source.DocVersion version, Moon2Source.SourceRange range) unique
    ReferenceQuery = (Moon2Editor.PositionQuery position, boolean include_declaration) unique
    RenameQuery = (Moon2Editor.PositionQuery position, string new_name) unique
    CodeActionQuery = (Moon2Editor.RangeQuery range, Moon2Editor.DiagnosticFact* diagnostics) unique

    ClientEvent = ClientInitialize(Moon2Editor.RpcId id, Moon2Editor.WorkspaceRoot* roots, Moon2Editor.ClientCapability* capabilities) unique
                | ClientInitialized
                | ClientShutdown(Moon2Editor.RpcId id) unique
                | ClientExit
                | ClientDidOpen(Moon2Source.DocumentSnapshot document) unique
                | ClientDidChange(Moon2Source.DocumentEdit edit) unique
                | ClientDidClose(Moon2Source.DocUri uri) unique
                | ClientDidSave(Moon2Source.DocUri uri) unique
                | ClientHover(Moon2Editor.RpcId id, Moon2Editor.PositionQuery query) unique
                | ClientDefinition(Moon2Editor.RpcId id, Moon2Editor.PositionQuery query) unique
                | ClientReferences(Moon2Editor.RpcId id, Moon2Editor.ReferenceQuery query) unique
                | ClientDocumentHighlight(Moon2Editor.RpcId id, Moon2Editor.PositionQuery query) unique
                | ClientDocumentSymbol(Moon2Editor.RpcId id, Moon2Source.DocUri uri) unique
                | ClientWorkspaceSymbol(Moon2Editor.RpcId id, string query) unique
                | ClientDiagnostic(Moon2Editor.RpcId id, Moon2Source.DocUri uri) unique
                | ClientCompletion(Moon2Editor.RpcId id, Moon2Editor.PositionQuery query) unique
                | ClientSignatureHelp(Moon2Editor.RpcId id, Moon2Editor.PositionQuery query) unique
                | ClientSemanticTokensFull(Moon2Editor.RpcId id, Moon2Source.DocUri uri) unique
                | ClientSemanticTokensRange(Moon2Editor.RpcId id, Moon2Editor.RangeQuery query) unique
                | ClientPrepareRename(Moon2Editor.RpcId id, Moon2Editor.PositionQuery query) unique
                | ClientRename(Moon2Editor.RpcId id, Moon2Editor.RenameQuery query) unique
                | ClientCodeAction(Moon2Editor.RpcId id, Moon2Editor.CodeActionQuery query) unique
                | ClientFoldingRange(Moon2Editor.RpcId id, Moon2Source.DocUri uri) unique
                | ClientSelectionRange(Moon2Editor.RpcId id, Moon2Editor.PositionQuery* positions) unique
                | ClientInlayHint(Moon2Editor.RpcId id, Moon2Editor.RangeQuery query) unique
                | ClientUnsupported(Moon2Editor.RpcId id, string method) unique
                | ClientIgnoredNotification(string method) unique
    Transition = (Moon2Editor.WorkspaceState before, Moon2Editor.ClientEvent event, Moon2Editor.WorkspaceState after) unique

    DiagnosticSeverity = DiagnosticError
                       | DiagnosticWarning
                       | DiagnosticInformation
                       | DiagnosticHint
    DiagnosticOrigin = DiagFromParse(Moon2Parse.ParseIssue issue) unique
                     | DiagFromHost(Moon2Host.HostIssue issue) unique
                     | DiagFromOpen(Moon2Open.ValidationIssue issue) unique
                     | DiagFromType(Moon2Tree.TypeIssue issue) unique
                     | DiagFromBack(Moon2Back.BackValidationIssue issue) unique
                     | DiagFromVectorReject(Moon2Vec.VecReject reject) unique
                     | DiagFromBindingResolution(Moon2Editor.BindingResolution resolution) unique
                     | DiagFromSource(Moon2Source.SourceApplyIssue issue) unique
                     | DiagFromTransport(string code, string message) unique
    DiagnosticFact = (Moon2Editor.DiagnosticSeverity severity, Moon2Editor.DiagnosticOrigin origin, string code, string message, Moon2Source.SourceRange range) unique

    Subject = SubjectKeyword(string text) unique
            | SubjectScalar(Moon2Core.Scalar scalar) unique
            | SubjectType(Moon2Type.Type ty) unique
            | SubjectHostStruct(Moon2Host.HostStructDecl decl) unique
            | SubjectHostField(Moon2Host.HostStructDecl owner, Moon2Host.HostFieldDecl field) unique
            | SubjectHostExpose(Moon2Host.HostExposeDecl decl) unique
            | SubjectHostAccessor(Moon2Host.HostAccessorDecl decl) unique
            | SubjectTreeFunc(Moon2Tree.Func func) unique
            | SubjectTreeModule(Moon2Tree.Module module) unique
            | SubjectRegionFrag(Moon2Open.RegionFrag frag) unique
            | SubjectExprFrag(Moon2Open.ExprFrag frag) unique
            | SubjectBinding(Moon2Bind.Binding binding) unique
            | SubjectContinuation(Moon2Source.AnchorId scope, Moon2Tree.BlockLabel label) unique
            | SubjectBuiltin(string name) unique
            | SubjectDiagnostic(Moon2Editor.DiagnosticFact diagnostic) unique
            | SubjectMissing(string reason) unique
    SubjectPick = (Moon2Editor.PositionQuery query, Moon2Source.AnchorSpan* anchors, Moon2Editor.Subject subject) unique

    SymbolKind = SymFile
               | SymModule
               | SymNamespace
               | SymPackage
               | SymClass
               | SymMethod
               | SymProperty
               | SymField
               | SymConstructor
               | SymEnum
               | SymInterface
               | SymFunction
               | SymVariable
               | SymConstant
               | SymString
               | SymNumber
               | SymBoolean
               | SymArray
               | SymObject
               | SymKey
               | SymNull
               | SymEnumMember
               | SymStruct
               | SymEvent
               | SymOperator
               | SymTypeParameter
    SymbolId = (string text) unique
    SymbolFact = (Moon2Editor.SymbolId id, Moon2Editor.SymbolId parent, string name, Moon2Editor.SymbolKind kind, string detail, Moon2Source.SourceRange range, Moon2Source.SourceRange selection_range, Moon2Editor.Subject subject) unique
    SymbolTree = (Moon2Editor.SymbolFact* symbols) unique

    BindingRole = BindingDef
                | BindingUse
                | BindingRead
                | BindingWrite
                | BindingCall
                | BindingTypeUse
    BindingScopeId = (string text) unique
    BindingScopeKind = BindingScopeDocument
                     | BindingScopeIsland
                     | BindingScopeFunction
                     | BindingScopeRegion
                     | BindingScopeExpr
                     | BindingScopeControlBlock
                     | BindingScopeBranch
                     | BindingScopeModule
                     | BindingScopeOpaque(string name) unique
    BindingScopeFact = (Moon2Editor.BindingScopeId id, Moon2Editor.BindingScopeId parent, Moon2Editor.BindingScopeKind kind, Moon2Source.SourceRange range) unique
    ScopedBinding = (Moon2Bind.Binding binding, Moon2Editor.BindingScopeId scope, Moon2Source.SourceRange visible_range, Moon2Source.AnchorSpan anchor) unique
    BindingUseSite = (Moon2Source.AnchorSpan anchor, Moon2Editor.BindingRole role, Moon2Editor.BindingScopeId scope) unique
    BindingResolution = BindingResolved(Moon2Editor.BindingUseSite use, Moon2Editor.ScopedBinding binding) unique
                      | BindingUnresolved(Moon2Editor.BindingUseSite use, string reason) unique
    BindingScopeReport = (Moon2Editor.BindingScopeFact* scopes, Moon2Editor.ScopedBinding* bindings, Moon2Editor.BindingResolution* resolutions) unique
    BindingFact = (Moon2Editor.SymbolId id, Moon2Editor.BindingRole role, Moon2Editor.Subject subject, Moon2Source.AnchorSpan anchor) unique
    DefinitionResult = DefinitionHit(Moon2Editor.Subject subject, Moon2Source.SourceRange* ranges) unique
                     | DefinitionMiss(string reason) unique
    ReferenceResult = ReferenceHit(Moon2Editor.Subject subject, Moon2Source.SourceRange* ranges) unique
                    | ReferenceMiss(string reason) unique
    DocumentHighlightKind = HighlightText
                          | HighlightRead
                          | HighlightWrite
    DocumentHighlight = (Moon2Source.SourceRange range, Moon2Editor.DocumentHighlightKind kind) unique
    RenameEdit = (Moon2Source.SourceRange range, string new_text) unique
    RenameResult = RenameOk(Moon2Editor.RenameEdit* edits) unique
                 | RenameRejected(string reason) unique
    PrepareRenameResult = PrepareRenameOk(Moon2Source.SourceRange range, string placeholder) unique
                        | PrepareRenameRejected(string reason) unique

    MarkupKind = MarkupPlainText
               | MarkupMarkdown
    HoverInfo = HoverInfo(Moon2Editor.MarkupKind kind, string value, Moon2Source.SourceRange range) unique
              | HoverMissing(string reason) unique

    CompletionContext = CompletionTopLevel
                      | CompletionModuleItem
                      | CompletionStructField
                      | CompletionTypePosition
                      | CompletionExprPosition
                      | CompletionPlacePosition
                      | CompletionExposeSubject
                      | CompletionExposeTarget
                      | CompletionExposeMode
                      | CompletionRegionStatement
                      | CompletionContinuationArgs
                      | CompletionBuiltinPath
                      | CompletionLuaOpaque
                      | CompletionInvalid(string reason) unique
    CompletionKind = CompletionText
                   | CompletionMethod
                   | CompletionFunction
                   | CompletionConstructor
                   | CompletionField
                   | CompletionVariable
                   | CompletionClass
                   | CompletionInterface
                   | CompletionModule
                   | CompletionProperty
                   | CompletionUnit
                   | CompletionValue
                   | CompletionEnum
                   | CompletionKeyword
                   | CompletionSnippet
                   | CompletionColor
                   | CompletionFile
                   | CompletionReference
                   | CompletionFolder
                   | CompletionEnumMember
                   | CompletionConstant
                   | CompletionStruct
                   | CompletionEvent
                   | CompletionOperator
                   | CompletionTypeParameter
    CompletionQuery = (Moon2Editor.PositionQuery position, Moon2Editor.CompletionContext context) unique
    CompletionItem = (string label, Moon2Editor.CompletionKind kind, string detail, string documentation, string insert_text) unique
    SignatureContext = SignatureCall(string callee, number active_parameter, Moon2Source.SourceRange callee_range) unique
                     | SignatureNoCall(string reason) unique
    SignatureParameter = (string label, string documentation) unique
    SignatureInfo = (string label, string documentation, Moon2Editor.SignatureParameter* params) unique
    SignatureHelp = SignatureHelp(Moon2Editor.SignatureInfo* signatures, number active_signature, number active_parameter) unique
                  | SignatureHelpMissing(string reason) unique

    SemanticTokenType = TokNamespace
                      | TokType
                      | TokClass
                      | TokEnum
                      | TokInterface
                      | TokStruct
                      | TokTypeParameter
                      | TokParameter
                      | TokVariable
                      | TokProperty
                      | TokEnumMember
                      | TokEvent
                      | TokFunction
                      | TokMethod
                      | TokMacro
                      | TokKeyword
                      | TokModifier
                      | TokComment
                      | TokString
                      | TokNumber
                      | TokRegexp
                      | TokOperator
                      | TokDecorator
    SemanticTokenModifier = TokModDeclaration
                          | TokModDefinition
                          | TokModReadonly
                          | TokModStatic
                          | TokModDeprecated
                          | TokModAbstract
                          | TokModAsync
                          | TokModModification
                          | TokModDocumentation
                          | TokModDefaultLibrary
                          | TokModMutable
                          | TokModExported
                          | TokModStorage
                          | TokModDiagnostic
    SemanticTokenSpan = (Moon2Source.SourceRange range, Moon2Editor.SemanticTokenType token_type, Moon2Editor.SemanticTokenModifier* modifiers) unique

    CodeActionKind = CodeActionQuickFix
                   | CodeActionRefactor
                   | CodeActionSource
                   | CodeActionOrganizeImports
    TextEdit = (Moon2Source.SourceRange range, string new_text) unique
    WorkspaceEdit = (Moon2Editor.TextEdit* edits) unique
    CodeAction = (string title, Moon2Editor.CodeActionKind kind, Moon2Editor.DiagnosticFact* diagnostics, Moon2Editor.WorkspaceEdit edit) unique
    FoldingRange = (Moon2Source.SourceRange range, string kind) unique
    SelectionRange = (Moon2Source.SourceRange range, Moon2Source.SourceRange* parents) unique
    InlayHint = (Moon2Source.SourcePos pos, string label, string kind) unique
}

module Moon2Lsp {
    ProtocolPosition = (number line, number character) unique
    ProtocolRange = (Moon2Lsp.ProtocolPosition start, Moon2Lsp.ProtocolPosition stop) unique
    Location = (Moon2Source.DocUri uri, Moon2Lsp.ProtocolRange range) unique
    InitializeResult = (string server_name, string position_encoding, string capabilities_json) unique
    DiagnosticPayload = (Moon2Lsp.ProtocolRange range, number severity, string code, string message) unique
    DiagnosticReport = (Moon2Source.DocUri uri, Moon2Source.DocVersion version, Moon2Lsp.DiagnosticPayload* diagnostics) unique
    DiagnosticDocumentReport = (string kind, Moon2Lsp.DiagnosticPayload* items) unique
    Hover = Hover(Moon2Editor.MarkupKind kind, string value, Moon2Lsp.ProtocolRange range) unique
          | HoverNull
    CompletionPayload = (string label, number kind, string detail, string documentation, string insert_text) unique
    CompletionList = (boolean incomplete, Moon2Lsp.CompletionPayload* items) unique
    DocumentSymbolPayload = (string name, string detail, number kind, Moon2Lsp.ProtocolRange range, Moon2Lsp.ProtocolRange selection_range, Moon2Lsp.DocumentSymbolPayload* children) unique
    WorkspaceSymbolPayload = (string name, string detail, number kind, Moon2Lsp.Location location, string container_name) unique
    SignatureParameterPayload = (string label, string documentation) unique
    SignatureInformationPayload = (string label, string documentation, Moon2Lsp.SignatureParameterPayload* params) unique
    SignatureHelpPayload = (Moon2Lsp.SignatureInformationPayload* signatures, number active_signature, number active_parameter) unique
    SemanticTokens = (number* data) unique
    DocumentHighlightPayload = (Moon2Lsp.ProtocolRange range, number kind) unique
    PrepareRenamePayload = (Moon2Lsp.ProtocolRange range, string placeholder) unique
    TextEditPayload = (Moon2Lsp.ProtocolRange range, string new_text) unique
    WorkspaceEditPayload = (Moon2Source.DocUri uri, Moon2Lsp.TextEditPayload* edits) unique
    CodeActionPayload = (string title, string kind, Moon2Lsp.DiagnosticPayload* diagnostics, Moon2Lsp.WorkspaceEditPayload* edits) unique
    FoldingRangePayload = (number start_line, number start_character, number end_line, number end_character, string kind) unique
    SelectionRangePayload = (Moon2Lsp.ProtocolRange range, Moon2Lsp.SelectionRangePayload* parents) unique
    InlayHintPayload = (Moon2Lsp.ProtocolPosition position, string label, string kind) unique
    Payload = PayloadNull
            | PayloadInitialize(Moon2Lsp.InitializeResult result) unique
            | PayloadDiagnostics(Moon2Lsp.DiagnosticReport report) unique
            | PayloadDiagnosticDocumentReport(Moon2Lsp.DiagnosticDocumentReport report) unique
            | PayloadHover(Moon2Lsp.Hover hover) unique
            | PayloadCompletion(Moon2Lsp.CompletionList completion) unique
            | PayloadDocumentSymbols(Moon2Lsp.DocumentSymbolPayload* symbols) unique
            | PayloadWorkspaceSymbols(Moon2Lsp.WorkspaceSymbolPayload* symbols) unique
            | PayloadSignatureHelp(Moon2Lsp.SignatureHelpPayload help) unique
            | PayloadLocations(Moon2Lsp.Location* locations) unique
            | PayloadDocumentHighlights(Moon2Lsp.DocumentHighlightPayload* highlights) unique
            | PayloadPrepareRename(Moon2Lsp.PrepareRenamePayload result) unique
            | PayloadSemanticTokens(Moon2Lsp.SemanticTokens tokens) unique
            | PayloadWorkspaceEdit(Moon2Lsp.WorkspaceEditPayload* edits) unique
            | PayloadCodeActions(Moon2Lsp.CodeActionPayload* actions) unique
            | PayloadFoldingRanges(Moon2Lsp.FoldingRangePayload* ranges) unique
            | PayloadSelectionRanges(Moon2Lsp.SelectionRangePayload* ranges) unique
            | PayloadInlayHints(Moon2Lsp.InlayHintPayload* hints) unique
            | PayloadError(string code, string message) unique
}

module Moon2Rpc {
    JsonMember = (string key, Moon2Rpc.JsonValue value) unique
    JsonValue = JsonNull
              | JsonBool(boolean value) unique
              | JsonNumber(string raw) unique
              | JsonString(string value) unique
              | JsonArray(Moon2Rpc.JsonValue* values) unique
              | JsonObject(Moon2Rpc.JsonMember* members) unique
    Incoming = RpcRequest(Moon2Editor.RpcId id, string method, Moon2Rpc.JsonValue params) unique
             | RpcIncomingNotification(string method, Moon2Rpc.JsonValue params) unique
             | RpcInvalid(string reason) unique
    Outgoing = RpcResult(Moon2Editor.RpcId id, Moon2Lsp.Payload payload) unique
             | RpcError(Moon2Editor.RpcId id, number code, string message) unique
             | RpcOutgoingNotification(string method, Moon2Lsp.Payload payload) unique
    OutCommand = SendMessage(Moon2Rpc.Outgoing outgoing) unique
               | LogMessage(string level, string message) unique
               | StopServer
}
]]

function M.Define(T)
    T:Define(M.SCHEMA)
    return T
end

return M
