package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Tape = require("moonlift.back_command_tape")

local T = pvm.context()
A.Define(T)
local B = T.MoonBack
local C = T.MoonCore
local E = Tape.Define(T)

local sig = B.BackSigId("sig")
local func = B.BackFuncId("f")
local entry = B.BackBlockId("entry")
local v = B.BackValId("v")
local program = B.BackProgram({
    B.CmdCreateSig(sig, {}, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdConst(v, B.BackI32, B.BackLitInt("7")),
    B.CmdReturnValue(v),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})

local tape = E.encode(program)
assert(pvm.classof(tape) == B.BackCommandTape)
assert(tape.version == 2)
assert(tape.command_count == #program.cmds)
assert(tape.payload:match("moonlift%-back%-command%-tape%-v2"))
assert(tape.payload:match("CmdCreateSig"))
assert(tape.payload:match("CmdFinalizeModule"))

print("moonlift back_command_tape ok")
