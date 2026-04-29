package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local J = require("moonlift.back_jit")
local Validate = require("moonlift.back_validate")
local VecToBack = require("moonlift.vec_to_back")

local T = pvm.context()
A2.Define(T)
local jit_api = J.Define(T)
local validate = Validate.Define(T)
local lower = VecToBack.Define(T)

local C = T.Moon2Core
local Ty = T.Moon2Type
local Tr = T.Moon2Tree
local V = T.Moon2Vec
local Back = T.Moon2Back
local B2 = T.Moon2Back

local p = V.VecValueId("p")
local loaded = V.VecValueId("loaded")
local one = V.VecValueId("one")
local ones = V.VecValueId("ones")
local added = V.VecValueId("added")
local first = V.VecValueId("first")
local entry = V.VecBlockId("entry.vec_first_plus_one")
local i32x4 = V.VecVectorShape(V.VecElemI32, 4)
local i32 = V.VecScalarShape(V.VecElemI32)
local dummy_expr = Tr.ExprLit(Tr.ExprTyped(Ty.TScalar(C.ScalarI32)), C.LitInt("0"))
local dummy_access = V.VecMemoryAccess(V.VecAccessId("load"), V.VecAccessLoad, V.VecMemoryBaseRawAddr(dummy_expr), V.VecExprId("idx"), Ty.TScalar(C.ScalarI32), V.VecAccessContiguous, V.VecAlignmentKnown(16), V.VecBoundsProven(V.VecProofKernelSafety("test in bounds")))

local block = V.VecBlock(entry, {}, {
    V.VecCmdLoad(loaded, i32x4, dummy_access, p),
    V.VecCmdConstInt(one, V.VecElemI32, "1"),
    V.VecCmdSplat(ones, i32x4, one),
    V.VecCmdBin(added, i32x4, V.VecAdd, loaded, ones),
    V.VecCmdExtractLane(first, added, 0),
}, V.VecReturnValue(first))

local spec = V.VecBackProgramSpec({
    V.VecBackFuncSpec("vec_first_plus_one", C.VisibilityExport, { V.VecScalarParam(p, V.VecElemPtr) }, { i32 }, { block }),
})

local program = lower.program(spec)
assert(pvm.classof(program) == Back.BackProgram)
local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)
local fn = ffi.cast("int32_t (*)(const int32_t*)", artifact:getpointer(B2.BackFuncId("vec_first_plus_one")))
local xs = ffi.new("int32_t[4]", { 41, 1, 2, 3 })
assert(fn(xs) == 42)
artifact:free()

local bad = V.VecBackProgramSpec({
    V.VecBackFuncSpec("bad_vec_rem", C.VisibilityExport, {}, { i32 }, {
        V.VecBlock(V.VecBlockId("entry.bad"), {}, {
            V.VecCmdBin(V.VecValueId("bad"), i32x4, V.VecRem, loaded, ones),
        }, V.VecReturnValue(V.VecValueId("bad"))),
    }),
})
local rejected = lower.program(bad)
assert(pvm.classof(rejected) == V.VecBackReject)

print("moonlift vec_to_back ok")
