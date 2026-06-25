package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Back = T.LalinBack
local Value = T.LalinValue
local Kernel = T.LalinKernel
local Stencil = T.LalinStencil
local LJ = T.LalinLuaJIT

assert(LJ ~= nil, "LalinLuaJIT namespace should be installed")

local i32_c = LJ.LJCTypeScalar(Back.BackI32, "int32_t")
local void_c = LJ.LJCTypeVoid
local i32_ty = LJ.LJPhysicalType(
    Code.CodeTyInt(32, Code.CodeSigned),
    LJ.LJRegTraceInt32(32, Code.CodeSigned),
    i32_c,
    i32_c
)
local ptr_i32_c = LJ.LJCTypePointer(i32_c, true)
local ptr_i32_ty = LJ.LJPhysicalType(nil, LJ.LJRegCData(ptr_i32_c), ptr_i32_c, ptr_i32_c)

assert(i32_ty.register == LJ.LJRegTraceInt32(32, Code.CodeSigned), "i32 registers should force trace-int arithmetic")
assert(i32_ty.storage == i32_c and i32_ty.abi == i32_c, "i32 storage/ABI should use C scalar type")
assert(ptr_i32_ty.register.ty == ptr_i32_c, "pointers should be cdata registers")

local sig = LJ.LJFuncSig(
    LJ.LJFuncSigId("sig:sum_positive_i32"),
    { ptr_i32_ty, i32_ty },
    i32_ty,
    "int32_t (*)(int32_t*, int32_t)"
)
assert(sig.params[1] == ptr_i32_ty and sig.result == i32_ty)

local items = LJ.LJValueId("items")
local n = LJ.LJValueId("n")
local item = LJ.LJValueId("item")
local acc = LJ.LJValueId("acc")
local source_id = LJ.LJMachineId("m:source")
local map_id = LJ.LJMachineId("m:map")
local filter_id = LJ.LJMachineId("m:filter")
local fold_id = LJ.LJMachineId("m:fold")

local zero = LJ.LJExprLiteral(Core.LitInt("0"), i32_ty)
local one = LJ.LJExprLiteral(Core.LitInt("1"), i32_ty)
local item_expr = LJ.LJExprValue(item)
local wrap_sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local plus_one = LJ.LJExprIntBinary(Core.BinAdd, i32_ty, wrap_sem, item_expr, one)
local keep_positive = LJ.LJExprCompare(Core.CmpGt, i32_ty, item_expr, zero)
local sum_step = LJ.LJExprIntBinary(Core.BinAdd, i32_ty, wrap_sem, LJ.LJExprValue(acc), item_expr)

