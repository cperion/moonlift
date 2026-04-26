local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.Moon2Core

    local scalar_family
    local scalar_bits
    local scalar_info

    scalar_family = pvm.phase("moon2_core_scalar_family", {
        [C.ScalarVoid] = function() return pvm.once(C.ScalarFamilyVoid) end,
        [C.ScalarBool] = function() return pvm.once(C.ScalarFamilyBool) end,
        [C.ScalarI8] = function() return pvm.once(C.ScalarFamilySignedInt) end,
        [C.ScalarI16] = function() return pvm.once(C.ScalarFamilySignedInt) end,
        [C.ScalarI32] = function() return pvm.once(C.ScalarFamilySignedInt) end,
        [C.ScalarI64] = function() return pvm.once(C.ScalarFamilySignedInt) end,
        [C.ScalarU8] = function() return pvm.once(C.ScalarFamilyUnsignedInt) end,
        [C.ScalarU16] = function() return pvm.once(C.ScalarFamilyUnsignedInt) end,
        [C.ScalarU32] = function() return pvm.once(C.ScalarFamilyUnsignedInt) end,
        [C.ScalarU64] = function() return pvm.once(C.ScalarFamilyUnsignedInt) end,
        [C.ScalarF32] = function() return pvm.once(C.ScalarFamilyFloat) end,
        [C.ScalarF64] = function() return pvm.once(C.ScalarFamilyFloat) end,
        [C.ScalarRawPtr] = function() return pvm.once(C.ScalarFamilyRawPtr) end,
        [C.ScalarIndex] = function() return pvm.once(C.ScalarFamilyIndex) end,
    })

    scalar_bits = pvm.phase("moon2_core_scalar_bits", {
        [C.ScalarVoid] = function() return pvm.once(C.ScalarBits(0)) end,
        [C.ScalarBool] = function() return pvm.once(C.ScalarBits(1)) end,
        [C.ScalarI8] = function() return pvm.once(C.ScalarBits(8)) end,
        [C.ScalarU8] = function() return pvm.once(C.ScalarBits(8)) end,
        [C.ScalarI16] = function() return pvm.once(C.ScalarBits(16)) end,
        [C.ScalarU16] = function() return pvm.once(C.ScalarBits(16)) end,
        [C.ScalarI32] = function() return pvm.once(C.ScalarBits(32)) end,
        [C.ScalarU32] = function() return pvm.once(C.ScalarBits(32)) end,
        [C.ScalarF32] = function() return pvm.once(C.ScalarBits(32)) end,
        [C.ScalarI64] = function() return pvm.once(C.ScalarBits(64)) end,
        [C.ScalarU64] = function() return pvm.once(C.ScalarBits(64)) end,
        [C.ScalarF64] = function() return pvm.once(C.ScalarBits(64)) end,
        [C.ScalarRawPtr] = function() return pvm.once(C.ScalarBits(64)) end,
        [C.ScalarIndex] = function() return pvm.once(C.ScalarBits(64)) end,
    })

    scalar_info = pvm.phase("moon2_core_scalar_info", function(scalar)
        return C.ScalarInfo(pvm.one(scalar_family(scalar)), pvm.one(scalar_bits(scalar)))
    end)

    return {
        scalar_family = scalar_family,
        scalar_bits = scalar_bits,
        scalar_info = scalar_info,
        family = function(scalar) return pvm.one(scalar_family(scalar)) end,
        bits = function(scalar) return pvm.one(scalar_bits(scalar)) end,
        info = function(scalar) return pvm.one(scalar_info(scalar)) end,
    }
end

return M
