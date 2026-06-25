package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Ty = T.LalinType
local Code = T.LalinCode
local LJ = T.LalinLuaJIT
local Expr = require("lalin.luajit_expr")(T)

local function cls(value) return pvm.classof(value) end

local origin = Code.CodeOriginGenerated("luajit expr test")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local a = Code.CodeValueId("v:a")
local b = Code.CodeValueId("v:b")
local dst = Code.CodeValueId("v:sum")
local inst = Code.CodeInst(
    Code.CodeInstId("inst:add"),
    Code.CodeInstBinary(dst, Core.BinAdd, i32, sem, a, b),
    origin
)
local ctx = { value_types = { [a.text] = i32, [b.text] = i32 } }
local stmt = Expr.inst_to_stmt(ctx, inst)
assert(cls(stmt) == LJ.LJStmtLet)
assert(stmt.dst == LJ.LJValueId("sum"))
assert(cls(stmt.expr) == LJ.LJExprIntBinary)
assert(stmt.expr.semantics == sem)
assert(stmt.ty.register == LJ.LJRegTraceInt32(32, Code.CodeSigned))
assert(ctx.value_types[dst.text] == i32)

local f_dst = Code.CodeValueId("v:f")
local f_inst = Code.CodeInst(
    Code.CodeInstId("inst:fadd"),
    Code.CodeInstFloatBinary(f_dst, Core.BinAdd, f64, Code.CodeFloatStrict, a, b),
    origin
)
ctx.value_types[a.text] = f64
ctx.value_types[b.text] = f64
local f_stmt = Expr.inst_to_stmt(ctx, f_inst)
assert(cls(f_stmt.expr) == LJ.LJExprFloatBinary)
assert(f_stmt.ty.register == LJ.LJRegLuaNumber)

local ptr_i32 = Code.CodeTyDataPtr(i32)
local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local ptr_u8 = Code.CodeTyDataPtr(u8)
local view_ty = Code.CodeTyView(i32)
local slice_ty = Code.CodeTySlice(i32)
local view = Code.CodeValueId("v:view")
ctx.value_types[view.text] = view_ty
local slice = Code.CodeValueId("v:slice")
ctx.value_types[slice.text] = slice_ty
local bytespan = Code.CodeValueId("v:bytespan")
ctx.value_types[bytespan.text] = Code.CodeTyByteSpan
local data_dst = Code.CodeValueId("v:data")
ctx.value_types[data_dst.text] = ptr_i32
local byte_data = Code.CodeValueId("v:byte_data")
ctx.value_types[byte_data.text] = ptr_u8
local data_stmt = Expr.inst_to_stmt(ctx, Code.CodeInst(
    Code.CodeInstId("inst:view_data"),
    Code.CodeInstViewData(data_dst, view),
    origin
))
assert(cls(data_stmt.expr) == LJ.LJExprProjectField)
assert(data_stmt.expr.name == "data")
assert(data_stmt.expr.hoist == true)
assert(data_stmt.ty.semantic == ptr_i32)
assert(ctx.value_types[data_dst.text] == ptr_i32)

