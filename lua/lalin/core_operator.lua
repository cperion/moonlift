local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    local C = T.LalinCore

    local unary_class
    local binary_class
    local cmp_class
    local intrinsic_class

    function unary_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.UnaryNeg) then
            return (function()
 return single(C.UnaryFamilyArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.UnaryNot) then
            return (function()
 return single(C.UnaryFamilyLogical)
            end)(node, ...)
        elseif schema.isa(node, C.UnaryBitNot) then
            return (function()
 return single(C.UnaryFamilyBitwise)
            end)(node, ...)
        else
            error("phase lalin_core_unary_op_class: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function binary_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.BinAdd) then
            return (function()
 return single(C.BinaryFamilyArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.BinSub) then
            return (function()
 return single(C.BinaryFamilyArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.BinMul) then
            return (function()
 return single(C.BinaryFamilyArithmetic)
            end)(node, ...)
        elseif schema.isa(node, C.BinDiv) then
            return (function()
 return single(C.BinaryFamilyDivision)
            end)(node, ...)
        elseif schema.isa(node, C.BinRem) then
            return (function()
 return single(C.BinaryFamilyRemainder)
            end)(node, ...)
        elseif schema.isa(node, C.BinBitAnd) then
            return (function()
 return single(C.BinaryFamilyBitwise)
            end)(node, ...)
        elseif schema.isa(node, C.BinBitOr) then
            return (function()
 return single(C.BinaryFamilyBitwise)
            end)(node, ...)
        elseif schema.isa(node, C.BinBitXor) then
            return (function()
 return single(C.BinaryFamilyBitwise)
            end)(node, ...)
        elseif schema.isa(node, C.BinShl) then
            return (function()
 return single(C.BinaryFamilyShift)
            end)(node, ...)
        elseif schema.isa(node, C.BinLShr) then
            return (function()
 return single(C.BinaryFamilyShift)
            end)(node, ...)
        elseif schema.isa(node, C.BinAShr) then
            return (function()
 return single(C.BinaryFamilyShift)
            end)(node, ...)
        else
            error("phase lalin_core_binary_op_class: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function cmp_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.CmpEq) then
            return (function()
 return single(C.CmpFamilyEquality)
            end)(node, ...)
        elseif schema.isa(node, C.CmpNe) then
            return (function()
 return single(C.CmpFamilyEquality)
            end)(node, ...)
        elseif schema.isa(node, C.CmpLt) then
            return (function()
 return single(C.CmpFamilyOrdering)
            end)(node, ...)
        elseif schema.isa(node, C.CmpLe) then
            return (function()
 return single(C.CmpFamilyOrdering)
            end)(node, ...)
        elseif schema.isa(node, C.CmpGt) then
            return (function()
 return single(C.CmpFamilyOrdering)
            end)(node, ...)
        elseif schema.isa(node, C.CmpGe) then
            return (function()
 return single(C.CmpFamilyOrdering)
            end)(node, ...)
        else
            error("phase lalin_core_cmp_op_class: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function intrinsic_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.IntrinsicPopcount) then
            return (function()
 return single(C.IntrinsicFamilyBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicClz) then
            return (function()
 return single(C.IntrinsicFamilyBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicCtz) then
            return (function()
 return single(C.IntrinsicFamilyBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicRotl) then
            return (function()
 return single(C.IntrinsicFamilyBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicRotr) then
            return (function()
 return single(C.IntrinsicFamilyBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicBswap) then
            return (function()
 return single(C.IntrinsicFamilyBit)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicFma) then
            return (function()
 return single(C.IntrinsicFamilyFused)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicSqrt) then
            return (function()
 return single(C.IntrinsicFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicAbs) then
            return (function()
 return single(C.IntrinsicFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicFloor) then
            return (function()
 return single(C.IntrinsicFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicCeil) then
            return (function()
 return single(C.IntrinsicFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicTruncFloat) then
            return (function()
 return single(C.IntrinsicFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicRound) then
            return (function()
 return single(C.IntrinsicFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicTrap) then
            return (function()
 return single(C.IntrinsicFamilyControl)
            end)(node, ...)
        elseif schema.isa(node, C.IntrinsicAssume) then
            return (function()
 return single(C.IntrinsicFamilyControl)
            end)(node, ...)
        else
            error("phase lalin_core_intrinsic_class: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        unary_class = unary_class,
        binary_class = binary_class,
        cmp_class = cmp_class,
        intrinsic_class = intrinsic_class,
        unary = function(op) return only(unary_class(op)) end,
        binary = function(op) return only(binary_class(op)) end,
        cmp = function(op) return only(cmp_class(op)) end,
        intrinsic = function(op) return only(intrinsic_class(op)) end,
    }
end

return bind_context