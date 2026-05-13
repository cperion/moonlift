-- tests/test_dasm_backend_full.lua
-- Comprehensive DynASM backend test — mirrors the cranelift test_back_*.lua tests.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lib/?.lua;" ..
               "./.vendor/LuaJIT/dynasm/?.lua;" .. package.path

local ffi  = require("ffi")
local pvm  = require("moonlift.pvm")
local A2   = require("moonlift.asdl")

local T = pvm.context()
A2.Define(T)

local dasm_init = require("back.dasm")
local api = dasm_init.Define(T)

local B2 = T.MoonBack
local C2 = T.MoonCore

-- ── helpers ──────────────────────────────────────────────────────────

local function sid(text)  return B2.BackSigId(text) end
local function fid(text)  return B2.BackFuncId(text) end
local function xid(text)  return B2.BackExternId(text) end
local function bid(text)  return B2.BackBlockId(text) end
local function vid(text)  return B2.BackValId(text) end
local function did(text)  return B2.BackDataId(text) end
local function slotid(text) return B2.BackStackSlotId(text) end

local i32   = B2.BackI32
local i64   = B2.BackI64
local u32   = B2.BackU32
local u8    = B2.BackU8
local f32   = B2.BackF32
local f64   = B2.BackF64
local idx   = B2.BackIndex
local ptr   = B2.BackPtr
local bool  = B2.BackBool

local shape_i32  = B2.BackShapeScalar(i32)
local shape_f64  = B2.BackShapeScalar(f64)
local shape_u32  = B2.BackShapeScalar(u32)

local function mem(id, mode)
    return B2.BackMemoryInfo(
        B2.BackAccessId(id),
        B2.BackAlignUnknown,
        B2.BackDerefUnknown,
        B2.BackMayTrap,
        B2.BackMayNotMove,
        mode)
end

local function addr(base, off)
    return B2.BackAddress(
        B2.BackAddrValue(base),
        off,
        B2.BackProvUnknown,
        B2.BackPtrBoundsUnknown)
end

local function sem() return B2.BackIntSemantics(B2.BackIntWrap, B2.BackIntMayLose) end

local pass_count = 0
local function check(name, ok, got, expected)
    if ok then
        pass_count = pass_count + 1
    else
        error(string.format("FAIL %s: got %s, expected %s", name, tostring(got), tostring(expected)), 2)
    end
end
local function eq(name, got, expected) check(name, got == expected, got, expected) end

-- ── test: add_i32 ────────────────────────────────────────────────────

do
    local art = api.jit():compile(B2.BackProgram({
        B2.CmdCreateSig(sid("sig:add_i32"), { i32, i32 }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, fid("add_i32"), sid("sig:add_i32")),
        B2.CmdBeginFunc(fid("add_i32")),
        B2.CmdCreateBlock(bid("entry.add_i32")),
        B2.CmdSwitchToBlock(bid("entry.add_i32")),
        B2.CmdBindEntryParams(bid("entry.add_i32"), { vid("a"), vid("b") }),
        B2.CmdIntBinary(vid("r"), B2.BackIntAdd, i32, sem(), vid("a"), vid("b")),
        B2.CmdReturnValue(vid("r")),
        B2.CmdSealBlock(bid("entry.add_i32")),
        B2.CmdFinishFunc(fid("add_i32")),
        B2.CmdFinalizeModule,
    }))
    local fn = ffi.cast("int32_t(*)(int32_t,int32_t)", art:getpointer("add_i32"))
    eq("add_i32(20,22)", fn(20, 22), 42)
    eq("add_i32(-10,3)", fn(-10, 3), -7)
    art:free()
    print("add_i32: ok")
end

-- ── test: branch + select (abs / sign) ───────────────────────────────

