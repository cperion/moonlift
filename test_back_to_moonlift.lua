package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A1 = require("moonlift_legacy.asdl")
local A2 = require("moonlift.asdl")
local Bridge = require("moonlift.back_to_moonlift")

local T = pvm.context()
A1.Define(T)
A2.Define(T)
local L = Bridge.Define(T)

local C2 = T.Moon2Core
local B2 = T.Moon2Back
local B1 = T.MoonliftBack

local sig = B2.BackSigId("sig:add")
local func = B2.BackFuncId("add")
local entry = B2.BackBlockId("entry")
local a = B2.BackValId("a")
local b = B2.BackValId("b")
local r = B2.BackValId("r")

local src = B2.BackProgram({
    B2.CmdCreateSig(sig, { B2.BackI32, B2.BackI32 }, { B2.BackI32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, func, sig),
    B2.CmdBeginFunc(func),
    B2.CmdCreateBlock(entry),
    B2.CmdSwitchToBlock(entry),
    B2.CmdBindEntryParams(entry, { a, b }),
    B2.CmdBinary(r, B2.BackIadd, B2.BackShapeScalar(B2.BackI32), a, b),
    B2.CmdReturnValue(r),
    B2.CmdSealBlock(entry),
    B2.CmdFinishFunc(func),
    B2.CmdFinalizeModule,
})

local out = L.lower_program(src)
local expected = B1.BackProgram({
    B1.BackCmdCreateSig(B1.BackSigId("sig:add"), { B1.BackI32, B1.BackI32 }, { B1.BackI32 }),
    B1.BackCmdDeclareFuncExport(B1.BackFuncId("add"), B1.BackSigId("sig:add")),
    B1.BackCmdBeginFunc(B1.BackFuncId("add")),
    B1.BackCmdCreateBlock(B1.BackBlockId("entry")),
    B1.BackCmdSwitchToBlock(B1.BackBlockId("entry")),
    B1.BackCmdBindEntryParams(B1.BackBlockId("entry"), { B1.BackValId("a"), B1.BackValId("b") }),
    B1.BackCmdIadd(B1.BackValId("r"), B1.BackI32, B1.BackValId("a"), B1.BackValId("b")),
    B1.BackCmdReturnValue(B1.BackValId("r")),
    B1.BackCmdSealBlock(B1.BackBlockId("entry")),
    B1.BackCmdFinishFunc(B1.BackFuncId("add")),
    B1.BackCmdFinalizeModule,
})

assert(out == expected)

print("moonlift back_to_moonlift ok")
