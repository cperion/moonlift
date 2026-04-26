package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")

local T = moon.T
local Ty, Tr = T.Moon2Type, T.Moon2Tree

local fx = moon.field("x", moon.i32)
assert(fx.decl == Ty.FieldDecl("x", moon.i32.ty))

local Pair = moon.struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})
assert(Pair.name == "Pair")
assert(pvm.classof(Pair.decl) == Tr.TypeDeclStruct)
assert(Pair.decl.name == "Pair")
assert(#Pair.decl.fields == 2)
assert(Pair.fields_by_name.x == moon.i32)
assert(moon.ptr(Pair).ty == Ty.TPtr(Pair:as_moon2_type()))

local M = moon.module("Demo")
local MPair = M:struct("Pair", {
    moon.field("left", moon.i32),
    moon.field("right", moon.i32),
})
assert(MPair.owner_module == M)
assert(MPair.type.ty == Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))

local Bits = M:union("Bits", { moon.field("i", moon.i32), moon.field("f", moon.f32) })
assert(pvm.classof(Bits.decl) == Tr.TypeDeclUnion)

local Color = M:enum("Color", { "red", "green", "blue" })
assert(pvm.classof(Color.decl) == Tr.TypeDeclEnumSugar)
assert(#Color.decl.variants == 3)

local Result = M:tagged_union("Result", { moon.variant("ok", moon.i32), moon.variant("err", moon.i32) })
assert(pvm.classof(Result.decl) == Tr.TypeDeclTaggedUnionSugar)

local module = M:to_asdl()
assert(pvm.classof(module.h) == Tr.ModuleTyped)
assert(module.h.module_name == "Demo")
assert(#module.items == 4)
assert(pvm.classof(module.items[1]) == Tr.ItemType)

local ok, err = pcall(function()
    moon.struct("Bad", { moon.field("x", moon.i32), moon.field("x", moon.i64) })
end)
assert(not ok and tostring(err):match("duplicate field"))

print("moonlift host struct values ok")
