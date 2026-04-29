package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Object = require("moonlift.back_object")

local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", [['"'"']]) .. "'"
end

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local out = pipe:read("*a")
    local ok, why, code = pipe:close()
    if ok == nil or ok == false then
        error((out ~= "" and out or command) .. (why and (" (" .. tostring(why) .. " " .. tostring(code) .. ")") or ""), 2)
    end
    return out
end

local function have_cc()
    local ok = os.execute("cc --version >/dev/null 2>&1")
    return ok == true or ok == 0
end

local T = pvm.context()
A2.Define(T)
local validate = Validate.Define(T)
local object_api = Object.Define(T)
local C2 = T.Moon2Core
local B2 = T.Moon2Back

local function sid(text) return B2.BackSigId(text) end
local function fid(text) return B2.BackFuncId(text) end
local function xid(text) return B2.BackExternId(text) end
local function bid(text) return B2.BackBlockId(text) end
local function vid(text) return B2.BackValId(text) end
local function did(text) return B2.BackDataId(text) end
local function slotid(text) return B2.BackStackSlotId(text) end
local i32, ptr, idx, u8 = B2.BackI32, B2.BackPtr, B2.BackIndex, B2.BackU8
local shape_i32 = B2.BackShapeScalar(i32)
local vec_i32x4 = B2.BackVec(i32, 4)
local shape_vec_i32x4 = B2.BackShapeVec(vec_i32x4)
local function mem(id, mode) return B2.BackMemoryInfo(B2.BackAccessId(id), B2.BackAlignUnknown, B2.BackDerefUnknown, B2.BackMayTrap, B2.BackMayNotMove, mode) end
local function addr(base, off) return B2.BackAddress(B2.BackAddrValue(base), off, B2.BackProvUnknown, B2.BackPtrBoundsUnknown) end

local inc_sig, inc_func = sid("sig:inc_i32"), fid("inc_i32")
local inc_entry = bid("entry.inc_i32")
local inc_x, inc_one, inc_out = vid("inc.x"), vid("inc.one"), vid("inc.out")
local call_sig, call_func = sid("sig:call_inc_i32"), fid("call_inc_i32")
local call_entry = bid("entry.call_inc_i32")
local call_x, call_out = vid("call.x"), vid("call.out")

local getk_sig, getk_func = sid("sig:get_k"), fid("get_k")
local getk_entry = bid("entry.get_k")
local k_data = did("data:k")
local k_addr, k_off, k_value = vid("k.addr"), vid("k.off"), vid("k.value")

local slot_sig, slot_func = sid("sig:slot_roundtrip"), fid("slot_roundtrip")
local slot_entry = bid("entry.slot_roundtrip")
local slot = slotid("slot.tmp")
local slot_addr, slot_off_store, slot_off_load = vid("slot.addr"), vid("slot.off.store"), vid("slot.off.load")
local slot_const, slot_value = vid("slot.const"), vid("slot.value")

local store_sig, store_func = sid("sig:store_then_load"), fid("store_then_load")
local store_entry = bid("entry.store_then_load")
local p, x, loaded = vid("p"), vid("x"), vid("loaded")
local store_off, load_off = vid("store.off"), vid("load.off")

local extern_sig = sid("sig:host_add7")
local extern_id = xid("extern:host_add7")
local host_call_sig, host_call_func = sid("sig:call_host_add7"), fid("call_host_add7")
local host_call_entry = bid("entry.call_host_add7")
local cx, cout = vid("host.call.x"), vid("host.call.out")

local copy_sig, copy_func = sid("sig:copy_then_zero"), fid("copy_then_zero")
local copy_entry = bid("entry.copy_then_zero")
local dst, src = vid("dst"), vid("src")
local copy_len, before_zero, before_off = vid("copy.len"), vid("before.zero"), vid("before.off")
local zero_byte, zero_len, after_zero, after_off = vid("zero.byte"), vid("zero.len"), vid("after.zero"), vid("after.off")

local vec_sig, vec_func = sid("sig:first_plus_one_vec"), fid("first_plus_one_vec")
local vec_entry = bid("entry.first_plus_one_vec")
local vp, vloaded, vzero, vone, vones, vadded, vfirst = vid("vec.p"), vid("vec.loaded"), vid("vec.zero"), vid("vec.one"), vid("vec.ones"), vid("vec.added"), vid("vec.first")

