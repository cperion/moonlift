package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test struct values using .mlua eval
local Host = require("moonlift.mlua_run")

local Pair = Host.eval [[return struct Pair x: i32; y: i32 end]]
assert(Pair.kind == "type")
assert(Pair.decl.name == "Pair")
assert(Pair.source_hint == "Pair")
assert(#Pair.decl.fields == 2)
assert(Pair.decl.fields[1].field_name == "x")
assert(Pair.decl.fields[2].field_name == "y")
print("OK: struct fields correct")

-- Nested struct
local Outer = Host.eval [[
local Inner = struct Inner v: i32 end
return struct Outer inner: Inner end
]]
assert(Outer.decl.name == "Outer")
assert(#Outer.decl.fields == 1)
print("OK: nested struct")

print("moonlift host struct draft values ok")
