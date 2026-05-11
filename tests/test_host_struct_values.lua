package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test struct values using session API and .mlua
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context(); A.Define(T)
local Session = require("moonlift.host_session")
local session = Session.new({ prefix = "struct_test", T = T })
local moon = session:api()
local Tr = T.MoonTree

-- Standalone struct via builder API
local Pair = moon.struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})
assert(Pair.name == "Pair")
assert(pvm.classof(Pair.decl) == Tr.TypeDeclStruct)
assert(Pair.decl.name == "Pair")
assert(#Pair.decl.fields == 2)
assert(Pair.decl.fields[1].field_name == "x")
assert(Pair.decl.fields[2].field_name == "y")
print("OK: standalone struct")

-- ptr(struct) type works
assert(moon.ptr(Pair).ty == T.MoonType.TPtr(Pair:as_moonlift_type()))
print("OK: ptr(struct)")

-- Struct via .mlua
local Host = require("moonlift.mlua_run")
local MPair = Host.eval [[return struct MPair left: i32; right: i32 end]]
assert(MPair.decl.name == "MPair")
assert(#MPair.decl.fields == 2)
assert(MPair.decl.fields[1].field_name == "left")
print("OK: .mlua struct")

print("moonlift host struct values ok")
