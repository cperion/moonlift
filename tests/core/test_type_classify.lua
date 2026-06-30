package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A = require("lalin.schema_projection")
local Classify = require("lalin.type_classify")

local T = asdl.context()
A(T)
local L = Classify(T)
local C = T.LalinCore
local Ty = T.LalinType

local i32 = Ty.TScalar(C.ScalarI32)
assert(L.classify(i32) == Ty.TypeShapeScalar(C.ScalarI32))
assert(L.classify(Ty.TPtr(i32)) == Ty.TypeShapePointer(i32))
assert(L.classify(Ty.TArray(Ty.ArrayLenConst(4), i32)) == Ty.TypeShapeArray(i32, 4))
assert(L.classify(Ty.TSlice(i32)) == Ty.TypeShapeSlice(i32))
assert(L.classify(Ty.TView(i32)) == Ty.TypeShapeView(i32))
assert(L.classify(Ty.TFunc({ i32 }, i32)) == Ty.TypeShapeCallable({ i32 }, i32))
assert(L.classify(Ty.TClosure({ i32 }, i32)) == Ty.TypeShapeClosure({ i32 }, i32))
assert(L.classify(Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))) == Ty.TypeShapeAggregate("Demo", "Pair"))
assert(L.classify(Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name("Pair") })))) == Ty.TypeShapeUnknown)

print("lalin type_classify ok")
