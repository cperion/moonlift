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
local u32 = B2.BackU32
local f32 = B2.BackF32
local f64 = B2.BackF64
local idx = B2.BackIndex
local shape_i32 = B2.BackShapeScalar(i32)
local shape_u32 = B2.BackShapeScalar(u32)

local cast_sig = sid("sig:i32_to_f64")
local cast_func = fid("i32_to_f64")
local cast_entry = bid("entry.i32_to_f64")
local cast_x = vid("cast.x")
local cast_out = vid("cast.out")

local poprot_sig = sid("sig:poprot")
local poprot_func = fid("poprot")
local poprot_entry = bid("entry.poprot")
local pop_x = vid("pop.x")
local pop_pc = vid("pop.pc")
local pop_one = vid("pop.one")
local pop_out = vid("pop.out")

local fma_sig = sid("sig:fma1")
local fma_func = fid("fma1")
local fma_entry = bid("entry.fma1")
local fa = vid("fma.a")
local fb = vid("fma.b")
local fc = vid("fma.c")
local fma_out = vid("fma.out")

local switch_sig = sid("sig:switch_i32")
local switch_func = fid("switch_i32")
local switch_entry = bid("entry.switch_i32")
local case0 = bid("case.switch_i32.0")
local case5 = bid("case.switch_i32.5")
local default = bid("default.switch_i32")
local sx = vid("switch.x")
local r0 = vid("switch.r0")
local r5 = vid("switch.r5")
local rd = vid("switch.rd")

local program = B2.BackProgram({
    B2.CmdCreateSig(cast_sig, { i32 }, { f64 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, cast_func, cast_sig),
    B2.CmdBeginFunc(cast_func),
    B2.CmdCreateBlock(cast_entry),
    B2.CmdSwitchToBlock(cast_entry),
    B2.CmdBindEntryParams(cast_entry, { cast_x }),
    B2.CmdCast(cast_out, B2.BackSToF, f64, cast_x),
    B2.CmdReturnValue(cast_out),
    B2.CmdSealBlock(cast_entry),
    B2.CmdFinishFunc(cast_func),

    B2.CmdCreateSig(poprot_sig, { u32 }, { u32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, poprot_func, poprot_sig),
    B2.CmdBeginFunc(poprot_func),
    B2.CmdCreateBlock(poprot_entry),
    B2.CmdSwitchToBlock(poprot_entry),
    B2.CmdBindEntryParams(poprot_entry, { pop_x }),
    B2.CmdIntrinsic(pop_pc, B2.BackIntrinsicPopcount, shape_u32, { pop_x }),
    B2.CmdConst(pop_one, u32, B2.BackLitInt("1")),
    B2.CmdBinary(pop_out, B2.BackRotl, shape_u32, pop_pc, pop_one),
    B2.CmdReturnValue(pop_out),
    B2.CmdSealBlock(poprot_entry),
    B2.CmdFinishFunc(poprot_func),

    B2.CmdCreateSig(fma_sig, { f32, f32, f32 }, { f32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, fma_func, fma_sig),
    B2.CmdBeginFunc(fma_func),
    B2.CmdCreateBlock(fma_entry),
    B2.CmdSwitchToBlock(fma_entry),
    B2.CmdBindEntryParams(fma_entry, { fa, fb, fc }),
    B2.CmdFma(fma_out, f32, fa, fb, fc),
    B2.CmdReturnValue(fma_out),
    B2.CmdSealBlock(fma_entry),
    B2.CmdFinishFunc(fma_func),

    B2.CmdCreateSig(switch_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, switch_func, switch_sig),
    B2.CmdBeginFunc(switch_func),
    B2.CmdCreateBlock(switch_entry),
    B2.CmdCreateBlock(case0),
    B2.CmdCreateBlock(case5),
    B2.CmdCreateBlock(default),
    B2.CmdSwitchToBlock(switch_entry),
    B2.CmdBindEntryParams(switch_entry, { sx }),
    B2.CmdSwitchInt(sx, i32, {
        B2.BackSwitchCase("0", case0),
        B2.BackSwitchCase("5", case5),
    }, default),
    B2.CmdSwitchToBlock(case0),
    B2.CmdConst(r0, i32, B2.BackLitInt("10")),
    B2.CmdReturnValue(r0),
    B2.CmdSealBlock(case0),
    B2.CmdSwitchToBlock(case5),
    B2.CmdConst(r5, i32, B2.BackLitInt("50")),
    B2.CmdReturnValue(r5),
    B2.CmdSealBlock(case5),
    B2.CmdSwitchToBlock(default),
    B2.CmdConst(rd, i32, B2.BackLitInt("99")),
    B2.CmdReturnValue(rd),
    B2.CmdSealBlock(default),
    B2.CmdSealBlock(switch_entry),
    B2.CmdFinishFunc(switch_func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)

local current_program = bridge.lower_program(program)
local jit = jit_api.jit()
local artifact = jit:compile(current_program)

local i32_to_f64 = ffi.cast("double (*)(int32_t)", artifact:getpointer(B1.BackFuncId("i32_to_f64")))
assert(tonumber(i32_to_f64(-7)) == -7)

local poprot = ffi.cast("uint32_t (*)(uint32_t)", artifact:getpointer(B1.BackFuncId("poprot")))
assert(poprot(0xF0) == 8)

local fma1 = ffi.cast("float (*)(float, float, float)", artifact:getpointer(B1.BackFuncId("fma1")))
assert(tonumber(fma1(2, 3, 4)) == 10)

local switch_i32 = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B1.BackFuncId("switch_i32")))
assert(switch_i32(0) == 10)
assert(switch_i32(5) == 50)
assert(switch_i32(9) == 99)

artifact:free()

print("moonlift back_cast_intrinsic_switch ok")
