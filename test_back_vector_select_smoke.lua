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

local sig = sid("sig:first_max_vec")
local func = fid("first_max_vec")
local entry = bid("entry.first_max_vec")
local a = vid("a")
local b = vid("b")
local av = vid("av")
local bv = vid("bv")
local mask = vid("mask")
local maxv = vid("maxv")
local first = vid("first")

local program = B2.BackProgram({
    B2.CmdCreateSig(sig, { ptr, ptr }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, func, sig),
    B2.CmdBeginFunc(func),
    B2.CmdCreateBlock(entry),
    B2.CmdSwitchToBlock(entry),
    B2.CmdBindEntryParams(entry, { a, b }),
    B2.CmdLoad(av, shape_vec_i32x4, a),
    B2.CmdLoad(bv, shape_vec_i32x4, b),
    B2.CmdVecCompare(mask, B2.BackVecSIcmpGt, vec_i32x4, av, bv),
    B2.CmdVecSelect(maxv, vec_i32x4, mask, av, bv),
    B2.CmdVecExtractLane(first, i32, maxv, 0),
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

local first_max_vec = ffi.cast("int32_t (*)(const int32_t*, const int32_t*)", artifact:getpointer(B1.BackFuncId("first_max_vec")))
local xs = ffi.new("int32_t[4]", { 42, -1, 2, 3 })
local ys = ffi.new("int32_t[4]", { 7, 10, 2, 4 })
assert(first_max_vec(xs, ys) == 42)
xs[0] = -5
assert(first_max_vec(xs, ys) == 7)

artifact:free()

print("moonlift back_vector_select_smoke ok")
