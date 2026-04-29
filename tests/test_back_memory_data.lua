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
local function did(text) return B2.BackDataId(text) end
local function slotid(text) return B2.BackStackSlotId(text) end
local i32 = B2.BackI32
local ptr = B2.BackPtr
local shape_i32 = B2.BackShapeScalar(i32)
local function mem(id, mode) return B2.BackMemoryInfo(B2.BackAccessId(id), B2.BackAlignUnknown, B2.BackDerefUnknown, B2.BackMayTrap, B2.BackMayNotMove, mode) end
local function addr(base, off) return B2.BackAddress(B2.BackAddrValue(base), off, B2.BackProvUnknown, B2.BackPtrBoundsUnknown) end

local getk_sig = sid("sig:get_k")
local getk_func = fid("get_k")
local getk_entry = bid("entry.get_k")
local k_data = did("data:k")
local k_addr = vid("k.addr")
local k_off = vid("k.off")
local k_value = vid("k.value")

local slot_sig = sid("sig:slot_roundtrip")
local slot_func = fid("slot_roundtrip")
local slot_entry = bid("entry.slot_roundtrip")
local slot = slotid("slot.tmp")
local slot_addr = vid("slot.addr")
local slot_off_store = vid("slot.off.store")
local slot_off_load = vid("slot.off.load")
local slot_const = vid("slot.const")
local slot_value = vid("slot.value")

local store_sig = sid("sig:store_then_load")
local store_func = fid("store_then_load")
local store_entry = bid("entry.store_then_load")
local p = vid("p")
local x = vid("x")
local loaded = vid("loaded")
local store_off = vid("store.off")
local load_off = vid("load.off")

local program = B2.BackProgram({
    B2.CmdDeclareData(k_data, 4, 4),
    B2.CmdDataInit(k_data, 0, i32, B2.BackLitInt("77")),

    B2.CmdCreateSig(getk_sig, {}, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, getk_func, getk_sig),
    B2.CmdBeginFunc(getk_func),
    B2.CmdCreateBlock(getk_entry),
    B2.CmdSwitchToBlock(getk_entry),
    B2.CmdDataAddr(k_addr, k_data),
    B2.CmdConst(k_off, B2.BackIndex, B2.BackLitInt("0")),
    B2.CmdLoadInfo(k_value, shape_i32, addr(k_addr, k_off), mem("get_k:load", B2.BackAccessRead)),
    B2.CmdReturnValue(k_value),
    B2.CmdSealBlock(getk_entry),
    B2.CmdFinishFunc(getk_func),

    B2.CmdCreateSig(slot_sig, {}, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, slot_func, slot_sig),
    B2.CmdBeginFunc(slot_func),
    B2.CmdCreateBlock(slot_entry),
    B2.CmdSwitchToBlock(slot_entry),
    B2.CmdCreateStackSlot(slot, 4, 4),
    B2.CmdStackAddr(slot_addr, slot),
    B2.CmdConst(slot_const, i32, B2.BackLitInt("42")),
    B2.CmdConst(slot_off_store, B2.BackIndex, B2.BackLitInt("0")),
    B2.CmdStoreInfo(shape_i32, addr(slot_addr, slot_off_store), slot_const, mem("slot_roundtrip:store", B2.BackAccessWrite)),
    B2.CmdConst(slot_off_load, B2.BackIndex, B2.BackLitInt("0")),
    B2.CmdLoadInfo(slot_value, shape_i32, addr(slot_addr, slot_off_load), mem("slot_roundtrip:load", B2.BackAccessRead)),
    B2.CmdReturnValue(slot_value),
    B2.CmdSealBlock(slot_entry),
    B2.CmdFinishFunc(slot_func),

    B2.CmdCreateSig(store_sig, { ptr, i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, store_func, store_sig),
    B2.CmdBeginFunc(store_func),
    B2.CmdCreateBlock(store_entry),
    B2.CmdSwitchToBlock(store_entry),
    B2.CmdBindEntryParams(store_entry, { p, x }),
    B2.CmdConst(store_off, B2.BackIndex, B2.BackLitInt("0")),
    B2.CmdStoreInfo(shape_i32, addr(p, store_off), x, mem("store_then_load:store", B2.BackAccessWrite)),
    B2.CmdConst(load_off, B2.BackIndex, B2.BackLitInt("0")),
    B2.CmdLoadInfo(loaded, shape_i32, addr(p, load_off), mem("store_then_load:load", B2.BackAccessRead)),
    B2.CmdReturnValue(loaded),
    B2.CmdSealBlock(store_entry),
    B2.CmdFinishFunc(store_func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)

local get_k = ffi.cast("int32_t (*)()", artifact:getpointer(B2.BackFuncId("get_k")))
assert(get_k() == 77)

local slot_roundtrip = ffi.cast("int32_t (*)()", artifact:getpointer(B2.BackFuncId("slot_roundtrip")))
assert(slot_roundtrip() == 42)

local store_then_load = ffi.cast("int32_t (*)(int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("store_then_load")))
local cell = ffi.new("int32_t[1]", { 0 })
assert(store_then_load(cell, 1234) == 1234)
assert(cell[0] == 1234)

artifact:free()

print("moonlift back_memory_data ok")