local full_program = B2.BackProgram({
    B2.CmdCreateSig(inc_sig, { i32 }, { i32 }),
    B2.CmdCreateSig(call_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityLocal, inc_func, inc_sig),
    B2.CmdDeclareFunc(C2.VisibilityExport, call_func, call_sig),
    B2.CmdBeginFunc(inc_func),
    B2.CmdCreateBlock(inc_entry), B2.CmdSwitchToBlock(inc_entry), B2.CmdBindEntryParams(inc_entry, { inc_x }),
    B2.CmdConst(inc_one, i32, B2.BackLitInt("1")),
    B2.CmdIntBinary(inc_out, B2.BackIntAdd, i32, B2.BackIntSemantics(B2.BackIntWrap, B2.BackIntMayLose), inc_x, inc_one),
    B2.CmdReturnValue(inc_out), B2.CmdSealBlock(inc_entry), B2.CmdFinishFunc(inc_func),
    B2.CmdBeginFunc(call_func),
    B2.CmdCreateBlock(call_entry), B2.CmdSwitchToBlock(call_entry), B2.CmdBindEntryParams(call_entry, { call_x }),
    B2.CmdCall(B2.BackCallValue(call_out, i32), B2.BackCallDirect(inc_func), inc_sig, { call_x }),
    B2.CmdReturnValue(call_out), B2.CmdSealBlock(call_entry), B2.CmdFinishFunc(call_func),

    B2.CmdDeclareData(k_data, 4, 4),
    B2.CmdDataInit(k_data, 0, i32, B2.BackLitInt("77")),
    B2.CmdCreateSig(getk_sig, {}, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, getk_func, getk_sig),
    B2.CmdBeginFunc(getk_func),
    B2.CmdCreateBlock(getk_entry), B2.CmdSwitchToBlock(getk_entry),
    B2.CmdDataAddr(k_addr, k_data),
    B2.CmdConst(k_off, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(k_value, shape_i32, addr(k_addr, k_off), mem("get_k:load", B2.BackAccessRead)),
    B2.CmdReturnValue(k_value), B2.CmdSealBlock(getk_entry), B2.CmdFinishFunc(getk_func),

    B2.CmdCreateSig(slot_sig, {}, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, slot_func, slot_sig),
    B2.CmdBeginFunc(slot_func),
    B2.CmdCreateBlock(slot_entry), B2.CmdSwitchToBlock(slot_entry),
    B2.CmdCreateStackSlot(slot, 4, 4),
    B2.CmdStackAddr(slot_addr, slot),
    B2.CmdConst(slot_const, i32, B2.BackLitInt("42")),
    B2.CmdConst(slot_off_store, idx, B2.BackLitInt("0")),
    B2.CmdStoreInfo(shape_i32, addr(slot_addr, slot_off_store), slot_const, mem("slot:store", B2.BackAccessWrite)),
    B2.CmdConst(slot_off_load, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(slot_value, shape_i32, addr(slot_addr, slot_off_load), mem("slot:load", B2.BackAccessRead)),
    B2.CmdReturnValue(slot_value), B2.CmdSealBlock(slot_entry), B2.CmdFinishFunc(slot_func),

    B2.CmdCreateSig(store_sig, { ptr, i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, store_func, store_sig),
    B2.CmdBeginFunc(store_func),
    B2.CmdCreateBlock(store_entry), B2.CmdSwitchToBlock(store_entry), B2.CmdBindEntryParams(store_entry, { p, x }),
    B2.CmdConst(store_off, idx, B2.BackLitInt("0")),
    B2.CmdStoreInfo(shape_i32, addr(p, store_off), x, mem("store_then_load:store", B2.BackAccessWrite)),
    B2.CmdConst(load_off, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(loaded, shape_i32, addr(p, load_off), mem("store_then_load:load", B2.BackAccessRead)),
    B2.CmdReturnValue(loaded), B2.CmdSealBlock(store_entry), B2.CmdFinishFunc(store_func),

    B2.CmdCreateSig(extern_sig, { i32 }, { i32 }),
    B2.CmdDeclareExtern(extern_id, "host_add7", extern_sig),
    B2.CmdCreateSig(host_call_sig, { i32 }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, host_call_func, host_call_sig),
    B2.CmdBeginFunc(host_call_func),
    B2.CmdCreateBlock(host_call_entry), B2.CmdSwitchToBlock(host_call_entry), B2.CmdBindEntryParams(host_call_entry, { cx }),
    B2.CmdCall(B2.BackCallValue(cout, i32), B2.BackCallExtern(extern_id), extern_sig, { cx }),
    B2.CmdReturnValue(cout), B2.CmdSealBlock(host_call_entry), B2.CmdFinishFunc(host_call_func),

    B2.CmdCreateSig(copy_sig, { ptr, ptr }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, copy_func, copy_sig),
    B2.CmdBeginFunc(copy_func),
    B2.CmdCreateBlock(copy_entry), B2.CmdSwitchToBlock(copy_entry), B2.CmdBindEntryParams(copy_entry, { dst, src }),
    B2.CmdConst(copy_len, idx, B2.BackLitInt("4")),
    B2.CmdMemcpy(dst, src, copy_len),
    B2.CmdConst(before_off, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(before_zero, shape_i32, addr(dst, before_off), mem("copy_then_zero:before", B2.BackAccessRead)),
    B2.CmdConst(zero_byte, u8, B2.BackLitInt("0")),
    B2.CmdConst(zero_len, idx, B2.BackLitInt("4")),
    B2.CmdMemset(dst, zero_byte, zero_len),
    B2.CmdConst(after_off, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(after_zero, shape_i32, addr(dst, after_off), mem("copy_then_zero:after", B2.BackAccessRead)),
    B2.CmdReturnValue(before_zero), B2.CmdSealBlock(copy_entry), B2.CmdFinishFunc(copy_func),

    B2.CmdCreateSig(vec_sig, { ptr }, { i32 }),
    B2.CmdDeclareFunc(C2.VisibilityExport, vec_func, vec_sig),
    B2.CmdBeginFunc(vec_func),
    B2.CmdCreateBlock(vec_entry), B2.CmdSwitchToBlock(vec_entry), B2.CmdBindEntryParams(vec_entry, { vp }),
    B2.CmdConst(vzero, idx, B2.BackLitInt("0")),
    B2.CmdLoadInfo(vloaded, shape_vec_i32x4, addr(vp, vzero), mem("first_plus_one_vec:load", B2.BackAccessRead)),
    B2.CmdConst(vone, i32, B2.BackLitInt("1")),
    B2.CmdVecSplat(vones, vec_i32x4, vone),
    B2.CmdVecBinary(vadded, B2.BackVecIntAdd, vec_i32x4, vloaded, vones),
    B2.CmdVecExtractLane(vfirst, i32, vadded, 0),
    B2.CmdReturnValue(vfirst), B2.CmdSealBlock(vec_entry), B2.CmdFinishFunc(vec_func),
    B2.CmdFinalizeModule,
})

local report = validate.validate(full_program)
assert(#report.issues == 0, "back validation issues: " .. #report.issues)
local full_object = object_api.compile(full_program, { module_name = "moonlift_object_full" })
assert(#full_object:bytes() > 0)

local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local source = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
]]
local parsed = P.parse_module(source)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local source_program = Lower.module(checked.module)
local source_report = validate.validate(source_program)
assert(#source_report.issues == 0)
local source_object = object_api.compile(source_program, { module_name = "moonlift_object_source" })
assert(#source_object:bytes() > 0)

if not have_cc() then
    io.stderr:write("test_back_object_full: cc not available; object byte emission only checked\n")
    print("moonlift back_object_full ok")
    return
end

local base = os.tmpname():gsub("[^A-Za-z0-9_./-]", "_")
local full_obj_path = base .. ".full.o"
local source_obj_path = base .. ".source.o"
local c_path = base .. ".c"
local exe_path = base .. ".exe"
full_object:write(full_obj_path)
source_object:write(source_obj_path)
local c = assert(io.open(c_path, "wb"))
c:write [[
#include <stdint.h>
#include <string.h>

extern int32_t call_inc_i32(int32_t x);
extern int32_t get_k(void);
extern int32_t slot_roundtrip(void);
extern int32_t store_then_load(int32_t* p, int32_t x);
int32_t host_add7(int32_t x) { return x + 7; }
extern int32_t call_host_add7(int32_t x);
extern int32_t copy_then_zero(int32_t* dst, const int32_t* src);
extern int32_t first_plus_one_vec(const int32_t* xs);
extern int32_t sum_i32(const int32_t* xs, int32_t n);

int main(void) {
    if (call_inc_i32(41) != 42) return 1;
    if (get_k() != 77) return 2;
    if (slot_roundtrip() != 42) return 3;
    int32_t cell = 0;
    if (store_then_load(&cell, 1234) != 1234 || cell != 1234) return 4;
    if (call_host_add7(35) != 42) return 5;
    int32_t src[1] = { 123 };
    int32_t dst[1] = { 999 };
    if (copy_then_zero(dst, src) != 123 || dst[0] != 0) return 6;
    int32_t vec[4] = { 41, 1, 2, 3 };
    if (first_plus_one_vec(vec) != 42) return 7;
    int32_t xs[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
    if (sum_i32(xs, 8) != 36) return 8;
    return 0;
}
]]
c:close()

run(string.format("cc %s %s %s -o %s", shell_quote(c_path), shell_quote(full_obj_path), shell_quote(source_obj_path), shell_quote(exe_path)))
run(shell_quote(exe_path))

os.remove(full_obj_path)
os.remove(source_obj_path)
os.remove(c_path)
os.remove(exe_path)
print("moonlift back_object_full ok")
