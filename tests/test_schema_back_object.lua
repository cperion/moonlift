package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Validate = require("moonlift.back_validate")
local Object = require("moonlift.back_object")

local T = pvm.context()
Schema.Define(T)

local C = T.MoonCore
local B = T.MoonBack
local validate = Validate.Define(T)
local object = Object.Define(T)

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
local artifact = object.compile(program, { module_name = "schema_back_object" })
local bytes = artifact:bytes()
assert(type(bytes) == "string")
assert(#bytes > 0)
assert(bytes:find("add_i32", 1, true), "object should contain exported symbol text")

io.write("moonlift schema_back_object ok\n")
