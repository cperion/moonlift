local M = {}

M.SCHEMA = [[
module MoonliftSurface {
    SurfName = (string text) unique
    SurfPath = (MoonliftSurface.SurfName* parts) unique

    SurfIntrinsic = SurfPopcount
                  | SurfClz
                  | SurfCtz
                  | SurfRotl
                  | SurfRotr
                  | SurfBswap
                  | SurfFma
                  | SurfSqrt
                  | SurfAbs
                  | SurfFloor
                  | SurfCeil
                  | SurfTruncFloat
                  | SurfRound
                  | SurfTrap
                  | SurfAssume

    SurfTypeExpr = SurfTVoid
                 | SurfTBool
                 | SurfTI8 | SurfTI16 | SurfTI32 | SurfTI64
                 | SurfTU8 | SurfTU16 | SurfTU32 | SurfTU64
                 | SurfTF32 | SurfTF64
                 | SurfTIndex
                 | SurfTPtr(MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTArray(MoonliftSurface.SurfExpr count, MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTSlice(MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTView(MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTFunc(MoonliftSurface.SurfTypeExpr* params, MoonliftSurface.SurfTypeExpr result) unique
                 | SurfTClosure(MoonliftSurface.SurfTypeExpr* params, MoonliftSurface.SurfTypeExpr result) unique
                 | SurfTNamed(MoonliftSurface.SurfPath path) unique

    SurfParam = (string name, MoonliftSurface.SurfTypeExpr ty) unique
    SurfFieldDecl = (string field_name, MoonliftSurface.SurfTypeExpr ty) unique
    SurfVariant = (string name, MoonliftSurface.SurfTypeExpr payload) unique
    SurfFieldInit = (string name, MoonliftSurface.SurfExpr value) unique
    SurfSwitchStmtArm = (MoonliftSurface.SurfExpr key, MoonliftSurface.SurfStmt* body) unique
    SurfSwitchExprArm = (MoonliftSurface.SurfExpr key, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfExpr result) unique
    SurfLoopCarryInit = (string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr init) unique
    SurfLoopUpdate = (string name, MoonliftSurface.SurfExpr value) unique

    SurfPlace = SurfPlaceName(string name) unique
              | SurfPlacePath(MoonliftSurface.SurfPath path) unique
              | SurfPlaceDeref(MoonliftSurface.SurfExpr base) unique
              | SurfPlaceDot(MoonliftSurface.SurfPlace base, string name) unique
              | SurfPlaceField(MoonliftSurface.SurfPlace base, string name) unique
              | SurfPlaceIndex(MoonliftSurface.SurfExpr base, MoonliftSurface.SurfExpr index) unique

    SurfDomainExpr = SurfDomainRange(MoonliftSurface.SurfExpr stop) unique
                   | SurfDomainRange2(MoonliftSurface.SurfExpr start, MoonliftSurface.SurfExpr stop) unique
                   | SurfDomainZipEq(MoonliftSurface.SurfExpr* values) unique
                   | SurfDomainValue(MoonliftSurface.SurfExpr value) unique

    SurfLoopStmt = SurfStmtLoopWhile(MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopUpdate* next) unique
                 | SurfStmtLoopOver(string index_name, MoonliftSurface.SurfDomainExpr domain, MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopUpdate* next) unique

    SurfLoopExpr = SurfExprLoopWhile(MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfTypeExpr result_ty, MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopUpdate* next, MoonliftSurface.SurfExpr result) unique
                 | SurfExprLoopOver(string index_name, MoonliftSurface.SurfDomainExpr domain, MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfTypeExpr result_ty, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopUpdate* next, MoonliftSurface.SurfExpr result) unique

    SurfExpr = SurfInt(string raw) unique
             | SurfFloat(string raw) unique
             | SurfBool(boolean value) unique
             | SurfNil
             | SurfNameRef(string name) unique
             | SurfPathRef(MoonliftSurface.SurfPath path) unique
             | SurfExprDot(MoonliftSurface.SurfExpr base, string name) unique
             | SurfExprNeg(MoonliftSurface.SurfExpr value) unique
             | SurfExprNot(MoonliftSurface.SurfExpr value) unique
             | SurfExprBNot(MoonliftSurface.SurfExpr value) unique
             | SurfExprRef(MoonliftSurface.SurfPlace place) unique
             | SurfExprDeref(MoonliftSurface.SurfExpr value) unique
             | SurfExprAdd(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprSub(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprMul(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprDiv(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprRem(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprEq(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprNe(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprLt(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprLe(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprGt(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprGe(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprAnd(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprOr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprBitAnd(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprBitOr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprBitXor(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprShl(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprLShr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprAShr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprCastTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprTruncTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprZExtTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprSExtTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprBitcastTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprSatCastTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprIntrinsicCall(MoonliftSurface.SurfIntrinsic op, MoonliftSurface.SurfExpr* args) unique
             | SurfCall(MoonliftSurface.SurfExpr callee, MoonliftSurface.SurfExpr* args) unique
             | SurfField(MoonliftSurface.SurfExpr base, string name) unique
             | SurfIndex(MoonliftSurface.SurfExpr base, MoonliftSurface.SurfExpr index) unique
             | SurfAgg(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfFieldInit* fields) unique
             | SurfArrayLit(MoonliftSurface.SurfTypeExpr elem_ty, MoonliftSurface.SurfExpr* elems) unique
             | SurfIfExpr(MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfExpr then_expr, MoonliftSurface.SurfExpr else_expr) unique
             | SurfSelectExpr(MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfExpr then_expr, MoonliftSurface.SurfExpr else_expr) unique
             | SurfSwitchExpr(MoonliftSurface.SurfExpr value, MoonliftSurface.SurfSwitchExprArm* arms, MoonliftSurface.SurfExpr default_expr) unique
             | SurfExprLoop(MoonliftSurface.SurfLoopExpr loop) unique
             | SurfBlockExpr(MoonliftSurface.SurfStmt* stmts, MoonliftSurface.SurfExpr result) unique
             | SurfClosureExpr(MoonliftSurface.SurfParam* params, MoonliftSurface.SurfTypeExpr result, MoonliftSurface.SurfStmt* body) unique
             | SurfExprView(MoonliftSurface.SurfExpr base) unique
             | SurfExprViewWindow(MoonliftSurface.SurfExpr base, MoonliftSurface.SurfExpr start, MoonliftSurface.SurfExpr len) unique
             | SurfExprViewFromPtr(MoonliftSurface.SurfExpr ptr, MoonliftSurface.SurfExpr len) unique
             | SurfExprViewFromPtrStrided(MoonliftSurface.SurfExpr ptr, MoonliftSurface.SurfExpr len, MoonliftSurface.SurfExpr stride) unique
             | SurfExprViewStrided(MoonliftSurface.SurfExpr base, MoonliftSurface.SurfExpr stride) unique
             | SurfExprViewInterleaved(MoonliftSurface.SurfExpr base, MoonliftSurface.SurfExpr stride, MoonliftSurface.SurfExpr lane) unique

    SurfStmt = SurfLet(string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr init) unique
             | SurfVar(string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr init) unique
             | SurfSet(MoonliftSurface.SurfPlace place, MoonliftSurface.SurfExpr value) unique
             | SurfExprStmt(MoonliftSurface.SurfExpr expr) unique
             | SurfAssert(MoonliftSurface.SurfExpr cond) unique
             | SurfIf(MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfStmt* then_body, MoonliftSurface.SurfStmt* else_body) unique
             | SurfSwitch(MoonliftSurface.SurfExpr value, MoonliftSurface.SurfSwitchStmtArm* arms, MoonliftSurface.SurfStmt* default_body) unique
             | SurfReturnVoid
             | SurfReturnValue(MoonliftSurface.SurfExpr value) unique
             | SurfBreak
             | SurfBreakValue(MoonliftSurface.SurfExpr value) unique
             | SurfContinue
             | SurfStmtLoop(MoonliftSurface.SurfLoopStmt loop) unique

    SurfFunc = SurfFuncLocal(string name, MoonliftSurface.SurfParam* params, MoonliftSurface.SurfTypeExpr result, MoonliftSurface.SurfStmt* body) unique
             | SurfFuncExport(string name, MoonliftSurface.SurfParam* params, MoonliftSurface.SurfTypeExpr result, MoonliftSurface.SurfStmt* body) unique
    SurfExternFunc = (string name, string symbol, MoonliftSurface.SurfParam* params, MoonliftSurface.SurfTypeExpr result) unique
    SurfConst = (string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
    SurfStatic = (string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
    SurfImport = (MoonliftSurface.SurfPath path) unique
    SurfTypeDecl = SurfStruct(string name, MoonliftSurface.SurfFieldDecl* fields) unique
                 | SurfEnum(string name, MoonliftSurface.SurfName* variants) unique
                 | SurfTaggedUnion(string name, MoonliftSurface.SurfVariant* variants) unique
                 | SurfUnion(string name, MoonliftSurface.SurfFieldDecl* fields) unique

    SurfItem = SurfItemFunc(MoonliftSurface.SurfFunc func) unique
             | SurfItemExtern(MoonliftSurface.SurfExternFunc func) unique
             | SurfItemConst(MoonliftSurface.SurfConst c) unique
             | SurfItemStatic(MoonliftSurface.SurfStatic s) unique
             | SurfItemImport(MoonliftSurface.SurfImport imp) unique
             | SurfItemType(MoonliftSurface.SurfTypeDecl t) unique

    SurfModule = (MoonliftSurface.SurfItem* items) unique
}

module MoonliftElab {
    ElabIntrinsic = ElabPopcount
                  | ElabClz
                  | ElabCtz
                  | ElabRotl
                  | ElabRotr
                  | ElabBswap
                  | ElabFma
                  | ElabSqrt
                  | ElabAbs
                  | ElabFloor
                  | ElabCeil
                  | ElabTruncFloat
                  | ElabRound
                  | ElabTrap
                  | ElabAssume

    ElabType = ElabTVoid
             | ElabTBool
             | ElabTI8 | ElabTI16 | ElabTI32 | ElabTI64
             | ElabTU8 | ElabTU16 | ElabTU32 | ElabTU64
             | ElabTF32 | ElabTF64
             | ElabTIndex
             | ElabTPtr(MoonliftElab.ElabType elem) unique
             | ElabTArray(MoonliftElab.ElabExpr count, MoonliftElab.ElabType elem) unique
             | ElabTSlice(MoonliftElab.ElabType elem) unique
             | ElabTView(MoonliftElab.ElabType elem) unique
             | ElabTFunc(MoonliftElab.ElabType* params, MoonliftElab.ElabType result) unique
             | ElabTNamed(string module_name, string type_name) unique

    ElabBinding = ElabLocalValue(string id, string name, MoonliftElab.ElabType ty) unique
                | ElabLocalCell(string id, string name, MoonliftElab.ElabType ty) unique
                | ElabArg(number index, string name, MoonliftElab.ElabType ty) unique
                | ElabLoopCarry(string loop_id, string port_id, string name, MoonliftElab.ElabType ty) unique
                | ElabLoopIndex(string loop_id, string name, MoonliftElab.ElabType ty) unique
                | ElabGlobalFunc(string module_name, string item_name, MoonliftElab.ElabType ty) unique
                | ElabGlobalConst(string module_name, string item_name, MoonliftElab.ElabType ty) unique
                | ElabGlobalStatic(string module_name, string item_name, MoonliftElab.ElabType ty) unique
                | ElabExtern(string symbol, MoonliftElab.ElabType ty) unique

    ElabValueEntry = (string name, MoonliftElab.ElabBinding binding) unique
    ElabTypeEntry = (string name, MoonliftElab.ElabType ty) unique
    ElabFieldType = (string field_name, MoonliftElab.ElabType ty) unique
    ElabTypeLayout = ElabLayoutNamed(string module_name, string type_name, MoonliftElab.ElabFieldType* fields) unique
    ElabEnv = (string module_name, MoonliftElab.ElabValueEntry* values, MoonliftElab.ElabTypeEntry* types, MoonliftElab.ElabTypeLayout* layouts) unique
    ElabConstEntry = (string module_name, string item_name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
    ElabConstEnv = (MoonliftElab.ElabConstEntry* entries) unique
    ElabStmtEnvEffect = ElabNoBinding
                      | ElabAddBinding(MoonliftElab.ElabValueEntry entry) unique
                      | ElabAddBindings(MoonliftElab.ElabValueEntry* entries) unique

    ElabParam = (string name, MoonliftElab.ElabType ty) unique
    ElabFieldInit = (string name, MoonliftElab.ElabExpr value) unique
    ElabSwitchStmtArm = (MoonliftElab.ElabExpr key, MoonliftElab.ElabStmt* body) unique
    ElabSwitchExprArm = (MoonliftElab.ElabExpr key, MoonliftElab.ElabStmt* body, MoonliftElab.ElabExpr result) unique
    ElabCarryPort = (string port_id, string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr init) unique
    ElabIndexPort = (string name, MoonliftElab.ElabType ty) unique
    ElabCarryUpdate = (string port_id, MoonliftElab.ElabExpr value) unique

    ElabPlace = ElabPlaceBinding(MoonliftElab.ElabBinding binding) unique
              | ElabPlaceDeref(MoonliftElab.ElabExpr base, MoonliftElab.ElabType elem) unique
              | ElabPlaceField(MoonliftElab.ElabPlace base, string name, MoonliftElab.ElabType ty) unique
              | ElabPlaceIndex(MoonliftElab.ElabIndexBase base, MoonliftElab.ElabExpr index, MoonliftElab.ElabType ty) unique

    ElabIndexBase = ElabIndexBasePlace(MoonliftElab.ElabPlace base, MoonliftElab.ElabType elem) unique
                  | ElabIndexBaseView(MoonliftElab.ElabExpr base, MoonliftElab.ElabType elem) unique

    ElabDomain = ElabDomainRange(MoonliftElab.ElabExpr stop) unique
               | ElabDomainRange2(MoonliftElab.ElabExpr start, MoonliftElab.ElabExpr stop) unique
               | ElabDomainZipEq(MoonliftElab.ElabExpr* values) unique
               | ElabDomainValue(MoonliftElab.ElabExpr value) unique

    ElabExprExit = ElabExprEndOnly
                 | ElabExprEndOrBreakValue

    ElabOperandContext = ElabOperandNeedsExpected
                       | ElabOperandHasNaturalType

    ElabLoop = ElabWhileStmt(string loop_id, MoonliftElab.ElabCarryPort* carries, MoonliftElab.ElabExpr cond, MoonliftElab.ElabStmt* body, MoonliftElab.ElabCarryUpdate* next) unique
             | ElabOverStmt(string loop_id, MoonliftElab.ElabIndexPort index_port, MoonliftElab.ElabDomain domain, MoonliftElab.ElabCarryPort* carries, MoonliftElab.ElabStmt* body, MoonliftElab.ElabCarryUpdate* next) unique
             | ElabWhileExpr(string loop_id, MoonliftElab.ElabCarryPort* carries, MoonliftElab.ElabExpr cond, MoonliftElab.ElabStmt* body, MoonliftElab.ElabCarryUpdate* next, MoonliftElab.ElabExprExit exit, MoonliftElab.ElabExpr result) unique
             | ElabOverExpr(string loop_id, MoonliftElab.ElabIndexPort index_port, MoonliftElab.ElabDomain domain, MoonliftElab.ElabCarryPort* carries, MoonliftElab.ElabStmt* body, MoonliftElab.ElabCarryUpdate* next, MoonliftElab.ElabExprExit exit, MoonliftElab.ElabExpr result) unique

    ElabExpr = ElabInt(string raw, MoonliftElab.ElabType ty) unique
             | ElabFloat(string raw, MoonliftElab.ElabType ty) unique
             | ElabBool(boolean value, MoonliftElab.ElabType ty) unique
             | ElabNil(MoonliftElab.ElabType ty) unique
             | ElabBindingExpr(MoonliftElab.ElabBinding binding) unique
             | ElabExprNeg(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprNot(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprBNot(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprAddrOf(MoonliftElab.ElabPlace place, MoonliftElab.ElabType ty) unique
             | ElabExprDeref(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprAdd(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprSub(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprMul(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprDiv(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprRem(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprEq(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprNe(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprLt(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprLe(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprGt(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprGe(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprAnd(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprOr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprBitAnd(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprBitOr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprBitXor(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprShl(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprLShr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprAShr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprCastTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprTruncTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprZExtTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprSExtTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprBitcastTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprSatCastTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprIntrinsicCall(MoonliftElab.ElabIntrinsic op, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr* args) unique
             | ElabCall(MoonliftElab.ElabExpr callee, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr* args) unique
             | ElabField(MoonliftElab.ElabExpr base, string name, MoonliftElab.ElabType ty) unique
             | ElabIndex(MoonliftElab.ElabIndexBase base, MoonliftElab.ElabExpr index, MoonliftElab.ElabType ty) unique
             | ElabAgg(MoonliftElab.ElabType ty, MoonliftElab.ElabFieldInit* fields) unique
             | ElabArrayLit(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr* elems) unique
             | ElabIfExpr(MoonliftElab.ElabExpr cond, MoonliftElab.ElabExpr then_expr, MoonliftElab.ElabExpr else_expr, MoonliftElab.ElabType ty) unique
             | ElabSelectExpr(MoonliftElab.ElabExpr cond, MoonliftElab.ElabExpr then_expr, MoonliftElab.ElabExpr else_expr, MoonliftElab.ElabType ty) unique
             | ElabSwitchExpr(MoonliftElab.ElabExpr value, MoonliftElab.ElabSwitchExprArm* arms, MoonliftElab.ElabExpr default_expr, MoonliftElab.ElabType ty) unique
             | ElabExprLoop(MoonliftElab.ElabLoop loop, MoonliftElab.ElabType ty) unique
             | ElabBlockExpr(MoonliftElab.ElabStmt* stmts, MoonliftElab.ElabExpr result, MoonliftElab.ElabType ty) unique
             | ElabExprView(MoonliftElab.ElabExpr base, MoonliftElab.ElabType ty) unique
             | ElabExprViewWindow(MoonliftElab.ElabExpr base, MoonliftElab.ElabExpr start, MoonliftElab.ElabExpr len, MoonliftElab.ElabType ty) unique
             | ElabExprViewFromPtr(MoonliftElab.ElabExpr ptr, MoonliftElab.ElabExpr len, MoonliftElab.ElabType ty) unique
             | ElabExprViewFromPtrStrided(MoonliftElab.ElabExpr ptr, MoonliftElab.ElabExpr len, MoonliftElab.ElabExpr stride, MoonliftElab.ElabType ty) unique
             | ElabExprViewStrided(MoonliftElab.ElabExpr base, MoonliftElab.ElabExpr stride, MoonliftElab.ElabType ty) unique
             | ElabExprViewInterleaved(MoonliftElab.ElabExpr base, MoonliftElab.ElabExpr stride, MoonliftElab.ElabExpr lane, MoonliftElab.ElabType ty) unique

    ElabStmt = ElabLet(string id, string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr init) unique
             | ElabVar(string id, string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr init) unique
             | ElabSet(MoonliftElab.ElabPlace place, MoonliftElab.ElabExpr value) unique
             | ElabExprStmt(MoonliftElab.ElabExpr expr) unique
             | ElabAssert(MoonliftElab.ElabExpr cond) unique
             | ElabIf(MoonliftElab.ElabExpr cond, MoonliftElab.ElabStmt* then_body, MoonliftElab.ElabStmt* else_body) unique
             | ElabSwitch(MoonliftElab.ElabExpr value, MoonliftElab.ElabSwitchStmtArm* arms, MoonliftElab.ElabStmt* default_body) unique
             | ElabReturnVoid
             | ElabReturnValue(MoonliftElab.ElabExpr value) unique
             | ElabBreak
             | ElabBreakValue(MoonliftElab.ElabExpr value) unique
             | ElabContinue
             | ElabStmtLoop(MoonliftElab.ElabLoop loop) unique

    ElabFunc = ElabFuncLocal(string name, MoonliftElab.ElabParam* params, MoonliftElab.ElabType result, MoonliftElab.ElabStmt* body) unique
             | ElabFuncExport(string name, MoonliftElab.ElabParam* params, MoonliftElab.ElabType result, MoonliftElab.ElabStmt* body) unique
    ElabExternFunc = (string name, string symbol, MoonliftElab.ElabParam* params, MoonliftElab.ElabType result) unique
    ElabConst = (string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
    ElabStatic = (string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
    ElabImport = (string module_name) unique
    ElabTypeDecl = ElabStruct(string name, MoonliftElab.ElabFieldType* fields) unique
                 | ElabUnion(string name, MoonliftElab.ElabFieldType* fields) unique

    ElabItem = ElabItemFunc(MoonliftElab.ElabFunc func) unique
             | ElabItemExtern(MoonliftElab.ElabExternFunc func) unique
             | ElabItemConst(MoonliftElab.ElabConst c) unique
             | ElabItemStatic(MoonliftElab.ElabStatic s) unique
             | ElabItemImport(MoonliftElab.ElabImport imp) unique
             | ElabItemType(MoonliftElab.ElabTypeDecl t) unique

    ElabModule = (string module_name, MoonliftElab.ElabItem* items) unique
}

module MoonliftMeta {
    MetaModuleName = MetaModuleNameOpen
                   | MetaModuleNameFixed(string module_name) unique

    MetaIntrinsic = MetaPopcount
                  | MetaClz
                  | MetaCtz
                  | MetaRotl
                  | MetaRotr
                  | MetaBswap
                  | MetaFma
                  | MetaSqrt
                  | MetaAbs
                  | MetaFloor
                  | MetaCeil
                  | MetaTruncFloat
                  | MetaRound
                  | MetaTrap
                  | MetaAssume

    MetaTypeSym = (string key, string name) unique
    MetaFuncSym = (string key, string name) unique
    MetaExternSym = (string key, string name, string symbol) unique
    MetaConstSym = (string key, string name) unique
    MetaStaticSym = (string key, string name) unique

    MetaTypeSlot = (string key, string pretty_name) unique
    MetaExprSlot = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaPlaceSlot = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaDomainSlot = (string key, string pretty_name) unique
    MetaRegionSlot = (string key, string pretty_name) unique
    MetaFuncSlot = (string key, string pretty_name, MoonliftMeta.MetaType fn_ty) unique
    MetaConstSlot = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaStaticSlot = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaTypeDeclSlot = (string key, string pretty_name) unique
    MetaItemsSlot = (string key, string pretty_name) unique
    MetaModuleSlot = (string key, string pretty_name) unique

    MetaSlot = MetaSlotType(MoonliftMeta.MetaTypeSlot slot) unique
             | MetaSlotExpr(MoonliftMeta.MetaExprSlot slot) unique
             | MetaSlotPlace(MoonliftMeta.MetaPlaceSlot slot) unique
             | MetaSlotDomain(MoonliftMeta.MetaDomainSlot slot) unique
             | MetaSlotRegion(MoonliftMeta.MetaRegionSlot slot) unique
             | MetaSlotFunc(MoonliftMeta.MetaFuncSlot slot) unique
             | MetaSlotConst(MoonliftMeta.MetaConstSlot slot) unique
             | MetaSlotStatic(MoonliftMeta.MetaStaticSlot slot) unique
             | MetaSlotTypeDecl(MoonliftMeta.MetaTypeDeclSlot slot) unique
             | MetaSlotItems(MoonliftMeta.MetaItemsSlot slot) unique
             | MetaSlotModule(MoonliftMeta.MetaModuleSlot slot) unique

    MetaParam = (string key, string name, MoonliftMeta.MetaType ty) unique

    MetaValueImport = MetaImportValue(string key, string name, MoonliftMeta.MetaType ty) unique
                    | MetaImportGlobalFunc(string key, string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportGlobalConst(string key, string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportGlobalStatic(string key, string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportExtern(string key, string symbol, MoonliftMeta.MetaType ty) unique

    MetaTypeImport = (string key, string local_name, MoonliftMeta.MetaType ty) unique
    MetaFieldType = (string field_name, MoonliftMeta.MetaType ty) unique

    MetaTypeLayout = MetaLayoutNamed(string module_name, string type_name, MoonliftMeta.MetaFieldType* fields) unique
                   | MetaLayoutLocal(MoonliftMeta.MetaTypeSym sym, MoonliftMeta.MetaFieldType* fields) unique

    MetaOpenSet = (MoonliftMeta.MetaValueImport* value_imports, MoonliftMeta.MetaTypeImport* type_imports, MoonliftMeta.MetaTypeLayout* layouts, MoonliftMeta.MetaSlot* slots) unique
    MetaSourceBinding = MetaSourceParamBinding(MoonliftMeta.MetaParam param) unique
                      | MetaSourceValueImportBinding(MoonliftMeta.MetaValueImport import) unique
                      | MetaSourceExprSlotBinding(MoonliftMeta.MetaExprSlot slot) unique
                      | MetaSourceFuncSlotBinding(MoonliftMeta.MetaFuncSlot slot) unique
                      | MetaSourceConstSlotBinding(MoonliftMeta.MetaConstSlot slot) unique
                      | MetaSourceStaticSlotBinding(MoonliftMeta.MetaStaticSlot slot) unique
    MetaSourceBindingEntry = (MoonliftElab.ElabBinding binding, MoonliftMeta.MetaSourceBinding source) unique
    MetaSourceTypeEntry = (MoonliftElab.ElabType ty, MoonliftMeta.MetaType meta_ty) unique
    MetaSourceEnv = (string module_name, MoonliftMeta.MetaSourceBindingEntry* bindings, MoonliftMeta.MetaSourceTypeEntry* types) unique
    MetaParamBinding = (MoonliftMeta.MetaParam param, MoonliftMeta.MetaExpr value) unique
    MetaFillSet = (MoonliftMeta.MetaSlotBinding* bindings) unique
    MetaExpandEnv = (MoonliftMeta.MetaFillSet fills, MoonliftMeta.MetaParamBinding* params, string rebase_prefix) unique
    MetaSealParamEntry = (MoonliftMeta.MetaParam param, number index) unique
    MetaSealEnv = (string module_name, MoonliftMeta.MetaSealParamEntry* params) unique

    MetaType = MetaTVoid
             | MetaTBool
             | MetaTI8 | MetaTI16 | MetaTI32 | MetaTI64
             | MetaTU8 | MetaTU16 | MetaTU32 | MetaTU64
             | MetaTF32 | MetaTF64
             | MetaTIndex
             | MetaTPtr(MoonliftMeta.MetaType elem) unique
             | MetaTArray(MoonliftMeta.MetaExpr count, MoonliftMeta.MetaType elem) unique
             | MetaTSlice(MoonliftMeta.MetaType elem) unique
             | MetaTView(MoonliftMeta.MetaType elem) unique
             | MetaTFunc(MoonliftMeta.MetaType* params, MoonliftMeta.MetaType result) unique
             | MetaTNamed(string module_name, string type_name) unique
             | MetaTLocalNamed(MoonliftMeta.MetaTypeSym sym) unique
             | MetaTSlot(MoonliftMeta.MetaTypeSlot slot) unique

    MetaBinding = MetaBindParam(MoonliftMeta.MetaParam param) unique
                | MetaBindLocalValue(string id, string name, MoonliftMeta.MetaType ty) unique
                | MetaBindLocalCell(string id, string name, MoonliftMeta.MetaType ty) unique
                | MetaBindLoopCarry(string loop_id, string port_id, string name, MoonliftMeta.MetaType ty) unique
                | MetaBindLoopIndex(string loop_id, string name, MoonliftMeta.MetaType ty) unique
                | MetaBindGlobalFunc(string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                | MetaBindGlobalConst(string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                | MetaBindGlobalStatic(string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                | MetaBindExtern(string symbol, MoonliftMeta.MetaType ty) unique
                | MetaBindImport(MoonliftMeta.MetaValueImport import) unique
                | MetaBindFuncSym(MoonliftMeta.MetaFuncSym sym, MoonliftMeta.MetaType ty) unique
                | MetaBindExternSym(MoonliftMeta.MetaExternSym sym, MoonliftMeta.MetaType ty) unique
                | MetaBindConstSym(MoonliftMeta.MetaConstSym sym, MoonliftMeta.MetaType ty) unique
                | MetaBindStaticSym(MoonliftMeta.MetaStaticSym sym, MoonliftMeta.MetaType ty) unique
                | MetaBindFuncSlot(MoonliftMeta.MetaFuncSlot slot) unique
                | MetaBindConstSlot(MoonliftMeta.MetaConstSlot slot) unique
                | MetaBindStaticSlot(MoonliftMeta.MetaStaticSlot slot) unique

    MetaFieldInit = (string name, MoonliftMeta.MetaExpr value) unique
    MetaSwitchStmtArm = (MoonliftMeta.MetaExpr key, MoonliftMeta.MetaStmt* body) unique
    MetaSwitchExprArm = (MoonliftMeta.MetaExpr key, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaExpr result) unique
    MetaCarryPort = (string port_id, string name, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr init) unique
    MetaIndexPort = (string name, MoonliftMeta.MetaType ty) unique
    MetaCarryUpdate = (string port_id, MoonliftMeta.MetaExpr value) unique

    MetaPlace = MetaPlaceBinding(MoonliftMeta.MetaBinding binding) unique
              | MetaPlaceDeref(MoonliftMeta.MetaExpr base, MoonliftMeta.MetaType elem) unique
              | MetaPlaceField(MoonliftMeta.MetaPlace base, string name, MoonliftMeta.MetaType ty) unique
              | MetaPlaceIndex(MoonliftMeta.MetaIndexBase base, MoonliftMeta.MetaExpr index, MoonliftMeta.MetaType ty) unique
              | MetaPlaceSlotValue(MoonliftMeta.MetaPlaceSlot slot) unique

    MetaIndexBase = MetaIndexBasePlace(MoonliftMeta.MetaPlace base, MoonliftMeta.MetaType elem) unique
                  | MetaIndexBaseView(MoonliftMeta.MetaExpr base, MoonliftMeta.MetaType elem) unique

    MetaDomain = MetaDomainRange(MoonliftMeta.MetaExpr stop) unique
               | MetaDomainRange2(MoonliftMeta.MetaExpr start, MoonliftMeta.MetaExpr stop) unique
               | MetaDomainZipEq(MoonliftMeta.MetaExpr* values) unique
               | MetaDomainValue(MoonliftMeta.MetaExpr value) unique
               | MetaDomainSlotValue(MoonliftMeta.MetaDomainSlot slot) unique

    MetaExprExit = MetaExprEndOnly
                 | MetaExprEndOrBreakValue

    MetaLoop = MetaWhileStmt(string loop_id, MoonliftMeta.MetaCarryPort* carries, MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaCarryUpdate* next) unique
             | MetaOverStmt(string loop_id, MoonliftMeta.MetaIndexPort index_port, MoonliftMeta.MetaDomain domain, MoonliftMeta.MetaCarryPort* carries, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaCarryUpdate* next) unique
             | MetaWhileExpr(string loop_id, MoonliftMeta.MetaCarryPort* carries, MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaCarryUpdate* next, MoonliftMeta.MetaExprExit exit, MoonliftMeta.MetaExpr result) unique
             | MetaOverExpr(string loop_id, MoonliftMeta.MetaIndexPort index_port, MoonliftMeta.MetaDomain domain, MoonliftMeta.MetaCarryPort* carries, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaCarryUpdate* next, MoonliftMeta.MetaExprExit exit, MoonliftMeta.MetaExpr result) unique

    MetaExpr = MetaInt(string raw, MoonliftMeta.MetaType ty) unique
             | MetaFloat(string raw, MoonliftMeta.MetaType ty) unique
             | MetaBool(boolean value, MoonliftMeta.MetaType ty) unique
             | MetaNil(MoonliftMeta.MetaType ty) unique
             | MetaBindingExpr(MoonliftMeta.MetaBinding binding) unique
             | MetaExprNeg(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprNot(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprBNot(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprAddrOf(MoonliftMeta.MetaPlace place, MoonliftMeta.MetaType ty) unique
             | MetaExprDeref(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprAdd(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprSub(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprMul(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprDiv(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprRem(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprEq(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprNe(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprLt(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprLe(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprGt(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprGe(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprAnd(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprOr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprBitAnd(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprBitOr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprBitXor(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprShl(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprLShr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprAShr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprCastTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprTruncTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprZExtTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprSExtTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprBitcastTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprSatCastTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprIntrinsicCall(MoonliftMeta.MetaIntrinsic op, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr* args) unique
             | MetaCall(MoonliftMeta.MetaExpr callee, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr* args) unique
             | MetaField(MoonliftMeta.MetaExpr base, string name, MoonliftMeta.MetaType ty) unique
             | MetaIndex(MoonliftMeta.MetaIndexBase base, MoonliftMeta.MetaExpr index, MoonliftMeta.MetaType ty) unique
             | MetaAgg(MoonliftMeta.MetaType ty, MoonliftMeta.MetaFieldInit* fields) unique
             | MetaArrayLit(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr* elems) unique
             | MetaIfExpr(MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaExpr then_expr, MoonliftMeta.MetaExpr else_expr, MoonliftMeta.MetaType ty) unique
             | MetaSelectExpr(MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaExpr then_expr, MoonliftMeta.MetaExpr else_expr, MoonliftMeta.MetaType ty) unique
             | MetaSwitchExpr(MoonliftMeta.MetaExpr value, MoonliftMeta.MetaSwitchExprArm* arms, MoonliftMeta.MetaExpr default_expr, MoonliftMeta.MetaType ty) unique
             | MetaExprLoop(MoonliftMeta.MetaLoop loop, MoonliftMeta.MetaType ty) unique
             | MetaBlockExpr(MoonliftMeta.MetaStmt* stmts, MoonliftMeta.MetaExpr result, MoonliftMeta.MetaType ty) unique
             | MetaExprView(MoonliftMeta.MetaExpr base, MoonliftMeta.MetaType ty) unique
             | MetaExprViewWindow(MoonliftMeta.MetaExpr base, MoonliftMeta.MetaExpr start, MoonliftMeta.MetaExpr len, MoonliftMeta.MetaType ty) unique
             | MetaExprViewFromPtr(MoonliftMeta.MetaExpr ptr, MoonliftMeta.MetaExpr len, MoonliftMeta.MetaType ty) unique
             | MetaExprViewFromPtrStrided(MoonliftMeta.MetaExpr ptr, MoonliftMeta.MetaExpr len, MoonliftMeta.MetaExpr stride, MoonliftMeta.MetaType ty) unique
             | MetaExprViewStrided(MoonliftMeta.MetaExpr base, MoonliftMeta.MetaExpr stride, MoonliftMeta.MetaType ty) unique
             | MetaExprViewInterleaved(MoonliftMeta.MetaExpr base, MoonliftMeta.MetaExpr stride, MoonliftMeta.MetaExpr lane, MoonliftMeta.MetaType ty) unique
             | MetaExprSlotValue(MoonliftMeta.MetaExprSlot slot, MoonliftMeta.MetaType ty) unique
             | MetaExprUseExprFrag(string use_id, MoonliftMeta.MetaExprFrag frag, MoonliftMeta.MetaExpr* args, MoonliftMeta.MetaSlotBinding* fills, MoonliftMeta.MetaType ty) unique

    MetaStmt = MetaLet(string id, string name, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr init) unique
             | MetaVar(string id, string name, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr init) unique
             | MetaSet(MoonliftMeta.MetaPlace place, MoonliftMeta.MetaExpr value) unique
             | MetaExprStmt(MoonliftMeta.MetaExpr expr) unique
             | MetaAssert(MoonliftMeta.MetaExpr cond) unique
             | MetaIf(MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaStmt* then_body, MoonliftMeta.MetaStmt* else_body) unique
             | MetaSwitch(MoonliftMeta.MetaExpr value, MoonliftMeta.MetaSwitchStmtArm* arms, MoonliftMeta.MetaStmt* default_body) unique
             | MetaReturnVoid
             | MetaReturnValue(MoonliftMeta.MetaExpr value) unique
             | MetaBreak
             | MetaBreakValue(MoonliftMeta.MetaExpr value) unique
             | MetaContinue
             | MetaStmtLoop(MoonliftMeta.MetaLoop loop) unique
             | MetaStmtUseRegionSlot(MoonliftMeta.MetaRegionSlot slot) unique
             | MetaStmtUseRegionFrag(string use_id, MoonliftMeta.MetaRegionFrag frag, MoonliftMeta.MetaExpr* args, MoonliftMeta.MetaSlotBinding* fills) unique

    MetaExprFrag = (MoonliftMeta.MetaParam* params, MoonliftMeta.MetaOpenSet open, MoonliftMeta.MetaExpr body, MoonliftMeta.MetaType result) unique
    MetaRegionFrag = (MoonliftMeta.MetaParam* params, MoonliftMeta.MetaOpenSet open, MoonliftMeta.MetaStmt* body) unique

    MetaFunc = MetaFuncLocal(MoonliftMeta.MetaFuncSym sym, MoonliftMeta.MetaParam* params, MoonliftMeta.MetaOpenSet open, MoonliftMeta.MetaType result, MoonliftMeta.MetaStmt* body) unique
             | MetaFuncExport(MoonliftMeta.MetaFuncSym sym, MoonliftMeta.MetaParam* params, MoonliftMeta.MetaOpenSet open, MoonliftMeta.MetaType result, MoonliftMeta.MetaStmt* body) unique

    MetaExternFunc = (MoonliftMeta.MetaExternSym sym, MoonliftMeta.MetaParam* params, MoonliftMeta.MetaType result) unique
    MetaConst = (MoonliftMeta.MetaConstSym sym, MoonliftMeta.MetaOpenSet open, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
    MetaStatic = (MoonliftMeta.MetaStaticSym sym, MoonliftMeta.MetaOpenSet open, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
    MetaImport = (string module_name) unique

    MetaTypeDecl = MetaStruct(MoonliftMeta.MetaTypeSym sym, MoonliftMeta.MetaFieldType* fields) unique
                 | MetaUnion(MoonliftMeta.MetaTypeSym sym, MoonliftMeta.MetaFieldType* fields) unique

    MetaItem = MetaItemFunc(MoonliftMeta.MetaFunc func) unique
             | MetaItemExtern(MoonliftMeta.MetaExternFunc func) unique
             | MetaItemConst(MoonliftMeta.MetaConst c) unique
             | MetaItemStatic(MoonliftMeta.MetaStatic s) unique
             | MetaItemImport(MoonliftMeta.MetaImport imp) unique
             | MetaItemType(MoonliftMeta.MetaTypeDecl t) unique
             | MetaItemUseTypeDeclSlot(MoonliftMeta.MetaTypeDeclSlot slot) unique
             | MetaItemUseItemsSlot(MoonliftMeta.MetaItemsSlot slot) unique
             | MetaItemUseModule(string use_id, MoonliftMeta.MetaModule module, MoonliftMeta.MetaSlotBinding* fills) unique
             | MetaItemUseModuleSlot(string use_id, MoonliftMeta.MetaModuleSlot slot, MoonliftMeta.MetaSlotBinding* fills) unique

    MetaModule = (MoonliftMeta.MetaModuleName name, MoonliftMeta.MetaOpenSet open, MoonliftMeta.MetaItem* items) unique

    MetaSlotValue = MetaSlotValueType(MoonliftMeta.MetaType ty) unique
                  | MetaSlotValueExpr(MoonliftMeta.MetaExpr expr) unique
                  | MetaSlotValuePlace(MoonliftMeta.MetaPlace place) unique
                  | MetaSlotValueDomain(MoonliftMeta.MetaDomain domain) unique
                  | MetaSlotValueRegion(MoonliftMeta.MetaStmt* body) unique
                  | MetaSlotValueFunc(MoonliftMeta.MetaFunc func) unique
                  | MetaSlotValueConst(MoonliftMeta.MetaConst c) unique
                  | MetaSlotValueStatic(MoonliftMeta.MetaStatic s) unique
                  | MetaSlotValueTypeDecl(MoonliftMeta.MetaTypeDecl t) unique
                  | MetaSlotValueItems(MoonliftMeta.MetaItem* items) unique
                  | MetaSlotValueModule(MoonliftMeta.MetaModule module) unique

    MetaSlotBinding = (MoonliftMeta.MetaSlot slot, MoonliftMeta.MetaSlotValue value) unique

    MetaRewriteRule = MetaRewriteType(MoonliftMeta.MetaType from, MoonliftMeta.MetaType to) unique
                    | MetaRewriteBinding(MoonliftMeta.MetaBinding from, MoonliftMeta.MetaBinding to) unique
                    | MetaRewritePlace(MoonliftMeta.MetaPlace from, MoonliftMeta.MetaPlace to) unique
                    | MetaRewriteDomain(MoonliftMeta.MetaDomain from, MoonliftMeta.MetaDomain to) unique
                    | MetaRewriteExpr(MoonliftMeta.MetaExpr from, MoonliftMeta.MetaExpr to) unique
                    | MetaRewriteStmt(MoonliftMeta.MetaStmt from, MoonliftMeta.MetaStmt* to) unique
                    | MetaRewriteItem(MoonliftMeta.MetaItem from, MoonliftMeta.MetaItem* to) unique
    MetaRewriteSet = (MoonliftMeta.MetaRewriteRule* rules) unique

    MetaFact = MetaFactSlot(MoonliftMeta.MetaSlot slot) unique
             | MetaFactParamUse(MoonliftMeta.MetaParam param) unique
             | MetaFactValueImportUse(MoonliftMeta.MetaValueImport import) unique
             | MetaFactLocalValue(string id, string name) unique
             | MetaFactLocalCell(string id, string name) unique
             | MetaFactLoopCarry(string loop_id, string port_id, string name) unique
             | MetaFactLoopIndex(string loop_id, string name) unique
             | MetaFactGlobalFunc(string module_name, string item_name) unique
             | MetaFactGlobalConst(string module_name, string item_name) unique
             | MetaFactGlobalStatic(string module_name, string item_name) unique
             | MetaFactExtern(string symbol) unique
             | MetaFactExprFragUse(string use_id) unique
             | MetaFactRegionFragUse(string use_id) unique
             | MetaFactModuleUse(string use_id) unique
             | MetaFactModuleSlotUse(string use_id, MoonliftMeta.MetaModuleSlot slot) unique
             | MetaFactOpenModuleName
             | MetaFactLocalType(MoonliftMeta.MetaTypeSym sym) unique
    MetaFactSet = (MoonliftMeta.MetaFact* facts) unique

    MetaValidationIssue = MetaIssueOpenSlot(MoonliftMeta.MetaSlot slot) unique
                        | MetaIssueUnfilledTypeSlot(MoonliftMeta.MetaTypeSlot slot) unique
                        | MetaIssueUnfilledExprSlot(MoonliftMeta.MetaExprSlot slot) unique
                        | MetaIssueUnfilledPlaceSlot(MoonliftMeta.MetaPlaceSlot slot) unique
                        | MetaIssueUnfilledDomainSlot(MoonliftMeta.MetaDomainSlot slot) unique
                        | MetaIssueUnfilledRegionSlot(MoonliftMeta.MetaRegionSlot slot) unique
                        | MetaIssueUnfilledFuncSlot(MoonliftMeta.MetaFuncSlot slot) unique
                        | MetaIssueUnfilledConstSlot(MoonliftMeta.MetaConstSlot slot) unique
                        | MetaIssueUnfilledStaticSlot(MoonliftMeta.MetaStaticSlot slot) unique
                        | MetaIssueUnfilledTypeDeclSlot(MoonliftMeta.MetaTypeDeclSlot slot) unique
                        | MetaIssueUnfilledItemsSlot(MoonliftMeta.MetaItemsSlot slot) unique
                        | MetaIssueUnfilledModuleSlot(MoonliftMeta.MetaModuleSlot slot) unique
                        | MetaIssueUnexpandedExprFragUse(string use_id) unique
                        | MetaIssueUnexpandedRegionFragUse(string use_id) unique
                        | MetaIssueUnexpandedModuleUse(string use_id) unique
                        | MetaIssueOpenModuleName
                        | MetaIssueGenericValueImport(MoonliftMeta.MetaValueImport import) unique
    MetaValidationReport = (MoonliftMeta.MetaValidationIssue* issues) unique
}

module MoonliftSem {
    SemType = SemTVoid
            | SemTBool
            | SemTI8 | SemTI16 | SemTI32 | SemTI64
            | SemTU8 | SemTU16 | SemTU32 | SemTU64
            | SemTF32 | SemTF64
            | SemTRawPtr
            | SemTIndex
            | SemTPtrTo(MoonliftSem.SemType elem) unique
            | SemTArray(MoonliftSem.SemType elem, number count) unique
            | SemTSlice(MoonliftSem.SemType elem) unique
            | SemTView(MoonliftSem.SemType elem) unique
            | SemTFunc(MoonliftSem.SemType* params, MoonliftSem.SemType result) unique
            | SemTNamed(string module_name, string type_name) unique

    SemIntrinsic = SemPopcount
                 | SemClz
                 | SemCtz
                 | SemRotl
                 | SemRotr
                 | SemBswap
                 | SemFma
                 | SemSqrt
                 | SemAbs
                 | SemFloor
                 | SemCeil
                 | SemTruncFloat
                 | SemRound
                 | SemTrap
                 | SemAssume

    SemParam = (string name, MoonliftSem.SemType ty) unique
    SemBinding = SemBindLocalValue(string id, string name, MoonliftSem.SemType ty) unique
               | SemBindLocalCell(string id, string name, MoonliftSem.SemType ty) unique
               | SemBindArg(number index, string name, MoonliftSem.SemType ty) unique
               | SemBindLoopCarry(string loop_id, string port_id, string name, MoonliftSem.SemType ty) unique
               | SemBindLoopIndex(string loop_id, string name, MoonliftSem.SemType ty) unique
               | SemBindGlobalFunc(string module_name, string item_name, MoonliftSem.SemType ty) unique
               | SemBindGlobalConst(string module_name, string item_name, MoonliftSem.SemType ty) unique
               | SemBindGlobalStatic(string module_name, string item_name, MoonliftSem.SemType ty) unique
               | SemBindExtern(string symbol, MoonliftSem.SemType ty) unique

    SemResidence = SemResidenceValue | SemResidenceStack
    SemResidenceEntry = (MoonliftSem.SemBinding binding, MoonliftSem.SemResidence residence) unique
    SemResidencePlan = (MoonliftSem.SemResidenceEntry* entries) unique

    SemBackBinding = SemBackLocalValue(string id, string name, MoonliftSem.SemType ty) unique
                   | SemBackLocalStored(string id, string name, MoonliftSem.SemType ty) unique
                   | SemBackLocalCell(string id, string name, MoonliftSem.SemType ty) unique
                   | SemBackArgValue(number index, string name, MoonliftSem.SemType ty) unique
                   | SemBackArgStored(number index, string name, MoonliftSem.SemType ty) unique
                   | SemBackLoopCarryValue(string loop_id, string port_id, string name, MoonliftSem.SemType ty) unique
                   | SemBackLoopCarryStored(string loop_id, string port_id, string name, MoonliftSem.SemType ty) unique
                   | SemBackLoopIndexValue(string loop_id, string name, MoonliftSem.SemType ty) unique
                   | SemBackLoopIndexStored(string loop_id, string name, MoonliftSem.SemType ty) unique
                   | SemBackGlobalFunc(string module_name, string item_name, MoonliftSem.SemType ty) unique
                   | SemBackGlobalConst(string module_name, string item_name, MoonliftSem.SemType ty) unique
                   | SemBackGlobalStatic(string module_name, string item_name, MoonliftSem.SemType ty) unique
                   | SemBackExtern(string symbol, MoonliftSem.SemType ty) unique

    SemView = SemViewFromExpr(MoonliftSem.SemExpr base, MoonliftSem.SemType elem) unique
            | SemViewContiguous(MoonliftSem.SemExpr data, MoonliftSem.SemType elem, MoonliftSem.SemExpr len) unique
            | SemViewStrided(MoonliftSem.SemExpr data, MoonliftSem.SemType elem, MoonliftSem.SemExpr len, MoonliftSem.SemExpr stride) unique
            | SemViewRestrided(MoonliftSem.SemView base, MoonliftSem.SemType elem, MoonliftSem.SemExpr stride) unique
            | SemViewWindow(MoonliftSem.SemView base, MoonliftSem.SemExpr start, MoonliftSem.SemExpr len) unique
            | SemViewRowBase(MoonliftSem.SemView base, MoonliftSem.SemExpr row_offset, MoonliftSem.SemType elem) unique
            | SemViewInterleaved(MoonliftSem.SemExpr data, MoonliftSem.SemType elem, MoonliftSem.SemExpr len, MoonliftSem.SemExpr stride, MoonliftSem.SemExpr lane) unique
            | SemViewInterleavedView(MoonliftSem.SemView base, MoonliftSem.SemType elem, MoonliftSem.SemExpr stride, MoonliftSem.SemExpr lane) unique

    SemDomain = SemDomainRange(MoonliftSem.SemExpr stop) unique
              | SemDomainRange2(MoonliftSem.SemExpr start, MoonliftSem.SemExpr stop) unique
              | SemDomainView(MoonliftSem.SemView view) unique
              | SemDomainZipEq(MoonliftSem.SemView* views) unique

    SemIndexBase = SemIndexBasePlace(MoonliftSem.SemPlace base, MoonliftSem.SemType elem) unique
                 | SemIndexBaseView(MoonliftSem.SemView view) unique

    SemCallTarget = SemCallDirect(string module_name, string func_name, MoonliftSem.SemType fn_ty) unique
                  | SemCallIndirect(MoonliftSem.SemExpr callee, MoonliftSem.SemType fn_ty) unique
                  | SemCallExtern(string symbol, MoonliftSem.SemType fn_ty) unique

    SemFieldRef = SemFieldByName(string field_name, MoonliftSem.SemType ty) unique
                | SemFieldByOffset(string field_name, number offset, MoonliftSem.SemType ty) unique

    SemFieldType = (string field_name, MoonliftSem.SemType ty) unique
    SemFieldLayout = (string field_name, number offset, MoonliftSem.SemType ty) unique
    SemMemLayout = (number size, number align) unique
    SemTypeLayout = SemLayoutNamed(string module_name, string type_name, MoonliftSem.SemFieldLayout* fields, number size, number align) unique
    SemLayoutEnv = (MoonliftSem.SemTypeLayout* layouts) unique
    SemConstFieldValue = (string name, MoonliftSem.SemConstValue value) unique
    SemConstValue = SemConstInt(MoonliftSem.SemType ty, string raw) unique
                  | SemConstFloat(MoonliftSem.SemType ty, string raw) unique
                  | SemConstBool(boolean value) unique
                  | SemConstNil(MoonliftSem.SemType ty) unique
                  | SemConstAgg(MoonliftSem.SemType ty, MoonliftSem.SemConstFieldValue* fields) unique
                  | SemConstArray(MoonliftSem.SemType elem_ty, MoonliftSem.SemConstValue* elems) unique
    SemConstEntry = (string module_name, string item_name, MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
    SemConstEnv = (MoonliftSem.SemConstEntry* entries) unique
    SemConstLocalEntry = (MoonliftSem.SemBinding binding, MoonliftSem.SemConstValue value) unique
    SemConstLocalEnv = (MoonliftSem.SemConstLocalEntry* entries) unique
    SemConstStmtResult = SemConstStmtFallsThrough(MoonliftSem.SemConstLocalEnv local_env) unique
                       | SemConstStmtReturnVoid(MoonliftSem.SemConstLocalEnv local_env) unique
                       | SemConstStmtReturnValue(MoonliftSem.SemConstLocalEnv local_env, MoonliftSem.SemConstValue value) unique
                       | SemConstStmtBreak(MoonliftSem.SemConstLocalEnv local_env) unique
                       | SemConstStmtBreakValue(MoonliftSem.SemConstLocalEnv local_env, MoonliftSem.SemConstValue value) unique
                       | SemConstStmtContinue(MoonliftSem.SemConstLocalEnv local_env) unique

    SemFieldInit = (string name, MoonliftSem.SemExpr value) unique
    SemSwitchStmtArm = (MoonliftSem.SemExpr key, MoonliftSem.SemStmt* body) unique
    SemSwitchExprArm = (MoonliftSem.SemExpr key, MoonliftSem.SemStmt* body, MoonliftSem.SemExpr result) unique
    SemBackSwitchKey = SemBackSwitchKeyConst(string raw) unique
                     | SemBackSwitchKeyExpr(MoonliftSem.SemExpr key) unique
    SemBackSwitchStmtArm = (MoonliftSem.SemBackSwitchKey key, MoonliftSem.SemStmt* body) unique
    SemBackSwitchExprArm = (MoonliftSem.SemBackSwitchKey key, MoonliftSem.SemStmt* body, MoonliftSem.SemExpr result) unique
    SemBackSwitchStmtArms = SemBackSwitchStmtArmsConst(MoonliftSem.SemBackSwitchStmtArm* arms) unique
                          | SemBackSwitchStmtArmsExpr(MoonliftSem.SemBackSwitchStmtArm* arms) unique
    SemBackSwitchExprArms = SemBackSwitchExprArmsConst(MoonliftSem.SemBackSwitchExprArm* arms) unique
                          | SemBackSwitchExprArmsExpr(MoonliftSem.SemBackSwitchExprArm* arms) unique
    SemCarryPort = (string port_id, string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr init) unique
    SemIndexPort = (string name, MoonliftSem.SemType ty) unique
    SemCarryUpdate = (string port_id, MoonliftSem.SemExpr value) unique

    SemPlace = SemPlaceBinding(MoonliftSem.SemBinding binding) unique
             | SemPlaceDeref(MoonliftSem.SemExpr base, MoonliftSem.SemType elem) unique
             | SemPlaceField(MoonliftSem.SemPlace base, MoonliftSem.SemFieldRef field) unique
             | SemPlaceIndex(MoonliftSem.SemIndexBase base, MoonliftSem.SemExpr index, MoonliftSem.SemType ty) unique

    SemExpr = SemExprConstInt(MoonliftSem.SemType ty, string raw) unique
            | SemExprConstFloat(MoonliftSem.SemType ty, string raw) unique
            | SemExprConstBool(boolean value) unique
            | SemExprNil(MoonliftSem.SemType ty) unique
            | SemExprBinding(MoonliftSem.SemBinding binding) unique
            | SemExprNeg(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprNot(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprBNot(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprAddrOf(MoonliftSem.SemPlace place, MoonliftSem.SemType ty) unique
            | SemExprDeref(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprAdd(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprSub(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprMul(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprDiv(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprRem(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprEq(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprNe(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprLt(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprLe(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprGt(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprGe(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprAnd(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprOr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprBitAnd(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprBitOr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprBitXor(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprShl(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprLShr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprAShr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprCastTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprTruncTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprZExtTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprSExtTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprBitcastTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprSatCastTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprSelect(MoonliftSem.SemExpr cond, MoonliftSem.SemExpr then_value, MoonliftSem.SemExpr else_value, MoonliftSem.SemType ty) unique
            | SemExprIndex(MoonliftSem.SemIndexBase base, MoonliftSem.SemExpr index, MoonliftSem.SemType ty) unique
            | SemExprField(MoonliftSem.SemExpr base, MoonliftSem.SemFieldRef field) unique
            | SemExprLoad(MoonliftSem.SemType ty, MoonliftSem.SemExpr addr) unique
            | SemExprIntrinsicCall(MoonliftSem.SemIntrinsic op, MoonliftSem.SemType ty, MoonliftSem.SemExpr* args) unique
            | SemExprCall(MoonliftSem.SemCallTarget target, MoonliftSem.SemType ty, MoonliftSem.SemExpr* args) unique
            | SemExprAgg(MoonliftSem.SemType ty, MoonliftSem.SemFieldInit* fields) unique
            | SemExprArrayLit(MoonliftSem.SemType elem_ty, MoonliftSem.SemExpr* elems) unique
            | SemExprBlock(MoonliftSem.SemStmt* stmts, MoonliftSem.SemExpr result, MoonliftSem.SemType ty) unique
            | SemExprIf(MoonliftSem.SemExpr cond, MoonliftSem.SemExpr then_expr, MoonliftSem.SemExpr else_expr, MoonliftSem.SemType ty) unique
            | SemExprSwitch(MoonliftSem.SemExpr value, MoonliftSem.SemSwitchExprArm* arms, MoonliftSem.SemExpr default_expr, MoonliftSem.SemType ty) unique
            | SemExprLoop(MoonliftSem.SemLoop loop, MoonliftSem.SemType ty) unique

    SemExprExit = SemExprEndOnly
                | SemExprEndOrBreakValue

    SemCastOp = SemCastIdentity
              | SemCastBitcast
              | SemCastIreduce
              | SemCastSextend
              | SemCastUextend
              | SemCastFpromote
              | SemCastFdemote
              | SemCastSToF
              | SemCastUToF
              | SemCastFToS
              | SemCastFToU

    SemLoop = SemWhileStmt(string loop_id, MoonliftSem.SemCarryPort* carries, MoonliftSem.SemExpr cond, MoonliftSem.SemStmt* body, MoonliftSem.SemCarryUpdate* next) unique
            | SemOverStmt(string loop_id, MoonliftSem.SemIndexPort index_port, MoonliftSem.SemDomain domain, MoonliftSem.SemCarryPort* carries, MoonliftSem.SemStmt* body, MoonliftSem.SemCarryUpdate* next) unique
            | SemWhileExpr(string loop_id, MoonliftSem.SemCarryPort* carries, MoonliftSem.SemExpr cond, MoonliftSem.SemStmt* body, MoonliftSem.SemCarryUpdate* next, MoonliftSem.SemExprExit exit, MoonliftSem.SemExpr result) unique
            | SemOverExpr(string loop_id, MoonliftSem.SemIndexPort index_port, MoonliftSem.SemDomain domain, MoonliftSem.SemCarryPort* carries, MoonliftSem.SemStmt* body, MoonliftSem.SemCarryUpdate* next, MoonliftSem.SemExprExit exit, MoonliftSem.SemExpr result) unique

    SemStmt = SemStmtLet(string id, string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr init) unique
            | SemStmtVar(string id, string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr init) unique
            | SemStmtSet(MoonliftSem.SemPlace place, MoonliftSem.SemExpr value) unique
            | SemStmtExpr(MoonliftSem.SemExpr expr) unique
            | SemStmtIf(MoonliftSem.SemExpr cond, MoonliftSem.SemStmt* then_body, MoonliftSem.SemStmt* else_body) unique
            | SemStmtSwitch(MoonliftSem.SemExpr value, MoonliftSem.SemSwitchStmtArm* arms, MoonliftSem.SemStmt* default_body) unique
            | SemStmtAssert(MoonliftSem.SemExpr cond) unique
            | SemStmtReturnVoid
            | SemStmtReturnValue(MoonliftSem.SemExpr value) unique
            | SemStmtBreak
            | SemStmtBreakValue(MoonliftSem.SemExpr value) unique
            | SemStmtContinue
            | SemStmtLoop(MoonliftSem.SemLoop loop) unique

    SemFunc = SemFuncLocal(string name, MoonliftSem.SemParam* params, MoonliftSem.SemType result, MoonliftSem.SemStmt* body) unique
            | SemFuncExport(string name, MoonliftSem.SemParam* params, MoonliftSem.SemType result, MoonliftSem.SemStmt* body) unique
    SemExternFunc = (string name, string symbol, MoonliftSem.SemParam* params, MoonliftSem.SemType result) unique
    SemConst = (string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
    SemStatic = (string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
    SemImport = (string module_name) unique
    SemTypeDecl = SemStruct(string name, MoonliftSem.SemFieldType* fields) unique
                | SemUnion(string name, MoonliftSem.SemFieldType* fields) unique
    SemItem = SemItemFunc(MoonliftSem.SemFunc func) unique
            | SemItemExtern(MoonliftSem.SemExternFunc func) unique
            | SemItemConst(MoonliftSem.SemConst c) unique
            | SemItemStatic(MoonliftSem.SemStatic s) unique
            | SemItemImport(MoonliftSem.SemImport imp) unique
            | SemItemType(MoonliftSem.SemTypeDecl t) unique
    SemModule = (string module_name, MoonliftSem.SemItem* items) unique
}

module MoonliftVec {
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

    VecShape = VecScalarShape(MoonliftVec.VecElem elem) unique
             | VecVectorShape(MoonliftVec.VecElem elem, number lanes) unique

    VecBinOp = VecAdd | VecSub | VecMul | VecRem
             | VecBitAnd | VecBitOr | VecBitXor
             | VecShl | VecLShr | VecAShr
             | VecEq | VecNe | VecLt | VecLe | VecGt | VecGe

    VecUnaryOp = VecNeg | VecNot | VecBitNot | VecPopcount | VecClz | VecCtz

    VecReject = VecRejectUnsupportedLoop(MoonliftVec.VecLoopId loop, string reason) unique
              | VecRejectUnsupportedExpr(MoonliftVec.VecExprId expr, string reason) unique
              | VecRejectUnsupportedStmt(string stmt_id, string reason) unique
              | VecRejectUnsupportedMemory(MoonliftVec.VecAccessId access, string reason) unique
              | VecRejectDependence(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, string reason) unique
              | VecRejectRange(MoonliftVec.VecExprId expr, string reason) unique
              | VecRejectTarget(MoonliftVec.VecShape shape, string reason) unique
              | VecRejectCost(string reason) unique

    VecTarget = VecTargetCraneliftJit
              | VecTargetNamed(string name) unique

    VecTargetFact = VecTargetSupportsShape(MoonliftVec.VecShape shape) unique
                  | VecTargetSupportsBinOp(MoonliftVec.VecShape shape, MoonliftVec.VecBinOp op) unique
                  | VecTargetSupportsUnaryOp(MoonliftVec.VecShape shape, MoonliftVec.VecUnaryOp op) unique
                  | VecTargetPrefersUnroll(MoonliftVec.VecShape shape, number unroll, number rank) unique
                  | VecTargetPrefersScalarTail
                  | VecTargetSupportsMaskedTail
                  | VecTargetVectorBits(number bits) unique

    VecTargetModel = (MoonliftVec.VecTarget target, MoonliftVec.VecTargetFact* facts) unique

    VecExprFact = VecExprConst(MoonliftVec.VecExprId id, MoonliftSem.SemExpr expr, MoonliftSem.SemType ty) unique
                | VecExprInvariant(MoonliftVec.VecExprId id, MoonliftSem.SemExpr expr, MoonliftSem.SemType ty) unique
                | VecExprLaneIndex(MoonliftVec.VecExprId id, MoonliftSem.SemBinding binding, MoonliftSem.SemType ty) unique
                | VecExprLocal(MoonliftVec.VecExprId id, MoonliftSem.SemBinding binding, MoonliftVec.VecExprId value, MoonliftSem.SemType ty) unique
                | VecExprUnary(MoonliftVec.VecExprId id, MoonliftVec.VecUnaryOp op, MoonliftVec.VecExprId value, MoonliftSem.SemType ty) unique
                | VecExprBin(MoonliftVec.VecExprId id, MoonliftVec.VecBinOp op, MoonliftVec.VecExprId lhs, MoonliftVec.VecExprId rhs, MoonliftSem.SemType ty) unique
                | VecExprSelect(MoonliftVec.VecExprId id, MoonliftVec.VecExprId cond, MoonliftVec.VecExprId then_value, MoonliftVec.VecExprId else_value, MoonliftSem.SemType ty) unique
                | VecExprLoad(MoonliftVec.VecExprId id, MoonliftVec.VecAccessId access, MoonliftSem.SemType ty) unique
                | VecExprRejected(MoonliftVec.VecExprId id, MoonliftVec.VecReject reject) unique

    VecExprGraph = (MoonliftVec.VecExprFact* exprs) unique
    VecExprResult = VecExprResult(MoonliftVec.VecExprId value, MoonliftVec.VecExprFact* facts, MoonliftVec.VecMemoryFact* memory, MoonliftVec.VecRangeFact* ranges, MoonliftVec.VecReject* rejects, MoonliftSem.SemType ty) unique
    VecLocalFact = (MoonliftSem.SemBinding binding, MoonliftVec.VecExprId value, MoonliftSem.SemType ty) unique
    VecExprEnv = (MoonliftSem.SemBinding index, MoonliftVec.VecLocalFact* locals) unique
    VecStmtResult = VecStmtLocal(MoonliftVec.VecLocalFact local, MoonliftVec.VecExprFact* facts, MoonliftVec.VecMemoryFact* memory, MoonliftVec.VecRangeFact* ranges, MoonliftVec.VecReject* rejects) unique
                  | VecStmtStore(MoonliftVec.VecStoreFact store, MoonliftVec.VecExprFact* facts, MoonliftVec.VecMemoryFact* memory, MoonliftVec.VecRangeFact* ranges, MoonliftVec.VecReject* rejects) unique
                  | VecStmtIgnored(MoonliftVec.VecExprFact* facts, MoonliftVec.VecMemoryFact* memory, MoonliftVec.VecRangeFact* ranges, MoonliftVec.VecReject* rejects) unique

    VecRangeFact = VecRangeUnknown(MoonliftVec.VecExprId expr) unique
                 | VecRangeExact(MoonliftVec.VecExprId expr, string value) unique
                 | VecRangeUnsigned(MoonliftVec.VecExprId expr, string min, string max) unique
                 | VecRangeBitAnd(MoonliftVec.VecExprId expr, string mask, string max_value) unique
                 | VecRangeDerived(MoonliftVec.VecExprId expr, string min, string max, MoonliftVec.VecProof* proofs) unique

    VecDomain = VecDomainCounted(MoonliftSem.SemExpr start, MoonliftSem.SemExpr stop, MoonliftSem.SemExpr step) unique
              | VecDomainRejected(MoonliftVec.VecReject reject) unique

    VecInduction = VecPrimaryInduction(MoonliftSem.SemBinding binding, MoonliftSem.SemExpr start, MoonliftSem.SemExpr step) unique
                 | VecDerivedInduction(MoonliftSem.SemBinding binding, MoonliftVec.VecExprId expr) unique

    VecAccessKind = VecAccessLoad | VecAccessStore
    VecAccessPattern = VecAccessContiguous
                     | VecAccessStrided(number stride)
                     | VecAccessGather
                     | VecAccessScatter
                     | VecAccessUnknown
    VecAlignment = VecAlignmentKnown(number bytes)
                 | VecAlignmentUnknown
                 | VecAlignmentAssumed(number bytes, MoonliftVec.VecProof proof) unique
    VecBounds = VecBoundsProven(MoonliftVec.VecProof proof) unique
              | VecBoundsUnknown(MoonliftVec.VecReject reject) unique

    VecMemoryFact = VecMemoryAccess(MoonliftVec.VecAccessId id,
                                    MoonliftVec.VecAccessKind access_kind,
                                    MoonliftSem.SemExpr base,
                                    MoonliftVec.VecExprId index,
                                    MoonliftSem.SemType elem_ty,
                                    MoonliftVec.VecAccessPattern pattern,
                                    MoonliftVec.VecAlignment alignment,
                                    MoonliftVec.VecBounds bounds) unique

    VecDependenceFact = VecNoDependence(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, MoonliftVec.VecProof proof) unique
                      | VecDependenceUnknown(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, MoonliftVec.VecReject reject) unique
                      | VecLoopCarriedDependence(MoonliftVec.VecAccessId a, MoonliftVec.VecAccessId b, MoonliftVec.VecReject reject) unique

    VecReassoc = VecReassocWrapping
               | VecReassocExact
               | VecReassocFloatFastMath
               | VecReassocRejected(MoonliftVec.VecReject reject) unique

    VecReductionFact = VecReductionAdd(MoonliftSem.SemCarryPort carry, MoonliftVec.VecExprId value, MoonliftVec.VecReassoc reassoc) unique
                     | VecReductionMul(MoonliftSem.SemCarryPort carry, MoonliftVec.VecExprId value, MoonliftVec.VecReassoc reassoc) unique
                     | VecReductionBitAnd(MoonliftSem.SemCarryPort carry, MoonliftVec.VecExprId value) unique
                     | VecReductionBitOr(MoonliftSem.SemCarryPort carry, MoonliftVec.VecExprId value) unique
                     | VecReductionBitXor(MoonliftSem.SemCarryPort carry, MoonliftVec.VecExprId value) unique

    VecStoreFact = VecStoreFact(MoonliftVec.VecMemoryFact access, MoonliftVec.VecExprId value) unique

    VecProof = VecProofDomain(string reason) unique
             | VecProofRange(MoonliftVec.VecRangeFact range, string reason) unique
             | VecProofNoMemoryDependence(MoonliftVec.VecAccessId* accesses, string reason) unique
             | VecProofReduction(MoonliftVec.VecReductionFact reduction, string reason) unique
             | VecProofNarrowSafe(MoonliftVec.VecReductionFact reduction, MoonliftVec.VecElem narrow_elem, number chunk_elems, string reason) unique
             | VecProofTarget(MoonliftVec.VecTargetFact fact, string reason) unique

    VecLoopFacts = VecLoopFacts(MoonliftVec.VecLoopId loop,
                                MoonliftVec.VecDomain domain,
                                MoonliftVec.VecInduction* inductions,
                                MoonliftVec.VecExprGraph exprs,
                                MoonliftVec.VecMemoryFact* memory,
                                MoonliftVec.VecDependenceFact* dependences,
                                MoonliftVec.VecRangeFact* ranges,
                                MoonliftVec.VecStoreFact* stores,
                                MoonliftVec.VecReductionFact* reductions,
                                MoonliftVec.VecReject* rejects) unique

    VecTail = VecTailNone
            | VecTailScalar
            | VecTailMasked(MoonliftVec.VecProof proof) unique

    VecLoopShape = VecLoopScalar(MoonliftVec.VecLoopId loop, MoonliftVec.VecReject* vector_rejects) unique
                 | VecLoopVector(MoonliftVec.VecLoopId loop,
                                 MoonliftVec.VecShape shape,
                                 number unroll,
                                 MoonliftVec.VecTail tail,
                                 MoonliftVec.VecProof* proofs) unique
                 | VecLoopChunkedNarrowVector(MoonliftVec.VecLoopId loop,
                                               MoonliftVec.VecShape narrow_shape,
                                               number unroll,
                                               number chunk_elems,
                                               MoonliftVec.VecTail tail,
                                               MoonliftVec.VecProof narrow_proof,
                                               MoonliftVec.VecProof* proofs) unique

    VecShapeScore = VecShapeScore(MoonliftVec.VecLoopShape shape,
                                  number elems_per_iter,
                                  number rank,
                                  string rationale) unique

    VecLoopDecision = VecLoopDecision(MoonliftVec.VecLoopFacts facts,
                                      MoonliftVec.VecLoopShape chosen,
                                      MoonliftVec.VecShapeScore* considered) unique

    VecValue = VecScalarValue(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem) unique
             | VecVectorValue(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem, number lanes) unique

    VecParam = VecScalarParam(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem) unique
             | VecVectorParam(MoonliftVec.VecValueId id, MoonliftVec.VecElem elem, number lanes) unique

    VecCmd = VecCmdConstInt(MoonliftVec.VecValueId dst, MoonliftVec.VecElem elem, string raw) unique
           | VecCmdSplat(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecValueId scalar) unique
           | VecCmdRamp(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecValueId base, string* offsets) unique
           | VecCmdBin(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecBinOp op, MoonliftVec.VecValueId lhs, MoonliftVec.VecValueId rhs) unique
           | VecCmdSelect(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecValueId cond, MoonliftVec.VecValueId then_value, MoonliftVec.VecValueId else_value) unique
           | VecCmdIreduce(MoonliftVec.VecValueId dst, MoonliftVec.VecElem narrow_elem, MoonliftVec.VecValueId value, MoonliftVec.VecProof proof) unique
           | VecCmdUextend(MoonliftVec.VecValueId dst, MoonliftVec.VecElem wide_elem, MoonliftVec.VecValueId value) unique
           | VecCmdExtractLane(MoonliftVec.VecValueId dst, MoonliftVec.VecValueId vec, number lane) unique
           | VecCmdHorizontalReduce(MoonliftVec.VecValueId dst, MoonliftVec.VecBinOp op, MoonliftVec.VecValueId* vectors) unique
           | VecCmdLoad(MoonliftVec.VecValueId dst, MoonliftVec.VecShape shape, MoonliftVec.VecMemoryFact access, MoonliftVec.VecValueId addr) unique
           | VecCmdStore(MoonliftVec.VecMemoryFact access, MoonliftVec.VecShape shape, MoonliftVec.VecValueId addr, MoonliftVec.VecValueId value) unique

    VecTerminator = VecJump(MoonliftVec.VecBlockId dest, MoonliftVec.VecValueId* args) unique
                  | VecBrIf(MoonliftVec.VecValueId cond,
                            MoonliftVec.VecBlockId then_block, MoonliftVec.VecValueId* then_args,
                            MoonliftVec.VecBlockId else_block, MoonliftVec.VecValueId* else_args) unique
                  | VecReturnVoid
                  | VecReturnValue(MoonliftVec.VecValueId value) unique

    VecBlock = VecBlock(MoonliftVec.VecBlockId id,
                        MoonliftVec.VecParam* params,
                        MoonliftVec.VecCmd* cmds,
                        MoonliftVec.VecTerminator terminator) unique

    VecFunc = VecFuncScalar(MoonliftSem.SemFunc func, MoonliftVec.VecLoopDecision* decisions) unique
            | VecFuncVector(MoonliftSem.SemFunc func, MoonliftVec.VecLoopDecision* decisions, MoonliftVec.VecBlock* blocks) unique
            | VecFuncMixed(MoonliftSem.SemFunc func, MoonliftVec.VecLoopDecision* decisions, MoonliftVec.VecBlock* blocks) unique

    VecModule = VecModule(MoonliftSem.SemModule source,
                          MoonliftVec.VecTargetModel target,
                          MoonliftVec.VecFunc* funcs) unique
}

module MoonliftBack {
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
    BackSwitchCase = (string raw, MoonliftBack.BackBlockId dest) unique
    BackVec = (MoonliftBack.BackScalar elem, number lanes) unique

    BackCmd = BackCmdCreateSig(MoonliftBack.BackSigId sig, MoonliftBack.BackScalar* params, MoonliftBack.BackScalar* results) unique
            | BackCmdDeclareData(MoonliftBack.BackDataId data, number size, number align) unique
            | BackCmdDataInitZero(MoonliftBack.BackDataId data, number offset, number size) unique
            | BackCmdDataInitInt(MoonliftBack.BackDataId data, number offset, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdDataInitFloat(MoonliftBack.BackDataId data, number offset, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdDataInitBool(MoonliftBack.BackDataId data, number offset, boolean value) unique
            | BackCmdDataAddr(MoonliftBack.BackValId dst, MoonliftBack.BackDataId data) unique
            | BackCmdFuncAddr(MoonliftBack.BackValId dst, MoonliftBack.BackFuncId func) unique
            | BackCmdExternAddr(MoonliftBack.BackValId dst, MoonliftBack.BackExternId func) unique
            | BackCmdDeclareFuncLocal(MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig) unique
            | BackCmdDeclareFuncExport(MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig) unique
            | BackCmdDeclareFuncExtern(MoonliftBack.BackExternId func, string symbol, MoonliftBack.BackSigId sig) unique
            | BackCmdBeginFunc(MoonliftBack.BackFuncId func) unique
            | BackCmdCreateBlock(MoonliftBack.BackBlockId block) unique
            | BackCmdSwitchToBlock(MoonliftBack.BackBlockId block) unique
            | BackCmdSealBlock(MoonliftBack.BackBlockId block) unique
            | BackCmdBindEntryParams(MoonliftBack.BackBlockId block, MoonliftBack.BackValId* values) unique
            | BackCmdAppendBlockParam(MoonliftBack.BackBlockId block, MoonliftBack.BackValId value, MoonliftBack.BackScalar ty) unique
            | BackCmdAppendVecBlockParam(MoonliftBack.BackBlockId block, MoonliftBack.BackValId value, MoonliftBack.BackVec ty) unique
            | BackCmdCreateStackSlot(MoonliftBack.BackStackSlotId slot, number size, number align) unique
            | BackCmdAlias(MoonliftBack.BackValId dst, MoonliftBack.BackValId src) unique
            | BackCmdStackAddr(MoonliftBack.BackValId dst, MoonliftBack.BackStackSlotId slot) unique
            | BackCmdConstInt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdConstFloat(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdConstBool(MoonliftBack.BackValId dst, boolean value) unique
            | BackCmdConstNull(MoonliftBack.BackValId dst) unique
            | BackCmdIneg(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFneg(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdBnot(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdBoolNot(MoonliftBack.BackValId dst, MoonliftBack.BackValId value) unique
            | BackCmdPopcount(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdClz(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdCtz(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdBswap(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdSqrt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdAbs(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFloor(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdCeil(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdTruncFloat(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdRound(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdIadd(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIsub(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdImul(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFadd(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFsub(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFmul(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSdiv(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUdiv(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFdiv(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSrem(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUrem(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBand(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBor(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBxor(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIshl(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUshr(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSshr(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdRotl(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdRotr(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIcmpEq(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIcmpNe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpEq(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpNe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBitcast(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdIreduce(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdSextend(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdUextend(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFpromote(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFdemote(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdSToF(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdUToF(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFToS(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFToU(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdLoad(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId addr) unique
            | BackCmdStore(MoonliftBack.BackScalar ty, MoonliftBack.BackValId addr, MoonliftBack.BackValId value) unique
            | BackCmdMemcpy(MoonliftBack.BackValId dst, MoonliftBack.BackValId src, MoonliftBack.BackValId len) unique
            | BackCmdMemset(MoonliftBack.BackValId dst, MoonliftBack.BackValId byte, MoonliftBack.BackValId len) unique
            | BackCmdSelect(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId cond, MoonliftBack.BackValId then_value, MoonliftBack.BackValId else_value) unique
            | BackCmdFma(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId a, MoonliftBack.BackValId b, MoonliftBack.BackValId c) unique
            | BackCmdVecSplat(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId value) unique
            | BackCmdVecIcmpEq(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecIcmpNe(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecSIcmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecSIcmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecSIcmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecSIcmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecUIcmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecUIcmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecUIcmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecUIcmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecSelect(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId mask, MoonliftBack.BackValId then_value, MoonliftBack.BackValId else_value) unique
            | BackCmdVecMaskNot(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId value) unique
            | BackCmdVecMaskAnd(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecMaskOr(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecIadd(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecIsub(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecImul(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecBand(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecBor(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecBxor(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdVecLoad(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId addr) unique
            | BackCmdVecStore(MoonliftBack.BackVec ty, MoonliftBack.BackValId addr, MoonliftBack.BackValId value) unique
            | BackCmdVecInsertLane(MoonliftBack.BackValId dst, MoonliftBack.BackVec ty, MoonliftBack.BackValId value, MoonliftBack.BackValId lane_value, number lane) unique
            | BackCmdVecExtractLane(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value, number lane) unique
            | BackCmdCallValueDirect(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallStmtDirect(MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallValueExtern(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackExternId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallStmtExtern(MoonliftBack.BackExternId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallValueIndirect(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId callee, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallStmtIndirect(MoonliftBack.BackValId callee, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdJump(MoonliftBack.BackBlockId dest, MoonliftBack.BackValId* args) unique
            | BackCmdBrIf(MoonliftBack.BackValId cond, MoonliftBack.BackBlockId then_block, MoonliftBack.BackValId* then_args, MoonliftBack.BackBlockId else_block, MoonliftBack.BackValId* else_args) unique
            | BackCmdSwitchInt(MoonliftBack.BackValId value, MoonliftBack.BackScalar ty, MoonliftBack.BackSwitchCase* cases, MoonliftBack.BackBlockId default_dest) unique
            | BackCmdReturnVoid
            | BackCmdReturnValue(MoonliftBack.BackValId value) unique
            | BackCmdTrap
            | BackCmdFinishFunc(MoonliftBack.BackFuncId func) unique
            | BackCmdFinalizeModule

    BackFlow = BackFallsThrough | BackTerminates
    BackSigSpec = (MoonliftBack.BackScalar* params, MoonliftBack.BackScalar* results) unique
    BackStackSlotSpec = (number size, number align) unique
    BackExprLowering = BackExprPlan(MoonliftBack.BackCmd* cmds, MoonliftBack.BackValId value, MoonliftBack.BackScalar ty) unique
                     | BackExprTerminated(MoonliftBack.BackCmd* cmds) unique
    BackAddrLowering = BackAddrWrites(MoonliftBack.BackCmd* cmds) unique
                     | BackAddrTerminated(MoonliftBack.BackCmd* cmds) unique
    BackViewLowering = BackViewPlan(MoonliftBack.BackCmd* cmds, MoonliftBack.BackValId data, MoonliftBack.BackValId len, MoonliftBack.BackValId stride) unique
                     | BackViewTerminated(MoonliftBack.BackCmd* cmds) unique
    BackReturnTarget = BackReturnValue
                     | BackReturnSret(MoonliftBack.BackValId addr) unique
    BackStmtPlan = (MoonliftBack.BackCmd* cmds, MoonliftBack.BackFlow flow) unique
    BackFuncPlan = (MoonliftBack.BackCmd* cmds) unique
    BackItemPlan = (MoonliftBack.BackCmd* cmds) unique
    BackProgram = (MoonliftBack.BackCmd* cmds) unique
}
]]

function M.Define(T)
    T:Define(M.SCHEMA)
    return T
end

return M
