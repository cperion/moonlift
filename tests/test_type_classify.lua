package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Classify = require("moonlift.type_classify")

local T = pvm.context()
A.Define(T)
local L = Classify.Define(T)
local C = T.MoonCore
local Ty = T.MoonType
local O = T.MoonOpen

local i32 = Ty.TScalar(C.ScalarI32)
assert(L.classify(i32) == Ty.TypeClassScalar(C.ScalarI32))
assert(L.classify(Ty.TPtr(i32)) == Ty.TypeClassPointer(i32))
assert(L.classify(Ty.TArray(Ty.ArrayLenConst(4), i32)) == Ty.TypeClassArray(i32, 4))
assert(L.classify(Ty.TArray(Ty.ArrayLenSlot(O.ExprSlot("n", "n", i32)), i32)) == Ty.TypeClassUnknown)
assert(L.classify(Ty.TSlice(i32)) == Ty.TypeClassSlice(i32))
assert(L.classify(Ty.TView(i32)) == Ty.TypeClassView(i32))
assert(L.classify(Ty.TFunc({ i32 }, i32)) == Ty.TypeClassCallable({ i32 }, i32))
assert(L.classify(Ty.TClosure({ i32 }, i32)) == Ty.TypeClassClosure({ i32 }, i32))
assert(L.classify(Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))) == Ty.TypeClassAggregate("Demo", "Pair"))
assert(L.classify(Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name("Pair") })))) == Ty.TypeClassUnknown)
assert(L.classify(Ty.TSlot(O.TypeSlot("T", "T"))) == Ty.TypeClassUnknown)

print("moonlift type_classify ok")
