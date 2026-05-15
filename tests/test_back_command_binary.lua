package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Binary = require("moonlift.back_command_binary")
local J = require("moonlift.back_jit")

local T = pvm.context()
A.Define(T)
local B = T.MoonBack
local C = T.MoonCore
local E = Binary.Define(T)
local jit_api = J.Define(T)

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

local payload = E.encode(program)
assert(type(payload) == "string")
assert(#payload > 16)
assert(payload:byte(1) == 0x54) -- "MLBT" as little-endian u32 bytes: T B L M
assert(payload:byte(2) == 0x42)
assert(payload:byte(3) == 0x4c)
assert(payload:byte(4) == 0x4d)

local jit = jit_api.jit()
local artifact = jit:compile(program)
local f = ffi.cast("int32_t (*)()", artifact:getpointer(func))
assert(f() == 7)
artifact:free()
jit:free()

print("moonlift back_command_binary ok")
