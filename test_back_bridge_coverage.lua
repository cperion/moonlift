package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A1 = require("moonlift_legacy.asdl")
local A2 = require("moonlift.asdl")
local Bridge = require("moonlift.back_to_moonlift")
local Validate = require("moonlift.back_validate")

local T = pvm.context()
A1.Define(T)
A2.Define(T)
local bridge = Bridge.Define(T)
local validate = Validate.Define(T)

local C = T.Moon2Core
local B = T.Moon2Back
local Old = T.MoonliftBack

local function sid(text) return B.BackSigId(text) end
local function fid(text) return B.BackFuncId(text) end
local function xid(text) return B.BackExternId(text) end
local function did(text) return B.BackDataId(text) end
local function bid(text) return B.BackBlockId(text) end
local function vid(text) return B.BackValId(text) end
local function ssid(text) return B.BackStackSlotId(text) end

local scalar = B.BackI32
local scalar_shape = B.BackShapeScalar(B.BackI32)
local bool_shape = B.BackShapeScalar(B.BackBool)
local vec = B.BackVec(B.BackI32, 4)
local vec_shape = B.BackShapeVec(vec)

local s = sid("sig")
local f = fid("f")
local x = xid("x")
local d = did("d")
local b = bid("b")
local b2 = bid("b2")
local v = vid("v")
local v2 = vid("v2")
local v3 = vid("v3")
local v4 = vid("v4")
local slot = ssid("slot")

local function bridge_one(cmd)
    local out = pvm.one(bridge.cmd(cmd))
    assert(out ~= nil)
    return out
end

local function fact_count(cmd)
    local g, p, c = validate.cmd_facts(cmd, 1)
    return #pvm.drain(g, p, c)
end

local commands = {
    B.CmdCreateSig(s, { B.BackI32 }, { B.BackI32 }),
    B.CmdDeclareData(d, 8, 8),
    B.CmdDataInitZero(d, 0, 4),
    B.CmdDataInit(d, 0, B.BackI32, B.BackLitInt("1")),
    B.CmdDataInit(d, 0, B.BackF32, B.BackLitFloat("1.5")),
    B.CmdDataInit(d, 0, B.BackBool, B.BackLitBool(true)),
    B.CmdDataInit(d, 0, B.BackPtr, B.BackLitNull),
    B.CmdDataAddr(v, d),
    B.CmdFuncAddr(v, f),
    B.CmdExternAddr(v, x),
    B.CmdDeclareFunc(C.VisibilityLocal, f, s),
    B.CmdDeclareFunc(C.VisibilityExport, f, s),
    B.CmdDeclareExtern(x, "host", s),
    B.CmdBeginFunc(f),
    B.CmdCreateBlock(b),
    B.CmdSwitchToBlock(b),
    B.CmdSealBlock(b),
    B.CmdBindEntryParams(b, { v, v2 }),
    B.CmdAppendBlockParam(b, v, scalar_shape),
    B.CmdAppendBlockParam(b, v, vec_shape),
    B.CmdCreateStackSlot(slot, 4, 4),
    B.CmdAlias(v2, v),
    B.CmdStackAddr(v, slot),
    B.CmdConst(v, B.BackI32, B.BackLitInt("1")),
    B.CmdConst(v, B.BackF32, B.BackLitFloat("1.5")),
    B.CmdConst(v, B.BackBool, B.BackLitBool(true)),
    B.CmdConst(v, B.BackPtr, B.BackLitNull),
    B.CmdLoad(v, scalar_shape, v2),
    B.CmdLoad(v, vec_shape, v2),
    B.CmdStore(scalar_shape, v, v2),
    B.CmdStore(vec_shape, v, v2),
    B.CmdMemcpy(v, v2, v3),
    B.CmdMemset(v, v2, v3),
    B.CmdSelect(v, scalar_shape, v2, v, v3),
    B.CmdFma(v, B.BackF32, v, v2, v3),
    B.CmdVecSplat(v, vec, v2),
    B.CmdVecInsertLane(v, vec, v2, v3, 0),
    B.CmdVecExtractLane(v, B.BackI32, v2, 0),
    B.CmdCall(B.BackCallStmt, B.BackCallDirect(f), s, { v }),
    B.CmdCall(B.BackCallValue(v, B.BackI32), B.BackCallDirect(f), s, { v }),
    B.CmdCall(B.BackCallStmt, B.BackCallExtern(x), s, { v }),
    B.CmdCall(B.BackCallValue(v, B.BackI32), B.BackCallExtern(x), s, { v }),
    B.CmdCall(B.BackCallStmt, B.BackCallIndirect(v), s, { v2 }),
    B.CmdCall(B.BackCallValue(v, B.BackI32), B.BackCallIndirect(v2), s, { v3 }),
    B.CmdJump(b, { v }),
    B.CmdBrIf(v, b, { v2 }, b2, { v3 }),
    B.CmdSwitchInt(v, B.BackI32, { B.BackSwitchCase("1", b) }, b2),
    B.CmdReturnVoid,
    B.CmdReturnValue(v),
    B.CmdTrap,
    B.CmdFinishFunc(f),
    B.CmdFinalizeModule,
}

