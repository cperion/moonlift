package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Validate = require("lalin.back_validate")

local T = pvm.context()
Schema(T)

local C = T.LalinCore
local B = T.LalinBack
local validate = Validate(T)

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
assert(#report.issues == 0, "expected clean LalinBack program to validate")

local bad = B.BackProgram({
    B.CmdReturnValue(r),
    B.CmdFinalizeModule,
})
local bad_report = validate.validate(bad)
assert(#bad_report.issues >= 1, "expected invalid LalinBack program to report issues")

io.write("lalin schema_back_validate ok\n")
