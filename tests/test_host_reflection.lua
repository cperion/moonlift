package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test reflection API via session
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context(); A.Define(T)
local Session = require("moonlift.host_session")
local session = Session.new({ prefix = "reflect", T = T })
local moon = session:api()
local Ty = T.MoonType

-- Type classification via session method
local class = session:classify_type(moon.i32)
assert(pvm.classof(class) == Ty.TypeClassScalar)
assert(class == Ty.TypeClassScalar(T.MoonCore.ScalarI32))
print("OK: classify_type")

-- Size/align via session method
local layout = session:size_align(moon.ptr(moon.i32))
assert(pvm.classof(layout) == Ty.TypeMemLayoutKnown)
assert(layout.layout.size == 8)
assert(layout.layout.align == 8)
print("OK: size_align")

-- ABI via session method
local abi = session:abi_of(moon.i32)
assert(pvm.classof(abi) == Ty.AbiDecision)
assert(pvm.classof(abi.class) == Ty.AbiDirect)
print("OK: abi_of")

-- Struct via session API
local Pair = moon.struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})
assert(Pair.name == "Pair")
assert(pvm.classof(Pair.decl) == T.MoonTree.TypeDeclStruct)
print("OK: struct creation")

-- Layout via session method
local pair_layout = session:layout_of(Pair)
assert(pvm.classof(pair_layout) == T.MoonSem.LayoutNamed)
assert(pair_layout.size == 8)
print("OK: layout_of")

-- ptr(T)
assert(moon.ptr(moon.i32).ty == Ty.TPtr(moon.i32.ty))
print("OK: ptr type")

print("moonlift host reflection ok")
