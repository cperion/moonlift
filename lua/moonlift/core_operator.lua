local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.Moon2Core

    local unary_class
    local binary_class
    local cmp_class
    local intrinsic_class

    unary_class = pvm.phase("moon2_core_unary_op_class", {
        [C.UnaryNeg] = function() return pvm.once(C.UnaryClassArithmetic) end,
        [C.UnaryNot] = function() return pvm.once(C.UnaryClassLogical) end,
        [C.UnaryBitNot] = function() return pvm.once(C.UnaryClassBitwise) end,
    })

    binary_class = pvm.phase("moon2_core_binary_op_class", {
        [C.BinAdd] = function() return pvm.once(C.BinaryClassArithmetic) end,
        [C.BinSub] = function() return pvm.once(C.BinaryClassArithmetic) end,
        [C.BinMul] = function() return pvm.once(C.BinaryClassArithmetic) end,
        [C.BinDiv] = function() return pvm.once(C.BinaryClassDivision) end,
        [C.BinRem] = function() return pvm.once(C.BinaryClassRemainder) end,
        [C.BinBitAnd] = function() return pvm.once(C.BinaryClassBitwise) end,
        [C.BinBitOr] = function() return pvm.once(C.BinaryClassBitwise) end,
        [C.BinBitXor] = function() return pvm.once(C.BinaryClassBitwise) end,
        [C.BinShl] = function() return pvm.once(C.BinaryClassShift) end,
        [C.BinLShr] = function() return pvm.once(C.BinaryClassShift) end,
        [C.BinAShr] = function() return pvm.once(C.BinaryClassShift) end,
    })

    cmp_class = pvm.phase("moon2_core_cmp_op_class", {
        [C.CmpEq] = function() return pvm.once(C.CmpClassEquality) end,
        [C.CmpNe] = function() return pvm.once(C.CmpClassEquality) end,
        [C.CmpLt] = function() return pvm.once(C.CmpClassOrdering) end,
        [C.CmpLe] = function() return pvm.once(C.CmpClassOrdering) end,
        [C.CmpGt] = function() return pvm.once(C.CmpClassOrdering) end,
        [C.CmpGe] = function() return pvm.once(C.CmpClassOrdering) end,
    })

    intrinsic_class = pvm.phase("moon2_core_intrinsic_class", {
        [C.IntrinsicPopcount] = function() return pvm.once(C.IntrinsicClassBit) end,
        [C.IntrinsicClz] = function() return pvm.once(C.IntrinsicClassBit) end,
        [C.IntrinsicCtz] = function() return pvm.once(C.IntrinsicClassBit) end,
        [C.IntrinsicRotl] = function() return pvm.once(C.IntrinsicClassBit) end,
        [C.IntrinsicRotr] = function() return pvm.once(C.IntrinsicClassBit) end,
        [C.IntrinsicBswap] = function() return pvm.once(C.IntrinsicClassBit) end,
        [C.IntrinsicFma] = function() return pvm.once(C.IntrinsicClassFused) end,
        [C.IntrinsicSqrt] = function() return pvm.once(C.IntrinsicClassFloat) end,
        [C.IntrinsicAbs] = function() return pvm.once(C.IntrinsicClassFloat) end,
        [C.IntrinsicFloor] = function() return pvm.once(C.IntrinsicClassFloat) end,
        [C.IntrinsicCeil] = function() return pvm.once(C.IntrinsicClassFloat) end,
        [C.IntrinsicTruncFloat] = function() return pvm.once(C.IntrinsicClassFloat) end,
        [C.IntrinsicRound] = function() return pvm.once(C.IntrinsicClassFloat) end,
        [C.IntrinsicTrap] = function() return pvm.once(C.IntrinsicClassControl) end,
        [C.IntrinsicAssume] = function() return pvm.once(C.IntrinsicClassControl) end,
    })

    return {
        unary_class = unary_class,
        binary_class = binary_class,
        cmp_class = cmp_class,
        intrinsic_class = intrinsic_class,
        unary = function(op) return pvm.one(unary_class(op)) end,
        binary = function(op) return pvm.one(binary_class(op)) end,
        cmp = function(op) return pvm.one(cmp_class(op)) end,
        intrinsic = function(op) return pvm.one(intrinsic_class(op)) end,
    }
end

return M
