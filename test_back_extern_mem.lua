package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local J = require("moonlift.back_jit")
local Validate = require("moonlift.back_validate")

local T = pvm.context()
A2.Define(T)
local validate = Validate.Define(T)
local jit_api = J.Define(T)

local C2 = T.Moon2Core
local B2 = T.Moon2Back
local B2 = T.Moon2Back

local function sid(text) return B2.BackSigId(text) end
local function fid(text) return B2.BackFuncId(text) end
local function xid(text) return B2.BackExternId(text) end
local function bid(text) return B2.BackBlockId(text) end
local function vid(text) return B2.BackValId(text) end
local i32 = B2.BackI32
local ptr = B2.BackPtr
local idx = B2.BackIndex
local u8 = B2.BackU8
local shape_i32 = B2.BackShapeScalar(i32)
local function mem(id, mode) return B2.BackMemoryInfo(B2.BackAccessId(id), B2.BackAlignUnknown, B2.BackDerefUnknown, B2.BackMayTrap, B2.BackMayNotMove, mode) end
local function addr(base, off) return B2.BackAddress(B2.BackAddrValue(base), off, B2.BackProvUnknown, B2.BackPtrBoundsUnknown) end

local extern_cb = ffi.cast("int32_t (*)(int32_t)", function(x)
    return x + 7
end)

local extern_sig = sid("sig:host_add7")
local extern_id = xid("extern:host_add7")
local call_sig = sid("sig:call_host_add7")
local call_func = fid("call_host_add7")
local call_entry = bid("entry.call_host_add7")
local cx = vid("call.x")
local cout = vid("call.out")

local copy_sig = sid("sig:copy_then_zero")
local copy_func = fid("copy_then_zero")
local copy_entry = bid("entry.copy_then_zero")
local dst = vid("dst")
local src = vid("src")
local copy_len = vid("copy.len")
local before_zero = vid("before.zero")
local before_off = vid("before.off")
local zero_byte = vid("zero.byte")
local zero_len = vid("zero.len")
local after_zero = vid("after.zero")
local after_off = vid("after.off")

local program = B2.BackProgram({
    B2.CmdCreateSig(extern_sig, { i32 }, { i32 }),
    B2.CmdDeclareExtern(extern_id, "host_add7", extern_sig),
    B2.CmdCreateSig(call_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, call_func, call_sig),
    B2.CmdBeginFunc(call_func),
    B2.CmdCreateBlock(call_entry),
    B2.CmdSwitchToBlock(call_entry),
    B2.CmdBindEntryParams(call_entry, { cx }),
    B2.CmdCall(B2.BackCallValue(cout, i32), B2.BackCallExtern(extern_id), extern_sig, { cx }),
    B2.CmdReturnValue(cout),
    B2.CmdSealBlock(call_entry),
    B2.CmdFinishFunc(call_func),

    B2.CmdCreateSig(copy_sig, { ptr, ptr }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, copy_func, copy_sig),
    B2.CmdBeginFunc(copy_func),
    B2.CmdCreateBlock(copy_entry),
    B2.CmdSwitchToBlock(copy_entry),
    B2.CmdBindEntryParams(copy_entry, { dst, src }),
    B2.CmdConst(copy_len, idx, B2.BackLitInt("4")),
    B2.CmdMemcpy(dst, src, copy_len),
    B2.CmdConst(before_off, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(before_zero, shape_i32, addr(dst, before_off), mem("copy_then_zero:before", B2.BackAccessRead)),
    B2.CmdConst(zero_byte, u8, B2.BackLitInt("0")),
    B2.CmdConst(zero_len, idx, B2.BackLitInt("4")),
    B2.CmdMemset(dst, zero_byte, zero_len),
    B2.CmdConst(after_off, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(after_zero, shape_i32, addr(dst, after_off), mem("copy_then_zero:after", B2.BackAccessRead)),
    B2.CmdReturnValue(before_zero),
    B2.CmdSealBlock(copy_entry),
    B2.CmdFinishFunc(copy_func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
jit:symbol("host_add7", extern_cb)
local artifact = jit:compile(program)

local call_host_add7 = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("call_host_add7")))
assert(call_host_add7(35) == 42)

local copy_then_zero = ffi.cast("int32_t (*)(int32_t*, const int32_t*)", artifact:getpointer(B2.BackFuncId("copy_then_zero")))
local src_arr = ffi.new("int32_t[1]", { 123 })
local dst_arr = ffi.new("int32_t[1]", { 999 })
assert(copy_then_zero(dst_arr, src_arr) == 123)
assert(dst_arr[0] == 0)

artifact:free()
extern_cb:free()

print("moonlift back_extern_mem ok")
