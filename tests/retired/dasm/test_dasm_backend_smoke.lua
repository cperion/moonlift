-- tests/retired/dasm/test_dasm_backend_smoke.lua — end-to-end smoke test using ASDL BackProgram

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lib/?.lua;" ..
               "./.vendor/LuaJIT/dynasm/?.lua;" .. package.path

local ffi       = require("ffi")
local pvm       = require("lalin.pvm")
local A2        = require("lalin.schema_projection")
local dasm_init = require("back.dasm")

local T = pvm.context()
A2(T)
local dasm_api = dasm_init(T)

local B2 = T.LalinBack
local C2 = T.LalinCore

local function sid(text) return B2.BackSigId(text) end
local function fid(text) return B2.BackFuncId(text) end
local function bid(text) return B2.BackBlockId(text) end
local function vid(text) return B2.BackValId(text) end
local i32 = B2.BackI32
local shape_i32 = B2.BackShapeScalar(i32)

-- Test 1: Simple add1
print("test 1: add1...")
local add1_sig = sid("sig:add1")
local add1_func = fid("add1")
local add1_entry = bid("entry.add1")
local arg = vid("arg")
local one = vid("one")
local sum = vid("sum")

local program1 = B2.BackProgram({
    B2.CmdCreateSig(add1_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, add1_func, add1_sig),
    B2.CmdBeginFunc(add1_func),
    B2.CmdCreateBlock(add1_entry),
    B2.CmdSwitchToBlock(add1_entry),
    B2.CmdBindEntryParams(add1_entry, { arg }),
    B2.CmdConst(one, i32, B2.BackLitInt("1")),
    B2.CmdIntBinary(sum, B2.BackIntAdd, i32, B2.BackIntSemantics(B2.BackIntWrap, B2.BackIntMayLose), arg, one),
    B2.CmdReturnValue(sum),
    B2.CmdSealBlock(add1_entry),
    B2.CmdFinishFunc(add1_func),
    B2.CmdFinalizeModule,
})

local jit = dasm_api.jit()
local artifact = jit:compile(program1)
local ptr = artifact:getpointer("add1")
local add1 = ffi.cast("int32_t (*)(int32_t)", ptr)
assert(add1(41) == 42, "add1(41) != 42")
assert(add1(-5) == -4, "add1(-5) != -4")
artifact:free()
print("  OK")

-- Test 2: Two-arg add
print("test 2: add_i32...")
local add_sig = sid("sig:add_i32")
local add_func = fid("add_i32")
local add_entry = bid("entry.add_i32")
local a = vid("a")
local b = vid("b")
local r = vid("r")

local program2 = B2.BackProgram({
    B2.CmdCreateSig(add_sig, { i32, i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, add_func, add_sig),
    B2.CmdBeginFunc(add_func),
    B2.CmdCreateBlock(add_entry),
    B2.CmdSwitchToBlock(add_entry),
    B2.CmdBindEntryParams(add_entry, { a, b }),
    B2.CmdIntBinary(r, B2.BackIntAdd, i32, B2.BackIntSemantics(B2.BackIntWrap, B2.BackIntMayLose), a, b),
    B2.CmdReturnValue(r),
    B2.CmdSealBlock(add_entry),
    B2.CmdFinishFunc(add_func),
    B2.CmdFinalizeModule,
})

jit = dasm_api.jit()
artifact = jit:compile(program2)
local add_i32 = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer("add_i32"))
assert(add_i32(20, 22) == 42)
assert(add_i32(-10, 3) == -7)
artifact:free()
print("  OK")

-- Test 3: Branch + select
print("test 3: branch + select...")
local select_sig = sid("sig:select_abs_i32")
local select_func = fid("select_abs_i32")
local select_entry = bid("entry.select_abs_i32")
local sx = vid("x")
local zero = vid("select.zero")
local neg = vid("select.neg")
local cond = vid("select.cond")
local out = vid("select.out")

local branch_sig = sid("sig:branch_sign_i32")
local branch_func = fid("branch_sign_i32")
local branch_entry = bid("entry.branch_sign_i32")
local branch_neg = bid("branch_sign_i32.neg")
local branch_nonneg = bid("branch_sign_i32.nonneg")
local bx = vid("branch.x")
local bzero = vid("branch.zero")
local bcond = vid("branch.cond")
local bneg_ret = vid("branch.ret.neg")
local bnonneg_ret = vid("branch.ret.nonneg")

