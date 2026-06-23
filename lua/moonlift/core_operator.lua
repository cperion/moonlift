local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local C = T.MoonCore

    local unary_class
    local binary_class
    local cmp_class
    local intrinsic_class

    function unary_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.UnaryNeg) then
            return (function()
 return erased.once(C.UnaryClassArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.UnaryNot) then
            return (function()
 return erased.once(C.UnaryClassLogical)
            end)(node, ...)
        elseif schema.isa(node, C.UnaryBitNot) then
            return (function()
 return erased.once(C.UnaryClassBitwise)
            end)(node, ...)
        else
            error("erased phase moonlift_core_unary_op_class: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function binary_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.BinAdd) then
            return (function()
 return erased.once(C.BinaryClassArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.BinSub) then
            return (function()
 return erased.once(C.BinaryClassArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.BinMul) then
            return (function()
 return erased.once(C.BinaryClassArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.BinDiv) then
            return (function()
 return erased.once(C.BinaryClassDivision)
            end)(node, ...)
        elseif schema.isa(node, C.BinRem) then
            return (function()
 return erased.once(C.BinaryClassRemainder)
            end)(node, ...)
        elseif schema.isa(node, C.BinBitAnd) then
            return (function()
 return erased.once(C.BinaryClassBitwise)
            end)(node, ...)
        elseif schema.isa(node, C.BinBitOr) then
            return (function()
 return erased.once(C.BinaryClassBitwise)
            end)(node, ...)
        elseif schema.isa(node, C.BinBitXor) then
            return (function()
 return erased.once(C.BinaryClassBitwise)
            end)(node, ...)
        elseif schema.isa(node, C.BinShl) then
            return (function()
 return erased.once(C.BinaryClassShift)
            end)(node, ...)
        elseif schema.isa(node, C.BinLShr) then
            return (function()
 return erased.once(C.BinaryClassShift)
            end)(node, ...)
        elseif schema.isa(node, C.BinAShr) then
            return (function()
 return erased.once(C.BinaryClassShift)
            end)(node, ...)
        else
            error("erased phase moonlift_core_binary_op_class: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function cmp_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.CmpEq) then
            return (function()
 return erased.once(C.CmpClassEquality)
            end)(node, ...)
        elseif schema.isa(node, C.CmpNe) then
            return (function()
 return erased.once(C.CmpClassEquality)
            end)(node, ...)
        elseif schema.isa(node, C.CmpLt) then
            return (function()
 return erased.once(C.CmpClassOrdering)
            end)(node, ...)
        elseif schema.isa(node, C.CmpLe) then
            return (function()
 return erased.once(C.CmpClassOrdering)
            end)(node, ...)
        elseif schema.isa(node, C.CmpGt) then
            return (function()
 return erased.once(C.CmpClassOrdering)
            end)(node, ...)
        elseif schema.isa(node, C.CmpGe) then
            return (function()
 return erased.once(C.CmpClassOrdering)
            end)(node, ...)
        else
            error("erased phase moonlift_core_cmp_op_class: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function intrinsic_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.IntrinsicPopcount) then
            return (function()
 return erased.once(C.IntrinsicClassBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicClz) then
            return (function()
 return erased.once(C.IntrinsicClassBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicCtz) then
            return (function()
 return erased.once(C.IntrinsicClassBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicRotl) then
            return (function()
 return erased.once(C.IntrinsicClassBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicRotr) then
            return (function()
 return erased.once(C.IntrinsicClassBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicBswap) then
            return (function()
 return erased.once(C.IntrinsicClassBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicFma) then
            return (function()
 return erased.once(C.IntrinsicClassFused)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicSqrt) then
            return (function()
 return erased.once(C.IntrinsicClassFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicAbs) then
            return (function()
 return erased.once(C.IntrinsicClassFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicFloor) then
            return (function()
 return erased.once(C.IntrinsicClassFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicCeil) then
            return (function()
 return erased.once(C.IntrinsicClassFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicTruncFloat) then
            return (function()
 return erased.once(C.IntrinsicClassFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicRound) then
            return (function()
 return erased.once(C.IntrinsicClassFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicTrap) then
            return (function()
 return erased.once(C.IntrinsicClassControl)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicAssume) then
            return (function()
 return erased.once(C.IntrinsicClassControl)
            end)(node, ...)
        else
            error("erased phase moonlift_core_intrinsic_class: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        unary_class = unary_class,
        binary_class = binary_class,
        cmp_class = cmp_class,
        intrinsic_class = intrinsic_class,
        unary = function(op) return erased.one(unary_class(op)) end,
        binary = function(op) return erased.one(binary_class(op)) end,
        cmp = function(op) return erased.one(cmp_class(op)) end,
        intrinsic = function(op) return erased.one(intrinsic_class(op)) end,
    }
end

return M
