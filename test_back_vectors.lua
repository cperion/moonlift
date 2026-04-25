package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local J = require("moonlift.jit")

local T = pvm.context()
A.Define(T)
local Back = T.MoonliftBack
local jit = J.Define(T).jit()

local V2I64 = Back.BackVec(Back.BackI64, 2)
local program = Back.BackProgram({
    Back.BackCmdCreateSig(Back.BackSigId("sig:vec_smoke"), {}, { Back.BackI64 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("vec_smoke"), Back.BackSigId("sig:vec_smoke")),
    Back.BackCmdBeginFunc(Back.BackFuncId("vec_smoke")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("entry"), {}),
    Back.BackCmdConstInt(Back.BackValId("c2"), Back.BackI64, "2"),
    Back.BackCmdConstInt(Back.BackValId("c3"), Back.BackI64, "3"),
    Back.BackCmdConstInt(Back.BackValId("c5"), Back.BackI64, "5"),
    Back.BackCmdConstInt(Back.BackValId("c15"), Back.BackI64, "15"),
    Back.BackCmdVecSplat(Back.BackValId("v2"), V2I64, Back.BackValId("c2")),
    Back.BackCmdVecSplat(Back.BackValId("v3"), V2I64, Back.BackValId("c3")),
    Back.BackCmdVecSplat(Back.BackValId("v5"), V2I64, Back.BackValId("c5")),
    Back.BackCmdVecSplat(Back.BackValId("v15"), V2I64, Back.BackValId("c15")),
    Back.BackCmdVecInsertLane(Back.BackValId("v23"), V2I64, Back.BackValId("v2"), Back.BackValId("c3"), 1),
    Back.BackCmdVecImul(Back.BackValId("vmul"), V2I64, Back.BackValId("v23"), Back.BackValId("v3")),
    Back.BackCmdVecIadd(Back.BackValId("vadd"), V2I64, Back.BackValId("vmul"), Back.BackValId("v5")),
    Back.BackCmdVecBand(Back.BackValId("vand"), V2I64, Back.BackValId("vadd"), Back.BackValId("v15")),
    Back.BackCmdVecExtractLane(Back.BackValId("lane0"), Back.BackI64, Back.BackValId("vand"), 0),
    Back.BackCmdVecExtractLane(Back.BackValId("lane1"), Back.BackI64, Back.BackValId("vand"), 1),
    Back.BackCmdIadd(Back.BackValId("sum"), Back.BackI64, Back.BackValId("lane0"), Back.BackValId("lane1")),
    Back.BackCmdReturnValue(Back.BackValId("sum")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry")),
    Back.BackCmdFinishFunc(Back.BackFuncId("vec_smoke")),
    Back.BackCmdFinalizeModule,
})

local artifact = jit:compile(program)
local ptr = artifact:getpointer(Back.BackFuncId("vec_smoke"))
local f = ffi.cast("int64_t (*)()", ptr)
assert(f() == 25)
local disasm = artifact:disasm("vec_smoke", { bytes = 160 })
assert(disasm:find("xmm", 1, true) or disasm:find("ymm", 1, true) or disasm:find("zmm", 1, true), disasm)
artifact:free()

print("moonlift back vectors ok")
