package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Back = T.MoonBack
local LJ = T.MoonLuaJIT

assert(LJ ~= nil, "MoonLuaJIT namespace should be installed")

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

io.write("moonlift schema_luajit ok\n")