local unary_ops = { B.BackUnaryIneg, B.BackUnaryFneg, B.BackUnaryBnot, B.BackUnaryBoolNot }
for i = 1, #unary_ops do
    commands[#commands + 1] = B.CmdUnary(v, unary_ops[i], unary_ops[i] == B.BackUnaryBoolNot and bool_shape or scalar_shape, v2)
end

local intrinsic_ops = {
    B.BackIntrinsicPopcount, B.BackIntrinsicClz, B.BackIntrinsicCtz, B.BackIntrinsicBswap,
    B.BackIntrinsicSqrt, B.BackIntrinsicAbs, B.BackIntrinsicFloor, B.BackIntrinsicCeil,
    B.BackIntrinsicTruncFloat, B.BackIntrinsicRound,
}
for i = 1, #intrinsic_ops do
    commands[#commands + 1] = B.CmdIntrinsic(v, intrinsic_ops[i], scalar_shape, { v2 })
end

local binary_ops = {
    B.BackIadd, B.BackIsub, B.BackImul, B.BackFadd, B.BackFsub, B.BackFmul,
    B.BackSdiv, B.BackUdiv, B.BackFdiv, B.BackSrem, B.BackUrem,
    B.BackBand, B.BackBor, B.BackBxor, B.BackIshl, B.BackUshr, B.BackSshr,
    B.BackRotl, B.BackRotr,
}
for i = 1, #binary_ops do
    commands[#commands + 1] = B.CmdBinary(v, binary_ops[i], scalar_shape, v2, v3)
end
local vec_binary_ops = { B.BackVecIadd, B.BackVecIsub, B.BackVecImul, B.BackVecBand, B.BackVecBor, B.BackVecBxor }
for i = 1, #vec_binary_ops do
    commands[#commands + 1] = B.CmdBinary(v, vec_binary_ops[i], vec_shape, v2, v3)
end

local compare_ops = {
    B.BackIcmpEq, B.BackIcmpNe,
    B.BackSIcmpLt, B.BackSIcmpLe, B.BackSIcmpGt, B.BackSIcmpGe,
    B.BackUIcmpLt, B.BackUIcmpLe, B.BackUIcmpGt, B.BackUIcmpGe,
    B.BackFCmpEq, B.BackFCmpNe, B.BackFCmpLt, B.BackFCmpLe, B.BackFCmpGt, B.BackFCmpGe,
}
for i = 1, #compare_ops do
    commands[#commands + 1] = B.CmdCompare(v, compare_ops[i], scalar_shape, v2, v3)
end

local vec_compare_ops = {
    B.BackVecIcmpEq, B.BackVecIcmpNe,
    B.BackVecSIcmpLt, B.BackVecSIcmpLe, B.BackVecSIcmpGt, B.BackVecSIcmpGe,
    B.BackVecUIcmpLt, B.BackVecUIcmpLe, B.BackVecUIcmpGt, B.BackVecUIcmpGe,
}
for i = 1, #vec_compare_ops do
    commands[#commands + 1] = B.CmdVecCompare(v, vec_compare_ops[i], vec, v2, v3)
end
commands[#commands + 1] = B.CmdVecSelect(v, vec, v2, v3, v4)
commands[#commands + 1] = B.CmdVecMask(v, B.BackVecMaskNot, vec, { v2 })
commands[#commands + 1] = B.CmdVecMask(v, B.BackVecMaskAnd, vec, { v2, v3 })
commands[#commands + 1] = B.CmdVecMask(v, B.BackVecMaskOr, vec, { v2, v3 })

local cast_ops = {
    B.BackBitcast, B.BackIreduce, B.BackSextend, B.BackUextend, B.BackFpromote,
    B.BackFdemote, B.BackSToF, B.BackUToF, B.BackFToS, B.BackFToU,
}
for i = 1, #cast_ops do
    commands[#commands + 1] = B.CmdCast(v, cast_ops[i], B.BackI32, v2)
end

for i = 1, #commands do
    local out = bridge_one(commands[i])
    assert(pvm.classof(out) ~= nil)
    assert(fact_count(commands[i]) >= 0)
end

local program = B.BackProgram(commands)
local lowered = bridge.lower_program(program)
assert(pvm.classof(lowered) == pvm.classof(Old.BackProgram({})))
assert(#lowered.cmds == #commands)

print("moonlift back_bridge_coverage ok")
