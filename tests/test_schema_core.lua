package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Emit = require("moonlift.asdl_emit")

local T = pvm.context()
local schema = Schema.schema(T)
assert(pvm.classof(schema) == T.MoonAsdl.Schema)
assert(#schema.modules == 1)
assert(schema.modules[1].name == "MoonCore")

local text = Emit.emit(schema, T.MoonAsdl)
assert(text:match("module MoonCore"))
assert(text:match("Scalar = ScalarVoid"))
assert(text:match("TypeSym = %(string key, string name%) unique"))

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

io.write("moonlift schema_core ok\n")