local program3 = B2.BackProgram({
    B2.CmdCreateSig(select_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, select_func, select_sig),
    B2.CmdBeginFunc(select_func),
    B2.CmdCreateBlock(select_entry),
    B2.CmdSwitchToBlock(select_entry),
    B2.CmdBindEntryParams(select_entry, { sx }),
    B2.CmdConst(zero, i32, B2.BackLitInt("0")),
    B2.CmdUnary(neg, B2.BackUnaryIneg, shape_i32, sx),
    B2.CmdCompare(cond, B2.BackSIcmpLt, shape_i32, sx, zero),
    B2.CmdSelect(out, shape_i32, cond, neg, sx),
    B2.CmdReturnValue(out),
    B2.CmdSealBlock(select_entry),
    B2.CmdFinishFunc(select_func),

    B2.CmdCreateSig(branch_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, branch_func, branch_sig),
    B2.CmdBeginFunc(branch_func),
    B2.CmdCreateBlock(branch_entry),
    B2.CmdCreateBlock(branch_neg),
    B2.CmdCreateBlock(branch_nonneg),
    B2.CmdSwitchToBlock(branch_entry),
    B2.CmdBindEntryParams(branch_entry, { bx }),
    B2.CmdConst(bzero, i32, B2.BackLitInt("0")),
    B2.CmdCompare(bcond, B2.BackSIcmpLt, shape_i32, bx, bzero),
    B2.CmdBrIf(bcond, branch_neg, {}, branch_nonneg, {}),
    B2.CmdSwitchToBlock(branch_neg),
    B2.CmdConst(bneg_ret, i32, B2.BackLitInt("-1")),
    B2.CmdReturnValue(bneg_ret),
    B2.CmdSealBlock(branch_neg),
    B2.CmdSwitchToBlock(branch_nonneg),
    B2.CmdConst(bnonneg_ret, i32, B2.BackLitInt("1")),
    B2.CmdReturnValue(bnonneg_ret),
    B2.CmdSealBlock(branch_nonneg),
    B2.CmdSealBlock(branch_entry),
    B2.CmdFinishFunc(branch_func),
    B2.CmdFinalizeModule,
})

jit = dasm_api.jit()
artifact = jit:compile(program3)
local select_abs = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer("select_abs_i32"))
assert(select_abs(-42) == 42, "select_abs(-42) != 42")
assert(select_abs(17) == 17, "select_abs(17) != 17")
local branch_sign = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer("branch_sign_i32"))
assert(branch_sign(-1) == -1)
assert(branch_sign(0) == 1)
assert(branch_sign(99) == 1)
artifact:free()
print("  OK")

-- Test 4: Direct function call
print("test 4: direct call...")
local inc_sig = sid("sig:inc_i32")
local inc_func = fid("inc_i32")
local inc_entry = bid("entry.inc_i32")
local ix = vid("inc.x")
local ione = vid("inc.one")
local inc_out = vid("inc.out")

local call_sig = sid("sig:call_inc_i32")
local call_func = fid("call_inc_i32")
local call_entry = bid("entry.call_inc_i32")
local cx = vid("call.x")
local call_out = vid("call.out")

local program4 = B2.BackProgram({
    B2.CmdCreateSig(inc_sig, { i32 }, { i32 }),
    B2.CmdCreateSig(call_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityLocal, inc_func, inc_sig),
    B2.CmdDeclareFunc(C2.VisibilityExport, call_func, call_sig),

    B2.CmdBeginFunc(inc_func),
    B2.CmdCreateBlock(inc_entry),
    B2.CmdSwitchToBlock(inc_entry),
    B2.CmdBindEntryParams(inc_entry, { ix }),
    B2.CmdConst(ione, i32, B2.BackLitInt("1")),
    B2.CmdIntBinary(inc_out, B2.BackIntAdd, i32, B2.BackIntSemantics(B2.BackIntWrap, B2.BackIntMayLose), ix, ione),
    B2.CmdReturnValue(inc_out),
    B2.CmdSealBlock(inc_entry),
    B2.CmdFinishFunc(inc_func),

    B2.CmdBeginFunc(call_func),
    B2.CmdCreateBlock(call_entry),
    B2.CmdSwitchToBlock(call_entry),
    B2.CmdBindEntryParams(call_entry, { cx }),
    B2.CmdCall(B2.BackCallValue(call_out, i32), B2.BackCallDirect(inc_func), inc_sig, { cx }),
    B2.CmdReturnValue(call_out),
    B2.CmdSealBlock(call_entry),
    B2.CmdFinishFunc(call_func),
    B2.CmdFinalizeModule,
})

jit = dasm_api.jit()
artifact = jit:compile(program4)
local call_inc = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer("call_inc_i32"))
assert(call_inc(41) == 42, "call_inc(41) != 42")
assert(call_inc(-8) == -7, "call_inc(-8) != -7")
artifact:free()
print("  OK")

print("OK — DynASM backend smoke test passed (ASDL BackProgram format)")
