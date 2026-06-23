local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local C = T.MoonCore

    local scalar_family
    local scalar_bits
    local scalar_info

    function scalar_family(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.ScalarVoid) then
            return (function()
 return erased.once(C.ScalarFamilyVoid)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarBool) then
            return (function()
 return erased.once(C.ScalarFamilyBool)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI8) then
            return (function()
 return erased.once(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI16) then
            return (function()
 return erased.once(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI32) then
            return (function()
 return erased.once(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI64) then
            return (function()
 return erased.once(C.ScalarFamilySignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU8) then
            return (function()
 return erased.once(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU16) then
            return (function()
 return erased.once(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU32) then
            return (function()
 return erased.once(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU64) then
            return (function()
 return erased.once(C.ScalarFamilyUnsignedInt)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF32) then
            return (function()
 return erased.once(C.ScalarFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF64) then
            return (function()
 return erased.once(C.ScalarFamilyFloat)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarRawPtr) then
            return (function()
 return erased.once(C.ScalarFamilyRawPtr)
            end)(node, ...)
        elseif schema.isa(node, C.ScalarIndex) then
            return (function()
 return erased.once(C.ScalarFamilyIndex)
            end)(node, ...)
        else
            error("erased phase moonlift_core_scalar_family: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function scalar_bits(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.ScalarVoid) then
            return (function()
 return erased.once(C.ScalarBits(0))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarBool) then
            return (function()
 return erased.once(C.ScalarBits(1))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI8) then
            return (function()
 return erased.once(C.ScalarBits(8))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU8) then
            return (function()
 return erased.once(C.ScalarBits(8))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI16) then
            return (function()
 return erased.once(C.ScalarBits(16))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU16) then
            return (function()
 return erased.once(C.ScalarBits(16))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI32) then
            return (function()
 return erased.once(C.ScalarBits(32))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU32) then
            return (function()
 return erased.once(C.ScalarBits(32))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF32) then
            return (function()
 return erased.once(C.ScalarBits(32))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarI64) then
            return (function()
 return erased.once(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarU64) then
            return (function()
 return erased.once(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarF64) then
            return (function()
 return erased.once(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarRawPtr) then
            return (function()
 return erased.once(C.ScalarBits(64))
            end)(node, ...)
        elseif schema.isa(node, C.ScalarIndex) then
            return (function()
 return erased.once(C.ScalarBits(64))
            end)(node, ...)
        else
            error("erased phase moonlift_core_scalar_bits: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function scalar_info(scalar)
        return C.ScalarInfo(erased.one(scalar_family(scalar)), erased.one(scalar_bits(scalar)))
    end

    return {
        scalar_family = scalar_family,
        scalar_bits = scalar_bits,
        scalar_info = scalar_info,
        family = function(scalar) return erased.one(scalar_family(scalar)) end,
        bits = function(scalar) return erased.one(scalar_bits(scalar)) end,
        info = function(scalar) return scalar_info(scalar) end,
    }
end

return M
