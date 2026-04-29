package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Validate = require("moonlift.back_validate")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
Schema.Define(T)

local C = T.MoonCore
local B = T.MoonBack
local validate = Validate.Define(T)
local jit_api = Jit.Define(T)

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
assert(#report.issues == 0)
local artifact = jit_api.jit():compile(program)
local add_i32 = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(func))
assert(add_i32(20, 22) == 42)
assert(add_i32(-10, 3) == -7)
artifact:free()

io.write("moonlift schema_back_jit ok\n")
