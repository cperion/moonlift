package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context(); Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local C = T.LalinC
local CodeToC = require("lalin.code_to_c")(T)

local origin = Code.CodeOriginGenerated("test_code_to_c_lowering")
local f64 = Code.CodeTyFloat(64)
local sig = Code.CodeSigId("sig:fadd")
local fn = Code.CodeFuncId("fn:fadd")
local entry = Code.CodeBlockId("block:entry")
local a = Code.CodeParam(Code.CodeValueId("v:a"), "a", f64, origin)
local b = Code.CodeParam(Code.CodeValueId("v:b"), "b", f64, origin)
local sum = Code.CodeValueId("v:sum")
local inst = Code.CodeInst(
    Code.CodeInstId("inst:sum"),
    Code.CodeInstFloatBinary(sum, Core.BinAdd, f64, Code.CodeFloatStrict, a.value, b.value),
    origin
)
local term = Code.CodeTerm(Code.CodeTermId("term:return"), Code.CodeTermReturn({ sum }), origin)
local block = Code.CodeBlock(entry, "entry", {}, { inst }, term, origin)
local module = Code.CodeModule(
    Code.CodeModuleId("module:code_to_c_float"),
    { Code.CodeSig(sig, { f64, f64 }, { f64 }) },
    {}, {}, {}, {},
    { Code.CodeFunc(fn, "fadd", Code.CodeLinkageExport, sig, { a, b }, {}, entry, { block }, origin) },
    origin
)

local unit = CodeToC.module(module)
assert(#unit.helpers == 1, "float binary lowering should register one helper")
local helper_spec = unit.helpers[1].spec
assert(asdl.classof(helper_spec) == C.CBackendHelperFloatBinary, "float binary must lower to CBackendHelperFloatBinary")

io.write("lalin code_to_c_lowering ok\n")