do
    local select_sig   = sid("sig:select_abs_i32")
    local select_func  = fid("select_abs_i32")
    local select_entry = bid("entry.select_abs_i32")
    local x, zero, neg_, cond_, out =
        vid("x"), vid("s.zero"), vid("s.neg"), vid("s.cond"), vid("s.out")

    local branch_sig   = sid("sig:branch_sign_i32")
    local branch_func  = fid("branch_sign_i32")
    local branch_entry = bid("entry.branch_sign_i32")
    local branch_neg   = bid("branch_sign_i32.neg")
    local branch_nonneg = bid("branch_sign_i32.nonneg")
    local bx, bzero, bcond, bneg_r, bnonneg_r =
        vid("bx"), vid("b.zero"), vid("b.cond"), vid("b.ret.neg"), vid("b.ret.nonneg")

    local art = api.jit():compile(B2.BackProgram({
        B2.CmdCreateSig(select_sig, { i32 }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, select_func, select_sig),
        B2.CmdBeginFunc(select_func),
        B2.CmdCreateBlock(select_entry), B2.CmdSwitchToBlock(select_entry),
        B2.CmdBindEntryParams(select_entry, { x }),
        B2.CmdConst(zero, i32, B2.BackLitInt("0")),
        B2.CmdUnary(neg_, B2.BackUnaryIneg, shape_i32, x),
        B2.CmdCompare(cond_, B2.BackSIcmpLt, shape_i32, x, zero),
        B2.CmdSelect(out, shape_i32, cond_, neg_, x),
        B2.CmdReturnValue(out),
        B2.CmdSealBlock(select_entry),
        B2.CmdFinishFunc(select_func),

        B2.CmdCreateSig(branch_sig, { i32 }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, branch_func, branch_sig),
        B2.CmdBeginFunc(branch_func),
        B2.CmdCreateBlock(branch_entry),
        B2.CmdCreateBlock(branch_neg),
        B2.CmdCreateBlock(branch_nonneg),
        B2.CmdSwitchToBlock(branch_entry),
        B2.CmdBindEntryParams(branch_entry, { bx }),
        B2.CmdConst(bzero, i32, B2.BackLitInt("0")),
        B2.CmdCompare(bcond, B2.BackSIcmpLt, shape_i32, bx, bzero),
        B2.CmdBrIf(bcond, branch_neg, {}, branch_nonneg, {}),
        B2.CmdSwitchToBlock(branch_neg),
        B2.CmdConst(bneg_r, i32, B2.BackLitInt("-1")),
        B2.CmdReturnValue(bneg_r),
        B2.CmdSealBlock(branch_neg),
        B2.CmdSwitchToBlock(branch_nonneg),
        B2.CmdConst(bnonneg_r, i32, B2.BackLitInt("1")),
        B2.CmdReturnValue(bnonneg_r),
        B2.CmdSealBlock(branch_nonneg),
        B2.CmdSealBlock(branch_entry),
        B2.CmdFinishFunc(branch_func),
        B2.CmdFinalizeModule,
    }))

    local select_abs = ffi.cast("int32_t(*)(int32_t)", art:getpointer("select_abs_i32"))
    eq("select_abs(-42)", select_abs(-42), 42)
    eq("select_abs(17)",  select_abs(17),  17)
    eq("select_abs(0)",   select_abs(0),   0)

    local branch_sign = ffi.cast("int32_t(*)(int32_t)", art:getpointer("branch_sign_i32"))
    eq("branch_sign(-1)", branch_sign(-1), -1)
    eq("branch_sign(0)",  branch_sign(0),   1)
    eq("branch_sign(99)", branch_sign(99),  1)

    art:free()
    print("branch_select: ok")
end

-- ── test: direct calls ────────────────────────────────────────────────

