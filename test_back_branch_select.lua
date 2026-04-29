package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local J = require("moonlift.back_jit")
local Validate = require("moonlift.back_validate")

local T = pvm.context()
A2.Define(T)
local validate = Validate.Define(T)
local jit_api = J.Define(T)

local C2 = T.Moon2Core
local B2 = T.Moon2Back
local B2 = T.Moon2Back

local function sid(text) return B2.BackSigId(text) end
local function fid(text) return B2.BackFuncId(text) end
local function bid(text) return B2.BackBlockId(text) end
local function vid(text) return B2.BackValId(text) end
local i32 = B2.BackI32
local bool = B2.BackBool
local shape_i32 = B2.BackShapeScalar(i32)

local select_sig = sid("sig:select_abs_i32")
local select_func = fid("select_abs_i32")
local select_entry = bid("entry.select_abs_i32")
local x = vid("x")
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

local program = B2.BackProgram({
    B2.CmdCreateSig(select_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, select_func, select_sig),
    B2.CmdBeginFunc(select_func),
    B2.CmdCreateBlock(select_entry),
    B2.CmdSwitchToBlock(select_entry),
    B2.CmdBindEntryParams(select_entry, { x }),
    B2.CmdConst(zero, i32, B2.BackLitInt("0")),
    B2.CmdUnary(neg, B2.BackUnaryIneg, shape_i32, x),
    B2.CmdCompare(cond, B2.BackSIcmpLt, shape_i32, x, zero),
    B2.CmdSelect(out, shape_i32, cond, neg, x),
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

local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)

local select_ptr = artifact:getpointer(B2.BackFuncId("select_abs_i32"))
local select_abs_i32 = ffi.cast("int32_t (*)(int32_t)", select_ptr)
assert(select_abs_i32(-42) == 42)
assert(select_abs_i32(17) == 17)

local branch_ptr = artifact:getpointer(B2.BackFuncId("branch_sign_i32"))
local branch_sign_i32 = ffi.cast("int32_t (*)(int32_t)", branch_ptr)
assert(branch_sign_i32(-1) == -1)
assert(branch_sign_i32(0) == 1)
assert(branch_sign_i32(99) == 1)

artifact:free()

print("moonlift back_branch_select ok")
