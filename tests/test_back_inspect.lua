package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Inspect = require("moonlift.back_inspect")

local T = pvm.context()
A2.Define(T)
local B = T.MoonBack
local I = Inspect.Define(T)

local sig = B.BackSigId("sig")
local func = B.BackFuncId("f")
local entry = B.BackBlockId("entry")
local a, b, c, p, q, off = B.BackValId("a"), B.BackValId("b"), B.BackValId("c"), B.BackValId("p"), B.BackValId("q"), B.BackValId("off")
local addr = B.BackAddress(B.BackAddrValue(p), off, B.BackProvArg("p"), B.BackPtrInBounds("test"))
local mem = B.BackMemoryInfo(B.BackAccessId("load"), B.BackAlignKnown(4), B.BackDerefBytes(4, "test"), B.BackNonTrapping("test"), B.BackMayNotMove, B.BackAccessRead)
local sem = B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose)

local program = B.BackProgram({
    B.CmdTargetModel(B.BackTargetModel(B.BackTargetCraneliftJit, { B.BackTargetSupportsShape(B.BackShapeScalar(B.BackI32)) })),
    B.CmdCreateSig(sig, { B.BackPtr }, { B.BackI32 }),
    B.CmdDeclareFunc(T.MoonCore.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { p }),
    B.CmdConst(off, B.BackIndex, B.BackLitInt("0")),
    B.CmdPtrOffset(q, B.BackAddrValue(p), off, 4, 0, B.BackProvArg("p"), B.BackPtrInBounds("test")),
    B.CmdLoadInfo(a, B.BackShapeScalar(B.BackI32), addr, mem),
    B.CmdConst(b, B.BackI32, B.BackLitInt("1")),
    B.CmdIntBinary(c, B.BackIntAdd, B.BackI32, sem, a, b),
    B.CmdReturnValue(c),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})

local report = I.inspect(program)
assert(pvm.classof(report) == B.BackInspectionReport)
assert(#report.targets == 1)
assert(#report.memory == 1)
assert(report.memory[1].index == 10 and report.memory[1].access == B.BackAccessId("load"))
assert(#report.addresses == 1 and report.addresses[1].address == addr)
assert(#report.pointer_offsets == 1 and report.pointer_offsets[1].dst == q and report.pointer_offsets[1].elem_size == 4)
assert(#report.int_semantics == 1)
assert(report.int_semantics[1].op == B.BackIntAdd and report.int_semantics[1].semantics == sem)

local saw_load, saw_const = false, false
for i = 1, #report.command_counts do
    local count = report.command_counts[i]
    if count.command_kind == "CmdLoadInfo" and count.count == 1 then saw_load = true end
    if count.command_kind == "CmdConst" and count.count == 2 then saw_const = true end
end
assert(saw_load, "expected CmdLoadInfo count")
assert(saw_const, "expected CmdConst count")

print("moonlift back_inspect ok")