do
    local inc_sig  = sid("sig:inc_i32")
    local inc_func = fid("inc_i32")
    local inc_entry = bid("entry.inc_i32")
    local call_sig  = sid("sig:call_inc_i32")
    local call_func = fid("call_inc_i32")
    local call_entry = bid("entry.call_inc_i32")

    local art = api.jit():compile(B2.BackProgram({
        B2.CmdCreateSig(inc_sig, { i32 }, { i32 }),
        B2.CmdCreateSig(call_sig, { i32 }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityLocal,  inc_func,  inc_sig),
        B2.CmdDeclareFunc(C2.VisibilityExport, call_func, call_sig),
        B2.CmdBeginFunc(inc_func),
        B2.CmdCreateBlock(inc_entry), B2.CmdSwitchToBlock(inc_entry),
        B2.CmdBindEntryParams(inc_entry, { vid("inc.x") }),
        B2.CmdConst(vid("inc.one"), i32, B2.BackLitInt("1")),
        B2.CmdIntBinary(vid("inc.out"), B2.BackIntAdd, i32, sem(), vid("inc.x"), vid("inc.one")),
        B2.CmdReturnValue(vid("inc.out")),
        B2.CmdSealBlock(inc_entry),
        B2.CmdFinishFunc(inc_func),

        B2.CmdBeginFunc(call_func),
        B2.CmdCreateBlock(call_entry), B2.CmdSwitchToBlock(call_entry),
        B2.CmdBindEntryParams(call_entry, { vid("call.x") }),
        B2.CmdCall(B2.BackCallValue(vid("call.out"), i32), B2.BackCallDirect(inc_func), inc_sig, { vid("call.x") }),
        B2.CmdReturnValue(vid("call.out")),
        B2.CmdSealBlock(call_entry),
        B2.CmdFinishFunc(call_func),
        B2.CmdFinalizeModule,
    }))
    local call_inc = ffi.cast("int32_t(*)(int32_t)", art:getpointer("call_inc_i32"))
    eq("call_inc(41)", call_inc(41), 42)
    eq("call_inc(-8)", call_inc(-8), -7)
    art:free()
    print("direct_call: ok")
end

-- ── test: extern call + memcpy + memset ──────────────────────────────

do
    local extern_cb = ffi.cast("int32_t(*)(int32_t)", function(x) return x + 7 end)
    local extern_sig  = sid("sig:host_add7")
    local extern_id   = xid("extern:host_add7")
    local call_sig    = sid("sig:call_host_add7")
    local call_func   = fid("call_host_add7")
    local call_entry  = bid("entry.call_host_add7")
    local copy_sig    = sid("sig:copy_then_zero")
    local copy_func   = fid("copy_then_zero")
    local copy_entry  = bid("entry.copy_then_zero")

    local jit = api.jit()
    jit:symbol("host_add7", extern_cb)
    local art = jit:compile(B2.BackProgram({
        B2.CmdCreateSig(extern_sig, { i32 }, { i32 }),
        B2.CmdDeclareExtern(extern_id, "host_add7", extern_sig),
        B2.CmdCreateSig(call_sig, { i32 }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, call_func, call_sig),
        B2.CmdBeginFunc(call_func),
        B2.CmdCreateBlock(call_entry), B2.CmdSwitchToBlock(call_entry),
        B2.CmdBindEntryParams(call_entry, { vid("cx") }),
        B2.CmdCall(B2.BackCallValue(vid("cout"), i32), B2.BackCallExtern(extern_id), extern_sig, { vid("cx") }),
        B2.CmdReturnValue(vid("cout")),
        B2.CmdSealBlock(call_entry),
        B2.CmdFinishFunc(call_func),

        B2.CmdCreateSig(copy_sig, { ptr, ptr }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, copy_func, copy_sig),
        B2.CmdBeginFunc(copy_func),
        B2.CmdCreateBlock(copy_entry), B2.CmdSwitchToBlock(copy_entry),
        B2.CmdBindEntryParams(copy_entry, { vid("dst"), vid("src") }),
        B2.CmdConst(vid("copy.len"), idx, B2.BackLitInt("4")),
        B2.CmdMemcpy(vid("dst"), vid("src"), vid("copy.len")),
        B2.CmdConst(vid("before.off"), idx, B2.BackLitInt("0")),
        B2.CmdLoadInfo(vid("before.zero"), shape_i32, addr(vid("dst"), vid("before.off")), mem("copy:before", B2.BackAccessRead)),
        B2.CmdConst(vid("zero.byte"), u8, B2.BackLitInt("0")),
        B2.CmdConst(vid("zero.len"), idx, B2.BackLitInt("4")),
        B2.CmdMemset(vid("dst"), vid("zero.byte"), vid("zero.len")),
        B2.CmdReturnValue(vid("before.zero")),
        B2.CmdSealBlock(copy_entry),
        B2.CmdFinishFunc(copy_func),
        B2.CmdFinalizeModule,
    }))

    local call_host = ffi.cast("int32_t(*)(int32_t)", art:getpointer("call_host_add7"))
    eq("call_host_add7(35)", call_host(35), 42)

    local copy_then_zero = ffi.cast("int32_t(*)(int32_t*, const int32_t*)", art:getpointer("copy_then_zero"))
    local src_arr = ffi.new("int32_t[1]", { 123 })
    local dst_arr = ffi.new("int32_t[1]", { 999 })
    eq("copy_then_zero result", copy_then_zero(dst_arr, src_arr), 123)
    eq("dst_arr[0] == 0", dst_arr[0], 0)

    art:free()
    extern_cb:free()
    print("extern_mem: ok")
