package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")

local T = moon.T
local Ty, Sem = T.MoonType, T.MoonSem

local class = moon.classify_type(moon.i32)
assert(class == Ty.TypeClassScalar(T.MoonCore.ScalarI32))

local layout = moon.size_align(moon.ptr(moon.i32))
assert(pvm.classof(layout) == Ty.TypeMemLayoutKnown)
assert(layout.layout.size == 8)
assert(layout.layout.align == 8)

local abi = moon.abi_of(moon.i32)
assert(pvm.classof(abi) == Ty.AbiDecision)
assert(pvm.classof(abi.class) == Ty.AbiDirect)

local M = moon.module("ReflectDemo")
local Pair = M:struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})
local pair_layout = moon.layout_of(Pair)
assert(pvm.classof(pair_layout) == Sem.LayoutNamed)
assert(pair_layout.module_name == "ReflectDemo")
assert(pair_layout.type_name == "Pair")
assert(pair_layout.size == 8)
assert(pair_layout.align == 4)
assert(#pair_layout.fields == 2)
assert(pair_layout.fields[1] == Sem.FieldLayout("x", 0, moon.i32.ty))
assert(pair_layout.fields[2] == Sem.FieldLayout("y", 4, moon.i32.ty))

local env = Sem.LayoutEnv({ pair_layout })
local pair_size = moon.size_align(Pair, env)
assert(pvm.classof(pair_size) == Ty.TypeMemLayoutKnown)
assert(pair_size.layout.size == 8)
local pair_abi = moon.abi_of(Pair, env)
assert(pvm.classof(pair_abi.class) == Ty.AbiIndirect)
assert(pair_abi.class.layout.size == 8)

local unknown = moon.type_param("U")
local unknown_class = moon.classify_type(unknown)
assert(unknown_class == Ty.TypeClassUnknown)
local unknown_layout = moon.size_align(unknown)
assert(pvm.classof(unknown_layout) == Ty.TypeMemLayoutUnknown)
local unknown_abi = moon.abi_of(unknown)
assert(pvm.classof(unknown_abi.class) == Ty.AbiUnknown)

local s = moon.session({ prefix = "reflect" })
local h = s:api()
assert(s:classify_type(h.u64) == h.T.MoonType.TypeClassScalar(h.T.MoonCore.ScalarU64))

print("moonlift host reflection ok")
