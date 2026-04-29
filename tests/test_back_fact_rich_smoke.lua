package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local J = require("moonlift.back_jit")
local Validate = require("moonlift.back_validate")

local T = pvm.context()
A2.Define(T)
local validate = Validate.Define(T)
local jit_api = J.Define(T)

local C = T.MoonCore
local B = T.MoonBack

local function sid(text) return B.BackSigId(text) end
local function fid(text) return B.BackFuncId(text) end
local function bid(text) return B.BackBlockId(text) end
local function vid(text) return B.BackValId(text) end
local function slotid(text) return B.BackStackSlotId(text) end
local function access(text) return B.BackAccessId(text) end

local i32 = B.BackI32
local index = B.BackIndex
local shape_i32 = B.BackShapeScalar(i32)

local sig = sid("sig:fact_rich_slot")
local func = fid("fact_rich_slot")
local entry = bid("entry.fact_rich_slot")
local slot = slotid("slot.fact_rich")
local zero = vid("zero")
local value = vid("value")
local loaded = vid("loaded")
local addr = B.BackAddress(B.BackAddrStack(slot), zero, B.BackProvStack(slot), B.BackPtrInBounds("stack slot start"))
local write_info = B.BackMemoryInfo(access("store.slot"), B.BackAlignKnown(4), B.BackDerefBytes(4, "stack slot size"), B.BackNonTrapping("stack slot size"), B.BackMayNotMove, B.BackAccessWrite)
local read_info = B.BackMemoryInfo(access("load.slot"), B.BackAlignKnown(4), B.BackDerefBytes(4, "stack slot size"), B.BackNonTrapping("stack slot size"), B.BackMayNotMove, B.BackAccessRead)

local program = B.BackProgram({
    B.CmdCreateSig(sig, {}, { i32 }),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdCreateStackSlot(slot, 4, 4),
    B.CmdConst(zero, index, B.BackLitInt("0")),
    B.CmdConst(value, i32, B.BackLitInt("99")),
    B.CmdStoreInfo(shape_i32, addr, value, write_info),
    B.CmdLoadInfo(loaded, shape_i32, addr, read_info),
    B.CmdAliasFact(B.BackMayAlias(access("store.slot"), access("load.slot"), "same stack slot in smoke test")),
    B.CmdReturnValue(loaded),
    B.CmdSealBlock(entry),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})

local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)
local fn = ffi.cast("int32_t (*)()", artifact:getpointer(func))
assert(fn() == 99)
artifact:free()

print("moonlift back_fact_rich_smoke ok")
