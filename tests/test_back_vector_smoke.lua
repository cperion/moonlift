package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local J = require("moonlift.back_jit")
local Validate = require("moonlift.back_validate")

local T = pvm.context()
A2.Define(T)
local validate = Validate.Define(T)
local jit_api = J.Define(T)

local C2 = T.MoonCore
local B2 = T.MoonBack
local B2 = T.MoonBack

local function sid(text) return B2.BackSigId(text) end
local function fid(text) return B2.BackFuncId(text) end
local function bid(text) return B2.BackBlockId(text) end
local function vid(text) return B2.BackValId(text) end
local i32 = B2.BackI32
local ptr = B2.BackPtr
local vec_i32x4 = B2.BackVec(i32, 4)
local shape_vec_i32x4 = B2.BackShapeVec(vec_i32x4)
local function mem(id, mode) return B2.BackMemoryInfo(B2.BackAccessId(id), B2.BackAlignUnknown, B2.BackDerefUnknown, B2.BackMayTrap, B2.BackMayNotMove, mode) end
local function addr(base, off) return B2.BackAddress(B2.BackAddrValue(base), off, B2.BackProvUnknown, B2.BackPtrBoundsUnknown) end

local sig = sid("sig:first_plus_one_vec")
local func = fid("first_plus_one_vec")
local entry = bid("entry.first_plus_one_vec")
local p = vid("p")
local loaded = vid("loaded")
local zero = vid("zero")
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
    B2.CmdConst(zero, B2.BackIndex, B2.BackLitInt("0")),
    B2.CmdLoadInfo(loaded, shape_vec_i32x4, addr(p, zero), mem("first_plus_one_vec:load", B2.BackAccessRead)),
    B2.CmdConst(one, i32, B2.BackLitInt("1")),
    B2.CmdVecSplat(ones, vec_i32x4, one),
    B2.CmdVecBinary(added, B2.BackVecIntAdd, vec_i32x4, loaded, ones),
    B2.CmdVecExtractLane(first, i32, added, 0),
    B2.CmdReturnValue(first),
    B2.CmdSealBlock(entry),
    B2.CmdFinishFunc(func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)

local first_plus_one_vec = ffi.cast("int32_t (*)(const int32_t*)", artifact:getpointer(B2.BackFuncId("first_plus_one_vec")))
local xs = ffi.new("int32_t[4]", { 41, 1, 2, 3 })
assert(first_plus_one_vec(xs) == 42)

artifact:free()

print("moonlift back_vector_smoke ok")
