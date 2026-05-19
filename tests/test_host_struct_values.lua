package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test struct values using session API and .mlua
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context(); A.Define(T)
local Session = require("moonlift.host_session")
local session = Session.new({ prefix = "struct_test", T = T })
local moon = session:api()
local host_moon = require("moonlift.host")

-- Standalone struct via moon.struct[[]] quote
local Pair = host_moon.struct [[struct Pair x: i32; y: i32 end]]
assert(Pair.name == "Pair")
assert(pvm.classof(Pair.decl) ~= false)  -- is an ASDL node
assert(Pair.decl.name == "Pair")
assert(#Pair.decl.fields == 2)
assert(Pair.decl.fields[1].field_name == "x")
assert(Pair.decl.fields[2].field_name == "y")
print("OK: standalone struct")

-- ptr(struct) type works
local ptr_ty = host_moon.ptr(Pair)
assert(ptr_ty ~= nil)
print("OK: ptr(struct): " .. tostring(ptr_ty))

-- Struct via .mlua
local Host = require("moonlift.mlua_run")
local MPair = Host.eval [[return struct MPair left: i32; right: i32 end]]
assert(MPair.decl.name == "MPair")
assert(#MPair.decl.fields == 2)
assert(MPair.decl.fields[1].field_name == "left")
print("OK: .mlua struct")

print("moonlift host struct values ok")
