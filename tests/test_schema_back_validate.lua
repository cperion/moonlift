package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Validate = require("moonlift.back_validate")

local T = pvm.context()
Schema.Define(T)

local C = T.MoonCore
local B = T.MoonBack
local validate = Validate.Define(T)

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

local report = validate.validate(program)
assert(#report.issues == 0, "expected clean MoonBack program to validate")

local bad = B.BackProgram({
    B.CmdReturnValue(r),
    B.CmdFinalizeModule,
})
local bad_report = validate.validate(bad)
assert(#bad_report.issues >= 1, "expected invalid MoonBack program to report issues")

io.write("moonlift schema_back_validate ok\n")
