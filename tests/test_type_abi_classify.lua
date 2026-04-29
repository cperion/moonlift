package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Abi = require("moonlift.type_abi_classify")

local T = pvm.context()
A.Define(T)
local L = Abi.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local B = T.Moon2Back
local Sem = T.Moon2Sem
local O = T.Moon2Open

local i32 = Ty.TScalar(C.ScalarI32)
local void = Ty.TScalar(C.ScalarVoid)
local ptr = Ty.TPtr(i32)
local slice = Ty.TSlice(i32)
local view = Ty.TView(i32)
local closure = Ty.TClosure({ i32 }, i32)
local array = Ty.TArray(Ty.ArrayLenConst(4), i32)
local pair = Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))
local env = Sem.LayoutEnv({
    Sem.LayoutNamed("Demo", "Pair", {
        Sem.FieldLayout("left", 0, i32),
        Sem.FieldLayout("right", 4, i32),
    }, 8, 4),
})

assert(L.decide(i32) == Ty.AbiDecision(i32, Ty.AbiDirect(B.BackI32)))
assert(L.decide(void) == Ty.AbiDecision(void, Ty.AbiIgnore))
assert(L.decide(ptr) == Ty.AbiDecision(ptr, Ty.AbiDirect(B.BackPtr)))
assert(L.decide(Ty.TFunc({ i32 }, i32)) == Ty.AbiDecision(Ty.TFunc({ i32 }, i32), Ty.AbiDirect(B.BackPtr)))
assert(L.decide(slice) == Ty.AbiDecision(slice, Ty.AbiDescriptor(Sem.MemLayout(16, 8))))
assert(L.decide(view) == Ty.AbiDecision(view, Ty.AbiDescriptor(Sem.MemLayout(24, 8))))
assert(L.decide(closure) == Ty.AbiDecision(closure, Ty.AbiDescriptor(Sem.MemLayout(16, 8))))
assert(L.decide(array) == Ty.AbiDecision(array, Ty.AbiIndirect(Sem.MemLayout(16, 4))))
assert(L.decide(pair, env) == Ty.AbiDecision(pair, Ty.AbiIndirect(Sem.MemLayout(8, 4))))

local unknown = Ty.TSlot(O.TypeSlot("T", "T"))
local decision = L.decide(unknown)
assert(decision.ty == unknown)
assert(pvm.classof(decision.class) == Ty.AbiUnknown)

print("moonlift type_abi_classify ok")
