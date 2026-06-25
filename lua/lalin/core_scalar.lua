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

    local scalar_family
    local scalar_bits
    local scalar_info

    function scalar_family(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.ScalarVoid) then
            return (function()
 return single(C.ScalarFamilyVoid)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarBool) then
            return (function()
 return single(C.ScalarFamilyBool)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI8) then
            return (function()
 return single(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI16) then
            return (function()
 return single(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI32) then
            return (function()
 return single(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI64) then
            return (function()
 return single(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU8) then
            return (function()
 return single(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU16) then
            return (function()
 return single(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU32) then
            return (function()
 return single(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU64) then
            return (function()
 return single(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF32) then
            return (function()
 return single(C.ScalarFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF64) then
            return (function()
 return single(C.ScalarFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarRawPtr) then
            return (function()
 return single(C.ScalarFamilyRawPtr)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarIndex) then
            return (function()
 return single(C.ScalarFamilyIndex)
            end)(node, ...)
        else
            error("phase lalin_core_scalar_family: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function scalar_bits(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.ScalarVoid) then
            return (function()
 return single(C.ScalarBits(0))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarBool) then
            return (function()
 return single(C.ScalarBits(1))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI8) then
            return (function()
 return single(C.ScalarBits(8))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU8) then
            return (function()
 return single(C.ScalarBits(8))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI16) then
            return (function()
 return single(C.ScalarBits(16))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU16) then
            return (function()
 return single(C.ScalarBits(16))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI32) then
            return (function()
 return single(C.ScalarBits(32))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU32) then
            return (function()
 return single(C.ScalarBits(32))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF32) then
            return (function()
 return single(C.ScalarBits(32))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI64) then
            return (function()
 return single(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU64) then
            return (function()
 return single(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF64) then
            return (function()
 return single(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarRawPtr) then
            return (function()
 return single(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarIndex) then
            return (function()
 return single(C.ScalarBits(64))
            end)(node, ...)
        else
            error("phase lalin_core_scalar_bits: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function scalar_info(scalar)
        return C.ScalarInfo(only(scalar_family(scalar)), only(scalar_bits(scalar)))
    end

    return {
        scalar_family = scalar_family,
        scalar_bits = scalar_bits,
        scalar_info = scalar_info,
        family = function(scalar) return only(scalar_family(scalar)) end,
        bits = function(scalar) return only(scalar_bits(scalar)) end,
        info = function(scalar) return scalar_info(scalar) end,
    }
end

return bind_context