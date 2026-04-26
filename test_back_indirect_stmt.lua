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
local shape_i32 = B2.BackShapeScalar(i32)

local inc_sig = sid("sig:inc_i32")
local inc_func = fid("inc_i32")
local inc_entry = bid("entry.inc_i32")
local ix = vid("inc.x")
local one = vid("inc.one")
local inc_out = vid("inc.out")

local indirect_sig = sid("sig:call_indirect_inc")
local indirect_func = fid("call_indirect_inc")
local indirect_entry = bid("entry.call_indirect_inc")
local cx = vid("call.x")
local fptr = vid("call.fptr")
local indirect_out = vid("call.out")

local store_sig = sid("sig:store_42")
local store_func = fid("store_42")
local store_entry = bid("entry.store_42")
local sp = vid("store.p")
local forty_two = vid("store.42")

local call_store_sig = sid("sig:call_store_42")
local call_store_func = fid("call_store_42")
local call_store_entry = bid("entry.call_store_42")
local cp = vid("callstore.p")
local loaded = vid("callstore.loaded")

local program = B2.BackProgram({
    B2.CmdCreateSig(inc_sig, { i32 }, { i32 }),
    B2.CmdCreateSig(indirect_sig, { i32 }, { i32 }),
    B2.CmdCreateSig(store_sig, { ptr }, {}),
    B2.CmdCreateSig(call_store_sig, { ptr }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityLocal, inc_func, inc_sig),
    B2.CmdDeclareFunc(C2.VisibilityExport, indirect_func, indirect_sig),
    B2.CmdDeclareFunc(C2.VisibilityLocal, store_func, store_sig),
    B2.CmdDeclareFunc(C2.VisibilityExport, call_store_func, call_store_sig),

    B2.CmdBeginFunc(inc_func),
    B2.CmdCreateBlock(inc_entry),
    B2.CmdSwitchToBlock(inc_entry),
    B2.CmdBindEntryParams(inc_entry, { ix }),
    B2.CmdConst(one, i32, B2.BackLitInt("1")),
    B2.CmdBinary(inc_out, B2.BackIadd, shape_i32, ix, one),
    B2.CmdReturnValue(inc_out),
    B2.CmdSealBlock(inc_entry),
    B2.CmdFinishFunc(inc_func),

    B2.CmdBeginFunc(indirect_func),
    B2.CmdCreateBlock(indirect_entry),
    B2.CmdSwitchToBlock(indirect_entry),
    B2.CmdBindEntryParams(indirect_entry, { cx }),
    B2.CmdFuncAddr(fptr, inc_func),
    B2.CmdCall(B2.BackCallValue(indirect_out, i32), B2.BackCallIndirect(fptr), inc_sig, { cx }),
    B2.CmdReturnValue(indirect_out),
    B2.CmdSealBlock(indirect_entry),
    B2.CmdFinishFunc(indirect_func),

    B2.CmdBeginFunc(store_func),
    B2.CmdCreateBlock(store_entry),
    B2.CmdSwitchToBlock(store_entry),
    B2.CmdBindEntryParams(store_entry, { sp }),
    B2.CmdConst(forty_two, i32, B2.BackLitInt("42")),
    B2.CmdStore(shape_i32, sp, forty_two),
    B2.CmdReturnVoid,
    B2.CmdSealBlock(store_entry),
    B2.CmdFinishFunc(store_func),

    B2.CmdBeginFunc(call_store_func),
    B2.CmdCreateBlock(call_store_entry),
    B2.CmdSwitchToBlock(call_store_entry),
    B2.CmdBindEntryParams(call_store_entry, { cp }),
    B2.CmdCall(B2.BackCallStmt, B2.BackCallDirect(store_func), store_sig, { cp }),
    B2.CmdLoad(loaded, shape_i32, cp),
    B2.CmdReturnValue(loaded),
    B2.CmdSealBlock(call_store_entry),
    B2.CmdFinishFunc(call_store_func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)
local current_program = bridge.lower_program(program)
local jit = jit_api.jit()
local artifact = jit:compile(current_program)

local call_indirect_inc = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B1.BackFuncId("call_indirect_inc")))
assert(call_indirect_inc(41) == 42)

local call_store_42 = ffi.cast("int32_t (*)(int32_t*)", artifact:getpointer(B1.BackFuncId("call_store_42")))
local cell = ffi.new("int32_t[1]", { 0 })
assert(call_store_42(cell) == 42)
assert(cell[0] == 42)

artifact:free()
print("moonlift back_indirect_stmt ok")
