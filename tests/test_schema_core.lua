package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Emit = require("moonlift.asdl_emit")

local T = pvm.context()
local schema = Schema.schema(T)
assert(pvm.classof(schema) == T.MoonAsdl.Schema)
assert(#schema.modules >= 16)
assert(schema.modules[1].name == "MoonCore")
assert(schema.modules[2].name == "MoonBack")

local text = Emit.emit(schema, T.MoonAsdl)
assert(text:match("module MoonCore"))
assert(text:match("module MoonBack"))
assert(text:match("module MoonType"))
assert(text:match("Scalar = ScalarVoid"))
assert(text:match("TypeSym = %(string key, string name%) unique"))
assert(not text:match("Moon2"))

Schema.Define(T)

local C = T.MoonCore
assert(C.Id("x") == C.Id("x"))
assert(C.Path({ C.Name("a"), C.Name("b") }) == C.Path({ C.Name("a"), C.Name("b") }))
assert(C.ScalarI32.kind == "ScalarI32")
assert(C.ScalarInfo(C.ScalarFamilySignedInt, C.ScalarBits(32)).bits.bits == 32)
assert(C.LitInt("7") == C.LitInt("7"))
assert(C.LitBool(true).value == true)
assert(C.VisibilityExport.kind == "VisibilityExport")
assert(C.MachineCastSToF.kind == "MachineCastSToF")
assert(C.ExternSym("extern:puts", "puts", "puts").symbol == "puts")

local B = T.MoonBack
local sig = B.BackSigId("sig:add_i32")
local func = B.BackFuncId("add_i32")
local entry = B.BackBlockId("entry")
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
assert(#program.cmds == 11)

local Ty = T.MoonType
local i32 = Ty.TScalar(C.ScalarI32)
assert(i32.scalar == C.ScalarI32)

io.write("moonlift schema_core ok\n")