end

-- ── test: memory / data / stack-slots ────────────────────────────────

do
    local k_data    = did("data:k")
    local getk_sig  = sid("sig:get_k")
    local getk_func = fid("get_k")
    local getk_entry = bid("entry.get_k")
    local slot_sig  = sid("sig:slot_roundtrip")
    local slot_func = fid("slot_roundtrip")
    local slot_entry = bid("entry.slot_roundtrip")
    local slot_id   = slotid("slot.tmp")
    local store_sig  = sid("sig:store_then_load")
    local store_func = fid("store_then_load")
    local store_entry = bid("entry.store_then_load")

    local art = api.jit():compile(B2.BackProgram({
        B2.CmdDeclareData(k_data, 4, 4),
        B2.CmdDataInit(k_data, 0, i32, B2.BackLitInt("77")),

        B2.CmdCreateSig(getk_sig, {}, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, getk_func, getk_sig),
        B2.CmdBeginFunc(getk_func),
        B2.CmdCreateBlock(getk_entry), B2.CmdSwitchToBlock(getk_entry),
        B2.CmdDataAddr(vid("k.addr"), k_data),
        B2.CmdConst(vid("k.off"), idx, B2.BackLitInt("0")),
        B2.CmdLoadInfo(vid("k.val"), shape_i32, addr(vid("k.addr"), vid("k.off")), mem("getk:load", B2.BackAccessRead)),
        B2.CmdReturnValue(vid("k.val")),
        B2.CmdSealBlock(getk_entry),
        B2.CmdFinishFunc(getk_func),

        B2.CmdCreateSig(slot_sig, {}, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, slot_func, slot_sig),
        B2.CmdBeginFunc(slot_func),
        B2.CmdCreateBlock(slot_entry), B2.CmdSwitchToBlock(slot_entry),
        B2.CmdCreateStackSlot(slot_id, 4, 4),
        B2.CmdStackAddr(vid("slot.addr"), slot_id),
        B2.CmdConst(vid("slot.const"), i32, B2.BackLitInt("42")),
        B2.CmdConst(vid("slot.off"), idx, B2.BackLitInt("0")),
        B2.CmdStoreInfo(shape_i32, addr(vid("slot.addr"), vid("slot.off")), vid("slot.const"), mem("slot:store", B2.BackAccessWrite)),
        B2.CmdConst(vid("slot.off2"), idx, B2.BackLitInt("0")),
        B2.CmdLoadInfo(vid("slot.val"), shape_i32, addr(vid("slot.addr"), vid("slot.off2")), mem("slot:load", B2.BackAccessRead)),
        B2.CmdReturnValue(vid("slot.val")),
        B2.CmdSealBlock(slot_entry),
        B2.CmdFinishFunc(slot_func),

        B2.CmdCreateSig(store_sig, { ptr, i32 }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, store_func, store_sig),
        B2.CmdBeginFunc(store_func),
        B2.CmdCreateBlock(store_entry), B2.CmdSwitchToBlock(store_entry),
        B2.CmdBindEntryParams(store_entry, { vid("p"), vid("x") }),
        B2.CmdConst(vid("store.off"), idx, B2.BackLitInt("0")),
        B2.CmdStoreInfo(shape_i32, addr(vid("p"), vid("store.off")), vid("x"), mem("store:store", B2.BackAccessWrite)),
        B2.CmdConst(vid("load.off"), idx, B2.BackLitInt("0")),
        B2.CmdLoadInfo(vid("loaded"), shape_i32, addr(vid("p"), vid("load.off")), mem("store:load", B2.BackAccessRead)),
        B2.CmdReturnValue(vid("loaded")),
        B2.CmdSealBlock(store_entry),
        B2.CmdFinishFunc(store_func),
        B2.CmdFinalizeModule,
    }))

    local get_k = ffi.cast("int32_t(*)()", art:getpointer("get_k"))
    eq("get_k()", get_k(), 77)

    local slot_rt = ffi.cast("int32_t(*)()", art:getpointer("slot_roundtrip"))
    eq("slot_roundtrip()", slot_rt(), 42)

    local store_load = ffi.cast("int32_t(*)(int32_t*, int32_t)", art:getpointer("store_then_load"))
    local cell = ffi.new("int32_t[1]", { 0 })
    eq("store_then_load result", store_load(cell, 1234), 1234)
    eq("cell[0]", cell[0], 1234)

    art:free()
    print("memory_data: ok")
