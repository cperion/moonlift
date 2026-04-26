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

local function sid(text) return B2.BackSigId(text) end
local function fid(text) return B2.BackFuncId(text) end
local function bid(text) return B2.BackBlockId(text) end
local function vid(text) return B2.BackValId(text) end
local i32 = B2.BackI32
local ptr = B2.BackPtr
local vec_i32x4 = B2.BackVec(i32, 4)
local shape_vec_i32x4 = B2.BackShapeVec(vec_i32x4)

local sig = sid("sig:first_plus_one_vec")
local func = fid("first_plus_one_vec")
local entry = bid("entry.first_plus_one_vec")
local p = vid("p")
local loaded = vid("loaded")
local one = vid("one")
local ones = vid("ones")
local added = vid("added")
local first = vid("first")

local program = B2.BackProgram({
    B2.CmdCreateSig(sig, { ptr }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, func, sig),
    B2.CmdBeginFunc(func),
    B2.CmdCreateBlock(entry),
    B2.CmdSwitchToBlock(entry),
    B2.CmdBindEntryParams(entry, { p }),
    B2.CmdLoad(loaded, shape_vec_i32x4, p),
    B2.CmdConst(one, i32, B2.BackLitInt("1")),
    B2.CmdVecSplat(ones, vec_i32x4, one),
    B2.CmdBinary(added, B2.BackVecIadd, shape_vec_i32x4, loaded, ones),
    B2.CmdVecExtractLane(first, i32, added, 0),
    B2.CmdReturnValue(first),
    B2.CmdSealBlock(entry),
    B2.CmdFinishFunc(func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)

local current_program = bridge.lower_program(program)
local jit = jit_api.jit()
local artifact = jit:compile(current_program)

local first_plus_one_vec = ffi.cast("int32_t (*)(const int32_t*)", artifact:getpointer(B1.BackFuncId("first_plus_one_vec")))
local xs = ffi.new("int32_t[4]", { 41, 1, 2, 3 })
assert(first_plus_one_vec(xs) == 42)

artifact:free()

print("moonlift back_vector_smoke ok")
