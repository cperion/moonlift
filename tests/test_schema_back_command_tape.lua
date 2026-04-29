package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Tape = require("moonlift.back_command_tape")

local T = pvm.context()
Schema.Define(T)

local C = T.MoonCore
local B = T.MoonBack
local tape_api = Tape.Define(T)

local sig = B.BackSigId("sig:add_i32")
local func = B.BackFuncId("add_i32")
local entry = B.BackBlockId("entry.add_i32")
local a = B.BackValId("a")
local b = B.BackValId("b")
local r = B.BackValId("r")

local program = B.BackProgram({
    B.CmdCreateSig(sig, { B.BackI32, B.BackI32 }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { a, b }),
    B.CmdIntBinary(r, B.BackIntAdd, B.BackI32, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), a, b),
    B.CmdReturnValue(r),
    B.CmdSealBlock(entry),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})

local tape = tape_api.encode(program)
assert(pvm.classof(tape) == B.BackCommandTape)
assert(tape.version == 2)
assert(tape.command_count == #program.cmds)
assert(tape.payload:match("moonlift%-back%-command%-tape%-v2"))
assert(tape.payload:match("CmdDeclareFunc\tE\tadd_i32\tsig:add_i32"))
assert(tape.payload:match("CmdIntBinary\tr\tBackIntAdd\t4\t0\t[01]\ta\tb"))

io.write("moonlift schema_back_command_tape ok\n")
