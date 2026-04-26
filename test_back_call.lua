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
local shape_i32 = B2.BackShapeScalar(i32)

local inc_sig = sid("sig:inc_i32")
local inc_func = fid("inc_i32")
local inc_entry = bid("entry.inc_i32")
local inc_x = vid("inc.x")
local inc_one = vid("inc.one")
local inc_out = vid("inc.out")

local call_sig = sid("sig:call_inc_i32")
local call_func = fid("call_inc_i32")
local call_entry = bid("entry.call_inc_i32")
local call_x = vid("call.x")
local call_out = vid("call.out")

local program = B2.BackProgram({
    B2.CmdCreateSig(inc_sig, { i32 }, { i32 }),
    B2.CmdCreateSig(call_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityLocal, inc_func, inc_sig),
    B2.CmdDeclareFunc(C2.VisibilityExport, call_func, call_sig),

    B2.CmdBeginFunc(inc_func),
    B2.CmdCreateBlock(inc_entry),
    B2.CmdSwitchToBlock(inc_entry),
    B2.CmdBindEntryParams(inc_entry, { inc_x }),
    B2.CmdConst(inc_one, i32, B2.BackLitInt("1")),
    B2.CmdBinary(inc_out, B2.BackIadd, shape_i32, inc_x, inc_one),
    B2.CmdReturnValue(inc_out),
    B2.CmdSealBlock(inc_entry),
    B2.CmdFinishFunc(inc_func),

    B2.CmdBeginFunc(call_func),
    B2.CmdCreateBlock(call_entry),
    B2.CmdSwitchToBlock(call_entry),
    B2.CmdBindEntryParams(call_entry, { call_x }),
    B2.CmdCall(B2.BackCallValue(call_out, i32), B2.BackCallDirect(inc_func), inc_sig, { call_x }),
    B2.CmdReturnValue(call_out),
    B2.CmdSealBlock(call_entry),
    B2.CmdFinishFunc(call_func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)

local current_program = bridge.lower_program(program)
local jit = jit_api.jit()
local artifact = jit:compile(current_program)

local ptr = artifact:getpointer(B1.BackFuncId("call_inc_i32"))
local call_inc_i32 = ffi.cast("int32_t (*)(int32_t)", ptr)
assert(call_inc_i32(41) == 42)
assert(call_inc_i32(-8) == -7)
artifact:free()

print("moonlift back_call ok")
