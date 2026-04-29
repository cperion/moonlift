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

local C2 = T.MoonCore
local B2 = T.MoonBack
local B2 = T.MoonBack

local function sid(text) return B2.BackSigId(text) end
local function fid(text) return B2.BackFuncId(text) end
local function bid(text) return B2.BackBlockId(text) end
local function vid(text) return B2.BackValId(text) end
local function did(text) return B2.BackDataId(text) end
local i32 = B2.BackI32
local bool = B2.BackBool
local shape_i32 = B2.BackShapeScalar(i32)
local shape_bool = B2.BackShapeScalar(bool)
local function mem(id, mode) return B2.BackMemoryInfo(B2.BackAccessId(id), B2.BackAlignUnknown, B2.BackDerefUnknown, B2.BackMayTrap, B2.BackMayNotMove, mode) end
local function addr(base, off) return B2.BackAddress(B2.BackAddrValue(base), off, B2.BackProvUnknown, B2.BackPtrBoundsUnknown) end

local zero_data = did("data:zero")
local zero_sig = sid("sig:get_zero")
local zero_func = fid("get_zero")
local zero_entry = bid("entry.get_zero")
local zaddr = vid("zero.addr")
local zoff = vid("zero.off")
local zval = vid("zero.val")

local alias_sig = sid("sig:alias_add")
local alias_func = fid("alias_add")
local alias_entry = bid("entry.alias_add")
local ax = vid("alias.x")
local ay = vid("alias.y")
local aone = vid("alias.one")
local asum = vid("alias.sum")

local bit_sig = sid("sig:bit_mix")
local bit_func = fid("bit_mix")
local bit_entry = bid("entry.bit_mix")
local bx = vid("bit.x")
local bmask = vid("bit.mask")
local band = vid("bit.and")
local bnot = vid("bit.not")
local bor = vid("bit.or")

local bool_sig = sid("sig:not_to_i32")
local bool_func = fid("not_to_i32")
local bool_entry = bid("entry.not_to_i32")
local flag = vid("flag")
local not_flag = vid("not.flag")
local one_i = vid("bool.one")
local zero_i = vid("bool.zero")
local bool_out = vid("bool.out")

local program = B2.BackProgram({
    B2.CmdDeclareData(zero_data, 4, 4),
    B2.CmdDataInitZero(zero_data, 0, 4),

    B2.CmdCreateSig(zero_sig, {}, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, zero_func, zero_sig),
    B2.CmdBeginFunc(zero_func),
    B2.CmdCreateBlock(zero_entry),
    B2.CmdSwitchToBlock(zero_entry),
    B2.CmdDataAddr(zaddr, zero_data),
    B2.CmdConst(zoff, B2.BackIndex, B2.BackLitInt("0")),
    B2.CmdLoadInfo(zval, shape_i32, addr(zaddr, zoff), mem("get_zero:load", B2.BackAccessRead)),
    B2.CmdReturnValue(zval),
    B2.CmdSealBlock(zero_entry),
    B2.CmdFinishFunc(zero_func),

    B2.CmdCreateSig(alias_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, alias_func, alias_sig),
    B2.CmdBeginFunc(alias_func),
    B2.CmdCreateBlock(alias_entry),
    B2.CmdSwitchToBlock(alias_entry),
    B2.CmdBindEntryParams(alias_entry, { ax }),
    B2.CmdAlias(ay, ax),
    B2.CmdConst(aone, i32, B2.BackLitInt("1")),
    B2.CmdIntBinary(asum, B2.BackIntAdd, i32, B2.BackIntSemantics(B2.BackIntWrap, B2.BackIntMayLose), ay, aone),
    B2.CmdReturnValue(asum),
    B2.CmdSealBlock(alias_entry),
    B2.CmdFinishFunc(alias_func),

    B2.CmdCreateSig(bit_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, bit_func, bit_sig),
    B2.CmdBeginFunc(bit_func),
    B2.CmdCreateBlock(bit_entry),
    B2.CmdSwitchToBlock(bit_entry),
    B2.CmdBindEntryParams(bit_entry, { bx }),
    B2.CmdConst(bmask, i32, B2.BackLitInt("15")),
    B2.CmdBitBinary(band, B2.BackBitAnd, i32, bx, bmask),
    B2.CmdUnary(bnot, B2.BackUnaryBnot, shape_i32, bx),
    B2.CmdBitBinary(bor, B2.BackBitOr, i32, band, bnot),
    B2.CmdReturnValue(bor),
    B2.CmdSealBlock(bit_entry),
    B2.CmdFinishFunc(bit_func),

    B2.CmdCreateSig(bool_sig, { bool }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, bool_func, bool_sig),
    B2.CmdBeginFunc(bool_func),
    B2.CmdCreateBlock(bool_entry),
    B2.CmdSwitchToBlock(bool_entry),
    B2.CmdBindEntryParams(bool_entry, { flag }),
    B2.CmdUnary(not_flag, B2.BackUnaryBoolNot, shape_bool, flag),
    B2.CmdConst(one_i, i32, B2.BackLitInt("1")),
    B2.CmdConst(zero_i, i32, B2.BackLitInt("0")),
    B2.CmdSelect(bool_out, shape_i32, not_flag, one_i, zero_i),
    B2.CmdReturnValue(bool_out),
    B2.CmdSealBlock(bool_entry),
    B2.CmdFinishFunc(bool_func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)
local jit = jit_api.jit()
local artifact = jit:compile(program)

local get_zero = ffi.cast("int32_t (*)()", artifact:getpointer(B2.BackFuncId("get_zero")))
assert(get_zero() == 0)

local alias_add = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("alias_add")))
assert(alias_add(41) == 42)

local bit_mix = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("bit_mix")))
assert(bit_mix(0) == -1)

local not_to_i32 = ffi.cast("int32_t (*)(bool)", artifact:getpointer(B2.BackFuncId("not_to_i32")))
assert(not_to_i32(false) == 1)
assert(not_to_i32(true) == 0)

artifact:free()
print("moonlift back_zero_alias_ops ok")
