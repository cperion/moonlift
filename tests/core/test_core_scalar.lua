package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local A = require("lalin.schema_projection")
local CoreScalar = require("lalin.core_scalar")

local T = pvm.context()
A(T)
local L = CoreScalar(T)
local C = T.LalinCore

local function expect(scalar, family, bits)
    assert(L.family(scalar) == family)
    assert(L.bits(scalar) == C.ScalarBits(bits))
    assert(L.info(scalar) == C.ScalarInfo(family, C.ScalarBits(bits)))
end

expect(C.ScalarVoid, C.ScalarFamilyVoid, 0)
expect(C.ScalarBool, C.ScalarFamilyBool, 1)
expect(C.ScalarI8, C.ScalarFamilySignedInt, 8)
expect(C.ScalarI16, C.ScalarFamilySignedInt, 16)
expect(C.ScalarI32, C.ScalarFamilySignedInt, 32)
expect(C.ScalarI64, C.ScalarFamilySignedInt, 64)
expect(C.ScalarU8, C.ScalarFamilyUnsignedInt, 8)
expect(C.ScalarU16, C.ScalarFamilyUnsignedInt, 16)
expect(C.ScalarU32, C.ScalarFamilyUnsignedInt, 32)
expect(C.ScalarU64, C.ScalarFamilyUnsignedInt, 64)
expect(C.ScalarF32, C.ScalarFamilyFloat, 32)
expect(C.ScalarF64, C.ScalarFamilyFloat, 64)
expect(C.ScalarRawPtr, C.ScalarFamilyRawPtr, 64)
expect(C.ScalarIndex, C.ScalarFamilyIndex, 64)

print("lalin core_scalar ok")
