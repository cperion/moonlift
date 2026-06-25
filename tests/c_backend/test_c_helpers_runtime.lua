package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local T = pvm.context(); Schema(T)

local Core = T.LalinCore
local C = T.LalinC
local H = require("lalin.c_helpers")(T)

local function exec_ok(cmd)
    local r = os.execute(cmd)
    return r == true or r == 0
end

if not exec_ok("command -v cc >/dev/null 2>&1") then
    io.write("cc not found; skipping C helper runtime audit\n")
    os.exit(0)
end

local function cty(name) return C.CBackendScalar(Core[name]) end
local i8, i16, i32, i64 = cty("ScalarI8"), cty("ScalarI16"), cty("ScalarI32"), cty("ScalarI64")
local u8, u16, u32, u64 = cty("ScalarU8"), cty("ScalarU16"), cty("ScalarU32"), cty("ScalarU64")
local f64 = cty("ScalarF64")

local helper_order, helper_seen = {}, {}
local function use(kind)
    local id = H.helper_id(kind)
    if not helper_seen[id.text] then
        helper_seen[id.text] = true
        helper_order[#helper_order + 1] = C.CBackendHelperUse(id, kind)
    end
    return id.text
end

local add_i8 = use(C.CBackendHelperIntBinary(Core.BinAdd, i8, C.CBackendIntWrap))
local sub_i16 = use(C.CBackendHelperIntBinary(Core.BinSub, i16, C.CBackendIntWrap))
local mul_i32 = use(C.CBackendHelperIntBinary(Core.BinMul, i32, C.CBackendIntWrap))
local add_i64 = use(C.CBackendHelperIntBinary(Core.BinAdd, i64, C.CBackendIntWrap))
local div_i32 = use(C.CBackendHelperDivRem(Core.BinDiv, i32, C.CBackendDivTrapOnZeroOrOverflow))
local rem_i32 = use(C.CBackendHelperDivRem(Core.BinRem, i32, C.CBackendDivTrapOnZeroOrOverflow))
local div_u32 = use(C.CBackendHelperDivRem(Core.BinDiv, u32, C.CBackendDivTrapOnZeroOrOverflow))
local shl_u32 = use(C.CBackendHelperShift(Core.BinShl, u32, C.CBackendShiftMaskCount))
local lshr_u32 = use(C.CBackendHelperShift(Core.BinLShr, u32, C.CBackendShiftMaskCount))
local ashr_i32 = use(C.CBackendHelperShift(Core.BinAShr, i32, C.CBackendShiftMaskCount))
local rotl_u32 = use(C.CBackendHelperIntrinsic(Core.IntrinsicRotl, u32))
local rotr_u32 = use(C.CBackendHelperIntrinsic(Core.IntrinsicRotr, u32))
local clz_u32 = use(C.CBackendHelperIntrinsic(Core.IntrinsicClz, u32))
local ctz_u32 = use(C.CBackendHelperIntrinsic(Core.IntrinsicCtz, u32))
local bswap_u16 = use(C.CBackendHelperIntrinsic(Core.IntrinsicBswap, u16))
local bswap_u32 = use(C.CBackendHelperIntrinsic(Core.IntrinsicBswap, u32))
local cast_f64_i32 = use(C.CBackendHelperCast(Core.MachineCastFToS, f64, i32))
local bool_i32 = use(C.CBackendHelperBoolNormalize(i32))
local load_i32 = use(C.CBackendHelperLoad(C.CBackendMemoryAccess(i32, 1, C.CBackendMayTrap, false, nil)))
local store_i32 = use(C.CBackendHelperStore(C.CBackendMemoryAccess(i32, 1, C.CBackendMayTrap, false, nil)))

local function source(main_body)
    local lines = {
        "#include <stdint.h>",
        "#include <stddef.h>",
        "#include <string.h>",
        "#include <stdlib.h>",
        "#include <math.h>",
        "",
    }
    for i = 1, #helper_order do
        local hs = H.emit_helper(helper_order[i])
        for j = 1, #hs do lines[#lines + 1] = hs[j] end
    end
    lines[#lines + 1] = "int main(void) {"
    lines[#lines + 1] = main_body
    lines[#lines + 1] = "return 0;"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

local function compile_run(label, body, expect_ok)
    local base = os.tmpname()
    local c_path, exe = base .. ".c", base .. ".out"
    local f = assert(io.open(c_path, "wb")); f:write(source(body)); f:close()
    local ok_compile = exec_ok("cc -std=c99 -Wall -Wextra " .. c_path .. " -lm -o " .. exe)
    assert(ok_compile, label .. " failed to compile")
    local ok_run = exec_ok(exe .. " >/dev/null 2>&1")
    os.remove(c_path); os.remove(exe)
    if expect_ok == false then assert(not ok_run, label .. " should have trapped") else assert(ok_run, label .. " failed at runtime") end
end

compile_run("helper runtime edges", string.format([[ 
if ((int8_t)%s((int8_t)127, (int8_t)1) != (int8_t)-128) return 1;
if ((int16_t)%s((int16_t)-32768, (int16_t)1) != (int16_t)32767) return 2;
if ((int32_t)%s((int32_t)65536, (int32_t)65536) != (int32_t)0) return 3;
if ((int64_t)%s((int64_t)INT64_MAX, (int64_t)1) != (int64_t)INT64_MIN) return 4;
if (%s((int32_t)-7, (int32_t)2) != (int32_t)-3) return 5;
if (%s((int32_t)-7, (int32_t)2) != (int32_t)-1) return 6;
if (%s((uint32_t)0x80000000u, (uint32_t)0xffffffffu) != (uint32_t)0) return 7;
if (%s((uint32_t)1u, (uint32_t)32u) != (uint32_t)1u) return 8;
if (%s((uint32_t)0x80000000u, (uint32_t)32u) != (uint32_t)0x80000000u) return 9;
if (%s((int32_t)-8, (int32_t)1) != (int32_t)-4) return 10;
if (%s((uint32_t)0x12345678u, (uint32_t)8u) != (uint32_t)0x34567812u) return 11;
if (%s((uint32_t)0x12345678u, (uint32_t)8u) != (uint32_t)0x78123456u) return 12;
if (%s((uint32_t)0u) != (uint32_t)32u) return 13;
if (%s((uint32_t)0u) != (uint32_t)32u) return 14;
if (%s((uint16_t)0x1234u) != (uint16_t)0x3412u) return 15;
if (%s((uint32_t)0x11223344u) != (uint32_t)0x44332211u) return 16;
if (%s(42.0) != (int32_t)42) return 17;
if (%s((int32_t)-99) != (uint8_t)1u) return 18;
if (%s((int32_t)0) != (uint8_t)0u) return 19;
{ unsigned char buf[8]; int32_t x = (int32_t)0x11223344; %s(buf + 1, x); if (%s(buf + 1) != x) return 20; }
]], add_i8, sub_i16, mul_i32, add_i64, div_i32, rem_i32, div_u32, shl_u32, lshr_u32, ashr_i32, rotl_u32, rotr_u32, clz_u32, ctz_u32, bswap_u16, bswap_u32, cast_f64_i32, bool_i32, bool_i32, store_i32, load_i32), true)

compile_run("div zero traps", string.format("(void)%s((int32_t)1, (int32_t)0);", div_i32), false)
compile_run("signed min div -1 traps", string.format("(void)%s((int32_t)INT32_MIN, (int32_t)-1);", div_i32), false)
compile_run("signed min rem -1 traps", string.format("(void)%s((int32_t)INT32_MIN, (int32_t)-1);", rem_i32), false)

io.write("lalin C helper runtime audit ok\n")