local source = LJ.LJMachine(
    source_id,
    LJ.LJMachineSourceArray(items, i32_ty, LJ.LJExprValue(n)),
    i32_ty,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local map = LJ.LJMachine(
    map_id,
    LJ.LJMachineMap(source_id, item, plus_one),
    i32_ty,
    LJ.LJStateUpstream(source_id),
    LJ.LJTraceFusePreferred
)
local filter = LJ.LJMachine(
    filter_id,
    LJ.LJMachineFilter(map_id, item, keep_positive),
    i32_ty,
    LJ.LJStateUpstream(map_id),
    LJ.LJTraceFusePreferred
)
local fold = LJ.LJMachine(
    fold_id,
    LJ.LJMachineFold(filter_id, acc, item, zero, sum_step),
    i32_ty,
    LJ.LJStateUpstream(filter_id),
    LJ.LJTraceFusePreferred
)
local func = LJ.LJFunc(
    LJ.LJFuncId("fn:sum_positive_i32"),
    nil,
    "sum_positive_i32",
    sig.id,
    {
        LJ.LJParam(items, "items", ptr_i32_ty),
        LJ.LJParam(n, "n", i32_ty),
    },
    {
        LJ.LJCDeclTypedef(LJ.LJTypeId("ml_i32"), "ml_i32", i32_c),
        LJ.LJCDeclRaw("typedef int32_t ml_i32;", "stable FFI spelling for generated code"),
    },
    { source, map, filter, fold },
    LJ.LJBodyMachine(fold_id, LJ.LJTerminalFold(zero, sum_step)),
    LJ.LJTraceHot
)
local module = LJ.LJModule(nil, { func }, { sig }, {}, {})

assert(module.funcs[1].machines[4].kind.input == filter_id, "fold should consume filter machine")
assert(module.funcs[1].body.machine == fold_id, "function body should expose terminal machine")
assert(module.funcs[1].cdefs[1].ty == i32_c, "cdefs should carry FFI C physical type")
assert(void_c == LJ.LJCTypeVoid, "void C type singleton should be available")

local init = Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyInt(32, Code.CodeSigned), Core.LitInt("0")))
local descriptor = Stencil.StencilDescriptorReduce(
    Stencil.StencilDomainRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilDomainForward),
    {
        Stencil.StencilAccess("xs", Stencil.StencilAccessRead, Code.CodeTyInt(32, Code.CodeSigned), Stencil.StencilTopologyContiguous(1)),
        Stencil.StencilAccess("acc", Stencil.StencilAccessReduce, Code.CodeTyInt(32, Code.CodeSigned), Stencil.StencilTopologyScalar(init)),
    },
    Stencil.StencilReducer(Value.ReductionAdd, Code.CodeTyInt(32, Code.CodeSigned), init, nil, nil),
    Code.CodeTyInt(32, Code.CodeSigned)
)
local artifact = Stencil.StencilArtifact(
    Stencil.StencilInstance(
        Stencil.StencilInstanceId("stencil:test"),
        descriptor,
        Stencil.StencilScheduleScalar(Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, Stencil.StencilMachineNative, {})),
        Stencil.StencilAbi({ Code.CodeTyDataPtr(Code.CodeTyInt(32, Code.CodeSigned)), Code.CodeTyInt(32, Code.CodeSigned) }, Code.CodeTyInt(32, Code.CodeSigned)),
        {}
    ),
    Stencil.StencilProviderC,
    Stencil.StencilSymbolId("ml_stencil_test"),
    "int32_t ml_stencil_test(const int32_t*, int32_t);",
    Stencil.StencilArtifactFingerprint("test:fingerprint"),
    nil,
    {},
    {}
)
local stencil_machine = LJ.LJMachine(
    LJ.LJMachineId("m:stencil"),
    LJ.LJMachineStencilCall(artifact, { LJ.LJExprValue(items), LJ.LJExprValue(n) }, i32_ty),
    i32_ty,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local stencil_machine_plan = LJ.LJStencilMachinePlan(
    Code.CodeFuncId("fn:sum_positive_i32"),
    Kernel.KernelId("kernel:sum_positive_i32"),
    stencil_machine,
    artifact
)
assert(stencil_machine_plan.machine == stencil_machine, "stencil machine plan should carry the projected machine")
assert(stencil_machine_plan.artifact == artifact, "stencil machine plan should carry the selected artifact")

local install = LJ.LJMCInstallPolicy(LJ.LJMCInstallLow32Address, LJ.LJMCInstallWriteThenExec)
assert(install.address == LJ.LJMCInstallLow32Address, "MC bank install policy should carry address constraints")
assert(install.protection == LJ.LJMCInstallWriteThenExec, "MC bank install policy should carry W^X policy")
local local_abs = LJ.LJMCPatchRecord(4, LJ.LJMCPatchLocalAbs32, "R_X86_64_32S", nil, nil, 16)
assert(local_abs.kind == LJ.LJMCPatchLocalAbs32, "binary patch records should represent local absolute32 relocations")
local local_abs64 = LJ.LJMCPatchRecord(8, LJ.LJMCPatchLocalAbs64, "R_X86_64_64", nil, nil, 24)
assert(local_abs64.kind == LJ.LJMCPatchLocalAbs64, "binary patch records should represent local absolute64 relocations")

io.write("lalin schema_luajit ok\n")
