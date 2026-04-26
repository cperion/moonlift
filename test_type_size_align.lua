package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Size = require("moonlift.type_size_align")

local T = pvm.context()
A.Define(T)
local L = Size.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local Sem = T.Moon2Sem
local O = T.Moon2Open

local function known(ty, size, align, env)
    local result = L.result(ty, env)
    assert(result == Ty.TypeMemLayoutKnown(Sem.MemLayout(size, align)))
end
local function unknown(ty, env)
    local result = L.result(ty, env)
    assert(pvm.classof(result) == Ty.TypeMemLayoutUnknown)
    assert(result.ty == ty)
end

known(Ty.TScalar(C.ScalarVoid), 0, 1)
known(Ty.TScalar(C.ScalarBool), 1, 1)
known(Ty.TScalar(C.ScalarI8), 1, 1)
known(Ty.TScalar(C.ScalarU8), 1, 1)
known(Ty.TScalar(C.ScalarI16), 2, 2)
known(Ty.TScalar(C.ScalarU16), 2, 2)
known(Ty.TScalar(C.ScalarI32), 4, 4)
known(Ty.TScalar(C.ScalarU32), 4, 4)
known(Ty.TScalar(C.ScalarF32), 4, 4)
known(Ty.TScalar(C.ScalarI64), 8, 8)
known(Ty.TScalar(C.ScalarU64), 8, 8)
known(Ty.TScalar(C.ScalarF64), 8, 8)
known(Ty.TScalar(C.ScalarRawPtr), 8, 8)
known(Ty.TScalar(C.ScalarIndex), 8, 8)

local i32 = Ty.TScalar(C.ScalarI32)
known(Ty.TPtr(i32), 8, 8)
known(Ty.TFunc({ i32 }, i32), 8, 8)
known(Ty.TSlice(i32), 16, 8)
known(Ty.TView(i32), 24, 8)
known(Ty.TClosure({ i32 }, i32), 16, 8)
known(Ty.TArray(Ty.ArrayLenConst(3), i32), 12, 4)
known(Ty.TArray(Ty.ArrayLenConst(2), Ty.TScalar(C.ScalarI64)), 16, 8)

local pair_env = Sem.LayoutEnv({
    Sem.LayoutNamed("Demo", "Pair", {
        Sem.FieldLayout("left", 0, i32),
        Sem.FieldLayout("right", 4, i32),
    }, 8, 4),
})
known(Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")), 8, 4, pair_env)
unknown(Ty.TNamed(Ty.TypeRefGlobal("Demo", "Missing")), pair_env)
unknown(Ty.TArray(Ty.ArrayLenSlot(O.ExprSlot("n", "n", i32)), i32))
unknown(Ty.TSlot(O.TypeSlot("T", "T")))

print("moonlift type_size_align ok")