local mk_dst = Code.CodeValueId("v:made_view")
local mk_stmt = Expr.inst_to_stmt(ctx, Code.CodeInst(
    Code.CodeInstId("inst:view_make"),
    Code.CodeInstViewMake(mk_dst, i32, data_dst, Code.CodeValueId("v:len"), Code.CodeValueId("v:stride")),
    origin
))
assert(cls(mk_stmt.expr) == LJ.LJExprRecord)
assert(#mk_stmt.expr.fields == 3)
assert(ctx.value_types[mk_dst.text] == view_ty)

local slice_dst = Code.CodeValueId("v:made_slice")
local slice_stmt = Expr.inst_to_stmt(ctx, Code.CodeInst(
    Code.CodeInstId("inst:slice_make"),
    Code.CodeInstSliceMake(slice_dst, i32, data_dst, Code.CodeValueId("v:len")),
    origin
))
assert(cls(slice_stmt.expr) == LJ.LJExprRecord)
assert(#slice_stmt.expr.fields == 2)
assert(ctx.value_types[slice_dst.text] == slice_ty)

local bytespan_dst = Code.CodeValueId("v:made_bytespan")
local bytespan_stmt = Expr.inst_to_stmt(ctx, Code.CodeInst(
    Code.CodeInstId("inst:bytespan_make"),
    Code.CodeInstByteSpanMake(bytespan_dst, byte_data, Code.CodeValueId("v:len")),
    origin
))
assert(cls(bytespan_stmt.expr) == LJ.LJExprRecord)
assert(#bytespan_stmt.expr.fields == 2)
assert(ctx.value_types[bytespan_dst.text] == Code.CodeTyByteSpan)

local bool = Code.CodeTyBool8
local sig = Code.CodeSig(Code.CodeSigId("sig:add"), { i32, i32 }, { i32 })
ctx.code_sigs = { [sig.id.text] = sig }
local local_place = Code.CodePlaceLocal(Code.CodeLocalId("local:x"), i32)
local deref_place = Code.CodePlaceDeref(data_dst, i32, 4)
local field_ref = T.LalinSem.FieldByName("x", Ty.TScalar(Core.ScalarI32))
local named_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local variant = Code.CodeVariantRef(named_ty, "some", 1, i32)
local access = Code.CodeMemoryAccess(Code.CodeMemoryReadWrite, i32, 4, Code.CodeMayTrap, false, Core.AtomicSeqCst)
ctx.value_types[data_dst.text] = ptr_i32
ctx.value_types[Code.CodeValueId("v:fn").text] = Code.CodeTyCodePtr(sig.id)
ctx.value_types[Code.CodeValueId("v:ctx").text] = ptr_i32

local next_inst = 0
local function lower_expr(kind)
    next_inst = next_inst + 1
    local stmt = Expr.inst_to_stmt(ctx, Code.CodeInst(Code.CodeInstId("inst:coverage:" .. tostring(next_inst)), kind, origin))
    assert(cls(stmt) == LJ.LJStmtLet)
    return stmt.expr, stmt
end

local coverage = {
    { Code.CodeInstConst(Code.CodeValueId("v:c"), Code.CodeConstLiteral(i32, Core.LitInt("1"))), LJ.LJExprLiteral },
    { Code.CodeInstAlias(Code.CodeValueId("v:alias"), i32, a), LJ.LJExprValue },
    { Code.CodeInstUnary(Code.CodeValueId("v:neg"), Core.UnaryNeg, i32, a), LJ.LJExprUnary },
    { Code.CodeInstBinary(Code.CodeValueId("v:bin"), Core.BinAdd, i32, sem, a, b), LJ.LJExprIntBinary },
    { Code.CodeInstFloatBinary(Code.CodeValueId("v:fbin"), Core.BinAdd, f64, Code.CodeFloatStrict, a, b), LJ.LJExprFloatBinary },
    { Code.CodeInstCompare(Code.CodeValueId("v:cmp"), Core.CmpEq, i32, a, b), LJ.LJExprCompare },
    { Code.CodeInstCast(Code.CodeValueId("v:cast"), Core.MachineCastIdentity, i32, i32, a), LJ.LJExprCast },
    { Code.CodeInstSelect(Code.CodeValueId("v:sel"), i32, Code.CodeValueId("v:cmp"), a, b), LJ.LJExprSelect },
    { Code.CodeInstIntrinsic(Code.CodeValueId("v:pop"), Core.IntrinsicPopcount, i32, { a }), LJ.LJExprIntrinsic },
    { Code.CodeInstAddrOf(Code.CodeValueId("v:addr"), ptr_i32, local_place), LJ.LJExprAddrOfPlace },
    { Code.CodeInstGlobalRef(Code.CodeValueId("v:gref"), Code.CodeGlobalRefFunc(Code.CodeFuncId("fn:add")), Code.CodeTyCodePtr(sig.id)), LJ.LJExprGlobalRef },
    { Code.CodeInstPtrOffset(Code.CodeValueId("v:off"), ptr_i32, data_dst, a, 4, 0), LJ.LJExprPtrOffset },
    { Code.CodeInstLoad(Code.CodeValueId("v:load"), deref_place, access), LJ.LJExprLoad },
    { Code.CodeInstAggregate(Code.CodeValueId("v:agg"), named_ty, { Code.CodeFieldValue(field_ref, a) }), LJ.LJExprRecord },
    { Code.CodeInstArray(Code.CodeValueId("v:arr"), Code.CodeTyArray(i32, 1), { Code.CodeArrayValue(0, a) }), LJ.LJExprArray },
    { Code.CodeInstViewMake(Code.CodeValueId("v:view2"), i32, data_dst, Code.CodeValueId("v:len"), Code.CodeValueId("v:stride")), LJ.LJExprRecord },
    { Code.CodeInstViewData(Code.CodeValueId("v:vdata"), view), LJ.LJExprProjectField },
    { Code.CodeInstViewLen(Code.CodeValueId("v:vlen"), view), LJ.LJExprProjectField },
    { Code.CodeInstViewStride(Code.CodeValueId("v:vstride"), view), LJ.LJExprProjectField },
    { Code.CodeInstSliceMake(Code.CodeValueId("v:slice2"), i32, data_dst, Code.CodeValueId("v:len")), LJ.LJExprRecord },
    { Code.CodeInstSliceData(Code.CodeValueId("v:sdata"), slice), LJ.LJExprProjectField },
    { Code.CodeInstSliceLen(Code.CodeValueId("v:slen"), slice), LJ.LJExprProjectField },
    { Code.CodeInstByteSpanMake(Code.CodeValueId("v:bytespan2"), byte_data, Code.CodeValueId("v:len")), LJ.LJExprRecord },
    { Code.CodeInstByteSpanData(Code.CodeValueId("v:bdata"), bytespan), LJ.LJExprProjectField },
    { Code.CodeInstByteSpanLen(Code.CodeValueId("v:blen"), bytespan), LJ.LJExprProjectField },
    { Code.CodeInstClosure(Code.CodeValueId("v:closure"), Code.CodeTyClosure(sig.id), Code.CodeValueId("v:fn"), Code.CodeValueId("v:ctx"), sig.id), LJ.LJExprClosure },
    { Code.CodeInstVariantCtor(Code.CodeValueId("v:variant"), named_ty, variant, a), LJ.LJExprVariantCtor },
    { Code.CodeInstVariantTag(Code.CodeValueId("v:tag"), i32, Code.CodeValueId("v:variant")), LJ.LJExprVariantTag },
    { Code.CodeInstVariantPayload(Code.CodeValueId("v:payload"), variant, Code.CodeValueId("v:variant")), LJ.LJExprVariantPayload },
    { Code.CodeInstCall(Code.CodeValueId("v:call"), Code.CodeCallDirect(Code.CodeFuncId("fn:add")), sig.id, { a, b }), LJ.LJExprCall },
    { Code.CodeInstAtomicLoad(Code.CodeValueId("v:aload"), deref_place, access, Core.AtomicSeqCst), LJ.LJExprAtomicLoad },
    { Code.CodeInstAtomicRmw(Code.CodeValueId("v:armw"), Core.AtomicRmwAdd, deref_place, a, access, Core.AtomicSeqCst), LJ.LJExprAtomicRmw },
    { Code.CodeInstAtomicCas(Code.CodeValueId("v:acas"), deref_place, a, b, access, Core.AtomicSeqCst), LJ.LJExprAtomicCas },
}

for i = 1, #coverage do
    local got = lower_expr(coverage[i][1])
    assert(cls(got) == coverage[i][2], "coverage case " .. tostring(i) .. " lowered to " .. tostring(cls(got)))
end

local store_stmt = Expr.inst_to_stmt(ctx, Code.CodeInst(Code.CodeInstId("inst:store"), Code.CodeInstStore(deref_place, a, access), origin))
assert(cls(store_stmt) == LJ.LJStmtStore)
local void_call = Expr.inst_to_stmt(ctx, Code.CodeInst(Code.CodeInstId("inst:void_call"), Code.CodeInstCall(nil, Code.CodeCallDirect(Code.CodeFuncId("fn:add")), sig.id, { a, b }), origin))
assert(cls(void_call) == LJ.LJStmtCall)
local void_intr = Expr.inst_to_stmt(ctx, Code.CodeInst(Code.CodeInstId("inst:void_intr"), Code.CodeInstIntrinsic(nil, Core.IntrinsicAssume, Code.CodeTyVoid, { Code.CodeValueId("v:cmp") }), origin))
assert(cls(void_intr) == LJ.LJStmtIntrinsic)
local astore = Expr.inst_to_stmt(ctx, Code.CodeInst(Code.CodeInstId("inst:astore"), Code.CodeInstAtomicStore(deref_place, a, access, Core.AtomicSeqCst), origin))
assert(cls(astore) == LJ.LJStmtAtomicStore)
local fence = Expr.inst_to_stmt(ctx, Code.CodeInst(Code.CodeInstId("inst:fence"), Code.CodeInstAtomicFence(Core.AtomicSeqCst), origin))
assert(cls(fence) == LJ.LJStmtAtomicFence)

io.write("lalin luajit_expr ok\n")
