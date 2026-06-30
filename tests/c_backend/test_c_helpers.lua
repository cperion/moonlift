package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context(); Schema(T)

local Core = T.LalinCore
local C = T.LalinC
local H = require("lalin.c_helpers")(T)
local Emit = require("lalin.c_emit")(T)
local CodeType = require("lalin.code_type")(T)

local i32 = C.CBackendScalar(Core.ScalarI32)
local u32 = C.CBackendScalar(Core.ScalarU32)
local i64 = C.CBackendScalar(Core.ScalarI64)
local f64 = C.CBackendScalar(Core.ScalarF64)

local add_kind = C.CBackendHelperIntBinary(Core.BinAdd, i32, C.CBackendIntWrap)
local id = H.helper_id(add_kind)
assert(id.text == "ml_i32_add_intwrap")
local ctx = { helpers = {} }
assert(H.register(ctx, add_kind).text == id.text)
assert(H.register(ctx, add_kind).text == id.text)
assert(#ctx.helper_order == 1, "helper register deduplicates")
local add_src = table.concat(H.emit_helper(ctx.helper_order[1]), "\n")
assert(add_src:match("ml_i32_add_intwrap"))
assert(add_src:match("uint32_t"), "wrapping add uses same-width unsigned arithmetic")
local float_add_src = table.concat(H.emit_helper(C.CBackendHelperFloatBinary(Core.BinAdd, f64)), "\n")
assert(float_add_src:match("ml_f64_add"))
assert(float_add_src:match("a1 %-") == nil and float_add_src:match("uint64_t") == nil, "float add keeps float arithmetic")
assert(float_add_src:match("a1 %+ a2"), "float add emits direct C addition")

local binary_ops = {
    Core.BinAdd, Core.BinSub, Core.BinMul, Core.BinDiv, Core.BinRem,
    Core.BinBitAnd, Core.BinBitOr, Core.BinBitXor,
    Core.BinShl, Core.BinLShr, Core.BinAShr,
}
for i = 1, #binary_ops do
    local op = binary_ops[i]
    local kind
    if op == Core.BinDiv or op == Core.BinRem then kind = C.CBackendHelperDivRem(op, i64, C.CBackendDivTrapOnZeroOrOverflow)
    elseif op == Core.BinShl or op == Core.BinLShr or op == Core.BinAShr then kind = C.CBackendHelperShift(op, u32, C.CBackendShiftMaskCount)
    else kind = C.CBackendHelperIntBinary(op, u32, C.CBackendIntWrap) end
    local sig = H.helper_signature(kind)
    assert(#sig.params == 2 and sig.result ~= nil)
    local src = table.concat(H.emit_helper(kind), "\n")
    assert(src:match("return") or src:match("abort"), "binary helper emits body")
end
local div_src = table.concat(H.emit_helper(C.CBackendHelperDivRem(Core.BinDiv, i64, C.CBackendDivTrapOnZeroOrOverflow)), "\n")
assert(div_src:match("a2 == 0"), "div/rem traps on zero")
assert(div_src:match("%-1"), "div/rem checks signed min/-1 overflow")
local shift_src = table.concat(H.emit_helper(C.CBackendHelperShift(Core.BinShl, u32, C.CBackendShiftMaskCount)), "\n")
assert(shift_src:match("sizeof%(a1%) %* 8u"), "shift masks count by width")

local unary_src = table.concat(H.emit_helper(C.CBackendHelperUnary(Core.UnaryNeg, i32)), "\n")
assert(unary_src:match("uint32_t"), "unary neg avoids signed overflow with same-width unsigned arithmetic")
local bool_src = table.concat(H.emit_helper(C.CBackendHelperBoolNormalize(i32)), "\n")
assert(bool_src:match("%? 1u : 0u"), "bool normalize emits 0/1")

local cast_ops = {
    Core.MachineCastIdentity, Core.MachineCastBitcast, Core.MachineCastIreduce,
    Core.MachineCastSextend, Core.MachineCastUextend, Core.MachineCastFpromote,
    Core.MachineCastFdemote, Core.MachineCastSToF, Core.MachineCastUToF,
    Core.MachineCastFToS, Core.MachineCastFToU,
}
for i = 1, #cast_ops do
    local kind = C.CBackendHelperCast(cast_ops[i], i32, f64)
    local sig = H.helper_signature(kind)
    assert(#sig.params == 1 and sig.result == f64)
    local src = table.concat(H.emit_helper(kind), "\n")
    if cast_ops[i] == Core.MachineCastBitcast then assert(src:match("memcpy"), "bitcast uses memcpy") else assert(src:match("return")) end
end

local intrinsic_patterns = {
    { Core.IntrinsicPopcount, "while %(x%)" },
    { Core.IntrinsicClz, "for %(int i" },
    { Core.IntrinsicCtz, "for %(unsigned int i" },
    { Core.IntrinsicRotl, "<< s" },
    { Core.IntrinsicRotr, ">> s" },
    { Core.IntrinsicBswap, "y = %(y << 8%)" },
    { Core.IntrinsicFma, "fma" },
    { Core.IntrinsicSqrt, "sqrt" },
    { Core.IntrinsicAbs, "a1 < 0" },
    { Core.IntrinsicFloor, "floor" },
    { Core.IntrinsicCeil, "ceil" },
    { Core.IntrinsicTruncFloat, "trunc" },
    { Core.IntrinsicRound, "round" },
    { Core.IntrinsicTrap, "abort%(%);" },
    { Core.IntrinsicAssume, "if %(!a1%) abort" },
}
for i = 1, #intrinsic_patterns do
    local kind = C.CBackendHelperIntrinsic(intrinsic_patterns[i][1], f64)
    local src = table.concat(H.emit_helper(kind), "\n")
    assert(src:match(intrinsic_patterns[i][2]), "intrinsic helper pattern " .. tostring(i))
end

local access = C.CBackendMemoryAccess(i32, 4, C.CBackendMayTrap, false, nil)
local load_spec = C.CBackendHelperLoad(access)
local load_use = C.CBackendHelperUse(H.helper_id(load_spec), load_spec)
local load_src = table.concat(H.emit_helper(load_use), "\n")
assert(load_src:match("memcpy"), "load helper uses memcpy")
assert(load_src:match("ml_load_i32_a4"))
local store_src = table.concat(H.emit_helper(C.CBackendHelperStore(access)), "\n")
assert(store_src:match("memcpy"), "store helper uses memcpy")
assert(table.concat(H.emit_helper(C.CBackendHelperTypedMemcpy(i32, 4, 4)), "\n"):match("%(size_t%)4"))
assert(table.concat(H.emit_helper(C.CBackendHelperTypedMemset(i32, 4, 4)), "\n"):match("%(size_t%)4"))

local atomic_access = C.CBackendMemoryAccess(i32, 4, C.CBackendMayTrap, false, Core.AtomicSeqCst)
local atomic_helpers = {
    C.CBackendHelperAtomicLoad(atomic_access),
    C.CBackendHelperAtomicStore(atomic_access),
    C.CBackendHelperAtomicRmw(Core.AtomicRmwAdd, atomic_access),
    C.CBackendHelperAtomicCas(atomic_access, Core.AtomicSeqCst, Core.AtomicSeqCst),
    C.CBackendHelperAtomicFence(Core.AtomicSeqCst),
}
for i = 1, #atomic_helpers do
    local src = table.concat(H.emit_helper(atomic_helpers[i]), "\n")
    assert(src:match("atomic_"), "atomic helper emits C11 atomic operation")
end
local atomic_use = C.CBackendHelperUse(H.helper_id(atomic_helpers[1]), atomic_helpers[1])
local unit = C.CBackendUnit("helpers", CodeType.default_target({ dialect = "c11" }), {}, {}, {}, {}, { atomic_use }, {})
assert(Emit.emit_artifact(unit).source:match("#include <stdatomic.h>"), "C11 atomic unit includes stdatomic")

local trap_use = C.CBackendHelperUse(H.helper_id(C.CBackendHelperTrap), C.CBackendHelperTrap)
local trap_src = table.concat(H.emit_helper(trap_use), "\n")
assert(trap_src:match("abort%(%);"), "trap helper aborts")

io.write("lalin c_helpers ok\n")
