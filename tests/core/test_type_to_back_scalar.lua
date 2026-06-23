package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.schema_projection")
local Scalar = require("moonlift.type_to_back_scalar")

local T = pvm.context()
A(T)
local L = Scalar(T)
local C = T.MoonCore
local Ty = T.MoonType
local B = T.MoonBack

local function known(ty, scalar)
    assert(L.result(ty) == Ty.TypeBackScalarKnown(scalar))
end
local function unavailable(ty)
    local result = L.result(ty)
    assert(pvm.classof(result) == Ty.TypeBackScalarUnavailable)
    assert(result.ty == ty)
end

known(Ty.TScalar(C.ScalarBool), B.BackBool)
known(Ty.TScalar(C.ScalarI8), B.BackI8)
known(Ty.TScalar(C.ScalarI16), B.BackI16)
known(Ty.TScalar(C.ScalarI32), B.BackI32)
known(Ty.TScalar(C.ScalarI64), B.BackI64)
known(Ty.TScalar(C.ScalarU8), B.BackU8)
known(Ty.TScalar(C.ScalarU16), B.BackU16)
known(Ty.TScalar(C.ScalarU32), B.BackU32)
known(Ty.TScalar(C.ScalarU64), B.BackU64)
known(Ty.TScalar(C.ScalarF32), B.BackF32)
known(Ty.TScalar(C.ScalarF64), B.BackF64)
known(Ty.TScalar(C.ScalarRawPtr), B.BackPtr)
known(Ty.TScalar(C.ScalarIndex), B.BackIndex)

local i32 = Ty.TScalar(C.ScalarI32)
known(Ty.TPtr(i32), B.BackPtr)
known(Ty.TFunc({ i32 }, i32), B.BackPtr)
unavailable(Ty.TScalar(C.ScalarVoid))
unavailable(Ty.TArray(Ty.ArrayLenConst(2), i32))
unavailable(Ty.TSlice(i32))
unavailable(Ty.TView(i32))
known(Ty.TClosure({ i32 }, i32), B.BackPtr)
unavailable(Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))

print("moonlift type_to_back_scalar ok")
