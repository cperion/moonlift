package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A1 = require("moonlift_legacy.asdl")
local A2 = require("moonlift.asdl")
local J = require("moonlift_legacy.jit")
local Bridge = require("moonlift.back_to_moonlift")
local Validate = require("moonlift.back_validate")

local T = pvm.context()
A1.Define(T)
A2.Define(T)
local bridge = Bridge.Define(T)
local validate = Validate.Define(T)
local jit_api = J.Define(T)

local C2 = T.Moon2Core
local B2 = T.Moon2Back
local B1 = T.MoonliftBack

local sig = B2.BackSigId("sig:add_i32")
local func = B2.BackFuncId("add_i32")
local entry = B2.BackBlockId("entry.add_i32")
local a = B2.BackValId("a")
local b = B2.BackValId("b")
local r = B2.BackValId("r")

local moon2_program = B2.BackProgram({
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

local report = validate.validate(moon2_program)
assert(#report.issues == 0)

local current_program = bridge.lower_program(moon2_program)
local jit = jit_api.jit()
local artifact = jit:compile(current_program)
local ptr = artifact:getpointer(B1.BackFuncId("add_i32"))
local add_i32 = ffi.cast("int32_t (*)(int32_t, int32_t)", ptr)
assert(add_i32(20, 22) == 42)
assert(add_i32(-10, 3) == -7)
artifact:free()

print("moonlift back_add_i32 ok")