end

-- ── test: indirect calls + func-addr + void call ─────────────────────

do
    local inc_sig      = sid("sig:inc")
    local indirect_sig = sid("sig:indirect")
    local store_sig    = sid("sig:store_42")
    local call_store_sig = sid("sig:call_store_42")

    local art = api.jit():compile(B2.BackProgram({
        B2.CmdCreateSig(inc_sig,        { i32 },       { i32 }),
        B2.CmdCreateSig(indirect_sig,   { i32 },       { i32 }),
        B2.CmdCreateSig(store_sig,      { ptr },       {}     ),
        B2.CmdCreateSig(call_store_sig, { ptr },       { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityLocal,  fid("inc_fn"),  inc_sig),
        B2.CmdDeclareFunc(C2.VisibilityExport, fid("indirect_inc"), indirect_sig),
        B2.CmdDeclareFunc(C2.VisibilityLocal,  fid("store_42"),     store_sig),
        B2.CmdDeclareFunc(C2.VisibilityExport, fid("call_store_42"), call_store_sig),

        B2.CmdBeginFunc(fid("inc_fn")),
        B2.CmdCreateBlock(bid("e.inc")), B2.CmdSwitchToBlock(bid("e.inc")),
        B2.CmdBindEntryParams(bid("e.inc"), { vid("ix") }),
        B2.CmdConst(vid("i1"), i32, B2.BackLitInt("1")),
        B2.CmdIntBinary(vid("io"), B2.BackIntAdd, i32, sem(), vid("ix"), vid("i1")),
        B2.CmdReturnValue(vid("io")),
        B2.CmdSealBlock(bid("e.inc")),
        B2.CmdFinishFunc(fid("inc_fn")),

        B2.CmdBeginFunc(fid("indirect_inc")),
        B2.CmdCreateBlock(bid("e.indir")), B2.CmdSwitchToBlock(bid("e.indir")),
        B2.CmdBindEntryParams(bid("e.indir"), { vid("cx") }),
        B2.CmdFuncAddr(vid("fp"), fid("inc_fn")),
        B2.CmdCall(B2.BackCallValue(vid("cout"), i32), B2.BackCallIndirect(vid("fp")), inc_sig, { vid("cx") }),
        B2.CmdReturnValue(vid("cout")),
        B2.CmdSealBlock(bid("e.indir")),
        B2.CmdFinishFunc(fid("indirect_inc")),

        B2.CmdBeginFunc(fid("store_42")),
        B2.CmdCreateBlock(bid("e.s42")), B2.CmdSwitchToBlock(bid("e.s42")),
        B2.CmdBindEntryParams(bid("e.s42"), { vid("sp") }),
        B2.CmdConst(vid("s42"), i32, B2.BackLitInt("42")),
        B2.CmdConst(vid("szero"), idx, B2.BackLitInt("0")),
        B2.CmdStoreInfo(shape_i32, addr(vid("sp"), vid("szero")), vid("s42"), mem("s42:store", B2.BackAccessWrite)),
        B2.CmdReturnVoid,
        B2.CmdSealBlock(bid("e.s42")),
        B2.CmdFinishFunc(fid("store_42")),

        B2.CmdBeginFunc(fid("call_store_42")),
        B2.CmdCreateBlock(bid("e.cs42")), B2.CmdSwitchToBlock(bid("e.cs42")),
        B2.CmdBindEntryParams(bid("e.cs42"), { vid("cp") }),
        B2.CmdCall(B2.BackCallStmt, B2.BackCallDirect(fid("store_42")), store_sig, { vid("cp") }),
        B2.CmdConst(vid("lzero"), idx, B2.BackLitInt("0")),
        B2.CmdLoadInfo(vid("lval"), shape_i32, addr(vid("cp"), vid("lzero")), mem("cs42:load", B2.BackAccessRead)),
        B2.CmdReturnValue(vid("lval")),
        B2.CmdSealBlock(bid("e.cs42")),
        B2.CmdFinishFunc(fid("call_store_42")),
        B2.CmdFinalizeModule,
    }))

    local indirect_inc = ffi.cast("int32_t(*)(int32_t)", art:getpointer("indirect_inc"))
    eq("indirect_inc(41)", indirect_inc(41), 42)

    local call_store = ffi.cast("int32_t(*)(int32_t*)", art:getpointer("call_store_42"))
    local cell = ffi.new("int32_t[1]", { 0 })
    eq("call_store_42 result", call_store(cell), 42)
    eq("cell[0] == 42", cell[0], 42)

    art:free()
    print("indirect_stmt: ok")
end

-- ── test: casts + intrinsics + switch ────────────────────────────────

do
    local cast_sig    = sid("sig:i32_to_f64")
    local poprot_sig  = sid("sig:poprot")
    local switch_sig  = sid("sig:switch_i32")

    local art = api.jit():compile(B2.BackProgram({
        -- i32 → f64 cast
        B2.CmdCreateSig(cast_sig, { i32 }, { f64 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, fid("i32_to_f64"), cast_sig),
        B2.CmdBeginFunc(fid("i32_to_f64")),
        B2.CmdCreateBlock(bid("e.cast")), B2.CmdSwitchToBlock(bid("e.cast")),
        B2.CmdBindEntryParams(bid("e.cast"), { vid("cast.x") }),
        B2.CmdCast(vid("cast.out"), B2.BackSToF, f64, vid("cast.x")),
        B2.CmdReturnValue(vid("cast.out")),
        B2.CmdSealBlock(bid("e.cast")),
        B2.CmdFinishFunc(fid("i32_to_f64")),

        -- popcount + rotate
        B2.CmdCreateSig(poprot_sig, { u32 }, { u32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, fid("poprot"), poprot_sig),
        B2.CmdBeginFunc(fid("poprot")),
        B2.CmdCreateBlock(bid("e.poprot")), B2.CmdSwitchToBlock(bid("e.poprot")),
        B2.CmdBindEntryParams(bid("e.poprot"), { vid("pop.x") }),
        B2.CmdIntrinsic(vid("pop.pc"), B2.BackIntrinsicPopcount, shape_u32, { vid("pop.x") }),
        B2.CmdConst(vid("pop.one"), u32, B2.BackLitInt("1")),
        B2.CmdRotate(vid("pop.out"), B2.BackRotateLeft, u32, vid("pop.pc"), vid("pop.one")),
        B2.CmdReturnValue(vid("pop.out")),
        B2.CmdSealBlock(bid("e.poprot")),
        B2.CmdFinishFunc(fid("poprot")),

        -- switch_i32
        B2.CmdCreateSig(switch_sig, { i32 }, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, fid("switch_i32"), switch_sig),
        B2.CmdBeginFunc(fid("switch_i32")),
        B2.CmdCreateBlock(bid("sw.entry")),
        B2.CmdCreateBlock(bid("sw.case0")),
        B2.CmdCreateBlock(bid("sw.case5")),
        B2.CmdCreateBlock(bid("sw.default")),
        B2.CmdSwitchToBlock(bid("sw.entry")),
        B2.CmdBindEntryParams(bid("sw.entry"), { vid("sw.x") }),
        B2.CmdSwitchInt(vid("sw.x"), i32, {
            B2.BackSwitchCase("0", bid("sw.case0")),
            B2.BackSwitchCase("5", bid("sw.case5")),
        }, bid("sw.default")),
        B2.CmdSwitchToBlock(bid("sw.case0")),
        B2.CmdConst(vid("sw.r0"), i32, B2.BackLitInt("10")),
        B2.CmdReturnValue(vid("sw.r0")),
        B2.CmdSealBlock(bid("sw.case0")),
        B2.CmdSwitchToBlock(bid("sw.case5")),
        B2.CmdConst(vid("sw.r5"), i32, B2.BackLitInt("50")),
        B2.CmdReturnValue(vid("sw.r5")),
        B2.CmdSealBlock(bid("sw.case5")),
        B2.CmdSwitchToBlock(bid("sw.default")),
        B2.CmdConst(vid("sw.rd"), i32, B2.BackLitInt("99")),
        B2.CmdReturnValue(vid("sw.rd")),
        B2.CmdSealBlock(bid("sw.default")),
        B2.CmdSealBlock(bid("sw.entry")),
        B2.CmdFinishFunc(fid("switch_i32")),
        B2.CmdFinalizeModule,
    }))

    local i32_to_f64 = ffi.cast("double(*)(int32_t)", art:getpointer("i32_to_f64"))
    eq("i32_to_f64(-7)", tonumber(i32_to_f64(-7)), -7.0)

    local poprot = ffi.cast("uint32_t(*)(uint32_t)", art:getpointer("poprot"))
    eq("poprot(0xF0)", poprot(0xF0), 8)

    local switch_i32 = ffi.cast("int32_t(*)(int32_t)", art:getpointer("switch_i32"))
    eq("switch_i32(0)", switch_i32(0), 10)
    eq("switch_i32(5)", switch_i32(5), 50)
    eq("switch_i32(9)", switch_i32(9), 99)

    art:free()
    print("cast_intrinsic_switch: ok")
end

-- ── test: loop (block params / back-edge) ────────────────────────────

do
    local art = api.jit():compile(B2.BackProgram({
        B2.CmdCreateSig(sid("sig:count"), {}, { i32 }),
        B2.CmdDeclareFunc(C2.VisibilityExport, fid("count"), sid("sig:count")),
        B2.CmdBeginFunc(fid("count")),
        B2.CmdCreateBlock(bid("entry")),
        B2.CmdCreateBlock(bid("header")),
        B2.CmdCreateBlock(bid("body")),
        B2.CmdCreateBlock(bid("exit")),
        B2.CmdSwitchToBlock(bid("entry")),
        B2.CmdAppendBlockParam(bid("header"), vid("header.i"), shape_i32),
        B2.CmdAppendBlockParam(bid("body"),   vid("body.i"),   shape_i32),
        B2.CmdAppendBlockParam(bid("exit"),   vid("exit.i"),   shape_i32),
        B2.CmdConst(vid("zero"), i32, B2.BackLitInt("0")),
        B2.CmdJump(bid("header"), { vid("zero") }),
        B2.CmdSwitchToBlock(bid("header")),
        B2.CmdAlias(vid("i"), vid("header.i")),
        B2.CmdConst(vid("limit"), i32, B2.BackLitInt("4")),
        B2.CmdCompare(vid("cond"), B2.BackSIcmpLt, shape_i32, vid("i"), vid("limit")),
        B2.CmdBrIf(vid("cond"), bid("body"), { vid("header.i") }, bid("exit"), { vid("header.i") }),
        B2.CmdSealBlock(bid("body")),
        B2.CmdSealBlock(bid("exit")),
        B2.CmdSwitchToBlock(bid("body")),
        B2.CmdAlias(vid("i2"), vid("body.i")),
        B2.CmdConst(vid("one"), i32, B2.BackLitInt("1")),
        B2.CmdIntBinary(vid("next"), B2.BackIntAdd, i32, sem(), vid("i2"), vid("one")),
        B2.CmdJump(bid("header"), { vid("next") }),
        B2.CmdSealBlock(bid("header")),
        B2.CmdSwitchToBlock(bid("exit")),
        B2.CmdAlias(vid("result"), vid("exit.i")),
        B2.CmdReturnValue(vid("result")),
        B2.CmdFinishFunc(fid("count")),
        B2.CmdFinalizeModule,
    }))

    local count = ffi.cast("int32_t(*)()", art:getpointer("count"))
    eq("count()", count(), 4)
    art:free()
    print("loop_block_param: ok")
end

-- ── summary ──────────────────────────────────────────────────────────

print(string.format("\ndasm backend full test: %d checks passed", pass_count))
print("OK")
